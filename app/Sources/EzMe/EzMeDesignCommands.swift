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
    private static func taken(except ownID: String) -> Set<String> {
        var words = Set<String>()
        for app in builderApps() where designID(forApp: app) != ownID {
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

    /// An app made in App Designer runs as soon as its name is typed. Only a box the maker marked mandatory can stop it.
    static func runnable(_ command: CustomBuilderCommand) -> Bool {
        guard isDesignApp(command.app) else { return false }
        for (index, name) in command.slotNames.enumerated() where field(app: command.app, label: name)?.required == true {
            if index >= command.slotValues.count || command.slotValues[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        }
        return true
    }

    /// Names of the other apps in the popup (not the one made from this design).
    static func otherAppNames(except designID: String) -> [String] {
        let own = registered()[designID]
        let designApps = Set(registered().values)
        return builderApps().filter { $0 != own && !designApps.contains($0) }
    }

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
        let command = word(for: design)
        let slotNames = slots(for: design).map { $0.label }
        defaults.set(command, forKey: "ezmeBuilderPrefix." + name)
        defaults.set("design:" + design.id, forKey: "ezmeBuilderPhotoTemplate." + name)
        defaults.set(slotNames.joined(separator: ","), forKey: "ezmeBuilderVariables." + name)
        defaults.set("", forKey: "ezmeBuilderCollections." + name)
        defaults.set(popupFormat(design), forKey: "ezmeBuilderFormat." + name)
        if let data = try? JSONEncoder().encode(apps) { defaults.set(String(decoding: data, as: UTF8.self), forKey: listKey) }
        defaults.set(map, forKey: mapKey)
        return command
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
        switch DesignDynamic.format(design) {
        case .png, .gif: return "Image"
        case .pdf, .docx: return "PDF"
        case .html: return "HTML"
        }
    }

    // MARK: Reading the command

    /// Puts each part of a typed command into the box it belongs to, whatever order it was typed in.
    /// "hbd rahul" runs like "hbd-rahul": the app word, then a space, works as the first dash.
    static func spaceToDash(_ command: String) -> String {
        let lower = command.lowercased()
        for (_, app) in registered() {
            let prefix = (UserDefaults.standard.string(forKey: "ezmeBuilderPrefix." + app) ?? "").lowercased()
            if !prefix.isEmpty, lower.hasPrefix(prefix + " ") {
                let rest = command.dropFirst(prefix.count + 1).trimmingCharacters(in: .whitespaces)
                return rest.isEmpty ? String(command.prefix(prefix.count)) : String(command.prefix(prefix.count)) + "-" + rest
            }
        }
        return command
    }

    static func arrange(_ raw: String) -> String {
        var command = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if command.first == "\\" || command.first == "/" { command.removeFirst() }
        let lower = command.lowercased()
        for (designID, app) in registered() {
            guard let design = AppDesignStore.shared.design(id: designID), design.version > 0 else { continue }
            let prefix = (UserDefaults.standard.string(forKey: "ezmeBuilderPrefix." + app) ?? "").lowercased()
            guard !prefix.isEmpty, lower.hasPrefix(prefix + "-") else { continue }
            var parts = splitBuilderCommand(String(command.dropFirst(prefix.count + 1)))
            // A trailing temp1, temp2, tempr or template name stays at the end; it is not a value for any box.
            var template = ""
            if let last = parts.last, DesignTemplates.isToken(last, design: design) { template = last; parts.removeLast() }
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
            // A collection named on its own (#birthday-wishes) means "pick from it": its first item is used.
            for (slot, box) in boxes.enumerated() where box.kind == .wish && filled[slot] == nil {
                let wanted = TemplateFill.normal(box.collection ?? "")
                guard !wanted.isEmpty, let part = parts.indices.first(where: { !used.contains($0) && TemplateFill.normal(parts[$0]) == wanted }),
                      let first = WishPick.clips(in: box.collection ?? "").first else { continue }
                filled[slot] = first.key.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
                used.insert(part)
            }
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
            return prefix + "-" + (ordered + rest.map(quoteBuilderValue)).joined(separator: "-") + (template.isEmpty ? "" : "-" + template)
        }
        return raw
    }

    // MARK: Templates and missing details

    /// True when the word is temp1, temp2, tempr or the name of one of this app's templates.
    static func isTemplateToken(_ word: String, app: String) -> Bool {
        guard let id = designID(forApp: app), let design = AppDesignStore.shared.design(id: id) else { return false }
        return DesignTemplates.isToken(word, design: design)
    }

    /// Fills the boxes a command left empty with the last value typed, or the first item of the collection, so the app never stops to ask.
    static func completed(app: String, names: [String], values: [String]) -> [String] {
        guard let id = designID(forApp: app), let design = AppDesignStore.shared.design(id: id) else { return values }
        let boxes = slots(for: design)
        let remembered = DesignMemory.last(id)
        var result = values
        for (index, name) in names.enumerated() where index < result.count && result[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let box = boxes.first(where: { $0.label == name }) else { continue }
            if let last = remembered[TemplateFill.normal(box.key)], !last.isEmpty { result[index] = last; continue }
            var one = [box.key: ""]
            DesignDefaults.fill([box], into: &one)
            if let first = one[box.key], !first.isEmpty { result[index] = first }
        }
        return result
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


extension DesignCommands {
    /// Renames an app (a released one keeps working: its run word follows the name unless the person chose their own).
    /// Returns the name that was saved and the run word, or nil when the app is missing.
    @discardableResult static func rename(designID: String, to name: String) -> (name: String, command: String)? {
        let designs = AppDesignStore.shared
        guard var current = designs.design(id: designID) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldName = current.appTitle ?? current.name
        guard !trimmed.isEmpty, trimmed != oldName else { return (oldName, current.command ?? word(for: current)) }
        let oldFirst = sanitize(String(oldName.split(separator: " ").first ?? ""))
        let followsName = current.command == nil || sanitize(current.command ?? "") == oldFirst
        let unique = DesignNames.unique(trimmed, taken: designs.designs.filter { $0.id != current.id }.map { $0.appTitle ?? $0.name })
        current.name = unique
        current.appTitle = unique
        if followsName { current.command = nil }
        designs.save(current)
        // The sentence commands and the run-by-itself choice stay with the app under its new name.
        let defaults = UserDefaults.standard
        for key in ["ezmeBuilderPhrases.", "ezmeBuilderVoiceAutoRun."] {
            if let value = defaults.object(forKey: key + oldName) { defaults.set(value, forKey: key + unique); defaults.removeObject(forKey: key + oldName) }
        }
        let command = current.version > 0 ? register(current) : word(for: current)
        return (unique, command)
    }
}
