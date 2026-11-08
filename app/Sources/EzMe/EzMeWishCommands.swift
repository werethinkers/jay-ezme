// WishStudio voice and typed commands: one sentence in, a list of edits out.
// English and Hindi (Devanagari or Latin letters). Foundation only.
import Foundation

enum WishColorTarget: Equatable {
    case auto
    case background
    case text
    case accent
}

enum WishAction: Equatable {
    case setField(key: String, value: String)
    case useRecord(key: String, value: String)
    case color(WishColorTarget, hex: String, name: String)
    case scale(Double)
    case move(dx: Double, dy: Double)
    case bold
    case italic
    case plain
    case hide
    case show
    case fontStyle(WishFontStyle)
    case design(String)
    case stepDesign(Int)
    case switchApp(String)
    case language(WishLanguage)
    case magicDelta(Int)
    case magicLevel(Int)
    case undo
    case redo
    case reset
    case export
    case copyImage
    case newCard
    case clearSelection

    /// Which switch in WishBuilder's Live Changes step controls this action. nil = always allowed.
    var group: String? {
        switch self {
        case .setField: return "Fields"
        case .useRecord: return "Collections"
        case .color: return "Colors"
        case .scale, .move, .bold, .italic, .plain, .hide, .show, .fontStyle: return "Text"
        case .design, .stepDesign, .switchApp: return "Design"
        case .language: return "Language"
        case .magicDelta, .magicLevel: return "Magic"
        case .export, .copyImage, .newCard: return "Output"
        case .undo, .redo, .reset, .clearSelection: return nil
        }
    }
}

struct WishCommand: Equatable {
    var action: WishAction
    /// An element named in the sentence ("make the title bigger"). nil = the selection, or the whole card.
    var target: String? = nil
}

/// A value from one of the app's linked collections, offered as a chip and understood by "use ...".
struct WishChip: Hashable {
    var fieldKey: String
    var value: String
    var label: String
}

struct WishCommandEnvironment {
    var app: WishApp
    var apps: [WishApp]
    var designs: [WishDesign]
    var chips: [WishChip]
}

enum WishCommandParser {
    // MARK: Vocabulary

    private static let colorTable: [(names: [String], hex: String)] = [
        (["pink", "\u{0917}\u{0941}\u{0932}\u{093E}\u{092C}\u{0940}", "gulabi"], "#EC6AA8"),
        (["red", "\u{0932}\u{093E}\u{0932}", "laal", "lal"], "#D63B3B"),
        (["orange", "\u{0928}\u{093E}\u{0930}\u{0902}\u{0917}\u{0940}"], "#F28A2E"),
        (["saffron", "kesariya", "\u{0915}\u{0947}\u{0938}\u{0930}\u{093F}\u{092F}\u{093E}"], "#E67E00"),
        (["yellow", "\u{092A}\u{0940}\u{0932}\u{093E}", "peela"], "#F2C230"),
        (["gold", "golden", "\u{0938}\u{0941}\u{0928}\u{0939}\u{0930}\u{093E}", "sunehra"], "#C9A227"),
        (["green", "\u{0939}\u{0930}\u{093E}", "hara"], "#3FA66A"),
        (["teal", "turquoise"], "#1E9E9E"),
        (["mint"], "#BFE8CF"),
        (["blue", "\u{0928}\u{0940}\u{0932}\u{093E}", "neela"], "#3B6FD6"),
        (["sky blue", "light blue", "\u{0906}\u{0938}\u{092E}\u{093E}\u{0928}\u{0940}"], "#7FB8F0"),
        (["navy", "dark blue"], "#1F2A55"),
        (["purple", "violet", "\u{092C}\u{0948}\u{0902}\u{0917}\u{0928}\u{0940}", "\u{091C}\u{093E}\u{092E}\u{0941}\u{0928}\u{0940}", "baingani"], "#7B52B8"),
        (["lavender"], "#B9A3E3"),
        (["black", "\u{0915}\u{093E}\u{0932}\u{093E}", "kala"], "#1A1A1A"),
        (["white", "\u{0938}\u{092B}\u{0947}\u{0926}", "\u{0938}\u{092B}\u{093C}\u{0947}\u{0926}", "safed"], "#FFFFFF"),
        (["grey", "gray", "\u{0938}\u{094D}\u{0932}\u{0947}\u{091F}\u{0940}", "\u{0917}\u{094D}\u{0930}\u{0947}"], "#8A8A8A"),
        (["brown", "\u{092D}\u{0942}\u{0930}\u{093E}"], "#8B5A2B"),
        (["maroon"], "#800000"),
        (["cream", "\u{0915}\u{094D}\u{0930}\u{0940}\u{092E}"], "#FFF1D6"),
        (["peach"], "#FFC9AE"),
    ]

