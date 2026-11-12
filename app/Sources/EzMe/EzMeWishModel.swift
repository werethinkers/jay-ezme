// WishStudio data: the apps WishBuilder defines, the cards made from them, designs, and saving.
import Foundation
import SwiftUI

// MARK: - Basic types

enum WishKind: String, Codable, CaseIterable, Hashable {
    case greeting
    case infographic

    var title: String {
        switch self {
        case .greeting: return "Greeting card"
        case .infographic: return "Infographic"
        }
    }
}

enum WishLanguage: String, Codable, CaseIterable, Hashable {
    case english
    case hindi

    var title: String { return self == .english ? "English" : "\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}" }
    var locale: Locale { return Locale(identifier: self == .english ? "en_US" : "hi_IN") }
    var speechIdentifier: String { return self == .english ? "en-IN" : "hi-IN" }
}

enum WishFieldType: String, Codable, CaseIterable, Hashable {
    case text
    case longText
    case date
    case number
    case list

    var title: String {
        switch self {
        case .text: return "Short text"
        case .longText: return "Long text"
        case .date: return "Date"
        case .number: return "Number"
        case .list: return "List (one per line)"
        }
    }
}

enum WishFontStyle: String, Codable, CaseIterable, Hashable {
    case classic
    case modern
    case romantic

    var title: String {
        switch self {
        case .classic: return "Classic serif"
        case .modern: return "Modern sans"
        case .romantic: return "Romantic italic"
        }
    }
}

enum WishCommandGroup {
    static let allNames = ["Fields", "Collections", "Colors", "Text", "Design", "Language", "Magic", "Output"]
}

// MARK: - Apps (what WishBuilder defines)

struct WishField: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    /// The name used in functions, like =name or FIELD("name").
    var key: String
    var label: String
    var labelHi: String = ""
    var type: WishFieldType = .text
    var value: String = ""
    var valueHi: String = ""
    /// A name or a date is the same in every language, so changing it in one changes both.
    var universal: Bool = false
    var placeholder: String = ""
}

/// Shows values from one of the user's EzMe collections as tappable chips for a field.
struct WishCollectionLink: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var collection: String
    var fieldKey: String
    /// false: use the record names; true: use the shortcut text.
    var useShortcutText: Bool = false
}

struct WishLiveSettings: Codable, Hashable {
    /// "card" follows the card language, otherwise "english" or "hindi".
    var recognition: String = "card"
    /// How long speech must pause before the command is applied.
    var commitDelay: Double = 0.9
    /// How long a tapped element stays selected.
    var selectionSeconds: Double = 5
    var enabledGroups: [String] = WishCommandGroup.allNames
}

struct WishApp: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var nameHi: String = ""
    var tagline: String = ""
    var symbol: String = "sparkles"
    var artwork: String = "sparkles"
    var kind: WishKind = .greeting
    var prompt: String = ""
    var defaultLanguage: WishLanguage = .english
    var fields: [WishField] = []
    var links: [WishCollectionLink] = []
    var live: WishLiveSettings = WishLiveSettings()
    var builtIn: Bool = false
    /// File name (inside WishMedia) of the picture, GIF or video shown on the cover page and tab.
    var coverFile: String? = nil
    /// Which part of the cover shows, its zoom and where a cover video starts.
    var coverFraming: WishFraming? = nil
    /// The design a new card of this app starts with.
    var designID: String? = nil

    func title(_ language: WishLanguage) -> String {
        if language == .hindi && !nameHi.isEmpty { return nameHi }
        return name
    }

    func field(_ key: String) -> WishField? {
        return fields.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }
    }
}

/// A global function the user defines, like Hello = GREETING() or Tomorrow = Date+1.
struct WishFunction: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var expression: String
    var note: String = ""
}

/// A picture, GIF or video shown on a card. The file lives in the WishMedia folder.
/// How a picture, GIF or video sits in its box: which part shows, how far it is zoomed, and where a video starts.
/// Videos always play at most 10 seconds from `start`, then loop.
struct WishFraming: Codable, Hashable {
    var x: Double? = nil
    var y: Double? = nil
    var zoom: Double? = nil
    var start: Double? = nil

