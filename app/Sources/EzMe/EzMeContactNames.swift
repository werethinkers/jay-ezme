// How a contact's name is read: titles such as Dr. or Shri are not part of the name, a dash ends the name and starts extra details,
// and a name is never longer than 15 characters.
import Foundation

enum ContactNames {
    static let maxLength = 15

    /// Respectful words that come before a name. They are not the name.
    static let titles: Set<String> = [
        "dr", "mr", "mrs", "ms", "miss", "mx", "shri", "shree", "sri", "shrimati", "smt", "md", "er", "prof",
        "mohammad", "mohammed", "muhammad", "mohamad", "mohd"
    ]

    private static let dashes = CharacterSet(charactersIn: "-\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}\u{2015}\u{2212}")

    private static func bare(_ token: String) -> String { token.lowercased().trimmingCharacters(in: CharacterSet.letters.inverted) }

    struct Result {
        var first: String
        var last: String
        var full: String
        /// What came after a dash or a bar, and the full name when it had to be shortened.
        var extra: String
    }

    static func normalize(first: String, last: String, full: String) -> Result {
        var source = full.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty { source = [first, last].filter { !$0.isEmpty }.joined(separator: " ") }
        let original = source
        var extra: [String] = []

        // A bar or a dash ends the name; the rest is extra detail.
        for cut in [CharacterSet(charactersIn: "|"), dashes] {
            if let range = source.rangeOfCharacter(from: cut) {
                let detail = String(source[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines.union(dashes).union(CharacterSet(charactersIn: "|")))
                if !detail.isEmpty { extra.append(detail) }
                source = String(source[..<range.lowerBound])
            }
        }

        source = source.replacingOccurrences(of: "(?i)^(dr|mr|mrs|ms|er|md|mohd|prof)\\.(?=\\S)", with: "$1. ", options: .regularExpression)
        var tokens = source.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",;:")) }.filter { !$0.isEmpty }
        // Leading titles are dropped, unless nothing else is left.
        var stripped = tokens
        while let head = stripped.first, titles.contains(bare(head)), stripped.count > 1 { stripped.removeFirst() }
        tokens = stripped
        tokens = tokens.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.filter { !$0.isEmpty }

        guard var firstName = tokens.first else { return Result(first: first, last: last, full: original, extra: extra.joined(separator: " · ")) }
        let surname = tokens.dropFirst().joined(separator: " ")
        var shown = tokens.joined(separator: " ")
        if shown.count > maxLength {
            if firstName.count <= maxLength - 2, let initial = surname.first { shown = firstName + " " + String(initial) }
            else { shown = String(firstName.prefix(maxLength)) }
            extra.append("Full name: " + tokens.joined(separator: " "))
        }
        if firstName.count > maxLength { firstName = String(firstName.prefix(maxLength)) }
        return Result(first: firstName, last: surname, full: shown, extra: extra.joined(separator: " · "))
    }
}
