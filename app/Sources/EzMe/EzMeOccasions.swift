// More greeting cards in the style of hbd / hwa: Thank You, Wedding Anniversary and 14 Indian festivals.
//
// Type  thanks-Hiral  or  holi-Family  (or a media shortcut after the dash) in the shortcut popup. The card is a
// WishStudio web page. Every occasion is also a WishStudio app, so its text and its default look can be changed there.
// Add a template after the name to use another look for that card only:  thanks-Hiral-gold,  diwali-Shah family-night,
// or the name of a template saved in WishStudio.
import Foundation
import AppKit
import WebKit

struct GreetingOccasion {
    let id: String
    let appName: String      // the WishStudio app
    let presetName: String   // the AppBuilder app
    let prefix: String
    let symbol: String
    let design: String       // default look: a greeting design id
    let eyebrow: String
    let title: String
    let titleHi: String
    let message: String
    let from: String
    /// An older WishStudio starter app that already is this occasion, so no second app is added.
    var reuses: String? = nil

    var engine: String { "wish-occ-" + id }
}

enum WishOccasions {
    static let all: [GreetingOccasion] = [
        GreetingOccasion(id: "thanks", appName: "Thank You", presetName: "Thank You Card (THANKS)", prefix: "thanks", symbol: "heart.fill", design: "g-mint",
                     eyebrow: "WITH ALL MY GRATITUDE", title: "Thank You", titleHi: "धन्यवाद",
                     message: "Thank you for your kindness, your time and your support. It truly made a difference.", from: "With thanks"),
        GreetingOccasion(id: "wed", appName: "Happy Anniversary", presetName: "Wedding Anniversary Card (WED)", prefix: "wed", symbol: "heart.fill", design: "g-rose",
                     eyebrow: "CELEBRATING YOUR LOVE", title: "Happy Wedding Anniversary", titleHi: "शादी की सालगिरह मुबारक",
                     message: "Here is to the love you share and every beautiful year still ahead.", from: "Warmly", reuses: "Happy Anniversary"),
        GreetingOccasion(id: "diwali", appName: "Happy Diwali", presetName: "Diwali Card (DIWALI)", prefix: "diwali", symbol: "flame.fill", design: "g-saffron",
                     eyebrow: "A FESTIVAL OF LIGHT", title: "Happy Diwali", titleHi: "दीपावली की शुभकामनाएँ",
                     message: "May the lamps of Diwali bring you joy, health and prosperity.", from: "Warm wishes", reuses: "Happy Diwali"),
        GreetingOccasion(id: "holi", appName: "Happy Holi", presetName: "Holi Card (HOLI)", prefix: "holi", symbol: "sparkles", design: "g-coral",
                     eyebrow: "A FESTIVAL OF COLOURS", title: "Happy Holi", titleHi: "होली की शुभकामनाएँ",
                     message: "May your life be painted with the colours of joy, love and good health.", from: "Warm wishes"),
        GreetingOccasion(id: "eid", appName: "Eid Mubarak", presetName: "Eid Card (EID)", prefix: "eid", symbol: "moon.stars.fill", design: "g-mint",
                     eyebrow: "MAY YOUR DAYS BE BLESSED", title: "Eid Mubarak", titleHi: "ईद मुबारक",
                     message: "Wishing you and your family peace, happiness and countless blessings this Eid.", from: "Warm wishes"),
        GreetingOccasion(id: "xmas", appName: "Merry Christmas", presetName: "Christmas Card (XMAS)", prefix: "xmas", symbol: "star.fill", design: "g-sage",
                     eyebrow: "PEACE ON EARTH, GOODWILL TO ALL", title: "Merry Christmas", titleHi: "क्रिसमस की शुभकामनाएँ",
                     message: "Wishing you a Christmas filled with warmth, laughter and the people you love.", from: "Warm wishes"),
        GreetingOccasion(id: "rakhi", appName: "Happy Raksha Bandhan", presetName: "Raksha Bandhan Card (RAKHI)", prefix: "rakhi", symbol: "heart.fill", design: "g-blush",
                     eyebrow: "A BOND OF LOVE", title: "Happy Raksha Bandhan", titleHi: "रक्षाबंधन की शुभकामनाएँ",
                     message: "For the bond of love and protection that grows stronger every year.", from: "With love"),
        GreetingOccasion(id: "ganesh", appName: "Happy Ganesh Chaturthi", presetName: "Ganesh Chaturthi Card (GANESH)", prefix: "ganesh", symbol: "sparkles", design: "g-gold",
                     eyebrow: "GANPATI BAPPA MORYA", title: "Happy Ganesh Chaturthi", titleHi: "गणेश चतुर्थी की शुभकामनाएँ",
                     message: "May Lord Ganesha remove every obstacle and bless your home with wisdom and prosperity.", from: "Warm wishes"),
        GreetingOccasion(id: "navratri", appName: "Happy Navratri", presetName: "Navratri Card (NAVRATRI)", prefix: "navratri", symbol: "flame.fill", design: "g-peach",
                     eyebrow: "NINE NIGHTS OF DEVOTION", title: "Happy Navratri", titleHi: "नवरात्रि की शुभकामनाएँ",
                     message: "May the nine nights bring you strength, devotion and joy in every step.", from: "Warm wishes"),
        GreetingOccasion(id: "durga", appName: "Happy Durga Puja", presetName: "Durga Puja Card (DURGA)", prefix: "durga", symbol: "flame.fill", design: "g-rose",
                     eyebrow: "SHUBHO PUJO", title: "Happy Durga Puja", titleHi: "दुर्गा पूजा की शुभकामनाएँ",
                     message: "May Maa Durga bless you and your family with strength, peace and happiness.", from: "Warm wishes"),
        GreetingOccasion(id: "dussehra", appName: "Happy Dussehra", presetName: "Dussehra Card (DUSSEHRA)", prefix: "dussehra", symbol: "star.fill", design: "g-saffron",
                     eyebrow: "VICTORY OF GOOD OVER EVIL", title: "Happy Dussehra", titleHi: "दशहरा की शुभकामनाएँ",
                     message: "May the victory of good over evil bring light, courage and happiness into your life.", from: "Warm wishes"),
        GreetingOccasion(id: "sankranti", appName: "Happy Makar Sankranti", presetName: "Makar Sankranti Card (SANKRANTI)", prefix: "sankranti", symbol: "sun.max.fill", design: "g-sky",
                     eyebrow: "KITES, SUN AND SWEETNESS", title: "Happy Makar Sankranti", titleHi: "मकर संक्रांति की शुभकामनाएँ",
                     message: "May the kites of joy fly high and the sweetness of til-gud fill your days.", from: "Warm wishes"),
        GreetingOccasion(id: "pongal", appName: "Happy Pongal", presetName: "Pongal Card (PONGAL)", prefix: "pongal", symbol: "sun.max.fill", design: "g-gold",
                     eyebrow: "THE HARVEST FESTIVAL", title: "Happy Pongal", titleHi: "पोंगल की शुभकामनाएँ",
                     message: "May the harvest festival overflow your home with prosperity, sweetness and good fortune.", from: "Warm wishes"),
        GreetingOccasion(id: "onam", appName: "Happy Onam", presetName: "Onam Card (ONAM)", prefix: "onam", symbol: "camera.macro", design: "g-sage",
                     eyebrow: "A FEAST OF FLOWERS AND JOY", title: "Happy Onam", titleHi: "ओणम की शुभकामनाएँ",
                     message: "Wishing you a joyful Onam with a beautiful pookalam, a grand sadya and loved ones around you.", from: "Warm wishes"),
        GreetingOccasion(id: "baisakhi", appName: "Happy Baisakhi", presetName: "Baisakhi Card (BAISAKHI)", prefix: "baisakhi", symbol: "leaf.fill", design: "g-gold",
                     eyebrow: "THE HARVEST NEW YEAR", title: "Happy Baisakhi", titleHi: "बैसाखी की शुभकामनाएँ",
                     message: "May this harvest festival bring you a season of hope, happiness and abundance.", from: "Warm wishes"),
        GreetingOccasion(id: "janmashtami", appName: "Happy Janmashtami", presetName: "Janmashtami Card (JANMASHTAMI)", prefix: "janmashtami", symbol: "music.note", design: "g-night",
                     eyebrow: "JAI SHRI KRISHNA", title: "Happy Janmashtami", titleHi: "जन्माष्टमी की शुभकामनाएँ",
                     message: "May Lord Krishna's flute fill your life with joy, love and peace.", from: "Warm wishes"),
    ]

