// Data types for variables: what kind of value a box of the form takes (text, number, currency, date, phone...).
// The type is kept with the design's variables under a hidden key, so every screen that already carries the
// variables (designer, form, popup, live preview) knows it without new plumbing.
import SwiftUI
import AppKit

enum DesignDataType: String, CaseIterable, Identifiable {
    case text, long, number, whole, currency, date, time, phone, email, link
    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "Text"
        case .long: return "Long text"
        case .number: return "Number"
        case .whole: return "Whole number"
        case .currency: return "Currency"
        case .date: return "Date"
        case .time: return "Time"
        case .phone: return "Phone"
        case .email: return "Email"
        case .link: return "Web link"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "textformat"
        case .long: return "text.alignleft"
        case .number: return "number"
        case .whole: return "number.square"
        case .currency: return "indianrupeesign.circle"
        case .date: return "calendar"
        case .time: return "clock"
        case .phone: return "phone"
        case .email: return "envelope"
        case .link: return "link"
        }
    }

    var example: String {
        switch self {
        case .text: return "Any words"
        case .long: return "A few lines"
        case .number: return "1250.5"
        case .whole: return "25"
        case .currency: return "1,25,000"
        case .date: return "14 Feb 2027"
        case .time: return "5:30 PM"
        case .phone: return "98765 43210"
        case .email: return "name@example.com"
        case .link: return "example.com"
        }
    }

    // MARK: Where the type is kept

    static let prefix = "__type."
    static func key(_ name: String) -> String { prefix + TemplateFill.normal(name) }
    static func isHidden(_ key: String) -> Bool { key.hasPrefix(prefix) || key.hasPrefix(requiredPrefix) }
    /// Marks a box the person must fill before the app makes anything.
    static let requiredPrefix = "__req."
    static func requiredKey(_ name: String) -> String { requiredPrefix + TemplateFill.normal(name) }
    static func isRequired(_ name: String, in variables: [String: String]) -> Bool { variables[requiredKey(name)] != nil }
    static func of(_ name: String, in variables: [String: String]) -> DesignDataType {
        variables[key(name)].flatMap { DesignDataType(rawValue: $0) } ?? .text
    }
    /// The variable names to show, without the hidden type entries.
    static func names(_ variables: [String: String]) -> [String] { variables.keys.filter { !isHidden($0) }.sorted() }
    static func set(_ type: DesignDataType, for name: String, in variables: inout [String: String]) {
        if type == .text { variables[key(name)] = nil } else { variables[key(name)] = type.rawValue }
    }

    /// "string", "money", "mobile number" and so on, as people say them.
    static func spoken(_ words: String) -> DesignDataType? {
        let w = words.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .,!?")).replacingOccurrences(of: "^(?:a|an)\\s+", with: "", options: .regularExpression)
        let table: [(DesignDataType, [String])] = [
            (.whole, ["whole number", "whole numbers", "integer", "count", "quantity", "age"]),
            (.currency, ["currency", "money", "amount", "price", "rupees", "rupee", "rs", "inr", "dollars", "cost", "salary"]),
            (.number, ["number", "numbers", "numeric", "decimal", "digits"]),
            (.date, ["date", "day", "dates"]),
            (.time, ["time", "clock", "hour"]),
            (.phone, ["phone", "phone number", "mobile", "mobile number", "contact number", "whatsapp"]),
            (.email, ["email", "e-mail", "mail", "email address"]),
            (.link, ["link", "url", "website", "web link", "web address"]),
            (.long, ["long text", "paragraph", "notes", "message", "description"]),
            (.text, ["text", "string", "word", "words", "name", "plain text"])
        ]
        for (type, names) in table where names.contains(w) { return type }
        return nil
    }

    // MARK: Checking a value

    struct Check { var ok: Bool; var clean: String; var message: String }

    /// Works out the plain number inside "₹ 1,25,000.50", "Rs. 500" or "1,200": nil when it is not a number.
    static func numeric(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        for symbol in ["Rs.", "Rs", "INR", "USD", "\u{20B9}", "$", "\u{20AC}", "\u{00A3}", ",", " "] { text = text.replacingOccurrences(of: symbol, with: "", options: .caseInsensitive) }
        guard let value = Double(text), value.isFinite else { return nil }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(format: "%.6f", value).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
    }

    private static func grouped(_ plain: String) -> String {
        guard let value = Double(plain) else { return plain }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = plain.contains(".") ? 2 : 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? plain
    }

    func check(_ raw: String) -> Check {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.hasPrefix("{=") { return Check(ok: true, clean: raw, message: "") }
        switch self {
        case .text, .long:
            return Check(ok: true, clean: raw, message: "")
        case .number:
            if let plain = Self.numeric(text) { return Check(ok: true, clean: plain, message: "") }
            return Check(ok: false, clean: raw, message: "Numbers only, like 1250.5")
        case .whole:
            if let plain = Self.numeric(text), let value = Double(plain), value == value.rounded() { return Check(ok: true, clean: String(Int64(value)), message: "") }
            return Check(ok: false, clean: raw, message: "A whole number, like 25")
        case .currency:
            if let plain = Self.numeric(text) { return Check(ok: true, clean: Self.grouped(plain), message: "") }
            return Check(ok: false, clean: raw, message: "An amount, like 1,25,000")
        case .date:
            if let date = WishFormula.parseDate(text) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_IN")
                formatter.dateFormat = "d MMMM yyyy"
                return Check(ok: true, clean: formatter.string(from: date), message: "")
            }
            return Check(ok: false, clean: raw, message: "A date, like 14 Feb 2027")
        case .time:
            if let clean = Self.time(text) { return Check(ok: true, clean: clean, message: "") }
            return Check(ok: false, clean: raw, message: "A time, like 5:30 PM or 17:30")
        case .phone:
            let digits = text.filter { $0.isNumber }
            guard (7...15).contains(digits.count), text.allSatisfy({ $0.isNumber || " +-()".contains($0) }) else {
                return Check(ok: false, clean: raw, message: "A phone number, like 98765 43210")
            }
            if digits.count == 10 { return Check(ok: true, clean: "\(digits.prefix(5)) \(digits.suffix(5))", message: "") }
            if text.hasPrefix("+"), digits.count == 12, digits.hasPrefix("91") { return Check(ok: true, clean: "+91 \(digits.dropFirst(2).prefix(5)) \(digits.suffix(5))", message: "") }
            return Check(ok: true, clean: (text.hasPrefix("+") ? "+" : "") + digits, message: "")
        case .email:
            let pattern = "^[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,}$"
            if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { return Check(ok: true, clean: text.lowercased(), message: "") }
            return Check(ok: false, clean: raw, message: "An email, like name@example.com")
        case .link:
            if text.contains(" ") || !text.contains(".") { return Check(ok: false, clean: raw, message: "A web link, like example.com") }
            return Check(ok: true, clean: text, message: "")
        }
    }

    private static func time(_ text: String) -> String? {
        let lower = text.lowercased().replacingOccurrences(of: ".", with: ":").replacingOccurrences(of: " ", with: "")
        guard let regex = try? NSRegularExpression(pattern: "^(\\d{1,2})(?::(\\d{2}))?(am|pm)?$"),
              let m = regex.firstMatch(in: lower, range: NSRange(location: 0, length: (lower as NSString).length)) else { return nil }
        func part(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : (lower as NSString).substring(with: m.range(at: i)) }
        guard var hour = Int(part(1)) else { return nil }
        let minute = Int(part(2)) ?? 0
        let suffix = part(3)
        guard minute < 60 else { return nil }
        if suffix.isEmpty && part(2).isEmpty { return nil }
        var ampm = suffix
        if suffix.isEmpty { ampm = hour >= 12 ? "pm" : "am"; if hour > 12 { hour -= 12 }; if hour == 0 { hour = 12 } }
        else if hour < 1 || hour > 12 { return nil }
        return String(format: "%d:%02d %@", hour, minute, ampm.uppercased())
    }
}

