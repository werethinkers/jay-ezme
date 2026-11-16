// AppDesigner: a design is a set of pages (each page is a template). Boxes on a page can hold live content
// (variables, collection items, shortcuts, functions, pictures, videos). Pages can be made from a picture, a blank
// sheet, or an uploaded document such as an NDA or agreement. Changes can be spoken or typed, and a finished design
// is released so WishBuilder and AppBuilder apps use that frozen version.
import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

// MARK: - What boxes can show

/// What the designer needs from the person's library while it works.
@MainActor final class AppDesignContext {
    static let shared = AppDesignContext()
    /// The live library. When set, the lists below always read from it, so every entry point sees everything.
    weak var db: DB?
    private var storedClips: [Clip] = []
    private var storedRecords: [CollectionRecord] = []
    private var storedCollections: [String] = []
    private var storedDefinitions: [CollectionDefinition] = []
    var clips: [Clip] { get { db?.clips ?? storedClips } set { storedClips = newValue } }
    var records: [CollectionRecord] { get { db?.collectionRecords ?? storedRecords } set { storedRecords = newValue } }
    var collections: [String] { get { db?.visibleCollections ?? storedCollections } set { storedCollections = newValue } }
    var definitions: [CollectionDefinition] { get { db?.collectionDefinitions ?? storedDefinitions } set { storedDefinitions = newValue } }

    /// Collections grouped by category: category, then the collections in it.
    var collectionTree: [CollectionGroup] {
        var order: [String] = []
        var map: [String: [String]] = [:]
        for name in collections {
            let category = collectionCategory(name, definition: definitions.first { $0.name.caseInsensitiveCompare(name) == .orderedSame })
            if map[category] == nil { order.append(category) }
            map[category, default: []].append(name)
        }
        return order.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { CollectionGroup(category: $0, names: (map[$0] ?? []).sorted { $0.localizedStandardCompare($1) == .orderedAscending }) }
    }
}

struct CollectionGroup: Identifiable {
    let category: String
    let names: [String]
    var id: String { category }
}

enum DesignContent {
    private static let regex = try? NSRegularExpression(pattern: "\\{\\{([^}]+)\\}\\}")

    /// Works out one piece of live content.
    ///   {{name}}                    a variable
    ///   {{@Customers/Rahul/email}}  a field of a collection item ("$name" in place of Rahul uses the variable called name)
    ///   {{shortcut:thanks}}         the text of a shortcut
    ///   {=Date+7}  or  =TODAY()     a function
    @MainActor static func resolve(_ text: String, values: [String: String], designing: Bool) -> String {
        var output = text
        if let regex {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                let inner = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = token(inner, values: values, designing: designing)
                output = (output as NSString).replacingCharacters(in: match.range, with: value)
            }
        }
        var context = WishContext()
        context.variables = values
        return WishFormula.render(output, context: context)
    }

    @MainActor private static func token(_ inner: String, values: [String: String], designing: Bool) -> String {
        let missing = designing ? "\u{2039}\(inner)\u{203A}" : ""
        let shared = AppDesignContext.shared
        if inner.hasPrefix("@") {
            var parts = String(inner.dropFirst()).split(separator: "/", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { return missing }
            if parts[1].hasPrefix("$") { parts[1] = values[TemplateFill.normal(String(parts[1].dropFirst()))] ?? "" }
            guard let record = shared.records.first(where: {
                $0.collection.caseInsensitiveCompare(parts[0]) == .orderedSame &&
                ($0.alias.caseInsensitiveCompare(parts[1]) == .orderedSame || $0.name.caseInsensitiveCompare(parts[1]) == .orderedSame)
            }) else { return missing }
            guard parts.count > 2, !parts[2].isEmpty else { return record.name }
            let field = parts[2].lowercased()
            if field == "name" { return record.name }
            if field == "alias" { return record.alias }
            if let found = record.values.first(where: { $0.key.lowercased() == field }) { return found.value }
            return missing
        }
        if inner.lowercased().hasPrefix("shortcut:") {
            let name = String(inner.dropFirst("shortcut:".count)).trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "\\", with: "")
            if let clip = shared.clips.first(where: { $0.key.lowercased().replacingOccurrences(of: "\\", with: "") == name }) { return clip.text }
            return missing
        }
        return values[TemplateFill.normal(inner)] ?? missing
    }
}

// MARK: - Designs

struct AppDesign: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    /// Template ids of the pages being worked on.
    var pages: [String] = []
    /// Template ids of the released copy of the pages. Apps use these once there are any.
    var releasedPages: [String]? = nil
    /// Starting values for variables.
    var variables: [String: String] = [:]
    var version: Int = 0
    var releasedAt: Date? = nil
    /// png, gif, pdf, docx or html: what a published app delivers.
    var outputFormat: String? = nil
    var appTitle: String? = nil
    var created: Date = Date()
}

@MainActor final class AppDesignStore: ObservableObject {
    static let shared = AppDesignStore()
    @Published private(set) var designs: [AppDesign] = []

    private var fileURL: URL { TemplateStore.shared.directory.appendingPathComponent("designs.json") }

    init() {
        guard let data = try? Data(contentsOf: fileURL), let list = try? JSONDecoder().decode([AppDesign].self, from: data) else { return }
        designs = list
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(designs) { try? data.write(to: fileURL, options: .atomic) }
    }