    static func occasion(forApp app: String) -> GreetingOccasion? {
        let engine = UserDefaults.standard.string(forKey: "ezmeBuilderEngine." + app) ?? ""
        guard engine.hasPrefix("wish-occ-") else { return nil }
        return all.first { $0.engine == engine }
    }

    /// One AppBuilder app per occasion. They all save into the Greeting Cards collection.
    static var presets: [AppBuilderPreset] {
        all.map { item in
            AppBuilderPreset(name: item.presetName, prefix: item.prefix, prompt: "\(item.title) card web page.", variables: "Name", sourceCollections: "",
                             outputCollections: "Greeting Cards", template: "Modern",
                             details: "Makes a \(item.title) card as a web page. Type \(item.prefix)-Name, or \(item.prefix)- and a media shortcut to use its picture. Add -gold, -night or a saved template name to pick another look.",
                             format: "Image", engine: item.engine)
        }
    }

    /// The WishStudio app for an occasion (not used when an older starter app already covers it).
    static func makeApp(_ item: GreetingOccasion) -> WishApp {
        func field(_ key: String, _ label: String, _ labelHi: String, _ type: WishFieldType, _ value: String, _ valueHi: String, universal: Bool = false) -> WishField {
            WishField(key: key, label: label, labelHi: labelHi, type: type, value: value, valueHi: valueHi, universal: universal)
        }
        var app = WishApp(name: item.appName, nameHi: item.titleHi, tagline: item.eyebrow.capitalized, symbol: item.symbol, artwork: item.symbol, kind: .greeting,
                          prompt: "A \(item.title) card with a name and a short blessing.")
        app.builtIn = true
        app.designID = item.design
        app.fields = [
            field("eyebrow", "Top line", "ऊपर की पंक्ति", .text, item.eyebrow, item.eyebrow),
            field("title", "Title", "शीर्षक", .text, item.title, item.titleHi, universal: false),
            field("name", "Name", "नाम", .text, "Dear friend", "प्रिय मित्र", universal: true),
            field("message", "Message", "संदेश", .longText, item.message, item.message),
            field("from", "From", "की ओर से", .text, item.from, item.from),
            field("date", "Date", "तारीख", .date, "=Date", "=Date", universal: true),
        ]
        return app
    }