// MARK: - The input of a typed field

/// A small line under a form box: the type, and a red note when the value does not fit it.
struct DesignTypeNote: View {
    var type: DesignDataType
    var text: String

    var body: some View {
        let check = type.check(text)
        HStack(spacing: 4) {
            Image(systemName: check.ok ? type.symbol : "exclamationmark.triangle.fill").font(.system(size: 9))
            Text(check.ok ? (text.isEmpty ? "\(type.title), like \(type.example)" : type.title) : check.message).font(.system(size: 10))
        }
        .foregroundStyle(check.ok ? Butter.cocoa.opacity(0.6) : Color(red: 0.74, green: 0.18, blue: 0.1))
    }
}

/// Date and time boxes get a small calendar or clock to pick from.
struct DesignDatePickButton: View {
    var type: DesignDataType
    @Binding var text: String
    @State private var open = false
    @State private var picked = Date()

    var body: some View {
        Button { picked = WishFormula.parseDate(text) ?? Date(); open = true } label: { Image(systemName: type.symbol) }
            .buttonStyle(.bordered).controlSize(.small).help(type == .date ? "Pick a date" : "Pick a time")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(spacing: 8) {
                    if type == .date { DatePicker("", selection: $picked, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden() }
                    else { DatePicker("", selection: $picked, displayedComponents: .hourAndMinute).datePickerStyle(.stepperField).labelsHidden() }
                    Button("Use this") {
                        let formatter = DateFormatter()
                        formatter.locale = Locale(identifier: "en_IN")
                        formatter.dateFormat = type == .date ? "d MMMM yyyy" : "h:mm a"
                        text = formatter.string(from: picked)
                        open = false
                    }.buttonStyle(.borderedProminent).tint(Butter.coral)
                }
                .padding(12)
            }
    }
}

