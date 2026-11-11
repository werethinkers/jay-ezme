// WishStudio formula engine.
//
// Global functions for WishStudio cards: "=Date" is today, "=Date+1" is tomorrow, "=Time+1" is one hour
// from now, "=Month+1" is next month, plus a large set of Google Sheets style functions
// (TEXT, IF, SUM, ROUND, LEFT, SPLIT, EDATE ...). Foundation only, so it can be tested on its own.
import Foundation

// MARK: - Values

/// What a date-like value is anchored to. "+1" moves it by one of that unit.
enum WishUnit {
    case date      // days
    case time      // hours
    case now       // days, shown with the time
    case month     // months
    case year      // years
    case day       // days, shown as a day number
    case weekday   // days, shown as a weekday name
}

enum WishValue {
    case number(Double)
    case text(String)
    case bool(Bool)
    case moment(Date, WishUnit)
    case list([WishValue])
    case error(String)

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

struct WishContext {
    /// Information field values by lowercased key, so "=name" or "=FIELD("name")" works.
    var variables: [String: String] = [:]
    /// Global custom functions by lowercased name. The value is the expression (with or without "=").
    var functions: [String: String] = [:]
    var locale: Locale = Locale(identifier: "en_US")
    var now: Date = Date()

    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale
        cal.timeZone = TimeZone.current
        return cal
    }

    func format(_ date: Date, _ unit: WishUnit) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone.current
        switch unit {
        case .date: formatter.dateFormat = "d MMMM yyyy"
        case .time: formatter.dateFormat = "h:mm a"
        case .now: formatter.dateFormat = "d MMM yyyy, h:mm a"
        case .month: formatter.dateFormat = "MMMM"
        case .year: formatter.dateFormat = "yyyy"
        case .day: formatter.dateFormat = "d"
        case .weekday: formatter.dateFormat = "EEEE"
        }
        return formatter.string(from: date)
    }
}

extension WishValue {
    func display(_ context: WishContext) -> String {
        switch self {
        case .number(let value): return WishFormula.formatNumber(value)
        case .text(let text): return text
        case .bool(let flag): return flag ? "TRUE" : "FALSE"
        case .moment(let date, let unit): return context.format(date, unit)
        case .list(let items): return items.map { $0.display(context) }.joined(separator: ", ")
        case .error(let code): return code
        }
    }
}

// MARK: - Lexer

enum WishToken: Equatable {
    case number(Double)
    case string(String)
    case ident(String)
    case op(String)
    case lparen
    case rparen
    case comma
}

enum WishLexer {
    private static func isDigit(_ c: Character) -> Bool {
        return c.isASCII && c.isNumber
    }

    static func tokenize(_ source: String) -> [WishToken]? {
        let chars = Array(source)
        var tokens: [WishToken] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }

            let startsDot = c == "." && i + 1 < chars.count && isDigit(chars[i + 1])
            if isDigit(c) || startsDot {
                var j = i
                var seenDot = false
                while j < chars.count {
                    if isDigit(chars[j]) {
                        j += 1
                    } else if chars[j] == "." && !seenDot {
                        seenDot = true
                        j += 1
                    } else {
                        break
                    }
                }
                guard let value = Double(String(chars[i..<j])) else { return nil }
                tokens.append(.number(value))
                i = j
                continue
            }

            if c == "\"" || c == "\u{201C}" || c == "\u{201D}" {
                var j = i + 1
                var text = ""
                var closed = false
                while j < chars.count {
                    let d = chars[j]
                    if d == "\"" || d == "\u{201C}" || d == "\u{201D}" {
                        if d == "\"" && j + 1 < chars.count && chars[j + 1] == "\"" {
                            text.append("\"")
                            j += 2
                            continue
                        }
                        closed = true
                        j += 1
                        break
                    }
                    text.append(d)
                    j += 1
                }
                guard closed else { return nil }
                tokens.append(.string(text))
                i = j
                continue
            }

            if c.isLetter || c == "_" {
                var j = i
                while j < chars.count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_") { j += 1 }
                tokens.append(.ident(String(chars[i..<j])))
                i = j
                continue
            }

            if i + 1 < chars.count {
                let pair = String(chars[i...i + 1])
                if pair == "<=" || pair == ">=" || pair == "<>" {
                    tokens.append(.op(pair))
                    i += 2
                    continue
                }
                if pair == "!=" {
                    tokens.append(.op("<>"))
                    i += 2
                    continue
                }
            }

            switch c {
            case "+", "-", "*", "/", "^", "&", "=", "<", ">", "%":
                tokens.append(.op(String(c)))
            case "\u{00D7}":
                tokens.append(.op("*"))
            case "\u{00F7}":
                tokens.append(.op("/"))
            case "(":
                tokens.append(.lparen)
            case ")":
                tokens.append(.rparen)
            case ",", ";":
                tokens.append(.comma)
            default:
                return nil
            }
            i += 1
        }
        return tokens
    }
}

// MARK: - Parser

indirect enum WishNode {
    case number(Double)
    case string(String)
    case variable(String)
    case call(String, [WishNode])
    case unary(String, WishNode)
    case binary(String, WishNode, WishNode)
    case percent(WishNode)
}

struct WishParser {
    let tokens: [WishToken]
    var pos = 0

    init(tokens: [WishToken]) {
        self.tokens = tokens
    }

    private var peek: WishToken? {
        return pos < tokens.count ? tokens[pos] : nil
    }

    mutating func parse() -> WishNode? {
        guard let node = comparison() else { return nil }
        guard pos == tokens.count else { return nil }
        return node
    }

    private mutating func comparison() -> WishNode? {
        guard var left = concat() else { return nil }
        while case .op(let symbol)? = peek, ["=", "<>", "<", ">", "<=", ">="].contains(symbol) {
            pos += 1
            guard let right = concat() else { return nil }
            left = .binary(symbol, left, right)
        }
        return left
    }

    private mutating func concat() -> WishNode? {
        guard var left = additive() else { return nil }
        while case .op("&")? = peek {
            pos += 1
            guard let right = additive() else { return nil }
            left = .binary("&", left, right)
        }
        return left
    }

    private mutating func additive() -> WishNode? {
        guard var left = term() else { return nil }
        while case .op(let symbol)? = peek, symbol == "+" || symbol == "-" {
            pos += 1
            guard let right = term() else { return nil }
            left = .binary(symbol, left, right)
        }
        return left
    }

    private mutating func term() -> WishNode? {
        guard var left = unary() else { return nil }
        while case .op(let symbol)? = peek, symbol == "*" || symbol == "/" {
            pos += 1
            guard let right = unary() else { return nil }
            left = .binary(symbol, left, right)
        }
        return left
    }

    private mutating func unary() -> WishNode? {
        if case .op(let symbol)? = peek, symbol == "-" || symbol == "+" {
            pos += 1
            guard let inner = unary() else { return nil }
            return .unary(symbol, inner)
        }
        return power()
    }

    private mutating func power() -> WishNode? {
        guard let base = postfix() else { return nil }
        if case .op("^")? = peek {
            pos += 1
            guard let exponent = unary() else { return nil }
            return .binary("^", base, exponent)
        }
        return base
    }

    private mutating func postfix() -> WishNode? {
        guard var node = primary() else { return nil }
        while case .op("%")? = peek {
            pos += 1
            node = .percent(node)
        }
        return node
    }

    private mutating func primary() -> WishNode? {
        guard let token = peek else { return nil }
        switch token {
        case .number(let value):
            pos += 1
            return .number(value)
        case .string(let text):
            pos += 1
            return .string(text)
        case .lparen:
            pos += 1
            guard let inner = comparison() else { return nil }
            guard peek == WishToken.rparen else { return nil }
            pos += 1
            return inner
        case .ident(let name):
            pos += 1
            if peek == WishToken.lparen {
                pos += 1
                var args: [WishNode] = []
                if peek == WishToken.rparen {
                    pos += 1
                    return .call(name, args)
                }
                while true {
                    guard let arg = comparison() else { return nil }
                    args.append(arg)
                    if peek == WishToken.comma {
                        pos += 1
                        continue
                    }
                    if peek == WishToken.rparen {
                        pos += 1
                        break
                    }
                    return nil
                }
                return .call(name, args)
            }
            return .variable(name)
        default:
            return nil
        }
    }
}