    func design(id: String?) -> AppDesign? { id.flatMap { key in designs.first { $0.id == key } } }

    func save(_ design: AppDesign) {
        if let index = designs.firstIndex(where: { $0.id == design.id }) { designs[index] = design } else { designs.append(design) }
        persist()
    }

    private func claim(_ template: ImageTemplate?, for designID: String) -> ImageTemplate? {
        guard var page = template else { return nil }
        page.designID = designID
        TemplateStore.shared.save(page)
        return page
    }

    func newBlank(name: String, width: Int, height: Int, colorHex: String = "#FFFFFF") -> AppDesign? {
        var design = AppDesign(name: name)
        guard let page = claim(TemplateStore.shared.blank(name: "Page 1", width: width, height: height, colorHex: colorHex), for: design.id) else { return nil }
        design.pages = [page.id]
        save(design)
        return design
    }

    func newFromPicture(_ image: NSImage, name: String) -> AppDesign? {
        var design = AppDesign(name: name)
        guard let page = claim(TemplateStore.shared.create(from: image, name: "Page 1"), for: design.id) else { return nil }
        design.pages = [page.id]
        save(design)
        return design
    }

    /// Lays a document out on white A4 pages, one text box per paragraph.
    func newFromDocument(name: String, paragraphs: [String]) -> AppDesign? {
        var design = AppDesign(name: name)
        let layout = DocumentLayout.pages(for: paragraphs)
        for (number, boxes) in layout.enumerated() {
            guard var page = claim(TemplateStore.shared.blank(name: "Page \(number + 1)", width: 1654, height: 2339), for: design.id) else { continue }
            page.slots = boxes
            TemplateStore.shared.save(page)
            design.pages.append(page.id)
        }
        guard !design.pages.isEmpty else { return nil }
        save(design)
        return design
    }

    func addPage(to id: String, like template: ImageTemplate) -> ImageTemplate? {
        guard var design = design(id: id),
              let page = claim(TemplateStore.shared.blank(name: "Page \(design.pages.count + 1)", width: template.pixelWidth, height: template.pixelHeight), for: id) else { return nil }
        design.pages.append(page.id)
        save(design)
        return page
    }

    func delete(_ id: String) {
        guard let design = design(id: id) else { return }
        for page in design.pages + (design.releasedPages ?? []) { TemplateStore.shared.delete(page) }
        designs.removeAll { $0.id == id }
        persist()
    }

    /// Freezes the pages as they are now. Apps that use this design switch to the frozen copy.
    func release(_ id: String) -> String {
        guard var design = design(id: id) else { return "That design is missing." }
        for old in design.releasedPages ?? [] { TemplateStore.shared.delete(old) }
        var made: [String] = []
        for pageID in design.pages {
            guard let copy = TemplateStore.shared.duplicate(pageID) else { continue }
            var frozen = copy
            frozen.designID = design.id
            frozen.name = "\(design.name) v\(design.version + 1) page \(made.count + 1)"
            TemplateStore.shared.save(frozen)
            made.append(frozen.id)
        }
        guard !made.isEmpty else { return "Nothing to release yet." }
        design.releasedPages = made
        design.version += 1
        design.releasedAt = Date()
        save(design)
        return "Published version \(design.version). It is on your Home page, and apps that use \u{201C}\(design.name)\u{201D} now use it."
    }

    func activePages(_ design: AppDesign) -> [ImageTemplate] {
        let ids = (design.releasedPages?.isEmpty == false) ? (design.releasedPages ?? []) : design.pages
        return ids.compactMap { TemplateStore.shared.template(id: $0) }
    }
}

// MARK: - Apps using templates or designs

/// An app is linked to either a template id or "design:<id>".
enum TemplateLinks {
    static func designID(_ link: String) -> String? { link.hasPrefix("design:") ? String(link.dropFirst("design:".count)) : nil }

    @MainActor static func design(_ link: String) -> AppDesign? { AppDesignStore.shared.design(id: designID(link)) }

    @MainActor static func pages(for link: String) -> [ImageTemplate] {
        if let design = design(link) { return AppDesignStore.shared.activePages(design) }
        if designID(link) != nil { return [] }
        return TemplateStore.shared.template(id: link).map { [$0] } ?? []
    }

    @MainActor static func title(for link: String) -> String {
        design(link)?.name ?? TemplateStore.shared.template(id: link)?.name ?? "template"
    }

    @MainActor static func fieldKeys(for link: String) -> [String] {
        var keys: [String] = []
        for page in pages(for: link) { for key in page.fieldKeys where !keys.contains(key) { keys.append(key) } }
        for key in (design(link)?.variables.keys.sorted() ?? []) where !keys.contains(key) { keys.append(key) }
        return keys
    }

    @MainActor static func variables(for link: String) -> [String: String] { design(link)?.variables ?? [:] }
}

enum DesignFill {
    /// Combines values so that a later layer replaces an earlier one with the same name, however it is spelled.
    static func merge(_ layers: [String: String]...) -> [String: String] {
        var result: [String: String] = [:]
        for layer in layers { for (key, value) in layer { result[TemplateFill.normal(key)] = value } }
        return result
    }