    private static let biggerWords = ["bigger", "larger", "increase", "enlarge", "zoom in", "grow", "big", "large", "\u{092C}\u{0921}\u{093C}\u{093E}", "\u{092C}\u{0921}\u{093C}\u{0940}", "\u{092C}\u{0922}\u{093C}\u{093E}\u{0913}", "\u{092C}\u{0922}\u{093C}\u{093E}"]
    private static let smallerWords = ["smaller", "decrease", "reduce", "shrink", "zoom out", "small", "tiny", "\u{091B}\u{094B}\u{091F}\u{093E}", "\u{091B}\u{094B}\u{091F}\u{0940}", "\u{0918}\u{091F}\u{093E}\u{0913}", "\u{0915}\u{092E} \u{0915}\u{0930}\u{094B}"]
    private static let directions: [(words: [String], dx: Double, dy: Double)] = [
        (["left", "\u{092C}\u{093E}\u{090F}\u{0902}", "\u{092C}\u{093E}\u{090F}\u{0901}", "\u{0932}\u{0947}\u{092B}\u{094D}\u{091F}"], -1, 0),
        (["right", "\u{0926}\u{093E}\u{090F}\u{0902}", "\u{0926}\u{093E}\u{090F}\u{0901}", "\u{0930}\u{093E}\u{0907}\u{091F}"], 1, 0),
        (["up", "upward", "\u{090A}\u{092A}\u{0930}"], 0, -1),
        (["down", "downward", "\u{0928}\u{0940}\u{091A}\u{0947}"], 0, 1),
    ]
    private static let boldWords = ["bold", "\u{092E}\u{094B}\u{091F}\u{093E}", "\u{092C}\u{094B}\u{0932}\u{094D}\u{0921}"]
    private static let italicWords = ["italic", "italics", "slanted", "\u{0924}\u{093F}\u{0930}\u{091B}\u{093E}", "\u{0907}\u{091F}\u{0948}\u{0932}\u{093F}\u{0915}"]
    private static let plainWords = ["plain", "normal", "unbold", "regular", "\u{0938}\u{093E}\u{0927}\u{093E}\u{0930}\u{0923}"]
    private static let hideWords = ["hide", "remove", "delete", "hidden", "\u{0939}\u{091F}\u{093E}\u{0913}", "\u{091B}\u{0941}\u{092A}\u{093E}\u{0913}"]
    private static let showWords = ["show", "unhide", "restore", "visible", "\u{0926}\u{093F}\u{0916}\u{093E}\u{0913}"]
    private static let artworkWords = ["artwork", "picture", "image", "icon", "illustration", "drawing", "\u{091A}\u{093F}\u{0924}\u{094D}\u{0930}", "\u{0924}\u{0938}\u{094D}\u{0935}\u{0940}\u{0930}", "\u{0906}\u{0907}\u{0915}\u{0928}"]
    private static let modifiers = ["a little", "a bit", "slightly", "much", "very", "a lot", "far", "more", "\u{0925}\u{094B}\u{0921}\u{093C}\u{093E}", "\u{092C}\u{0939}\u{0941}\u{0924}"]