    static let maxSeconds: Double = 10

    func px() -> Double { return min(1, max(0, x ?? 0.5)) }
    /// A video starts from the top unless moved; pictures and GIFs stay centred.
    func py(video: Bool) -> Double { return min(1, max(0, y ?? (video ? 0 : 0.5))) }
    func pz() -> Double { return min(3, max(1, zoom ?? 1)) }
    func ps() -> Double { return max(0, start ?? 0) }
}

struct WishMedia: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var file: String
    /// "image", "gif" or "video"
    var kind: String
    /// "hero" (where the artwork sits) or "background"
    var placement: String
    var framing: WishFraming? = nil
}

/// A saved look (and optionally the text) that can be applied to a card of the same app.
struct WishTemplate: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var appID: String
    var designID: String
    var backgroundHex: String? = nil
    var accentHex: String? = nil
    var inkHex: String? = nil
    var fontStyle: WishFontStyle = .classic
    var textScale: Double = 1
    var magic: Int = 2
    var artwork: String = "sparkles"
    var values: [String: String]? = nil
    var valuesHi: [String: String]? = nil
}

// MARK: - Cards (what is being edited)

struct WishElementStyle: Codable, Equatable {
    var colorHex: String? = nil
    var scale: Double = 1
    var dx: Double = 0
    var dy: Double = 0
    var bold: Bool? = nil
    var italic: Bool? = nil
    var hidden: Bool = false
}

struct WishCard: Codable, Equatable {
    var appID: String
    var designID: String
    var language: WishLanguage = .english
    var values: [String: String] = [:]
    var valuesHi: [String: String] = [:]
    var backgroundHex: String? = nil
    var accentHex: String? = nil
    var textScale: Double = 1
    var fontStyle: WishFontStyle = .classic
    var magic: Int = 2
    var artwork: String = "sparkles"
    var styles: [String: WishElementStyle] = [:]
    var inkHex: String? = nil
    var media: [WishMedia]? = nil

    func value(for key: String) -> String {
        if language == .hindi {
            return valuesHi[key] ?? values[key] ?? ""
        }
        return values[key] ?? ""
    }

    mutating func set(_ key: String, to value: String, universal: Bool) {
        if language == .hindi {
            valuesHi[key] = value
            if universal { values[key] = value }
        } else {
            values[key] = value
            if universal { valuesHi[key] = value }
        }
    }

    static func make(for app: WishApp, designID: String) -> WishCard {
        var card = WishCard(appID: app.id, designID: designID)
        card.language = app.defaultLanguage
        card.artwork = app.artwork
        for field in app.fields {
            card.values[field.key] = field.value
            card.valuesHi[field.key] = field.valueHi.isEmpty ? field.value : field.valueHi
        }
        return card
    }
}

// MARK: - Designs

struct WishDesign: Identifiable, Hashable {
    let id: String
    let name: String
    let background: String
    let accent: String
    let ink: String
    /// Greeting layouts: frame, arch, band. Infographic layouts: circles, table, bars, donut, flow, grid, timeline, ranked.
    let layout: String
}

