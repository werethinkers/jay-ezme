// New app, step by step: 1 pick or upload a background (a logo spot is already on it), 2 add the boxes (variables,
// collections, functions, pictures, text) by hand, by voice or by a sentence, and let AI tidy the positions,
// 3 name the app, choose its command word and say which boxes are mandatory.
import SwiftUI
import AppKit

// MARK: - Kinds of app

enum WizardKind: String, CaseIterable, Identifiable {
    case invoice, birthday, card, invitation, quotation, blank
    var id: String { rawValue }

    var title: String {
        switch self {
        case .invoice: return "Invoice"
        case .birthday: return "Birthday wish"
        case .card: return "Visiting card"
        case .invitation: return "Invitation"
        case .quotation: return "Quotation"
        case .blank: return "Blank"
        }
    }

    var symbol: String {
        switch self {
        case .invoice: return "doc.text.fill"
        case .birthday: return "birthday.cake.fill"
        case .card: return "person.crop.rectangle.fill"
        case .invitation: return "envelope.open.fill"
        case .quotation: return "indianrupeesign.square.fill"
        case .blank: return "doc"
        }
    }

    var detail: String {
        switch self {
        case .invoice: return "A4. Logo top left."
        case .birthday: return "Square. Logo on top."
        case .card: return "Wide card. Logo left."
        case .invitation: return "Tall card. Logo on top."
        case .quotation: return "A4. Logo top right."
        case .blank: return "A4. Logo top left."
        }
    }

    var size: (Int, Int) {
        switch self {
        case .invoice, .quotation, .blank: return (1654, 2339)
        case .birthday: return (1080, 1080)
        case .card: return (1050, 600)
        case .invitation: return (1240, 1754)
        }
    }

    var background: String {
        switch self {
        case .invoice, .quotation, .blank: return "#FFFFFF"
        case .birthday: return "#FFF1E6"
        case .card: return "#F8EFE1"
        case .invitation: return "#FBF3E4"
        }
    }

    /// The default logo spot: centre x, centre y and width as a fraction of the page.
    var logoSpot: (cx: Double, cy: Double, w: Double) {
        switch self {
        case .invoice, .blank: return (0.14, 0.07, 0.14)
        case .quotation: return (0.86, 0.07, 0.14)
        case .birthday: return (0.5, 0.1, 0.16)
        case .invitation: return (0.5, 0.09, 0.16)
        case .card: return (0.14, 0.2, 0.16)
        }
    }

    /// Boxes people usually want on this kind of page.
    var suggested: [(String, DesignDataType)] {
        switch self {
        case .invoice: return [("customer", .text), ("date", .date), ("amount", .currency), ("phone", .phone)]
        case .birthday: return [("name", .text), ("date", .date)]
        case .card: return [("name", .text), ("phone", .phone), ("email", .email)]
        case .invitation: return [("guest", .text), ("date", .date), ("time", .time)]
        case .quotation: return [("client", .text), ("date", .date), ("amount", .currency)]
        case .blank: return []
        }
    }
}

enum WizardElementKind: String, CaseIterable, Identifiable {
    case variable, collection, function, picture, text
    var id: String { rawValue }
    var title: String {
        switch self {
        case .variable: return "Variable"
        case .collection: return "Collection"
        case .function: return "Function"
        case .picture: return "Picture"
        case .text: return "Text"
        }
    }
    var symbol: String {
        switch self {
        case .variable: return "curlybraces"
        case .collection: return "books.vertical"
        case .function: return "function"
        case .picture: return "photo"
        case .text: return "textformat"
        }
    }
}

struct WizardElement: Identifiable, Equatable {
    var id = UUID().uuidString
    var kind: WizardElementKind
    var name: String
    var type: DesignDataType = .text
    var required = false
    var category = ""
    var sub = ""
    var field = "name"
    var defaultValue = ""
    var formula = ""
    var text = ""
    var cx = 0.5, cy = 0.5, w = 0.7, h = 0.07

    var isMediaCollection: Bool { kind == .collection && !sub.isEmpty && MediaFinder.isMediaCollection(sub) }
    /// The key apps and the form know this box by.
    var fieldKey: String { kind == .collection && !sub.isEmpty ? TemplateFill.normal(sub) : TemplateFill.normal(name) }
    var needsChoice: Bool { (kind == .collection && sub.isEmpty) || (kind == .function && formula.isEmpty) }
}

// MARK: - Turning elements into boxes