    // MARK: Helpers

    private static func regex(_ pattern: String, _ text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = expression.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var groups: [String] = []
        for index in 0..<match.numberOfRanges {
            let range = match.range(at: index)
            groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
        }
        return groups
    }

    private static func hasWord(_ word: String, in lower: String) -> Bool {
        let isLatin = word.unicodeScalars.allSatisfy { $0.isASCII }
        if isLatin {
            let escaped = NSRegularExpression.escapedPattern(for: word)
            return regex("(?<![a-z0-9])" + escaped + "(?![a-z0-9])", lower) != nil
        }
        return lower.contains(word)
    }

    private static func hasAny(_ words: [String], in lower: String) -> Bool {
        return words.contains { hasWord($0, in: lower) }
    }

    private static func colorMatch(in lower: String) -> (name: String, hex: String)? {
        var flat: [(name: String, hex: String)] = []
        for entry in colorTable {
            for name in entry.names { flat.append((name, entry.hex)) }
        }
        flat.sort { $0.name.count > $1.name.count }
        for item in flat where hasWord(item.name, in: lower) { return item }
        return nil
    }

    private static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let fillers = "^(?:please|kindly|ok|okay|hey|hi|can you|could you|will you|would you|let's|lets|just|\u{0915}\u{0943}\u{092A}\u{092F}\u{093E})\\s+"
        while let groups = regex(fillers, text) {
            text = String(text.dropFirst(groups[0].count))
        }
        while let last = text.last, ".!?\u{0964},".contains(last) {
            text.removeLast()
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripModifiers(_ value: String) -> String {
        var text = value.lowercased().trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            for modifier in modifiers where text.hasPrefix(modifier + " ") {
                text = String(text.dropFirst(modifier.count + 1))
                changed = true
            }
        }
        return text
    }

    /// True when a value is really a command word ("pink", "bigger"), not text to put on the card.
    private static func isCommandWord(_ value: String) -> Bool {
        let text = stripModifiers(value)
        if text.isEmpty { return false }
        var all: [String] = biggerWords + smallerWords + boldWords + italicWords + plainWords + hideWords + showWords
        for direction in directions { all.append(contentsOf: direction.words) }
        for entry in colorTable { all.append(contentsOf: entry.names) }
        for word in all {
            if text == word || text == word + " color" || text == word + " colour" { return true }
        }
        return false
    }

    private static func elementTarget(in lower: String, env: WishCommandEnvironment) -> String? {
        var candidates: [(label: String, key: String)] = []
        for field in env.app.fields {
            for name in [field.label, field.labelHi, field.key] where !name.isEmpty {
                candidates.append((name.lowercased(), field.key))
            }
        }
        candidates.sort { $0.label.count > $1.label.count }
        for candidate in candidates where hasWord(candidate.label, in: lower) { return candidate.key }
        if hasAny(artworkWords, in: lower) { return "artwork" }
        return nil
    }

    private static func normalizedNumbers(_ lower: String) -> String {
        let words = ["one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10", "eleven": "11", "twelve": "12", "fifteen": "15"]
        var text = lower
        for (word, digit) in words { text = text.replacingOccurrences(of: "\\b" + word + "\\b", with: digit, options: .regularExpression) }
        return text
    }

    // MARK: Entry point

    static func parse(_ transcript: String, env: WishCommandEnvironment) -> [WishCommand] {
        let text = clean(transcript)
        guard !text.isEmpty else { return [] }
        let lower = text.lowercased()

        if let simple = simpleCommand(lower) { return [WishCommand(action: simple)] }
        if let fields = fieldCommands(text, env: env) { return fields }

        var commands: [WishCommand] = []
        for clause in splitClauses(text) {
            commands.append(contentsOf: clauseCommands(clause, env: env))
        }
        return commands
    }

