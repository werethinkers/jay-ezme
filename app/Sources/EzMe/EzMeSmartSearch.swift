import Foundation
import SwiftUI

/// Words, short forms and ranking shared by the shortcut-name helper and phrase search.
///
/// The idea: every shortcut name follows one simple rule, so people can guess it, and when they
/// can't, they type what they want in plain words ("80s picture") and phrase search finds it.
enum EzMeWords {
    /// Small words that carry no meaning in a shortcut name.
    static let stopwords: Set<String> = [
        "a", "an", "the", "for", "of", "to", "my", "me", "in", "on", "with", "and", "or", "make", "making",
        "create", "creating", "new", "style", "styled", "some", "please", "i", "want", "need", "get", "give",
        "show", "type", "like", "that", "this", "is", "it", "from", "by", "at", "as", "your", "our", "into",
        "quick", "simple", "write", "generate", "do", "can", "you",
    ]

    /// Short form -> words that mean the same thing. The short form is what goes into a shortcut name.
    static let shortForms: [(String, [String])] = [
        ("pic", ["picture", "photo", "image", "img", "pic", "photograph", "snap", "selfie", "portrait", "wallpaper"]),
        ("vid", ["video", "movie", "film", "vid", "reel", "clip"]),
        ("gif", ["gif", "animation", "animated", "meme", "sticker"]),
        ("80s", ["80s", "eighties", "1980s", "retro", "vintage", "synthwave", "neon"]),
        ("90s", ["90s", "nineties", "1990s"]),
        ("mail", ["email", "mail", "e-mail", "inbox", "gmail"]),
        ("addr", ["address", "location", "office", "directions"]),
        ("ph", ["phone", "mobile", "cell", "number", "whatsapp", "contact"]),
        ("sig", ["signature", "signoff", "regards", "sign-off"]),
        ("thx", ["thanks", "thank", "thankyou", "ty", "grateful", "appreciate", "thx"]),
        ("hi", ["hello", "hi", "hey", "greeting", "welcome", "intro", "introduction", "introduce"]),
        ("bye", ["bye", "goodbye", "farewell"]),
        ("meet", ["meeting", "meet", "zoom", "schedule", "calendar", "appointment", "minutes"]),
        ("inv", ["invoice", "bill", "billing", "payment", "receipt", "inv"]),
        ("quote", ["quote", "quotation", "estimate", "proposal"]),
        ("date", ["date", "today", "day"]),
        ("time", ["time", "clock", "now"]),
        ("link", ["link", "url", "website", "site", "web", "page"]),
        ("app", ["app", "application", "launch"]),
        ("ai", ["ai", "gpt", "chatgpt", "claude", "gemini", "prompt", "assistant"]),
        ("fix", ["fix", "correct", "grammar", "proofread", "rewrite", "improve"]),
        ("sum", ["summary", "summarize", "summarise", "tldr", "recap"]),
        ("song", ["song", "music", "audio", "sound", "mp3", "voice"]),
        ("logo", ["logo", "brand", "branding", "icon"]),
        ("bday", ["birthday", "bday", "anniversary", "celebrate", "congrats", "congratulations", "wishes"]),
        ("sorry", ["sorry", "apology", "apologise", "apologize"]),
        ("follow", ["followup", "follow-up", "follow", "reminder", "remind", "nudge"]),
        ("price", ["price", "pricing", "cost", "rate", "fee"]),
        ("bank", ["bank", "iban", "ifsc", "upi", "account"]),
        ("toon", ["cartoon", "anime", "comic", "toon", "ghibli", "pixar"]),
        ("art", ["art", "painting", "drawing", "sketch", "illustration", "poster"]),
        ("cv", ["resume", "cv", "biodata"]),
        ("note", ["note", "notes", "memo"]),
        ("todo", ["todo", "to-do", "task", "tasks", "checklist"]),
        ("calc", ["calculate", "calculator", "math", "sum", "total"]),
    ]

    private static let canonicalMap: [String: String] = {
        var map: [String: String] = [:]
        for (short, words) in shortForms {
            map[short] = map[short] ?? short
            for word in words where map[word] == nil { map[word] = short }
        }
        return map
    }()

