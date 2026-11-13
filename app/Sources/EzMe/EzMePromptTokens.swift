// Prompt Builder tokens and spoken commands.
//
// In the typed prompt:
//   #rohit.media  a shortcut or a collection record (a media shortcut is attached, a text shortcut is written out)
//   @priya        a person (collection record) or an app shortcut
//   =date         a function: =date =time =day =month =year =tomorrow =yesterday =now
//   =2+5          a calculation, written out as 7 (=2+5=7 also gives 7)
//
// By voice (see PromptVoice.helpRows): "hash rohit dot media", "mention priya", "equals date", "equals two plus five",
// "comma", "undo one word", "undo one sentence", "edit word", "edit prompt rohit", "enter chatgpt".
import AppKit
import Foundation
import SwiftUI

// MARK: - Functions: =date, =2+5

enum PromptFunctions {
    static let names: [(name: String, detail: String)] = [
        ("date", "Today's date"), ("time", "The current time"), ("day", "The day of the week"),
        ("month", "The current month"), ("year", "The current year"),
        ("tomorrow", "Tomorrow's date"), ("yesterday", "Yesterday's date"), ("now", "Date and time"),
    ]

    /// "=date", "=2+5" or "=2+5=7", written out. Nil when the text is not a function.
    static func evaluate(_ core: String, now: Date = Date()) -> String? {
        guard core.hasPrefix("="), core.count >= 2 else { return nil }
        var body = String(core.dropFirst())
        if let second = body.firstIndex(of: "=") { body = String(body[body.startIndex..<second]) }
        let lower = body.lowercased()
        if let named = namedValue(lower, now: now) { return named }
        guard let first = lower.first, first.isNumber || first == "(" || first == "-" || first == "." else { return nil }
        var parser = MathParser(lower)
        guard let value = parser.parse() else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSNumber(value: value))
    }

    private static func format(_ date: Date, dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    private static func format(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private static func namedValue(_ name: String, now: Date) -> String? {
        let calendar = Calendar.current
        switch name {
        case "date", "today": return format(now, dateStyle: .long, timeStyle: .none)
        case "time": return format(now, dateStyle: .none, timeStyle: .short)
        case "now": return format(now, dateStyle: .long, timeStyle: .short)
        case "day": return format(now, pattern: "EEEE")
        case "month": return format(now, pattern: "LLLL")
        case "year": return format(now, pattern: "yyyy")
        case "tomorrow":
            let date = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return format(date, dateStyle: .long, timeStyle: .none)
        case "yesterday":
            let date = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return format(date, dateStyle: .long, timeStyle: .none)
        default: return nil
        }
    }
}

/// A small calculator: + - * / x ( ) and decimals. No NSExpression, so a mistyped sum can never crash the app.
private struct MathParser {
    private let chars: [Character]
    private var pos = 0

    init(_ text: String) { chars = Array(text.filter { !$0.isWhitespace }) }

    mutating func parse() -> Double? {
        guard let value = expression(), pos == chars.count, value.isFinite else { return nil }
        return value
    }

    private mutating func expression() -> Double? {
        guard var value = term() else { return nil }
        while pos < chars.count, chars[pos] == "+" || chars[pos] == "-" {
            let op = chars[pos]
            pos += 1
            guard let rhs = term() else { return nil }
            value = op == "+" ? value + rhs : value - rhs
        }
        return value
    }

    private mutating func term() -> Double? {
        guard var value = factor() else { return nil }
        while pos < chars.count, "*/x×÷".contains(chars[pos]) {
            let op = chars[pos]
            pos += 1
            guard let rhs = factor() else { return nil }
            if op == "/" || op == "÷" {
                guard rhs != 0 else { return nil }
                value /= rhs
            } else {
                value *= rhs
            }
        }
        return value
    }

    private mutating func factor() -> Double? {
        guard pos < chars.count else { return nil }
        if chars[pos] == "-" {
            pos += 1
            guard let inner = factor() else { return nil }
            return -inner
        }
        if chars[pos] == "(" {
            pos += 1
            guard let inner = expression(), pos < chars.count, chars[pos] == ")" else { return nil }
            pos += 1
            return inner
        }
        let start = pos
        while pos < chars.count, chars[pos].isNumber || chars[pos] == "." { pos += 1 }
        guard pos > start else { return nil }
        return Double(String(chars[start..<pos]))
    }
}

// MARK: - Suggestions while typing # @ =

struct PromptSuggestion: Identifiable, Equatable {
    var title: String
    var detail: String
    var insert: String
    var symbol: String
    var id: String { insert }
}

enum PromptSuggestions {
    private static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff", "bmp"]
    private static let videoTypes: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]

    /// The word being typed right now, when it starts with # @ or =.
    static func lastToken(in text: String) -> String? {
        guard let last = text.last, !last.isWhitespace else { return nil }
        guard let token = text.split(whereSeparator: { $0.isWhitespace }).last.map(String.init), let first = token.first else { return nil }
        return "#@=".contains(first) ? token : nil
    }

    static func trimmedKey(_ key: String) -> String {
        key.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
    }

    static func symbol(for clip: Clip) -> String {
        if let path = clip.files.first {
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            if imageTypes.contains(ext) { return "photo" }
            if videoTypes.contains(ext) { return "film" }
            return "doc"
        }
        if clip.appBundleIdentifier != nil { return "app" }
        if clip.webURL != nil { return "globe" }
        return "text.quote"
    }

    static func suggestions(for token: String, clips: [Clip], records: [CollectionRecord], apps: [PromptAppEntry] = []) -> [PromptSuggestion] {
        guard let marker = token.first else { return [] }
        let query = String(token.dropFirst()).lowercased()

        func rank(_ text: String) -> Int? {
            let lower = text.lowercased()
            if query.isEmpty { return 1 }
            if lower.hasPrefix(query) { return 0 }
            return lower.contains(query) ? 1 : nil
        }

        var found: [(Int, PromptSuggestion)] = []
        switch marker {
        case "=":
            for item in PromptFunctions.names {
                if let r = rank(item.name) {
                    found.append((r, PromptSuggestion(title: "=" + item.name, detail: item.detail, insert: "=" + item.name, symbol: "function")))
                }
            }
            if query.isEmpty || Double(query.prefix(1)) != nil {
                found.append((2, PromptSuggestion(title: "=2+5", detail: "A sum: =2+5 becomes 7", insert: "=2+5", symbol: "plus.forwardslash.minus")))
            }
        case "#":
            for clip in clips {
                let key = trimmedKey(clip.key)
                guard !key.isEmpty, let r = rank(key) ?? rank(clip.name) else { continue }
                found.append((r, PromptSuggestion(title: "#" + key, detail: clip.name, insert: "#" + key, symbol: symbol(for: clip))))
            }
            for record in records where !record.alias.isEmpty {
                guard let r = rank(record.alias) ?? rank(record.name) else { continue }
                found.append((r, PromptSuggestion(title: "#" + record.alias, detail: record.collection + " · " + record.name, insert: "#" + record.alias, symbol: "tray.full")))
            }
        case "@":
            for record in records where !record.alias.isEmpty {
                guard let r = rank(record.alias) ?? rank(record.name) else { continue }
                found.append((r, PromptSuggestion(title: "@" + record.alias, detail: record.collection + " · " + record.name, insert: "@" + record.alias, symbol: "person.crop.circle")))
            }
            for app in apps {
                guard let r = rank(app.compact) ?? rank(app.name) else { continue }
                found.append((r, PromptSuggestion(title: "@" + app.compact, detail: app.source + " app", insert: "@" + app.compact, symbol: "square.grid.2x2")))
            }
        default:
            break
        }
        let ordered = found.sorted { $0.0 < $1.0 }.prefix(8).map { $0.1 }
        return Array(ordered)
    }
}