    private static func splitClauses(_ text: String) -> [String] {
        let pattern = "\\s+(?:and then|and|then|also|plus)\\s+|\\s*,\\s*|\\s+(?:\u{0914}\u{0930}|\u{092B}\u{093F}\u{0930}|\u{0924}\u{0925}\u{093E})\\s+"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [text] }
        let ns = text as NSString
        var parts: [String] = []
        var cursor = 0
        for match in expression.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            parts.append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            cursor = match.range.location + match.range.length
        }
        parts.append(ns.substring(from: cursor))
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func simpleCommand(_ lower: String) -> WishAction? {
        if regex("^(?:undo|undo that|go back|step back|revert|\u{092A}\u{0940}\u{091B}\u{0947}|\u{0935}\u{093E}\u{092A}\u{0938}|\u{0905}\u{0928}\u{0921}\u{0942}|\u{092A}\u{0942}\u{0930}\u{094D}\u{0935}\u{0935}\u{0924})$", lower) != nil { return .undo }
        if regex("^(?:redo|do it again|\u{0906}\u{0917}\u{0947}|\u{0930}\u{0940}\u{0921}\u{0942})$", lower) != nil { return .redo }
        if regex("^(?:reset|reset card|reset all|start over|clear all|\u{0930}\u{0940}\u{0938}\u{0947}\u{091F})$", lower) != nil { return .reset }
        if regex("^(?:download|export|save|save image|save card|download png|download card|download image|\u{0921}\u{093E}\u{0909}\u{0928}\u{0932}\u{094B}\u{0921}|\u{0938}\u{0947}\u{0935})$", lower) != nil { return .export }
        if regex("^(?:copy|copy image|copy card|copy picture|\u{0915}\u{0949}\u{092A}\u{0940})$", lower) != nil { return .copyImage }
        if regex("^(?:new card|new one|another card|\u{0928}\u{092F}\u{093E} \u{0915}\u{093E}\u{0930}\u{094D}\u{0921})$", lower) != nil { return .newCard }
        if regex("^(?:deselect|clear selection|select nothing|whole card|\u{091A}\u{092F}\u{0928} \u{0939}\u{091F}\u{093E}\u{0913})$", lower) != nil { return .clearSelection }
        return nil
    }

    // MARK: Setting a field

    private static func fieldCommands(_ text: String, env: WishCommandEnvironment) -> [WishCommand]? {
        var candidates: [(label: String, key: String)] = []
        for field in env.app.fields {
            for name in [field.label, field.labelHi, field.key] where !name.isEmpty {
                candidates.append((name.lowercased(), field.key))
            }
        }
        candidates.sort { $0.label.count > $1.label.count }

        for candidate in candidates {
            let escaped = NSRegularExpression.escapedPattern(for: candidate.label)
            let verbs = "(?:set|change|make|update|put|write|type|edit|replace|enter|\u{092C}\u{0926}\u{0932}\u{094B}|\u{0932}\u{093F}\u{0916}\u{094B}|\u{092C}\u{0926}\u{0932} \u{0926}\u{094B})"
            let pattern = "^(?:" + verbs + "\\s+)?(?:the\\s+|my\\s+)?" + escaped + "(?:\\s+(?:to|as|is|\u{0915}\u{094B}|\u{0939}\u{0948}))?\\s*[:=,\\-]?\\s+(.+)$"
            guard let groups = regex(pattern, text), groups.count > 1 else { continue }
            var value = groups[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty || isCommandWord(value) { continue }

            var rest: String? = nil
            for other in candidates where other.key != candidate.key {
                let otherEscaped = NSRegularExpression.escapedPattern(for: other.label)
                let splitPattern = "^(.*?)\\s+(?:and|then|\u{0914}\u{0930})\\s+((?:set\\s+|change\\s+|the\\s+|my\\s+)*" + otherEscaped + "\\s+.+)$"
                if let parts = regex(splitPattern, value), parts.count > 2, !parts[1].isEmpty {
                    value = parts[1].trimmingCharacters(in: .whitespaces)
                    rest = parts[2]
                    break
                }
            }
            var commands = [WishCommand(action: .setField(key: candidate.key, value: value))]
            if let rest = rest { commands.append(contentsOf: parse(rest, env: env)) }
            return commands
        }
        return nil
    }

    // MARK: One clause

    private static func clauseCommands(_ clause: String, env: WishCommandEnvironment) -> [WishCommand] {
        let lower = clause.lowercased()
        let numeric = normalizedNumbers(lower)
        var out: [WishCommand] = []

        if let simple = simpleCommand(lower) { return [WishCommand(action: simple)] }

        // Language
        let wantsHindi = hasAny(["hindi", "\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}", "\u{0939}\u{093F}\u{0902}\u{0926}\u{0940}"], in: lower)
        let wantsEnglish = hasAny(["english", "\u{0905}\u{0902}\u{0917}\u{094D}\u{0930}\u{0947}\u{091C}\u{093C}\u{0940}", "\u{0905}\u{0902}\u{0917}\u{094D}\u{0930}\u{0947}\u{091C}\u{0940}"], in: lower)
        if wantsHindi != wantsEnglish {
            return [WishCommand(action: .language(wantsHindi ? .hindi : .english))]
        }

        // Magic
        if hasAny(["magic", "sparkles", "sparkle", "\u{091C}\u{093E}\u{0926}\u{0942}"], in: lower) {
            if hasAny(["no", "stop", "off", "without", "\u{092C}\u{0902}\u{0926}"], in: lower) { return [WishCommand(action: .magicLevel(0))] }
            if hasAny(["full", "max", "maximum", "most"], in: lower) { return [WishCommand(action: .magicLevel(3))] }
            if hasAny(["less", "reduce", "lower", "decrease", "\u{0915}\u{092E}"], in: lower) { return [WishCommand(action: .magicDelta(-1))] }
            return [WishCommand(action: .magicDelta(1))]
        }

        // Lettering
        if hasAny(["romantic", "script"], in: lower) { return [WishCommand(action: .fontStyle(.romantic))] }
        if hasAny(["serif", "classic"], in: lower) { return [WishCommand(action: .fontStyle(.classic))] }
        if hasAny(["modern", "sans", "clean font"], in: lower) { return [WishCommand(action: .fontStyle(.modern))] }

        // Designs
        if regex("^(?:the\\s+)?(?:next|another)(?:\\s+(?:design|one|style|theme|card))?$", lower) != nil || hasAny(["\u{0905}\u{0917}\u{0932}\u{093E}"], in: lower) {
            return [WishCommand(action: .stepDesign(1))]
        }
        if regex("^(?:the\\s+)?(?:previous|prev|last)(?:\\s+(?:design|one|style|theme|card))?$", lower) != nil || hasAny(["\u{092A}\u{093F}\u{091B}\u{0932}\u{093E}"], in: lower) {
            return [WishCommand(action: .stepDesign(-1))]
        }
        if let groups = regex("(?:design|style|theme|number|\u{0921}\u{093F}\u{091C}\u{093C}\u{093E}\u{0907}\u{0928}|\u{0928}\u{0902}\u{092C}\u{0930})\\s*(?:no\\.?\\s*)?(\\d{1,2})", numeric), let number = Int(groups[1]), number >= 1, number <= env.designs.count {
            return [WishCommand(action: .design(env.designs[number - 1].id))]
        }
        let mentionsDesign = hasAny(["design", "theme", "style", "template"], in: lower)
        for design in env.designs {
            let full = design.name.lowercased()
            let first = full.split(separator: " ").first.map(String.init) ?? full
            if lower.contains(full) || (mentionsDesign && hasWord(first, in: lower)) {
                return [WishCommand(action: .design(design.id))]
            }
        }

        // Switching app
        let switchVerbs = ["open", "switch", "go to", "make", "create", "new", "show", "start", "\u{0916}\u{094B}\u{0932}\u{094B}", "\u{092C}\u{0928}\u{093E}\u{0913}", "\u{0926}\u{093F}\u{0916}\u{093E}\u{0913}"]
        for app in env.apps {
            var names = [app.name.lowercased(), app.nameHi.lowercased()]
            if app.name.lowercased().hasSuffix("s") { names.append(String(app.name.lowercased().dropLast())) }
            for name in names where !name.isEmpty {
                let exact = lower == name
                let withVerb = hasWord(name, in: lower) && hasAny(switchVerbs, in: lower)
                if exact || withVerb {
                    if app.id == env.app.id && !exact { continue }
                    return [WishCommand(action: .switchApp(app.id))]
                }
            }
        }

        // A value from a linked collection
        if let record = chipCommand(clause, env: env) { return [record] }

        // Dates
        if hasAny(["date", "\u{0924}\u{093E}\u{0930}\u{0940}\u{0916}"], in: lower), env.app.field("date") != nil {
            if hasAny(["tomorrow", "\u{0915}\u{0932}"], in: lower) { return [WishCommand(action: .setField(key: env.app.field("date")?.key ?? "date", value: "=Date+1"))] }
            if hasAny(["today", "todays", "today's", "insert", "add", "put", "\u{0906}\u{091C}"], in: lower) { return [WishCommand(action: .setField(key: env.app.field("date")?.key ?? "date", value: "=Date"))] }
        }

        // Edits to an element, the selection or the whole card
        let target = elementTarget(in: lower, env: env)

        if hasAny(biggerWords, in: lower) {
            var factor = 1.15
            if hasAny(["much", "a lot", "far", "very", "\u{092C}\u{0939}\u{0941}\u{0924}"], in: lower) { factor = 1.4 }
            if hasAny(["a little", "a bit", "slightly", "\u{0925}\u{094B}\u{0921}\u{093C}\u{093E}"], in: lower) { factor = 1.06 }
            out.append(WishCommand(action: .scale(factor), target: target))
        } else if hasAny(smallerWords, in: lower) {
            var factor = 0.87
            if hasAny(["much", "a lot", "far", "very", "\u{092C}\u{0939}\u{0941}\u{0924}"], in: lower) { factor = 0.7 }
            if hasAny(["a little", "a bit", "slightly", "\u{0925}\u{094B}\u{0921}\u{093C}\u{093E}"], in: lower) { factor = 0.94 }
            out.append(WishCommand(action: .scale(factor), target: target))
        }

        for direction in directions where hasAny(direction.words, in: lower) {
            var amount = 14.0
            if hasAny(["a little", "a bit", "slightly", "\u{0925}\u{094B}\u{0921}\u{093C}\u{093E}"], in: lower) { amount = 6 }
            if hasAny(["much", "a lot", "far", "more", "\u{092C}\u{0939}\u{0941}\u{0924}"], in: lower) { amount = 40 }
            out.append(WishCommand(action: .move(dx: direction.dx * amount, dy: direction.dy * amount), target: target))
            break
        }

        if hasAny(boldWords, in: lower) { out.append(WishCommand(action: .bold, target: target)) }
        if hasAny(italicWords, in: lower) { out.append(WishCommand(action: .italic, target: target)) }
        if hasAny(plainWords, in: lower) && !hasAny(boldWords + italicWords, in: lower) { out.append(WishCommand(action: .plain, target: target)) }
        if hasAny(hideWords, in: lower) {
            out.append(WishCommand(action: .hide, target: target))
        } else if hasAny(showWords, in: lower) {
            out.append(WishCommand(action: .show, target: target))
        }

        if let color = colorMatch(in: lower) {
            var colorTarget = WishColorTarget.auto
            if hasAny(["background", "bg", "backdrop", "\u{092C}\u{0948}\u{0915}\u{0917}\u{094D}\u{0930}\u{093E}\u{0909}\u{0902}\u{0921}", "\u{092A}\u{0943}\u{0937}\u{094D}\u{0920}\u{092D}\u{0942}\u{092E}\u{093F}"], in: lower) {
                colorTarget = .background
            } else if hasAny(["border", "frame", "accent", "\u{092C}\u{0949}\u{0930}\u{094D}\u{0921}\u{0930}"], in: lower) {
                colorTarget = .accent
            } else if target != nil || hasAny(["text", "font", "letters", "words", "\u{091F}\u{0947}\u{0915}\u{094D}\u{0938}\u{094D}\u{091F}", "\u{0905}\u{0915}\u{094D}\u{0937}\u{0930}"], in: lower) {
                colorTarget = .text
            }
            out.append(WishCommand(action: .color(colorTarget, hex: color.hex, name: color.name), target: target))
        }

        return out
    }

    private static func chipCommand(_ clause: String, env: WishCommandEnvironment) -> WishCommand? {
        guard !env.chips.isEmpty else { return nil }
        var candidate = clause.trimmingCharacters(in: .whitespaces)
        let prefix = "^(?:use|select|pick|choose|add|apply|for|to)\\s+(.+)$"
        if let groups = regex(prefix, candidate), groups.count > 1 { candidate = groups[1] }
        if let groups = regex("^(.+?)\\s+(?:\u{0915}\u{094B} \u{091A}\u{0941}\u{0928}\u{094B}|\u{091A}\u{0941}\u{0928}\u{094B}|\u{0915}\u{0947} \u{0932}\u{093F}\u{090F})$", candidate), groups.count > 1 { candidate = groups[1] }
        let needle = candidate.lowercased().trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return nil }
        if let exact = env.chips.first(where: { $0.value.lowercased() == needle || $0.label.lowercased() == needle }) {
            return WishCommand(action: .useRecord(key: exact.fieldKey, value: exact.value))
        }
        let usedVerb = candidate != clause.trimmingCharacters(in: .whitespaces)
        if usedVerb, let partial = env.chips.first(where: { $0.value.lowercased().contains(needle) || needle.contains($0.value.lowercased()) }) {
            return WishCommand(action: .useRecord(key: partial.fieldKey, value: partial.value))
        }
        return nil
    }

    // MARK: Describing

    static func summary(of command: WishCommand, env: WishCommandEnvironment) -> String {
        let on = command.target.map { " (\($0))" } ?? ""
        switch command.action {
        case .setField(let key, let value):
            let label = env.app.field(key)?.label ?? key
            return "\(label) \u{2192} \(value)"
        case .useRecord(let key, let value):
            let label = env.app.field(key)?.label ?? key
            return "\(label) \u{2192} \(value)"
        case .color(_, _, let name): return "Colour \u{2192} \(name)\(on)"
        case .scale(let factor): return factor > 1 ? "Bigger\(on)" : "Smaller\(on)"
        case .move(let dx, let dy):
            if dx < 0 { return "Move left\(on)" }
            if dx > 0 { return "Move right\(on)" }
            return dy < 0 ? "Move up\(on)" : "Move down\(on)"
        case .bold: return "Bold\(on)"
        case .italic: return "Italic\(on)"
        case .plain: return "Plain\(on)"
        case .hide: return "Hide\(on)"
        case .show: return "Show\(on)"
        case .fontStyle(let style): return "Lettering \u{2192} \(style.title)"
        case .design(let id): return "Design \u{2192} \(env.designs.first { $0.id == id }?.name ?? id)"
        case .stepDesign(let step): return step > 0 ? "Next design" : "Previous design"
        case .switchApp(let id): return "Open \(env.apps.first { $0.id == id }?.name ?? "app")"
        case .language(let language): return "Card language \u{2192} \(language.title)"
        case .magicDelta(let delta): return delta > 0 ? "More magic" : "Less magic"
        case .magicLevel(let level): return level == 0 ? "No magic" : "Full magic"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .reset: return "Reset card"
        case .export: return "Download PNG"
        case .copyImage: return "Copy image"
        case .newCard: return "New card"
        case .clearSelection: return "Whole card"
        }
    }
}
