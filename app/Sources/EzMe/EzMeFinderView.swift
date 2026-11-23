// My Files > Finder, the screen. Big icons with real previews, hover buttons, rename right on the name,
// click / Shift-click / Command-click and drag-a-box selection, and drag and drop between folders.
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing

private struct FinderFrameKey: PreferenceKey {
    static var defaultValue: [URL: CGRect] = [:]
    static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// A real picture of the file (photo, video frame, PDF page, document) with the normal icon while it loads.
struct FinderThumb: View {
    let url: URL
    let side: CGFloat
    let isFolder: Bool
    @State private var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
            }
        }
        .frame(width: side, height: side)
        .task(id: "\(url.path)|\(Int(side))") { await load() }
    }

    private func load() async {
        if isFolder { image = nil; return }
        let key = "\(url.path)|\(Int(side))" as NSString
        if let cached = FinderThumb.cache.object(forKey: key) { image = cached; return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: scale, representationTypes: .thumbnail)
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            let picture = rep.nsImage
            FinderThumb.cache.setObject(picture, forKey: key)
            image = picture
        }
    }
}

/// The name shown as an editable box while renaming. Return saves, Escape cancels.
private struct FinderNameField: View {
    @Binding var text: String
    var center: Bool
    var commit: () -> Void
    var cancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, weight: .medium))
            .multilineTextAlignment(center ? .center : .leading)
            .focused($focused)
            .onSubmit(commit)
            .onExitCommand(perform: cancel)
            .onAppear {
                focused = true
                DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
            }
            .onChange(of: focused) { isFocused in if !isFocused { commit() } }
    }
}

