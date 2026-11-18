// Picking a wish, a record or a media item from a collection while an app runs.
//  - The first item is chosen already (the default); typing or saying something else swaps it.
//  - Typing shows only the few items that come near the letters typed, never the whole collection.
//  - Voice takes the best match, even when the words said are only part of the name or the text.
import SwiftUI
import AppKit

@MainActor enum PickerRank {
    private static let filler: Set<String> = ["the", "and", "for", "with", "wish", "wishes", "number", "option", "please", "from", "this", "that", "one"]

    static func tokens(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 && !filler.contains($0) }
    }

    /// How well one item (its key, name and text) fits what was typed or said. Zero means it does not fit.
    private static func score(query: String, compact: String, tokens: [String], key: String, name: String, text: String) -> Int {
        let plainKey = WishPick.plain(key)
        let lowerName = name.lowercased()
        let lowerText = text.lowercased()
        var total = 0
        if !compact.isEmpty {
            if plainKey == compact { total += 100 } else if plainKey.hasPrefix(compact) { total += 70 } else if compact.count >= 2, plainKey.contains(compact) { total += 45 }
        }
        if lowerName == query { total += 90 } else if !query.isEmpty, lowerName.hasPrefix(query) { total += 65 } else if query.count >= 2, lowerName.contains(query) { total += 40 }
        var hits = 0
        for token in tokens {
            if lowerName.contains(token) || plainKey.contains(token) { total += 12; hits += 1 }
            else if lowerText.contains(token) { total += 5; hits += 1 }
        }
        if !tokens.isEmpty, hits == tokens.count { total += 15 }
        return total
    }

    /// Shortcuts of a collection that come near the query, best first. An empty query gives the first few in order.
    static func clips(_ query: String, in collection: String, limit: Int = 6) -> [Clip] {
        let all = WishPick.clips(in: collection)
        let said = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !said.isEmpty else { return Array(all.prefix(limit)) }
        if let number = Int(said), number >= 1, number <= all.count, said.count <= 3 {
            let named = all[number - 1]
            return [named] + all.filter { $0.id != named.id && WishPick.plain($0.key).hasPrefix(said) }.prefix(limit - 1)
        }
        let compact = WishPick.plain(said)
        let words = tokens(said)
        var scored: [(clip: Clip, score: Int, order: Int)] = []
        for (order, clip) in all.enumerated() {
            let value = score(query: said, compact: compact, tokens: words, key: clip.key, name: clip.name, text: String(clip.text.prefix(500)))
            if value > 0 { scored.append((clip, value, order)) }
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }.prefix(limit).map { $0.clip }
    }

    static func records(_ query: String, in collection: String, limit: Int = 6) -> [CollectionRecord] {
        let all = AppDesignContext.shared.records.filter { $0.collection.caseInsensitiveCompare(collection) == .orderedSame }
        let said = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !said.isEmpty else { return Array(all.prefix(limit)) }
        let compact = WishPick.plain(said)
        let words = tokens(said)
        var scored: [(record: CollectionRecord, score: Int, order: Int)] = []
        for (order, record) in all.enumerated() {
            let extra = record.values.values.joined(separator: " ")
            let value = score(query: said, compact: compact, tokens: words, key: record.alias, name: record.name, text: String(extra.prefix(300)))
            if value > 0 { scored.append((record, value, order)) }
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }.prefix(limit).map { $0.record }
    }

    static func record(matching value: String, in collection: String) -> CollectionRecord? {
        let all = AppDesignContext.shared.records.filter { $0.collection.caseInsensitiveCompare(collection) == .orderedSame }
        let said = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !said.isEmpty else { return nil }
        return all.first { ($0.alias.isEmpty ? $0.name : $0.alias).lowercased() == said || $0.name.lowercased() == said }
    }
}

