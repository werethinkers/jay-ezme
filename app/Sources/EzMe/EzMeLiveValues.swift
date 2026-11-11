// One list of live values for the whole app.
//
// The Library (Live & dynamic), AppBuilder templates and WishStudio all read from here, so a value that
// works in one place works in the others. Values are written {{like this}} in the Library and AppBuilder;
// WishStudio writes the same thing as =Like this. Anything WishStudio can calculate can also be used in a
// template as {{=FORMULA}}, for example {{=INR(1234567)}} or {{=ORDINAL(21)}}.
import Foundation
import AppKit
import SwiftUI

struct LiveValueInfo: Identifiable, Hashable {
    let token: String      // what to type, with the braces
    let summary: String
    let group: String
    var id: String { return token }
}

enum LiveValues {
    static let groups = ["Date & time", "Offsets", "Smart (from WishStudio)", "System"]

    /// Every live value, in the order it is shown. Used by the Library panel, the AppBuilder insert menu
    /// and the example shortcuts.
    static let catalog: [LiveValueInfo] = [
        LiveValueInfo(token: "{{date}}", summary: "Today's date", group: "Date & time"),
        LiveValueInfo(token: "{{time}}", summary: "The time now", group: "Date & time"),
        LiveValueInfo(token: "{{datetime}}", summary: "Date and time now", group: "Date & time"),
        LiveValueInfo(token: "{{now}}", summary: "Date and time now (same as datetime)", group: "Date & time"),
        LiveValueInfo(token: "{{today}}", summary: "Today's date (same as date)", group: "Date & time"),
        LiveValueInfo(token: "{{weekday}}", summary: "Today's weekday name", group: "Date & time"),
        LiveValueInfo(token: "{{day}}", summary: "Day of the month", group: "Date & time"),
        LiveValueInfo(token: "{{month}}", summary: "This month's name", group: "Date & time"),
        LiveValueInfo(token: "{{year}}", summary: "This year", group: "Date & time"),
        LiveValueInfo(token: "{{week}}", summary: "Week number of the year", group: "Date & time"),
        LiveValueInfo(token: "{{hour}}", summary: "The hour now, 0 to 23", group: "Date & time"),
        LiveValueInfo(token: "{{minute}}", summary: "The minute now", group: "Date & time"),
        LiveValueInfo(token: "{{second}}", summary: "The second now", group: "Date & time"),

        LiveValueInfo(token: "{{date+1}}", summary: "Tomorrow's date", group: "Offsets"),
        LiveValueInfo(token: "{{date-1}}", summary: "Yesterday's date", group: "Offsets"),
        LiveValueInfo(token: "{{date+7}}", summary: "The date a week from now", group: "Offsets"),
        LiveValueInfo(token: "{{weekday+1}}", summary: "Tomorrow's weekday name", group: "Offsets"),
        LiveValueInfo(token: "{{month+1}}", summary: "Next month's name", group: "Offsets"),
        LiveValueInfo(token: "{{year+1}}", summary: "Next year", group: "Offsets"),
        LiveValueInfo(token: "{{time+1}}", summary: "The time one hour from now", group: "Offsets"),

        LiveValueInfo(token: "{{greeting}}", summary: "Good morning, afternoon or evening", group: "Smart (from WishStudio)"),
        LiveValueInfo(token: "{{=INR(1234567)}}", summary: "Rupees with Indian grouping", group: "Smart (from WishStudio)"),
        LiveValueInfo(token: "{{=ORDINAL(21)}}", summary: "1st, 2nd, 3rd", group: "Smart (from WishStudio)"),
        LiveValueInfo(token: "{{=AGE(\"15/08/1990\")}}", summary: "Whole years since a date", group: "Smart (from WishStudio)"),
        LiveValueInfo(token: "{{=COUNTDOWN(\"15/08/1990\")}}", summary: "Days until that date next comes round", group: "Smart (from WishStudio)"),
        LiveValueInfo(token: "{{=TEXT(Date,\"dddd, d mmmm\")}}", summary: "Any WishStudio formula works after =", group: "Smart (from WishStudio)"),

        LiveValueInfo(token: "{{timestamp}}", summary: "Date and time in ISO form", group: "System"),
        LiveValueInfo(token: "{{unix}}", summary: "Seconds since 1970", group: "System"),
        LiveValueInfo(token: "{{uuid}}", summary: "A new unique ID", group: "System"),
        LiveValueInfo(token: "{{clipboard}}", summary: "Whatever you last copied", group: "System"),
        LiveValueInfo(token: "{{worldclock:Asia/Kolkata}}", summary: "Time in India", group: "System"),
        LiveValueInfo(token: "{{worldclock:London}}", summary: "Time in London", group: "System"),
        LiveValueInfo(token: "{{worldclock:New York}}", summary: "Time in New York", group: "System"),
        LiveValueInfo(token: "{{worldclock:Tokyo}}", summary: "Time in Tokyo", group: "System"),
    ]

