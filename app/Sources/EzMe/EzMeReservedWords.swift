// Words that clash with voice and typed commands, so a shortcut cannot be only that word.
import Foundation

enum ReservedShortcutWords {
    static let commands: Set<String> = [
        "send", "create", "generate", "design", "make", "build", "write", "draw", "open", "show", "share", "paste", "post", "submit",
        "enter", "edit", "undo", "accept", "dismiss", "copy", "search", "find", "run", "start", "stop", "save", "delete", "add", "new",
        "remove", "rename", "update", "change", "translate", "summarize", "summarise", "explain", "tell", "give", "close", "cancel",
        "hash", "hashtag", "mention", "equals", "comma", "paragraph"
    ]

    /// The advice to show when a shortcut word clashes, or nil when it is fine.
    static func problem(_ rawKey: String) -> String? {
        var key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        while key.hasPrefix("/") || key.hasPrefix("\\") { key.removeFirst() }
        guard !key.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        if key.unicodeScalars.contains(where: { !allowed.contains($0) }) || !key.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
            return "Use letters and numbers only. Punctuation can clash with dictation. Join words with a dot or dash, such as thanks.mail."
        }
        let lower = key.lowercased()
        if commands.contains(lower) || PromptMarkIndex.plainWords.contains(lower) {
            return "“\(key)” is a command or pronoun word, so it would clash with voice and commands. Change the word, or add a suffix such as \(key).pic, \(key).phone or \(key).mobile."
        }
        return nil
    }
}
