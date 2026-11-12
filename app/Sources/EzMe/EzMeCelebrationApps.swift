// HBD and HWA: Happy Birthday and Happy Work Anniversary cards.
//
// Type  hbd-Rahul   or  hbd-<media shortcut>   (hwa-... for work anniversaries) in the shortcut popup.
// If the word after the dash is a shortcut with a picture attached, that picture is used on the card and
// the shortcut's name is written on it. Two versions of each app are installed:
//   hbd / hwa         AppBuilder: the AI makes a card image.
//   hbdweb / hwaweb   WishStudio: a card web page (HTML) is built on this Mac and its link is pasted.
import Foundation

// MARK: - Media shortcut lookup

/// A shortcut with at least one picture, found by its key or its name.
func celebrationMedia(_ value: String, clips: [Clip]) -> (name: String, paths: [String])? {
    let wanted = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/\\")).lowercased()
    guard !wanted.isEmpty else { return nil }
    let imageTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "gif"]
    for clip in clips {
        let key = clip.key.trimmingCharacters(in: CharacterSet(charactersIn: "/\\")).lowercased()
        guard key == wanted || clip.name.lowercased() == wanted else { continue }
        let pictures = clip.files.filter { path in
            FileManager.default.fileExists(atPath: path) && imageTypes.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
        }
        if pictures.isEmpty { continue }
        let shown = clip.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (shown.isEmpty ? value : shown, pictures)
    }
    return nil
}

// MARK: - Presets

private let birthdayImagePrompt = "Design a beautiful, colourful Happy Birthday greeting card as one square image. Write the headline \"Happy Birthday\" and the person's name (the Name variable) in large, elegant lettering, with one short warm wish underneath. If reference images are supplied, place that person's photo prominently in a tasteful frame and keep their face exactly as it is. Otherwise decorate with balloons, a cake and confetti. Use only the name given. Do not add any other names, dates or numbers."

private let anniversaryImagePrompt = "Design a polished, warm Happy Work Anniversary greeting card as one square image. Write the headline \"Happy Work Anniversary\" and the person's name (the Name variable) in large, elegant lettering, with one short line thanking them for their dedication underneath. If reference images are supplied, place that person's photo prominently in a tasteful frame and keep their face exactly as it is. Otherwise decorate with stars, a trophy and soft confetti. Use only the name given. Do not add any other names, dates or numbers."

let celebrationPresets: [AppBuilderPreset] = [
    AppBuilderPreset(name: "Birthday Card (HBD)", prefix: "hbd", prompt: birthdayImagePrompt, variables: "Name", sourceCollections: "", outputCollections: "Birthday Cards", template: "Modern",
                     details: "Joyful and warm. Spell the name exactly as given. Type hbd-Name, or hbd- and a media shortcut to use its picture.", format: "Image"),
    AppBuilderPreset(name: "Work Anniversary Card (HWA)", prefix: "hwa", prompt: anniversaryImagePrompt, variables: "Name", sourceCollections: "", outputCollections: "Work Anniversary Cards", template: "Modern",
                     details: "Professional and warm. Spell the name exactly as given. Type hwa-Name, or hwa- and a media shortcut to use its picture.", format: "Image"),
    AppBuilderPreset(name: "Birthday Web Card (HBD · WishStudio)", prefix: "hbdweb", prompt: "Happy Birthday card page made in WishStudio.", variables: "Name", sourceCollections: "", outputCollections: "Birthday Cards", template: "Modern",
                     details: "Builds a WishStudio card web page and pastes its link. Type hbdweb-Name, or hbdweb- and a media shortcut to use its picture.", format: "HTML", engine: "wish-birthday"),
    AppBuilderPreset(name: "Work Anniversary Web Card (HWA · WishStudio)", prefix: "hwaweb", prompt: "Happy Work Anniversary card page made in WishStudio.", variables: "Name", sourceCollections: "", outputCollections: "Work Anniversary Cards", template: "Modern",
                     details: "Builds a WishStudio card web page and pastes its link. Type hwaweb-Name, or hwaweb- and a media shortcut to use its picture.", format: "HTML", engine: "wish-anniversary"),
]