    // MARK: Templates (looks)

    private static func normalize(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// A built-in look by a short word: gold, night, blush, mint, sky, lavender, peach, rose, sage, coral, ink, saffron.
    static func design(forToken token: String) -> String? {
        let wanted = normalize(token)
        guard wanted.count >= 3 else { return nil }
        let designs = WishDesigns.greeting
        if let exact = designs.first(where: { normalize(String($0.id.dropFirst(2))) == wanted }) { return exact.id }
        if let starts = designs.first(where: { normalize($0.name).hasPrefix(wanted) }) { return starts.id }
        return designs.first(where: { normalize($0.name).contains(wanted) })?.id
    }

    /// A template saved in WishStudio for this app, by name.
    static func savedTemplate(forToken token: String, appID: String, in templates: [WishTemplate]) -> WishTemplate? {
        let wanted = normalize(token)
        guard !wanted.isEmpty else { return nil }
        let mine = templates.filter { $0.appID == appID }
        return mine.first { normalize($0.name) == wanted } ?? mine.first { normalize($0.name).hasPrefix(wanted) }
    }

    /// Cards used to default to an HTML page, whose link only works on this Mac. They now default to a picture.
    /// Runs once: apps still set to HTML are switched to Image. People can change the output back afterwards.
    static func migrateToImageOutput() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "ezmeOccasionImageDefaultV1") else { return }
        for item in all {
            let key = "ezmeBuilderFormat." + item.presetName
            if let format = defaults.string(forKey: key), format.caseInsensitiveCompare("HTML") == .orderedSame { defaults.set("Image", forKey: key) }
        }
        defaults.set(true, forKey: "ezmeOccasionImageDefaultV1")
    }

    // MARK: Building the card

    /// The app, card text, colours and look for one occasion card, after any saved template or look word is applied.
    static func resolve(occasion item: GreetingOccasion, name: String, templateToken: String, in directory: URL) -> (app: WishApp, card: WishCard, designID: String, note: String) {
        let stored = WishStoreReader.read(directory: directory)
        let seeded = WishSeeds.apps().first { $0.name == (item.reuses ?? item.appName) }
        let app = stored.apps.first { $0.name == (item.reuses ?? item.appName) } ?? seeded ?? makeApp(item)
        var designID = app.designID ?? item.design
        var saved: WishTemplate?
        var note = ""
        let token = templateToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            if let found = savedTemplate(forToken: token, appID: app.id, in: stored.templates) {
                saved = found
                designID = found.designID
            } else if let look = design(forToken: token) {
                designID = look
            } else {
                note = "No template called \u{201C}\(token)\u{201D}: used the default look."
            }
        }
        var card = WishCard.make(for: app, designID: designID)
        if let saved {
            card.backgroundHex = saved.backgroundHex
            card.accentHex = saved.accentHex
            card.inkHex = saved.inkHex
            card.fontStyle = saved.fontStyle
            card.textScale = saved.textScale
            card.magic = saved.magic
            card.artwork = saved.artwork
            if let values = saved.values { card.values = values }
            if let valuesHi = saved.valuesHi { card.valuesHi = valuesHi }
        }
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !who.isEmpty {
            card.values["name"] = who
            card.valuesHi["name"] = who
        }
        return (app, card, designID, note)
    }

    /// Builds the card page (index.html and its picture) and returns its address, with a note when the template was not found.
    static func build(occasion item: GreetingOccasion, name: String, photo: String?, templateToken: String, in directory: URL) throws -> (url: URL, note: String) {
        let resolved = resolve(occasion: item, name: name, templateToken: templateToken, in: directory)
        let app = resolved.app, designID = resolved.designID, note = resolved.note
        var card = resolved.card
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
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
            card.media = [WishMedia(file: file, kind: source.pathExtension.lowercased() == "gif" ? "gif" : "image", placement: "hero")]
        }
        var context = WishContext()
        context.locale = card.language.locale
        for field in app.fields {
            context.variables[field.key.lowercased()] = WishFormula.render(card.value(for: field.key), context: context)
        }
        let layout = WishDesigns.design(id: card.designID, kind: .greeting)
        let json = WishHTML.stateJSON(app: app, card: card, design: layout, context: context, selected: nil) { file in "media/" + file }
        let index = folder.appendingPathComponent("index.html")
        try WishHTML.page(stateJSON: json, interactive: false).write(to: index, atomically: true, encoding: .utf8)
        return (index, note)
    }

    /// The card as a PNG picture in the Attachments folder, so it can be pasted or attached anywhere.
    @MainActor static func buildPNG(occasion item: GreetingOccasion, name: String, photo: String?, templateToken: String, in directory: URL) async throws -> (path: String, note: String) {
        let resolved = resolve(occasion: item, name: name, templateToken: templateToken, in: directory)
        var card = resolved.card
        var context = WishContext()
        context.locale = card.language.locale
        for key in ["eyebrow", "title", "name", "message", "from"] {
            let rendered = WishFormula.render(card.value(for: key), context: context)
            if card.language == .hindi { card.valuesHi[key] = rendered } else { card.values[key] = rendered }
        }
        let design = WishDesigns.design(id: card.designID, kind: .greeting)
        guard let data = OccasionCardDrawer.pngData(card: card, design: design, photo: photo) else { throw CardImageError() }
        let built = (note: resolved.note, ())
        let folder = directory.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let title = item.title.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let file = folder.appendingPathComponent("\(title)\(safe.isEmpty ? "" : "_" + safe)-\(UUID().uuidString.prefix(4)).png")
        try data.write(to: file, options: .atomic)
        return (file.path, built.note)
    }
}

