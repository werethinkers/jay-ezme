// My Files > Finder: browse, drag, copy, move, rename and tidy any folder on this Mac without leaving KeyDo.
// Works on real files and folders (Desktop, Documents, Downloads, other drives). Nothing is hidden: Trash keeps files recoverable.
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing
import QuickLookUI

struct FinderEntry: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    let name: String
    let isFolder: Bool
    let size: Int64
    let modified: Date?
    let kind: String
}

@MainActor
final class FinderModel: ObservableObject {
    static let pinnedKey = "keydoFinderPinnedFolders"
    static let lastKey = "keydoFinderLastFolder"

    @Published var current: URL
    @Published var entries: [FinderEntry] = []
    @Published var selection: Set<URL> = []
    @Published var query = ""
    @Published var showHidden = false
    @Published var sortKey = "Name"
    @Published var ascending = true
    @Published var iconView: Bool = UserDefaults.standard.object(forKey: "keydoFinderIconView") as? Bool ?? true { didSet { UserDefaults.standard.set(iconView, forKey: "keydoFinderIconView") } }
    @Published var message = ""
    @Published var pinned: [URL] = []
    @Published var loading = false
    @Published var canPaste = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var iconSize: Double = {
        let saved = UserDefaults.standard.double(forKey: "keydoFinderIconSize")
        return saved >= 64 ? saved : 112
    }() { didSet { UserDefaults.standard.set(iconSize, forKey: "keydoFinderIconSize") } }
    static let hiddenKey = "keydoFinderHiddenPaths"
    /// Files and folders the person hid. They stay exactly where they are; KeyDo just does not show them until the passcode is entered.
    @Published var hiddenPaths: Set<String> = Set(UserDefaults.standard.stringArray(forKey: FinderModel.hiddenKey) ?? [])
    @Published var showProtected = false
    private var beforeVault: URL?
    var anchor: URL?
    var dragSet: [URL] = []

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var clipboardURLs: [URL] = []
    private var clipboardCut = false
    private var watcher: DispatchSourceFileSystemObject?
    private var generation = 0
    private var reloadTask: Task<Void, Never>?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let desktop = home.appendingPathComponent("Desktop")
        if let saved = UserDefaults.standard.string(forKey: FinderModel.lastKey), FileManager.default.fileExists(atPath: saved), !saved.hasPrefix(FinderModel.vaultRoot.standardizedFileURL.path) {
            current = URL(fileURLWithPath: saved)
        } else {
            current = desktop
        }
        let paths = UserDefaults.standard.stringArray(forKey: FinderModel.pinnedKey) ?? []
        pinned = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        migrateLegacyHidden()
    }

    func stop() { watcher?.cancel(); watcher = nil; showProtected = false }

    // MARK: Places

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static var places: [(title: String, symbol: String, url: URL)] {
        let h = home
        var list: [(title: String, symbol: String, url: URL)] = [
            ("Home", "house", h),
            ("Desktop", "menubar.dock.rectangle", h.appendingPathComponent("Desktop")),
            ("Documents", "doc", h.appendingPathComponent("Documents")),
            ("Downloads", "arrow.down.circle", h.appendingPathComponent("Downloads")),
            ("Pictures", "photo", h.appendingPathComponent("Pictures")),
            ("Movies", "film", h.appendingPathComponent("Movies")),
            ("Music", "music.note", h.appendingPathComponent("Music")),
            ("Applications", "square.grid.2x2", URL(fileURLWithPath: "/Applications"))
        ]
        let cloud = h.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: cloud.path) { list.insert(("iCloud Drive", "icloud", cloud), at: 1) }
        return list.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    static var drives: [(title: String, url: URL)] {
        let keys: [URLResourceKey] = [.volumeNameKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var out: [(title: String, url: URL)] = []
        for u in urls where u.path != "/" {
            let name = (try? u.resourceValues(forKeys: Set(keys)))?.volumeName ?? u.lastPathComponent
            out.append((name, u))
        }
        return out
    }

    // MARK: Navigation

    func go(_ url: URL, remember: Bool = true) {
        var target = url
        if isProtected(url) && !showProtected {
            guard HiddenAccess.unlock("files") else { message = "That folder is hidden. Enter your passcode to open it."; return }
            showProtected = true
        }
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) { message = "That folder is not there any more."; return }
        if !isDir.boolValue { target = url.deletingLastPathComponent() }
        if remember, target != current { backStack.append(current); forwardStack.removeAll() }
        if !isProtected(target) { showProtected = false }
        current = target
        selection = []
        query = ""
        if !isProtected(target) { UserDefaults.standard.set(target.path, forKey: FinderModel.lastKey) }
        syncButtons()
        reload()
        watch()
    }

    func goBack() {
        guard let last = backStack.popLast() else { return }
        forwardStack.append(current)
        go(last, remember: false)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(current)
        go(next, remember: false)
    }

    func goUp() {
        let parent = current.deletingLastPathComponent()
        if parent.path != current.path { go(parent) }
    }

    private func syncButtons() {
        canGoBack = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
    }

    func crumbs() -> [(title: String, url: URL)] {
        let home = FinderModel.home
        var out: [(title: String, url: URL)] = []
        var base: URL
        var parts: [String]
        if current.path == home.path || current.path.hasPrefix(home.path + "/") {
            base = home
            out.append(("Home", home))
            let rest = String(current.path.dropFirst(home.path.count))
            parts = rest.split(separator: "/").map(String.init)
        } else {
            base = URL(fileURLWithPath: "/")
            out.append(("Macintosh HD", base))
            parts = current.path.split(separator: "/").map(String.init)
        }
        for part in parts {
            base = base.appendingPathComponent(part)
            out.append((part, base))
        }
        return out
    }

    // MARK: Listing

    var visible: [FinderEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var list = entries
        if !q.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(q) } }
        if !showProtected && !hiddenPaths.isEmpty { list = list.filter { !isProtected($0.url) } }
        let up = ascending
        list.sort { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            let result: Bool
            switch sortKey {
            case "Modified": result = (a.modified ?? .distantPast) < (b.modified ?? .distantPast)
            case "Size": result = a.size < b.size
            case "Kind": result = a.kind.localizedCaseInsensitiveCompare(b.kind) == .orderedAscending
            default: result = a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            return up ? result : !result
        }
        return list
    }

    func setSort(_ key: String) {
        if sortKey == key { ascending.toggle() } else { sortKey = key; ascending = true }
    }

    func reload() {
        generation += 1
        let job = generation
        let folder = current
        let hidden = showHidden
        loading = true
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            let result: ([FinderEntry], String?) = await Task.detached(priority: .userInitiated) {
                FinderModel.read(folder, showHidden: hidden)
            }.value
            guard let self, job == self.generation else { return }
            self.entries = result.0
            self.loading = false
            self.selection = self.selection.filter { sel in result.0.contains { $0.url == sel } }
            if let problem = result.1 { self.message = problem }
        }
    }

    nonisolated static func read(_ folder: URL, showHidden: Bool) -> ([FinderEntry], String?) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey]
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: showHidden ? [] : [.skipsHiddenFiles])
            var out: [FinderEntry] = []
            out.reserveCapacity(urls.count)
            for u in urls {
                let v = try? u.resourceValues(forKeys: Set(keys))
                let isDir = (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
                out.append(FinderEntry(url: u, name: u.lastPathComponent, isFolder: isDir, size: Int64(v?.fileSize ?? 0), modified: v?.contentModificationDate, kind: isDir ? "Folder" : (v?.localizedTypeDescription ?? "Document")))
            }
            return (out, nil)
        } catch {
            return ([], "KeyDo cannot open this folder. If macOS asked for permission, allow it, or turn KeyDo on under System Settings > Privacy & Security > Files and Folders.")
        }
    }

    private func watch() {
        watcher?.cancel()
        watcher = nil
        let fd = Darwin.open(current.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in self?.reload() }
        source.setCancelHandler { _ = Darwin.close(fd) }
        source.resume()
        watcher = source
    }

    func start() {
        if watcher == nil { go(current, remember: false) } else { reload() }
    }

    // MARK: Changes

    func unique(_ wanted: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: wanted.path) { return wanted }
        let base = wanted.deletingPathExtension().lastPathComponent
        let ext = wanted.pathExtension
        let folder = wanted.deletingLastPathComponent()
        var n = 2
        while n < 1000 {
            let label = n == 2 ? "\(base) copy" : "\(base) copy \(n - 1)"
            let name = ext.isEmpty ? label : label + "." + ext
            let candidate = folder.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
        return folder.appendingPathComponent(UUID().uuidString + (ext.isEmpty ? "" : "." + ext))
    }

    @discardableResult
    func newFolder() -> URL? {
        let target = unique(current.appendingPathComponent("untitled folder"))
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            reload()
            selection = [target]
            message = "Created \"\(target.lastPathComponent)\"."
            return target
        } catch {
            message = "Could not create a folder here."
            return nil
        }
    }

    func rename(_ url: URL, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), name != url.lastPathComponent else { return }
        let destination = url.deletingLastPathComponent().appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) { message = "A file called \"\(name)\" is already here."; return }
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            remapHidden(from: url, to: destination)
            reload()
            selection = [destination]
            message = "Renamed to \"\(name)\"."
        } catch {
            message = "Could not rename \"\(url.lastPathComponent)\"."
        }
    }

    func trash(_ urls: [URL]) {
        var done = 0
        var failed = 0
        for u in urls {
            if (try? FileManager.default.trashItem(at: u, resultingItemURL: nil)) != nil { done += 1; remapHidden(from: u, to: nil) } else { failed += 1 }
        }
        selection = []
        reload()
        message = "Moved \(done) item(s) to the Trash." + (failed > 0 ? " \(failed) could not be moved." : "")
    }

    func duplicate(_ urls: [URL]) {
        var made: Set<URL> = []
        for u in urls {
            let target = unique(u)
            if (try? FileManager.default.copyItem(at: u, to: target)) != nil { made.insert(target) }
        }
        reload()
        selection = made
        message = "Duplicated \(made.count) item(s)."
    }

    func copy(_ urls: [URL]) { clipboardURLs = urls; clipboardCut = false; canPaste = !urls.isEmpty; message = "Copied \(urls.count) item(s). Open a folder and press Paste." }
    func cut(_ urls: [URL]) { clipboardURLs = urls; clipboardCut = true; canPaste = !urls.isEmpty; message = "Ready to move \(urls.count) item(s). Open a folder and press Paste." }

    func paste(into folder: URL? = nil) {
        let target = folder ?? current
        let list = clipboardURLs
        let wasCut = clipboardCut
        place(list, into: target, copy: !wasCut)
        if wasCut { clipboardURLs = []; canPaste = false }
    }

    private func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let ia = (try? a.resourceValues(forKeys: [.volumeURLKey]))?.volume
        let ib = (try? b.resourceValues(forKeys: [.volumeURLKey]))?.volume
        guard let ia, let ib else { return true }
        return ia.path == ib.path
    }

    /// Moves (or copies) items into a folder. Dragging inside one drive moves; across drives copies; Option always copies.
    func place(_ urls: [URL], into folder: URL, copy: Bool) {
        var done = 0
        var skipped = 0
        let fm = FileManager.default
        for u in urls {
            let source = u.standardizedFileURL
            let dest = folder.standardizedFileURL
            if source.deletingLastPathComponent().path == dest.path && !copy { skipped += 1; continue }
            if dest.path == source.path || dest.path.hasPrefix(source.path + "/") { skipped += 1; continue }
            let target = unique(dest.appendingPathComponent(source.lastPathComponent))
            do {
                if copy || !sameVolume(source, dest) { try fm.copyItem(at: source, to: target) } else { try fm.moveItem(at: source, to: target); remapHidden(from: source, to: target) }
                done += 1
            } catch { skipped += 1 }
        }
        reload()
        message = (copy ? "Copied " : "Moved ") + "\(done) item(s) to \"\(folder.lastPathComponent)\"." + (skipped > 0 ? " \(skipped) skipped." : "")
    }

    func compress(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let name = urls.count == 1 ? first.lastPathComponent : "Archive"
        let zip = unique(current.appendingPathComponent(name + ".zip"))
        let sources = urls.map { $0.path }
        message = "Compressing…"
        Task { [weak self] in
            let ok: Bool = await Task.detached { () -> Bool in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                process.currentDirectoryURL = first.deletingLastPathComponent()
                process.arguments = ["-r", "-q", zip.path] + sources.map { URL(fileURLWithPath: $0).lastPathComponent }
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 } catch { return false }
            }.value
            self?.reload()
            self?.message = ok ? "Created \"\(zip.lastPathComponent)\"." : "Could not compress these items."
        }
    }

    // MARK: Hide with passcode

    // The secure vault: hidden items are moved out of their folder into KeyDo's own hidden folder
    // (Application Support/KeyDo/Vault). They no longer show where they were, in KeyDo or in the Mac's Finder.
    // The passcode opens the vault inside KeyDo. The files are not encrypted.
    static var vaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyDo", isDirectory: true).appendingPathComponent("Vault", isDirectory: true)
    }
    private static var manifestURL: URL { vaultRoot.deletingLastPathComponent().appendingPathComponent("vault-origins.json") }

    private func loadOrigins() -> [String: String] {
        guard let data = try? Data(contentsOf: FinderModel.manifestURL), let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    private func saveOrigins(_ map: [String: String]) {
        if let data = try? JSONEncoder().encode(map) { try? data.write(to: FinderModel.manifestURL, options: .atomic) }
    }

    private func prepareVault() {
        try? FileManager.default.createDirectory(at: FinderModel.vaultRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var url = FinderModel.vaultRoot
        var values = URLResourceValues()
        values.isHidden = true
        try? url.setResourceValues(values)
    }

    func isProtected(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path, root = FinderModel.vaultRoot.standardizedFileURL.path
        return p == root || p.hasPrefix(root + "/")
    }

    func isHidden(_ url: URL) -> Bool { isProtected(url) }

    private func saveHidden() { UserDefaults.standard.set(Array(hiddenPaths), forKey: FinderModel.hiddenKey) }

    /// Kept for the move, rename and delete code: nothing is hidden in place any more.
    func remapHidden(from old: URL, to new: URL?) {}

    /// Items hidden by an earlier version stayed in their folder. They are moved into the vault once.
    private func migrateLegacyHidden() {
        guard !hiddenPaths.isEmpty else { return }
        let old = hiddenPaths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        hiddenPaths = []
        saveHidden()
        _ = moveToVault(old)
    }

    @discardableResult private func moveToVault(_ urls: [URL]) -> (moved: Int, failed: Int) {
        prepareVault()
        var origins = loadOrigins()
        var moved = 0, failed = 0
        for u in urls where !isProtected(u) {
            let target = unique(FinderModel.vaultRoot.appendingPathComponent(u.lastPathComponent))
            do {
                try FileManager.default.moveItem(at: u, to: target)
                origins[target.lastPathComponent] = u.standardizedFileURL.path
                moved += 1
            } catch { failed += 1 }
        }
        saveOrigins(origins)
        return (moved, failed)
    }

    func hide(_ urls: [URL]) {
        if !AppPasscode.isSet {
            guard HiddenAccess.unlock("files") else { message = "Choose a passcode to hide files."; return }
        }
        let result = moveToVault(urls)
        selection = []
        reload()
        message = result.failed == 0 ? "Moved \(result.moved) item(s) into the secure vault. They are no longer in this folder. Use Protected files and your passcode to see them or put them back."
            : "Moved \(result.moved) item(s) into the vault. \(result.failed) could not be moved."
    }

    /// Puts items from the vault back in the folder they came from (the Desktop if that folder is gone).
    func unhide(_ urls: [URL]) {
        var origins = loadOrigins()
        let fm = FileManager.default
        var back = 0
        for u in urls where isProtected(u) {
            let key = u.lastPathComponent
            let topLevel = u.deletingLastPathComponent().standardizedFileURL.path == FinderModel.vaultRoot.standardizedFileURL.path
            var folder = FinderModel.home.appendingPathComponent("Desktop")
            var name = key
            if topLevel, let origin = origins[key] {
                let original = URL(fileURLWithPath: origin)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: original.deletingLastPathComponent().path, isDirectory: &isDir), isDir.boolValue { folder = original.deletingLastPathComponent() }
                name = original.lastPathComponent
            }
            let target = unique(folder.appendingPathComponent(name))
            if (try? fm.moveItem(at: u, to: target)) != nil { origins[key] = nil; back += 1 }
        }
        saveOrigins(origins)
        reload()
        message = "Put \(back) item(s) back where they came from."
    }

    func toggleProtected() {
        if showProtected {
            showProtected = false
            selection = []
            go(beforeVault ?? FinderModel.home.appendingPathComponent("Desktop"))
            message = "The vault is closed again."
            return
        }
        if HiddenAccess.unlock("files") {
            beforeVault = current
            prepareVault()
            showProtected = true
            go(FinderModel.vaultRoot)
            message = "Secure vault. Right-click an item and choose Put back to return it."
        }
    }

    func pin(_ url: URL) {
        guard !pinned.contains(url) else { return }
        pinned.append(url)
        savePinned()
    }

    func unpin(_ url: URL) { pinned.removeAll { $0 == url }; savePinned() }

    private func savePinned() { UserDefaults.standard.set(pinned.map { $0.path }, forKey: FinderModel.pinnedKey) }

    // MARK: Opening

    func open(_ urls: [URL]) {
        if urls.count == 1, let one = urls.first {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: one.path, isDirectory: &isDir)
            let package = (try? one.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
            if exists, isDir.boolValue, !package { go(one); return }
        }
        for u in urls { NSWorkspace.shared.open(u) }
    }

    func reveal(_ urls: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(urls) }

    func quickLook(_ urls: [URL]) {
        FinderQuickLook.shared.show(urls)
    }

    func openInViewer(_ url: URL) {
        NotificationCenter.default.post(name: .keydoOpenDocumentViewer, object: url.path)
    }

    func addToLibrary(_ urls: [URL]) {
        let files = urls.filter { u in
            var d: ObjCBool = false
            return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && !d.boolValue
        }
        guard !files.isEmpty else { message = "Pick files (not folders) to add to the My Files library."; return }
        _ = MyDatabaseStore.shared.addFiles(files, collection: "Mac files", kind: "file")
        message = "Added \(files.count) file(s) to the My Files library, in the collection \"Mac files\"."
    }

    func chooseFolder(_ prompt: String, then: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.directoryURL = current
        if panel.runModal() == .OK, let url = panel.url { then(url) }
    }

    func isFolder(_ url: URL) -> Bool {
        var d: ObjCBool = false
        let package = (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue && !package
    }
}

struct FinderInfoItem: Identifiable { let url: URL; var id: String { url.path } }

struct SidebarPlace: View {
    let title: String
    let symbol: String
    let active: Bool
    let removable: Bool
    var open: () -> Void
    var remove: () -> Void
    var drop: ([NSItemProvider]) -> Bool
    @State private var targeted = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(Butter.coral)
                Text(title).font(.system(size: 13, weight: active ? .bold : .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(targeted ? Butter.coral.opacity(0.28) : (active ? Butter.coral.opacity(0.14) : Color.clear), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in drop(providers) }
        .contextMenu { if removable { Button("Remove from My folders", action: remove) } }
    }
}

enum FinderFormat {
    static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct FinderInfoSheet: View {
    let url: URL
    var close: () -> Void

    private var attrs: [FileAttributeKey: Any] { (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 48, height: 48)
                Text(url.lastPathComponent).font(.title3.bold()).lineLimit(2)
            }
            infoRow("Kind", (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription ?? "Item")
            infoRow("Size", FinderFormat.size((attrs[.size] as? NSNumber)?.int64Value ?? 0))
            infoRow("Created", (attrs[.creationDate] as? Date).map { FinderFormat.date.string(from: $0) } ?? "--")
            infoRow("Modified", (attrs[.modificationDate] as? Date).map { FinderFormat.date.string(from: $0) } ?? "--")
            infoRow("Where", url.deletingLastPathComponent().path)
            HStack {
                Button("Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string) }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            Text(value).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The normal macOS Quick Look window, inside KeyDo. Arrow keys move between files; Space or Escape closes it.
@MainActor
final class FinderQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = FinderQuickLook()
    private var items: [NSURL] = []

    func show(_ urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        items = existing.map { $0 as NSURL }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { items.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { index >= 0 && index < items.count ? items[index] : nil }
    }
}
