// My Files > Finder: browse, drag, copy, move, rename and tidy any folder on this Mac without leaving KeyDo.
// Works on real files and folders (Desktop, Documents, Downloads, other drives). Nothing is hidden: Trash keeps files recoverable.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    @Published var iconView = false
    @Published var message = ""
    @Published var pinned: [URL] = []
    @Published var loading = false
    @Published var canPaste = false
    @Published var canGoBack = false
    @Published var canGoForward = false

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
        if let saved = UserDefaults.standard.string(forKey: FinderModel.lastKey), FileManager.default.fileExists(atPath: saved) {
            current = URL(fileURLWithPath: saved)
        } else {
            current = desktop
        }
        let paths = UserDefaults.standard.stringArray(forKey: FinderModel.pinnedKey) ?? []
        pinned = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func stop() { watcher?.cancel(); watcher = nil }

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
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) { message = "That folder is not there any more."; return }
        if !isDir.boolValue { target = url.deletingLastPathComponent() }
        if remember, target != current { backStack.append(current); forwardStack.removeAll() }
        current = target
        selection = []
        query = ""
        UserDefaults.standard.set(target.path, forKey: FinderModel.lastKey)
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
            if (try? FileManager.default.trashItem(at: u, resultingItemURL: nil)) != nil { done += 1 } else { failed += 1 }
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
                if copy || !sameVolume(source, dest) { try fm.copyItem(at: source, to: target) } else { try fm.moveItem(at: source, to: target) }
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
        guard let first = urls.first else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", first.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
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

// MARK: - View