// MARK: - Public entry points

enum WishFormula {
    /// Evaluates "=Date+1" style text. A leading "=" is optional.
    static func evaluate(_ source: String, context: WishContext) -> WishValue {
        return WishEvaluator(context: context).run(source)
    }

    static func isFormula(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("=") && trimmed.count > 1
    }

    /// Text shown on a card. A value that starts with "=" is calculated; "{=Date+1}" inside other text is
    /// calculated in place. A formula with a typing mistake is left as typed.
    static func render(_ text: String, context: WishContext) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFormula(trimmed) {
            let value = evaluate(trimmed, context: context)
            if case .error(let code) = value, code == "#ERROR!" { return text }
            return value.display(context)
        }
        guard text.contains("{="), let regex = try? NSRegularExpression(pattern: "\\{=([^}]*)\\}") else { return text }
        let ns = text as NSString
        var result = text
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let expression = ns.substring(with: match.range(at: 1))
            let value = evaluate(expression, context: context)
            if case .error(let code) = value, code == "#ERROR!" { continue }
            result = (result as NSString).replacingCharacters(in: match.range, with: value.display(context))
        }
        return result
    }

    static func formatNumber(_ value: Double) -> String {
        if value.isNaN || value.isInfinite { return "#NUM!" }
        if value == value.rounded() && abs(value) < 1e15 { return String(Int64(value)) }
        return String(format: "%.10g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formats = ["yyyy-MM-dd", "dd/MM/yyyy", "d/M/yyyy", "dd-MM-yyyy", "d-M-yyyy", "yyyy/MM/dd", "d MMM yyyy", "d MMMM yyyy", "MMM d, yyyy", "MMMM d, yyyy", "yyyy-MM-dd HH:mm", "d MMM", "d MMMM"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                if format == "d MMM" || format == "d MMMM" {
                    var cal = Calendar(identifier: .gregorian)
                    cal.timeZone = TimeZone.current
                    var parts = cal.dateComponents([.month, .day], from: date)
                    parts.year = cal.component(.year, from: Date())
                    return cal.date(from: parts)
                }
                return date
            }
        }
        return nil
    }

    /// Google Sheets date format ("dd mmm yyyy", "h:mm AM/PM") to a DateFormatter pattern.
    static func dateFormatPattern(_ sheet: String) -> String {
        let lower = sheet.lowercased()
        let twelveHour = lower.contains("am/pm") || lower.contains("a/p")
        let chars = Array(sheet)
        var out = ""
        var i = 0
        var afterHour = false
        while i < chars.count {
            let c = chars[i]
            let rest = String(chars[i...]).lowercased()
            if rest.hasPrefix("am/pm") {
                out += "a"
                i += 5
                continue
            }
            if c.isASCII && c.isLetter {
                let lc = String(c).lowercased()
                var j = i
                while j < chars.count && String(chars[j]).lowercased() == lc { j += 1 }
                let count = j - i
                switch lc {
                case "y":
                    out += count <= 2 ? "yy" : "yyyy"
                    afterHour = false
                case "d":
                    if count == 1 { out += "d" } else if count == 2 { out += "dd" } else if count == 3 { out += "EEE" } else { out += "EEEE" }
                    afterHour = false
                case "h":
                    if twelveHour { out += count == 1 ? "h" : "hh" } else { out += count == 1 ? "H" : "HH" }
                    afterHour = true
                case "s":
                    out += count == 1 ? "s" : "ss"
                case "m":
                    var k = j
                    while k < chars.count && chars[k] == ":" { k += 1 }
                    let beforeSeconds = k < chars.count && String(chars[k]).lowercased() == "s"
                    if afterHour || beforeSeconds {
                        out += count == 1 ? "m" : "mm"
                        afterHour = false
                    } else {
                        if count == 1 { out += "M" } else if count == 2 { out += "MM" } else if count == 3 { out += "MMM" } else { out += "MMMM" }
                    }
                default:
                    out += "'" + String(chars[i..<j]) + "'"
                }
                i = j
                continue
            }
            if c.isLetter {
                out += "'" + String(c) + "'"
            } else if c == "'" {
                out += "''"
            } else {
                out += String(c)
            }
            i += 1
        }
        return out
    }

    /// Google Sheets number format ("#,##0.00", "0%", "₹#,##0") for TEXT().
    static func formatNumber(_ value: Double, pattern: String) -> String {
        var number = value
        var percent = false
        if pattern.contains("%") {
            number *= 100
            percent = true
        }
        let chars = Array(pattern)
        let patternChars = Set("#0,.")
        var firstIndex: Int? = nil
        var lastIndex: Int? = nil
        for (index, ch) in chars.enumerated() where patternChars.contains(ch) {
            if firstIndex == nil { firstIndex = index }
            lastIndex = index
        }
        guard let first = firstIndex, let last = lastIndex else { return formatNumber(value) }
        let prefix = String(chars[0..<first]).replacingOccurrences(of: "\"", with: "")
        var core = String(chars[first...last])
        var suffix = String(chars[(last + 1)...]).replacingOccurrences(of: "\"", with: "")
        if percent { suffix = suffix.replacingOccurrences(of: "%", with: "") + "%" }
        let grouping = core.contains(",")
        core = core.replacingOccurrences(of: ",", with: "")
        var minimum = 0
        var maximum = 0
        if let dot = core.firstIndex(of: ".") {
            let fraction = core[core.index(after: dot)...]
            minimum = fraction.filter { $0 == "0" }.count
            maximum = fraction.count
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        formatter.minimumFractionDigits = minimum
        formatter.maximumFractionDigits = maximum
        let body = formatter.string(from: NSNumber(value: number)) ?? formatNumber(number)
        return prefix + body + suffix
    }

    /// 1234567 -> "12,34,567" (Indian grouping).
    static func indianGrouping(_ value: Double) -> String {
        let negative = value < 0
        let hasFraction = abs(value - value.rounded()) > 0.004
        let raw = String(format: hasFraction ? "%.2f" : "%.0f", locale: Locale(identifier: "en_US_POSIX"), abs(value))
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        let digits = Array(String(parts[0]))
        var grouped = ""
        if digits.count > 3 {
            let tail = String(digits[(digits.count - 3)...])
            var head = Array(digits[0..<(digits.count - 3)])
            var chunks: [String] = []
            while head.count > 2 {
                chunks.insert(String(head[(head.count - 2)...]), at: 0)
                head.removeLast(2)
            }
            if !head.isEmpty { chunks.insert(String(head), at: 0) }
            grouped = chunks.joined(separator: ",") + "," + tail
        } else {
            grouped = String(digits)
        }
        if parts.count > 1 { grouped += "." + parts[1] }
        return (negative ? "-" : "") + grouped
    }

    static func ordinal(_ n: Int) -> String {
        let tens = n % 100
        if tens >= 11 && tens <= 13 { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    static func roman(_ value: Int) -> String? {
        guard value > 0 && value < 4000 else { return nil }
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var remaining = value
        var out = ""
        for (amount, symbol) in table {
            while remaining >= amount {
                out += symbol
                remaining -= amount
            }
        }
        return out
    }
}

// MARK: - Evaluator

struct WishEvaluator {
    let context: WishContext
    var depth = 0

    /// 30 Dec 1899, the day Google Sheets counts from.
    static let epoch = Date(timeIntervalSince1970: -2209161600)

    func run(_ source: String) -> WishValue {
        var text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("=") { text.removeFirst() }
        guard let tokens = WishLexer.tokenize(text) else { return .error("#ERROR!") }
        var parser = WishParser(tokens: tokens)
        guard let node = parser.parse() else { return .error("#ERROR!") }
        return evaluate(node)
    }

    func evaluate(_ node: WishNode) -> WishValue {
        switch node {
        case .number(let value):
            return .number(value)
        case .string(let text):
            return .text(text)
        case .variable(let name):
            return variable(name)
        case .unary(let symbol, let inner):
            let value = evaluate(inner)
            if value.isError { return value }
            if case .moment = value { return value }
            guard let n = number(value) else { return .error("#VALUE!") }
            return .number(symbol == "-" ? -n : n)
        case .percent(let inner):
            let value = evaluate(inner)
            if value.isError { return value }
            guard let n = number(value) else { return .error("#VALUE!") }
            return .number(n / 100)
        case .binary(let symbol, let left, let right):
            return binary(symbol, evaluate(left), evaluate(right))
        case .call(let name, let args):
            return call(name.uppercased(), args)
        }
    }

    // MARK: Names

    private func variable(_ raw: String) -> WishValue {
        let key = raw.lowercased()
        let now = context.now
        let cal = context.calendar
        switch key {
        case "date", "today": return .moment(now, .date)
        case "time": return .moment(now, .time)
        case "now": return .moment(now, .now)
        case "month": return .moment(now, .month)
        case "year": return .moment(now, .year)
        case "day": return .moment(now, .day)
        case "weekday": return .moment(now, .weekday)
        case "hour": return .number(Double(cal.component(.hour, from: now)))
        case "minute": return .number(Double(cal.component(.minute, from: now)))
        case "second": return .number(Double(cal.component(.second, from: now)))
        case "week": return .number(Double(cal.component(.weekOfYear, from: now)))
        case "pi": return .number(Double.pi)
        case "true": return .bool(true)
        case "false": return .bool(false)
        default: break
        }
        if let text = context.variables[key] { return coerce(text) }
        if let body = context.functions[key] {
            guard depth < 12 else { return .error("#REF!") }
            let inner = WishEvaluator(context: context, depth: depth + 1)
            return inner.run(body)
        }
        return .error("#NAME?")
    }

    /// A field value that looks like a number behaves as one; everything else stays text.
    private func coerce(_ text: String) -> WishValue {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.count > 1 && trimmed.hasPrefix("0") && !trimmed.contains(".") { return .text(text) }
        if let value = Double(trimmed.replacingOccurrences(of: ",", with: "")), !trimmed.isEmpty { return .number(value) }
        return .text(text)
    }

    // MARK: Conversions

    private func serial(_ date: Date) -> Double {
        return date.timeIntervalSince(WishEvaluator.epoch) / 86400
    }

    private func fromSerial(_ value: Double) -> Date {
        return WishEvaluator.epoch.addingTimeInterval(value * 86400)
    }

    private func number(_ value: WishValue) -> Double? {
        switch value {
        case .number(let n): return n
        case .bool(let flag): return flag ? 1 : 0
        case .moment(let date, _): return serial(date)
        case .list(let items): return items.first.flatMap { number($0) }
        case .error: return nil
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return 0 }
            if trimmed.hasSuffix("%"), let p = Double(trimmed.dropLast()) { return p / 100 }
            return Double(trimmed.replacingOccurrences(of: ",", with: ""))
        }
    }

    /// For aggregates: numbers in lists count, blank and text cells are skipped.
    private func numericOnly(_ value: WishValue) -> Double? {
        switch value {
        case .number(let n): return n
        case .moment(let date, _): return serial(date)
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return nil }
            return Double(trimmed.replacingOccurrences(of: ",", with: ""))
        default: return nil
        }
    }

    private func truthy(_ value: WishValue) -> Bool {
        switch value {
        case .bool(let flag): return flag
        case .number(let n): return n != 0
        case .text(let text): return text.lowercased() == "true"
        default: return false
        }
    }

    private func flatten(_ values: [WishValue]) -> [WishValue] {
        var out: [WishValue] = []
        for value in values {
            if case .list(let items) = value {
                out.append(contentsOf: flatten(items))
            } else {
                out.append(value)
            }
        }
        return out
    }

    private func dateValue(_ value: WishValue?) -> Date? {
        guard let value = value else { return nil }
        switch value {
        case .moment(let date, _): return date
        case .number(let n): return fromSerial(n)
        case .text(let text): return WishFormula.parseDate(text)
        default: return nil
        }
    }

    // MARK: Operators

    private func shift(_ date: Date, _ unit: WishUnit, _ amount: Double) -> Date {
        let cal = context.calendar
        let whole = amount == amount.rounded()
        switch unit {
        case .date, .now, .day, .weekday:
            if whole { return cal.date(byAdding: .day, value: Int(amount), to: date) ?? date }
            return date.addingTimeInterval(amount * 86400)
        case .time:
            return date.addingTimeInterval(amount * 3600)
        case .month:
            return cal.date(byAdding: .month, value: Int(amount.rounded(.towardZero)), to: date) ?? date
        case .year:
            return cal.date(byAdding: .year, value: Int(amount.rounded(.towardZero)), to: date) ?? date
        }
    }

    private func isMoment(_ value: WishValue) -> Bool {
        if case .moment = value { return true }
        return false
    }

    private func binary(_ symbol: String, _ left: WishValue, _ right: WishValue) -> WishValue {
        if left.isError { return left }
        if right.isError { return right }

        if symbol == "&" {
            return .text(left.display(context) + right.display(context))
        }
        if ["=", "<>", "<", ">", "<=", ">="].contains(symbol) {
            return compare(symbol, left, right)
        }

        if case .moment(let date, let unit) = left {
            if symbol == "+" || symbol == "-" {
                if !isMoment(right), let amount = number(right) {
                    return .moment(shift(date, unit, symbol == "+" ? amount : -amount), unit)
                }
                if symbol == "-", case .moment(let other, _) = right {
                    let cal = context.calendar
                    let days = cal.dateComponents([.day], from: cal.startOfDay(for: other), to: cal.startOfDay(for: date)).day ?? 0
                    return .number(Double(days))
                }
            }
        }
        if case .moment(let date, let unit) = right, symbol == "+", !isMoment(left), let amount = number(left) {
            return .moment(shift(date, unit, amount), unit)
        }

        guard let a = number(left), let b = number(right) else { return .error("#VALUE!") }
        switch symbol {
        case "+": return .number(a + b)
        case "-": return .number(a - b)
        case "*": return .number(a * b)
        case "/": return b == 0 ? .error("#DIV/0!") : .number(a / b)
        case "^":
            let result = pow(a, b)
            return result.isFinite ? .number(result) : .error("#NUM!")
        default: return .error("#ERROR!")
        }
    }

    private func comparable(_ value: WishValue) -> Double? {
        switch value {
        case .number(let n): return n
        case .bool(let flag): return flag ? 1 : 0
        case .moment(let date, _): return serial(date)
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return nil }
            return Double(trimmed.replacingOccurrences(of: ",", with: ""))
        default: return nil
        }
    }

    private func compare(_ symbol: String, _ left: WishValue, _ right: WishValue) -> WishValue {
        var order = 0
        if let a = comparable(left), let b = comparable(right) {
            order = a < b ? -1 : (a > b ? 1 : 0)
        } else {
            let a = left.display(context).lowercased()
            let b = right.display(context).lowercased()
            order = a < b ? -1 : (a > b ? 1 : 0)
        }
        switch symbol {
        case "=": return .bool(order == 0)
        case "<>": return .bool(order != 0)
        case "<": return .bool(order < 0)
        case ">": return .bool(order > 0)
        case "<=": return .bool(order <= 0)
        default: return .bool(order >= 0)
        }
    }

    // MARK: Functions

    private func call(_ name: String, _ args: [WishNode]) -> WishValue {
        switch name {
        case "IF":
            guard args.count >= 2 && args.count <= 3 else { return .error("#N/A") }
            let condition = evaluate(args[0])
            if condition.isError { return condition }
            if truthy(condition) { return evaluate(args[1]) }
            return args.count == 3 ? evaluate(args[2]) : .bool(false)
        case "IFS":
            guard args.count >= 2 && args.count % 2 == 0 else { return .error("#N/A") }
            var index = 0
            while index < args.count {
                let condition = evaluate(args[index])
                if condition.isError { return condition }
                if truthy(condition) { return evaluate(args[index + 1]) }
                index += 2
            }
            return .error("#N/A")
        case "IFERROR":
            guard args.count >= 1 else { return .error("#N/A") }
            let value = evaluate(args[0])
            if value.isError { return args.count > 1 ? evaluate(args[1]) : .text("") }
            return value
        case "IFNA":
            guard args.count >= 2 else { return .error("#N/A") }
            let value = evaluate(args[0])
            if case .error(let code) = value, code == "#N/A" { return evaluate(args[1]) }
            return value
        case "ISERROR", "ISERR":
            guard args.count == 1 else { return .error("#N/A") }
            return .bool(evaluate(args[0]).isError)
        case "ISNA":
            guard args.count == 1 else { return .error("#N/A") }
            if case .error(let code) = evaluate(args[0]), code == "#N/A" { return .bool(true) }
            return .bool(false)
        case "CHOOSE":
            guard args.count >= 2 else { return .error("#N/A") }
            let pick = evaluate(args[0])
            if pick.isError { return pick }
            guard let n = number(pick), Int(n) >= 1, Int(n) < args.count else { return .error("#N/A") }
            return evaluate(args[Int(n)])
        case "SWITCH":
            guard args.count >= 3 else { return .error("#N/A") }
            let subject = evaluate(args[0])
            if subject.isError { return subject }
            var index = 1
            while index + 1 < args.count {
                let candidate = evaluate(args[index])
                if case .bool(true) = compare("=", subject, candidate) { return evaluate(args[index + 1]) }
                index += 2
            }
            if args.count % 2 == 0 { return evaluate(args[args.count - 1]) }
            return .error("#N/A")
        default:
            break
        }

        let values = args.map { evaluate($0) }
        if let failure = values.first(where: { $0.isError }) { return failure }
        return eager(name, values)
    }

    private func eager(_ name: String, _ v: [WishValue]) -> WishValue {
        let cal = context.calendar
        func n(_ i: Int) -> Double? { return i < v.count ? number(v[i]) : nil }
        func s(_ i: Int) -> String { return i < v.count ? v[i].display(context) : "" }
        func d(_ i: Int) -> Date? { return dateValue(i < v.count ? v[i] : nil) }
        func nums() -> [Double] { return flatten(v).compactMap { numericOnly($0) } }
        func need(_ count: Int) -> Bool { return v.count >= count }

        switch name {
        // MARK: Date and time
        case "TODAY":
            return .moment(context.now, .date)
        case "NOW":
            return .moment(context.now, .now)
        case "DATE":
            guard need(3), let y = n(0), let m = n(1), let day = n(2) else { return .error("#VALUE!") }
            var parts = DateComponents()
            parts.year = Int(y)
            parts.month = 1
            parts.day = 1
            guard let base = cal.date(from: parts),
                  let withMonths = cal.date(byAdding: .month, value: Int(m) - 1, to: base),
                  let result = cal.date(byAdding: .day, value: Int(day) - 1, to: withMonths) else { return .error("#NUM!") }
            return .moment(result, .date)
        case "TIME":
            guard need(1), let h = n(0) else { return .error("#VALUE!") }
            let minutes = n(1) ?? 0
            let seconds = n(2) ?? 0
            let start = cal.startOfDay(for: context.now)
            return .moment(start.addingTimeInterval(h * 3600 + minutes * 60 + seconds), .time)
        case "DAY":
            guard let date = d(0) else { return .error("#VALUE!") }
            return .number(Double(cal.component(.day, from: date)))
        case "MONTH":
            guard let date = d(0) else { return .error("#VALUE!") }
            return .number(Double(cal.component(.month, from: date)))
        case "YEAR":
            guard let date = d(0) else { return .error("#VALUE!") }
            return .number(Double(cal.component(.year, from: date)))
        case "HOUR":
            guard let date = d(0) else { return .error("#VALUE!") }
            return .number(Double(cal.component(.hour, from: date)))
        case "MINUTE":
            guard let date = d(0) else { return .error("#VALUE!") }
            return .number(Double(cal.component(.minute, from: date)))
        case "SECOND":
            guard let date = d(0) else { return .error("#VALUE!") }
            return .number(Double(cal.component(.second, from: date)))
        case "WEEKDAY":
            guard let date = d(0) else { return .error("#VALUE!") }
            let sundayBased = cal.component(.weekday, from: date)
            let type = Int(n(1) ?? 1)
            switch type {
            case 2: return .number(Double(sundayBased == 1 ? 7 : sundayBased - 1))
            case 3: return .number(Double(sundayBased == 1 ? 6 : sundayBased - 2))
            default: return .number(Double(sundayBased))
            }
        case "WEEKNUM", "ISOWEEKNUM":
            guard let date = d(0) else { return .error("#VALUE!") }
            var iso = Calendar(identifier: .iso8601)
            iso.timeZone = TimeZone.current
            return .number(Double(iso.component(.weekOfYear, from: date)))
        case "EDATE":
            guard let date = d(0), let months = n(1), let result = cal.date(byAdding: .month, value: Int(months), to: date) else { return .error("#VALUE!") }
            return .moment(result, .date)
        case "EOMONTH":
            guard let date = d(0), let months = n(1), let base = cal.date(byAdding: .month, value: Int(months), to: date),
                  let range = cal.range(of: .day, in: .month, for: base) else { return .error("#VALUE!") }
            var parts = cal.dateComponents([.year, .month], from: base)
            parts.day = range.count
            return .moment(cal.date(from: parts) ?? base, .date)
        case "DAYS":
            guard let end = d(0), let start = d(1) else { return .error("#VALUE!") }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: end)).day ?? 0
            return .number(Double(days))
        case "DATEDIF":
            guard let start = d(0), let end = d(1) else { return .error("#VALUE!") }
            let unit = s(2).uppercased()
            let from = cal.startOfDay(for: start)
            let to = cal.startOfDay(for: end)
            if to < from { return .error("#NUM!") }
            let parts = cal.dateComponents([.year, .month, .day], from: from, to: to)
            switch unit {
            case "D": return .number(Double(cal.dateComponents([.day], from: from, to: to).day ?? 0))
            case "M": return .number(Double((parts.year ?? 0) * 12 + (parts.month ?? 0)))
            case "Y": return .number(Double(parts.year ?? 0))
            case "YM": return .number(Double(parts.month ?? 0))
            case "MD": return .number(Double(parts.day ?? 0))
            default: return .error("#NUM!")
            }
        case "DATEVALUE":
            guard let date = WishFormula.parseDate(s(0)) else { return .error("#VALUE!") }
            return .moment(date, .date)
        case "NETWORKDAYS":
            guard let start = d(0), let end = d(1) else { return .error("#VALUE!") }
            var day = cal.startOfDay(for: min(start, end))
            let last = cal.startOfDay(for: max(start, end))
            var count = 0
            var guardCount = 0
            while day <= last && guardCount < 4000 {
                let weekday = cal.component(.weekday, from: day)
                if weekday != 1 && weekday != 7 { count += 1 }
                day = cal.date(byAdding: .day, value: 1, to: day) ?? last.addingTimeInterval(86400)
                guardCount += 1
            }
            return .number(Double(start <= end ? count : -count))
        case "WORKDAY":
            guard let start = d(0), let days = n(1) else { return .error("#VALUE!") }
            var remaining = Int(days)
            let step = remaining >= 0 ? 1 : -1
            var day = start
            var guardCount = 0
            while remaining != 0 && guardCount < 4000 {
                day = cal.date(byAdding: .day, value: step, to: day) ?? day
                let weekday = cal.component(.weekday, from: day)
                if weekday != 1 && weekday != 7 { remaining -= step }
                guardCount += 1
            }
            return .moment(day, .date)

        // MARK: Text
        case "TEXT":
            guard need(2) else { return .error("#N/A") }
            let pattern = s(1)
            if case .moment(let date, _) = v[0] {
                let formatter = DateFormatter()
                formatter.locale = context.locale
                formatter.timeZone = TimeZone.current
                formatter.dateFormat = WishFormula.dateFormatPattern(pattern)
                return .text(formatter.string(from: date))
            }
            if let value = n(0), !s(0).isEmpty {
                let lower = pattern.lowercased()
                if lower.contains("yy") || lower.contains("dd") || lower.contains("mm") || lower.contains("hh") {
                    let formatter = DateFormatter()
                    formatter.locale = context.locale
                    formatter.timeZone = TimeZone.current
                    formatter.dateFormat = WishFormula.dateFormatPattern(pattern)
                    return .text(formatter.string(from: fromSerial(value)))
                }
                return .text(WishFormula.formatNumber(value, pattern: pattern))
            }
            return .text(s(0))
        case "UPPER": return .text(s(0).uppercased())
        case "LOWER": return .text(s(0).lowercased())
        case "PROPER":
            var out = ""
            var capitalizeNext = true
            for ch in s(0) {
                if ch.isLetter {
                    out += capitalizeNext ? String(ch).uppercased() : String(ch).lowercased()
                    capitalizeNext = false
                } else {
                    out.append(ch)
                    capitalizeNext = !ch.isNumber && ch != "'"
                }
            }
            return .text(out)
        case "LEN": return .number(Double(s(0).count))
        case "LEFT":
            let count = Int(n(1) ?? 1)
            guard count >= 0 else { return .error("#VALUE!") }
            return .text(String(s(0).prefix(count)))
        case "RIGHT":
            let count = Int(n(1) ?? 1)
            guard count >= 0 else { return .error("#VALUE!") }
            return .text(String(s(0).suffix(count)))
        case "MID":
            guard need(3), let start = n(1), let length = n(2), start >= 1, length >= 0 else { return .error("#VALUE!") }
            let chars = Array(s(0))
            let from = Int(start) - 1
            if from >= chars.count { return .text("") }
            let to = min(chars.count, from + Int(length))
            return .text(String(chars[from..<to]))
        case "TRIM":
            return .text(s(0).split(whereSeparator: { $0 == " " }).joined(separator: " "))
        case "CLEAN":
            return .text(String(s(0).unicodeScalars.filter { $0.value >= 32 }.map { Character($0) }))
        case "CONCATENATE", "CONCAT":
            return .text(flatten(v).map { $0.display(context) }.joined())
        case "TEXTJOIN":
            guard need(3) else { return .error("#N/A") }
            let skipEmpty = truthy(v[1])
            var items = flatten(Array(v.dropFirst(2))).map { $0.display(context) }
            if skipEmpty { items = items.filter { !$0.isEmpty } }
            return .text(items.joined(separator: s(0)))
        case "JOIN":
            guard need(2) else { return .error("#N/A") }
            return .text(flatten(Array(v.dropFirst())).map { $0.display(context) }.joined(separator: s(0)))
        case "SUBSTITUTE":
            guard need(3) else { return .error("#N/A") }
            let text = s(0)
            let old = s(1)
            let replacement = s(2)
            if old.isEmpty { return .text(text) }
            if let instance = n(3) {
                var found = 0
                var searchStart = text.startIndex
                while let range = text.range(of: old, range: searchStart..<text.endIndex) {
                    found += 1
                    if found == Int(instance) {
                        return .text(text.replacingCharacters(in: range, with: replacement))
                    }
                    searchStart = range.upperBound
                }
                return .text(text)
            }
            return .text(text.replacingOccurrences(of: old, with: replacement))
        case "REPLACE":
            guard need(4), let position = n(1), let length = n(2), position >= 1, length >= 0 else { return .error("#VALUE!") }
            let chars = Array(s(0))
            let from = min(chars.count, Int(position) - 1)
            let to = min(chars.count, from + Int(length))
            return .text(String(chars[0..<from]) + s(3) + String(chars[to...]))
        case "REPT":
            guard need(2), let times = n(1), times >= 0, times <= 1000 else { return .error("#VALUE!") }
            return .text(String(repeating: s(0), count: Int(times)))
        case "FIND", "SEARCH":
            guard need(2) else { return .error("#N/A") }
            let needle = s(0)
            let hay = s(1)
            let startOffset = max(1, Int(n(2) ?? 1)) - 1
            guard startOffset <= hay.count else { return .error("#VALUE!") }
            let from = hay.index(hay.startIndex, offsetBy: startOffset)
            let options: String.CompareOptions = name == "SEARCH" ? [.caseInsensitive] : []
            if let range = hay.range(of: needle, options: options, range: from..<hay.endIndex) {
                return .number(Double(hay.distance(from: hay.startIndex, to: range.lowerBound) + 1))
            }
            return .error("#VALUE!")
        case "EXACT":
            return .bool(s(0) == s(1))
        case "CHAR", "UNICHAR":
            guard let code = n(0), code >= 1, let scalar = UnicodeScalar(UInt32(code)) else { return .error("#VALUE!") }
            return .text(String(Character(scalar)))
        case "CODE", "UNICODE":
            guard let first = s(0).unicodeScalars.first else { return .error("#VALUE!") }
            return .number(Double(first.value))
        case "VALUE":
            if let value = number(v.first ?? .text("")), !s(0).trimmingCharacters(in: .whitespaces).isEmpty { return .number(value) }
            return .error("#VALUE!")
        case "T":
            if case .text(let text) = v.first ?? .text("") { return .text(text) }
            return .text("")
        case "SPLIT":
            guard need(2) else { return .error("#N/A") }
            let splitEach = v.count > 2 ? truthy(v[2]) : true
            let dropEmpty = v.count > 3 ? truthy(v[3]) : true
            var pieces: [String]
            if splitEach {
                pieces = s(0).components(separatedBy: CharacterSet(charactersIn: s(1)))
            } else {
                pieces = s(0).components(separatedBy: s(1))
            }
            if dropEmpty { pieces = pieces.filter { !$0.isEmpty } }
            return .list(pieces.map { .text($0) })
        case "REGEXMATCH":
            guard need(2), let regex = try? NSRegularExpression(pattern: s(1)) else { return .error("#VALUE!") }
            let text = s(0)
            return .bool(regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil)
        case "REGEXEXTRACT":
            guard need(2), let regex = try? NSRegularExpression(pattern: s(1)) else { return .error("#VALUE!") }
            let text = s(0)
            let ns = text as NSString
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return .error("#N/A") }
            let target = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            return .text(ns.substring(with: target))
        case "REGEXREPLACE":
            guard need(3), let regex = try? NSRegularExpression(pattern: s(1)) else { return .error("#VALUE!") }
            let text = s(0)
            return .text(regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: s(2)))
        case "ROMAN":
            guard let value = n(0), let roman = WishFormula.roman(Int(value)) else { return .error("#VALUE!") }
            return .text(roman)

        // MARK: Logic
        case "AND":
            let items = flatten(v)
            return .bool(!items.isEmpty && items.allSatisfy { truthy($0) })
        case "OR":
            return .bool(flatten(v).contains { truthy($0) })
        case "XOR":
            return .bool(flatten(v).filter { truthy($0) }.count % 2 == 1)
        case "NOT":
            return .bool(!truthy(v.first ?? .bool(false)))
        case "TRUE": return .bool(true)
        case "FALSE": return .bool(false)
        case "ISBLANK":
            if case .text(let text) = v.first ?? .text("") { return .bool(text.isEmpty) }
            return .bool(false)
        case "ISNUMBER":
            if case .number = v.first ?? .text("") { return .bool(true) }
            return .bool(false)
        case "ISTEXT":
            if case .text = v.first ?? .number(0) { return .bool(true) }
            return .bool(false)
        case "ISEVEN":
            guard let value = n(0) else { return .error("#VALUE!") }
            return .bool(Int(value) % 2 == 0)
        case "ISODD":
            guard let value = n(0) else { return .error("#VALUE!") }
            return .bool(abs(Int(value)) % 2 == 1)

        // MARK: Math
        case "SUM": return .number(nums().reduce(0, +))
        case "AVERAGE":
            let items = nums()
            return items.isEmpty ? .error("#DIV/0!") : .number(items.reduce(0, +) / Double(items.count))
        case "MIN": return .number(nums().min() ?? 0)
        case "MAX": return .number(nums().max() ?? 0)
        case "COUNT": return .number(Double(nums().count))
        case "COUNTA":
            return .number(Double(flatten(v).filter { !$0.display(context).isEmpty }.count))
        case "COUNTIF":
            guard need(2) else { return .error("#N/A") }
            return .number(Double(countIf(flatten([v[0]]), s(1))))
        case "PRODUCT":
            let items = nums()
            return .number(items.isEmpty ? 0 : items.reduce(1, *))
        case "MEDIAN":
            let items = nums().sorted()
            guard !items.isEmpty else { return .error("#NUM!") }
            let mid = items.count / 2
            return .number(items.count % 2 == 1 ? items[mid] : (items[mid - 1] + items[mid]) / 2)
        case "MODE":
            let items = nums()
            guard !items.isEmpty else { return .error("#N/A") }
            var counts: [Double: Int] = [:]
            for item in items { counts[item, default: 0] += 1 }
            let best = counts.max { a, b in a.value < b.value || (a.value == b.value && a.key > b.key) }
            return .number(best?.key ?? 0)
        case "LARGE", "SMALL":
            guard need(2), let k = n(1) else { return .error("#N/A") }
            let items = flatten([v[0]]).compactMap { numericOnly($0) }.sorted()
            let index = Int(k) - 1
            guard index >= 0 && index < items.count else { return .error("#NUM!") }
            return .number(name == "LARGE" ? items[items.count - 1 - index] : items[index])
        case "STDEV", "VAR":
            let items = nums()
            guard items.count > 1 else { return .error("#DIV/0!") }
            let mean = items.reduce(0, +) / Double(items.count)
            let variance = items.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(items.count - 1)
            return .number(name == "VAR" ? variance : variance.squareRoot())
        case "ROUND", "ROUNDUP", "ROUNDDOWN":
            guard let value = n(0) else { return .error("#VALUE!") }
            let digits = Int(n(1) ?? 0)
            let factor = pow(10.0, Double(digits))
            let rule: FloatingPointRoundingRule = name == "ROUND" ? .toNearestOrAwayFromZero : (name == "ROUNDUP" ? .awayFromZero : .towardZero)
            return .number((value * factor).rounded(rule) / factor)
        case "CEILING":
            guard let value = n(0) else { return .error("#VALUE!") }
            let significance = n(1) ?? 1
            return significance == 0 ? .number(0) : .number((value / significance).rounded(.up) * significance)
        case "FLOOR":
            guard let value = n(0) else { return .error("#VALUE!") }
            let significance = n(1) ?? 1
            return significance == 0 ? .number(0) : .number((value / significance).rounded(.down) * significance)
        case "INT":
            guard let value = n(0) else { return .error("#VALUE!") }
            return .number(value.rounded(.down))
        case "TRUNC":
            guard let value = n(0) else { return .error("#VALUE!") }
            let factor = pow(10.0, Double(Int(n(1) ?? 0)))
            return .number((value * factor).rounded(.towardZero) / factor)
        case "ABS":
            guard let value = n(0) else { return .error("#VALUE!") }
            return .number(abs(value))
        case "SIGN":
            guard let value = n(0) else { return .error("#VALUE!") }
            return .number(value > 0 ? 1 : (value < 0 ? -1 : 0))
        case "SQRT":
            guard let value = n(0) else { return .error("#VALUE!") }
            return value < 0 ? .error("#NUM!") : .number(value.squareRoot())
        case "POWER":
            guard need(2), let base = n(0), let exponent = n(1) else { return .error("#VALUE!") }
            let result = pow(base, exponent)
            return result.isFinite ? .number(result) : .error("#NUM!")
        case "MOD":
            guard need(2), let a = n(0), let b = n(1) else { return .error("#VALUE!") }
            return b == 0 ? .error("#DIV/0!") : .number(a - b * (a / b).rounded(.down))
        case "QUOTIENT":
            guard need(2), let a = n(0), let b = n(1) else { return .error("#VALUE!") }
            return b == 0 ? .error("#DIV/0!") : .number((a / b).rounded(.towardZero))
        case "EXP":
            guard let value = n(0) else { return .error("#VALUE!") }
            return .number(exp(value))
        case "LN":
            guard let value = n(0), value > 0 else { return .error("#NUM!") }
            return .number(log(value))
        case "LOG":
            guard let value = n(0), value > 0 else { return .error("#NUM!") }
            let base = n(1) ?? 10
            guard base > 0 && base != 1 else { return .error("#NUM!") }
            return .number(log(value) / log(base))
        case "LOG10":
            guard let value = n(0), value > 0 else { return .error("#NUM!") }
            return .number(log10(value))
        case "FACT":
            guard let value = n(0), value >= 0, value <= 170 else { return .error("#NUM!") }
            var result = 1.0
            if Int(value) > 1 { for i in 2...Int(value) { result *= Double(i) } }
            return .number(result)
        case "GCD", "LCM":
            let items = nums().map { Int(abs($0)) }
            guard !items.isEmpty else { return .error("#VALUE!") }
            func gcd(_ a: Int, _ b: Int) -> Int { return b == 0 ? a : gcd(b, a % b) }
            var result = items[0]
            for item in items.dropFirst() {
                if name == "GCD" {
                    result = gcd(result, item)
                } else {
                    let divisor = gcd(result, item)
                    result = divisor == 0 ? 0 : result / divisor * item
                }
            }
            return .number(Double(result))
        case "SIN": return n(0).map { .number(sin($0)) } ?? .error("#VALUE!")
        case "COS": return n(0).map { .number(cos($0)) } ?? .error("#VALUE!")
        case "TAN": return n(0).map { .number(tan($0)) } ?? .error("#VALUE!")
        case "DEGREES": return n(0).map { .number($0 * 180 / Double.pi) } ?? .error("#VALUE!")
        case "RADIANS": return n(0).map { .number($0 * Double.pi / 180) } ?? .error("#VALUE!")
        case "PI": return .number(Double.pi)
        case "RAND": return .number(Double.random(in: 0..<1))
        case "RANDBETWEEN":
            guard need(2), let low = n(0), let high = n(1), Int(low) <= Int(high) else { return .error("#NUM!") }
            return .number(Double(Int.random(in: Int(low)...Int(high))))

        // MARK: Lists
        case "INDEX":
            guard need(2), let position = n(1) else { return .error("#N/A") }
            let items = flatten([v[0]])
            let index = Int(position) - 1
            guard index >= 0 && index < items.count else { return .error("#REF!") }
            return items[index]
        case "SEQUENCE":
            guard let count = n(0), count >= 1, count <= 1000 else { return .error("#VALUE!") }
            let start = n(1) ?? 1
            let step = n(2) ?? 1
            return .list((0..<Int(count)).map { .number(start + Double($0) * step) })
        case "SORT":
            let ascending = v.count > 1 ? truthy(v[1]) : true
            let items = flatten([v.first ?? .list([])])
            let sorted = items.sorted { left, right in
                if let a = numericOnly(left), let b = numericOnly(right) { return ascending ? a < b : a > b }
                let a = left.display(context).lowercased()
                let b = right.display(context).lowercased()
                return ascending ? a < b : a > b
            }
            return .list(sorted)
        case "UNIQUE":
            var seen = Set<String>()
            var out: [WishValue] = []
            for item in flatten([v.first ?? .list([])]) {
                let key = item.display(context).lowercased()
                if seen.insert(key).inserted { out.append(item) }
            }
            return .list(out)
        case "FIELD":
            let key = s(0).lowercased()
            if let text = context.variables[key] { return .text(text) }
            return .error("#NAME?")

        // MARK: EzMe extras
        case "INR":
            guard let value = n(0) else { return .error("#VALUE!") }
            return .text("\u{20B9}" + WishFormula.indianGrouping(value))
        case "ORDINAL":
            guard let value = n(0) else { return .error("#VALUE!") }
            return .text(WishFormula.ordinal(Int(value)))
        case "AGE":
            guard let born = d(0) else { return .error("#VALUE!") }
            return .number(Double(cal.dateComponents([.year], from: born, to: context.now).year ?? 0))
        case "COUNTDOWN":
            guard let target = d(0) else { return .error("#VALUE!") }
            let today = cal.startOfDay(for: context.now)
            var parts = cal.dateComponents([.month, .day], from: target)
            parts.year = cal.component(.year, from: today)
            guard var next = cal.date(from: parts) else { return .error("#VALUE!") }
            if next < today {
                parts.year = (parts.year ?? 0) + 1
                next = cal.date(from: parts) ?? next
            }
            return .number(Double(cal.dateComponents([.day], from: today, to: next).day ?? 0))
        case "GREETING":
            let hour = cal.component(.hour, from: context.now)
            let hindi = context.locale.identifier.hasPrefix("hi")
            if hour < 12 { return .text(hindi ? "\u{0938}\u{0941}\u{092A}\u{094D}\u{0930}\u{092D}\u{093E}\u{0924}" : "Good morning") }
            if hour < 17 { return .text(hindi ? "\u{0936}\u{0941}\u{092D} \u{0926}\u{094B}\u{092A}\u{0939}\u{0930}" : "Good afternoon") }
            return .text(hindi ? "\u{0936}\u{0941}\u{092D} \u{0938}\u{0902}\u{0927}\u{094D}\u{092F}\u{093E}" : "Good evening")
        default:
            return .error("#NAME?")
        }
    }

    private func countIf(_ items: [WishValue], _ criterion: String) -> Int {
        var symbol = "="
        var operand = criterion
        for candidate in ["<=", ">=", "<>", "<", ">", "="] where criterion.hasPrefix(candidate) {
            symbol = candidate
            operand = String(criterion.dropFirst(candidate.count))
            break
        }
        let target: WishValue = Double(operand).map { WishValue.number($0) } ?? WishValue.text(operand)
        return items.filter { item in
            if case .bool(true) = compare(symbol, item, target) { return true }
            return false
        }.count
    }
}