@MainActor enum WizardBuilder {
    static func slot(for e: WizardElement) -> TemplateSlot {
        var slot: TemplateSlot
        switch e.kind {
        case .variable:
            slot = TemplateSlot(key: e.name, kind: .text)
            slot.content = "{{\(e.name)}}"
            slot.sample = e.defaultValue.isEmpty ? e.type.example : e.defaultValue
        case .collection:
            if e.isMediaCollection {
                slot = TemplateSlot(key: e.sub, kind: .image)
                slot.sample = ""
            } else {
                slot = TemplateSlot(key: e.name, kind: .text)
                var token = DesignElementTokens.refine("{{wish:\(e.sub)}}")
                if token.hasPrefix("{{@"), e.field != "name" { token = "{{@\(e.sub)/$\(TemplateFill.normal(e.sub))/\(e.field)}}" }
                slot.content = e.sub.isEmpty ? nil : token
                slot.sample = e.defaultValue.isEmpty ? (e.sub.isEmpty ? "Choose a collection" : e.sub) : e.defaultValue
            }
        case .function:
            slot = TemplateSlot(key: e.name, kind: .text)
            slot.content = e.formula.isEmpty ? nil : e.formula
            slot.sample = e.formula.isEmpty ? "Function" : "Live value"
        case .picture:
            slot = TemplateSlot(key: e.name, kind: .image)
            slot.sample = ""
        case .text:
            slot = TemplateSlot(key: e.name, kind: .text)
            slot.content = e.text.isEmpty ? nil : e.text
            slot.sample = e.text.isEmpty ? "Your text" : e.text
        }
        slot.cx = e.cx; slot.cy = e.cy; slot.w = e.w; slot.h = e.h
        return slot
    }

    /// The starting values and the hidden type and mandatory marks the app needs.
    static func variables(for elements: [WizardElement]) -> [String: String] {
        var vars: [String: String] = [:]
        for e in elements {
            switch e.kind {
            case .variable:
                vars[e.name] = e.defaultValue
                DesignDataType.set(e.type, for: e.name, in: &vars)
            case .collection, .picture:
                if !e.defaultValue.isEmpty { vars[e.fieldKey] = e.defaultValue }
            default: break
            }
            if e.required, e.kind != .function, e.kind != .text { vars[DesignDataType.requiredKey(e.kind == .variable ? e.name : e.fieldKey)] = "1" }
        }
        return vars
    }

    /// Lays the boxes top to bottom under the logo with even gaps, shrinking them to fit the page.
    static func tidy(_ elements: inout [WizardElement], aspect: Double, logoBottom: Double) {
        guard !elements.isEmpty else { return }
        let top = max(0.16, logoBottom + 0.04), bottom = 0.95, gap = 0.018
        func height(_ e: WizardElement) -> Double {
            if e.kind == .picture || e.isMediaCollection { return min(0.24, 0.34 * aspect) }
            if e.kind == .variable && e.type == .long { return 0.14 }
            return 0.07
        }
        let natural = elements.map(height).reduce(0, +) + gap * Double(elements.count - 1)
        let scale = min(1, (bottom - top) / max(0.01, natural))
        var y = top
        for index in elements.indices {
            let h = height(elements[index]) * scale
            let picture = elements[index].kind == .picture || elements[index].isMediaCollection
            elements[index].w = picture ? min(0.4, h / max(0.05, aspect)) : 0.76
            elements[index].h = h
            elements[index].cx = 0.5
            elements[index].cy = y + h / 2
            y += h + gap * scale
        }
    }
}

// MARK: - Saying what you need

