// Tags: a few words like Personal, Safe, Work, Client and Stealth (and your own), each with its own colour.
// Used on shortcuts and collection items, in the preview, and in the Database Organizer. Searching finds them everywhere.
import SwiftUI

enum KeyDoTags {
    static let defaults = ["Personal", "Safe", "Work", "Client", "Stealth"]
    private static let customKey = "keydoCustomTags"

    static var custom: [String] {
        get { UserDefaults.standard.stringArray(forKey: customKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: customKey) }
    }

    /// Defaults first, then the ones you made.
    static var known: [String] { defaults + custom.filter { name in !defaults.contains { $0.caseInsensitiveCompare(name) == .orderedSame } } }

    /// The spelling already known for a tag (so "work" and "Work" are one tag), or the cleaned new one.
    static func canonical(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "#,;")))
        guard !clean.isEmpty else { return "" }
        if let match = known.first(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) { return match }
        return String(clean.prefix(20))
    }

    /// Remembers a tag you typed so it is offered next time.
    static func remember(_ tag: String) {
        guard !tag.isEmpty, !known.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
        custom = custom + [tag]
    }

    /// "work, client" or "work client" into ["Work", "Client"], without repeats.
    static func parse(_ text: String) -> [String] {
        var result: [String] = []
        for piece in text.split(whereSeparator: { ",;\n".contains($0) }) {
            let tag = canonical(String(piece))
            if !tag.isEmpty, !result.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { result.append(tag) }
        }
        return result
    }

    static func join(_ tags: [String]) -> String { tags.joined(separator: ", ") }

    private static let customColours: [Color] = [
        Color(red: 0.55, green: 0.36, blue: 0.85), Color(red: 0.0, green: 0.6, blue: 0.6), Color(red: 0.8, green: 0.25, blue: 0.25),
        Color(red: 0.4, green: 0.45, blue: 0.9), Color(red: 0.6, green: 0.4, blue: 0.2), Color(red: 0.85, green: 0.7, blue: 0.1)
    ]

    static func colour(_ tag: String) -> Color {
        switch tag.lowercased() {
        case "personal": return Color(red: 0.92, green: 0.35, blue: 0.62)
        case "safe": return Color(red: 0.2, green: 0.65, blue: 0.4)
        case "work": return Color(red: 0.2, green: 0.45, blue: 0.85)
        case "client": return Color(red: 0.95, green: 0.55, blue: 0.15)
        case "stealth": return Color(red: 0.28, green: 0.3, blue: 0.36)
        default:
            var hash = 5381
            for scalar in tag.lowercased().unicodeScalars { hash = (hash &* 33 &+ Int(scalar.value)) & 0xFFFFFF }
            return customColours[hash % customColours.count]
        }
    }
}

extension Clip {
    /// Everything a search looks at besides the key, name and text: extra words and tags.
    var searchWords: String { [keywords ?? "", (tags ?? []).joined(separator: " ")].filter { !$0.isEmpty }.joined(separator: " ") }
    func hasTag(_ tag: String) -> Bool { (tags ?? []).contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
}

// MARK: - Views

struct TagChip: View {
    let tag: String
    var filled = true
    var small = false
    var onRemove: (() -> Void)? = nil

    var body: some View {
        let colour = KeyDoTags.colour(tag)
        HStack(spacing: 3) {
            Text(tag).font(.system(size: small ? 9.5 : 11, weight: .semibold)).lineLimit(1)
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain).help("Remove \(tag)")
            }
        }
        .foregroundStyle(filled ? Color.white : colour)
        .padding(.horizontal, small ? 6 : 8).padding(.vertical, small ? 2 : 3)
        .background(filled ? colour : colour.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(colour.opacity(filled ? 0 : 0.6), lineWidth: 1))
        .fixedSize()
    }
}

/// Small row of tags for a card.
struct TagStrip: View {
    let tags: [String]
    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(tags.prefix(3), id: \.self) { TagChip(tag: $0, small: true) }
                if tags.count > 3 { Text("+\(tags.count - 3)").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Add, remove and change tags: tap the tags you want, or type a new one.
struct TagEditor: View {
    @Binding var tags: [String]
    var onChange: ([String]) -> Void = { _ in }
    @State private var draft = ""
    @State private var version = 0

    private func set(_ list: [String]) { tags = list; onChange(list) }

    private func toggle(_ tag: String) {
        if let index = tags.firstIndex(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { var list = tags; list.remove(at: index); set(list) }
        else { set(tags + [tag]) }
    }

    private func addDraft() {
        for tag in KeyDoTags.parse(draft) {
            KeyDoTags.remember(tag)
            if !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { set(tags + [tag]) }
        }
        draft = ""; version += 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    Image(systemName: "tag.fill").font(.caption).foregroundStyle(.secondary)
                    ForEach(KeyDoTags.known + tags.filter { t in !KeyDoTags.known.contains { $0.caseInsensitiveCompare(t) == .orderedSame } }, id: \.self) { tag in
                        let on = tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
                        Button { toggle(tag) } label: { TagChip(tag: tag, filled: on) }.buttonStyle(.plain)
                            .help(on ? "Remove the tag \(tag)" : "Add the tag \(tag)")
                    }
                    TextField("New tag", text: $draft).textFieldStyle(.roundedBorder).frame(width: 100).controlSize(.small).onSubmit { addDraft() }
                    Button("Add") { addDraft() }.controlSize(.small).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.vertical, 2)
            }
            .id(version)
        }
    }
}

/// A row of tags to filter by, with how many items have each.
struct TagFilterBar: View {
    @Binding var selection: String
    let counts: [(tag: String, count: Int)]

    var body: some View {
        if !counts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    Image(systemName: "tag").font(.caption).foregroundStyle(.secondary)
                    Button { selection = "" } label: {
                        Text("All tags").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(selection.isEmpty ? Color.gray.opacity(0.35) : Color.gray.opacity(0.12), in: Capsule())
                    }.buttonStyle(.plain)
                    ForEach(counts, id: \.tag) { row in
                        Button { selection = selection.caseInsensitiveCompare(row.tag) == .orderedSame ? "" : row.tag } label: {
                            HStack(spacing: 4) {
                                TagChip(tag: row.tag, filled: selection.caseInsensitiveCompare(row.tag) == .orderedSame)
                                Text("\(row.count)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    static func counts(_ clips: [Clip]) -> [(tag: String, count: Int)] {
        var map: [String: Int] = [:]
        for clip in clips { for tag in clip.tags ?? [] { map[tag, default: 0] += 1 } }
        return map.map { (tag: $0.key, count: $0.value) }.sorted { $0.count == $1.count ? $0.tag < $1.tag : $0.count > $1.count }
    }
}