enum WishDesigns {
    static let greeting: [WishDesign] = [
        WishDesign(id: "g-lavender", name: "Lavender wishes", background: "#EFE6FA", accent: "#7B52B8", ink: "#2B1E45", layout: "frame"),
        WishDesign(id: "g-blush", name: "Blush & balloons", background: "#FBE3E6", accent: "#D9577A", ink: "#4A1F2C", layout: "arch"),
        WishDesign(id: "g-mint", name: "Mint garden", background: "#E0F3E8", accent: "#2E9467", ink: "#173D2B", layout: "band"),
        WishDesign(id: "g-sky", name: "Soft sky", background: "#E3EEFB", accent: "#3B6FD6", ink: "#1B2C52", layout: "frame"),
        WishDesign(id: "g-gold", name: "Golden hour", background: "#FBF0D5", accent: "#B98A12", ink: "#463408", layout: "arch"),
        WishDesign(id: "g-peach", name: "Peach glow", background: "#FFE7DA", accent: "#E2703A", ink: "#4F2410", layout: "band"),
        WishDesign(id: "g-rose", name: "Rose petal", background: "#F8DDE8", accent: "#B83A72", ink: "#47182F", layout: "frame"),
        WishDesign(id: "g-sage", name: "Sage calm", background: "#E6EDDD", accent: "#6B8F4E", ink: "#26361A", layout: "arch"),
        WishDesign(id: "g-night", name: "Midnight", background: "#1F1B3A", accent: "#F2C45A", ink: "#F6F1FF", layout: "frame"),
        WishDesign(id: "g-coral", name: "Coral sunrise", background: "#FFE1D6", accent: "#E5584A", ink: "#4D1D17", layout: "band"),
        WishDesign(id: "g-ink", name: "Ink & ivory", background: "#F7F2E8", accent: "#2D2A26", ink: "#1F1D1A", layout: "arch"),
        WishDesign(id: "g-saffron", name: "Saffron festival", background: "#FFEDCC", accent: "#E67E00", ink: "#4A2A00", layout: "frame"),
    ]

    static let infographic: [WishDesign] = [
        WishDesign(id: "i-circles", name: "Circle cluster", background: "#EFE6FA", accent: "#7B52B8", ink: "#2B1E45", layout: "circles"),
        WishDesign(id: "i-table", name: "Clean table", background: "#E8F3EC", accent: "#2E9467", ink: "#173D2B", layout: "table"),
        WishDesign(id: "i-bars", name: "Bar chart", background: "#E3EEFB", accent: "#3B6FD6", ink: "#1B2C52", layout: "bars"),
        WishDesign(id: "i-donut", name: "Donut chart", background: "#FBE3E6", accent: "#D9577A", ink: "#4A1F2C", layout: "donut"),
        WishDesign(id: "i-flow", name: "Flow steps", background: "#FBF0D5", accent: "#B98A12", ink: "#463408", layout: "flow"),
        WishDesign(id: "i-grid", name: "Card grid", background: "#FFE7DA", accent: "#E2703A", ink: "#4F2410", layout: "grid"),
        WishDesign(id: "i-timeline", name: "Timeline", background: "#E6EDDD", accent: "#6B8F4E", ink: "#26361A", layout: "timeline"),
        WishDesign(id: "i-ranked", name: "Ranked list", background: "#1F1B3A", accent: "#F2C45A", ink: "#F6F1FF", layout: "ranked"),
    ]

    static func designs(for kind: WishKind) -> [WishDesign] {
        return kind == .greeting ? greeting : infographic
    }

    static func design(id: String, kind: WishKind) -> WishDesign {
        let list = designs(for: kind)
        return list.first { $0.id == id } ?? list[0]
    }
}

enum WishArtwork {
    static let choices: [(name: String, symbol: String)] = [
        ("Cake", "birthday.cake.fill"), ("Balloon", "balloon.fill"), ("Gift", "gift.fill"), ("Heart", "heart.fill"),
        ("Diya", "flame.fill"), ("Stars", "sparkles"), ("Crown", "crown.fill"), ("Flower", "camera.macro"),
        ("Moon", "moon.stars.fill"), ("Clap", "hands.clap.fill"), ("Star", "star.fill"), ("Leaf", "leaf.fill"),
        ("Bell", "bell.fill"), ("Music", "music.note"), ("Sun", "sun.max.fill"), ("Trophy", "trophy.fill"),
    ]
}