struct FinderView: View {
    @StateObject private var model = FinderModel()
    @State private var renaming: URL?
    @State private var renameText = ""
    @State private var infoItem: FinderInfoItem?
    @State private var showGoTo = false
    @State private var goText = ""
    @State private var dropRow: URL?
    @State private var paneDrop = false
    @State private var hovered: URL?
    @State private var frames: [URL: CGRect] = [:]
    @State private var marquee: CGRect?
    @State private var marqueeBase: Set<URL> = []
    @FocusState private var canvasFocused: Bool

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
        .alert("Go to folder", isPresented: $showGoTo) {
            TextField("/Users/you/Desktop", text: $goText)
            Button("Cancel", role: .cancel) {}
            Button("Go") { model.go(URL(fileURLWithPath: (goText as NSString).expandingTildeInPath)) }
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
                    Label("Icons", systemImage: "square.grid.2x2").tag(true)
                    Label("List", systemImage: "list.bullet").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 110).help("Icons or list")
                if model.iconView {
                    Image(systemName: "photo").font(.system(size: 10)).foregroundStyle(.secondary)
                    Slider(value: $model.iconSize, in: 64...200).frame(width: 110).help("Icon size")
                    Image(systemName: "photo").font(.system(size: 15)).foregroundStyle(.secondary)
                }
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
                Button { model.toggleProtected() } label: { Label(model.showProtected ? "Close vault" : "Protected files", systemImage: model.showProtected ? "lock.open.fill" : "lock.fill") }
                    .tint(model.showProtected ? Butter.coral : nil)
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
            if urls.contains(where: { model.isHidden($0) }) { Button("Put back") { model.unhide(urls) } } else { Button("Move to secure vault") { model.hide(urls) } }
            Spacer()
            Button("Select none") { model.selection = [] }
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
                Image(systemName: model.loading ? "hourglass" : "folder").font(.system(size: 44)).foregroundStyle(.secondary)
                Text(model.loading ? "Loading…" : (model.query.isEmpty ? "This folder is empty" : "Nothing matches your search")).font(.headline)
                Text("Drag files and folders here from your Desktop or Finder to put them in this folder.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contextMenu { blankMenu }
        } else {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        if !model.iconView { listHeader }
                        if model.iconView { iconGrid(list) } else { listRows(list) }
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                    .background(canvasBackground)
                    .coordinateSpace(name: "finderCanvas")
                    .overlay(alignment: .topLeading) { marqueeBox }
                    .onPreferenceChange(FinderFrameKey.self) { frames = $0 }
                }
            }
            .focusable()
            .focused($canvasFocused)
            .focusEffectDisabled()
            .onKeyPress(.return) { handleReturn() }
            .onKeyPress(.space) { handleSpace() }
            .onKeyPress(.escape) { model.selection = []; return .handled }
            .onKeyPress(characters: CharacterSet(charactersIn: "a"), phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                model.selection = Set(model.visible.map { $0.url })
                return .handled
            }
        }
    }

    private func handleReturn() -> KeyPress.Result {
        if renaming == nil, model.selection.count == 1, let one = model.selection.first { beginRename(one); return .handled }
        return .ignored
    }

    private func handleSpace() -> KeyPress.Result {
        if renaming == nil, !model.selection.isEmpty { model.quickLook(Array(model.selection)); return .handled }
        return .ignored
    }

    /// The empty space behind the files: click to clear, drag to draw a selection box.
    private var canvasBackground: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { model.selection = []; canvasFocused = true; commitRename() }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("finderCanvas"))
                    .onChanged { value in
                        if marquee == nil {
                            let flags = NSEvent.modifierFlags
                            marqueeBase = (flags.contains(.shift) || flags.contains(.command)) ? model.selection : []
                            canvasFocused = true
                        }
                        let rect = CGRect(x: min(value.startLocation.x, value.location.x), y: min(value.startLocation.y, value.location.y),
                                          width: abs(value.location.x - value.startLocation.x), height: abs(value.location.y - value.startLocation.y))
                        marquee = rect
                        var hit = Set<URL>()
                        for (url, frame) in frames where frame.intersects(rect) { hit.insert(url) }
                        model.selection = marqueeBase.union(hit)
                    }
                    .onEnded { _ in marquee = nil }
            )
    }

    @ViewBuilder private var marqueeBox: some View {
        if let rect = marquee {
            RoundedRectangle(cornerRadius: 3).fill(Butter.coral.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Butter.coral.opacity(0.9), lineWidth: 1))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }

    // MARK: Icons

    private func iconGrid(_ list: [FinderEntry]) -> some View {
        let side = CGFloat(model.iconSize)
        let tileWidth = side + 28
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth, maximum: tileWidth + 40), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
            ForEach(list) { entry in
                tile(entry, side: side)
            }
        }
        .padding(18)
    }

    private func tile(_ entry: FinderEntry, side: CGFloat) -> some View {
        let selected = model.selection.contains(entry.url)
        let isHover = hovered == entry.url
        let isRenaming = renaming == entry.url
        return VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                FinderThumb(url: entry.url, side: side, isFolder: entry.isFolder)
                    .opacity(1)
                    .overlay(alignment: .bottomLeading) { lockBadge(entry.url) }
                    .scaleEffect(isHover ? 1.04 : 1)
                    .animation(.easeOut(duration: 0.12), value: isHover)
                if isHover && !isRenaming {
                    HStack(spacing: 4) {
                        hoverButton("eye", "Quick Look") { model.quickLook([entry.url]) }
                        hoverButton("pencil", "Rename") { beginRename(entry.url) }
                    }
                    .padding(2)
                    .transition(.opacity)
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.open([entry.url]) }
            if isRenaming {
                FinderNameField(text: $renameText, center: true, commit: commitRename, cancel: cancelRename).frame(width: side + 20)
            } else {
                Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(selected ? Butter.coral : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .frame(width: side + 20)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { beginRename(entry.url) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(tileFill(selected: selected, hover: isHover, dropping: dropRow == entry.url)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tileBorder(selected: selected, hover: isHover), lineWidth: 1.5))
        .shadow(color: .black.opacity(isHover ? 0.10 : 0), radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { click(entry) }
        .onHover { inside in hovered = inside ? entry.url : (hovered == entry.url ? nil : hovered) }
        .background(frameReader(entry.url))
        .onDrag { dragProvider(entry) }
        .onDrop(of: [UTType.fileURL], isTargeted: dropBinding(entry)) { providers in entry.isFolder ? drop(providers, into: entry.url) : false }
        .contextMenu { itemMenu(menuTargets(entry)) }
    }

    private func tileFill(selected: Bool, hover: Bool, dropping: Bool) -> Color {
        if dropping { return Butter.coral.opacity(0.26) }
        if selected { return Butter.coral.opacity(0.14) }
        if hover { return Butter.coral.opacity(0.07) }
        return Color.clear
    }

    private func tileBorder(selected: Bool, hover: Bool) -> Color {
        if selected { return Butter.coral.opacity(0.7) }
        if hover { return Butter.honey }
        return Color.clear
    }

    private func rowFill(selected: Bool, hover: Bool, dropping: Bool) -> Color {
        if dropping { return Butter.coral.opacity(0.3) }
        if selected { return Butter.coral.opacity(0.88) }
        if hover { return Butter.coral.opacity(0.10) }
        return Color.clear
    }

    @ViewBuilder private func lockBadge(_ url: URL) -> some View {
        if model.isProtected(url) {
            Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Circle().fill(Butter.coral))
        }
    }

    private func hoverButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain).help(help)
    }

    // MARK: List

    private var listHeader: some View {
        HStack(spacing: 0) {
            headerCell("Name", width: nil)
            headerCell("Modified", width: 150)
            headerCell("Size", width: 80)
            headerCell("Kind", width: 150)
        }
        .padding(.horizontal, 18).padding(.vertical, 7)
        .background(Butter.coral.opacity(0.06))
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

    private func listRows(_ list: [FinderEntry]) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(list) { entry in row(entry) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func row(_ entry: FinderEntry) -> some View {
        let selected = model.selection.contains(entry.url)
        let isHover = hovered == entry.url
        let isRenaming = renaming == entry.url
        return HStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().frame(width: 26, height: 26)
                    .opacity(1)
                    .overlay(alignment: .bottomTrailing) { lockBadge(entry.url) }
                if isRenaming {
                    FinderNameField(text: $renameText, center: false, commit: commitRename, cancel: cancelRename)
                } else {
                    Text(entry.name).font(.system(size: 13, weight: entry.isFolder ? .semibold : .regular)).lineLimit(1)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { beginRename(entry.url) }
                }
                Spacer(minLength: 0)
                if isHover && !isRenaming {
                    hoverButton("eye", "Quick Look") { model.quickLook([entry.url]) }
                    hoverButton("pencil", "Rename") { beginRename(entry.url) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.modified.map { FinderFormat.date.string(from: $0) } ?? "--").frame(width: 150, alignment: .leading)
            Text(entry.isFolder ? "--" : FinderFormat.size(entry.size)).frame(width: 80, alignment: .leading)
            Text(entry.kind).lineLimit(1).frame(width: 150, alignment: .leading)
        }
        .font(.system(size: 12)).foregroundStyle(selected ? Color.white.opacity(0.9) : Color.secondary)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(rowFill(selected: selected, hover: isHover, dropping: dropRow == entry.url)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.open([entry.url]) }
        .onTapGesture { click(entry) }
        .onHover { inside in hovered = inside ? entry.url : (hovered == entry.url ? nil : hovered) }
        .background(frameReader(entry.url))
        .onDrag { dragProvider(entry) }
        .onDrop(of: [UTType.fileURL], isTargeted: dropBinding(entry)) { providers in entry.isFolder ? drop(providers, into: entry.url) : false }
        .contextMenu { itemMenu(menuTargets(entry)) }
    }

    // MARK: Selection and drag helpers

    private func frameReader(_ url: URL) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: FinderFrameKey.self, value: [url: geo.frame(in: .named("finderCanvas"))])
        }
    }

    private func click(_ entry: FinderEntry) {
        canvasFocused = true
        commitRename()
        let flags = NSEvent.modifierFlags
        let urls = model.visible.map { $0.url }
        if flags.contains(.shift), let anchor = model.anchor, let i = urls.firstIndex(of: anchor), let j = urls.firstIndex(of: entry.url) {
            let range = Set(urls[min(i, j)...max(i, j)])
            model.selection = flags.contains(.command) ? model.selection.union(range) : range
        } else if flags.contains(.command) {
            if model.selection.contains(entry.url) { model.selection.remove(entry.url) } else { model.selection.insert(entry.url) }
            model.anchor = entry.url
        } else {
            model.selection = [entry.url]
            model.anchor = entry.url
        }
    }

    private func menuTargets(_ entry: FinderEntry) -> [URL] {
        model.selection.contains(entry.url) ? Array(model.selection) : [entry.url]
    }

    private func dragProvider(_ entry: FinderEntry) -> NSItemProvider {
        model.dragSet = model.selection.contains(entry.url) ? Array(model.selection) : [entry.url]
        return NSItemProvider(object: entry.url as NSURL)
    }

    private func dropBinding(_ entry: FinderEntry) -> Binding<Bool> {
        Binding(get: { dropRow == entry.url }, set: { on in dropRow = on ? entry.url : (dropRow == entry.url ? nil : dropRow) })
    }

    // MARK: Rename

    private func beginRename(_ url: URL) {
        model.selection = [url]
        renameText = url.lastPathComponent
        renaming = url
    }

    private func commitRename() {
        guard let target = renaming else { return }
        renaming = nil
        let name = renameText
        model.rename(target, to: name)
        canvasFocused = true
    }

    private func cancelRename() {
        renaming = nil
        canvasFocused = true
    }

    private func makeFolder() {
        if let made = model.newFolder() { beginRename(made) }
    }

    // MARK: Status, menus, drops

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(model.selection.isEmpty ? "\(model.visible.count) items" : "\(model.selection.count) of \(model.visible.count) selected").font(.caption).foregroundStyle(.secondary)
            if !model.message.isEmpty {
                Text("·").foregroundStyle(.secondary)
                Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Text("Click to select · Shift or \u{2318} click for more · drag a box to select · double-click a name to rename").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Butter.coral.opacity(0.04))
    }

    @ViewBuilder private var blankMenu: some View {
        Button("New folder") { makeFolder() }
        Button("Paste") { model.paste() }.disabled(!model.canPaste)
        Button("Select all") { model.selection = Set(model.visible.map { $0.url }) }
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
        if let one = single { Button("Rename") { beginRename(one) } }
        Button("Duplicate") { model.duplicate(urls) }
        Button("Copy") { model.copy(urls) }
        Button("Cut") { model.cut(urls) }
        if let one = single, model.isFolder(one) { Button("Paste into this folder") { model.paste(into: one) }.disabled(!model.canPaste) }
        Button("Move to…") { model.chooseFolder("Move here") { model.place(urls, into: $0, copy: false) } }
        Button("Copy to…") { model.chooseFolder("Copy here") { model.place(urls, into: $0, copy: true) } }
        Button("Compress") { model.compress(urls) }
        Divider()
        Button("Add to My Files library") { model.addToLibrary(urls) }
        if urls.contains(where: { model.isHidden($0) }) { Button("Put back") { model.unhide(urls) } } else { Button("Move to secure vault") { model.hide(urls) } }
        if let one = single, model.isFolder(one) { Button("Pin to My folders") { model.pin(one) } }
        Button("Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(urls.map { $0.path }.joined(separator: "\n"), forType: .string) }
        Divider()
        Button("Move to Trash", role: .destructive) { model.trash(urls) }
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
            // A drag that started in this window carries every selected file, not just the one under the pointer.
            var items = urls
            if let first = urls.first, model.dragSet.contains(where: { $0.standardizedFileURL == first.standardizedFileURL }) { items = model.dragSet }
            model.dragSet = []
            model.place(items, into: folder, copy: option)
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