enum WizardSpec {
    private static let numbers: [String: Int] = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]

    private static func elementKind(_ word: String) -> WizardElementKind? {
        switch word.lowercased() {
        case "variable", "variables": return .variable
        case "collection", "collections": return .collection
        case "function", "functions", "formula", "formulas": return .function
        case "picture", "pictures", "photo", "photos", "image", "images", "media": return .picture
        case "text", "texts", "label", "labels": return .text
        default: return nil
        }
    }

    /// "I need two variables string and date, two collections, one picture and a countdown function".
    @MainActor static func parse(_ raw: String, existing: [WizardElement]) -> [WizardElement] {
        let text = raw.lowercased().replacingOccurrences(of: ",", with: " , ")
        let pattern = "\\b(\\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten)\\s+(?:more\\s+)?(variables?|collections?|functions?|formulas?|pictures?|photos?|images?|media|texts?|labels?)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var made: [WizardElement] = []
        var taken = Set(existing.map { TemplateFill.normal($0.name) })
        func unique(_ base: String) -> String {
            var name = base.isEmpty ? "box" : base
            var n = 1
            while taken.contains(TemplateFill.normal(name)) { n += 1; name = base + String(n) }
            taken.insert(TemplateFill.normal(name))
            return name
        }
        DesignFormulaSpeech.variables = existing.filter { $0.kind == .variable }.map { $0.name }
        for (i, match) in matches.enumerated() {
            let countWord = ns.substring(with: match.range(at: 1))
            let count = Int(countWord) ?? numbers[countWord] ?? 1
            guard let kind = elementKind(ns.substring(with: match.range(at: 2))) else { continue }
            let segStart = match.range.location + match.range.length
            let segEnd = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            let segment = ns.substring(with: NSRange(location: segStart, length: max(0, segEnd - segStart)))
            let pieces = segment.replacingOccurrences(of: " and ", with: " , ").replacingOccurrences(of: " or ", with: " , ")
                .replacingOccurrences(of: "&", with: ",").components(separatedBy: ",")
                .map { $0.replacingOccurrences(of: "\\b(like|called|named|such as|where|of type|type|as|for|with|that|is|are|i|need|want|the|also|then|please)\\b", with: " ", options: .regularExpression)
                    .split(separator: " ").joined(separator: " ") }
                .filter { !$0.isEmpty }
            for n in 0..<min(count, 12) {
                let piece = n < pieces.count ? pieces[n] : ""
                var e = WizardElement(kind: kind, name: "")
                switch kind {
                case .variable:
                    var type: DesignDataType = .text
                    var name = ""
                    if let whole = DesignDataType.spoken(piece) { type = whole; name = piece == "string" || whole == .text ? "text" : whole.rawValue }
                    else {
                        let words = piece.split(separator: " ").map(String.init)
                        if let last = words.last, let t = DesignDataType.spoken(last) { type = t; name = words.dropLast().joined(separator: "_") }
                        else if let first = words.first, let t = DesignDataType.spoken(first) { type = t; name = words.dropFirst().joined(separator: "_") }
                        else { name = words.joined(separator: "_") }
                        if name.isEmpty { name = type == .text ? "text" : type.rawValue }
                    }
                    if type == .long && name == "long" { name = "notes" }
                    e.type = type
                    e.name = unique(name.isEmpty ? "text" : name)
                    DesignFormulaSpeech.variables.append(e.name)
                case .collection:
                    e.name = unique(piece.isEmpty ? "collection" : piece.replacingOccurrences(of: " ", with: "_"))
                    if !piece.isEmpty, let hit = findSub(piece) { e.category = hit.category; e.sub = hit.sub; e.name = unique(hit.sub) }
                case .function:
                    e.name = unique("function")
                    if !piece.isEmpty { e.formula = DesignFormulaSpeech.token(piece) }
                case .picture:
                    e.name = unique(piece.isEmpty ? "photo" : piece.replacingOccurrences(of: " ", with: "_"))
                case .text:
                    e.name = unique("label")
                    e.text = piece.isEmpty ? "" : piece.prefix(1).uppercased() + piece.dropFirst()
                }
                made.append(e)
            }
        }
        return made
    }

    /// Finds a collection the person named, even in the plural or in part ("birthday wish").
    @MainActor static func findSub(_ said: String) -> (category: String, sub: String)? {
        let wanted = TemplateFill.normal(said)
        guard !wanted.isEmpty else { return nil }
        var best: (String, String, Int)?
        for group in AppDesignContext.shared.collectionTree {
            for name in group.names {
                let have = TemplateFill.normal(name)
                var score = 0
                if have == wanted || have + "s" == wanted || have == wanted + "s" { score = 100 }
                else if have.contains(wanted) || wanted.contains(have) { score = 60 }
                if score > (best?.2 ?? 0) { best = (group.category, name, score) }
            }
        }
        return best.map { ($0.0, $0.1) }
    }
}

// MARK: - The model

@MainActor final class NewAppWizardModel: ObservableObject {
    @Published var step = 0
    @Published var kind: WizardKind = .invoice
    @Published var elements: [WizardElement] = []
    @Published var designID: String?
    @Published var appName = ""
    @Published var command = ""
    @Published var message = ""
    @Published var selection: String?
    @Published var busy = false
    @Published var spokenSpec = ""
    @Published var uploaded = false
    @Published var tick = 0

    private let designs = AppDesignStore.shared
    private let templates = TemplateStore.shared

    var page: ImageTemplate? { designID.flatMap { designs.design(id: $0) }?.pages.first.flatMap { templates.template(id: $0) } }
    var aspect: Double { page.map { Double($0.pixelWidth) / Double(max(1, $0.pixelHeight)) } ?? 1 }
    var logo: TemplateSlot? { page?.slots.first { $0.kind == .logo } }

    // Step 1
    func start(_ kind: WizardKind, background: NSImage? = nil) {
        discardDraft()
        self.kind = kind
        uploaded = background != nil
        let made: AppDesign?
        if let background { made = designs.newFromPicture(background, name: kind.title) }
        else { made = designs.newBlank(name: kind.title, width: kind.size.0, height: kind.size.1, colorHex: kind.background) }
        guard let made else { message = "The page could not be made."; return }
        designID = made.id
        appName = kind == .blank ? "My app" : kind.title
        command = Self.suggestCommand(appName)
        if var page = page {
            var logo = TemplateSlot(key: "logo", kind: .logo)
            logo.logo = "Star"
            let spot = kind.logoSpot
            logo.cx = spot.cx; logo.cy = spot.cy; logo.w = spot.w
            logo.h = spot.w * Double(page.pixelWidth) / Double(max(1, page.pixelHeight))
            page.slots = [logo]
            templates.save(page)
        }
        elements = []
        selection = nil
        message = ""
        commit()
    }

    static func suggestCommand(_ name: String) -> String {
        let letters = name.lowercased().filter { $0.isLetter || $0.isNumber }
        return String(letters.prefix(8))
    }

    func discardDraft() {
        if let id = designID { designs.delete(id) }
        designID = nil
    }

    // Step 2
    func addSuggested() {
        for (name, type) in kind.suggested where !elements.contains(where: { TemplateFill.normal($0.name) == TemplateFill.normal(name) }) {
            elements.append(WizardElement(kind: .variable, name: name, type: type))
        }
        relayout()
    }