struct CardImageError: LocalizedError {
    var errorDescription: String? { "The card picture could not be made. Try again, or switch this app's output to HTML." }
}

/// Draws a card page in a hidden web view and returns it as PNG data.
@MainActor
final class WishOffscreenRenderer: NSObject, WKNavigationDelegate {
    private var loaded: CheckedContinuation<Void, Never>?

    static func png(index: URL, readAccess: URL, width: CGFloat = 1080) async -> Data? {
        await WishOffscreenRenderer().render(index: index, readAccess: readAccess, width: width)
    }

    private func finishLoading() {
        loaded?.resume()
        loaded = nil
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { Task { @MainActor in self.finishLoading() } }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.finishLoading() } }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.finishLoading() } }

    private func render(index: URL, readAccess: URL, width: CGFloat) async -> Data? {
        let size = NSSize(width: 900, height: 1200)
        let view = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: WKWebViewConfiguration())
        view.navigationDelegate = self
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.close() }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loaded = continuation
            view.loadFileURL(index, allowingReadAccessTo: readAccess)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                self.finishLoading()
            }
        }
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard let image = await snapshot(view, width: width) else { return nil }
        return WishExport.pngData(from: image)
    }

    private func snapshot(_ web: WKWebView, width: CGFloat) async -> NSImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            web.evaluateJavaScript("setExport(true)") { _, _ in
                web.evaluateJavaScript("exportRect()") { value, _ in
                    let configuration = WKSnapshotConfiguration()
                    configuration.snapshotWidth = NSNumber(value: Double(width))
                    if let numbers = value as? [Double], numbers.count == 4 {
                        configuration.rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
                    }
                    web.takeSnapshot(with: configuration) { image, _ in
                        web.evaluateJavaScript("setExport(false)", completionHandler: nil)
                        continuation.resume(returning: image)
                    }
                }
            }
        }
    }
}
