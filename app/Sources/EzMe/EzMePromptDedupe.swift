// Spoken and typed prompts often say the same thing twice: the speech engine repeats the last words, or a sentence is dictated again.
// These helpers remove the repeat. They only use Foundation so they are easy to test on their own.
import Foundation

enum PromptDedupe {
    /// Short words that are never meant twice in a row.
    private static let small: Set<String> = ["the", "a", "an", "to", "of", "and", "is", "in", "it", "i", "for", "on", "at", "we", "you", "my", "so", "but", "or"]

    static func key(_ word: String) -> String { String(word.lowercased().filter { $0.isLetter || $0.isNumber }) }

    /// Shortcuts, names, formulas and attachment labels are never touched.
    private static func isProtected(_ word: String) -> Bool {
        guard let first = word.first else { return true }
        if "#@=/\\[".contains(first) || word.contains("[") || word.contains("]") { return true }
        return key(word).isEmpty
    }

    /// Words or phrases said twice in a row become one. Returns the cleaned text and the phrases that were removed.
    static func collapse(_ text: String) -> (text: String, removed: [String]) {
        var removed: [String] = []
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            var words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            var changed = true
            var rounds = 0
            while changed && rounds < 40 {
                changed = false
                rounds += 1
                var length = min(10, words.count / 2)
                while length >= 1 && !changed {
                    var start = 0
                    while start + 2 * length <= words.count {
                        let first = Array(words[start..<(start + length)])
                        let second = Array(words[(start + length)..<(start + 2 * length)])
                        let firstKeys = first.map { key($0) }
                        let sameWords = firstKeys == second.map { key($0) }
                        let allowed = length > 1 || small.contains(firstKeys[0])
                        if sameWords && allowed && !first.contains(where: { isProtected($0) }) {
                            removed.append(first.joined(separator: " "))
                            var kept = first
                            kept[kept.count - 1] = second[second.count - 1]
                            words.replaceSubrange(start..<(start + 2 * length), with: kept)
                            changed = true
                            break
                        }
                        start += 1
                    }
                    length -= 1
                }
            }
            lines.append(words.joined(separator: " "))
        }
        return (lines.joined(separator: "\n"), removed)
    }

    /// The speech engine sometimes starts a new round with the last words of the previous one. Those are dropped from `spoken`.
    static func dropEcho(base: String, spoken: String) -> String {
        let spokenWords = spoken.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let baseWords = base.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var length = min(12, spokenWords.count, baseWords.count)
        while length >= 3 {
            let tail = baseWords.suffix(length).map { key($0) }
            let head = spokenWords.prefix(length).map { key($0) }
            if tail == head && !tail.contains(where: { $0.isEmpty }) {
                return spokenWords.dropFirst(length).joined(separator: " ")
            }
            length -= 1
        }
        return spoken
    }

    /// "chat gee pee tee" said for ChatGPT.
    static func foldSpelledLetters(_ joined: String) -> String {
        joined.replacingOccurrences(of: "gee", with: "g").replacingOccurrences(of: "jee", with: "g")
            .replacingOccurrences(of: "pee", with: "p").replacingOccurrences(of: "tee", with: "t")
    }
}
