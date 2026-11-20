// The grid view of the Database Organizer: the same kind of tiles as the Collections grid, for contacts, links,
// files and media. Pictures and videos preview and open large, a title renames in place, one tap makes a
// shortcut, and every tile can be opened, shown in Finder, copied, moved or deleted.
import SwiftUI
import AppKit

struct DBGridView: View {
    let records: [DBRecord]
    @Binding var selection: Set<String>
    var collections: [String]
    var onEdit: (DBRecord) -> Void
    var onRename: (DBRecord, String) -> Void
    var onShortcut: (DBRecord) -> Void
    var onMove: (DBRecord, String) -> Void
    var onDelete: (DBRecord) -> Void
    var onOpenDocument: (URL) -> Void
    var onCopy: (String) -> Void

    @State private var viewer: LibraryGalleryStart?
    /// About four or five rows first; more tiles are added as you scroll near the end.
    @State private var shown = 24

    private func enlarge(_ record: DBRecord) {
        let items: [LibraryGalleryItem] = records.compactMap { item in
            guard item.isFileLike, FileManager.default.fileExists(atPath: item.value),
                  [.image, .gif, .video, .music].contains(LibraryContentType.fileType(item.value)) else { return nil }
            return LibraryGalleryItem(id: item.id + item.value, clipID: UUID(), title: item.title.isEmpty ? (item.value as NSString).lastPathComponent : item.title, path: item.value)
        }
        guard let start = items.firstIndex(where: { $0.path == record.value }) else { return }
        viewer = LibraryGalleryStart(items: items, index: start)
    }

    var body: some View {
        // The Database screen already scrolls, so the tiles are added lazily inside it.
        LazyVStack(spacing: 0) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(records.prefix(shown)) { record in
                        DBGridCard(
                            record: record,
                            isSelected: selection.contains(record.id),
                            collections: collections,
                            onToggle: { if selection.contains(record.id) { selection.remove(record.id) } else { selection.insert(record.id) } },
                            onEdit: { onEdit(record) },
                            onRename: { onRename(record, $0) },
                            onShortcut: { onShortcut(record) },
                            onMove: { onMove(record, $0) },
                            onDelete: { onDelete(record) },
                            onEnlarge: { enlarge(record) },
                            onOpenDocument: onOpenDocument,
                            onCopy: onCopy
                        )
                    }
                }
                .padding(2)
                if shown < records.count {
                    ProgressView().controlSize(.small).padding(14)
                        .onAppear { shown = min(records.count, shown + 24) }
                        .id(shown)
                }
        }
        .onChange(of: records.first?.id) { _ in shown = 24 }
        .onChange(of: records.count) { count in if count < shown { shown = max(24, count) } }
        .sheet(item: $viewer) { start in
            LibraryMediaViewer(items: start.items, startIndex: start.index, collectionNames: [], onFinished: { _ in })
        }
    }
}

struct DBGridCard: View {
    let record: DBRecord
    let isSelected: Bool
    var collections: [String]
    var onToggle: () -> Void
    var onEdit: () -> Void
    var onRename: (String) -> Void
    var onShortcut: () -> Void
    var onMove: (String) -> Void
    var onDelete: () -> Void
    var onEnlarge: () -> Void
    var onOpenDocument: (URL) -> Void
    var onCopy: (String) -> Void