enum CelebrationApps {
    /// Installs the four apps once, so hbd-Name works without opening AppBuilder first.
    /// Returns the collections the apps save into, so the caller can create them.
    static func seedOnce() -> [String] {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "ezmeCelebrationApps.v1") else { return [] }
        var installed = (try? JSONDecoder().decode([String].self, from: Data((defaults.string(forKey: "ezmeCustomBuilderAppsJSON") ?? "[]").utf8))) ?? []
        var collections: [String] = []
        for preset in celebrationPresets {
            // Never take over a prefix the person already uses for something else.
            let taken = installed.contains { name in
                name.caseInsensitiveCompare(preset.name) != .orderedSame && (defaults.string(forKey: "ezmeBuilderPrefix." + name) ?? "").caseInsensitiveCompare(preset.prefix) == .orderedSame
            }
            if taken { continue }
            if !installed.contains(where: { $0.caseInsensitiveCompare(preset.name) == .orderedSame }) { installed.append(preset.name) }
            write(preset)
            collections.append(preset.outputCollections)
        }
        defaults.set(String(decoding: (try? JSONEncoder().encode(installed)) ?? Data("[]".utf8), as: UTF8.self), forKey: "ezmeCustomBuilderAppsJSON")
        defaults.set(true, forKey: "ezmeCelebrationApps.v1")
        return collections
    }

    /// The same settings the AppBuilder gallery writes when a preset is added.
    static func write(_ preset: AppBuilderPreset) {
        let defaults = UserDefaults.standard
        defaults.set(preset.prompt, forKey: "ezmeBuilderPrompt." + preset.name)
        defaults.set(preset.details, forKey: "ezmeBuilderDetails." + preset.name)
        defaults.set(preset.name + " · " + preset.details, forKey: "ezmeBuilderDescription." + preset.name)
        defaults.set(preset.prefix, forKey: "ezmeBuilderPrefix." + preset.name)
        defaults.set(preset.variables, forKey: "ezmeBuilderVariables." + preset.name)
        defaults.set(preset.sourceCollections, forKey: "ezmeBuilderCollections." + preset.name)
        defaults.set(preset.outputCollections, forKey: "ezmeBuilderOutputCollections." + preset.name)
        defaults.set(preset.template, forKey: "ezmeBuilderTemplate." + preset.name)
        defaults.set(preset.format, forKey: "ezmeBuilderFormat." + preset.name)
        defaults.set(preset.engine, forKey: "ezmeBuilderEngine." + preset.name)
    }
}

// MARK: - WishStudio card page

enum WishQuickOccasion: String {
    case birthday = "wish-birthday"
    case workAnniversary = "wish-anniversary"
}

enum WishQuickCard {
    /// Which WishStudio card an app makes, or nil for a normal AppBuilder app.
    static func occasion(forApp app: String) -> WishQuickOccasion? {
        WishQuickOccasion(rawValue: UserDefaults.standard.string(forKey: "ezmeBuilderEngine." + app) ?? "")
    }

    private static func field(_ key: String, _ label: String, _ type: WishFieldType, _ value: String, _ valueHi: String, universal: Bool = false) -> WishField {
        WishField(key: key, label: label, type: type, value: value, valueHi: valueHi, universal: universal)
    }

    /// The Work Anniversary app that is also added to WishStudio next to Happy Birthday.
    static func workAnniversaryApp() -> WishApp {
        var app = WishApp(name: "Work Anniversary", nameHi: "कार्य वर्षगांठ", tagline: "Say thank you", symbol: "trophy.fill", artwork: "trophy.fill", kind: .greeting,
                          prompt: "A work anniversary card for a team member, with their name and a short thank-you.")
        app.builtIn = true
        app.designID = "g-sky"
        app.fields = [
            field("eyebrow", "Top line", .text, "THANK YOU FOR BEING PART OF THE TEAM", "टीम का हिस्सा बनने के लिए धन्यवाद"),
            field("title", "Title", .text, "Happy Work Anniversary", "कार्य वर्षगांठ की शुभकामनाएँ"),
            field("name", "Name", .text, "Dear teammate", "प्रिय साथी"),
            field("message", "Message", .longText, "Thank you for your dedication, your ideas and your energy. Here is to many more years of doing great work together.", "आपके समर्पण, विचारों और ऊर्जा के लिए धन्यवाद। साथ मिलकर और भी वर्षों तक शानदार काम करने की शुभकामनाएँ।"),
            field("from", "From", .text, "With gratitude", "आभार सहित"),
            field("date", "Date", .date, "=Date", "=Date", universal: true),
        ]
        return app
    }

    /// Builds the card as a web page (index.html plus its picture) and returns the page's address.
    static func build(occasion: WishQuickOccasion, name: String, photo: String?, in directory: URL) throws -> URL {
        let app: WishApp
        let design: String
        switch occasion {
        case .birthday:
            app = WishSeeds.apps().first { $0.name == "Happy Birthday" } ?? WishSeeds.apps()[0]
            design = "g-blush"
        case .workAnniversary:
            app = workAnniversaryApp()
            design = "g-sky"
        }
        var card = WishCard.make(for: app, designID: app.designID ?? design)
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !who.isEmpty {
            card.values["name"] = who
            card.valuesHi["name"] = who
        }
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HHmmss"
        let safeName = who.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let folder = directory.appendingPathComponent("WishPages", isDirectory: true)
            .appendingPathComponent("\(app.name) \(safeName.isEmpty ? "card" : safeName) \(stamp.string(from: Date()))", isDirectory: true)
        let mediaFolder = folder.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
        if let photo {
            let source = URL(fileURLWithPath: photo)
            let file = "photo." + (source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased())
            try FileManager.default.copyItem(at: source, to: mediaFolder.appendingPathComponent(file))
            let kind = source.pathExtension.lowercased() == "gif" ? "gif" : "image"
            card.media = [WishMedia(file: file, kind: kind, placement: "hero")]
        }
        var context = WishContext()
        context.locale = card.language.locale
        for item in app.fields {
            context.variables[item.key.lowercased()] = WishFormula.render(card.value(for: item.key), context: context)
        }
        let layout = WishDesigns.design(id: card.designID, kind: .greeting)
        let json = WishHTML.stateJSON(app: app, card: card, design: layout, context: context, selected: nil) { file in "media/" + file }
        let index = folder.appendingPathComponent("index.html")
        try WishHTML.page(stateJSON: json, interactive: false).write(to: index, atomically: true, encoding: .utf8)
        return index
    }
}