    /// The finished file of an app that uses a template or design, in the design's output format.
    @MainActor static func renderFile(link: String, values: [String: String], clips: [Clip], directory: URL, stem: String) throws -> URL {
        let pages = TemplateLinks.pages(for: link)
        guard !pages.isEmpty else { throw NSError(domain: "KeyDoTemplates", code: 3, userInfo: [NSLocalizedDescriptionKey: "The template is missing."]) }
        let design = TemplateLinks.design(link)
        let merged = merge(TemplateLinks.variables(for: link), values.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        let format = DesignFormat.from(design?.outputFormat) ?? (pages.count > 1 ? .pdf : .png)
        return try DesignOutput.write(format: format, pages: pages, values: merged, clips: clips, title: design?.appTitle ?? design?.name ?? "Design", directory: directory, stem: stem)
    }
}

// MARK: - Documents (NDA, agreement, letter)

enum DocumentImporter {
    /// The paragraphs of a PDF, Word, RTF, HTML or text file.
    static func paragraphs(from url: URL) -> [String]? {
        var text = ""
        if url.pathExtension.lowercased() == "pdf" {
            text = PDFDocument(url: url)?.string ?? ""
        } else if let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
            text = attributed.string
        } else if let plain = try? String(contentsOf: url, encoding: .utf8) {
            text = plain
        }
        let lines = text.replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [String] = []
        var current = ""
        for line in lines {
            if line.isEmpty {
                if !current.isEmpty { result.append(current); current = "" }
                continue
            }
            if current.isEmpty { current = line; continue }
            let wrapped = current.count > 55 && !".:;?!".contains(current.last ?? " ")
            if wrapped { current += " " + line } else { result.append(current); current = line }
        }
        if !current.isEmpty { result.append(current) }
        return result.isEmpty ? nil : Array(result.prefix(600))
    }
}

enum DocumentLayout {
    private static let pageWidth: CGFloat = 1654, pageHeight: CGFloat = 2339

    private static func isHeading(_ text: String) -> Bool {
        guard text.count < 70 else { return false }
        if text == text.uppercased() && text.rangeOfCharacter(from: .letters) != nil { return true }
        return text.range(of: "^(\\d+[.)]|[A-Z][.)]|Article|Section|Clause)\\s", options: [.regularExpression, .caseInsensitive]) != nil && text.count < 50
    }

    /// One text box per paragraph, flowed down white pages.
    static func pages(for paragraphs: [String]) -> [[TemplateSlot]] {
        var pages: [[TemplateSlot]] = [[]]
        var y: CGFloat = pageHeight * 0.06
        let bottom = pageHeight * 0.94
        let width = pageWidth * 0.82
        var number = 0
        for paragraph in paragraphs {
            let heading = isHeading(paragraph)
            let size: CGFloat = heading ? 36 : 30
            let font = NSFont(name: heading ? "HelveticaNeue-Bold" : "HelveticaNeue", size: size) ?? NSFont.systemFont(ofSize: size)
            let measured = (paragraph as NSString).boundingRect(with: CGSize(width: width, height: 100000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil).height
            let height = min(bottom - pageHeight * 0.06, ceil(measured) + 14)
            if y + height > bottom, !(pages.last ?? []).isEmpty {
                pages.append([])
                y = pageHeight * 0.06
            }
            number += 1
            var slot = TemplateSlot(key: "p\(number)", kind: .text)
            slot.cx = 0.5
            slot.w = Double(width / pageWidth)
            slot.h = Double(height / pageHeight)
            slot.cy = Double((y + height / 2) / pageHeight)
            slot.sample = paragraph
            slot.content = paragraph
            slot.align = "left"
            slot.bold = heading
            slot.fontSize = Double(size / pageHeight)
            slot.colorHex = "#1F2A2E"
            pages[pages.count - 1].append(slot)
            y += height + (heading ? 22 : 16)
        }
        return pages.filter { !$0.isEmpty }
    }
}

// MARK: - Spoken and typed design commands

enum DesignColorTarget { case text, allText, shape, logo, page, theme }

enum DesignAction {
    case undo, release, save, tryIt, designMode
    case goPage(Int), nextPage, previousPage, firstPage, lastPage, addPage
    case addBox(kind: TemplateSlotKind, name: String?, logo: String?)
    case deleteBox
    case select(String), selectOffset(Int)
    case move(dx: Double, dy: Double), center
    case scale(w: Double, h: Double)
    case angleSet(Double), angleAdd(Double)
    case shape(TemplateShape)
    case bold(Bool), italic(Bool), caps(Bool), align(String)
    case font(String, all: Bool)
    case color(String, DesignColorTarget)
    case setText(String)
    case insertToken(String)
    case replace(String, String, variable: String?)
    case variable(String, String)
    case makeVariable(String)
    case imageFrom(String)
    case fontSize(Double), fontScale(Double)
    case outputFormat(DesignFormat)
    case appName(String)
    case unknown(String)
}

enum DesignCommand {
    static let colors: [String: String] = [
        "hot pink": "#FF3D8B", "light pink": "#F8C8DC", "pink": "#EC6AA8", "black": "#111111", "white": "#FFFFFF", "red": "#D63B3B",
        "light blue": "#BFE3F7", "sky blue": "#8FC8EE", "navy": "#1B2A5C", "blue": "#2F6FDB", "dark green": "#1E6B43", "green": "#2E9E5B",
        "orange": "#F28A2E", "yellow": "#F2C230", "purple": "#7B52B8", "violet": "#7B52B8", "gold": "#C9A227", "silver": "#B8BDC4",
        "grey": "#777777", "gray": "#777777", "brown": "#8B5A2B", "teal": "#1A9AA0", "maroon": "#7A1F2B", "cream": "#FFF4DC",
        "peach": "#FFD9C0", "lavender": "#E6DCF7", "mint": "#CFEFD9", "magenta": "#C2188B", "turquoise": "#2CC4C0"
    ]