extension WishArtwork {
    /// The web page cannot draw SF Symbols, so each artwork has an emoji twin.
    static func emoji(_ symbol: String) -> String {
        switch symbol {
        case "birthday.cake.fill": return "\u{1F382}"
        case "balloon.fill": return "\u{1F388}"
        case "gift.fill": return "\u{1F381}"
        case "heart.fill": return "\u{2764}\u{FE0F}"
        case "flame.fill": return "\u{1FA94}"
        case "sparkles": return "\u{2728}"
        case "crown.fill": return "\u{1F451}"
        case "camera.macro": return "\u{1F338}"
        case "moon.stars.fill": return "\u{1F319}"
        case "hands.clap.fill": return "\u{1F44F}"
        case "star.fill": return "\u{2B50}"
        case "leaf.fill": return "\u{1F343}"
        case "bell.fill": return "\u{1F514}"
        case "music.note": return "\u{1F3B5}"
        case "sun.max.fill": return "\u{2600}\u{FE0F}"
        case "trophy.fill": return "\u{1F3C6}"
        case "chart.pie.fill": return "\u{1F4CA}"
        default: return "\u{2728}"
        }
    }
}

// MARK: - Starter apps

enum WishSeeds {
    private static func field(_ key: String, _ label: String, _ labelHi: String, _ type: WishFieldType, _ value: String, _ valueHi: String, universal: Bool = false) -> WishField {
        return WishField(key: key, label: label, labelHi: labelHi, type: type, value: value, valueHi: valueHi, universal: universal)
    }

    private static func greeting(name: String, nameHi: String, tagline: String, symbol: String, prompt: String, designID: String, eyebrow: (String, String), title: (String, String), who: (String, String), message: (String, String), from: (String, String)) -> WishApp {
        var app = WishApp(name: name, nameHi: nameHi, tagline: tagline, symbol: symbol, artwork: symbol, kind: .greeting, prompt: prompt)
        app.builtIn = true
        app.designID = designID
        app.fields = [
            field("eyebrow", "Top line", "\u{090A}\u{092A}\u{0930} \u{0915}\u{0940} \u{092A}\u{0902}\u{0915}\u{094D}\u{0924}\u{093F}", .text, eyebrow.0, eyebrow.1),
            field("title", "Title", "\u{0936}\u{0940}\u{0930}\u{094D}\u{0937}\u{0915}", .text, title.0, title.1),
            field("name", "Name", "\u{0928}\u{093E}\u{092E}", .text, who.0, who.1),
            field("message", "Message", "\u{0938}\u{0902}\u{0926}\u{0947}\u{0936}", .longText, message.0, message.1),
            field("from", "From", "\u{0915}\u{0940} \u{0913}\u{0930} \u{0938}\u{0947}", .text, from.0, from.1),
            field("date", "Date", "\u{0924}\u{093E}\u{0930}\u{0940}\u{0916}", .date, "=Date", "=Date", universal: true),
        ]
        return app
    }