// MARK: - Words that should have had a # @ or = (numbered suggestions)

struct PromptMarkEntry {
    var token: String
    var detail: String
    var symbol: String
}

/// An app made in KeyDo: an AppBuilder app, a WishStudio app or an Ezyourlife app. (Not apps installed on the Mac.)
struct PromptAppEntry: Equatable {
    var name: String
    var source: String

    /// "Happy Birthday" is written @HappyBirthday.
    var compact: String { name.filter { $0.isLetter || $0.isNumber } }
}

enum PromptAppCatalog {
    /// Reads the three places apps live. `wishDirectory` is the folder with wishstudio.json.
    @MainActor static func load(builderApps: [String], wishDirectory: URL?) -> [PromptAppEntry] {
        var result: [PromptAppEntry] = []
        var seen = Set<String>()
        func add(_ name: String, _ source: String) {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = clean.lowercased() + "|" + source
            guard !clean.isEmpty, seen.insert(key).inserted else { return }
            result.append(PromptAppEntry(name: clean, source: source))
        }
        for name in builderApps { add(name, "AppBuilder") }
        if let directory = wishDirectory,
           let data = try? Data(contentsOf: directory.appendingPathComponent("wishstudio.json")),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let apps = object["apps"] as? [[String: Any]] {
            for app in apps { if let name = app["name"] as? String { add(name, "WishStudio") } }
        }
        for app in Ezyourlife.shared.catalogue where app.runnable { add(app.name, "Ezyourlife") }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Everything that can be written with a mark, for finding plain words that should have one and for hearing
/// spoken names ("hash rohit media" finds #rohit.media).
struct PromptMarkIndex {
    var byWord: [String: PromptMarkEntry] = [:]
    var bySpoken: [String: PromptMarkEntry] = [:]

    static func alnum(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static let personWords = ["people", "person", "contact", "employee", "customer", "client", "candidate", "friend",
                                      "family", "team", "member", "user", "vendor", "supplier", "lead", "patient", "student"]

    static func build(clips: [Clip], records: [CollectionRecord], apps: [PromptAppEntry]) -> PromptMarkIndex {
        var index = PromptMarkIndex()
        for app in apps {
            let compact = app.compact
            guard compact.count >= 3 else { continue }
            let entry = PromptMarkEntry(token: "@" + compact, detail: app.source + " app", symbol: "square.grid.2x2")
            let lower = compact.lowercased()
            if index.byWord[lower] == nil { index.byWord[lower] = entry }
            if index.bySpoken[lower] == nil { index.bySpoken[lower] = entry }
        }
        for clip in clips {
            let key = PromptSuggestions.trimmedKey(clip.key)
            guard !key.isEmpty else { continue }
            let entry = PromptMarkEntry(token: "#" + key, detail: clip.name, symbol: PromptSuggestions.symbol(for: clip))
            let lower = key.lowercased()
            if lower.count >= 3, index.byWord[lower] == nil { index.byWord[lower] = entry }
            if let dot = lower.firstIndex(of: ".") {
                let base = String(lower[lower.startIndex..<dot])
                if base.count >= 3, index.byWord[base] == nil { index.byWord[base] = entry }
            }
            let spoken = alnum(key)
            if !spoken.isEmpty, index.bySpoken[spoken] == nil { index.bySpoken[spoken] = entry }
        }
        for record in records.prefix(5000) where !record.alias.isEmpty {
            let collection = record.collection.lowercased()
            let isPerson = personWords.contains(where: { collection.contains($0) })
            let entry = PromptMarkEntry(token: (isPerson ? "@" : "#") + record.alias, detail: record.collection + " · " + record.name,
                                        symbol: isPerson ? "person.crop.circle" : "tray.full")
            let lower = record.alias.lowercased()
            if lower.count >= 3, index.byWord[lower] == nil { index.byWord[lower] = entry }
            if let first = record.name.split(separator: " ").first.map({ String($0).lowercased() }),
               first.count >= 3, index.byWord[first] == nil { index.byWord[first] = entry }
            let spoken = alnum(record.alias)
            if !spoken.isEmpty, index.bySpoken[spoken] == nil { index.bySpoken[spoken] = entry }
        }
        return index
    }
}

struct PromptFix: Identifiable, Equatable {
    var range: NSRange
    var word: String
    var key: String
    var token: String
    var detail: String
    var symbol: String
    var id: String { "\(range.location)-\(token)" }
}

enum PromptFixes {
    private static let wordPattern = try? NSRegularExpression(pattern: "[\\p{L}\\p{N}_'’-]+(?:\\.[\\p{L}\\p{N}_-]+)*")
    private static let functionWords: Set<String> = ["date", "time", "day", "month", "year"]
    private static let functionLead: Set<String> = ["current", "todays", "today's", "today’s"]

    /// Plain words in the text that match a shortcut, record, app or "today's date", newest first.
    static func fixes(in text: String, index: PromptMarkIndex, dismissed: Set<String>, limit: Int = 5) -> [PromptFix] {
        guard let regex = wordPattern, !text.isEmpty else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result: [PromptFix] = []
        var skipNext = false
        for (position, match) in matches.enumerated() {
            if skipNext { skipNext = false; continue }
            let word = ns.substring(with: match.range)
            let lower = word.lowercased()
            if dismissed.contains(lower) { continue }
            if match.range.location > 0 {
                let before = ns.substring(with: NSRange(location: match.range.location - 1, length: 1))
                if "#@=/\\".contains(before) { continue }
            }
            if functionWords.contains(lower), position > 0 {
                let previous = matches[position - 1]
                let previousWord = ns.substring(with: previous.range).lowercased()
                let gapStart = previous.range.location + previous.range.length
                let gap = ns.substring(with: NSRange(location: gapStart, length: match.range.location - gapStart))
                if functionLead.contains(previousWord), gap.allSatisfy({ $0 == " " }) {
                    let range = NSRange(location: previous.range.location, length: match.range.location + match.range.length - previous.range.location)
                    result.append(PromptFix(range: range, word: previousWord + " " + lower, key: lower, token: "=" + lower, detail: "Written out as it is today", symbol: "function"))
                    continue
                }
            }
            if position + 1 < matches.count {
                let following = matches[position + 1]
                let gapStart = match.range.location + match.range.length
                let gap = ns.substring(with: NSRange(location: gapStart, length: following.range.location - gapStart))
                let secondWord = ns.substring(with: following.range)
                let joined = PromptMarkIndex.alnum(word) + PromptMarkIndex.alnum(secondWord)
                if gap == " ", let entry = index.bySpoken[joined], !dismissed.contains(secondWord.lowercased()) {
                    let range = NSRange(location: match.range.location, length: following.range.location + following.range.length - match.range.location)
                    result.append(PromptFix(range: range, word: word + " " + secondWord, key: lower, token: entry.token, detail: entry.detail, symbol: entry.symbol))
                    skipNext = true
                    continue
                }
            }
            if let entry = index.byWord[lower] {
                result.append(PromptFix(range: match.range, word: word, key: lower, token: entry.token, detail: entry.detail, symbol: entry.symbol))
            } else if lower.hasSuffix("'s") || lower.hasSuffix("’s") {
                let stripped = String(lower.dropLast(2))
                if let entry = index.byWord[stripped] {
                    let range = NSRange(location: match.range.location, length: match.range.length - 2)
                    result.append(PromptFix(range: range, word: String(word.dropLast(2)), key: lower, token: entry.token, detail: entry.detail, symbol: entry.symbol))
                }
            }
        }
        return Array(result.reversed().prefix(limit))
    }

    static func apply(_ fix: PromptFix, to text: String) -> String {
        (text as NSString).replacingCharacters(in: fix.range, with: fix.token)
    }

    static func applyAll(_ fixes: [PromptFix], to text: String) -> String {
        var result = text
        for fix in fixes.sorted(by: { $0.range.location > $1.range.location }) { result = apply(fix, to: result) }
        return result
    }
}

// MARK: - Spoken commands

struct PromptVoiceResult {
    var text: String
    var sends: [PromptTarget]
    var notice: String
    var dismissed: Set<String>
}

enum PromptVoice {
    /// What each spoken command does, for the help list in the app.
    static let helpRows: [(say: String, result: String)] = [
        ("hash rohit dot media", "writes #rohit.media (“hashtag” works too)"),
        ("mention priya", "writes @priya (“at sign priya” works too)"),
        ("equals date", "writes =date, which becomes today's date"),
        ("equals two plus five", "writes =2+5, which becomes 7"),
        ("(a name you have, said plainly)", "gets its # or @ on its own; tap ✕ on the chip to undo"),
        ("comma · full stop · question mark · new line", "adds that mark"),
        ("undo one word", "deletes the last word"),
        ("undo one sentence", "deletes the last sentence"),
        ("edit word", "deletes the last word, then say the new one"),
        ("edit prompt rohit", "finds that word, removes it, and your next words go in its place"),
        ("end edit", "go back to the end of the prompt"),
        ("enter chatgpt · grok · claude · gemini", "opens that site in the side panel and sends the prompt"),
    ]

    /// Words the speech engine should expect, so it hears the command words and your own names properly.
    static func contextualHints(targets: [PromptTarget], clips: [Clip], records: [CollectionRecord]) -> [String] {
        var hints = ["hashtag", "hash", "at sign", "mention", "equals", "equal sign", "comma", "full stop", "question mark", "new line",
                     "undo one word", "undo one sentence", "edit word", "edit prompt", "end edit",
                     "accept suggestion", "accept all", "dismiss suggestions", "dot media"]
        for target in targets { hints.append("enter " + target.name) }
        for item in PromptFunctions.names { hints.append("equals " + item.name) }
        for clip in clips.prefix(40) {
            let key = PromptSuggestions.trimmedKey(clip.key)
            if !key.isEmpty { hints.append(key.replacingOccurrences(of: ".", with: " dot ")) }
        }
        for record in records.prefix(30) where !record.alias.isEmpty { hints.append(record.alias) }
        return Array(hints.prefix(100))
    }

    private enum Command {
        case comma, fullStop, question, exclaim, newLine, newParagraph
        case undoWord, undoSentence, editWord, editPrompt, endEdit
        case hash, mention, equals, enter
        case accept, acceptAll, dismiss
    }

    private static let phrases: [([String], Command)] = [
        (["undo", "last", "sentence"], .undoSentence), (["undo", "one", "sentence"], .undoSentence),
        (["undo", "1", "sentence"], .undoSentence), (["undo", "sentence"], .undoSentence),
        (["undo", "last", "word"], .undoWord), (["undo", "one", "word"], .undoWord),
        (["undo", "1", "word"], .undoWord), (["undo", "word"], .undoWord),
        (["edit", "last", "word"], .editWord), (["edit", "word"], .editWord),
        (["edit", "prompt"], .editPrompt),
        (["done", "editing"], .endEdit), (["stop", "editing"], .endEdit), (["end", "edit"], .endEdit),
        (["full", "stop"], .fullStop), (["question", "mark"], .question),
        (["exclamation", "mark"], .exclaim), (["exclamation", "point"], .exclaim),
        (["new", "paragraph"], .newParagraph), (["new", "line"], .newLine),
        (["accept", "all", "suggestions"], .acceptAll), (["accept", "all"], .acceptAll),
        (["accept", "suggestions"], .accept), (["accept", "suggestion"], .accept), (["use", "suggestion"], .accept), (["accept"], .accept),
        (["dismiss", "suggestions"], .dismiss), (["ignore", "suggestions"], .dismiss), (["clear", "suggestions"], .dismiss),
        (["hash", "tag"], .hash), (["hash", "sign"], .hash), (["pound", "sign"], .hash), (["number", "sign"], .hash),
        (["hashtag"], .hash), (["hash"], .hash),
        (["at", "the", "rate"], .mention), (["at", "sign"], .mention), (["at", "symbol"], .mention), (["mention"], .mention),
        (["equals", "sign"], .equals), (["equal", "sign"], .equals), (["equal", "to"], .equals), (["equals"], .equals), (["equal"], .equals),
        (["comma"], .comma),
        (["enter"], .enter), (["inter"], .enter), (["entre"], .enter),
    ]

    private static let table = phrases.sorted { $0.0.count > $1.0.count }
    private static let fileSuffixes: Set<String> = ["media", "app", "ai", "web", "gif", "e"]
    private static let fillers: Set<String> = ["the", "todays", "current", "today"]
    private static let heardAsNumber: [String: Int] = ["to": 2, "too": 2, "tu": 2, "for": 4, "fore": 4, "won": 1]

    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    private static func norm(_ word: String) -> String {
        String(word.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    // MARK: Sites

    /// The speech recogniser often mishears short product names, so each site also answers to its common mishearings.
    static func aliases(for name: String) -> Set<String> {
        let base = norm(name)
        var set: Set<String> = [base]
        switch base {
        case "chatgpt": set.formUnion(["chatgbt", "chatjpt", "chatgp", "chatcpt", "chatgpd", "chatgbd"])
        case "claude": set.formUnion(["cloud", "clod", "clawed", "claud", "clode", "claudia"])
        case "grok": set.formUnion(["grock", "groc", "croc", "grokk", "rock"])
        case "gemini": set.formUnion(["jiminy", "gemni", "geminie", "gemin"])
        case "perplexity": set.formUnion(["perplexed", "perplexitee"])
        default: break
        }
        return set
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a)
        let y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[y.count]
    }

    /// The site a spoken name means: exactly, by a known mishearing, or by being one or two letters off.
    static func bestTarget(_ spoken: String, _ targets: [PromptTarget]) -> PromptTarget? {
        guard spoken.count >= 3 else { return nil }
        if let exact = targets.first(where: { aliases(for: $0.name).contains(spoken) }) { return exact }
        var best: (PromptTarget, Int)?
        var tie = false
        for target in targets {
            let distance = aliases(for: target.name).map { editDistance(spoken, $0) }.min() ?? 99
            let limit = norm(target.name).count <= 4 ? 1 : 2
            guard distance <= limit else { continue }
            if let current = best {
                if distance < current.1 { best = (target, distance); tie = false } else if distance == current.1 { tie = true }
            } else {
                best = (target, distance)
            }
        }
        return tie ? nil : best?.0
    }

    private static func matchTarget(_ keys: [String], from start: Int, _ targets: [PromptTarget]) -> (PromptTarget, Int)? {
        var length = min(3, keys.count - start)
        while length >= 1 {
            let spoken = keys[start..<(start + length)].joined()
            if let target = bestTarget(spoken, targets) { return (target, length) }
            length -= 1
        }
        return nil
    }

    // MARK: Matching phrases

    private static func match(_ keys: [String], at index: Int) -> (Command, Int)? {
        for entry in table {
            let words = entry.0
            if index + words.count <= keys.count, Array(keys[index..<(index + words.count)]) == words {
                return (entry.1, words.count)
            }
        }
        return nil
    }

    /// A symbol the recogniser wrote out on its own, such as "#" or "=".
    private static func symbolCommand(_ word: String) -> Command? {
        switch word {
        case "#": return .hash
        case "@": return .mention
        case "=": return .equals
        default: return nil
        }
    }

    private static func functionName(_ key: String) -> String? {
        if key == "today" { return "date" }
        return PromptFunctions.names.contains(where: { $0.name == key }) ? key : nil
    }

    // MARK: Text edits

    private static func append(_ piece: String, to head: inout String) {
        if head.isEmpty || head.hasSuffix(" ") || head.hasSuffix("\n") { head += piece } else { head += " " + piece }
    }

    private static func appendMark(_ mark: String, to head: inout String) {
        while head.hasSuffix(" ") { head.removeLast() }
        head += mark
    }

    private static func removeLastWord(_ head: inout String) {
        while let last = head.last, last.isWhitespace { head.removeLast() }
        while let last = head.last, !last.isWhitespace { head.removeLast() }
    }

    private static func removeLastSentence(_ head: inout String) {
        while let last = head.last, last.isWhitespace { head.removeLast() }
        if let last = head.last, ".!?".contains(last) { head.removeLast() }
        while let last = head.last, !".!?\n".contains(last) { head.removeLast() }
    }

    private static func split(_ full: String, around key: String) -> (String, String)? {
        guard !key.isEmpty else { return nil }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: key) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = full as NSString
        let matches = regex.matches(in: full, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last else { return nil }
        return (ns.substring(to: last.range.location), ns.substring(from: last.range.location + last.range.length))
    }

    // MARK: Numbers and sums

    private static func number(_ keys: [String], at start: Int) -> (String, Int)? {
        guard start < keys.count else { return nil }
        let first = keys[start]
        if !first.isEmpty, first.allSatisfy({ $0.isNumber }) { return (first, 1) }
        var total = 0
        var current = 0
        var kind = 0
        var any = false
        var i = start
        loop: while i < keys.count {
            let key = keys[i]
            if let unit = units[key] {
                if kind == 1 || (kind == 2 && unit >= 10) { break loop }
                current += unit
                kind = 1
            } else if let ten = tens[key] {
                if kind != 0 { break loop }
                current += ten
                kind = 2
            } else if key == "hundred", any {
                current = max(current, 1) * 100
                kind = 0
            } else if key == "thousand", any {
                total += max(current, 1) * 1000
                current = 0
                kind = 0
            } else {
                break loop
            }
            any = true
            i += 1
        }
        guard any else { return nil }
        var result = String(total + current)
        var consumed = i - start
        if i < keys.count, keys[i] == "point" {
            var j = i + 1
            var digits = ""
            while j < keys.count, let digit = units[keys[j]], digit < 10 {
                digits += String(digit)
                j += 1
            }
            if !digits.isEmpty {
                result += "." + digits
                consumed = j - start
            }
        }
        return (result, consumed)
    }

    /// "1", "one" and the usual mishearings ("to", "for") as a suggestion number.
    private static func spokenIndex(_ keys: [String], at start: Int) -> (Int, Int)? {
        guard start < keys.count else { return nil }
        if let found = number(keys, at: start), let value = Int(found.0) { return (value, found.1) }
        if let value = heardAsNumber[keys[start]] { return (value, 1) }
        return nil
    }

    private static func mathExpression(_ keys: [String], from start: Int) -> (String, Int)? {
        var expression = ""
        var i = start
        var sawNumber = false
        while i < keys.count {
            if let found = number(keys, at: i) {
                expression += found.0
                i += found.1
                sawNumber = true
                continue
            }
            var symbol: String?
            var width = 1
            switch keys[i] {
            case "plus": symbol = "+"
            case "minus": symbol = "-"
            case "times": symbol = "*"
            case "over": symbol = "/"
            case "multiplied", "divided":
                symbol = keys[i] == "divided" ? "/" : "*"
                if i + 1 < keys.count, keys[i + 1] == "by" { width = 2 }
            default: break
            }
            guard let op = symbol, !expression.isEmpty else { break }
            expression += op
            i += width
        }
        guard sawNumber, PromptFunctions.evaluate("=" + expression) != nil else { return nil }
        return (expression, i - start)
    }

    // MARK: Names after "hash" and "mention"

    private static func digitWord(_ key: String) -> String {
        if let value = units[key], value < 10 { return String(value) }
        return key
    }

    /// The spoken name written with its mark. A name you have is found even when spoken loosely
    /// ("rohit media" for rohit.media, "thumbs up" for thumbs-up, "photo one" for photo1).
    private static func spokenToken(marker: String, keys: [String], from next: Int, index: PromptMarkIndex) -> (String, Int)? {
        guard next < keys.count, !keys[next].isEmpty else { return nil }
        var length = min(4, keys.count - next)
        while length >= 1 {
            let slice = Array(keys[next..<(next + length)]).filter { $0 != "dot" }
            let plain = slice.joined()
            let digits = slice.map { digitWord($0) }.joined()
            if let entry = index.bySpoken[plain] ?? index.bySpoken[digits] { return (entry.token, next + length) }
            length -= 1
        }
        var token = marker + keys[next]
        var j = next + 1
        while j + 1 < keys.count, keys[j] == "dot" {
            token += "." + keys[j + 1]
            j += 2
        }
        if !token.contains("."), j < keys.count, fileSuffixes.contains(keys[j]) {
            token += "." + keys[j]
            j += 1
        }
        return (token, j)
    }

    // MARK: Putting it together

    /// Turns everything said in one listening session into the prompt text. It starts again from `base`
    /// (the text before listening began) on every call, so partial results can be revised freely.
    static func apply(base: String, spoken: String, targets: [PromptTarget], index: PromptMarkIndex, dismissed: Set<String>) -> PromptVoiceResult {
        let words = spoken.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let keys = words.map { norm($0) }
        var head = base
        var tail = ""
        var sends: [PromptTarget] = []
        var notice = ""
        var skipped = dismissed
        var i = 0

        while i < words.count {
            guard let found = symbolCommand(words[i]).map({ ($0, 1) }) ?? match(keys, at: i) else {
                append(words[i], to: &head)
                i += 1
                continue
            }
            let next = i + found.1
            switch found.0 {
            case .comma: appendMark(",", to: &head); i = next
            case .fullStop: appendMark(".", to: &head); i = next
            case .question: appendMark("?", to: &head); i = next
            case .exclaim: appendMark("!", to: &head); i = next
            case .newLine: appendMark("\n", to: &head); i = next
            case .newParagraph: appendMark("\n\n", to: &head); i = next
            case .undoWord, .editWord:
                removeLastWord(&head)
                if found.0 == .editWord { notice = "Say the new word" }
                i = next
            case .undoSentence:
                removeLastSentence(&head)
                i = next
            case .endEdit:
                head += tail
                tail = ""
                i = next
            case .editPrompt:
                if next < words.count {
                    var after = next + 1
                    if after < words.count, keys[after] == "to" || keys[after] == "with" { after += 1 }
                    if let parts = split(head + tail, around: keys[next]) {
                        head = parts.0
                        tail = parts.1
                        notice = "Editing “\(words[next])”: say the new words, or “end edit”"
                    } else {
                        notice = "Could not find “\(words[next])” in the prompt"
                    }
                    i = after
                } else {
                    notice = "Say the word to change, for example: edit prompt rohit"
                    i = next
                }
            case .hash, .mention:
                if let result = spokenToken(marker: found.0 == .hash ? "#" : "@", keys: keys, from: next, index: index) {
                    append(result.0, to: &head)
                    i = result.1
                } else {
                    append(words[i], to: &head)
                    i = next
                }
            case .equals:
                var j = next
                while j < keys.count, fillers.contains(keys[j]), functionName(keys[j]) == nil || keys[j] == "today" && j + 1 < keys.count { j += 1 }
                if j < keys.count, let name = functionName(keys[j]) {
                    append("=" + name, to: &head)
                    i = j + 1
                } else if let sum = mathExpression(keys, from: next) {
                    append("=" + sum.0, to: &head)
                    i = next + sum.1
                } else {
                    append(words[i], to: &head)
                    i = next
                }
            case .enter:
                if let target = matchTarget(keys, from: next, targets) {
                    sends.append(target.0)
                    i = next + target.1
                } else {
                    append(words[i], to: &head)
                    i = next
                }
            case .accept, .acceptAll, .dismiss:
                var full = head + tail
                if found.0 == .dismiss {
                    for fix in PromptFixes.fixes(in: full, index: index, dismissed: skipped, limit: 200) { skipped.insert(fix.key) }
                    notice = "Suggestions hidden"
                    i = next
                } else if found.0 == .acceptAll {
                    let list = PromptFixes.fixes(in: full, index: index, dismissed: skipped, limit: 200)
                    full = PromptFixes.applyAll(list, to: full)
                    head = full
                    tail = ""
                    notice = list.isEmpty ? "No suggestions to accept" : "Accepted \(list.count) suggestion\(list.count == 1 ? "" : "s")"
                    i = next
                } else {
                    let spokenNumber = spokenIndex(keys, at: next)
                    if found.1 == 1 && spokenNumber == nil {
                        append(words[i], to: &head)
                        i = next
                    } else {
                        let wanted = spokenNumber?.0 ?? 1
                        let list = PromptFixes.fixes(in: full, index: index, dismissed: skipped)
                        if wanted >= 1 && wanted <= list.count {
                            head = PromptFixes.apply(list[wanted - 1], to: full)
                            tail = ""
                            notice = "Accepted suggestion \(wanted): \(list[wanted - 1].token)"
                        } else {
                            notice = "There is no suggestion \(wanted)"
                        }
                        i = next + (spokenNumber?.1 ?? 0)
                    }
                }
            }
        }
        return PromptVoiceResult(text: head + tail, sends: sends, notice: notice, dismissed: skipped)
    }
}

// MARK: - The microphone button

/// Listens continuously, so a long prompt, a command and "enter chatgpt" can follow each other without pressing
/// the button again. `onText` gets everything said since listening started or since the last pause (final = true).
struct PromptMicButton: View {
    var onStart: () -> Void
    var onStop: () -> Void
    var onText: (String, Bool) -> Void
    @StateObject private var speech = EzMeSpeechDictation()
    @State private var showError = false

    var body: some View {
        Button {
            if speech.isListening {
                speech.stop()
                onStop()
            } else {
                onStart()
                speech.startContinuous(onTranscript: { spoken in onText(spoken, true) }, onPartial: { spoken in onText(spoken, false) })
            }
        } label: {
            Label(speech.isListening ? "Stop listening" : "Speak", systemImage: speech.isListening ? "stop.circle.fill" : "mic.fill")
                .foregroundStyle(speech.isListening ? .red : .blue)
        }
        .buttonStyle(.bordered)
        .onChange(of: speech.errorMessage) { value in showError = !value.isEmpty }
        .alert("Voice input", isPresented: $showError) {
            Button("OK") { speech.clearError() }
        } message: {
            Text(speech.errorMessage)
        }
    }
}