    /// Plain words that work as {{word}}.
    static let words: Set<String> = [
        "date", "today", "time", "datetime", "now", "timestamp", "weekday", "day", "month", "year", "week",
        "hour", "minute", "second", "unix", "uuid", "clipboard", "greeting",
    ]

    /// Words that can take +N or -N, with the size of one step.
    private static let stepWords: Set<String> = [
        "date", "today", "datetime", "now", "weekday", "day", "time", "hour", "minute", "second", "month", "year",
    ]

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }

    private static func show(_ word: String, _ date: Date) -> String? {
        let cal = calendar
        switch word {
        case "date", "today": return date.formatted(date: .long, time: .omitted)
        case "time": return date.formatted(date: .omitted, time: .shortened)
        case "datetime", "now": return date.formatted(date: .long, time: .shortened)
        case "weekday": return date.formatted(.dateTime.weekday(.wide))
        case "month": return date.formatted(.dateTime.month(.wide))
        case "year": return date.formatted(.dateTime.year())
        case "day": return date.formatted(.dateTime.day())
        case "hour": return String(cal.component(.hour, from: date))
        case "minute": return String(cal.component(.minute, from: date))
        case "second": return String(cal.component(.second, from: date))
        case "week": return String(cal.component(.weekOfYear, from: date))
        default: return nil
        }
    }

    private static func shifted(_ word: String, by amount: Double, from date: Date) -> Date? {
        let cal = calendar
        switch word {
        case "date", "today", "datetime", "now", "weekday", "day":
            return date.addingTimeInterval(amount * 86400)
        case "time", "hour":
            return date.addingTimeInterval(amount * 3600)
        case "minute":
            return date.addingTimeInterval(amount * 60)
        case "second":
            return date.addingTimeInterval(amount)
        case "month":
            return cal.date(byAdding: .month, value: Int(amount), to: date)
        case "year":
            return cal.date(byAdding: .year, value: Int(amount), to: date)
        default:
            return nil
        }
    }

    /// True when `inner` (the text between the braces) is a live value, so a template check can accept it.
    static func isLive(_ inner: String) -> Bool {
        return resolve(inner, clipboard: "") != nil
    }

    /// The text for one token, or nil when it is not a live value (so it can be left as typed).
    static func resolve(_ inner: String, clipboard: String? = nil) -> String? {
        let raw = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        let now = Date()

        // Formulas: {{=INR(5)}} or a bare function call such as {{INR(5)}}.
        if raw.hasPrefix("=") && raw.count > 1 {
            return formula(raw)
        }
        if let open = raw.firstIndex(of: "("), raw.hasSuffix(")") {
            let name = String(raw[..<open]).trimmingCharacters(in: .whitespaces).uppercased()
            if !name.isEmpty, WishFunctionCatalog.all.contains(where: { $0.name == name }) {
                return formula("=" + raw)
            }
        }

        if lower.hasPrefix("worldclock:") {
            return WishFormula.worldClock(String(raw.dropFirst("worldclock:".count)), now: now)
        }

        switch lower {
        case "timestamp": return ISO8601DateFormatter().string(from: now)
        case "unix": return String(Int(now.timeIntervalSince1970))
        case "uuid": return UUID().uuidString
        case "clipboard": return clipboard ?? NSPasteboard.general.string(forType: .string) ?? ""
        case "greeting": return formula("=GREETING()")
        default: break
        }

        if words.contains(lower), let text = show(lower, now) { return text }

        // date+1, weekday-1, month+2, time+0.5 ...
        if let regex = try? NSRegularExpression(pattern: #"^([a-z]+)\s*([+-])\s*(\d+(?:\.\d+)?)$"#),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let wordRange = Range(match.range(at: 1), in: lower),
           let signRange = Range(match.range(at: 2), in: lower),
           let numberRange = Range(match.range(at: 3), in: lower) {
            let word = String(lower[wordRange])
            guard stepWords.contains(word), let size = Double(lower[numberRange]) else { return nil }
            let amount = lower[signRange] == "-" ? -size : size
            if let moved = shifted(word, by: amount, from: now) { return show(word, moved) }
        }
        return nil
    }

    private static func formula(_ source: String) -> String? {
        let context = WishContext()
        let value = WishFormula.evaluate(source, context: context)
        if case .error = value { return nil }
        return value.display(context)
    }

    /// Replaces every live token in `source`. Tokens that are not live values are left exactly as typed.
    static func expand(_ source: String, clipboard: String? = nil) -> String {
        guard source.contains("{{"), let regex = try? NSRegularExpression(pattern: #"\{\{([^}]+)\}\}"#) else { return source }
        let ns = source as NSString
        var result = source
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)).reversed() {
            let inner = ns.substring(with: match.range(at: 1))
            guard let value = resolve(inner, clipboard: clipboard) else { continue }
            result = (result as NSString).replacingCharacters(in: match.range, with: value)
        }
        return result
    }
}