struct FinderView: View {
    @StateObject private var model = FinderModel()
    @State private var renameTarget: URL?
    @State private var renameText = ""
    @State private var showRename = false
    @State private var infoItem: FinderInfoItem?
    @State private var showGoTo = false
    @State private var goText = ""
    @State private var dropRow: URL?
    @State private var paneDrop = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                toolbar
                Divider()
                content
                statusBar
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $paneDrop) { providers in drop(providers, into: model.current) }
            .overlay { if paneDrop { RoundedRectangle(cornerRadius: 10).stroke(Butter.coral, lineWidth: 3).padding(4).allowsHitTesting(false) } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .alert("Rename", isPresented: $showRename) {
            TextField("New name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { if let target = renameTarget { model.rename(target, to: renameText) } }
        }
        .alert("Go to folder", isPresented: $showGoTo) {
            TextField("/Users/you/Desktop", text: $goText)
            Button("Cancel", role: .cancel) {}
            Button("Go") {
                let path = (goText as NSString).expandingTildeInPath
                model.go(URL(fileURLWithPath: path))
            }
        } message: { Text("Type or paste a folder path.") }
        .sheet(item: $infoItem) { item in FinderInfoSheet(url: item.url) { infoItem = nil } }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                sectionTitle("Favourites")
                ForEach(FinderModel.places, id: \.url) { place in
                    sidebarRow(place.title, place.symbol, place.url, removable: false)
                }
                sectionTitle("My folders")
                if model.pinned.isEmpty {
                    Text("Drop a folder here, or press Add folder.").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 4)
                }
                ForEach(model.pinned, id: \.self) { url in
                    sidebarRow(url.lastPathComponent, "folder.fill", url, removable: true)
                }
                Button {
                    model.chooseFolder("Add") { model.pin($0); model.go($0) }
                } label: {
                    Label("Add folder", systemImage: "plus.circle.fill").font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundStyle(Butter.coral)
                }
                .buttonStyle(.plain)
                let drives = FinderModel.drives
                if !drives.isEmpty {
                    sectionTitle("Drives")
                    ForEach(drives, id: \.url) { drive in sidebarRow(drive.title, "externaldrive", drive.url, removable: false) }
                }
            }
            .padding(10)
        }
        .frame(width: 210)
        .background(Butter.coral.opacity(0.04))
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in pinDropped(providers) }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 2)
    }

    private func sidebarRow(_ title: String, _ symbol: String, _ url: URL, removable: Bool) -> some View {
        SidebarPlace(title: title, symbol: symbol, active: model.current.path == url.path, removable: removable,
                     open: { model.go(url) }, remove: { model.unpin(url) },
                     drop: { providers in drop(providers, into: url) })
    }

    // MARK: Toolbar

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!model.canGoBack).keyboardShortcut("[", modifiers: .command).help("Back")
                Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.canGoForward).keyboardShortcut("]", modifiers: .command).help("Forward")
                Button { model.goUp() } label: { Image(systemName: "chevron.up") }
                    .keyboardShortcut(.upArrow, modifiers: .command).help("Enclosing folder")
                breadcrumbs
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search this folder", text: $model.query).textFieldStyle(.plain).frame(width: 150)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Butter.cream, in: Capsule()).overlay(Capsule().stroke(Butter.honey, lineWidth: 1))
            }
            HStack(spacing: 8) {
                Picker("View", selection: $model.iconView) {
                    Label("List", systemImage: "list.bullet").tag(false)
                    Label("Icons", systemImage: "square.grid.2x2").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 110).help("List or icons")
                Menu {
                    ForEach(["Name", "Modified", "Size", "Kind"], id: \.self) { key in
                        Button(model.sortKey == key ? key + (model.ascending ? "  \u{2191}" : "  \u{2193}") : key) { model.setSort(key) }
                    }
                } label: { Label("Sort: \(model.sortKey)", systemImage: "arrow.up.arrow.down") }
                    .menuStyle(.borderlessButton).fixedSize()
                Toggle(isOn: $model.showHidden) { Text("Hidden files") }
                    .toggleStyle(.checkbox).controlSize(.small)
                    .onChange(of: model.showHidden) { _ in model.reload() }
                Spacer()
                Button { makeFolder() } label: { Label("New folder", systemImage: "folder.badge.plus") }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button { model.paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }.disabled(!model.canPaste)
                Button { goText = model.current.path; showGoTo = true } label: { Label("Go to…", systemImage: "arrow.right.circle") }
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh")
                Button { NSWorkspace.shared.open(model.current) } label: { Label("Open in Finder", systemImage: "folder") }
            }
            .controlSize(.small)
            if !model.selection.isEmpty { selectionBar }
        }
        .padding(10)
    }

    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                let crumbs = model.crumbs()
                ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                    if index > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
                    Button { model.go(crumb.url) } label: {
                        Text(crumb.title).font(.system(size: 13, weight: index == crumbs.count - 1 ? .bold : .medium)).lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(index == crumbs.count - 1 ? Butter.coral.opacity(0.14) : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 520)
    }

    private var selectionBar: some View {
        let urls = Array(model.selection)
        return HStack(spacing: 8) {
            Text("\(urls.count) selected").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Button("Open") { model.open(urls) }
            Button("Copy") { model.copy(urls) }
            Button("Cut") { model.cut(urls) }
            Button("Duplicate") { model.duplicate(urls) }
            if urls.count == 1, let one = urls.first { Button("Rename") { beginRename(one) } }
            Button("Move to…") { model.chooseFolder("Move here") { model.place(urls, into: $0, copy: false) } }
            Button("Copy to…") { model.chooseFolder("Copy here") { model.place(urls, into: $0, copy: true) } }
            Button("Add to My Files library") { model.addToLibrary(urls) }
            Spacer()
            Button(role: .destructive) { model.trash(urls) } label: { Label("Trash", systemImage: "trash") }
                .keyboardShortcut(.delete, modifiers: .command)
        }
        .controlSize(.small)
        .padding(8)
        .background(Butter.coral.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        let list = model.visible
        if list.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: model.loading ? "hourglass" : "folder").font(.system(size: 40)).foregroundStyle(.secondary)
                Text(model.loading ? "Loading…" : (model.query.isEmpty ? "This folder is empty" : "Nothing matches your search")).font(.headline)
                Text("Drag files and folders here from your Desktop or Finder to put them in this folder.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contextMenu { blankMenu }
        } else if model.iconView {
            iconGrid(list)
        } else {
            listView(list)
        }
    }

    private func listView(_ list: [FinderEntry]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                headerCell("Name", width: nil)
                headerCell("Modified", width: 150)
                headerCell("Size", width: 80)
                headerCell("Kind", width: 150)
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Butter.coral.opacity(0.06))
            List(selection: $model.selection) {
                ForEach(list) { entry in
                    row(entry)
                        .tag(entry.url)
                        .onDrag { NSItemProvider(object: entry.url as NSURL) }
                        .onDrop(of: [UTType.fileURL], isTargeted: Binding(get: { dropRow == entry.url }, set: { on in dropRow = on ? entry.url : (dropRow == entry.url ? nil : dropRow) })) { providers in
                            entry.isFolder ? drop(providers, into: entry.url) : false
                        }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: URL.self) { urls in
                if urls.isEmpty { blankMenu } else { itemMenu(Array(urls)) }
            } primaryAction: { urls in model.open(Array(urls)) }
        }
    }

    private func headerCell(_ title: String, width: CGFloat?) -> some View {
        Button { model.setSort(title) } label: {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 11, weight: .bold))
                if model.sortKey == title { Image(systemName: model.ascending ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold)) }
                Spacer(minLength: 0)
            }
            .foregroundStyle(model.sortKey == title ? Butter.coral : Color.secondary)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func row(_ entry: FinderEntry) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().frame(width: 22, height: 22)
                Text(entry.name).font(.system(size: 13, weight: entry.isFolder ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.modified.map { FinderFormat.date.string(from: $0) } ?? "--").frame(width: 150, alignment: .leading)
            Text(entry.isFolder ? "--" : FinderFormat.size(entry.size)).frame(width: 80, alignment: .leading)
            Text(entry.kind).lineLimit(1).frame(width: 150, alignment: .leading)
        }
        .font(.system(size: 12)).foregroundStyle(.secondary)
        .padding(.vertical, 2)
        .background(dropRow == entry.url ? Butter.coral.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private func iconGrid(_ list: [FinderEntry]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 120), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(list) { entry in
                    FinderTile(entry: entry, selected: model.selection.contains(entry.url), dropTarget: dropRow == entry.url)
                        .onTapGesture(count: 2) { model.open([entry.url]) }
                        .onTapGesture {
                            if NSEvent.modifierFlags.contains(.command) {
                                if model.selection.contains(entry.url) { model.selection.remove(entry.url) } else { model.selection.insert(entry.url) }
                            } else { model.selection = [entry.url] }
                        }
                        .onDrag { NSItemProvider(object: entry.url as NSURL) }
                        .onDrop(of: [UTType.fileURL], isTargeted: Binding(get: { dropRow == entry.url }, set: { on in dropRow = on ? entry.url : (dropRow == entry.url ? nil : dropRow) })) { providers in
                            entry.isFolder ? drop(providers, into: entry.url) : false
                        }
                        .contextMenu {
                            let targets = model.selection.contains(entry.url) ? Array(model.selection) : [entry.url]
                            itemMenu(targets)
                        }
                }
            }
            .padding(14)
        }
        .contextMenu { blankMenu }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text("\(model.visible.count) items").font(.caption).foregroundStyle(.secondary)
            if !model.message.isEmpty {
                Text("·").foregroundStyle(.secondary)
                Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Butter.coral.opacity(0.04))
    }

    // MARK: Menus and actions

    @ViewBuilder private var blankMenu: some View {
        Button("New folder") { makeFolder() }
        Button("Paste") { model.paste() }.disabled(!model.canPaste)
        Button("Refresh") { model.reload() }
    }

    @ViewBuilder private func itemMenu(_ urls: [URL]) -> some View {
        let single: URL? = urls.count == 1 ? urls.first : nil
        Button("Open") { model.open(urls) }
        if let one = single, ["pdf", "docx", "doc"].contains(one.pathExtension.lowercased()) {
            Button("Open in KeyDo viewer (notes and highlights)") { model.openInViewer(one) }
        }
        Button("Quick Look") { model.quickLook(urls) }
        Button("Reveal in Finder") { model.reveal(urls) }
        if let one = single { Button("Get info") { infoItem = FinderInfoItem(url: one) } }
        Divider()
        if let one = single { Button("Rename…") { beginRename(one) } }
        Button("Duplicate") { model.duplicate(urls) }
        Button("Copy") { model.copy(urls) }
        Button("Cut") { model.cut(urls) }
        if let one = single, model.isFolder(one) { Button("Paste into this folder") { model.paste(into: one) }.disabled(!model.canPaste) }
        Button("Move to…") { model.chooseFolder("Move here") { model.place(urls, into: $0, copy: false) } }
        Button("Copy to…") { model.chooseFolder("Copy here") { model.place(urls, into: $0, copy: true) } }
        Button("Compress") { model.compress(urls) }
        Divider()
        Button("Add to My Files library") { model.addToLibrary(urls) }
        if let one = single, model.isFolder(one) { Button("Pin to My folders") { model.pin(one) } }
        Button("Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(urls.map { $0.path }.joined(separator: "\n"), forType: .string) }
        Divider()
        Button("Move to Trash", role: .destructive) { model.trash(urls) }
    }

    private func makeFolder() {
        if let made = model.newFolder() { beginRename(made) }
    }

    private func beginRename(_ url: URL) {
        renameTarget = url
        renameText = url.lastPathComponent
        showRename = true
    }

    private func readURLs(_ providers: [NSItemProvider], done: @escaping ([URL]) -> Void) {
        var found: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); found.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(found) }
    }

    private func drop(_ providers: [NSItemProvider], into folder: URL) -> Bool {
        let option = NSEvent.modifierFlags.contains(.option)
        readURLs(providers) { urls in
            guard !urls.isEmpty else { return }
            model.place(urls, into: folder, copy: option)
        }
        return true
    }

    private func pinDropped(_ providers: [NSItemProvider]) -> Bool {
        readURLs(providers) { urls in
            var added = 0
            for u in urls where model.isFolder(u) { model.pin(u); added += 1 }
            if added > 0 { model.message = "Added \(added) folder(s) to My folders." }
        }
        return true
    }
}

struct FinderInfoItem: Identifiable { let url: URL; var id: String { url.path } }

private struct SidebarPlace: View {
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

private struct FinderTile: View {
    let entry: FinderEntry
    let selected: Bool
    let dropTarget: Bool

    private var isMedia: Bool {
        let type = LibraryContentType.fileType(entry.url.path)
        return type == .image || type == .video
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if isMedia && !entry.isFolder {
                    LibraryPosterTile(path: entry.url.path, isVideo: LibraryContentType.fileType(entry.url.path) == .video)
                        .frame(width: 84, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().scaledToFit().frame(width: 62, height: 62)
                }
            }
            .frame(width: 90, height: 72)
            Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(8)
        .frame(width: 112, height: 124, alignment: .top)
        .background(dropTarget ? Butter.coral.opacity(0.25) : (selected ? Butter.coral.opacity(0.16) : Color.clear), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Butter.coral : Color.clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 12))
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
