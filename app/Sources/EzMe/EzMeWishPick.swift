// "Pick a wish from a collection when the app runs", the way WishBuilder does it.
// A box holds {{wish:HBD wishes/$wish}}. The person types a shortcut (ss10), a number, a few words, or picks from a list,
// and the box shows that shortcut's full text.
import SwiftUI

@MainActor enum WishPick {
    static func plain(_ key: String) -> String {
        key.lowercased().replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: " ", with: "")
    }

    /// "HBD wishes/$wish" gives the collection and the variable that holds the choice.
    static func parse(_ inner: String) -> (collection: String, variable: String)? {
        guard inner.lowercased().hasPrefix("wish:") else { return nil }
        let rest = String(inner.dropFirst("wish:".count)).trimmingCharacters(in: .whitespaces)
        let parts = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        guard let collection = parts.first, !collection.isEmpty else { return nil }
        var variable = parts.count > 1 ? parts[1] : ""
        if variable.hasPrefix("$") { variable.removeFirst() }
        if variable.isEmpty { variable = collection }
        return (collection, TemplateFill.normal(variable))
    }

    static func token(collection: String, variable: String? = nil) -> String {
        "{{wish:\(collection)/$\(variable ?? TemplateFill.normal(collection))}}"
    }

    /// The collection a spoken name most likely means ("birthday wishes" can mean "HBD wishes").
    static func canonicalCollection(_ spoken: String) -> String {
        let names = AppDesignContext.shared.collections
        let said = spoken.trimmingCharacters(in: .whitespaces)
        if let exact = names.first(where: { $0.caseInsensitiveCompare(said) == .orderedSame }) { return exact }
        let words = said.lowercased().split(separator: " ").map(String.init).filter { !["wishes", "wish", "messages", "shortcuts", "collection", "the", "from", "my"].contains($0) }
        guard !words.isEmpty else { return said }
        let scored = names.map { name -> (String, Int) in
            let lower = name.lowercased()
            return (name, words.filter { lower.contains($0) }.count)
        }
        if let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 { return best.0 }
        return said
    }

    static func clips(in collection: String) -> [Clip] {
        AppDesignContext.shared.clips
            .filter { clip in clip.allGroups.contains { $0.caseInsensitiveCompare(collection) == .orderedSame } }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    /// A shortcut named by its key, its number in the collection, its name, or words from its text.
    static func find(_ query: String, in collection: String) -> Clip? {
        let all = clips(in: collection)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !all.isEmpty else { return nil }
        let compact = plain(q)
        if let hit = all.first(where: { plain($0.key) == compact }) { return hit }
        var stripped = q.lowercased()
        for word in ["wish number", "number", "option", "wish", "no.", "no", "#"] where stripped.hasPrefix(word + " ") || stripped.hasPrefix(word) && stripped.dropFirst(word.count).first?.isNumber == true {
            stripped = String(stripped.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        if let number = Int(stripped), number >= 1, number <= all.count { return all[number - 1] }
        if let hit = all.first(where: { $0.name.caseInsensitiveCompare(q) == .orderedSame }) { return hit }
        guard q.count >= 3 else { return nil }
        return all.first(where: { $0.name.localizedCaseInsensitiveContains(q) }) ?? all.first(where: { $0.text.localizedCaseInsensitiveContains(q) })
            ?? PickerRank.clips(q, in: collection, limit: 1).first
    }

    /// Only a key or a number in range, so ordinary words in a typed command are never taken for a wish.
    static func findStrict(_ query: String, in collection: String) -> Clip? {
        let all = clips(in: collection)
        let compact = plain(query)
        guard !compact.isEmpty else { return nil }
        if let hit = all.first(where: { plain($0.key) == compact }) { return hit }
        if compact.count <= 3, let number = Int(compact), number >= 1, number <= all.count { return all[number - 1] }
        return nil
    }

    /// A shortcut key said somewhere in a sentence ("send ss10 to Rahul"). Spaces are ignored so "s s 10" works.
    static func spotted(in sentence: String, collection: String) -> Clip? {
        let collapsed = plain(sentence)
        let all = clips(in: collection).filter { plain($0.key).count >= 3 && plain($0.key).contains(where: { $0.isNumber }) }
        if let hit = all.filter({ collapsed.contains(plain($0.key)) }).max(by: { plain($0.key).count < plain($1.key).count }) { return hit }
        let lower = sentence.lowercased()
        if let regex = try? NSRegularExpression(pattern: "(?:wish|number|option|no\\.?)\\s*#?\\s*(\\d{1,3})"),
           let match = regex.firstMatch(in: lower, range: NSRange(location: 0, length: (lower as NSString).length)) {
            return find((lower as NSString).substring(with: match.range(at: 1)), in: collection)
        }
        return nil
    }
}

/// The form row for a wish box: it starts on the first wish; type a key, a number or words to narrow, or open the list.
struct WishChooserRow: View {
    var field: DesignField
    @Binding var text: String
    @State private var open = false

    private var collection: String { field.collection ?? "" }
    private var chosen: Clip? { WishPick.find(text, in: collection) }
    /// True while what is typed is exactly the chosen shortcut, so no short list is needed.
    private var settled: Bool { chosen.map { WishPick.plain($0.key) == WishPick.plain(text) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField(field.label + " (type a few letters, a shortcut like ss10, or a number)", text: $text)
                    .textFieldStyle(.roundedBorder).accessibilityLabel(field.label).help(field.label)
                    .onSubmit { if !settled, let best = PickerRank.clips(text, in: collection, limit: 1).first { text = best.key } }
                Button { open = true } label: { Label("Choose", systemImage: "list.bullet.rectangle") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .popover(isPresented: $open, arrowEdge: .bottom) {
                        WishListView(collection: collection) { clip in text = clip.key; open = false }.frame(width: 380, height: 420)
                    }
            }
            if !settled && !text.trimmingCharacters(in: .whitespaces).isEmpty {
                let near = PickerRank.clips(text, in: collection, limit: 5)
                if near.isEmpty {
                    Text("No shortcut in \(collection) is near \u{201C}\(text)\u{201D}. Press Choose to look.").font(.system(size: 11)).foregroundStyle(.orange)
                } else {
                    PickerSuggestionList {
                        ForEach(near, id: \.id) { clip in
                            PickerSuggestionRow(title: clip.key, detail: clip.text.replacingOccurrences(of: "\n", with: " ")) { text = clip.key }
                        }
                    }
                }
            }
            if let chosen, settled || text.trimmingCharacters(in: .whitespaces).isEmpty == false {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chosen.key).font(.system(size: 11, weight: .bold)).foregroundStyle(Butter.coral)
                        Text(chosen.text).font(.system(size: 12)).foregroundStyle(Butter.cocoa).lineLimit(4)
                    }
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.08)))
            }
        }
    }
}

struct WishListView: View {
    var collection: String
    var onPick: (Clip) -> Void
    @State private var query = ""

    var body: some View {
        let all = WishPick.clips(in: collection)
        // Only the first few until something is typed; then the ones nearest to the letters typed.
        let shown = PickerRank.clips(query, in: collection, limit: 30)
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Type to search \(collection)", text: $query).textFieldStyle(.plain)
                Text(query.isEmpty ? "\(all.count) in all" : "\(shown.count) near").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(10)
            Divider()
            if all.isEmpty {
                Text("No shortcuts in \(collection) yet.").font(.system(size: 12)).foregroundStyle(.secondary).padding(16)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(shown, id: \.id) { clip in
                            Button { onPick(clip) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(clip.key).font(.system(size: 12, weight: .bold)).foregroundStyle(Butter.coral)
                                    Text(clip.text).font(.system(size: 12)).foregroundStyle(Butter.cocoa).lineLimit(3).multilineTextAlignment(.leading)
                                }
                                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Butter.honey.opacity(0.6), lineWidth: 1))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }
}
