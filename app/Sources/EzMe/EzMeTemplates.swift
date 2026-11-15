// Photo templates: any picture (a bill, an invoice, a challan, a frame, a poster) becomes a template.
// Text is removed from the picture, then named boxes are placed on it: text, picture or logo boxes in a square,
// rectangle, circle, triangle or free shape, each with its own angle. WishBuilder and AppBuilder apps fill the
// boxes by name, and the text always shrinks to fit its box.
import SwiftUI
import AppKit
import Vision

// MARK: - Model

enum TemplateSlotKind: String, Codable, CaseIterable, Hashable {
    case text, image, logo

    var title: String {
        switch self {
        case .text: return "Text"
        case .image: return "Picture"
        case .logo: return "Logo"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "textformat"
        case .image: return "photo"
        case .logo: return "seal"
        }
    }
}

enum TemplateShape: String, Codable, CaseIterable, Hashable {
    case rectangle, square, circle, triangle, random

    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .square: return "Square"
        case .circle: return "Circle"
        case .triangle: return "Triangle"
        case .random: return "Free shape"
        }
    }

    var symbol: String {
        switch self {
        case .rectangle: return "rectangle"
        case .square: return "square"
        case .circle: return "circle"
        case .triangle: return "triangle"
        case .random: return "scribble.variable"
        }
    }
}

/// One place on the template. Position and size are fractions of the picture (0 to 1), from the top left.
struct TemplateSlot: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    /// The name apps use to fill this box, like name, amount or photo.
    var key: String
    var kind: TemplateSlotKind = .text
    var shape: TemplateShape = .rectangle
    var cx: Double = 0.5
    var cy: Double = 0.5
    var w: Double = 0.3
    var h: Double = 0.08
    /// Degrees, clockwise.
    var angle: Double = 0
    var sample: String = "Your text"
    var fontName: String = "Helvetica Neue"
    /// 0 means "as large as fits". Otherwise the biggest size, as a fraction of the picture height.
    var fontSize: Double = 0
    var bold: Bool = false
    var italic: Bool = false
    var colorHex: String = "#1F2A2E"
    /// left, center or right
    var align: String = "center"
    var uppercase: Bool = false
    /// A colour painted inside the shape, behind the text. Empty for none.
    var fillHex: String = ""
    /// For logo boxes: a built-in logo name, or "file:name.png" for one you uploaded.
    var logo: String = "Star"
    /// For free shapes: corner points as x,y pairs inside the box (0 to 1).
    var points: [Double] = TemplateSlot.defaultPoints

    static let defaultPoints: [Double] = [0.5, 0.0, 1.0, 0.38, 0.82, 1.0, 0.18, 1.0, 0.0, 0.38]
}

struct ImageTemplate: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    /// The picture the boxes sit on (text already removed, if the person did that).
    var file: String
    var originalFile: String
    var pixelWidth: Int
    var pixelHeight: Int
    var slots: [TemplateSlot] = []
    var created: Date = Date()

    var textKeys: [String] { slots.filter { $0.kind == .text }.map { $0.key } }
    var imageKeys: [String] { slots.filter { $0.kind == .image }.map { $0.key } }
    var fieldKeys: [String] { slots.filter { $0.kind != .logo }.map { $0.key } }
}

// MARK: - Colours

extension NSColor {
    convenience init(templateHex hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var templateHex: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(round(color.redComponent * 255)), Int(round(color.greenComponent * 255)), Int(round(color.blueComponent * 255)))
    }
}

// MARK: - Shapes

enum TemplateOutline {
    case rect(CGRect)
    case ellipse(CGRect)
    case polygon([CGPoint])
}

enum TemplateGeometry {
    /// The outline of a shape inside a box. y grows downward.
    static func outline(_ shape: TemplateShape, points: [Double], in box: CGRect) -> TemplateOutline {
        switch shape {
        case .rectangle:
            return .rect(box)
        case .square:
            return .rect(centredSquare(in: box))
        case .circle:
            return .ellipse(centredSquare(in: box))
        case .triangle:
            return .polygon([CGPoint(x: box.midX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)])
        case .random:
            let list = points.count >= 6 && points.count % 2 == 0 ? points : TemplateSlot.defaultPoints
            var result: [CGPoint] = []
            var index = 0
            while index + 1 < list.count {
                result.append(CGPoint(x: box.minX + box.width * CGFloat(list[index]), y: box.minY + box.height * CGFloat(list[index + 1])))
                index += 2
            }
            return .polygon(result)
        }
    }

