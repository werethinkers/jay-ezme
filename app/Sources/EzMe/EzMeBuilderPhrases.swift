// Sentence commands for apps. Say or type a phrase such as "send diwali greetings to Rohit": the words that match one of the
// app's phrases are the command, and everything after them is the app's details (here, the name).
// Each app has a few suggested phrases. They can be edited in the app's settings (one phrase per line), and an app can have
// two or three different phrases.
import SwiftUI

enum BuilderPhrases {
    private static func key(_ app: String) -> String { "ezmeBuilderPhrases." + app }

    private static let spoken: [String: String] = [
        "thanks": "thank you", "wed": "wedding anniversary", "xmas": "christmas", "rakhi": "raksha bandhan", "ganesh": "ganesh chaturthi",
        "navratri": "navratri", "durga": "durga puja", "dussehra": "dussehra", "sankranti": "makar sankranti", "pongal": "pongal",
        "onam": "onam", "baisakhi": "baisakhi", "janmashtami": "janmashtami", "diwali": "diwali", "holi": "holi", "eid": "eid"
    ]

    private static func prefix(_ app: String) -> String {
        let defaults = UserDefaults.standard
        let fallback = String(app.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).prefix(12))
        return defaults.string(forKey: "ezmeBuilderPrefix." + app) ?? fallback
    }

    /// The phrases KeyDo suggests for an app until the person edits them.
    static func suggested(for app: String) -> [String] {
        let code = prefix(app).lowercased()
        if code == "hbd" { return ["send birthday wishes to", "wish happy birthday to", "make a birthday card for"] }
        if code == "hwa" { return ["send work anniversary wishes to", "wish happy work anniversary to", "make a work anniversary card for"] }
        if let name = spoken[code] {
            if code == "thanks" { return ["send thank you to", "send a thank you card to", "say thank you to"] }
            if code == "wed" { return ["send wedding anniversary wishes to", "wish happy anniversary to", "make an anniversary card for"] }
            return ["send \(name) greetings to", "wish happy \(name) to", "make a \(name) card for"]
        }
        let name = app.lowercased().replacingOccurrences(of: "[^a-z0-9 ]+", with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
        guard !name.isEmpty else { return [] }
        return ["make \(name) for", "send \(name) to", "create \(name) for"]
    }

    /// The phrases now in use: the edited list, or the suggestions.
    static func phrases(for app: String) -> [String] {
        if let saved = UserDefaults.standard.stringArray(forKey: key(app)) { return saved }
        return suggested(for: app)
    }

    static func save(_ phrases: [String], for app: String) {
        let clean = phrases.map(normalize).filter { !$0.isEmpty }
        UserDefaults.standard.set(clean, forKey: key(app))
    }

    static func normalize(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ".,!?:;\""))
    }

    /// "send diwali greetings to Rohit" becomes "diwali-Rohit". Nil when the words match none of the phrases.
    static func rewrite(_ spokenText: String, apps: [String]) -> String? {
        let sentence = spokenText.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard sentence.contains(" ") else { return nil }
        let lower = sentence.lowercased()
        var best: (app: String, phrase: String)?
        for app in apps {
            for phrase in phrases(for: app).map({ normalize($0).lowercased() }) where !phrase.isEmpty {
                guard lower == phrase || lower.hasPrefix(phrase + " ") else { continue }
                if best == nil || phrase.count > best!.phrase.count { best = (app, phrase) }
            }
        }
        if let best {
            let rest = String(sentence.dropFirst(best.phrase.count)).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".,!?")))
            return command(app: best.app, rest: rest)
        }
        return looseRewrite(sentence, apps: apps)
    }

    // MARK: Loose matching: "send diwali greetings to Rohit"

    private static let verbs: Set<String> = ["send", "create", "make", "generate", "write", "prepare", "wish", "share", "run", "start", "give", "design", "build", "get", "compose", "draft", "produce", "do", "issue", "raise"]
    private static let lead: Set<String> = ["please", "can", "could", "you", "hey", "kindly", "now", "just", "i", "want", "to", "need", "would", "like", "will", "let", "lets", "let's"]
    private static let fillers: Set<String> = ["a", "an", "the", "some", "my", "happy", "greeting", "greetings", "card", "cards", "wish", "wishes", "wishing", "message", "messages", "note", "image", "picture", "pic", "post", "new", "special", "festival", "festive", "best", "warm", "lovely", "nice", "beautiful", "our", "and"]
    private static let connectors: Set<String> = ["to", "for", "of", "about", "towards", "with"]

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"\u{201C}\u{201D}")) }.filter { !$0.isEmpty }
    }

    /// The words that name an app: its code, its name, the festival or occasion name, and the key words of its phrases.
    static func keywords(for app: String) -> Set<String> {
        let code = prefix(app).lowercased()
        var result: Set<String> = [code]
        for part in code.split(separator: "-") { result.insert(String(part)) }
        let skip = verbs.union(lead).union(fillers).union(connectors)
        func add(_ text: String) {
            for word in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) where !skip.contains(word) && word.count > 1 { result.insert(word) }
        }
        add(app)
        if let name = spoken[code] { add(name) }
        for phrase in phrases(for: app) { add(phrase) }
        return result
    }

    private static func looseRewrite(_ sentence: String, apps: [String]) -> String? {
        let tokens = words(sentence)
        guard tokens.count >= 2 else { return nil }
        var start = 0
        while start < tokens.count, lead.contains(tokens[start].lowercased()), !verbs.contains(tokens[start].lowercased()) { start += 1 }
        guard start < tokens.count, verbs.contains(tokens[start].lowercased()) else { return nil }
        start += 1
        var best: (app: String, hits: Int, end: Int)?
        for app in apps {
            let names = keywords(for: app)
            var index = start, hits = 0
            while index < tokens.count {
                let word = tokens[index].lowercased()
                if names.contains(word) { hits += 1 } else if !fillers.contains(word) { break }
                index += 1
            }
            guard hits > 0 else { continue }
            if best == nil || hits > best!.hits { best = (app, hits, index) }
        }
        guard let best else { return nil }
        var rest = best.end
        while rest < tokens.count, connectors.contains(tokens[rest].lowercased()) { rest += 1 }
        return command(app: best.app, rest: tokens[rest...].joined(separator: " "))
    }

    /// Builds "diwali-Rohit" from the app and the words after the command.
    private static func command(app: String, rest: String) -> String? {
        let code = prefix(app)
        guard !code.isEmpty else { return nil }
        if rest.isEmpty { return code }
        let slots = (UserDefaults.standard.string(forKey: "ezmeBuilderVariables." + app) ?? "").split(separator: ",").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        var parts = [rest]
        if slots > 1 {
            let separated = rest.replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if separated.count > slots {
                parts = Array(separated.prefix(slots - 1)) + [separated.dropFirst(slots - 1).joined(separator: " ")]
            } else if !separated.isEmpty { parts = separated }
        }
        return code + parts.map { "-" + quoteBuilderValue($0) }.joined()
    }

    /// Whether a spoken command runs by itself (makes the result and pastes it) once the person stops talking.
    static func runsByItself(_ app: String) -> Bool {
        UserDefaults.standard.object(forKey: "ezmeBuilderVoiceAutoRun." + app) as? Bool ?? true
    }

    static func setRunsByItself(_ value: Bool, for app: String) {
        UserDefaults.standard.set(value, forKey: "ezmeBuilderVoiceAutoRun." + app)
    }
}