    func add(_ kind: WizardElementKind) {
        var e = WizardElement(kind: kind, name: "")
        e.name = uniqueName(kind == .variable ? "variable" : kind == .collection ? "collection" : kind == .function ? "function" : kind == .picture ? "photo" : "label")
        if kind == .function { e.formula = "{=TODAY()}" }
        if kind == .text { e.text = "Your text" }
        elements.append(e)
        selection = e.id
        relayout()
    }

    func uniqueName(_ base: String) -> String {
        var name = base
        var n = 1
        while elements.contains(where: { TemplateFill.normal($0.name) == TemplateFill.normal(name) }) { n += 1; name = base + String(n) }
        return name
    }

    func remove(_ id: String) { elements.removeAll { $0.id == id }; relayout() }

    func fromSpoken(_ text: String) {
        let made = WizardSpec.parse(text, existing: elements)
        if made.isEmpty {
            message = "I did not hear what to add. Try \u{201C}two variables string and date, one collection, one picture\u{201D}."
            return
        }
        elements += made
        relayout()
        let needs = made.filter { $0.needsChoice }.count
        message = "Added \(made.count) box\(made.count == 1 ? "" : "es")." + (needs > 0 ? " Choose the \(needs) that still need a collection or function." : "")
    }

    func chooseDefault(for id: String) {
        guard let index = elements.firstIndex(where: { $0.id == id }), elements[index].kind == .collection, !elements[index].sub.isEmpty else { return }
        // The first shortcut or media of the collection becomes the default, so the box is never empty.
        let sub = elements[index].sub
        if elements[index].defaultValue.isEmpty { elements[index].defaultValue = WishPick.clips(in: sub).first?.key ?? "" }
        elements[index].name = elements[index].isMediaCollection ? sub : elements[index].name
    }

    func relayout() {
        var copy = elements
        let logoBottom = logo.map { $0.cy + $0.h / 2 } ?? 0.15
        WizardBuilder.tidy(&copy, aspect: aspect, logoBottom: logoBottom)
        elements = copy
        commit()
    }

    /// Writes the boxes to the page and the variables to the design, so the preview shows every change at once.
    func commit() {
        guard let id = designID, var design = designs.design(id: id), var page = page else { return }
        let keepers = page.slots.filter { $0.kind == .logo }
        page.slots = keepers + elements.map { WizardBuilder.slot(for: $0) }
        templates.save(page)
        design.variables = WizardBuilder.variables(for: elements)
        designs.save(design)
        tick += 1
    }

    func moveLogo(cx: Double, cy: Double) {
        guard var page = page, let index = page.slots.firstIndex(where: { $0.kind == .logo }) else { return }
        page.slots[index].cx = cx; page.slots[index].cy = cy
        templates.save(page)
        relayout()
    }

    func resizeLogo(_ width: Double) {
        guard var page = page, let index = page.slots.firstIndex(where: { $0.kind == .logo }) else { return }
        page.slots[index].w = width
        page.slots[index].h = width * Double(page.pixelWidth) / Double(max(1, page.pixelHeight))
        templates.save(page)
        relayout()
    }

    func setLogo(_ name: String) {
        guard var page = page, let index = page.slots.firstIndex(where: { $0.kind == .logo }) else { return }
        page.slots[index].logo = name
        templates.save(page)
        tick += 1
    }

    func uploadLogo() {
        guard let image = TemplateDialogs.openImage(title: "Choose your logo"), let data = TemplateImages.png(image) else { return }
        let file = "logo-" + String(UUID().uuidString.prefix(8)) + ".png"
        try? data.write(to: templates.logoURL(file), options: .atomic)
        setLogo("file:" + file)
        message = "Your logo is on the page. Click it any time to move it."
    }

    /// Hit test for a click on the preview, in page fractions.
    func slotKey(at point: CGPoint) -> String? {
        guard let page else { return nil }
        for slot in page.slots.reversed() {
            if abs(Double(point.x) - slot.cx) <= slot.w / 2, abs(Double(point.y) - slot.cy) <= slot.h / 2 { return slot.kind == .logo ? "logo" : slot.key }
        }
        return nil
    }