    private static let numberWords = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]

    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let found = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<found.numberOfRanges).map { found.range(at: $0).location == NSNotFound ? "" : ns.substring(with: found.range(at: $0)) }
    }

    private static func number(_ text: String) -> Int? { Int(text) ?? numberWords[text.lowercased()] }

    private static func clean(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["hey keydo,", "hey keydo", "keydo,", "keydo", "please", "can you", "could you", "now", "also", "then"] {
            if result.lowercased().hasPrefix(prefix + " ") { result = String(result.dropFirst(prefix.count + 1)).trimmingCharacters(in: .whitespaces) }
        }
        while let last = result.last, ".!?,".contains(last) { result.removeLast() }
        return result
    }

    /// One sentence may hold several commands: "go to page 2 then make the title pink".
    static func parse(_ raw: String) -> [DesignAction] {
        let parts = raw.replacingOccurrences(of: ";", with: " then ").components(separatedBy: " then ")
        return parts.map { clean($0) }.filter { !$0.isEmpty }.map { one($0) }
    }

    private static func functionToken(_ name: String) -> String {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.contains("(") { return "{=\(name.uppercased())}" }
        switch lower {
        case "date", "today", "todays date", "today's date", "current date": return "{=TODAY()}"
        case "time", "current time": return "{=time}"
        case "now", "date and time": return "{=now}"
        case "month": return "{=month}"
        case "year": return "{=year}"
        case "day": return "{=day}"
        case "weekday", "day of week": return "{=weekday}"
        default: return "{=\(name.uppercased())()}"
        }
    }

    private static func one(_ s: String) -> DesignAction {
        let l = s.lowercased()

        if l == "undo" || l == "go back" || l == "revert" || l.hasPrefix("undo ") { return .undo }
        if l.contains("release") || l.contains("publish") { return .release }
        if let format = DesignFormat.spoken(l), match("\\b(output|export|deliver|format|download)\\b|save as|make it a|make it an", l) != nil { return .outputFormat(format) }
        if let m = match("^(?:rename|call)\\s+(?:this\\s+|the\\s+)?(?:app|design)\\s+(?:to\\s+|as\\s+)?(.+)$", s) ?? match("^app name\\s+(?:is\\s+)?(.+)$", s) { return .appName(m[1].trimmingCharacters(in: .whitespaces)) }
        if l == "save" || l.hasPrefix("save ") { return .save }
        if l.hasPrefix("try ") || l == "preview" || l.contains("try it") || l == "test it" { return .tryIt }
        if l.contains("design mode") || l == "edit mode" || l == "edit" { return .designMode }

        if let m = match("page\\s*(?:no\\.?|number|#)?\\s*(\\d+|one|two|three|four|five|six|seven|eight|nine|ten)\\b", l), let n = number(m[1]),
           !l.hasPrefix("add") && !l.hasPrefix("delete") { return .goPage(n) }
        if match("^(?:go to |show |open )?(?:the )?next page$", l) != nil { return .nextPage }
        if match("^(?:go to |show |open )?(?:the )?(?:previous|prior|back) page$", l) != nil { return .previousPage }
        if match("^(?:go to |show |open )?(?:the )?first page$", l) != nil { return .firstPage }
        if match("^(?:go to |show |open )?(?:the )?last page$", l) != nil { return .lastPage }
        if match("^(?:add|insert|create|new)\\s+(?:a\\s+|one\\s+)?(?:new\\s+)?page$", l) != nil || l == "new page" { return .addPage }

        // Content: variables, functions, collections, shortcuts
        if let m = match("^replace\\s+(.+?)\\s+with\\s+(?:a\\s+)?variable\\s+(?:called\\s+|named\\s+)?(.+)$", s) {
            let name = m[2].trimmingCharacters(in: .whitespaces)
            return .replace(m[1], "{{\(name)}}", variable: name)
        }
        if let m = match("^replace\\s+(.+?)\\s+with\\s+(?:the\\s+)?(?:function|formula)\\s+(.+)$", s) { return .replace(m[1], functionToken(m[2]), variable: nil) }
        if let m = match("^replace\\s+(.+?)\\s+with\\s+(?:the\\s+)?shortcut\\s+(.+)$", s) { return .replace(m[1], "{{shortcut:\(m[2].trimmingCharacters(in: .whitespaces))}}", variable: nil) }
        if let m = match("^replace\\s+(.+?)\\s+with\\s+(?:the\\s+)?collection\\s+(.+?)\\s+(?:item|record|row|entry)\\s+(.+?)(?:\\s+(?:field|value)\\s+(.+))?$", s) {
            let field = m.count > 4 && !m[4].isEmpty ? "/" + m[4] : ""
            return .replace(m[1], "{{@\(m[2])/\(m[3])\(field)}}", variable: nil)
        }
        if let m = match("^replace\\s+(.+?)\\s+with\\s+(.+)$", s) { return .replace(m[1], m[2], variable: nil) }
        if let m = match("^(?:make|turn)\\s+(?:this|it|that|selected|the box)\\s+(?:into\\s+)?(?:a\\s+)?variable\\s+(?:called\\s+|named\\s+)?(.+)$", s) { return .makeVariable(m[1].trimmingCharacters(in: .whitespaces)) }
        if let m = match("^(?:set\\s+)?variable\\s+(.+?)\\s+(?:to|is|equals|=)\\s+(.+)$", s) { return .variable(m[1].trimmingCharacters(in: .whitespaces), m[2]) }
        if let m = match("^(?:put|insert|add|use)\\s+(?:the\\s+)?variable\\s+(.+)$", s) { return .insertToken("{{\(m[1].trimmingCharacters(in: .whitespaces))}}") }
        if let m = match("^(?:put|insert|add|use)\\s+(?:the\\s+)?(?:function|formula)\\s+(.+)$", s) { return .insertToken(functionToken(m[1])) }
        if let m = match("^(?:put|insert|add|use)\\s+(?:the\\s+)?collection\\s+(.+?)\\s+(?:item|record|row|entry)\\s+(.+?)(?:\\s+(?:field|value)\\s+(.+))?$", s) {
            let field = m.count > 3 && !m[3].isEmpty ? "/" + m[3] : ""
            return .insertToken("{{@\(m[1])/\(m[2])\(field)}}")
        }
        if let m = match("^(?:put|insert|add|use)\\s+(?:the\\s+)?shortcut\\s+(.+)$", s) { return .insertToken("{{shortcut:\(m[1].trimmingCharacters(in: .whitespaces))}}") }
        if let m = match("^(?:use|put|set)\\s+(?:the\\s+)?(?:image|picture|photo|video)\\s+(?:from\\s+)?(?:shortcut\\s+)?(.+)$", s) { return .imageFrom(m[1].trimmingCharacters(in: .whitespaces)) }
        if let m = match("^(?:set|change|make|write|type|put)\\s+(?:the\\s+)?(?:text|title|heading|content|words?)\\s+(?:to|as|with|say|says)?\\s*[:\\-]?\\s*(.+)$", s) { return .setText(m[1]) }
        if let m = match("^(?:write|type|say)\\s+(.+)$", s) { return .setText(m[1]) }

        // Boxes
        if let m = match("^(?:add|insert|create|put|place)\\s+(?:a\\s+|an\\s+|one\\s+|new\\s+)*(text|heading|title|name|signature|picture|photo|image|video|logo|icon)(?:\\s+box|\\s+field)?(?:\\s+(?:called|named|for|of)?\\s*(.+))?$", s) {
            let word = m[1].lowercased()
            let extra = m.count > 2 ? m[2].trimmingCharacters(in: .whitespaces) : ""
            switch word {
            case "picture", "photo", "image", "video": return .addBox(kind: .image, name: extra.isEmpty ? nil : extra, logo: nil)
            case "logo", "icon":
                let found = TemplateLogos.builtIn.first { !extra.isEmpty && ($0.name.lowercased() == extra.lowercased() || extra.lowercased().contains($0.name.lowercased())) }?.name
                return .addBox(kind: .logo, name: nil, logo: found)
            default: return .addBox(kind: .text, name: extra.isEmpty ? (word == "text" ? nil : word) : extra, logo: nil)
            }
        }
        if match("^(?:delete|remove|erase)\\s+(?:this|the|selected)?\\s*(?:box|field|item)$", l) != nil { return .deleteBox }
        if l == "next box" { return .selectOffset(1) }
        if l == "previous box" || l == "last box" { return .selectOffset(-1) }
        if let m = match("^(?:select|choose|pick|click on|click)\\s+(?:the\\s+)?(?:box\\s+)?(.+?)(?:\\s+box)?$", s) { return .select(m[1]) }

        if let m = match("^move\\s+(?:it\\s+|this\\s+)?(left|right|up|down)(?:\\s+(?:by\\s+)?(\\d+))?", l) {
            let amount = (Double(m[2]) ?? 2) * 0.01
            switch m[1] {
            case "left": return .move(dx: -amount, dy: 0)
            case "right": return .move(dx: amount, dy: 0)
            case "up": return .move(dx: 0, dy: -amount)
            default: return .move(dx: 0, dy: amount)
            }
        }
        if l == "center" || l == "centre" || l == "center it" || l == "centre it" { return .center }

        if let m = match("(?:rotate|turn|tilt)\\s+(?:it\\s+|this\\s+)?(?:by\\s+)?(-?\\d+)", l) { return .angleAdd(Double(m[1]) ?? 0) }
        if l.contains("rotate left") || l.contains("tilt left") { return .angleAdd(-15) }
        if l.contains("rotate right") || l.contains("tilt right") { return .angleAdd(15) }
        if let m = match("angle\\s+(?:to\\s+|of\\s+)?(-?\\d+)", l) { return .angleSet(Double(m[1]) ?? 0) }
        if l.contains("straighten") || l.contains("no angle") || l.contains("reset angle") { return .angleSet(0) }

        // Look: colours, fonts, style
        var colorName: String?
        for name in colors.keys.sorted(by: { $0.count > $1.count }) where l.contains(name) { colorName = name; break }
        var hex = colorName.flatMap { colors[$0] }
        if let m = match("(#[0-9a-f]{6})", l) { hex = m[1].uppercased() }
        if let hex {
            let target: DesignColorTarget
            if l.contains("theme") || l.contains("mode") { target = .theme }
            else if l.contains("page") || l.contains("background") || l.contains("backdrop") || l.contains("paper") { target = .page }
            else if l.contains("shape") || l.contains("behind") || l.contains("fill") || l.contains("highlight") || l.contains(" box") { target = .shape }
            else if l.contains("logo") || l.contains("icon") { target = .logo }
            else if l.contains("all") || l.contains("every") || l.contains("whole") { target = .allText }
            else { target = .text }
            return .color(hex, target)
        }

        if let m = match("(?:font\\s*size|text\\s*size|size)\\s*(?:to|of|is)?\\s*(\\d+)", l) ?? match("(\\d+)\\s*(?:pt|point|points)\\b", l) { return .fontSize(Double(m[1]) ?? 12) }
        if (l.contains("font") || l.contains("text") || l.contains("letter")) && match("\\b(bigger|larger|increase|enlarge)\\b", l) != nil { return .fontScale(1.15) }
        if (l.contains("font") || l.contains("text") || l.contains("letter")) && match("\\b(smaller|decrease|reduce|shrink)\\b", l) != nil { return .fontScale(0.87) }
        if l.contains("same font") || l.contains("fix font") || l.contains("correct font") || l.contains("fix the font") { return .font("", all: true) }
        if let m = match("(?:font|typeface)\\s+(?:to\\s+|as\\s+|is\\s+)?(.+)$", s) { return .font(m[1].trimmingCharacters(in: .whitespaces), all: l.contains("all") || l.contains("every")) }
        if let m = match("(?:use|change to|switch to|make it)\\s+(.+?)\\s+font", s) { return .font(m[1].trimmingCharacters(in: .whitespaces), all: l.contains("all") || l.contains("every")) }

        if match("(?:not bold|remove bold|unbold|no bold)", l) != nil { return .bold(false) }
        if l.contains("bold") { return .bold(true) }
        if match("(?:not italic|remove italic|no italic)", l) != nil { return .italic(false) }
        if l.contains("italic") { return .italic(true) }
        if l.contains("lowercase") || l.contains("normal case") { return .caps(false) }
        if l.contains("capital") || l.contains("uppercase") || l.contains("all caps") { return .caps(true) }
        if let m = match("(?:align(?:ed)?\\s+(?:to\\s+the\\s+|to\\s+)?(left|right|center|centre|middle))|(?:(left|right|center|centre|middle)\\s+align)", l) {
            let word = (m[1].isEmpty ? m[2] : m[1])
            return .align(word == "left" ? "left" : word == "right" ? "right" : "center")
        }

        if let m = match("\\b(circle|round|oval|square|rectangle|triangle|random|freeform)\\b", l) {
            switch m[1] {
            case "circle", "round", "oval": return .shape(.circle)
            case "square": return .shape(.square)
            case "rectangle": return .shape(.rectangle)
            case "triangle": return .shape(.triangle)
            default: return .shape(.random)
            }
        }

        if match("\\b(bigger|larger|increase|grow|enlarge)\\b", l) != nil { return .scale(w: 1.15, h: 1.15) }
        if match("\\b(smaller|shrink|reduce|decrease)\\b", l) != nil { return .scale(w: 0.87, h: 0.87) }
        if l.contains("wider") || l.contains("broader") { return .scale(w: 1.15, h: 1) }
        if l.contains("narrower") { return .scale(w: 0.87, h: 1) }
        if l.contains("taller") { return .scale(w: 1, h: 1.15) }
        if l.contains("shorter") { return .scale(w: 1, h: 0.87) }

        return .unknown(s)
    }

    static let help = "Try: \u{201C}go to page 2\u{201D}, \u{201C}make the text pink\u{201D}, \u{201C}background black\u{201D}, \u{201C}font Georgia\u{201D}, \u{201C}add text box called amount\u{201D}, \u{201C}make it a circle\u{201D}, \u{201C}rotate 15\u{201D}, \u{201C}replace Acme Ltd with variable company\u{201D}, \u{201C}put function date\u{201D}, \u{201C}font size 18\u{201D}, \u{201C}output PDF\u{201D}, \u{201C}publish\u{201D}."
}