    /// Lowercases and splits text into words. "80's" becomes "80s", "e-mail" stays together.
    static func tokens(_ text: String) -> [String] {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "'s", with: "s")
            .replacingOccurrences(of: "'", with: "")
        var words: [String] = []
        var current = ""
        for ch in lowered {
            if ch.isLetter || ch.isNumber || ch == "-" { current.append(ch) } else if !current.isEmpty { words.append(current); current = "" }
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-")) }.filter { !$0.isEmpty }
    }

    /// The short form a word maps to, so "photo", "image" and "pictures" all become "pic".
    static func canonical(_ word: String) -> String {
        if let value = canonicalMap[word] { return value }
        for suffix in ["ies", "es", "s", "ing", "ed"] where word.count > suffix.count + 2 && word.hasSuffix(suffix) {
            var stem = String(word.dropLast(suffix.count))
            if suffix == "ies" { stem += "y" }
            if let value = canonicalMap[stem] { return value }
            if suffix == "s" { return stem }
        }
        return word
    }

    static func meaningful(_ text: String) -> [String] {
        let all = tokens(text)
        let kept = all.filter { !stopwords.contains($0) }
        return kept.isEmpty ? all : kept
    }

    // MARK: - Guessable shortcut names

    /// One rule for every shortcut name: drop small words, keep up to three key words, and use the
    /// short form for common words (picture → pic, email → mail). "Make an 80's picture" → /80spic.
    static func suggestedTrigger(for name: String, existing: Set<String> = []) -> String {
        var parts: [String] = []
        for word in meaningful(name) {
            let short = canonical(word)
            let piece: String
            if canonicalMap[word] != nil || short != word && canonicalMap[short] != nil { piece = short }
            else if word.first?.isNumber == true { piece = word }
            else { piece = String(short.prefix(5)) }
            if !piece.isEmpty, !parts.contains(piece) { parts.append(piece) }
            if parts.count == 3 { break }
        }
        var base = parts.joined().replacingOccurrences(of: "-", with: "")
        if base.isEmpty { base = "note" }
        base = String(base.prefix(16))
        let taken = Set(existing.map { $0.lowercased() })
        var candidate = "/" + base
        var number = 2
        while taken.contains(candidate) || taken.contains("\\" + candidate.dropFirst()) {
            candidate = "/" + base + String(number)
            number += 1
        }
        return candidate
    }

    /// How a suggestion was built, shown under the shortcut field so people learn the rule.
    static func explain(_ name: String) -> String {
        var pieces: [String] = []
        for word in meaningful(name).prefix(6) {
            let short = canonical(word)
            if canonicalMap[word] != nil, short != word { pieces.append("\(word) → \(short)") }
        }
        return pieces.isEmpty ? "Key words joined together, small words dropped." : pieces.joined(separator: " · ")
    }

    // MARK: - Phrase search

    /// Scores one shortcut against what someone typed. 0 means no match. Higher is better.
    static func score(query rawQuery: String, key: String, name: String, text: String, groups: [String]) -> Int {
        var raw = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.hasPrefix("/") || raw.hasPrefix("\\") { raw.removeFirst() }
        guard !raw.isEmpty else { return 1 }
        var keyNorm = key.lowercased()
        if keyNorm.hasPrefix("/") || keyNorm.hasPrefix("\\") { keyNorm.removeFirst() }

        var score = 0
        let compact = raw.replacingOccurrences(of: " ", with: "")
        if keyNorm == compact { score += 1000 }
        else if keyNorm.hasPrefix(compact) { score += 500 }
        else if compact.count >= 2, keyNorm.contains(compact) { score += 200 }

        let queryWords = meaningful(raw)
        let nameWords = tokens(name)
        let nameCanon = Set(nameWords.map(canonical))
        let groupCanon = Set(groups.flatMap { tokens($0) }.map(canonical))
        let textCanon = Set(tokens(String(text.prefix(400))).map(canonical))
        var matchedAll = true
        for word in queryWords {
            let c = canonical(word)
            var best = 0
            if nameCanon.contains(c) { best = 60 }
            if c.count >= 2, keyNorm.contains(c) { best = max(best, 55) }
            if word.count >= 2, nameWords.contains(where: { $0.hasPrefix(word) }) { best = max(best, 40) }
            if groupCanon.contains(c) { best = max(best, 30) }
            if textCanon.contains(c) { best = max(best, 20) }
            if best == 0, word.count >= 4, nameWords.contains(where: { $0.count >= 4 && editDistance($0, word) <= 1 }) { best = 25 }
            if best == 0 { matchedAll = false }
            score += best
        }
        if queryWords.count > 1 {
            if matchedAll { score += 40 } else if score < 200 { score /= 2 }
        }
        return score
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > 1 { return 2 }
        var previous = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var row = [i] + Array(repeating: 0, count: b.count)
            for j in 1...max(b.count, 1) where !b.isEmpty {
                row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = row
        }
        return previous[b.count]
    }