// MARK: - Spoken values

extension DesignDataType {
    private static let digitWords: [String: String] = ["zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
                                                        "six": "6", "seven": "7", "eight": "8", "nine": "9", "double": ""]

    /// "nine eight seven six five", "2 lakh", "14th of February", "name at example dot com" turned into what the box takes.
    func fromSpeech(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .phone:
            let words = text.lowercased().split(separator: " ").map(String.init)
            if words.contains(where: { Self.digitWords[$0] != nil && $0 != "double" }) {
                var out = ""
                var repeatNext = false
                for word in words {
                    if word == "double" { repeatNext = true; continue }
                    let digit = Self.digitWords[word] ?? word
                    out += repeatNext ? digit + digit : digit
                    repeatNext = false
                }
                text = out
            }
        case .number, .whole, .currency:
            let lower = text.lowercased().replacingOccurrences(of: "rupees", with: "").replacingOccurrences(of: "rupee", with: "").replacingOccurrences(of: " point ", with: ".")
            let scales: [(String, Double)] = [("crore", 1e7), ("lakh", 1e5), ("lac", 1e5), ("thousand", 1e3), ("million", 1e6), ("k", 1e3)]
            for (word, scale) in scales {
                if let range = lower.range(of: "\\s*" + word + "\\b", options: .regularExpression) {
                    let head = String(lower[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if let plain = Self.numeric(head), let value = Double(plain) {
                        let total = value * scale
                        return total == total.rounded() ? String(Int64(total)) : String(total)
                    }
                }
            }
            text = lower.trimmingCharacters(in: .whitespaces)
        case .date:
            text = text.replacingOccurrences(of: "(\\d+)(?:st|nd|rd|th)\\b", with: "$1", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "\\bof\\b", with: "", options: [.regularExpression, .caseInsensitive])
                .split(separator: " ").joined(separator: " ")
        case .time:
            text = text.replacingOccurrences(of: "([ap])\\.?\\s?m\\.?", with: "$1m", options: [.regularExpression, .caseInsensitive])
        case .email:
            text = text.lowercased().replacingOccurrences(of: " at ", with: "@").replacingOccurrences(of: " dot ", with: ".").replacingOccurrences(of: " ", with: "")
        case .link:
            text = text.lowercased().replacingOccurrences(of: " dot ", with: ".").replacingOccurrences(of: " ", with: "")
        default: break
        }
        let result = self.check(text)
        return result.ok ? result.clean : text
    }
}