// MARK: - AppDesigner screens

struct AppDesignerView: View {
    var wishDirectory: URL? = nil
    var clips: [Clip] = []
    var records: [CollectionRecord] = []
    var collections: [String] = []
    var definitions: [CollectionDefinition] = []
    @ObservedObject private var designs = AppDesignStore.shared
    @ObservedObject private var templates = TemplateStore.shared
    @State private var tab = 0
    @State private var editingID: String?
    @State private var pageIndex = 0
    @State private var usingID: String?
    @State private var deleteID: String?
    @State private var runningID: String?
    @State private var message = ""

    var body: some View {
        Group {
            if let id = editingID, designs.design(id: id) != nil {
                AppDesignEditor(designID: id, pageIndex: $pageIndex, onClose: { editingID = nil })
            } else {
                gallery
            }
        }
        .onAppear { sync() }
        .onChange(of: clips.count) { _, _ in sync() }
        .onChange(of: records.count) { _, _ in sync() }
    }

    private func sync() {
        if !clips.isEmpty { AppDesignContext.shared.clips = clips }
        if !records.isEmpty { AppDesignContext.shared.records = records }
        if !collections.isEmpty { AppDesignContext.shared.collections = collections }
        if !definitions.isEmpty { AppDesignContext.shared.definitions = definitions }
    }