// MARK: - Catalogue shown in the Function step

struct WishFunctionInfo: Identifiable, Hashable {
    let name: String
    let syntax: String
    let summary: String
    let category: String
    var id: String { return name }

    init(_ name: String, _ syntax: String, _ summary: String, _ category: String) {
        self.name = name
        self.syntax = syntax
        self.summary = summary
        self.category = category
    }
}

enum WishFunctionCatalog {
    static let categories = ["Date & time", "Text", "Logic", "Math", "Lists", "KeyDo extras"]

    /// Words that work on their own, without brackets.
    static let words: [WishFunctionInfo] = [
        WishFunctionInfo("Date", "=Date", "Today's date. =Date+1 is tomorrow, =Date-7 is a week ago.", "Date & time"),
        WishFunctionInfo("Time", "=Time", "The time now. =Time+1 is one hour later, =Time+0.5 is half an hour later.", "Date & time"),
        WishFunctionInfo("Now", "=Now", "Date and time now. =Now+1 is the same time tomorrow.", "Date & time"),
        WishFunctionInfo("Day", "=Day", "Today's day of the month. =Day+1 is tomorrow's number.", "Date & time"),
        WishFunctionInfo("Weekday", "=Weekday", "Today's weekday name. =Weekday+1 is tomorrow's.", "Date & time"),
        WishFunctionInfo("Month", "=Month", "This month's name. =Month+1 is next month.", "Date & time"),
        WishFunctionInfo("Year", "=Year", "This year. =Year+1 is next year.", "Date & time"),
        WishFunctionInfo("Hour", "=Hour", "The hour now, 0 to 23.", "Date & time"),
        WishFunctionInfo("Minute", "=Minute", "The minute now.", "Date & time"),
        WishFunctionInfo("Week", "=Week", "The week number of the year.", "Date & time"),
    ]

