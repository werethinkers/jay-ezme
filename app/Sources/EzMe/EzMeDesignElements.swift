// AppDesigner helpers: unique design names, a private copy of a design for each app that uses it, and the
// "elements" a box can hold (variable, function, dropdown of a collection) so they can be added by voice or one tap.
import Foundation

// MARK: - Unique names

enum DesignNames {
    /// "Diwali" taken gives "Diwali 2", then "Diwali 3".
    static func unique(_ wanted: String, taken: [String]) -> String {
        let trimmed = wanted.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = trimmed.isEmpty ? "Untitled" : trimmed
        func isTaken(_ name: String) -> Bool { taken.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
        if !isTaken(start) { return start }
        var number = 2
        while isTaken("\(start) \(number)") { number += 1 }
        return "\(start) \(number)"
    }
}

// MARK: - A copy of the design for each app

/// Sending a design or template to an existing app saves a new, uniquely named copy and links the app to that copy.
/// The app's own default look and the original design are never changed. Turning the app off restores its default.
@MainActor enum DesignSnapshots {
    private static func key(_ source: String, _ app: String) -> String { "ezmeSnapshot." + app + "." + source }

    static func exists(_ link: String) -> Bool {
        if let id = TemplateLinks.designID(link) { return AppDesignStore.shared.design(id: id) != nil }
        return TemplateStore.shared.template(id: link) != nil
    }

    /// The copy this app already has of the source, if it still exists.
    static func existingCopy(of source: String, app: String) -> String? {
        guard let link = UserDefaults.standard.string(forKey: key(source, app)), exists(link) else { return nil }
        return link
    }

    /// True when the app currently uses the source or the copy made from it.
    static func isLinked(current: String, to source: String, app: String) -> Bool {
        guard !current.isEmpty else { return false }
        return current == source || current == existingCopy(of: source, app: app)
    }

    /// The link to give the app: its earlier copy, or a new copy.
    static func makeCopy(of source: String, app: String, appName: String) -> String? {
        if let have = existingCopy(of: source, app: app) { return have }
        var link: String?
        if let design = TemplateLinks.design(source) {
            link = copyDesign(design, appName: appName)
        } else if let template = TemplateStore.shared.template(id: source) {
            link = copyTemplate(template, appName: appName)
        }
        if let link { UserDefaults.standard.set(link, forKey: key(source, app)) }
        return link
    }

    private static func copyTemplate(_ template: ImageTemplate, appName: String) -> String? {
        guard var copy = TemplateStore.shared.duplicate(template.id) else { return nil }
        copy.name = DesignNames.unique("\(template.name) for \(appName)", taken: TemplateStore.shared.templates.map { $0.name })
        TemplateStore.shared.save(copy)
        return copy.id
    }

    private static func copyDesign(_ design: AppDesign, appName: String) -> String? {
        let store = AppDesignStore.shared
        var made = AppDesign(name: DesignNames.unique("\(design.name) for \(appName)", taken: store.designs.map { $0.name }))
        made.variables = design.variables
        made.outputFormat = design.outputFormat
        made.appTitle = made.name
        for (number, source) in store.activePages(design).enumerated() {
            guard var page = TemplateStore.shared.duplicate(source.id) else { continue }
            page.designID = made.id
            page.name = "\(made.name) page \(number + 1)"
            TemplateStore.shared.save(page)
            made.pages.append(page.id)
        }
        guard !made.pages.isEmpty else { return nil }
        store.save(made)
        return "design:" + made.id
    }
}

// MARK: - Elements

enum DesignElementTokens {
    /// Functions offered by the Function button. They are the same ones the voice command "put function date" uses.
    struct Function: Identifiable {
        var title: String
        var token: String
        var id: String { title }
    }

    static let functions: [Function] = [
        Function(title: "Today's date", token: "{=TODAY()}"), Function(title: "Date + 7 days", token: "{=Date+7}"),
        Function(title: "Time", token: "{=time}"), Function(title: "Date and time", token: "{=now}"),
        Function(title: "Month", token: "{=month}"), Function(title: "Year", token: "{=year}"),
        Function(title: "Day of week", token: "{=weekday}")
    ]

