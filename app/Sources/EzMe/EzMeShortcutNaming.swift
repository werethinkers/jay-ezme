// Shortcut names for renamed files. A collection usually follows one pattern, like every key ending in .media or
// starting with the same word. When a file is renamed, KeyDo suggests keys in that pattern: the full file name,
// and a short one.
import Foundation

enum ShortcutNaming {
    struct Pattern: Equatable {
        var prefix = ""
        var suffix = ""
        var isEmpty: Bool { prefix.isEmpty && suffix.isEmpty }
        var note: String {
            if isEmpty { return "" }
            var parts: [String] = []
            if !prefix.isEmpty { parts.append("starts with " + prefix) }
            if !suffix.isEmpty { parts.append("ends with " + suffix) }
            return "This collection's shortcuts " + parts.joined(separator: " and ") + "."
        }
    }

    struct Suggestion: Identifiable, Equatable {
        var id: String { key }
        var label: String
        var key: String          // stored form, starting with /
    }

    static func bare(_ key: String) -> String {
        var value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("/") || value.hasPrefix("\\") { value.removeFirst() }
        return value
    }

    /// The prefix or suffix most keys of a collection share (at least two keys, at least half of them).
    static func infer(from keys: [String]) -> Pattern {
        let bares = keys.map(bare).filter { !$0.isEmpty }
        guard bares.count >= 2 else { return Pattern() }
        var suffixes: [String: Int] = [:]
        var prefixes: [String: Int] = [:]
        for key in bares {
            if let dot = key.lastIndex(of: "."), dot != key.startIndex {
                let suffix = String(key[dot...])
                if suffix.count >= 2, suffix.count <= 9, !suffix.dropFirst().contains(where: { !$0.isLetter && !$0.isNumber }) { suffixes[suffix.lowercased(), default: 0] += 1 }
            }
            if let separator = key.firstIndex(where: { "-_.".contains($0) }), separator != key.startIndex, key.index(after: separator) != key.endIndex {
                prefixes[String(key[...separator]).lowercased(), default: 0] += 1
            }
        }
        func common(_ counts: [String: Int]) -> String {
            guard let best = counts.max(by: { $0.value < $1.value }), best.value >= 2, best.value * 2 >= bares.count else { return "" }
            return best.key
        }
        return Pattern(prefix: common(prefixes), suffix: common(suffixes))
    }

    /// Lower-case letters and numbers with single dashes: "Sunset Beach 2024" becomes "sunset-beach-2024".
    static func slug(_ text: String, limit: Int = 40) -> String {
        let folded = text.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let dashed = folded.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        let trimmed = dashed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(trimmed.prefix(limit)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func build(_ base: String, pattern: Pattern, taken: Set<String>) -> String {
        var stem = base.isEmpty ? "file" : base
        // Do not repeat what the pattern already adds.
        if !pattern.suffix.isEmpty, stem.lowercased().hasSuffix(pattern.suffix) { stem = String(stem.dropLast(pattern.suffix.count)) }
        if !pattern.prefix.isEmpty, stem.lowercased().hasPrefix(pattern.prefix) { stem = String(stem.dropFirst(pattern.prefix.count)) }
        let used = Set(taken.map { bare($0).lowercased() })
        var candidate = pattern.prefix + stem + pattern.suffix
        var number = 2
        while used.contains(candidate.lowercased()) {
            candidate = pattern.prefix + stem + String(number) + pattern.suffix
            number += 1
        }
        return "/" + candidate
    }

    /// The full file name and a short form, both in the collection's pattern, never equal to a key already used.
    @MainActor static func suggestions(forFileName name: String, pattern: Pattern, taken: Set<String>) -> [Suggestion] {
        let full = build(slug(name), pattern: pattern, taken: taken)
        let shortBase = String(EzMeWords.suggestedTrigger(for: name).dropFirst())
        let short = build(shortBase, pattern: pattern, taken: taken)
        var result = [Suggestion(label: "Full name", key: full)]
        if short != full { result.append(Suggestion(label: "Short", key: short)) }
        return result
    }
}
