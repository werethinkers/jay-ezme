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
        guard let best else { return nil }
        let code = prefix(best.app)
        guard !code.isEmpty else { return nil }
        let rest = String(sentence.dropFirst(best.phrase.count)).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".,!?")))
        if rest.isEmpty { return code }
        let slots = (UserDefaults.standard.string(forKey: "ezmeBuilderVariables." + best.app) ?? "").split(separator: ",").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        var parts = [rest]
        if slots > 1 {
            let separated = rest.replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if separated.count > slots {
                parts = Array(separated.prefix(slots - 1)) + [separated.dropFirst(slots - 1).joined(separator: " ")]
            } else if !separated.isEmpty { parts = separated }
        }
        return code + parts.map { "-" + quoteBuilderValue($0) }.joined()
    }
}

/// Edit the phrases that start an app by voice or by typing a sentence. One phrase per line.
struct BuilderPhrasesEditor: View {
    let app: String
    @State private var text = ""
    @State private var loaded = false

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
            Text("One phrase per line, 2 or 3 is fine. Say or type a phrase, then the details, for example \u{201C}\(example) Rohit\u{201D}.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            guard !loaded else { return }
            text = BuilderPhrases.phrases(for: app).joined(separator: "\n")
            loaded = true
        }
        .onChange(of: text) { value in
            guard loaded else { return }
            BuilderPhrases.save(value.components(separatedBy: "\n"), for: app)
        }
    }
}