    @State private var hovering = false
    @State private var renaming = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var missing: Bool { record.isFileLike && !FileManager.default.fileExists(atPath: record.value) }
    private var canEnlarge: Bool {
        record.isFileLike && !missing && [.image, .gif, .video, .music].contains(LibraryContentType.fileType(record.value))
    }
    private var tags: [String] {
        record.tags.split(whereSeparator: { $0 == "," || $0 == ";" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private var subtitle: String {
        switch record.kind {
        case "contact": return [record.value, record.email, record.company].filter { !$0.isEmpty }.joined(separator: "  \u{00B7}  ")
        case "link": return URL(string: record.value)?.host ?? record.value
        default: return (record.value as NSString).lastPathComponent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .frame(height: 150).frame(maxWidth: .infinity).clipped()
                .overlay(alignment: .topLeading) { checkbox.padding(8) }
                .overlay(alignment: .topTrailing) { if hovering { actionRow.padding(8) } }
                .overlay(alignment: .bottomTrailing) {
                    if canEnlarge {
                        Button(action: onEnlarge) {
                            Image(systemName: [.video, .music].contains(LibraryContentType.fileType(record.value)) ? "play.fill" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 28, height: 28).background(Circle().fill(Color.black.opacity(0.62)))
                        }.buttonStyle(.plain).help("Show this larger").padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                if renaming {
                    TextField("Name", text: $draft)
                        .textFieldStyle(.roundedBorder).font(.system(size: 13, weight: .semibold))
                        .focused($focused)
                        .onSubmit { finishRename(save: true) }
                        .onExitCommand { finishRename(save: false) }
                } else {
                    Text(record.title.isEmpty ? "Untitled" : record.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
                        .help("Double-click to rename")
                        .onTapGesture(count: 2) { beginRename() }
                }
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if missing { Text("File not found").font(.system(size: 10)).foregroundStyle(.orange) }
                HStack(spacing: 6) {
                    Text(record.collection).font(.system(size: 10, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Butter.butter, in: Capsule())
                }
                TagStrip(tags: tags)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Butter.coral : Color.secondary.opacity(0.22), lineWidth: isSelected ? 2 : 1))
        .shadow(color: .black.opacity(hovering ? 0.14 : 0.05), radius: hovering ? 8 : 3, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onHover { hovering = $0 }
        .onTapGesture { if !renaming { onEdit() } }
        .contextMenu { menuItems }
    }

    // MARK: Preview

    @ViewBuilder private var preview: some View {
        if record.kind == "contact" {
            ZStack {
                Color(nsColor: .textBackgroundColor)
                if let photo = record.photo, let image = NSImage(contentsOfFile: photo) {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: 96, height: 96).clipShape(Circle())
                } else {
                    Circle().fill(Butter.butter).frame(width: 96, height: 96)
                        .overlay(Text(initials).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Butter.coral))
                }
            }
        } else if record.kind == "link" {
            ZStack {
                Color(nsColor: .textBackgroundColor)
                VStack(spacing: 8) {
                    WebsiteIcon(url: record.value, title: record.title, size: 56)
                    Text(URL(string: record.value)?.host ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        } else if missing {
            ZStack {
                Color(nsColor: .textBackgroundColor)
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34)).foregroundStyle(.orange)
            }
        } else {
            QuickLookThumbnailView(path: record.value)
                .hoverEnlarge(path: [.image, .gif, .video, .pdf, .sheet, .word, .slides, .document].contains(LibraryContentType.fileType(record.value)) ? record.value : nil)
        }
    }

    private var initials: String {
        let letters = record.title.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private var checkbox: some View {
        Button(action: onToggle) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3).foregroundStyle(isSelected ? Butter.coral : Color.secondary)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain).opacity(hovering || isSelected ? 1 : 0.55)
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack(spacing: 4) {
            tile("pencil", "Rename") { beginRename() }
            tile("bolt.fill", "Make a shortcut") { onShortcut() }
            Menu { menuItems } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private func tile(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28) }
            .buttonStyle(.plain).background(.ultraThinMaterial, in: Circle()).help(help)
    }

    @ViewBuilder private var menuItems: some View {
        Button { beginRename() } label: { Label("Rename", systemImage: "textformat") }
        Button { onShortcut() } label: { Label("Make a shortcut", systemImage: "bolt.fill") }
        Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
        Divider()
        if record.kind == "link", let url = URL(string: record.value) {
            Button { NSWorkspace.shared.open(url) } label: { Label("Open link", systemImage: "safari") }
            Button { onCopy(record.value) } label: { Label("Copy link", systemImage: "doc.on.doc") }
        }
        if record.isFileLike {
            if DocText.isViewable(record.value) {
                Button { onOpenDocument(URL(fileURLWithPath: record.value)) } label: { Label("Open in the Document Viewer", systemImage: "doc.richtext") }.disabled(missing)
            }
            Button { NSWorkspace.shared.open(URL(fileURLWithPath: record.value)) } label: { Label("Open file", systemImage: "arrow.up.forward.app") }.disabled(missing)
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.value)]) } label: { Label("Show in Finder", systemImage: "folder") }.disabled(missing)
            Button { onCopy(record.value) } label: { Label("Copy path", systemImage: "doc.on.doc") }
        }
        if record.kind == "contact" {
            Button { onCopy(record.value) } label: { Label("Copy mobile number", systemImage: "doc.on.doc") }.disabled(record.value.isEmpty)
            if !record.email.isEmpty { Button { onCopy(record.email) } label: { Label("Copy email", systemImage: "envelope") } }
        }
        if !collections.isEmpty {
            Menu {
                ForEach(collections, id: \.self) { name in Button(name) { onMove(name) } }
            } label: { Label("Move to", systemImage: "folder.badge.gearshape") }
        }
        Divider()
        Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
    }

    private func beginRename() {
        draft = record.title
        renaming = true
        DispatchQueue.main.async { focused = true }
    }

    private func finishRename(save: Bool) {
        renaming = false
        let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if save, !clean.isEmpty, clean != record.title { onRename(clean) }
    }
}