    private var gallery: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Designs").tag(0)
                Text("Templates (single pictures)").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 380).padding(.top, 12)
            if tab == 1 {
                TemplateLibraryView(wishDirectory: wishDirectory)
            } else {
                designsGallery
            }
        }
    }

    private var designsGallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BuilderHeader(symbol: "paintpalette.fill", title: "AppDesigner",
                              subtitle: "Design apps by voice. Start from a picture, a bill, or an NDA or agreement, then put variables, shortcuts, collections, functions and media in its boxes.") {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(StarterLayouts.Kind.allCases) { kind in
                                Button { startLayout(kind) } label: { Label(kind.title + ": " + kind.detail, systemImage: kind.symbol) }
                            }
                        } label: { Label("Ready layouts", systemImage: "sparkles.rectangle.stack") }
                            .menuStyle(.borderlessButton).fixedSize()
                        Button { fromDocument() } label: { Label("From document", systemImage: "doc.text") }
                            .buttonStyle(.borderedProminent).tint(Butter.coral)
                        Button { fromPicture() } label: { Label("From picture", systemImage: "photo") }.buttonStyle(.bordered)
                        Menu {
                            Button("A4 page") { blank("New design", 1654, 2339) }
                            Button("Invoice") { blank("Invoice", 1654, 2339) }
                            Button("Square post") { blank("Post", 1080, 1080) }
                            Button("Story") { blank("Story", 1080, 1920) }
                            Button("Wide certificate") { blank("Certificate", 2000, 1414) }
                        } label: { Label("Blank", systemImage: "doc") }
                            .menuStyle(.borderlessButton).fixedSize()
                    }
                }
                if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(Butter.cocoa.opacity(0.8)) }
                if designs.designs.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "paintpalette").font(.system(size: 40)).foregroundStyle(Butter.coral)
                        Text("No designs yet").font(.system(size: 17, weight: .semibold)).foregroundStyle(Butter.cocoa)
                        Text("Upload an NDA, agreement, bill or frame, or start blank. Then say what to change.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 50)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Butter.cream))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 300), spacing: 14)], spacing: 14) {
                        ForEach(designs.designs) { design in card(design) }
                    }
                }
                Text("Press the mic inside a design and say things like \u{201C}go to page 2\u{201D}, \u{201C}make it pink\u{201D} or \u{201C}replace Acme Ltd with variable company\u{201D}. When you are happy, say \u{201C}release\u{201D}.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(22)
        }
        .sheet(item: Binding(get: { usingID.map { DesignSheetID(id: $0) } }, set: { usingID = $0?.id })) { item in
            TemplateUseSheet(templateID: item.id, wishDirectory: wishDirectory)
        }
        .sheet(item: Binding(get: { runningID.map { DesignSheetID(id: $0) } }, set: { runningID = $0?.id })) { item in
            AppDesignRunView(designID: item.id, onClose: { runningID = nil }).frame(minWidth: 940, minHeight: 640)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in dropFiles(providers) }
        .alert("Delete this design?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button("Delete", role: .destructive) { if let id = deleteID { designs.delete(id) }; deleteID = nil }
            Button("Cancel", role: .cancel) { deleteID = nil }
        } message: { Text("Its pages and released copy are deleted. Apps that use it go back to their normal look.") }
    }

    private func card(_ design: AppDesign) -> some View {
        let first = design.pages.first.flatMap { templates.template(id: $0) }
        return VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Rectangle().fill(Color(white: 0.94))
                if let first, let picture = templates.basePicture(for: first) {
                    Image(nsImage: TemplateRenderer.render(first, base: picture, texts: nil, images: [:], useSamples: true, maxSide: 500) ?? picture)
                        .resizable().scaledToFit().padding(6)
                }
            }
            .frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture { open(design) }
            Text(design.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Butter.cocoa).lineLimit(1)
            Text("\(design.pages.count) page\(design.pages.count == 1 ? "" : "s") \u{00B7} " + (design.version > 0 ? "released v\(design.version)" : "not released"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button("Design") { open(design) }.buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.small)
                if design.version > 0 { Button("Run") { runningID = design.id }.buttonStyle(.bordered).controlSize(.small) }
                Button("Use in apps") { usingID = "design:" + design.id }.buttonStyle(.bordered).controlSize(.small)
                Spacer()
                Button { deleteID = design.id } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.red.opacity(0.8))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Butter.honey.opacity(0.7), lineWidth: 1))
    }

    private func open(_ design: AppDesign) { pageIndex = 0; editingID = design.id }

    private func startLayout(_ kind: StarterLayouts.Kind) {
        if let made = StarterLayouts.make(kind) { open(made) } else { message = "That layout could not be made." }
    }

    /// Dropping a picture or a document anywhere on the gallery starts a design from it.
    private func dropFiles(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) } else if let direct = item as? URL { url = direct }
            guard let url else { return }
            DispatchQueue.main.async {
                let ext = url.pathExtension.lowercased()
                if ["png", "jpg", "jpeg", "heic", "webp", "tiff", "gif"].contains(ext), let image = NSImage(contentsOf: url) {
                    if let made = designs.newFromPicture(image, name: url.deletingPathExtension().lastPathComponent) { open(made) }
                } else if let paragraphs = DocumentImporter.paragraphs(from: url) {
                    if let made = designs.newFromDocument(name: url.deletingPathExtension().lastPathComponent, paragraphs: paragraphs) { open(made) }
                } else {
                    message = "That file could not be used. Drop a picture, PDF, Word or text file."
                }
            }
        }
        return true
    }

    private func blank(_ name: String, _ width: Int, _ height: Int) {
        if let made = designs.newBlank(name: name, width: width, height: height) { open(made) } else { message = "The page could not be made." }
    }

    private func fromPicture() {
        guard let image = TemplateDialogs.openImage(title: "Choose a bill, invoice, frame or any picture") else { return }
        if let made = designs.newFromPicture(image, name: "New design") { open(made) } else { message = "That picture could not be opened." }
    }

    private func fromDocument() {
        let panel = NSOpenPanel()
        panel.title = "Choose an NDA, agreement or any document"
        panel.allowedContentTypes = [.pdf, .plainText, .rtf, .html, UTType(filenameExtension: "docx") ?? .data, UTType(filenameExtension: "doc") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let paragraphs = DocumentImporter.paragraphs(from: url) else { message = "No text could be read from that file."; return }
        let name = url.deletingPathExtension().lastPathComponent
        if let made = designs.newFromDocument(name: name, paragraphs: paragraphs) {
            message = "Made \(made.pages.count) page\(made.pages.count == 1 ? "" : "s") from \(url.lastPathComponent). Say \u{201C}replace <words> with variable <name>\u{201D} to turn text into variables."
            open(made)
        } else { message = "The document could not be laid out." }
    }
}