    // AI
    func askAI() {
        let profiles = AIModelProfileStore.load()
        let selectedID = UserDefaults.standard.string(forKey: "ezmeSelectedAIModelProfile") ?? UserDefaults.standard.string(forKey: "ezmeCollectionSelectedProfile") ?? CollectionAIModelProfile.starter.id
        let profile = profiles.first(where: { $0.id == selectedID }) ?? .starter
        let key = KeyStore.load(account: profile.keyAccount) ?? ""
        guard !elements.isEmpty else { message = "Add a few boxes first."; return }
        guard !key.isEmpty else {
            relayout()
            message = "No AI key is set up, so I tidied the boxes in order. Add a key in Setup to let AI place them."
            return
        }
        let logoText = logo.map { "logo: cx \($0.cx), cy \($0.cy), w \($0.w), h \($0.h) (do not move it)" } ?? ""
        let list = elements.map { "{\"key\":\"\($0.fieldKey)\",\"kind\":\"\($0.kind.rawValue)\",\"cx\":\(String(format: "%.3f", $0.cx)),\"cy\":\(String(format: "%.3f", $0.cy)),\"w\":\(String(format: "%.3f", $0.w)),\"h\":\(String(format: "%.3f", $0.h))}" }.joined(separator: ",")
        let prompt = "You place boxes on a \(kind.title.lowercased()) page whose width divided by height is \(String(format: "%.3f", aspect)). Positions are fractions of the page: cx and cy are the centre, w and h the size. \(logoText). Boxes: [\(list)]. Arrange them so nothing overlaps or touches the logo, keep a margin of at least 0.05, follow a natural reading order for a \(kind.title.lowercased()), group related boxes, and keep pictures roughly square. Reply with ONLY a JSON array with one object per box, each with key, cx, cy, w and h."
        busy = true
        message = "Asking AI to place the boxes\u{2026}"
        Task { [weak self] in
            guard let self else { return }
            do {
                let reply = try await SharedAIClient.generate(profile: profile, key: key, prompt: prompt, maxTokens: 2500)
                self.apply(reply)
            } catch {
                self.busy = false
                self.relayout()
                self.message = "AI could not be reached, so I tidied the boxes in order."
            }
        }
    }

    private func apply(_ reply: String) {
        busy = false
        guard let start = reply.firstIndex(of: "["), let end = reply.lastIndex(of: "]"), start < end,
              let data = String(reply[start...end]).data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            relayout(); message = "AI answered in a way I could not use, so I tidied the boxes in order."; return
        }
        var changed = 0
        for item in items {
            guard let key = item["key"] as? String, let index = elements.firstIndex(where: { $0.fieldKey == TemplateFill.normal(key) }) else { continue }
            func number(_ name: String) -> Double? { (item[name] as? Double) ?? (item[name] as? Int).map(Double.init) }
            if let cx = number("cx"), let cy = number("cy"), let w = number("w"), let h = number("h") {
                elements[index].w = min(0.95, max(0.05, w)); elements[index].h = min(0.6, max(0.03, h))
                elements[index].cx = min(1 - elements[index].w / 2, max(elements[index].w / 2, cx))
                elements[index].cy = min(1 - elements[index].h / 2, max(elements[index].h / 2, cy))
                changed += 1
            }
        }
        commit()
        message = changed > 0 ? "AI placed \(changed) box\(changed == 1 ? "" : "es"). Not right? Tap Tidy for plain order, or ask again." : "AI gave no positions, so nothing moved."
    }

    // Step 3
    var counts: (variables: Int, collections: Int, functions: Int, pictures: Int, texts: Int) {
        (elements.filter { $0.kind == .variable }.count, elements.filter { $0.kind == .collection }.count, elements.filter { $0.kind == .function }.count,
         elements.filter { $0.kind == .picture }.count, elements.filter { $0.kind == .text }.count)
    }

    var existingTemplates: Int { designs.designs.filter { $0.id != designID }.count }

    func finish() -> AppDesign? {
        guard let id = designID, var design = designs.design(id: id) else { return nil }
        let title = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        design.name = title.isEmpty ? kind.title : title
        design.appTitle = design.name
        let word = command.lowercased().filter { $0.isLetter || $0.isNumber }
        design.command = word.isEmpty ? nil : word
        designs.save(design)
        commit()
        let result = designs.release(id)
        designID = nil
        message = result
        return designs.design(id: id)
    }
}

// MARK: - The screen

