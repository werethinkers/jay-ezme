// Fills a published app's form from a spoken or typed sentence, on the Mac, without waiting for an AI call.
// "name Rahul amount 5000 message happy birthday" fills the three fields called Name, Amount and Message.
import Foundation

enum DesignVoiceFill {
    private static let connectors: Set<String> = ["is", "as", "to", "equals", "equal", "be", "set", "of", "the", "colon", "for", "with"]

    @MainActor static func options(for field: DesignField) -> [CollectionRecord] {
        AppDesignContext.shared.records.filter { $0.collection.caseInsensitiveCompare(field.collection ?? "") == .orderedSame }
    }

    /// Returns the values found in the sentence, keyed by field key. Image fields are filled from a shortcut name.
    @MainActor static func parse(_ sentence: String, fields: [DesignField]) -> [String: String] {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [:] }
        let lower = text.lowercased()
        let ns = lower as NSString
        struct Hit { var field: DesignField; var start: Int; var end: Int }
        var hits: [Hit] = []
        for field in fields {
            var names = Set([field.label.lowercased(), field.key.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")])
            names = names.filter { !$0.isEmpty }
            for name in names.sorted(by: { $0.count > $1.count }) {
                let pattern = "(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for: name).replacingOccurrences(of: "\\ ", with: "\\s+") + "(?![a-z0-9])"
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: lower, range: NSRange(location: 0, length: ns.length)) else { continue }
                if hits.contains(where: { $0.start < match.range.location + match.range.length && match.range.location < $0.end }) { continue }
                hits.append(Hit(field: field, start: match.range.location, end: match.range.location + match.range.length))
                break
            }
        }
        hits.sort { $0.start < $1.start }
        var result: [String: String] = [:]
        let original = text as NSString
        for (index, hit) in hits.enumerated() {
            let stop = index + 1 < hits.count ? hits[index + 1].start : original.length
            guard stop > hit.end else { continue }
            var words = original.substring(with: NSRange(location: hit.end, length: stop - hit.end))
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-\u{2013}\u{2014}\n"))
                .split(separator: " ").map(String.init)
            while let first = words.first, connectors.contains(first.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.:;"))) { words.removeFirst() }
            if index + 1 < hits.count, let last = words.last, ["and", "also", "then"].contains(last.lowercased()) { words.removeLast() }
            var value = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:"))
            guard !value.isEmpty else { continue }
            switch hit.field.kind {
            case .choice:
                let all = options(for: hit.field)
                if let match = all.first(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame || $0.alias.caseInsensitiveCompare(value) == .orderedSame })
                    ?? all.first(where: { value.lowercased().contains($0.name.lowercased()) || $0.name.lowercased().contains(value.lowercased()) }) {
                    value = match.alias.isEmpty ? match.name : match.alias
                } else { continue }
            case .wish:
                guard let clip = WishPick.find(value, in: hit.field.collection ?? "") else { continue }
                value = clip.key
            default: break
            }
            result[hit.field.key] = value
        }
        // A name from a pick-list said without its field name ("birthday card for Rahul") still fills the pick-list.
        for field in fields where field.kind == .choice && result[field.key] == nil {
            let found = options(for: field).filter { $0.name.count >= 3 && lower.contains($0.name.lowercased()) }.max { $0.name.count < $1.name.count }
            if let found { result[field.key] = found.alias.isEmpty ? found.name : found.alias }
        }
        // A shortcut said on its own ("ss10", "wish 3") fills the wish box even without its field name.
        for field in fields where field.kind == .wish && result[field.key] == nil {
            if let clip = WishPick.spotted(in: text, collection: field.collection ?? "") { result[field.key] = clip.key }
        }
        return result
    }

    /// When nothing was named, a short phrase goes into the first empty field of the right kind.
    static func firstEmpty(_ fields: [DesignField], values: [String: String]) -> DesignField? {
        fields.first { ($0.kind == .text || $0.kind == .long) && (values[$0.key] ?? "").isEmpty }
    }

    static func isMakeCommand(_ sentence: String) -> Bool {
        let t = sentence.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .!"))
        return ["make it", "make", "generate", "generate it", "create it", "done", "go", "press make", "submit"].contains(t)
    }
}