    static let all: [WishFunctionInfo] = [
        // Date & time
        WishFunctionInfo("TODAY", "TODAY()", "Today's date.", "Date & time"),
        WishFunctionInfo("NOW", "NOW()", "Date and time now.", "Date & time"),
        WishFunctionInfo("DATE", "DATE(year, month, day)", "Builds a date.", "Date & time"),
        WishFunctionInfo("TIME", "TIME(hour, minute, second)", "Builds a time of day.", "Date & time"),
        WishFunctionInfo("DAY", "DAY(date)", "Day of the month.", "Date & time"),
        WishFunctionInfo("MONTH", "MONTH(date)", "Month number.", "Date & time"),
        WishFunctionInfo("YEAR", "YEAR(date)", "Year.", "Date & time"),
        WishFunctionInfo("HOUR", "HOUR(time)", "Hour of a time.", "Date & time"),
        WishFunctionInfo("MINUTE", "MINUTE(time)", "Minute of a time.", "Date & time"),
        WishFunctionInfo("SECOND", "SECOND(time)", "Second of a time.", "Date & time"),
        WishFunctionInfo("WEEKDAY", "WEEKDAY(date, [type])", "Day of the week as a number.", "Date & time"),
        WishFunctionInfo("WEEKNUM", "WEEKNUM(date)", "Week number of the year.", "Date & time"),
        WishFunctionInfo("ISOWEEKNUM", "ISOWEEKNUM(date)", "ISO week number.", "Date & time"),
        WishFunctionInfo("EDATE", "EDATE(date, months)", "A date some months away.", "Date & time"),
        WishFunctionInfo("EOMONTH", "EOMONTH(date, months)", "Last day of a month.", "Date & time"),
        WishFunctionInfo("DATEDIF", "DATEDIF(start, end, \"Y\"|\"M\"|\"D\"|\"YM\"|\"MD\")", "Years, months or days between two dates.", "Date & time"),
        WishFunctionInfo("DAYS", "DAYS(end, start)", "Days between two dates.", "Date & time"),
        WishFunctionInfo("DATEVALUE", "DATEVALUE(text)", "Turns text like 2026-11-08 into a date.", "Date & time"),
        WishFunctionInfo("NETWORKDAYS", "NETWORKDAYS(start, end)", "Working days between two dates.", "Date & time"),
        WishFunctionInfo("WORKDAY", "WORKDAY(start, days)", "The date some working days away.", "Date & time"),
        // Text
        WishFunctionInfo("TEXT", "TEXT(value, \"dd mmm yyyy\")", "Formats a date or number, like =TEXT(Date,\"dddd\").", "Text"),
        WishFunctionInfo("UPPER", "UPPER(text)", "CAPITAL LETTERS.", "Text"),
        WishFunctionInfo("LOWER", "LOWER(text)", "small letters.", "Text"),
        WishFunctionInfo("PROPER", "PROPER(text)", "Capital First Letters.", "Text"),
        WishFunctionInfo("LEN", "LEN(text)", "Number of characters.", "Text"),
        WishFunctionInfo("LEFT", "LEFT(text, [count])", "First characters.", "Text"),
        WishFunctionInfo("RIGHT", "RIGHT(text, [count])", "Last characters.", "Text"),
        WishFunctionInfo("MID", "MID(text, start, count)", "Characters from the middle.", "Text"),
        WishFunctionInfo("TRIM", "TRIM(text)", "Removes extra spaces.", "Text"),
        WishFunctionInfo("CLEAN", "CLEAN(text)", "Removes hidden characters.", "Text"),
        WishFunctionInfo("CONCATENATE", "CONCATENATE(a, b, ...)", "Joins text.", "Text"),
        WishFunctionInfo("CONCAT", "CONCAT(a, b)", "Joins text.", "Text"),
        WishFunctionInfo("TEXTJOIN", "TEXTJOIN(delimiter, skipEmpty, a, b, ...)", "Joins text with a separator.", "Text"),
        WishFunctionInfo("JOIN", "JOIN(delimiter, list)", "Joins a list with a separator.", "Text"),
        WishFunctionInfo("SUBSTITUTE", "SUBSTITUTE(text, old, new, [which])", "Swaps text for other text.", "Text"),
        WishFunctionInfo("REPLACE", "REPLACE(text, start, count, new)", "Replaces characters by position.", "Text"),
        WishFunctionInfo("REPT", "REPT(text, times)", "Repeats text.", "Text"),
        WishFunctionInfo("FIND", "FIND(search, text, [start])", "Position of text, matching case.", "Text"),
        WishFunctionInfo("SEARCH", "SEARCH(search, text, [start])", "Position of text, ignoring case.", "Text"),
        WishFunctionInfo("EXACT", "EXACT(a, b)", "TRUE when two texts are identical.", "Text"),
        WishFunctionInfo("CHAR", "CHAR(code)", "Character for a code.", "Text"),
        WishFunctionInfo("CODE", "CODE(text)", "Code of the first character.", "Text"),
        WishFunctionInfo("UNICHAR", "UNICHAR(code)", "Unicode character for a code.", "Text"),
        WishFunctionInfo("UNICODE", "UNICODE(text)", "Unicode code of the first character.", "Text"),
        WishFunctionInfo("VALUE", "VALUE(text)", "Turns text into a number.", "Text"),
        WishFunctionInfo("T", "T(value)", "The text, or nothing if it is not text.", "Text"),
        WishFunctionInfo("SPLIT", "SPLIT(text, delimiter)", "Cuts text into a list.", "Text"),
        WishFunctionInfo("REGEXMATCH", "REGEXMATCH(text, pattern)", "TRUE if the pattern matches.", "Text"),
        WishFunctionInfo("REGEXEXTRACT", "REGEXEXTRACT(text, pattern)", "The part that matches.", "Text"),
        WishFunctionInfo("REGEXREPLACE", "REGEXREPLACE(text, pattern, new)", "Replaces what matches.", "Text"),
        WishFunctionInfo("ROMAN", "ROMAN(number)", "Roman numerals.", "Text"),
        // Logic
        WishFunctionInfo("IF", "IF(test, then, else)", "Picks one of two answers.", "Logic"),
        WishFunctionInfo("IFS", "IFS(test1, answer1, test2, answer2, ...)", "First test that is true wins.", "Logic"),
        WishFunctionInfo("IFERROR", "IFERROR(value, fallback)", "A fallback when something fails.", "Logic"),
        WishFunctionInfo("IFNA", "IFNA(value, fallback)", "A fallback for #N/A.", "Logic"),
        WishFunctionInfo("AND", "AND(a, b, ...)", "TRUE when all are true.", "Logic"),
        WishFunctionInfo("OR", "OR(a, b, ...)", "TRUE when any is true.", "Logic"),
        WishFunctionInfo("XOR", "XOR(a, b, ...)", "TRUE when an odd number are true.", "Logic"),
        WishFunctionInfo("NOT", "NOT(a)", "Flips true and false.", "Logic"),
        WishFunctionInfo("TRUE", "TRUE()", "Always true.", "Logic"),
        WishFunctionInfo("FALSE", "FALSE()", "Always false.", "Logic"),
        WishFunctionInfo("SWITCH", "SWITCH(value, case1, answer1, ..., [default])", "Matches a value against cases.", "Logic"),
        WishFunctionInfo("CHOOSE", "CHOOSE(index, a, b, c, ...)", "Picks the nth answer.", "Logic"),
        WishFunctionInfo("ISBLANK", "ISBLANK(value)", "TRUE when empty.", "Logic"),
        WishFunctionInfo("ISNUMBER", "ISNUMBER(value)", "TRUE for numbers.", "Logic"),
        WishFunctionInfo("ISTEXT", "ISTEXT(value)", "TRUE for text.", "Logic"),
        WishFunctionInfo("ISERROR", "ISERROR(value)", "TRUE when something failed.", "Logic"),
        WishFunctionInfo("ISNA", "ISNA(value)", "TRUE for #N/A.", "Logic"),
        WishFunctionInfo("ISEVEN", "ISEVEN(number)", "TRUE for even numbers.", "Logic"),
        WishFunctionInfo("ISODD", "ISODD(number)", "TRUE for odd numbers.", "Logic"),
        // Math
        WishFunctionInfo("SUM", "SUM(a, b, ...)", "Adds numbers.", "Math"),
        WishFunctionInfo("AVERAGE", "AVERAGE(a, b, ...)", "The average.", "Math"),
        WishFunctionInfo("MIN", "MIN(a, b, ...)", "Smallest.", "Math"),
        WishFunctionInfo("MAX", "MAX(a, b, ...)", "Largest.", "Math"),
        WishFunctionInfo("COUNT", "COUNT(a, b, ...)", "How many numbers.", "Math"),
        WishFunctionInfo("COUNTA", "COUNTA(a, b, ...)", "How many are not empty.", "Math"),
        WishFunctionInfo("COUNTIF", "COUNTIF(list, \">5\")", "How many match a test.", "Math"),
        WishFunctionInfo("PRODUCT", "PRODUCT(a, b, ...)", "Multiplies numbers.", "Math"),
        WishFunctionInfo("MEDIAN", "MEDIAN(a, b, ...)", "The middle number.", "Math"),
        WishFunctionInfo("MODE", "MODE(a, b, ...)", "The most common number.", "Math"),
        WishFunctionInfo("LARGE", "LARGE(list, n)", "The nth largest.", "Math"),
        WishFunctionInfo("SMALL", "SMALL(list, n)", "The nth smallest.", "Math"),
        WishFunctionInfo("STDEV", "STDEV(a, b, ...)", "Standard deviation.", "Math"),
        WishFunctionInfo("VAR", "VAR(a, b, ...)", "Variance.", "Math"),
        WishFunctionInfo("ROUND", "ROUND(number, [digits])", "Rounds.", "Math"),
        WishFunctionInfo("ROUNDUP", "ROUNDUP(number, [digits])", "Rounds away from zero.", "Math"),
        WishFunctionInfo("ROUNDDOWN", "ROUNDDOWN(number, [digits])", "Rounds toward zero.", "Math"),
        WishFunctionInfo("CEILING", "CEILING(number, [step])", "Rounds up to a step.", "Math"),
        WishFunctionInfo("FLOOR", "FLOOR(number, [step])", "Rounds down to a step.", "Math"),
        WishFunctionInfo("INT", "INT(number)", "Rounds down to a whole number.", "Math"),
        WishFunctionInfo("TRUNC", "TRUNC(number, [digits])", "Cuts off decimals.", "Math"),
        WishFunctionInfo("ABS", "ABS(number)", "Removes the minus sign.", "Math"),
        WishFunctionInfo("SIGN", "SIGN(number)", "1, 0 or -1.", "Math"),
        WishFunctionInfo("SQRT", "SQRT(number)", "Square root.", "Math"),
        WishFunctionInfo("POWER", "POWER(number, power)", "A number to a power.", "Math"),
        WishFunctionInfo("MOD", "MOD(number, divisor)", "The remainder.", "Math"),
        WishFunctionInfo("QUOTIENT", "QUOTIENT(number, divisor)", "Whole-number division.", "Math"),
        WishFunctionInfo("EXP", "EXP(number)", "e to a power.", "Math"),
        WishFunctionInfo("LN", "LN(number)", "Natural logarithm.", "Math"),
        WishFunctionInfo("LOG", "LOG(number, [base])", "Logarithm.", "Math"),
        WishFunctionInfo("LOG10", "LOG10(number)", "Base 10 logarithm.", "Math"),
        WishFunctionInfo("FACT", "FACT(number)", "Factorial.", "Math"),
        WishFunctionInfo("GCD", "GCD(a, b, ...)", "Greatest common divisor.", "Math"),
        WishFunctionInfo("LCM", "LCM(a, b, ...)", "Least common multiple.", "Math"),
        WishFunctionInfo("SIN", "SIN(radians)", "Sine.", "Math"),
        WishFunctionInfo("COS", "COS(radians)", "Cosine.", "Math"),
        WishFunctionInfo("TAN", "TAN(radians)", "Tangent.", "Math"),
        WishFunctionInfo("DEGREES", "DEGREES(radians)", "Radians to degrees.", "Math"),
        WishFunctionInfo("RADIANS", "RADIANS(degrees)", "Degrees to radians.", "Math"),
        WishFunctionInfo("PI", "PI()", "3.14159...", "Math"),
        WishFunctionInfo("RAND", "RAND()", "A random number from 0 to 1.", "Math"),
        WishFunctionInfo("RANDBETWEEN", "RANDBETWEEN(low, high)", "A random whole number.", "Math"),
        // Lists
        WishFunctionInfo("INDEX", "INDEX(list, n)", "The nth item.", "Lists"),
        WishFunctionInfo("SEQUENCE", "SEQUENCE(count, [start], [step])", "A list of numbers.", "Lists"),
        WishFunctionInfo("SORT", "SORT(list, [ascending])", "Sorts a list.", "Lists"),
        WishFunctionInfo("UNIQUE", "UNIQUE(list)", "Removes repeats.", "Lists"),
        WishFunctionInfo("FIELD", "FIELD(\"name\")", "The value of an Information field.", "Lists"),
        // EzMe extras
        WishFunctionInfo("INR", "INR(number)", "Rupees with Indian grouping: \u{20B9}12,34,567.", "KeyDo extras"),
        WishFunctionInfo("ORDINAL", "ORDINAL(number)", "1st, 2nd, 3rd. Try =ORDINAL(AGE(dob)).", "KeyDo extras"),
        WishFunctionInfo("AGE", "AGE(date)", "Whole years since a date.", "KeyDo extras"),
        WishFunctionInfo("COUNTDOWN", "COUNTDOWN(date)", "Days until that date comes round next (birthdays, anniversaries).", "KeyDo extras"),
        WishFunctionInfo("GREETING", "GREETING()", "Good morning, afternoon or evening (Hindi on Hindi cards).", "KeyDo extras"),
    ]

    /// Names that a custom function may not reuse.
    static var reservedNames: Set<String> {
        var names = Set(all.map { $0.name.lowercased() })
        for word in words { names.insert(word.name.lowercased()) }
        names.formUnion(["pi", "true", "false", "second"])
        return names
    }
}