    static func centredSquare(in box: CGRect) -> CGRect {
        let side = min(box.width, box.height)
        return CGRect(x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side)
    }

    /// The part of the shape where text can sit without touching the edge.
    static func textBox(_ shape: TemplateShape, in box: CGRect) -> CGRect {
        switch shape {
        case .rectangle:
            return box.insetBy(dx: box.width * 0.02, dy: box.height * 0.04)
        case .square:
            return centredSquare(in: box).insetBy(dx: box.width * 0.03, dy: box.width * 0.03)
        case .circle:
            let square = centredSquare(in: box)
            let side = square.width * 0.7
            return CGRect(x: square.midX - side / 2, y: square.midY - side / 2, width: side, height: side)
        case .triangle:
            let width = box.width * 0.5
            let height = box.height * 0.5
            return CGRect(x: box.midX - width / 2, y: box.minY + box.height * 0.42, width: width, height: height)
        case .random:
            let width = box.width * 0.62
            let height = box.height * 0.62
            return CGRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
        }
    }

    static func bezier(_ outline: TemplateOutline) -> NSBezierPath {
        switch outline {
        case .rect(let rect):
            return NSBezierPath(rect: rect)
        case .ellipse(let rect):
            return NSBezierPath(ovalIn: rect)
        case .polygon(let points):
            let path = NSBezierPath()
            if let first = points.first {
                path.move(to: first)
                for point in points.dropFirst() { path.line(to: point) }
                path.close()
            }
            return path
        }
    }
}

/// The same outline, for drawing in the designer.
struct TemplateOutlineShape: Shape {
    var shape: TemplateShape
    var points: [Double]

    func path(in rect: CGRect) -> Path {
        switch TemplateGeometry.outline(shape, points: points, in: rect) {
        case .rect(let box):
            return Path(box)
        case .ellipse(let box):
            return Path(ellipseIn: box)
        case .polygon(let list):
            var path = Path()
            if let first = list.first {
                path.move(to: first)
                for point in list.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
            }
            return path
        }
    }
}

// MARK: - Logos

enum TemplateLogos {
    /// Built-in logos: a name and the symbol drawn for it.
    static let builtIn: [(name: String, symbol: String)] = [
        ("Star", "star.fill"), ("Heart", "heart.fill"), ("Seal", "seal.fill"), ("Verified", "checkmark.seal.fill"),
        ("Rupee", "indianrupeesign.circle.fill"), ("Building", "building.2.fill"), ("Shop", "storefront.fill"),
        ("Cart", "cart.fill"), ("Truck", "box.truck.fill"), ("Parcel", "shippingbox.fill"), ("Phone", "phone.fill"),
        ("Mail", "envelope.fill"), ("Globe", "globe"), ("Location", "mappin.circle.fill"), ("Receipt", "doc.text.fill"),
        ("Gift", "gift.fill"), ("Camera", "camera.fill"), ("Briefcase", "briefcase.fill"), ("Leaf", "leaf.fill"),
        ("Flame", "flame.fill"), ("Bolt", "bolt.fill"), ("Shield", "checkmark.shield.fill"), ("Medal", "rosette"),
        ("Cake", "birthday.cake.fill"), ("Sparkles", "sparkles"), ("Home", "house.fill"), ("Person", "person.crop.circle.fill"),
        ("Card", "creditcard.fill"), ("Cart bag", "bag.fill"), ("Ticket", "ticket.fill")
    ]

    private static var cache: [String: NSImage] = [:]

    @MainActor static func image(_ name: String, colorHex: String) -> NSImage? {
        let key = name + "|" + colorHex
        if let cached = cache[key] { return cached }
        var result: NSImage?
        if name.hasPrefix("file:") {
            result = NSImage(contentsOf: TemplateStore.shared.logoURL(String(name.dropFirst(5))))
        } else if name == "KeyDo" {
            result = keyDoIconImage()
        } else if let symbol = builtIn.first(where: { $0.name == name })?.symbol {
            result = tinted(symbol: symbol, color: NSColor(templateHex: colorHex))
        }
        if let result { cache[key] = result }
        return result
    }

