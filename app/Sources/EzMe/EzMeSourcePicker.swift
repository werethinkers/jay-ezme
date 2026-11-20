// One picker for everything a box or form field can take from the library:
// category > collection > items, fields and shortcuts. Searchable. Media-only mode lists just pictures and videos.
import SwiftUI
import AppKit

enum SourceMedia {
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff", "bmp", "mp4", "mov", "m4v"]
    static func isMedia(_ path: String) -> Bool { extensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) }
    static func hasMedia(_ clip: Clip) -> Bool { clip.files.contains { isMedia($0) } }
}

struct SourcePickerButton: View {
    var title: String
    var symbol: String = "tray.full"
    var mediaOnly: Bool = false
    var onPick: (String) -> Void
    @State private var open = false

    var body: some View {
        Button { open = true } label: { Label(title, systemImage: symbol) }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                SourcePickerView(mediaOnly: mediaOnly) { value in
                    onPick(value)
                    open = false
                }
                .frame(width: 340, height: 440)
            }
    }
}

struct SourcePickerView: View {
    var mediaOnly: Bool
    var onPick: (String) -> Void
    @State private var query = ""
    @State private var expanded: Set<String> = []

    private var context: AppDesignContext { AppDesignContext.shared }

    private func clips(in name: String) -> [Clip] {
        context.clips.filter { clip in
            clip.allGroups.contains { $0.caseInsensitiveCompare(name) == .orderedSame } && (!mediaOnly || SourceMedia.hasMedia(clip))
        }
    }

