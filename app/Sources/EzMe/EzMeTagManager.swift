// Manage tags: see every tag in use across KeyDo (Recent Files, Database Organizer records and your own list),
// rename or delete one and the change is made everywhere those are kept.
import SwiftUI

struct TagManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var files = RecentFileStore.shared
    @ObservedObject private var database = MyDatabaseStore.shared
    @State private var renaming: String?
    @State private var draft = ""
    @State private var newTag = ""
    @State private var search = ""

    private var counts: [(tag: String, count: Int)] {
        var map: [String: Int] = [:]
        func add(_ tag: String) { if let key = map.keys.first(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { map[key, default: 0] += 1 } else { map[tag] = 1 } }
        for name in KeyDoTags.known where map[name] == nil { map[name] = 0 }
        for file in files.items { file.tags.forEach(add) }
        for record in database.records { KeyDoTags.parse(record.tags).forEach(add) }
        let text = search.trimmingCharacters(in: .whitespaces)
        return map.filter { text.isEmpty || $0.key.localizedCaseInsensitiveContains(text) }
            .map { (tag: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Manage tags").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).tint(Butter.coral)
            }
            Text("Tags are shared by Recent Files and Database Organizer records. Renaming or deleting a tag here changes it everywhere those are kept. Shortcut tags are not included yet.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("Search tags", text: $search).textFieldStyle(.roundedBorder)
                TextField("New tag", text: $newTag).textFieldStyle(.roundedBorder).frame(width: 140).onSubmit { addTag() }
                Button("Add") { addTag() }.buttonStyle(.bordered)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(counts, id: \.tag) { item in row(item.tag, item.count) }
                }
            }
            .frame(height: 320)
        }
        .padding(22).frame(width: 520)
    }

    private func row(_ tag: String, _ count: Int) -> some View {
        let isDefault = KeyDoTags.defaults.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        return HStack(spacing: 8) {
            if renaming == tag {
                TextField("New name", text: $draft).textFieldStyle(.roundedBorder).onSubmit { applyRename(tag) }
                Button("Save") { applyRename(tag) }.buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.small)
                Button("Cancel") { renaming = nil }.buttonStyle(.bordered).controlSize(.small)
            } else {
                TagChip(tag: tag)
                Text("\(count) item\(count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !isDefault {
                    Button("Rename") { renaming = tag; draft = tag }.buttonStyle(.bordered).controlSize(.small)
                    Button("Delete", role: .destructive) { change(tag, to: nil) }.buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .padding(8).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func addTag() {
        let tag = KeyDoTags.canonical(newTag)
        if !tag.isEmpty { KeyDoTags.remember(tag) }
        newTag = ""
        files.objectWillChange.send()
    }

    private func applyRename(_ old: String) {
        let new = KeyDoTags.canonical(draft)
        renaming = nil
        guard !new.isEmpty, new != old else { return }
        change(old, to: new)
    }

    private func change(_ old: String, to new: String?) {
        KeyDoTags.custom = KeyDoTags.custom.compactMap { name in
            guard name.caseInsensitiveCompare(old) == .orderedSame else { return name }
            return new
        }
        if let new { KeyDoTags.remember(new) }
        files.renameTag(old, to: new)
        database.renameTag(old, to: new)
    }
}
