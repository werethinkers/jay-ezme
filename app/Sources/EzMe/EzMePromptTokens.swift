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
import Foundation

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

    private static func symbol(for clip: Clip) -> String {
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

    static func suggestions(for token: String, clips: [Clip], records: [CollectionRecord]) -> [PromptSuggestion] {
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
            for clip in clips where clip.appBundleIdentifier != nil || clip.webURL != nil {
                let key = trimmedKey(clip.key)
                guard !key.isEmpty, let r = rank(key) ?? rank(clip.name) else { continue }
                found.append((r, PromptSuggestion(title: "@" + key, detail: clip.name, insert: "@" + key, symbol: symbol(for: clip))))
            }
        default:
            break
        }
        let ordered = found.sorted { $0.0 < $1.0 }.prefix(8).map { $0.1 }
        return Array(ordered)
    }
}

// MARK: - Spoken commands

struct PromptVoiceResult {
    var text: String
    var sends: [PromptTarget]
    var notice: String
}

enum PromptVoice {
    /// What each spoken command does, for the help list in the app.
    static let helpRows: [(say: String, result: String)] = [
        ("hash rohit dot media", "writes #rohit.media"),
        ("mention priya", "writes @priya"),
        ("equals date", "writes =date, which becomes today's date"),
        ("equals two plus five", "writes =2+5, which becomes 7"),
        ("comma · full stop · question mark · new line", "adds that mark"),
        ("undo one word", "deletes the last word"),
        ("undo one sentence", "deletes the last sentence"),
        ("edit word", "deletes the last word, then say the new one"),
        ("edit prompt rohit", "finds that word, removes it, and your next words go in its place"),
        ("end edit", "go back to the end of the prompt"),
        ("enter chatgpt · grok · claude · gemini", "opens that site in the side panel and sends the prompt"),
    ]

    private enum Command {
        case comma, fullStop, question, exclaim, newLine, newParagraph
        case undoWord, undoSentence, editWord, editPrompt, endEdit
        case hash, mention, equals, enter
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
        (["at", "sign"], .mention),
        (["comma"], .comma), (["hashtag"], .hash), (["hash"], .hash),
        (["mention"], .mention), (["equals"], .equals), (["enter"], .enter),
    ]

    private static let table = phrases.sorted { $0.0.count > $1.0.count }
    private static let fileSuffixes: Set<String> = ["media", "app", "ai", "web", "gif", "e"]

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

    /// The speech recogniser often mishears short product names, so each site also answers to its common mishearings.
    static func aliases(for name: String) -> Set<String> {
        let base = norm(name)
        var set: Set<String> = [base]
        switch base {
        case "chatgpt": set.formUnion(["chatgbt", "chatjpt", "chatgp", "chat"])
        case "claude": set.formUnion(["cloud", "clod", "clawed", "claud", "clode"])
        case "grok": set.formUnion(["grock", "groc", "croc", "grokk"])
        case "gemini": set.formUnion(["jiminy", "gemni", "geminie"])
        default: break
        }
        return set
    }

    private static func match(_ keys: [String], at index: Int) -> (Command, Int)? {
        for entry in table {
            let words = entry.0
            if index + words.count <= keys.count, Array(keys[index..<(index + words.count)]) == words {
                return (entry.1, words.count)
            }
        }
        return nil
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

    // MARK: Putting it together

    /// Turns everything said in one listening session into the prompt text. It starts again from `base`
    /// (the text before listening began) on every call, so partial results can be revised freely.
    static func apply(base: String, spoken: String, targets: [PromptTarget]) -> PromptVoiceResult {
        let words = spoken.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let keys = words.map { norm($0) }
        var head = base
        var tail = ""
        var sends: [PromptTarget] = []
        var notice = ""
        var i = 0

        while i < words.count {
            guard let found = match(keys, at: i) else {
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
                if next < words.count, !keys[next].isEmpty {
                    var token = (found.0 == .hash ? "#" : "@") + keys[next]
                    var j = next + 1
                    while j + 1 < words.count, keys[j] == "dot" {
                        token += "." + keys[j + 1]
                        j += 2
                    }
                    if !token.contains("."), j < words.count, fileSuffixes.contains(keys[j]) {
                        token += "." + keys[j]
                        j += 1
                    }
                    append(token, to: &head)
                    i = j
                } else {
                    append(words[i], to: &head)
                    i = next
                }
            case .equals:
                if next < keys.count, PromptFunctions.names.contains(where: { $0.name == keys[next] }) {
                    append("=" + keys[next], to: &head)
                    i = next + 1
                } else if let sum = mathExpression(keys, from: next) {
                    append("=" + sum.0, to: &head)
                    i = next + sum.1
                } else {
                    append(words[i], to: &head)
                    i = next
                }
            case .enter:
                var matched = false
                var length = min(3, keys.count - next)
                while length >= 1 && !matched {
                    let spokenName = keys[next..<(next + length)].joined()
                    if let target = targets.first(where: { aliases(for: $0.name).contains(spokenName) }) {
                        sends.append(target)
                        i = next + length
                        matched = true
                    }
                    length -= 1
                }
                if !matched {
                    append(words[i], to: &head)
                    i = next
                }
            }
        }
        return PromptVoiceResult(text: head + tail, sends: sends, notice: notice)
    }
}