    private static func tinted(symbol: String, color: NSColor) -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: 256, weight: .semibold)
        guard let sized = base.withSymbolConfiguration(configuration) else { return nil }
        let size = sized.size
        let result = NSImage(size: size)
        result.lockFocus()
        sized.draw(in: NSRect(origin: .zero, size: size))
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        result.unlockFocus()
        return result
    }
}

// MARK: - Storage

@MainActor final class TemplateStore: ObservableObject {
    static let shared = TemplateStore()

    @Published private(set) var templates: [ImageTemplate] = []
    let directory: URL
    private var pictureCache: [String: NSImage] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("EzMe/Templates", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: logoDirectory, withIntermediateDirectories: true)
        load()
    }

    private var indexURL: URL { directory.appendingPathComponent("templates.json") }
    private var logoDirectory: URL { directory.appendingPathComponent("Logos", isDirectory: true) }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([ImageTemplate].self, from: data) else { return }
        templates = list
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(templates) { try? data.write(to: indexURL, options: .atomic) }
    }

    func template(id: String?) -> ImageTemplate? {
        guard let id, !id.isEmpty else { return nil }
        return templates.first { $0.id == id }
    }

    func url(_ file: String) -> URL { directory.appendingPathComponent(file) }
    func logoURL(_ file: String) -> URL { logoDirectory.appendingPathComponent(file) }

    func picture(_ file: String) -> NSImage? {
        if let cached = pictureCache[file] { return cached }
        guard let image = NSImage(contentsOf: url(file)) else { return nil }
        pictureCache[file] = image
        return image
    }

    func basePicture(for template: ImageTemplate) -> NSImage? { picture(template.file) }

    // MARK: Changing templates

    @discardableResult func create(from image: NSImage, name: String) -> ImageTemplate? {
        let fitted = TemplateImages.limited(image, maxSide: 3200)
        guard let data = TemplateImages.png(fitted) else { return nil }
        let id = UUID().uuidString
        let file = id + ".png"
        let original = id + "-original.png"
        do {
            try data.write(to: url(file), options: .atomic)
            try data.write(to: url(original), options: .atomic)
        } catch { return nil }
        let size = TemplateImages.pixelSize(fitted)
        let template = ImageTemplate(id: id, name: name, file: file, originalFile: original, pixelWidth: Int(size.width), pixelHeight: Int(size.height))
        templates.append(template)
        persist()
        return template
    }

    func blank(name: String, width: Int, height: Int, colorHex: String = "#FFFFFF") -> ImageTemplate? {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(templateHex: colorHex).setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return create(from: image, name: name)
    }

    func save(_ template: ImageTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) { templates[index] = template } else { templates.append(template) }
        persist()
    }

    /// Writes a new picture for the template (after text was erased) and keeps the original for "Start again".
    func setPicture(_ image: NSImage, for template: ImageTemplate) {
        guard let data = TemplateImages.png(image) else { return }
        try? data.write(to: url(template.file), options: .atomic)
        pictureCache[template.file] = image
        objectWillChange.send()
    }

    /// Makes a new uploaded picture the one "Start again" returns to.
    func setOriginal(_ image: NSImage, for template: ImageTemplate) {
        guard let data = TemplateImages.png(image) else { return }
        try? data.write(to: url(template.originalFile), options: .atomic)
    }

    func original(for template: ImageTemplate) -> NSImage? { NSImage(contentsOf: url(template.originalFile)) }

    func delete(_ id: String) {
        guard let template = template(id: id) else { return }
        try? FileManager.default.removeItem(at: url(template.file))
        try? FileManager.default.removeItem(at: url(template.originalFile))
        pictureCache[template.file] = nil
        templates.removeAll { $0.id == id }
        persist()
    }

    @discardableResult func duplicate(_ id: String) -> ImageTemplate? {
        guard var copy = template(id: id), let picture = picture(copy.file) else { return nil }
        guard let made = create(from: picture, name: copy.name + " copy") else { return nil }
        copy.id = made.id
        copy.file = made.file
        copy.originalFile = made.originalFile
        copy.name = made.name
        copy.created = Date()
        save(copy)
        return copy
    }

    // MARK: Logos

    var uploadedLogos: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: logoDirectory.path)) ?? []
        return names.filter { ["png", "jpg", "jpeg", "heic", "webp"].contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
    }

    func addLogo(from source: URL) -> String? {
        let name = String(UUID().uuidString.prefix(6)) + "-" + source.lastPathComponent
        do {
            try FileManager.default.copyItem(at: source, to: logoURL(name))
            objectWillChange.send()
            return "file:" + name
        } catch { return nil }
    }

    // MARK: Linking templates to apps

    static func wishTemplateID(appID: String) -> String { UserDefaults.standard.string(forKey: "ezmeTemplateFor.wish." + appID) ?? "" }
    static func setWishTemplate(_ id: String, appID: String) { UserDefaults.standard.set(id, forKey: "ezmeTemplateFor.wish." + appID) }
    static func builderTemplateID(app: String) -> String { UserDefaults.standard.string(forKey: "ezmeBuilderPhotoTemplate." + app) ?? "" }
    static func setBuilderTemplate(_ id: String, app: String) { UserDefaults.standard.set(id, forKey: "ezmeBuilderPhotoTemplate." + app) }
}