    static func apps() -> [WishApp] {
        let birthday = greeting(
            name: "Happy Birthday", nameHi: "\u{091C}\u{0928}\u{094D}\u{092E}\u{0926}\u{093F}\u{0928}", tagline: "Make a wish", symbol: "birthday.cake.fill",
            prompt: "A birthday card with a name, a warm message and who it is from.", designID: "g-blush",
            eyebrow: ("TODAY IS ALL ABOUT YOU", "\u{0906}\u{091C} \u{0915}\u{093E} \u{0926}\u{093F}\u{0928} \u{0938}\u{093F}\u{0930}\u{094D}\u{092B} \u{0906}\u{092A}\u{0915}\u{093E}"),
            title: ("Happy Birthday", "\u{091C}\u{0928}\u{094D}\u{092E}\u{0926}\u{093F}\u{0928} \u{092E}\u{0941}\u{092C}\u{093E}\u{0930}\u{0915}"),
            who: ("Dear friend", "\u{092A}\u{094D}\u{0930}\u{093F}\u{092F} \u{092E}\u{093F}\u{0924}\u{094D}\u{0930}"),
            message: ("May your day be filled with laughter, love and every little thing that makes you smile.", "\u{0906}\u{092A}\u{0915}\u{093E} \u{0926}\u{093F}\u{0928} \u{0939}\u{0901}\u{0938}\u{0940}, \u{092A}\u{094D}\u{092F}\u{093E}\u{0930} \u{0914}\u{0930} \u{091B}\u{094B}\u{091F}\u{0940}-\u{091B}\u{094B}\u{091F}\u{0940} \u{0916}\u{0941}\u{0936}\u{093F}\u{092F}\u{094B}\u{0902} \u{0938}\u{0947} \u{092D}\u{0930}\u{093E} \u{0930}\u{0939}\u{0947}\u{0964}"),
            from: ("With love", "\u{092A}\u{094D}\u{092F}\u{093E}\u{0930} \u{0915}\u{0947} \u{0938}\u{093E}\u{0925}"))
        let anniversary = greeting(
            name: "Happy Anniversary", nameHi: "\u{0938}\u{093E}\u{0932}\u{0917}\u{093F}\u{0930}\u{0939}", tagline: "Celebrate your story", symbol: "heart.fill",
            prompt: "An anniversary card for a couple, with their names and a loving message.", designID: "g-rose",
            eyebrow: ("TWO HEARTS, ONE STORY", "\u{0926}\u{094B} \u{0926}\u{093F}\u{0932}, \u{090F}\u{0915} \u{0915}\u{0939}\u{093E}\u{0928}\u{0940}"),
            title: ("Happy Anniversary", "\u{0938}\u{093E}\u{0932}\u{0917}\u{093F}\u{0930}\u{0939} \u{092E}\u{0941}\u{092C}\u{093E}\u{0930}\u{0915}"),
            who: ("Priya & Rahul", "\u{092A}\u{094D}\u{0930}\u{093F}\u{092F}\u{093E} \u{0914}\u{0930} \u{0930}\u{093E}\u{0939}\u{0941}\u{0932}"),
            message: ("Here is to the love you share and every beautiful year still ahead.", "\u{0906}\u{092A}\u{0915}\u{0947} \u{092A}\u{094D}\u{092F}\u{093E}\u{0930} \u{0914}\u{0930} \u{0906}\u{0928}\u{0947} \u{0935}\u{093E}\u{0932}\u{0947} \u{0939}\u{0930} \u{0916}\u{0942}\u{092C}\u{0938}\u{0942}\u{0930}\u{0924} \u{0938}\u{093E}\u{0932} \u{0915}\u{0947} \u{0928}\u{093E}\u{092E}\u{0964}"),
            from: ("Warmly", "\u{0936}\u{0941}\u{092D}\u{0915}\u{093E}\u{092E}\u{0928}\u{093E}\u{0913}\u{0902} \u{0938}\u{0939}\u{093F}\u{0924}"))
        let diwali = greeting(
            name: "Happy Diwali", nameHi: "\u{0926}\u{093F}\u{0935}\u{093E}\u{0932}\u{0940}", tagline: "Send a little light", symbol: "flame.fill",
            prompt: "A Diwali greeting for a family, with blessings for the year ahead.", designID: "g-saffron",
            eyebrow: ("A FESTIVAL OF LIGHT", "\u{0930}\u{094B}\u{0936}\u{0928}\u{0940} \u{0915}\u{093E} \u{0924}\u{094D}\u{092F}\u{094B}\u{0939}\u{093E}\u{0930}"),
            title: ("Happy Diwali", "\u{0926}\u{0940}\u{092A}\u{093E}\u{0935}\u{0932}\u{0940} \u{0915}\u{0940} \u{0936}\u{0941}\u{092D}\u{0915}\u{093E}\u{092E}\u{0928}\u{093E}\u{090F}\u{0901}"),
            who: ("To you and your family", "\u{0906}\u{092A}\u{0915}\u{094B} \u{0914}\u{0930} \u{0906}\u{092A}\u{0915}\u{0947} \u{092A}\u{0930}\u{093F}\u{0935}\u{093E}\u{0930} \u{0915}\u{094B}"),
            message: ("May the lamps of Diwali bring you joy, health and prosperity.", "\u{0926}\u{0940}\u{092A}\u{094B}\u{0902} \u{0915}\u{093E} \u{092F}\u{0939} \u{092A}\u{0930}\u{094D}\u{0935} \u{0906}\u{092A}\u{0915}\u{0947} \u{091C}\u{0940}\u{0935}\u{0928} \u{092E}\u{0947}\u{0902} \u{0938}\u{0941}\u{0916}, \u{0938}\u{094D}\u{0935}\u{093E}\u{0938}\u{094D}\u{0925}\u{094D}\u{092F} \u{0914}\u{0930} \u{0938}\u{092E}\u{0943}\u{0926}\u{094D}\u{0927}\u{093F} \u{0932}\u{093E}\u{090F}\u{0964}"),
            from: ("Warm wishes", "\u{0936}\u{0941}\u{092D}\u{0915}\u{093E}\u{092E}\u{0928}\u{093E}\u{0913}\u{0902} \u{0938}\u{0939}\u{093F}\u{0924}"))

        var info = WishApp(name: "Infographics", nameHi: "\u{0907}\u{0928}\u{094D}\u{092B}\u{094B}\u{0917}\u{094D}\u{0930}\u{093E}\u{092B}\u{093C}\u{093F}\u{0915}\u{094D}\u{0938}", tagline: "Turn data into a story", symbol: "chart.pie.fill", artwork: "chart.pie.fill", kind: .infographic,
                           prompt: "Paste a list or a few numbers and get a clear picture: circles, a table, bars, a donut and more.")
        info.builtIn = true
        info.fields = [
            field("eyebrow", "Top line", "\u{090A}\u{092A}\u{0930} \u{0915}\u{0940} \u{092A}\u{0902}\u{0915}\u{094D}\u{0924}\u{093F}", .text, "IDEAS, BEAUTIFULLY CONNECTED", "\u{0935}\u{093F}\u{091A}\u{093E}\u{0930}, \u{0938}\u{0941}\u{0902}\u{0926}\u{0930} \u{0922}\u{0902}\u{0917} \u{0938}\u{0947} \u{091C}\u{0941}\u{0921}\u{093C}\u{0947}"),
            field("title", "Infographic title", "\u{0907}\u{0928}\u{094D}\u{092B}\u{094B}\u{0917}\u{094D}\u{0930}\u{093E}\u{092B}\u{093C}\u{093F}\u{0915} \u{0936}\u{0940}\u{0930}\u{094D}\u{0937}\u{0915}", .text, "Four steps to a better day", "\u{0915}\u{0937}\u{093E}\u{092F} \u{0915}\u{0947} \u{091A}\u{093E}\u{0930} \u{092A}\u{094D}\u{0930}\u{0915}\u{093E}\u{0930}"),
            field("data", "Data", "\u{0921}\u{0947}\u{091F}\u{093E}", .list, "Plan\nFocus\nAct\nReflect", "\u{0915}\u{094D}\u{0930}\u{094B}\u{0927}\n\u{092E}\u{093E}\u{0928}\n\u{092E}\u{093E}\u{092F}\u{093E}\n\u{0932}\u{094B}\u{092D}"),
        ]
        return [birthday, anniversary, WishQuickCard.workAnniversaryApp(), diwali, info]
    }

