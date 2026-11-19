// One place that understands a spoken or typed "open ..." command, so voice, Siri and Shortcuts all behave the same.
import Foundation
import AppKit

enum VoiceAction {
    case section(String)
    case builder(String)
    case collection(String)
    case url(String)
    case site(String, String)
    case macApp(URL)
}

enum VoiceRouter {
    private static let lead = ["hey siri", "ok siri", "siri", "in keydo", "on keydo", "with keydo", "to keydo", "keydo", "key do", "ezme", "ez me",
                               "please", "can you", "could you", "i want to", "i would like to", "take me to", "bring me to", "switch to", "go to", "show me", "pull up",
                               "open up", "open", "launch", "start", "run"]
    private static let noise: Set<String> = ["the", "my", "app", "application", "page", "tab", "screen", "section", "window", "please", "for", "me", "a", "to"]

    static func squash(_ text: String) -> String { String(text.lowercased().filter { $0.isLetter || $0.isNumber }) }

    /// The sentence without greetings, "open", "the", "app" and punctuation.
    static func clean(_ raw: String) -> (core: String, hadVerb: Bool) {
        var text = raw.lowercased().replacingOccurrences(of: "[^a-z0-9. ]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " dot ", with: ".").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        var verb = false
        var changed = true
        while changed {
            changed = false
            for phrase in lead where text == phrase || text.hasPrefix(phrase + " ") {
                if ["open up", "open", "launch", "start", "run", "go to", "switch to", "take me to", "bring me to", "show me", "pull up"].contains(phrase) { verb = true }
                text = String(text.dropFirst(phrase.count)).trimmingCharacters(in: .whitespaces)
                changed = true
                break
            }
        }
        for tail in [" in keydo", " on keydo", " with keydo", " in key do"] where text.hasSuffix(tail) { text = String(text.dropLast(tail.count)) }
        let words = text.split(separator: " ").map(String.init).filter { !noise.contains($0) }
        return (words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ". ")), verb)
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count { current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1)) }
            previous = current
        }
        return previous[y.count]
    }

    /// 0 for no match; higher is better.
    private static func score(_ spoken: String, _ alias: String) -> Int {
        let s = squash(spoken), a = squash(alias)
        guard !s.isEmpty, a.count >= 3 else { return 0 }
        if s == a { return 100 }
        if a.count >= 4, s.contains(a) { return 85 }
        if s.count >= 4, a.contains(s) { return 62 }
        let limit = a.count >= 9 ? 2 : (a.count >= 5 ? 1 : 0)
        if limit > 0, distance(s, a) <= limit { return 78 }
        return 0
    }

    static let sections: [(String, [String])] = [
        ("Dashboard", ["dashboard", "home", "home page", "start page"]),
        ("My shortcuts", ["my shortcuts", "shortcuts", "saved phrases", "all shortcuts"]),
        ("Collections", ["collections"]),
        ("Marketplace", ["marketplace", "market place", "store"]),
        ("AppBuilder", ["app builder", "appbuilder", "apps builder", "ai builder", "builders"]),
        ("AppDesigner", ["app designer", "appdesigner", "design an app", "template designer"]),
        ("WishStudio", ["wish studio", "wishstudio", "wish builder", "wishbuilder"]),
        ("API configuration", ["api configuration", "api keys", "api setup"]),
        ("Live & dynamic", ["live and dynamic", "live dynamic", "live values"]),
        ("Sound & media", ["sound and media", "sound media", "media files"]),
        ("Shortcut ideas", ["shortcut ideas", "ideas"]),
        ("Apps & links", ["apps and links", "apps links", "web links"]),
        ("Desktop apps", ["desktop apps", "mac apps"]),
        ("User guide", ["user guide", "help guide", "guide", "help"]),
        ("Browser", ["browser", "web browser", "internet", "safari"]),
        ("Ez Studio", ["ez studio", "studio", "image studio"]),
        ("Settings", ["settings", "preferences", "siri settings"])
    ]

    static func builderNames() -> [String] {
        let json = UserDefaults.standard.string(forKey: "ezmeCustomBuilderAppsJSON") ?? "[]"
        let user = (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
        var seen = Set<String>(), all = [String]()
        for name in ["Collection Builder", "MyDatabase", "Prompt Builder", "Template Designer"] + user where seen.insert(name.lowercased()).inserted { all.append(name) }
        return all
    }

    private static func builderAliases(_ name: String) -> [String] {
        switch name {
        case "Collection Builder": return ["collection builder", "build a collection", "make a collection", "create a collection"]
        case "Prompt Builder": return ["prompt builder", "prompt maker", "prompt writer", "write a prompt"]
        case "MyDatabase": return ["my database", "mydatabase", "my data base", "database", "contacts database"]
        default: return [name]
        }
    }

    private static var macApps: [(String, URL)] = {
        var found: [(String, URL)] = []
        for folder in ["/Applications", "/System/Applications", "/Applications/Utilities", "/System/Applications/Utilities"] {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for item in items where item.hasSuffix(".app") { found.append((String(item.dropLast(4)), URL(fileURLWithPath: folder + "/" + item))) }
        }
        return found
    }()

    /// What a spoken sentence means, or nil when KeyDo should fall back to searching shortcuts.
    static func resolve(_ raw: String, collections: [String], sites: [(title: String, url: String)]) -> VoiceAction? {
        let (core, hadVerb) = clean(raw)
        guard !core.isEmpty else { return nil }

        // A web address: "open youtube dot com", "go to chatgpt.com".
        if let range = core.range(of: "^([a-z0-9-]+\\.)+[a-z]{2,}(/\\S*)?$", options: .regularExpression), range.lowerBound == core.startIndex, !core.contains(" ") {
            return .url("https://" + core)
        }

        // "collection rohit" opens that collection only.
        if core.hasPrefix("collection ") || core.hasPrefix("collections ") {
            let name = core.split(separator: " ", maxSplits: 1).last.map(String.init) ?? ""
            let hit = collections.map { ($0, score(name, $0)) }.filter { $0.1 >= 70 }.max { $0.1 < $1.1 }
            if let hit { return .collection(hit.0) }
        }

        var best: (VoiceAction, Int)?
        func consider(_ action: VoiceAction, _ points: Int) { if points >= 70, points > (best?.1 ?? 0) { best = (action, points) } }

        for (name, aliases) in sections { consider(.section(name), (aliases.map { score(core, $0) }.max() ?? 0)) }
        for name in builderNames() { consider(.builder(name), (builderAliases(name).map { score(core, $0) }.max() ?? 0) + 2) }
        // Commands the person set for their own apps in AppBuilder, AppDesigner and WishStudio.
        for entry in AppVoiceStore.all() {
            let points = score(core, entry.phrase) + 4
            switch entry.kind {
            case .builder: consider(.builder(entry.name), points)
            case .designer: consider(.section("AppDesigner"), points)
            case .wish: consider(.section("WishStudio"), points)
            }
        }
        for collection in collections { consider(.collection(collection), score(core, collection)) }
        for site in sites where !site.title.isEmpty { consider(.site(site.title, site.url), score(core, site.title)) }

        if let best { return best.0 }
        if hadVerb {
            let apps = macApps.map { ($0, score(core, $0.0)) }.filter { $0.1 >= 78 }.max { $0.1 < $1.1 }
            if let apps { return .macApp(apps.0.1) }
        }
        return nil
    }
}