/// Edit the phrases that start an app by voice or by typing a sentence. One phrase per line.
struct BuilderPhrasesEditor: View {
    let app: String
    @State private var text = ""
    @State private var loaded = false
    @State private var autoRun = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Voice and sentence commands").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Use suggestions") { text = BuilderPhrases.suggested(for: app).joined(separator: "\n") }
                    .buttonStyle(.link).font(.caption)
            }
            TextEditor(text: $text)
                .font(.system(size: 12))
                .frame(height: 72)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            let example = BuilderPhrases.phrases(for: app).first ?? "make it for"
            Text("One phrase per line, 2 or 3 is fine. Say or type a phrase, then the details, for example \u{201C}\(example) Rohit\u{201D}. KeyDo also understands a plain Send, Create or Make followed by this app\u{2019}s name (like \u{201C}send diwali greetings to Rohit\u{201D}): words such as greetings, card and wishes are ignored, and what comes after to or for is the details.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Run by itself when I say it: make the result and paste it into the app I was in", isOn: $autoRun)
                .font(.caption)
                .toggleStyle(.checkbox)
        }
        .onAppear {
            guard !loaded else { return }
            text = BuilderPhrases.phrases(for: app).joined(separator: "\n")
            autoRun = BuilderPhrases.runsByItself(app)
            loaded = true
        }
        .onChange(of: autoRun) { value in
            guard loaded else { return }
            BuilderPhrases.setRunsByItself(value, for: app)
        }
        .onChange(of: text) { value in
            guard loaded else { return }
            BuilderPhrases.save(value.components(separatedBy: "\n"), for: app)
        }
    }
}