// MARK: - Image helpers

enum TemplateImages {
    static func cgImage(_ image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    static func pixelSize(_ image: NSImage) -> CGSize {
        if let cg = cgImage(image) { return CGSize(width: cg.width, height: cg.height) }
        return image.size
    }

    static func limited(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let size = pixelSize(image)
        let longest = max(size.width, size.height)
        guard longest > maxSide, let cg = cgImage(image) else { return image }
        let scale = maxSide / longest
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let rep = bitmap(width: width, height: height), let context = NSGraphicsContext(bitmapImageRep: rep) else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.interpolationQuality = .high
        context.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: NSSize(width: width, height: height))
        result.addRepresentation(rep)
        return result
    }

    static func bitmap(width: Int, height: Int) -> NSBitmapImageRep? {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    }

    static func png(_ image: NSImage) -> Data? {
        if let cg = cgImage(image) {
            return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static func fromPasteboard() -> NSImage? {
        NSImage(pasteboard: NSPasteboard.general)
    }
}

// MARK: - Drawing the template

enum TemplateRenderer {
    /// Draws the picture and every box. With `useSamples`, empty text boxes show their sample text and empty
    /// picture boxes show a grey placeholder, which is what the designer needs.
    @MainActor static func renderRep(_ template: ImageTemplate, base: NSImage, texts: [String: String]?, images: [String: NSImage],
                                     useSamples: Bool, maxSide: CGFloat?) -> NSBitmapImageRep? {
        var width = CGFloat(template.pixelWidth), height = CGFloat(template.pixelHeight)
        if let maxSide, max(width, height) > maxSide {
            let scale = maxSide / max(width, height)
            width = (width * scale).rounded(); height = (height * scale).rounded()
        }
        guard width > 0, height > 0, let rep = TemplateImages.bitmap(width: Int(width), height: Int(height)),
              let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let cg = graphics.cgContext
        cg.translateBy(x: 0, y: height)
        cg.scaleBy(x: 1, y: -1)
        let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = flipped
        flipped.imageInterpolation = .high
        defer { NSGraphicsContext.restoreGraphicsState() }

        base.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)

        for slot in template.slots {
            cg.saveGState()
            cg.translateBy(x: CGFloat(slot.cx) * width, y: CGFloat(slot.cy) * height)
            cg.rotate(by: CGFloat(slot.angle) * .pi / 180)
            let box = CGRect(x: -CGFloat(slot.w) * width / 2, y: -CGFloat(slot.h) * height / 2, width: CGFloat(slot.w) * width, height: CGFloat(slot.h) * height)
            let outline = TemplateGeometry.outline(slot.shape, points: slot.points, in: box)
            let path = TemplateGeometry.bezier(outline)

            switch slot.kind {
            case .text:
                if !slot.fillHex.isEmpty {
                    NSColor(templateHex: slot.fillHex).setFill()
                    path.fill()
                }
                let key = TemplateFill.normal(slot.key)
                var value = texts?[key] ?? ""
                if value.isEmpty && useSamples { value = slot.sample }
                if !value.isEmpty {
                    drawText(slot.uppercase ? value.uppercased() : value, slot: slot, in: TemplateGeometry.textBox(slot.shape, in: box), pictureHeight: height)
                }
            case .image:
                let key = TemplateFill.normal(slot.key)
                if let picture = images[key] {
                    NSGraphicsContext.saveGraphicsState()
                    path.addClip()
                    drawFilled(picture, in: box)
                    NSGraphicsContext.restoreGraphicsState()
                } else if useSamples {
                    NSColor(white: 0.5, alpha: 0.28).setFill()
                    path.fill()
                    if let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) {
                        let side = min(box.width, box.height) * 0.4
                        NSColor(white: 0.25, alpha: 0.6).set()
                        symbol.draw(in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side), from: .zero, operation: .sourceOver, fraction: 0.6, respectFlipped: true, hints: nil)
                    }
                }
            case .logo:
                if !slot.fillHex.isEmpty {
                    NSColor(templateHex: slot.fillHex).setFill()
                    path.fill()
                }
                if let logo = TemplateLogos.image(slot.logo, colorHex: slot.colorHex) {
                    drawFitted(logo, in: TemplateGeometry.textBox(slot.shape, in: box))
                }
            }
            cg.restoreGState()
        }
        return rep
    }

    @MainActor static func render(_ template: ImageTemplate, base: NSImage, texts: [String: String]?, images: [String: NSImage],
                                  useSamples: Bool, maxSide: CGFloat?) -> NSImage? {
        guard let rep = renderRep(template, base: base, texts: texts, images: images, useSamples: useSamples, maxSide: maxSide) else { return nil }
        let image = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        image.addRepresentation(rep)
        return image
    }

    @MainActor static func pngData(_ template: ImageTemplate, base: NSImage, texts: [String: String]?, images: [String: NSImage]) -> Data? {
        renderRep(template, base: base, texts: texts, images: images, useSamples: false, maxSide: nil)?.representation(using: .png, properties: [:])
    }

    // MARK: Pieces

    private static func drawFilled(_ picture: NSImage, in box: CGRect) {
        let size = TemplateImages.pixelSize(picture)
        guard size.width > 0, size.height > 0 else { return }
        let scale = max(box.width / size.width, box.height / size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        let target = CGRect(x: box.midX - drawn.width / 2, y: box.midY - drawn.height / 2, width: drawn.width, height: drawn.height)
        picture.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private static func drawFitted(_ picture: NSImage, in box: CGRect) {
        let size = picture.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(box.width / size.width, box.height / size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        let target = CGRect(x: box.midX - drawn.width / 2, y: box.midY - drawn.height / 2, width: drawn.width, height: drawn.height)
        picture.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private static func font(_ slot: TemplateSlot, size: CGFloat) -> NSFont {
        var font = NSFont(name: slot.fontName, size: size) ?? NSFont.systemFont(ofSize: size)
        if slot.bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if slot.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    private static func attributes(_ slot: TemplateSlot, size: CGFloat) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = slot.align == "left" ? .left : (slot.align == "right" ? .right : .center)
        style.lineBreakMode = .byWordWrapping
        return [.font: font(slot, size: size), .foregroundColor: NSColor(templateHex: slot.colorHex), .paragraphStyle: style]
    }

    /// The biggest size that fits the text inside the box, wrapping words but never splitting one.
    private static func fittingSize(_ text: String, slot: TemplateSlot, in box: CGRect, pictureHeight: CGFloat) -> CGFloat {
        var high = slot.fontSize > 0 ? slot.fontSize * pictureHeight : box.height
        high = max(5, min(high, box.height))
        var low: CGFloat = 5
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        func fits(_ size: CGFloat) -> Bool {
            let attrs = attributes(slot, size: size)
            for word in words where (word as NSString).size(withAttributes: attrs).width > box.width + 0.5 { return false }
            let bounds = (text as NSString).boundingRect(with: CGSize(width: box.width, height: .greatestFiniteMagnitude),
                                                         options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
            return bounds.height <= box.height + 0.5
        }
        if fits(high) { return high }
        for _ in 0..<14 {
            let mid = (low + high) / 2
            if fits(mid) { low = mid } else { high = mid }
        }
        return low
    }

    private static func drawText(_ text: String, slot: TemplateSlot, in box: CGRect, pictureHeight: CGFloat) {
        guard box.width > 2, box.height > 2 else { return }
        let size = fittingSize(text, slot: slot, in: box, pictureHeight: pictureHeight)
        let attrs = attributes(slot, size: size)
        let bounds = (text as NSString).boundingRect(with: CGSize(width: box.width, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        let height = min(bounds.height, box.height)
        let target = CGRect(x: box.minX, y: box.minY + (box.height - height) / 2, width: box.width, height: height)
        (text as NSString).draw(with: target, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
    }
}

// MARK: - Filling a template from an app

enum TemplateFill {
    /// "Invoice No." and "invoiceno" are the same name.
    static func normal(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Finds a picture from a shortcut name, a file path or a media shortcut.
    @MainActor static func picture(for value: String, clips: [Clip]) -> NSImage? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if FileManager.default.fileExists(atPath: trimmed), let image = NSImage(contentsOfFile: trimmed) { return image }
        let imageTypes = ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff"]
        if let found = celebrationMedia(trimmed, clips: clips),
           let path = found.paths.first(where: { imageTypes.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) {
            return NSImage(contentsOfFile: path)
        }
        return nil
    }

    /// The finished picture for a template, using the values by box name. Picture boxes read their value as a shortcut
    /// name or file path.
    @MainActor static func render(_ template: ImageTemplate, values: [String: String], extraImages: [String: NSImage] = [:], clips: [Clip], maxSide: CGFloat? = nil) -> NSImage? {
        guard let base = TemplateStore.shared.basePicture(for: template) else { return nil }
        var texts: [String: String] = [:]
        for (key, value) in values { texts[normal(key)] = value }
        var images: [String: NSImage] = [:]
        for (key, image) in extraImages { images[normal(key)] = image }
        for slot in template.slots where slot.kind == .image {
            let key = normal(slot.key)
            if images[key] == nil, let value = texts[key], let found = picture(for: value, clips: clips) { images[key] = found }
        }
        return TemplateRenderer.render(template, base: base, texts: texts, images: images, useSamples: false, maxSide: maxSide)
    }

    /// Saves the finished picture as a PNG and returns its path.
    @MainActor static func renderFile(_ template: ImageTemplate, values: [String: String], clips: [Clip], to file: URL) throws {
        guard let base = TemplateStore.shared.basePicture(for: template) else {
            throw NSError(domain: "KeyDoTemplates", code: 1, userInfo: [NSLocalizedDescriptionKey: "The template picture is missing."])
        }
        var texts: [String: String] = [:]
        for (key, value) in values { texts[normal(key)] = value }
        var images: [String: NSImage] = [:]
        for slot in template.slots where slot.kind == .image {
            let key = normal(slot.key)
            if let value = texts[key], let found = picture(for: value, clips: clips) { images[key] = found }
        }
        guard let data = TemplateRenderer.pngData(template, base: base, texts: texts, images: images) else {
            throw NSError(domain: "KeyDoTemplates", code: 2, userInfo: [NSLocalizedDescriptionKey: "The template picture could not be made."])
        }
        try data.write(to: file, options: .atomic)
    }
}

// MARK: - Taking text out of a picture

struct DetectedText: Identifiable {
    let id = UUID()
    var text: String
    /// Fractions of the picture, from the top left.
    var rect: CGRect
    var lightBackground: Bool = true
}

enum TemplateEraser {
    /// Finds every line of text in the picture.
    static func detect(in image: NSImage) async -> [DetectedText] {
        guard let cg = TemplateImages.cgImage(image) else { return [] }
        let lines: [DetectedText] = await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            var found: [DetectedText] = []
            for observation in (request.results as? [VNRecognizedTextObservation]) ?? [] {
                guard let best = observation.topCandidates(1).first, best.confidence >= 0.3 else { continue }
                let box = observation.boundingBox
                found.append(DetectedText(text: best.string, rect: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)))
            }
            return found
        }.value
        return lines
    }

    /// Paints over each rectangle with the colours around it, so the picture looks as if the text was never there.
    static func erase(_ image: NSImage, rects: [CGRect]) -> NSImage {
        guard !rects.isEmpty, let cg = TemplateImages.cgImage(image) else { return image }
        let width = cg.width, height = cg.height
        let source = NSBitmapImageRep(cgImage: cg)
        guard let rep = TemplateImages.bitmap(width: width, height: height), let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return image }
        let context = graphics.cgContext
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)

        for fraction in rects {
            var area = CGRect(x: fraction.minX * CGFloat(width), y: fraction.minY * CGFloat(height), width: fraction.width * CGFloat(width), height: fraction.height * CGFloat(height))
            let padX = max(3, area.height * 0.18), padY = max(3, area.height * 0.2)
            area = area.insetBy(dx: -padX, dy: -padY).intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
            guard area.width > 1, area.height > 1 else { continue }
            let band: CGFloat = 4
            let size = CGSize(width: width, height: height)
            let left = average(source, CGRect(x: area.minX - band - 1, y: area.minY, width: band, height: area.height), size)
            let right = average(source, CGRect(x: area.maxX + 1, y: area.minY, width: band, height: area.height), size)
            let top = average(source, CGRect(x: area.minX, y: area.minY - band - 1, width: area.width, height: band), size)
            let bottom = average(source, CGRect(x: area.minX, y: area.maxY + 1, width: area.width, height: band), size)
            let white: (CGFloat, CGFloat, CGFloat) = (1, 1, 1)
            let known: [(CGFloat, CGFloat, CGFloat)] = [left, right, top, bottom].compactMap { $0 }
            let fallback: (CGFloat, CGFloat, CGFloat) = known.first ?? white
            let l: (CGFloat, CGFloat, CGFloat) = left ?? right ?? fallback
            let r: (CGFloat, CGFloat, CGFloat) = right ?? left ?? fallback
            let t: (CGFloat, CGFloat, CGFloat) = top ?? bottom ?? fallback
            let b: (CGFloat, CGFloat, CGFloat) = bottom ?? top ?? fallback

            let cell: CGFloat = 3
            var y = area.minY
            while y < area.maxY {
                let fy = (y - area.minY) / max(1, area.height)
                var x = area.minX
                while x < area.maxX {
                    let fx = (x - area.minX) / max(1, area.width)
                    let horizontal = (l.0 + (r.0 - l.0) * fx, l.1 + (r.1 - l.1) * fx, l.2 + (r.2 - l.2) * fx)
                    let vertical = (t.0 + (b.0 - t.0) * fy, t.1 + (b.1 - t.1) * fy, t.2 + (b.2 - t.2) * fy)
                    context.setFillColor(red: (horizontal.0 + vertical.0) / 2, green: (horizontal.1 + vertical.1) / 2, blue: (horizontal.2 + vertical.2) / 2, alpha: 1)
                    context.fill(CGRect(x: x, y: y, width: cell + 0.5, height: cell + 0.5))
                    x += cell
                }
                y += cell
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: NSSize(width: width, height: height))
        result.addRepresentation(rep)
        return result
    }

    /// Whether the area around a rectangle is light, to pick a readable text colour for a new box.
    static func isLight(_ image: NSImage, around fraction: CGRect) -> Bool {
        guard let cg = TemplateImages.cgImage(image) else { return true }
        let source = NSBitmapImageRep(cgImage: cg)
        let size = CGSize(width: cg.width, height: cg.height)
        let area = CGRect(x: fraction.minX * size.width, y: fraction.minY * size.height, width: fraction.width * size.width, height: fraction.height * size.height).insetBy(dx: -6, dy: -6)
        guard let color = average(source, area, size) else { return true }
        return (0.299 * color.0 + 0.587 * color.1 + 0.114 * color.2) > 0.55
    }

    private static func average(_ source: NSBitmapImageRep, _ area: CGRect, _ size: CGSize) -> (CGFloat, CGFloat, CGFloat)? {
        let clipped = area.intersection(CGRect(origin: .zero, size: size))
        guard clipped.width >= 1, clipped.height >= 1 else { return nil }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, count: CGFloat = 0
        let columns = max(1, min(8, Int(clipped.width))), rows = max(1, min(8, Int(clipped.height)))
        for row in 0..<rows {
            for column in 0..<columns {
                let x = Int(clipped.minX + (CGFloat(column) + 0.5) * clipped.width / CGFloat(columns))
                let y = Int(clipped.minY + (CGFloat(row) + 0.5) * clipped.height / CGFloat(rows))
                guard x >= 0, y >= 0, x < source.pixelsWide, y < source.pixelsHigh,
                      let color = source.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                red += color.redComponent; green += color.greenComponent; blue += color.blueComponent; count += 1
            }
        }
        guard count > 0 else { return nil }
        return (red / count, green / count, blue / count)
    }
}