    /// A name for a new box made from a token: the variable, the collection, or "function".
    static func boxName(_ token: String) -> String {
        let inner = token.replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "").trimmingCharacters(in: .whitespaces)
        if inner.hasPrefix("{=") || inner.hasPrefix("=") { return "function" }
        if inner.lowercased().hasPrefix("wish:") {
            let rest = String(inner.dropFirst("wish:".count))
            return rest.split(separator: "/").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "choice"
        }
        if inner.hasPrefix("@") {
            let parts = String(inner.dropFirst()).split(separator: "/").map { String($0) }
            if parts.count > 1 { return parts[1].replacingOccurrences(of: "$", with: "") }
            return parts.first ?? "choice"
        }
        if inner.lowercased().hasPrefix("shortcut:") { return "shortcut" }
        return inner.isEmpty ? "text" : inner
    }

    /// The name of a plain variable token such as {{company}}, or nil for functions, collections and shortcuts.
    static func plainVariable(_ token: String) -> String? {
        let inner = token.replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "").trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty, !inner.contains(":"), !inner.contains("@"), !inner.contains("="), !inner.contains("/") else { return nil }
        guard token.hasPrefix("{{"), token.hasSuffix("}}") else { return nil }
        return inner
    }

    /// A spoken "dropdown of <name>" becomes a shortcut collection pick-list, unless the name is a collection of people,
    /// companies or other records (no shortcuts in it), which becomes a pick-list of those records.
    @MainActor static func refine(_ token: String) -> String {
        let inner = token.replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "")
        guard inner.lowercased().hasPrefix("wish:"), !inner.contains("/") else { return token }
        let said = String(inner.dropFirst("wish:".count)).trimmingCharacters(in: .whitespaces)
        let name = WishPick.canonicalCollection(said)
        let hasRecords = AppDesignContext.shared.records.contains { $0.collection.caseInsensitiveCompare(name) == .orderedSame }
        if WishPick.clips(in: name).isEmpty, hasRecords { return "{{@\(name)/$\(TemplateFill.normal(name))}}" }
        return token
    }
}

extension DesignElementTokens {
    /// "{{wish:Birthday photos}}" for a collection that holds pictures or videos gives that collection's name.
    @MainActor static func mediaCollection(in token: String) -> String? {
        let inner = token.replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "")
        guard inner.lowercased().hasPrefix("wish:") else { return nil }
        let rest = String(inner.dropFirst("wish:".count))
        let said = (rest.split(separator: "/").first.map(String.init) ?? rest).trimmingCharacters(in: .whitespaces)
        let name = WishPick.canonicalCollection(said)
        return MediaFinder.isMediaCollection(name) ? name : nil
    }
}

// MARK: - Examples of what to say or type

/// Ready-made lines for running an app: one full sentence, one short one, and the typed form.
@MainActor enum DesignExamples {
    struct Line: Identifiable {
        var label: String
        var text: String
        var id: String { label + text }
    }

    private static func sample(for field: DesignField) -> String? {
        let key = (field.key + " " + field.label).lowercased()
        switch field.kind {
        case .wish: return WishPick.clips(in: field.collection ?? "").first?.key
        case .image: return MediaFinder.search("", in: field.collection, limit: 1).first?.key
        case .choice:
            let record = AppDesignContext.shared.records.first { $0.collection.caseInsensitiveCompare(field.collection ?? "") == .orderedSame }
            return record.map { $0.alias.isEmpty ? $0.name : $0.alias }
        case .text, .long:
            if key.contains("date") || key.contains("time") { return nil }
            if key.contains("company") || key.contains("firm") { return "Acme Ltd" }
            if key.contains("amount") || key.contains("price") || key.contains("total") { return "5000" }
            if key.contains("city") { return "Pune" }
            return "Rahul"
        }
    }

    static func lines(appName: String, word: String, fields: [DesignField]) -> [Line] {
        guard !fields.isEmpty else { return [] }
        var spoken: [String] = []
        var typed: [String] = []
        for field in fields.prefix(4) {
            guard let value = sample(for: field) else { continue }
            let plain = value.trimmingCharacters(in: CharacterSet(charactersIn: "\\/"))
            switch field.kind {
            case .wish: spoken.append("with wish \(plain)")
            case .image: spoken.append("with photo \(plain)")
            default: spoken.append("for \(value)")
            }
            if !plain.contains("-") { typed.append(plain) }
        }
        var result = [Line(label: "Say", text: "Make \(appName)" + (spoken.isEmpty ? "" : " " + spoken.joined(separator: " ")))]
        result.append(Line(label: "Short", text: "Make \(appName)"))
        if !word.isEmpty { result.append(Line(label: "Type", text: "\\\(word)-" + typed.joined(separator: "-"))) }
        return result
    }
}