struct NewAppWizardView: View {
    var onDone: (AppDesign?) -> Void
    @StateObject private var model = NewAppWizardModel()
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                Group {
                    switch model.step {
                    case 0: stepOne
                    case 1: stepTwo
                    default: stepThree
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if model.designID != nil { Divider(); preview.frame(width: 330) }
            }
            Divider()
            footer
        }
        .frame(minWidth: 960, minHeight: 680)
        .background(Butter.cream)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "wand.and.stars").font(.system(size: 20)).foregroundStyle(Butter.coral)
            VStack(alignment: .leading, spacing: 2) {
                Text("New app").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Butter.cocoa)
                Text("Three short steps. You see every change on the page as you make it.").font(.system(size: 12)).foregroundStyle(Butter.cocoa.opacity(0.7))
            }
            Spacer()
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 5) {
                    Text("\(index + 1)").font(.system(size: 11, weight: .bold)).frame(width: 20, height: 20)
                        .background(Circle().fill(index <= model.step ? Butter.coral : Butter.honey.opacity(0.4))).foregroundStyle(.white)
                    Text(["Background", "Boxes", "Name"][index]).font(.system(size: 12, weight: index == model.step ? .bold : .regular)).foregroundStyle(Butter.cocoa)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // Step 1
    private var stepOne: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("1. Choose a background").font(.system(size: 16, weight: .bold)).foregroundStyle(Butter.cocoa)
                Text("Pick the kind of page. A logo spot is already there. You can also upload your own background, such as your letterhead or a designed birthday card.")
                    .font(.system(size: 12)).foregroundStyle(Butter.cocoa.opacity(0.75))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    ForEach(WizardKind.allCases) { kind in
                        Button { model.start(kind) } label: {
                            VStack(spacing: 6) {
                                Image(systemName: kind.symbol).font(.system(size: 26)).foregroundStyle(Butter.coral)
                                Text(kind.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Butter.cocoa)
                                Text(kind.detail).font(.system(size: 11)).foregroundStyle(Butter.cocoa.opacity(0.65))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.kind == kind && model.designID != nil ? Butter.coral : Butter.honey.opacity(0.7), lineWidth: model.kind == kind && model.designID != nil ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 10) {
                    Button { uploadBackground() } label: { Label("Upload my own background", systemImage: "photo.badge.plus") }
                        .buttonStyle(.borderedProminent).tint(Butter.coral)
                    Text(model.uploaded ? "Using your picture for \(model.kind.title.lowercased())." : "Choose a kind first, or upload and then pick what it is for.")
                        .font(.system(size: 11)).foregroundStyle(Butter.cocoa.opacity(0.7))
                }
                if model.designID != nil { logoControls }
                if !model.message.isEmpty { Text(model.message).font(.system(size: 12)).foregroundStyle(Butter.cocoa.opacity(0.8)) }
            }
            .padding(20)
        }
    }

    private func uploadBackground() {
        guard let image = TemplateDialogs.openImage(title: "Choose a background picture") else { return }
        model.start(model.kind, background: image)
    }

    private var logoControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Logo spot").font(.system(size: 13, weight: .bold)).foregroundStyle(Butter.cocoa)
            Text("Click the logo on the page to select it, or choose a spot here. You can move it again later in the designer.").font(.system(size: 11)).foregroundStyle(Butter.cocoa.opacity(0.7))
            HStack(spacing: 8) {
                let spots: [(String, Double, Double)] = [("Top left", 0.14, 0.07), ("Top centre", 0.5, 0.08), ("Top right", 0.86, 0.07), ("Centre", 0.5, 0.5), ("Bottom", 0.5, 0.92)]
                ForEach(0..<spots.count, id: \.self) { index in
                    Button(spots[index].0) { model.moveLogo(cx: spots[index].1, cy: spots[index].2) }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            HStack(spacing: 10) {
                Text("Size").font(.system(size: 12))
                Slider(value: Binding(get: { model.logo?.w ?? 0.14 }, set: { model.resizeLogo($0) }), in: 0.06...0.4).frame(width: 180)
                SearchablePick(title: "Logo style", options: TemplateLogos.builtIn.map { $0.name }, symbol: { name in TemplateLogos.builtIn.first { $0.name == name }?.symbol ?? "star" },
                               selection: Binding(get: { model.logo?.logo ?? "Star" }, set: { model.setLogo($0) })).frame(width: 150)
                Button { model.uploadLogo() } label: { Label("Upload logo", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.7)))
    }

    // Step 2
    private var stepTwo: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("2. Add your boxes").font(.system(size: 16, weight: .bold)).foregroundStyle(Butter.cocoa)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Say or type what you need").font(.system(size: 12, weight: .bold)).foregroundStyle(Butter.cocoa)
                    HStack {
                        TextField("I need two variables string and date, two collections, one picture", text: $model.spokenSpec)
                            .textFieldStyle(.roundedBorder).onSubmit { model.fromSpoken(model.spokenSpec); model.spokenSpec = "" }
                        Button("Add") { model.fromSpoken(model.spokenSpec); model.spokenSpec = "" }.buttonStyle(.borderedProminent).tint(Butter.coral)
                        VoiceDictationButton(onTranscript: { said in model.fromSpoken(said) })
                    }
                }
                HStack(spacing: 8) {
                    Menu {
                        ForEach(WizardElementKind.allCases) { kind in Button { model.add(kind) } label: { Label(kind.title, systemImage: kind.symbol) } }
                    } label: { Label("Add a box", systemImage: "plus.circle.fill") }
                        .menuStyle(.borderlessButton).fixedSize()
                    if !model.kind.suggested.isEmpty {
                        Button { model.addSuggested() } label: { Label("Add the usual boxes", systemImage: "sparkles") }.buttonStyle(.bordered).controlSize(.small)
                    }
                    Spacer()
                    Button { model.relayout(); model.message = "Tidied in reading order." } label: { Label("Tidy", systemImage: "rectangle.3.group") }.buttonStyle(.bordered).controlSize(.small)
                    Button { model.askAI() } label: { Label(model.busy ? "Asking\u{2026}" : "Ask AI to place them", systemImage: "wand.and.stars") }
                        .buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.small).disabled(model.busy)
                }
                if !model.message.isEmpty { Text(model.message).font(.system(size: 12)).foregroundStyle(Butter.cocoa.opacity(0.8)) }
                if model.elements.isEmpty {
                    Text("Nothing here yet. Say what you need above, add a box, or tap \u{201C}Add the usual boxes\u{201D}.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 20)
                }
                ForEach($model.elements) { $element in
                    ElementEditor(element: $element, selected: model.selection == element.id,
                                  onChange: { model.chooseDefault(for: element.id); model.relayout() },
                                  onSelect: { model.selection = element.id },
                                  onDelete: { model.remove(element.id) })
                }
            }
            .padding(20)
        }
    }

    // Step 3
    private var stepThree: some View {
        let counts = model.counts
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("3. Name it and make it yours").font(.system(size: 16, weight: .bold)).foregroundStyle(Butter.cocoa)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("App name").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        TextField("Invoice", text: $model.appName).textFieldStyle(.roundedBorder).frame(width: 240)
                            .onChange(of: model.appName) { _, value in if model.command.isEmpty || model.command == NewAppWizardModel.suggestCommand(model.kind.title) { model.command = NewAppWizardModel.suggestCommand(value) } }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Runs when you type  \\").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        TextField("inv", text: $model.command).textFieldStyle(.roundedBorder).frame(width: 140)
                    }
                }
                HStack(spacing: 8) {
                    summary("\(counts.variables)", "variables", "curlybraces")
                    summary("\(counts.collections)", "collections", "books.vertical")
                    summary("\(counts.functions)", "functions", "function")
                    summary("\(counts.pictures)", "pictures", "photo")
                    summary("\(model.existingTemplates)", "existing designs to reuse", "square.stack.3d.up")
                }
                Text("Three looks (temp1, temp2, temp3) are made for you, and you can add more in the designer.").font(.system(size: 11)).foregroundStyle(Butter.cocoa.opacity(0.7))
                Text("Mandatory boxes").font(.system(size: 13, weight: .bold)).foregroundStyle(Butter.cocoa)
                Text("A mandatory box must be filled before the app makes anything. All the others fall back to the last or a ready value.").font(.system(size: 11)).foregroundStyle(Butter.cocoa.opacity(0.7))
                let askable = model.elements.indices.filter { model.elements[$0].kind != .function && model.elements[$0].kind != .text }
                if askable.isEmpty { Text("No boxes to fill, so nothing to mark.").font(.system(size: 12)).foregroundStyle(.secondary) }
                ForEach(askable, id: \.self) { index in
                    Toggle(isOn: Binding(get: { model.elements[index].required }, set: { model.elements[index].required = $0; model.commit() })) {
                        HStack(spacing: 6) {
                            Image(systemName: model.elements[index].kind.symbol).foregroundStyle(Butter.coral).frame(width: 18)
                            Text(model.elements[index].kind == .collection && !model.elements[index].sub.isEmpty ? model.elements[index].sub : model.elements[index].name).font(.system(size: 13))
                            if model.elements[index].kind == .variable { Text(model.elements[index].type.title).font(.system(size: 10)).foregroundStyle(.secondary) }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                let open = model.elements.filter { $0.needsChoice }
                if !open.isEmpty {
                    Text("Still to choose: " + open.map { $0.name }.joined(separator: ", ") + ". Go back and pick a collection or function for them, or they stay empty.")
                        .font(.system(size: 12)).foregroundStyle(Color(red: 0.74, green: 0.18, blue: 0.1))
                }
            }
            .padding(20)
        }
    }

    private func summary(_ number: String, _ label: String, _ symbol: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).foregroundStyle(Butter.coral)
            Text(number).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Butter.cocoa)
            Text(label).font(.system(size: 10)).foregroundStyle(Butter.cocoa.opacity(0.7)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(8).background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
    }

    // Preview
    private var preview: some View {
        VStack(spacing: 8) {
            Text("Live page").font(.system(size: 12, weight: .bold)).foregroundStyle(Butter.cocoa)
            if let page = model.page, let base = TemplateStore.shared.basePicture(for: page),
               let image = TemplateRenderer.render(page, base: base, texts: nil, images: [:], useSamples: true, maxSide: 640) {
                Image(nsImage: image).resizable().scaledToFit()
                    .overlay(GeometryReader { proxy in
                        ZStack {
                            Color.clear.contentShape(Rectangle())
                                .onTapGesture { point in
                                    let spot = CGPoint(x: point.x / max(1, proxy.size.width), y: point.y / max(1, proxy.size.height))
                                    if let key = model.slotKey(at: spot) {
                                        if key == "logo" { model.step = 0 } else if let hit = model.elements.first(where: { $0.fieldKey == TemplateFill.normal(key) || TemplateFill.normal($0.name) == TemplateFill.normal(key) }) { model.step = 1; model.selection = hit.id }
                                    }
                                }
                            if let logo = model.logo {
                                RoundedRectangle(cornerRadius: 3).stroke(Butter.coral, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                    .frame(width: logo.w * proxy.size.width, height: logo.h * proxy.size.height)
                                    .position(x: logo.cx * proxy.size.width, y: logo.cy * proxy.size.height).allowsHitTesting(false)
                            }
                        }
                    })
                    .id(model.tick)
                    .shadow(color: .black.opacity(0.12), radius: 6)
                Text("Click the logo to change it, or a box to edit it.").font(.system(size: 10)).foregroundStyle(Butter.cocoa.opacity(0.6))
            }
            Spacer()
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { model.discardDraft(); onDone(nil) }.buttonStyle(.bordered)
            Spacer()
            if model.step > 0 { Button("Back") { model.step -= 1 }.buttonStyle(.bordered) }
            if model.step < 2 {
                Button("Next") { model.step += 1 }.buttonStyle(.borderedProminent).tint(Butter.coral).disabled(model.designID == nil)
                    .help(model.designID == nil ? "Choose a background first" : "")
            } else {
                Button("Create the app") { onDone(model.finish()) }.buttonStyle(.borderedProminent).tint(Butter.coral).disabled(model.designID == nil)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

/// One box of step 2, with what it needs: a type, a collection and subcategory with a default shortcut, or a function.
struct ElementEditor: View {
    @Binding var element: WizardElement
    var selected: Bool
    var onChange: () -> Void
    var onSelect: () -> Void
    var onDelete: () -> Void
    private var context: AppDesignContext { AppDesignContext.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: element.kind.symbol).foregroundStyle(Butter.coral).frame(width: 20)
                Text(element.kind.title).font(.system(size: 11, weight: .bold)).foregroundStyle(Butter.cocoa.opacity(0.7)).frame(width: 66, alignment: .leading)
                if element.kind != .collection || element.sub.isEmpty {
                    TextField("Name", text: $element.name).textFieldStyle(.roundedBorder).frame(maxWidth: 180)
                        .onSubmit { element.name = element.name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_"); onChange() }
                }
                Spacer()
                Button(action: onDelete) { Image(systemName: "xmark.circle") }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            switch element.kind {
            case .variable:
                HStack(spacing: 8) {
                    Text("Takes").font(.system(size: 11)).foregroundStyle(.secondary)
                    SearchablePick(title: "Data type", options: DesignDataType.allCases.map { $0.title }, symbol: { title in DesignDataType.allCases.first { $0.title == title }?.symbol ?? "textformat" },
                                   selection: Binding(get: { element.type.title }, set: { title in if let t = DesignDataType.allCases.first(where: { $0.title == title }) { element.type = t; onChange() } }))
                        .frame(width: 170)
                    TextField("Ready value, like " + element.type.example, text: $element.defaultValue).textFieldStyle(.roundedBorder)
                        .onSubmit { let check = element.type.check(element.defaultValue); if check.ok { element.defaultValue = check.clean }; onChange() }
                }
                if !element.defaultValue.isEmpty { DesignTypeNote(type: element.type, text: element.defaultValue) }
            case .collection:
                let tree = context.collectionTree
                HStack(spacing: 8) {
                    SearchablePick(title: "Category", options: tree.map { $0.category }, symbol: { _ in "folder" },
                                   selection: Binding(get: { element.category }, set: { value in element.category = value; element.sub = ""; element.defaultValue = ""; onChange() })).frame(width: 150)
                    SearchablePick(title: "Which subcategory?", options: tree.first(where: { $0.category == element.category })?.names ?? [],
                                   symbol: { MediaFinder.isMediaCollection($0) ? "photo.on.rectangle" : "list.bullet.rectangle" },
                                   selection: Binding(get: { element.sub }, set: { value in element.sub = value; element.defaultValue = ""; onChange() })).frame(width: 190)
                }
                if !element.sub.isEmpty {
                    let keys = WishPick.clips(in: element.sub).map { $0.key }
                    HStack(spacing: 8) {
                        Text(element.isMediaCollection ? "Default media" : "Default shortcut").font(.system(size: 11)).foregroundStyle(.secondary)
                        SearchablePick(title: keys.isEmpty ? "None yet" : "First one", options: keys, symbol: { _ in element.isMediaCollection ? "photo" : "text.quote" },
                                       selection: Binding(get: { element.defaultValue }, set: { element.defaultValue = $0; onChange() })).frame(width: 190)
                    }
                    Text("The default is filled in when nothing is chosen. Expanded text or media from this subcategory is used as is.").font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    Text("Pick the subcategory this box draws from.").font(.system(size: 10)).foregroundStyle(Color(red: 0.74, green: 0.18, blue: 0.1))
                }
            case .function:
                HStack(spacing: 8) {
                    TextField("Say or type it: days to event date, today plus 7", text: Binding(get: { element.formula }, set: { element.formula = $0 }))
                        .textFieldStyle(.roundedBorder).onSubmit { element.formula = DesignFormulaSpeech.token(element.formula.replacingOccurrences(of: "{=", with: "").replacingOccurrences(of: "}", with: "")); onChange() }
                    Menu {
                        ForEach(DesignFunction.items) { item in Button(item.title) { element.formula = item.token; onChange() } }
                    } label: { Image(systemName: "chevron.down.circle") }.menuStyle(.borderlessButton).fixedSize()
                }
            case .picture:
                Text("Filled with a shortcut name, a collection picture or an image the person adds.").font(.system(size: 10)).foregroundStyle(.secondary)
            case .text:
                TextField("Words on the page", text: $element.text).textFieldStyle(.roundedBorder).onSubmit { onChange() }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? Butter.coral : Butter.honey.opacity(0.7), lineWidth: selected ? 2 : 1))
        .onTapGesture { onSelect() }
    }
}