extension LiveValues {
    /// Example shortcuts added to the Library's "Live & dynamic" collection, one for each live value.
    static let exampleShortcuts: [(key: String, name: String, text: String)] = [
        ("now", "Date and time now", "{{datetime}}"),
        ("tomorrow", "Tomorrow's date", "{{date+1}}"),
        ("yesterday", "Yesterday's date", "{{date-1}}"),
        ("nextweek", "Date a week from today", "{{date+7}}"),
        ("weekday", "Today's weekday", "{{weekday}}"),
        ("nextday", "Tomorrow's weekday", "{{weekday+1}}"),
        ("day", "Day of the month", "{{day}}"),
        ("month", "This month", "{{month}}"),
        ("nextmonth", "Next month", "{{month+1}}"),
        ("year", "This year", "{{year}}"),
        ("nextyear", "Next year", "{{year+1}}"),
        ("week", "Week number", "{{week}}"),
        ("hour", "Hour now", "{{hour}}"),
        ("minute", "Minute now", "{{minute}}"),
        ("inhour", "Time one hour from now", "{{time+1}}"),
        ("greet", "Greeting for the time of day", "{{greeting}}"),
        ("hello", "Greeting with today's date", "{{greeting}}! Today is {{weekday}}, {{date}}."),
        ("inr", "Rupee format example", "{{=INR(1234567)}}"),
        ("ordinal", "Ordinal number example", "{{=ORDINAL(21)}}"),
        ("age", "Age from a birth date (edit the date)", "{{=AGE(\"15/08/1990\")}} years"),
        ("birthday", "Days until a birthday (edit the date)", "{{=COUNTDOWN(\"15/08/1990\")}} days to go"),
        ("longdate", "Long date with weekday", "{{=TEXT(Date,\"dddd, d mmmm yyyy\")}}"),
        ("stamp", "ISO timestamp", "{{timestamp}}"),
        ("unix", "Unix time", "{{unix}}"),
        ("uuid", "New unique ID", "{{uuid}}"),
        ("india", "Time in India", "{{worldclock:Asia/Kolkata}}"),
        ("london", "Time in London", "{{worldclock:London}}"),
        ("newyork", "Time in New York", "{{worldclock:New York}}"),
        ("tokyo", "Time in Tokyo", "{{worldclock:Tokyo}}"),
    ]
}

/// The list of live values shown in the Library and in Settings. Tap the copy button, or pass `onPick` to insert.
struct LiveValuesList: View {
    var onPick: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(LiveValues.groups, id: \.self) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group).font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(LiveValues.catalog.filter { $0.group == group }) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(item.token)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                            Text(item.summary).font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button {
                                if let onPick { onPick(item.token) } else {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item.token, forType: .string)
                                }
                            } label: {
                                Image(systemName: onPick == nil ? "doc.on.doc" : "plus.circle")
                            }
                            .buttonStyle(.plain)
                            .help(onPick == nil ? "Copy \(item.token)" : "Insert \(item.token)")
                        }
                    }
                }
            }
            Text("These are the same live values WishStudio uses. In WishStudio write =Date+1; in a shortcut or AppBuilder template write {{date+1}}. Anything WishStudio can calculate also works after an equals sign, like {{=INR(5000)}}.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(6)
    }
}