    static func functions() -> [WishFunction] {
        return [
            WishFunction(name: "Hello", expression: "GREETING()", note: "Good morning, afternoon or evening"),
            WishFunction(name: "NextMonth", expression: "Month+1", note: "The name of next month"),
            WishFunction(name: "LongDate", expression: "TEXT(Date,\"dddd, d mmmm yyyy\")", note: "Monday, 9 November 2026"),
        ]
    }
}

// MARK: - Saving

private struct WishSnapshot: Codable {
    var apps: [WishApp]
    var functions: [WishFunction]
    var cards: [String: WishCard]
    var lastAppID: String
    var templates: [WishTemplate]?
}

@MainActor
final class WishStore: ObservableObject {
    @Published var apps: [WishApp] = [] { didSet { scheduleSave() } }
    @Published var functions: [WishFunction] = [] { didSet { scheduleSave() } }
    @Published var cards: [String: WishCard] = [:] { didSet { scheduleSave() } }
    @Published var lastAppID: String = "" { didSet { scheduleSave() } }
    @Published var templates: [WishTemplate] = [] { didSet { scheduleSave() } }
    private(set) var directory: URL?

    private var fileURL: URL?
    private var loaded = false
    private var pendingSave: Task<Void, Never>?

    func load(directory: URL) {
        guard !loaded else { return }
        loaded = true
        self.directory = directory
        let url = directory.appendingPathComponent("wishstudio.json")
        fileURL = url
        if let data = try? Data(contentsOf: url), let snapshot = try? JSONDecoder().decode(WishSnapshot.self, from: data), !snapshot.apps.isEmpty {
            apps = snapshot.apps
            functions = snapshot.functions
            cards = snapshot.cards
            lastAppID = snapshot.lastAppID
            templates = snapshot.templates ?? []
            migrateNames()
        } else {
            apps = WishSeeds.apps()
            functions = WishSeeds.functions()
            lastAppID = apps.first?.id ?? ""
        }
    }

