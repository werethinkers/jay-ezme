// Voice commands that name the box they are about: "make the name red", "change title to Happy Birthday",
// "amount bold", "background of the heading yellow". The named box is selected first, then the rest is run as usual.
import Foundation

enum DesignVoiceTarget {
    struct Hit { var slot: TemplateSlot; var rest: String; var original: String }

    /// Commands that never name a box to work on.
    private static let skip = try? NSRegularExpression(
        pattern: "^(?:please\\s+)?(?:add|insert|create|new|replace|rename|call|use|put|go|page|variable|set variable|save|release|publish|try|preview|undo|output|format|command|select|choose|pick|click|next|previous|first|last|design|edit)\\b",
        options: [.caseInsensitive])

    static func split(_ text: String) -> [String] {
        text.replacingOccurrences(of: ";", with: " then ").components(separatedBy: " then ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?\n")) }.filter { !$0.isEmpty }
    }

    private static func spoken(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").lowercased().trimmingCharacters(in: .whitespaces)
    }

    static func find(_ sentence: String, slots: [TemplateSlot]) -> Hit? {
        let ns = sentence as NSString
        if let skip, skip.firstMatch(in: sentence, range: NSRange(location: 0, length: ns.length)) != nil { return nil }
        if sentence.range(of: "\\b(variable|function|formula|collection|shortcut|dropdown|drop down|called|named|type)\\b", options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        let ordered = slots.filter { spoken($0.key).count >= 2 }.sorted { spoken($0.key).count > spoken($1.key).count }
        for slot in ordered {
            let words = NSRegularExpression.escapedPattern(for: spoken(slot.key)).replacingOccurrences(of: "\\ ", with: "\\s+")
            let pattern = "(?:\\b(?:of|for|on|in)\\s+)?(?:\\bthe\\s+)?(?<![a-z0-9])" + words + "(?![a-z0-9])(?:\\s+(?:box|field|text|label))?"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let found = regex.firstMatch(in: sentence, range: NSRange(location: 0, length: ns.length)) else { continue }
            var rest = ns.replacingCharacters(in: found.range, with: " ")
            rest = rest.split(separator: " ").joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.:"))
            return Hit(slot: slot, rest: rest, original: sentence)
        }
        return nil
    }

    /// "change name to Rahul", "title says Happy Birthday", "photo ss10": puts a value into the named box.
    static func setAction(_ hit: Hit) -> DesignAction? {
        let words = NSRegularExpression.escapedPattern(for: spoken(hit.slot.key)).replacingOccurrences(of: "\\ ", with: "\\s+")
        let pattern = "(?:^|\\b)(?:(?:change|set|make|update|write|put|type|edit)\\s+)?(?:the\\s+)?" + words
            + "(?:\\s+(?:box|field|text|value|content))?\\s*(?:to|as|is|says?|equals|=|:)?\\s+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let found = regex.firstMatch(in: hit.original, range: NSRange(location: 0, length: (hit.original as NSString).length)),
              found.numberOfRanges > 1 else { return nil }
        let value = (hit.original as NSString).substring(with: found.range(at: 1)).trimmingCharacters(in: CharacterSet(charactersIn: " ,.\u{201C}\u{201D}\""))
        guard !value.isEmpty else { return nil }
        switch hit.slot.kind {
        case .image: return .imageFrom(value)
        case .logo: return nil
        case .text:
            let content = (hit.slot.content ?? "").trimmingCharacters(in: .whitespaces)
            if content.hasPrefix("{{"), content.hasSuffix("}}"), content.filter({ $0 == "{" }).count == 2 {
                let name = String(content.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, !name.contains(":"), !name.hasPrefix("@") { return .variable(name, value) }
            }
            return .setText(value)
        }
    }
}
