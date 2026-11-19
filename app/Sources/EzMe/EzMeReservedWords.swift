// Words that clash with voice and typed commands, so a shortcut cannot be only that word. The list is editable in Settings.
import SwiftUI

enum ReservedShortcutWords {
    static let storageKey = "ezmeReservedWordsList"
    static let enabledKey = "ezmeReservedWordsOn"

    static let actionWords: [String] = [
        "send", "create", "generate", "design", "make", "build", "write", "draw", "open", "show", "share", "paste", "post", "submit",
        "enter", "edit", "undo", "accept", "dismiss", "copy", "search", "find", "run", "start", "stop", "save", "delete", "add", "new",
        "remove", "rename", "update", "change", "translate", "summarize", "summarise", "explain", "tell", "give", "close", "cancel",
        "hash", "hashtag", "mention", "equals", "comma", "paragraph",
        "play", "call", "pause", "resume", "read", "listen", "watch", "view", "go", "take", "put", "set", "turn", "tap", "click", "press",
        "type", "say", "ask", "check", "order", "book", "buy", "pay", "download", "upload", "print", "scan", "record", "capture",
        "schedule", "remind", "reply", "forward", "email", "text", "message", "dial", "navigate", "launch", "quit", "exit", "restart",
        "reset", "clear", "select", "choose", "pick", "move", "drag", "drop", "insert", "replace", "fix", "improve", "rewrite", "convert",
        "calculate", "compare", "list", "describe", "analyze", "analyse", "review", "plan", "draft", "publish", "sync", "backup",
        "restore", "import", "export", "join", "invite", "follow", "like", "mute", "unmute", "lock", "unlock", "enable", "disable",
        "toggle", "hide", "display", "bring", "fetch", "load", "refresh", "search", "lookup", "remember", "forget", "repeat", "skip",
        "next", "previous", "back", "continue", "finish", "begin", "help", "enter", "return", "yes", "no", "r", "reply"
    ]

    /// The starting list: action words plus pronouns and small words that dictation says all the time.
    static var defaultList: [String] {
        var seen = Set<String>(), list = [String]()
        for word in actionWords + PromptMarkIndex.plainWords.sorted() where seen.insert(word).inserted { list.append(word) }
        return list.sorted()
    }

    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    static let alwaysReserved = ["r", "reply"]

    static func list() -> [String] {
        // "reply" and "r" belong to the Reply app and always stay reserved, even in a list saved earlier.
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey) { return Array(Set(saved + alwaysReserved)).sorted() }
        return defaultList
    }

    static func save(_ words: [String]) {
        let clean = Array(Set(words.map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }.filter { !$0.isEmpty })).sorted()
        UserDefaults.standard.set(clean, forKey: storageKey)
    }

    static func reset() { UserDefaults.standard.removeObject(forKey: storageKey) }

    /// The advice to show when a shortcut word clashes, or nil when it is fine.
    static func problem(_ rawKey: String) -> String? {
        guard enabled else { return nil }
        var key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        while key.hasPrefix("/") || key.hasPrefix("\\") { key.removeFirst() }
        guard !key.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        if key.unicodeScalars.contains(where: { !allowed.contains($0) }) || !key.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
            return "Use letters and numbers only. Punctuation can clash with dictation. Join words with a dot or dash, such as thanks.mail."
        }
        let lower = key.lowercased()
        if list().contains(lower) {
            return "“\(key)” is on your list of words that clash with voice and commands. Change the word, or add a suffix such as \(key).pic, \(key).phone or \(key).mobile. You can edit the list in Settings."
        }
        return nil
    }
}

/// Settings: which words shortcuts may not be, with add, remove and reset.
struct ReservedWordsSettings: View {
    @AppStorage(ReservedShortcutWords.enabledKey) private var on = true
    @State private var words = ReservedShortcutWords.list()
    @State private var newWords = ""
    @State private var filter = ""

    private var shown: [String] { filter.isEmpty ? words : words.filter { $0.contains(filter.lowercased()) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Do not allow shortcuts that are only one of these words", isOn: $on).toggleStyle(.switch).tint(Butter.coral)
            Text("Words like send, play, call, show or make are used by voice and typed commands, and so are pronouns such as I, me, he, she. A shortcut that is only one of them would clash. Add a suffix such as .pic, .phone or .mobile to use the word anyway (send.pic). Punctuation in a shortcut is also not allowed.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Add words, separated by commas or spaces", text: $newWords).textFieldStyle(.roundedBorder).onSubmit { add() }
                Button("Add") { add() }.buttonStyle(.borderedProminent).tint(Butter.coral).disabled(newWords.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                TextField("Search the list", text: $filter).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Text("\(words.count) words").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset to the standard list") { ReservedShortcutWords.reset(); words = ReservedShortcutWords.list() }.buttonStyle(.bordered)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(shown, id: \.self) { word in
                        HStack(spacing: 4) {
                            Text(word).font(.caption.weight(.semibold)).lineLimit(1)
                            Button { words.removeAll { $0 == word }; ReservedShortcutWords.save(words) } label: { Image(systemName: "xmark.circle.fill").font(.caption) }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("Allow “\(word)” as a shortcut")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Butter.coral.opacity(0.10), in: Capsule())
                    }
                }
            }
            .frame(maxHeight: 190)
        }
        .padding(8)
        .onAppear { words = ReservedShortcutWords.list() }
    }

    private func add() {
        let parts = newWords.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" }).map(String.init)
        guard !parts.isEmpty else { return }
        ReservedShortcutWords.save(words + parts)
        words = ReservedShortcutWords.list()
        newWords = ""
    }
}