    private func matches(_ text: String) -> Bool { query.isEmpty || text.localizedCaseInsensitiveContains(query) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(mediaOnly ? "Search pictures and videos" : "Search categories, collections, shortcuts", text: $query).textFieldStyle(.plain)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
            }
            .padding(10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let tree = context.collectionTree
                    if tree.isEmpty { Text("No collections yet.").font(.system(size: 12)).foregroundStyle(.secondary).padding(8) }
                    ForEach(tree) { group in categoryRow(group) }
                    shortcutsSection
                }
                .padding(8)
            }
        }
    }

    // MARK: Categories and collections

    @ViewBuilder private func categoryRow(_ group: CollectionGroup) -> some View {
        let names = group.names.filter { name in
            if query.isEmpty { return !mediaOnly || !clips(in: name).isEmpty || mediaRecords(in: name).isEmpty == false }
            return matches(name) || matches(group.category) || clips(in: name).contains { matches($0.key) || matches($0.name) || matches($0.searchWords) || matches(String($0.text.prefix(300))) } || context.records.contains { $0.collection.caseInsensitiveCompare(name) == .orderedSame && matches($0.name) }
        }
        if !names.isEmpty {
            let key = "cat:" + group.category
            row(group.category, symbol: "folder", count: names.count, open: isOpen(key)) { toggle(key) }
            if isOpen(key) {
                ForEach(names, id: \.self) { name in collectionRow(name).padding(.leading, 14) }
            }
        }
    }

    private func mediaRecords(in name: String) -> [CollectionRecord] {
        context.records.filter { $0.collection.caseInsensitiveCompare(name) == .orderedSame && $0.files.contains { SourceMedia.isMedia($0) } }
    }

    @ViewBuilder private func collectionRow(_ name: String) -> some View {
        let key = "col:" + name
        let shortcuts = clips(in: name)
        let records = context.records.filter { $0.collection.caseInsensitiveCompare(name) == .orderedSame }
        row(name, symbol: "square.stack.3d.up", count: shortcuts.count + records.count, open: isOpen(key)) { toggle(key) }
        if isOpen(key) {
            VStack(alignment: .leading, spacing: 2) {
                if !mediaOnly && !shortcuts.isEmpty {
                    leaf("Let the person pick a wish when the app runs", symbol: "list.bullet.rectangle") { onPick(WishPick.token(collection: name)) }
                }
                if !mediaOnly && !records.isEmpty {
                    let variable = TemplateFill.normal(name)
                    leaf("Choose when the app runs", symbol: "person.crop.circle.badge.questionmark") { onPick("{{@\(name)/$\(variable)/name}}") }
                    let fields = Array(Set(records.prefix(30).flatMap { $0.values.keys })).sorted()
                    ForEach(fields, id: \.self) { field in
                        leaf("Chosen \u{2192} \(field)", symbol: "tag") { onPick("{{@\(name)/$\(variable)/\(field)}}") }
                    }
                }
                ForEach(records.filter { r in
                    if mediaOnly { return r.files.contains { SourceMedia.isMedia($0) } }
                    return matches(r.name) || query.isEmpty || matches(name)
                }.prefix(60), id: \.id) { record in recordRow(name, record) }
                ForEach(shortcuts.filter { query.isEmpty || matches($0.key) || matches($0.name) || matches($0.searchWords) || matches(String($0.text.prefix(300))) || matches(name) }.prefix(80), id: \.id) { clip in shortcutLeaf(clip) }
            }
            .padding(.leading, 14)
        }
    }

    @ViewBuilder private func recordRow(_ collection: String, _ record: CollectionRecord) -> some View {
        let reference = record.alias.isEmpty ? record.name : record.alias
        let key = "rec:" + collection + "/" + record.id
        if mediaOnly {
            ForEach(record.files.filter { SourceMedia.isMedia($0) }, id: \.self) { path in
                leaf("\(record.name) \u{2192} \(URL(fileURLWithPath: path).lastPathComponent)", symbol: "photo") { onPick(path) }
            }
        } else {
            row(record.name, symbol: "person.crop.rectangle", count: record.values.count, open: isOpen(key)) { toggle(key) }
            if isOpen(key) {
                VStack(alignment: .leading, spacing: 2) {
                    leaf("Name", symbol: "textformat") { onPick("{{@\(collection)/\(reference)}}") }
                    ForEach(record.values.keys.sorted(), id: \.self) { field in
                        leaf(field, symbol: "tag") { onPick("{{@\(collection)/\(reference)/\(field)}}") }
                    }
                }
                .padding(.leading, 14)
            }
        }
    }

    // MARK: All shortcuts

    @ViewBuilder private var shortcutsSection: some View {
        let all = context.clips.filter { (!mediaOnly || SourceMedia.hasMedia($0)) && (query.isEmpty || matches($0.key) || matches($0.name) || matches($0.searchWords) || matches(String($0.text.prefix(300)))) }
        if !all.isEmpty {
            let key = "all"
            row("All shortcuts", symbol: "bolt", count: all.count, open: isOpen(key) || !query.isEmpty) { toggle(key) }
            if isOpen(key) || !query.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(all.prefix(120), id: \.id) { clip in shortcutLeaf(clip) }
                }
                .padding(.leading, 14)
            }
        }
    }

    private func shortcutLeaf(_ clip: Clip) -> some View {
        leaf(clip.key + (clip.name.isEmpty || clip.name == clip.key ? "" : "  \u{00B7}  " + clip.name), symbol: SourceMedia.hasMedia(clip) ? "photo" : "text.quote") {
            onPick(mediaOnly ? clip.key : (SourceMedia.hasMedia(clip) && clip.text.isEmpty ? clip.key : "{{shortcut:\(clip.key)}}"))
        }
    }

    // MARK: Rows

    private func isOpen(_ key: String) -> Bool { expanded.contains(key) || !query.isEmpty }
    private func toggle(_ key: String) { if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) } }

    private func row(_ title: String, symbol: String, count: Int, open: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold)).frame(width: 10)
                Image(systemName: symbol).foregroundStyle(Butter.coral)
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                Text("\(count)").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func leaf(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 14)
                Text(title).font(.system(size: 12)).lineLimit(1)
                Spacer()
            }
            .padding(.vertical, 3).padding(.horizontal, 4).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
