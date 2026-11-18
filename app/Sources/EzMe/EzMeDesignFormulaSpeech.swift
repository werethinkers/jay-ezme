// Formulas said out loud, with no brackets: "days to event date", "today plus 7", "price times quantity",
// "sum of price and tax", "round price". Words that match a variable become that variable.
import Foundation

enum DesignFormulaSpeech {
    /// The names of the variables and boxes of the design being edited, so spoken words can be matched to them.
    static var variables: [String] = []

    private static func normal(_ text: String) -> String { TemplateFill.normal(text) }

    private static func variable(_ words: String) -> String? {
        let wanted = normal(words)
        guard !wanted.isEmpty else { return nil }
        return variables.first { normal($0) == wanted }
    }

    private static let dateWords: Set<String> = ["today", "now", "todays date", "today's date", "current date"]

    /// One word of a formula: a variable, a number, today, or plain words in quotes.
    private static func operand(_ raw: String) -> String {
        let words = raw.trimmingCharacters(in: CharacterSet(charactersIn: " ,.\"")).replacingOccurrences(of: "^(?:the|my|its)\\s+", with: "", options: .regularExpression)
        if let name = variable(words) { return "{{\(name)}}" }
        if dateWords.contains(words.lowercased()) { return "TODAY()" }
        if let plain = DesignDataType.numeric(words) { return plain }
        return "\"\(words)\""
    }

    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let found = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<found.numberOfRanges).map { found.range(at: $0).location == NSNotFound ? "" : ns.substring(with: found.range(at: $0)) }
    }

    /// The date inside DAYS(...) wants quotes when it is a variable or a typed date.
    private static func dateOperand(_ raw: String) -> String {
        let value = operand(raw)
        if value == "TODAY()" || value.hasPrefix("\"") { return value }
        return "\"\(value)\""
    }

    /// Returns a formula token for a sentence that is only a formula, or nil when it does not look like one.
    static func recognise(_ spoken: String) -> String? {
        var t = spoken.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .,!?"))
        let stripped = t.replacingOccurrences(of: "^(?:please\\s+)?(?:the\\s+)?(?:formula|function)\\s+", with: "", options: .regularExpression)
        let explicit = stripped != t
        t = stripped
        guard !t.isEmpty else { return nil }

        // Days to go, days since, days between.
        if let m = match("^(?:days?\\s+(?:to go\\s+)?(?:to|until|till|left\\s+(?:to|for|until)|before|for)|countdown\\s+(?:to|for|of)|how many days\\s+(?:to|until|till))\\s+(.+)$", t) {
            return "{=DAYS(\(dateOperand(m[1])), TODAY())}"
        }
        if let m = match("^days?\\s+(?:since|from|after)\\s+(.+)$", t) { return "{=DAYS(TODAY(), \(dateOperand(m[1])))}" }
        if let m = match("^days?\\s+between\\s+(.+?)\\s+and\\s+(.+)$", t) { return "{=DAYS(\(dateOperand(m[2])), \(dateOperand(m[1])))}" }

        // Today plus or minus some days.
        if let m = match("^(?:today|date|today's date|todays date|current date)\\s+(plus|minus|\\+|-)\\s+(\\d+)(?:\\s+days?)?$", t) {
            return "{=Date\(m[1] == "minus" || m[1] == "-" ? "-" : "+")\(m[2])}"
        }
        if let m = match("^(\\d+)\\s+days?\\s+(?:from now|from today|later|after today)$", t) { return "{=Date+\(m[1])}" }
        if let m = match("^(\\d+)\\s+days?\\s+(?:ago|before today)$", t) { return "{=Date-\(m[1])}" }

        // Sums and the like: "price times quantity", "price plus tax".
        let operators: [(String, String)] = [(" multiplied by ", "*"), (" times ", "*"), (" into ", "*"), (" divided by ", "/"), (" over ", "/"), (" plus ", "+"), (" minus ", "-"), (" x ", "*")]
        for (word, symbol) in operators where t.contains(word) {
            let parts = t.components(separatedBy: word)
            guard parts.count == 2 else { continue }
            let left = operand(parts[0]), right = operand(parts[1])
            if left.hasPrefix("\"") || right.hasPrefix("\"") { continue }
            if left == "TODAY()" || right == "TODAY()" { continue }
            return "{=\(left)\(symbol)\(right)}"
        }

        // A function name first: "sum of price and tax", "round price", "upper name".
        let ordered = WishFunctionCatalog.all.sorted { $0.name.count > $1.name.count }
        for info in ordered {
            let name = info.name.lowercased()
            let spoken = name.replacingOccurrences(of: "_", with: " ")
            guard t == spoken || t.hasPrefix(spoken + " ") else { continue }
            var rest = String(t.dropFirst(spoken.count)).trimmingCharacters(in: .whitespaces)
            rest = rest.replacingOccurrences(of: "^(?:of|for|on|from|the)\\s+", with: "", options: .regularExpression)
            if rest.isEmpty { if explicit { return "{=\(info.name)()}" } else { continue } }
            let args = rest.replacingOccurrences(of: " and ", with: ",").split(separator: ",").map { operand(String($0)) }
            if !explicit && !args.contains(where: { !$0.hasPrefix("\"") }) { continue }
            return "{=\(info.name)(\(args.joined(separator: ", ")))}"
        }
        return nil
    }

    /// A spoken formula after words like "use the formula": always gives some token.
    static func token(_ spoken: String) -> String {
        if let found = recognise(spoken) { return found }
        let lower = spoken.lowercased().trimmingCharacters(in: .whitespaces)
        switch lower {
        case "date", "today", "todays date", "today's date", "current date": return "{=TODAY()}"
        case "time", "current time": return "{=time}"
        case "now", "date and time": return "{=now}"
        case "month": return "{=month}"
        case "year": return "{=year}"
        case "day": return "{=day}"
        case "weekday", "day of week": return "{=weekday}"
        default: return "{=\(spoken.uppercased().replacingOccurrences(of: " ", with: ""))()}"
        }
    }
}
