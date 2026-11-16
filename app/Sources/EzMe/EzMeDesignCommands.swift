// Published AppDesigner apps answer to the backslash popup like AppBuilder apps:
//   \hbd-rohit.media-pink     runs the app whose command word is hbd, with a picture from the shortcut rohit.media
// Parts can come in any order: pictures, wish shortcuts and collection items are recognised and put in the right box.
// When something is missing, the popup asks for it, and "Open the full form" opens the app's whole form.
import Foundation
import AppKit

@MainActor enum DesignCommands {
    private static let mapKey = "ezmeDesignCommandApps"
    private static let listKey = "ezmeCustomBuilderAppsJSON"

    // MARK: Command words

    static func sanitize(_ raw: String) -> String {
        var word = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "\\/ "))
        word = word.replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
        return String(word.prefix(12))
    }

    private static func builderApps() -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data((UserDefaults.standard.string(forKey: listKey) ?? "[]").utf8))) ?? []
    }

    private static func registered() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: mapKey) as? [String: String] ?? [:]   // design id -> builder app name
    }

    /// The command words already taken by other apps.
    private static func taken(except designID: String) -> Set<String> {
        var words = Set<String>()
        for app in builderApps() where designID(forApp: app) != designID {
            let prefix = UserDefaults.standard.string(forKey: "ezmeBuilderPrefix." + app) ?? String(app.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).prefix(12))
            words.insert(prefix.lowercased())
        }
        return words
    }

    /// One word to activate the app. The first word of its name unless the person chose another.
    static func word(for design: AppDesign) -> String {
        let chosen = sanitize(design.command ?? "")
        let base = chosen.isEmpty ? sanitize(String((design.appTitle ?? design.name).split(separator: " ").first ?? "app")) : chosen
        let start = base.isEmpty ? "app" : base
        let used = taken(except: design.id)
        var candidate = start, number = 2
        while used.contains(candidate) { candidate = String(start.prefix(10)) + String(number); number += 1 }
        return candidate
    }

    // MARK: The questions the command asks

    /// The boxes a command fills, in order. Boxes that already have a starting value are left to that value.
    static func slots(for design: AppDesign) -> [DesignField] {
        DesignFields.fields(for: design).filter { $0.defaultValue.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: Registering with the popup

    static func isDesignApp(_ app: String) -> Bool { registered().values.contains(app) }

    static func designID(forApp app: String) -> String? { registered().first(where: { $0.value == app })?.key }

    static func sync() {
        for design in AppDesignStore.shared.designs where design.version > 0 { register(design) }
    }

    @discardableResult static func register(_ design: AppDesign) -> String {
        let defaults = UserDefaults.standard
        var map = registered()
        var apps = builderApps()
        let wanted = design.appTitle ?? design.name
        // Keep one app name per design; a name used by a different AppBuilder app is not taken over.
        var name = wanted
        if apps.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }), map[design.id]?.caseInsensitiveCompare(name) != .orderedSame {
            name = wanted + " (design)"
        }
        if let old = map[design.id], old != name { remove(app: old, from: &apps) }
        if !apps.contains(name) { apps.append(name) }
        map[design.id] = name
        let word = word(for: design)
        let slotNames = slots(for: design).map { $0.label }
        defaults.set(word, forKey: "ezmeBuilderPrefix." + name)
        defaults.set("design:" + design.id, forKey: "ezmeBuilderPhotoTemplate." + name)
        defaults.set(slotNames.joined(separator: ","), forKey: "ezmeBuilderVariables." + name)
        defaults.set("", forKey: "ezmeBuilderCollections." + name)
        defaults.set(popupFormat(design), forKey: "ezmeBuilderFormat." + name)
        if let data = try? JSONEncoder().encode(apps) { defaults.set(String(decoding: data, as: UTF8.self), forKey: listKey) }
        defaults.set(map, forKey: mapKey)
        return word
    }

    static func unregister(designID: String) {
        var map = registered()
        guard let name = map[designID] else { return }
        var apps = builderApps()
        remove(app: name, from: &apps)
        map[designID] = nil
        if let data = try? JSONEncoder().encode(apps) { UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: listKey) }
        UserDefaults.standard.set(map, forKey: mapKey)
    }

    private static func remove(app: String, from apps: inout [String]) {
        apps.removeAll { $0 == app }
        let defaults = UserDefaults.standard
        for key in ["ezmeBuilderPrefix.", "ezmeBuilderPhotoTemplate.", "ezmeBuilderVariables.", "ezmeBuilderCollections.", "ezmeBuilderFormat."] { defaults.removeObject(forKey: key + app) }
    }

    private static func popupFormat(_ design: AppDesign) -> String {
        switch DesignFormat.from(design.outputFormat) ?? .png {
        case .png, .gif: return "Image"
        case .pdf, .docx: return "PDF"
        case .html: return "HTML"
        }
    }

    // MARK: Reading the command

    /// Puts each part of a typed command into the box it belongs to, whatever order it was typed in.
    static func arrange(_ raw: String) -> String {
        var command = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if command.first == "\\" || command.first == "/" { command.removeFirst() }
        let lower = command.lowercased()
        for (designID, app) in registered() {
            guard let design = AppDesignStore.shared.design(id: designID), design.version > 0 else { continue }
            let prefix = (UserDefaults.standard.string(forKey: "ezmeBuilderPrefix." + app) ?? "").lowercased()
            guard !prefix.isEmpty, lower.hasPrefix(prefix + "-") else { continue }
            let parts = splitBuilderCommand(String(command.dropFirst(prefix.count + 1)))
            let boxes = slots(for: design)
            guard !boxes.isEmpty, !parts.isEmpty else { return raw }
            var filled = [String?](repeating: nil, count: boxes.count)
            var used = Set<Int>()
            func take(_ kind: DesignField.Kind, where matches: (String, DesignField) -> Bool) {
                for (slot, box) in boxes.enumerated() where box.kind == kind && filled[slot] == nil {
                    if let part = parts.indices.first(where: { !used.contains($0) && matches(parts[$0], box) }) {
                        filled[slot] = parts[part]
                        used.insert(part)
                    }
                }
            }
            take(.image) { part, _ in celebrationMedia(part, clips: AppDesignContext.shared.clips) != nil }
            take(.wish) { part, box in WishPick.findStrict(part, in: box.collection ?? "") != nil }
            take(.choice) { part, box in
                DesignVoiceFill.options(for: box).contains { $0.name.caseInsensitiveCompare(part) == .orderedSame || $0.alias.caseInsensitiveCompare(part) == .orderedSame }
            }
            // Everything else goes to the text boxes, in the order typed.
            var rest = parts.indices.filter { !used.contains($0) }.map { parts[$0] }
            for (slot, box) in boxes.enumerated() where filled[slot] == nil && (box.kind == .text || box.kind == .long) && !rest.isEmpty {
                filled[slot] = rest.removeFirst()
            }
            for (slot, _) in boxes.enumerated() where filled[slot] == nil && !rest.isEmpty { filled[slot] = rest.removeFirst() }
            var last = filled.count - 1
            while last >= 0, filled[last] == nil { last -= 1 }
            let ordered = filled.prefix(last + 1).map { quoteBuilderValue($0 ?? "") }
            return prefix + "-" + (ordered + rest.map(quoteBuilderValue)).joined(separator: "-")
        }
        return raw
    }

    // MARK: The full form

    static func openForm(app: String, slotNames: [String], slotValues: [String]) {
        guard let id = designID(forApp: app), let design = AppDesignStore.shared.design(id: id) else { return }
        var start: [String: String] = [:]
        for (index, name) in slotNames.enumerated() where index < slotValues.count && !slotValues[index].isEmpty {
            start[TemplateFill.normal(name)] = slotValues[index]
        }
        AppLauncher.shared.open(design: design, prompt: "", values: start)
    }
}