    /// Best matches first.
    static func rank(_ clips: [Clip], query: String, limit: Int = 60) -> [Clip] {
        let scored = clips.compactMap { clip -> (Int, Clip)? in
            let s = score(query: query, key: clip.key, name: clip.name, text: clip.text, groups: clip.allGroups)
            return s > 0 ? (s, clip) : nil
        }
        return scored.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1.key.count < $1.1.key.count }.prefix(limit).map(\.1)
    }
}

// MARK: - Home: find anything

/// The big search box on Home. Type a phrase, see matching shortcuts and the name to type next time.
struct EzMeFindAnythingCard: View {
    let clips: [Clip]
    var onOpen: (Clip) -> Void
    var onCreate: (String) -> Void
    @State private var query = ""

    private var results: [Clip] { query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : EzMeWords.rank(clips, query: query, limit: 6) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What do you want to type?").font(.system(size: 24, weight: .bold, design: .serif)).foregroundStyle(Butter.cocoa)
            Text("Describe it in your own words. You don't need to remember the shortcut.").foregroundStyle(.secondary)
            MerlinBar(text: $query, placeholder: "Try “80s picture”, “bank details” or “thank you email”")
            if !results.isEmpty {
                VStack(spacing: 6) {
                    ForEach(results) { clip in
                        Button { onOpen(clip) } label: {
                            HStack(spacing: 12) {
                                Text("\\" + clip.key.drop(while: { $0 == "/" || $0 == "\\" }))
                                    .font(.system(.body, design: .monospaced).bold())
                                    .foregroundStyle(Butter.coral)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Butter.honey.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(clip.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    Text(clip.text.replacingOccurrences(of: "\n", with: " ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(clip.group).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(Butter.cream, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Anywhere on your Mac, type \\ and these words to get the same results.").font(.caption).foregroundStyle(.secondary)
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack {
                    Text("Nothing saved for “\(query)” yet.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Create \\\(EzMeWords.suggestedTrigger(for: query, existing: Set(clips.map(\.key))).dropFirst())") { onCreate(query) }
                        .buttonStyle(.borderedProminent).tint(Butter.coral)
                }
            }
        }
        .padding(22)
        .background(Butter.honey.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
    }
}

/// "Where things live": the four areas of the app, so people know where to look.
struct EzMeMapCard: View {
    var go: (String) -> Void
    private let areas: [(String, String, String, String)] = [
        ("Shortcuts", "My shortcuts", "text.cursor", "Words, links and media you type with \\"),
        ("Collections", "Collections", "folder", "Lists like customers or products, each item has its own \\name"),
        ("Create", "AppBuilder", "wand.and.stars", "Build documents, images and apps with AI"),
        ("Apps & web", "Apps & links", "globe", "Open apps and websites by typing their name"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ButterAccordion("Where things live", subtitle: "Shortcuts, collections, create and apps in one glance", icon: "square.grid.2x2", open: true) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(areas, id: \.0) { area in
                    Button { go(area.1) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: area.2).font(.title2).foregroundStyle(Butter.coral)
                            Text(area.0).font(.headline).foregroundStyle(.primary)
                            Text(area.3).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                        .padding(14)
                        .background(Butter.cream, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Butter.honey))
                    }
                    .buttonStyle(.plain)
                }
            }
            }
            ButterAccordion("The naming rule", subtitle: "How shortcut names are made", icon: "lightbulb") {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill").foregroundStyle(Butter.coral)
                VStack(alignment: .leading, spacing: 3) {
                    Text("The naming rule").font(.subheadline.bold())
                    Text("Every shortcut is its key words joined, with short forms: “80's picture” is \\80spic, “email signature” is \\mailsig, “thank you note” is \\thxnote. Forgot one? Type \\ and describe it.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            }
        }
    }
}

/// Sidebar layout: a few named areas instead of one long list.
enum EzMeNavigation {
    struct Item: Identifiable { var id: String; var title: String; var hint: String }
    struct Area: Identifiable { var id: String { title }; var title: String; var items: [Item] }

    static let areas: [Area] = [
        Area(title: "", items: [Item(id: "Dashboard", title: "Home", hint: "Your start page. Type what you want and EzMe finds it for you.")]),
        Area(title: "YOUR LIBRARY", items: [
            Item(id: "My shortcuts", title: "Shortcuts", hint: "Short words that turn into long text. Type \\ then the short word anywhere."),
            Item(id: "Collections", title: "Collections", hint: "Folders of shortcuts, like a list of customers or products."),
            Item(id: "Sound & media", title: "Media", hint: "Pictures, sounds and videos you can paste in one tap."),
            Item(id: "Live & dynamic", title: "Live values", hint: "Words that fill in today's date, time or clock by themselves."),
        ]),
        Area(title: "CREATE", items: [
            Item(id: "AppBuilder", title: "AppBuilder", hint: "Make your own mini app. Say what it does and get a PDF or a picture."),
            Item(id: "Ez Studio", title: "Ez Studio", hint: "Draw and fix pictures with AI."),
            Item(id: "Shortcut ideas", title: "Ideas", hint: "Ready-made shortcuts. Pick one to keep it."),
            Item(id: "Marketplace", title: "Marketplace", hint: "Get or share shortcut packs with other people."),
            Item(id: "Ezyourlife apps", title: "Ezyourlife apps", hint: "Little AI helpers from ezyourlife.com. Pick one, fill the boxes, press Run."),
        ]),
        Area(title: "APPS & WEB", items: [
            Item(id: "Apps & links", title: "Apps & links", hint: "Open your favourite websites and apps just by typing their name."),
            Item(id: "Desktop apps", title: "Desktop apps", hint: "All the apps on this Mac, ready to open."),
            Item(id: "Browser", title: "Browser", hint: "A web browser inside EzMe."),
        ]),
        Area(title: "SETUP", items: [
            Item(id: "API configuration", title: "AI keys", hint: "Paste the secret keys that let the AI robots work. Do it once."),
            Item(id: "Ezyourlife credits", title: "Credits", hint: "Your coins for Ezyourlife apps. Top up here."),
            Item(id: "Settings", title: "Account & settings", hint: "Your account, colours and backups."),
            Item(id: "User guide", title: "Guide", hint: "A picture guide to using EzMe."),
        ]),
    ]

    static func title(for section: String) -> String {
        areas.flatMap(\.items).first(where: { $0.id == section })?.title ?? section
    }
}

/// Under the shortcut field: the suggested name, how it was built, and a warning if it's taken.
/// While the shortcut field is empty (or still holds our last suggestion) it fills itself in.
struct EzMeTriggerSuggestion: View {
    let name: String
    @Binding var key: String
    let existing: Set<String>
    @State private var lastAuto = ""

    private var suggestion: String { "\\" + EzMeWords.suggestedTrigger(for: name, existing: existing).dropFirst() }
    private var typedIsTaken: Bool {
        let trimmed = key.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.count > 1 else { return false }
        let slash = "/" + trimmed.drop(while: { $0 == "/" || $0 == "\\" })
        return existing.contains(slash) || existing.contains(trimmed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Butter.coral)
                    Text("Suggested:").foregroundStyle(.secondary)
                    Text(suggestion).font(.system(.body, design: .monospaced).bold()).foregroundStyle(Butter.coral)
                    if key != suggestion { Button("Use") { key = suggestion; lastAuto = suggestion }.controlSize(.small) }
                    Spacer()
                }
                Text(EzMeWords.explain(name)).font(.caption).foregroundStyle(.secondary)
            }
            if typedIsTaken {
                Label("Another shortcut already uses \(key). Pick a different one.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .onChange(of: name) { _ in autofill() }
        .onAppear { autofill() }
    }

    private func autofill() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if key.isEmpty || key == lastAuto { key = suggestion; lastAuto = suggestion }
    }
}
