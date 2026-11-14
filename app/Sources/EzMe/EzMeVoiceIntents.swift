// Spoken forms for collections, shortcuts and live functions in the popup.
//
//   "hashtag birthday"            pick the collection called Birthday (or search a shortcut with that name)
//   "hash media files rahul"      collection Media files, then search "rahul" inside it
//   "run collection birthday"     same as the hashtag form
//   "run shortcut rahul address"  find that shortcut and paste it
//   "run rahul address"           the same, when no app has that name
//   "insert function date"        paste today's date ("insert date" works too)
//   "all collections"             search everywhere again
import Foundation

enum VoiceIntents {
    struct Result {
        var collection: String? = nil
        var allCollections = false
        var query = ""
        var runs = false
        var function: LiveValueInfo? = nil
        var label = ""
    }

    private static let lead: Set<String> = ["please", "now", "hey", "keydo", "can", "you", "just", "kindly", "ok", "okay"]
    private static let tagWords: [[String]] = [["hash", "tag"], ["hashtag"], ["hash", "sign"], ["number", "sign"], ["pound", "sign"], ["pound"], ["hash"], ["hashes"]]
    private static let runVerbs: Set<String> = ["run", "use", "select", "pick", "execute"]
    private static let insertVerbs: Set<String> = ["insert", "add", "type", "paste", "put"]
    private static let collectionNouns: Set<String> = ["collection", "collections", "group", "folder", "category"]
    private static let shortcutNouns: Set<String> = ["shortcut", "shortcuts", "snippet", "phrase"]
    private static let functionNouns: Set<String> = ["function", "functions", "value", "live", "variable"]

    private static func words(_ text: String) -> [String] {
        var text = text.lowercased()
        text = text.replacingOccurrences(of: "#", with: " hashtag ")
        let keep = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'"))
        return text.components(separatedBy: keep.inverted).filter { !$0.isEmpty }
    }

    private static func squash(_ words: [String]) -> String { words.joined() }

    /// The collection whose name starts the words (the longest one), and how many words it used.
    private static func matchCollection(_ rest: [String], _ collections: [String]) -> (String, Int)? {
        var best: (String, Int)?
        for name in collections {
            let parts = words(name)
            guard !parts.isEmpty, parts.count <= rest.count else { continue }
            if Array(rest[0..<parts.count]) == parts || squash(Array(rest[0..<parts.count])) == squash(parts) {
                if best == nil || parts.count > best!.1 { best = (name, parts.count) }
            }
        }
        if best != nil { return best }
        // A single word that begins one collection name, when it is unique ("birthday" for "Birthday wishes").
        if let first = rest.first, first.count >= 4 {
            let hits = collections.filter { words($0).first?.hasPrefix(first) == true }
            if hits.count == 1 { return (hits[0], 1) }
        }
        return nil
    }

    private static func matchFunction(_ rest: [String]) -> LiveValueInfo? {
        let drop: Set<String> = ["the", "current", "todays", "today's", "of", "a", "my", "now"]
        var core = rest.filter { !drop.contains($0) }
        if core.isEmpty { core = rest }
        guard !core.isEmpty else { return nil }
        let joined = core.joined(separator: " ")
        let tight = squash(core)
        func inner(_ info: LiveValueInfo) -> String { info.token.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "").lowercased() }
        if let exact = LiveValues.catalog.first(where: { inner($0) == tight || inner($0) == joined }) { return exact }
        if core == ["day", "of", "week"] || joined == "week day" { return LiveValues.catalog.first { inner($0) == "weekday" } }
        return LiveValues.catalog.first { info in
            let summary = info.summary.lowercased()
            return core.allSatisfy { summary.contains($0) }
        }
    }

    /// Reads a spoken phrase. Nil means it is none of the above, so the words are just a search.
    static func resolve(_ spoken: String, collections: [String]) -> Result? {
        var w = words(spoken)
        while let first = w.first, lead.contains(first) { w.removeFirst() }
        guard !w.isEmpty else { return nil }

        if w.count >= 2, w[0] == "all" || w[0] == "every", collectionNouns.contains(w[1]) {
            return Result(allCollections: true, query: w.dropFirst(2).joined(separator: " "), label: "All collections")
        }

        // Hashtag forms: "hashtag birthday"
        for tag in tagWords where w.count > tag.count && Array(w[0..<tag.count]) == tag {
            let rest = Array(w[tag.count...])
            if let (name, used) = matchCollection(rest, collections) {
                return Result(collection: name, query: rest.dropFirst(used).joined(separator: " "), label: "# " + name)
            }
            return Result(query: rest.joined(separator: " "), label: "# " + rest.joined(separator: " "))
        }

        var index = 0
        var ran = false
        if runVerbs.contains(w[0]) { ran = true; index = 1 } else if insertVerbs.contains(w[0]) { index = 1 } else if collectionNouns.contains(w[0]) || shortcutNouns.contains(w[0]) || functionNouns.contains(w[0]) {
            index = 0
        } else {
            return nil
        }
        let inserting = index == 1 && insertVerbs.contains(w[0])
        guard index < w.count else { return nil }
        var kind = ""
        if collectionNouns.contains(w[index]) { kind = "collection"; index += 1 }
        else if shortcutNouns.contains(w[index]) { kind = "shortcut"; index += 1 }
        else if functionNouns.contains(w[index]) { kind = "function"; index += 1; if index < w.count, w[index] == "value" || w[index] == "values" { index += 1 } }
        if index < w.count, ["called", "named", "for", "of", "the"].contains(w[index]), kind != "function" || w[index] != "of" { index += 1 }
        let rest = Array(w[index...])
        if rest.isEmpty { return nil }

        switch kind {
        case "collection":
            if let (name, used) = matchCollection(rest, collections) {
                return Result(collection: name, query: rest.dropFirst(used).joined(separator: " "), label: "# " + name)
            }
            return Result(query: rest.joined(separator: " "), label: "Collection \(rest.joined(separator: " ")) not found")
        case "shortcut":
            return Result(query: rest.joined(separator: " "), runs: true, label: "Run " + rest.joined(separator: " "))
        case "function":
            if let info = matchFunction(rest) { return Result(runs: true, function: info, label: "Insert " + info.summary) }
            return Result(query: "", label: "No function called \(rest.joined(separator: " "))")
        default:
            if inserting || ran, let info = matchFunction(rest), rest.count <= 4 {
                return Result(runs: true, function: info, label: "Insert " + info.summary)
            }
            if ran, rest.count >= 1 {
                if let (name, used) = matchCollection(rest, collections), used == rest.count {
                    return Result(collection: name, label: "# " + name)
                }
                return Result(query: rest.joined(separator: " "), runs: true, label: "Run " + rest.joined(separator: " "))
            }
            if inserting { return Result(query: rest.joined(separator: " "), runs: true, label: "Insert " + rest.joined(separator: " ")) }
            return nil
        }
    }
}
