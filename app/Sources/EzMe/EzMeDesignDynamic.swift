// Designs whose words change with the clock (days to go, today's date, the time) are best delivered as a web page,
// because the page works the number out again each time it is opened. Everything else stays an image.
import Foundation

enum DesignDynamic {
    private static let pattern = try? NSRegularExpression(
        pattern: "\\{=.*(\\b(COUNTDOWN|NOW|TIME|HOUR|MINUTE|SECOND)\\b|DAYS\\(.*TODAY)",
        options: [.caseInsensitive])

    /// True when any box has a function whose answer changes by the day or minute.
    static func isDynamic(_ pages: [ImageTemplate]) -> Bool {
        guard let pattern else { return false }
        for page in pages {
            for slot in page.slots {
                guard let content = slot.content, content.contains("{=") else { continue }
                if pattern.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)) != nil { return true }
            }
        }
        return false
    }

    /// The format a design delivers: the one the person chose, else HTML when it counts down, else image (PDF for several pages).
    @MainActor static func format(_ design: AppDesign?, pages: [ImageTemplate]? = nil) -> DesignFormat {
        let used = pages ?? design.map { AppDesignStore.shared.activePages($0) } ?? []
        let plain: DesignFormat = used.count > 1 ? .pdf : .png
        guard let design else { return plain }
        let chosen = DesignFormat.from(design.outputFormat)
        if design.formatPinned == true, let chosen { return chosen }
        if isDynamic(used) && (chosen == nil || chosen == .png || chosen == .pdf) { return .html }
        return chosen ?? plain
    }
}

/// Works out "N days to go" again inside the web page, so the number is right whenever the page is opened.
enum DesignLiveText {
    private static let daysRegex = try? NSRegularExpression(pattern: "\\{=\\s*DAYS\\(\\s*\"([^\"]*)\"\\s*,\\s*TODAY\\(\\)\\s*\\)\\s*\\}", options: [.caseInsensitive])
    private static let countdownRegex = try? NSRegularExpression(pattern: "\\{=\\s*COUNTDOWN\\(\\s*\"([^\"]*)\"\\s*\\)\\s*\\}", options: [.caseInsensitive])

    /// Returns the box text as HTML with a live number, or nil when the box has nothing that counts days.
    @MainActor static func html(content: String, values: [String: String], escape: (String) -> String) -> String? {
        // Plain variables first, so the date inside the formula is the one the person typed.
        var text = content
        if let plain = try? NSRegularExpression(pattern: "\\{\\{([^}@:]+)\\}\\}") {
            let ns = text as NSString
            for match in plain.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
                let name = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                let value = values[TemplateFill.normal(name)] ?? ""
                text = (text as NSString).replacingCharacters(in: match.range, with: value)
            }
        }
        for (regex, repeating) in [(daysRegex, false), (countdownRegex, true)] {
            guard let regex else { continue }
            let ns = text as NSString
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { continue }
            guard let date = WishFormula.parseDate(ns.substring(with: match.range(at: 1))) else { continue }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let before = DesignContent.resolve(ns.substring(to: match.range.location), values: values, designing: false)
            let after = DesignContent.resolve(ns.substring(from: match.range.location + match.range.length), values: values, designing: false)
            let span = "<span class=\"live\" data-d=\"\(formatter.string(from: date))\" data-r=\"\(repeating ? 1 : 0)\"></span>"
            return escape(before).replacingOccurrences(of: "\n", with: "<br>") + span + escape(after).replacingOccurrences(of: "\n", with: "<br>")
        }
        return nil
    }

    static let script = """
    function live(){var t=new Date();var today=new Date(t.getFullYear(),t.getMonth(),t.getDate());document.querySelectorAll('.live').forEach(function(s){var p=s.dataset.d.split('-');var d=new Date(+p[0],+p[1]-1,+p[2]);if(s.dataset.r==='1'){d=new Date(today.getFullYear(),+p[1]-1,+p[2]);if(d<today)d=new Date(today.getFullYear()+1,+p[1]-1,+p[2])}s.textContent=Math.round((d-today)/864e5)});fit()}
    setInterval(live,60000);
    """
}