private struct DesignSheetID: Identifiable { let id: String }

struct AppDesignEditor: View {
    var designID: String
    @Binding var pageIndex: Int
    var onClose: () -> Void
    @ObservedObject private var designs = AppDesignStore.shared
    @ObservedObject private var templates = TemplateStore.shared

    var body: some View {
        if let design = designs.design(id: designID), !design.pages.isEmpty {
            let index = min(max(0, pageIndex), design.pages.count - 1)
            if let page = templates.template(id: design.pages[index]) {
                TemplateDesignerView(
                    template: page, onClose: onClose,
                    pageInfo: (index + 1, design.pages.count),
                    onGoToPage: { pageIndex = $0 },
                    onAddPage: {
                        if let new = designs.addPage(to: designID, like: page), let updated = designs.design(id: designID), let at = updated.pages.firstIndex(of: new.id) { pageIndex = at }
                    },
                    onRelease: { designs.release(designID) },
                    variables: design.variables,
                    onVariablesChange: { values in
                        if var current = designs.design(id: designID) { current.variables = values; designs.save(current) }
                    },
                    onReplaceElsewhere: { old, new in
                        var changed = 0
                        for id in design.pages where id != page.id {
                            guard var other = templates.template(id: id) else { continue }
                            var touched = false
                            for slot in other.slots.indices where other.slots[slot].kind == .text {
                                let source = other.slots[slot].content ?? other.slots[slot].sample
                                if source.range(of: old, options: .caseInsensitive) != nil {
                                    other.slots[slot].content = source.replacingOccurrences(of: old, with: new, options: .caseInsensitive)
                                    changed += 1
                                    touched = true
                                }
                            }
                            if touched { templates.save(other) }
                        }
                        return changed
                    },
                    designTitle: design.appTitle ?? design.name,
                    outputFormat: design.outputFormat,
                    onOutputFormatChange: { format in
                        if var current = designs.design(id: designID) { current.outputFormat = format; designs.save(current) }
                    },
                    onMakeFile: { values in
                        guard let current = designs.design(id: designID) else { return "The design is missing." }
                        let drafts = current.pages.compactMap { templates.template(id: $0) }
                        guard !drafts.isEmpty else { return "The design has no pages." }
                        let format = DesignFormat.from(current.outputFormat) ?? (drafts.count > 1 ? .pdf : .png)
                        let merged = DesignFill.merge(current.variables, values.filter { !$0.value.isEmpty })
                        let stem = current.name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
                        do {
                            let file = try DesignOutput.write(format: format, pages: drafts, values: merged, clips: AppDesignContext.shared.clips, title: current.name,
                                                              directory: FileManager.default.temporaryDirectory, stem: (stem.isEmpty ? "Design" : stem) + "-" + String(UUID().uuidString.prefix(4)))
                            let panel = NSSavePanel()
                            panel.nameFieldStringValue = file.lastPathComponent
                            guard panel.runModal() == .OK, let destination = panel.url else { return "Cancelled." }
                            try? FileManager.default.removeItem(at: destination)
                            try FileManager.default.copyItem(at: file, to: destination)
                            return "Saved \(destination.lastPathComponent)."
                        } catch { return error.localizedDescription }
                    },
                    onRename: { name in
                        if var current = designs.design(id: designID) { current.name = name; current.appTitle = name; designs.save(current) }
                    }
                )
                .id(page.id)
            } else {
                missing
            }
        } else {
            missing
        }
    }

    private var missing: some View {
        VStack(spacing: 10) {
            Text("This design has no pages.").foregroundStyle(.secondary)
            Button("Back") { onClose() }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