/// The boxes that take their value from a collection start on its first item, so the app always has something to make.
@MainActor enum DesignDefaults {
    static func fill(_ fields: [DesignField], into values: inout [String: String]) {
        for field in fields where (values[field.key] ?? "").isEmpty && field.defaultValue.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let collection = field.collection, !collection.isEmpty else { continue }
            switch field.kind {
            case .wish:
                if let first = WishPick.clips(in: collection).first { values[field.key] = first.key }
            case .choice:
                if let first = AppDesignContext.shared.records.first(where: { $0.collection.caseInsensitiveCompare(collection) == .orderedSame }) {
                    values[field.key] = first.alias.isEmpty ? first.name : first.alias
                }
            case .image:
                if let first = MediaFinder.search("", in: collection, limit: 1).first { values[field.key] = first.key }
            default: break
            }
        }
    }
}

extension DesignDefaults {
    /// The same, for values keyed by the plain (normalised) name that rendering uses.
    static func fillMerged(_ fields: [DesignField], into merged: inout [String: String]) {
        var keyed: [String: String] = [:]
        for field in fields { keyed[field.key] = merged[TemplateFill.normal(field.key)] ?? "" }
        fill(fields, into: &keyed)
        for field in fields {
            if let value = keyed[field.key], !value.isEmpty { merged[TemplateFill.normal(field.key)] = value }
        }
    }
}

/// One line of the short list under a box.
struct PickerSuggestionRow: View {
    var title: String
    var detail: String
    var clip: Clip? = nil
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 8) {
                if let clip, SourceMedia.hasMedia(clip) { MediaClipThumb(clip: clip).frame(width: 34, height: 34) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(Butter.coral).lineLimit(1)
                    if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundStyle(Butter.cocoa).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A short list that follows what is typed in a box.
struct PickerSuggestionList<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Butter.honey.opacity(0.7), lineWidth: 1))
    }
}

/// A box that takes one record of a collection (a customer, a company): type to narrow, or open the short list.
struct RecordChooserRow: View {
    var field: DesignField
    @Binding var text: String
    @State private var open = false

    private var collection: String { field.collection ?? "" }
    private var current: CollectionRecord? { PickerRank.record(matching: text, in: collection) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField(field.label + " (type a few letters)", text: $text).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(field.label).help(field.label)
                    .onSubmit { if current == nil, let best = PickerRank.records(text, in: collection, limit: 1).first { text = best.alias.isEmpty ? best.name : best.alias } }
                Button { open = true } label: { Label("Choose", systemImage: "list.bullet") }.buttonStyle(.bordered).controlSize(.small)
                    .popover(isPresented: $open, arrowEdge: .bottom) {
                        RecordListView(collection: collection) { record in text = record.alias.isEmpty ? record.name : record.alias; open = false }.frame(width: 320, height: 360)
                    }
            }
            if let current {
                Label(current.name, systemImage: "checkmark.circle.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
            } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                let near = PickerRank.records(text, in: collection, limit: 5)
                if near.isEmpty {
                    Text("Nothing in \(collection) is near \u{201C}\(text)\u{201D}.").font(.system(size: 11)).foregroundStyle(.orange)
                } else {
                    PickerSuggestionList {
                        ForEach(near, id: \.id) { record in
                            PickerSuggestionRow(title: record.name, detail: record.alias) { text = record.alias.isEmpty ? record.name : record.alias }
                        }
                    }
                }
            }
        }
    }
}

struct RecordListView: View {
    var collection: String
    var onPick: (CollectionRecord) -> Void
    @State private var query = ""

    var body: some View {
        let shown = PickerRank.records(query, in: collection, limit: 30)
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Type to search \(collection)", text: $query).textFieldStyle(.plain)
            }
            .padding(10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shown, id: \.id) { record in
                        PickerSuggestionRow(title: record.name, detail: record.alias) { onPick(record) }
                    }
                    if query.isEmpty { Text("Showing the first few. Type to find others.").font(.system(size: 11)).foregroundStyle(.secondary).padding(8) }
                }
            }
        }
    }
}