    /// The first release called the starter apps Birthday, Anniversary and Diwali.
    private func migrateNames() {
        let renames = ["Birthday": "Happy Birthday", "Anniversary": "Happy Anniversary", "Diwali": "Happy Diwali"]
        let designs = ["Happy Birthday": "g-blush", "Happy Anniversary": "g-rose", "Happy Diwali": "g-saffron"]
        var changed = apps
        for index in changed.indices where changed[index].builtIn {
            if let better = renames[changed[index].name] { changed[index].name = better }
            if changed[index].designID == nil, let design = designs[changed[index].name] { changed[index].designID = design }
        }
        if changed != apps { apps = changed }
    }

    // MARK: Media files

    var mediaDirectory: URL? {
        return directory?.appendingPathComponent("WishMedia", isDirectory: true)
    }

    func mediaURL(_ file: String) -> URL? {
        return mediaDirectory?.appendingPathComponent(file)
    }

    /// Copies a picture, GIF or video next to the WishStudio data and returns its file name and kind.
    func importMedia(from source: URL) -> (file: String, kind: String)? {
        guard let folder = mediaDirectory else { return nil }
        let ext = source.pathExtension.lowercased()
        let kind: String
        if ["mp4", "mov", "m4v", "webm"].contains(ext) {
            kind = "video"
        } else if ext == "gif" {
            kind = "gif"
        } else if ["png", "jpg", "jpeg", "heic", "webp", "tiff", "bmp"].contains(ext) {
            kind = "image"
        } else {
            return nil
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = UUID().uuidString + "." + ext
        do {
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name))
        } catch {
            return nil
        }
        return (name, kind)
    }

    private func scheduleSave() {
        guard loaded else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let url = fileURL else { return }
        let snapshot = WishSnapshot(apps: apps, functions: functions, cards: cards, lastAppID: lastAppID, templates: templates)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func app(id: String) -> WishApp? {
        return apps.first { $0.id == id }
    }

    func updateApp(_ app: WishApp) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[index] = app
    }

    func resetStarterApps() {
        let starters = WishSeeds.apps()
        for starter in starters where !apps.contains(where: { $0.name == starter.name && $0.builtIn }) {
            apps.append(starter)
        }
    }

    /// The context functions are evaluated in: global functions plus this card's fields, in order.
    func context(for card: WishCard, app: WishApp) -> WishContext {
        var context = WishContext()
        context.locale = card.language.locale
        for function in functions {
            var body = function.expression.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.hasPrefix("=") { body.removeFirst() }
            context.functions[function.name.lowercased()] = body
        }
        for field in app.fields {
            let raw = card.value(for: field.key)
            context.variables[field.key.lowercased()] = WishFormula.render(raw, context: context)
        }
        return context
    }

    func rendered(_ key: String, card: WishCard, app: WishApp) -> String {
        let context = self.context(for: card, app: app)
        return context.variables[key.lowercased()] ?? ""
    }
}
