// KeyDo fonts: a small font engine that draws A to Z, 0 to 9 and common marks as strokes, in many styles.
// Ten styles come with KeyDo; Font Creator makes more from a picture of a letter. A KeyDo font is picked by name
// ("KeyDo · Summit Block") in every font list, and templates (Wish Studio, Template Designer, AppDesigner) draw
// text in it. Word and web page output cannot carry these fonts and use a normal font instead.
import SwiftUI
import AppKit

/// One letter cut out of a picture.
struct KeyDoGlyph: Codable, Equatable {
    var png: Data
    /// Width divided by height.
    var aspect: Double
    /// Height compared with the tallest letter in the picture.
    var ratio: Double
    /// How far below the writing line it sits, in tallest-letter heights (for g, j, p, q, y).
    var drop: Double
    /// False when the picture is one dark colour: the letter then takes the colour of the text box.
    var colored: Bool
}

struct KeyDoFontStyle: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// Stroke width as a fraction of the letter height.
    var weight: Double = 0.14
    /// 0 flat, 1 round, 2 square.
    var cap: Int = 1
    /// 0 sharp, 1 round, 2 bevelled.
    var join: Int = 1
    var slant: Double = 0
    var width: Double = 1
    var spacing: Double = 0.06
    /// 0 solid, 1 outline, 2 dots, 3 stencil, 4 neon, 5 shadow.
    var mode: Int = 0
    /// Colours used letter by letter. Empty means the colour of the text box.
    var palette: [String] = []
    var builtIn: Bool = false
    /// Letters cut straight out of the picture, by character. They are drawn exactly as they look in the picture.
    var glyphs: [String: KeyDoGlyph]? = nil
    /// Length of the small feet on stems and bars, as a fraction of the letter height. Nil or 0 for none (sans).
    var serif: Double? = nil
    /// How much thinner the horizontal strokes are than the vertical ones, 0 to 0.75. Nil or 0 for even strokes. Shows in Solid.
    var contrast: Double? = nil

    var fontName: String { "KeyDo \u{00B7} " + name }
    static let modes = ["Solid", "Outline", "Dots", "Stencil", "Neon glow", "Shadow", "Inline", "3D block", "Sticker", "Gloss"]
}

enum KeyDoFonts {
    static let prefix = "KeyDo \u{00B7} "

    // MARK: The ten styles that come with KeyDo

    static let builtIn: [KeyDoFontStyle] = [
        KeyDoFontStyle(id: "summit-block", name: "Summit Block", weight: 0.25, cap: 2, join: 0, width: 0.95, spacing: 0.04, mode: 0, palette: ["#E8484B", "#F7C62F", "#5BC0DE"], builtIn: true),
        KeyDoFontStyle(id: "marquee-neon", name: "Marquee Neon", weight: 0.09, cap: 1, join: 1, spacing: 0.08, mode: 4, palette: ["#FF3EA5", "#2DE2E6"], builtIn: true),
        KeyDoFontStyle(id: "rangoli-dots", name: "Rangoli Dots", weight: 0.11, cap: 1, join: 1, spacing: 0.1, mode: 2, palette: ["#F28C28", "#B4232C"], builtIn: true),
        KeyDoFontStyle(id: "stencil-army", name: "Stencil Army", weight: 0.17, cap: 0, join: 0, width: 0.9, spacing: 0.05, mode: 3, builtIn: true),
        KeyDoFontStyle(id: "royal-outline", name: "Royal Outline", weight: 0.2, cap: 1, join: 1, spacing: 0.06, mode: 1, palette: ["#C9A227"], builtIn: true),
        KeyDoFontStyle(id: "retro-shadow", name: "Retro Shadow", weight: 0.14, cap: 1, join: 1, spacing: 0.06, mode: 5, palette: ["#FF7A59"], builtIn: true),
        KeyDoFontStyle(id: "bollywood-italic", name: "Bollywood Italic", weight: 0.13, cap: 2, join: 0, slant: 14, width: 0.95, spacing: 0.05, mode: 5, palette: ["#C0262D", "#D9A521"], builtIn: true),
        KeyDoFontStyle(id: "candy-round", name: "Candy Round", weight: 0.19, cap: 1, join: 1, width: 0.9, spacing: 0.05, mode: 0, palette: ["#FF8FB1", "#6FD6B2", "#7FB5FF"], builtIn: true),
        KeyDoFontStyle(id: "deco-line", name: "Deco Line", weight: 0.045, cap: 0, join: 0, width: 1.15, spacing: 0.14, mode: 0, builtIn: true),
        KeyDoFontStyle(id: "pixel-grid", name: "Pixel Grid", weight: 0.1, cap: 2, join: 0, width: 0.95, spacing: 0.07, mode: 2, palette: ["#2E8B57", "#1F2A44"], builtIn: true),
        KeyDoFontStyle(id: "midnight-inline", name: "Midnight Inline", weight: 0.2, cap: 1, join: 1, spacing: 0.07, mode: 6, palette: ["#1F2A44"], builtIn: true),
        KeyDoFontStyle(id: "block-3d", name: "Block 3D", weight: 0.15, cap: 2, join: 0, width: 0.95, spacing: 0.08, mode: 7, palette: ["#E8484B"], builtIn: true),
        KeyDoFontStyle(id: "sticker-pop", name: "Sticker Pop", weight: 0.15, cap: 1, join: 1, spacing: 0.1, mode: 8, palette: ["#FF6F91", "#FFC75F", "#3DBE9B"], builtIn: true),
        KeyDoFontStyle(id: "gloss-candy", name: "Gloss Candy", weight: 0.17, cap: 1, join: 1, spacing: 0.06, mode: 9, palette: ["#7B61FF", "#FF5C8D"], builtIn: true),
        KeyDoFontStyle(id: "ink-mono", name: "Ink Mono", weight: 0.06, cap: 1, join: 1, spacing: 0.07, mode: 0, builtIn: true),
        KeyDoFontStyle(id: "heavy-slab", name: "Heavy Slab", weight: 0.3, cap: 2, join: 0, width: 0.9, spacing: 0.03, mode: 0, palette: ["#0B3D91"], builtIn: true),
        KeyDoFontStyle(id: "tall-condensed", name: "Tall Condensed", weight: 0.12, cap: 0, join: 0, width: 0.72, spacing: 0.05, mode: 0, builtIn: true),
        KeyDoFontStyle(id: "wide-techno", name: "Wide Techno", weight: 0.1, cap: 2, join: 0, width: 1.3, spacing: 0.09, mode: 0, palette: ["#00A99D"], builtIn: true),
        KeyDoFontStyle(id: "carnival-dots", name: "Carnival Dots", weight: 0.15, cap: 1, join: 1, spacing: 0.09, mode: 2, palette: ["#FF006E", "#FFBE0B", "#3A86FF", "#06D6A0"], builtIn: true),
        KeyDoFontStyle(id: "gold-stencil", name: "Gold Stencil", weight: 0.17, cap: 0, join: 0, spacing: 0.05, mode: 3, palette: ["#B8860B"], builtIn: true)
    ]

    // MARK: Your own styles

    private static let userKey = "keydoUserFontStyles"
    private static var cache: [KeyDoFontStyle]?

    static var user: [KeyDoFontStyle] {
        if let cache { return cache }
        let list: [KeyDoFontStyle]
        if let data = UserDefaults.standard.data(forKey: userKey), let decoded = try? JSONDecoder().decode([KeyDoFontStyle].self, from: data) { list = decoded } else { list = [] }
        cache = list
        return list
    }

    static func saveUser(_ style: KeyDoFontStyle) {
        var list = user.filter { $0.id != style.id }
        list.append(style)
        store(list)
    }

    static func deleteUser(_ id: String) { store(user.filter { $0.id != id }) }

    private static func store(_ list: [KeyDoFontStyle]) {
        cache = list
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: userKey) }
    }

    static var all: [KeyDoFontStyle] { builtIn + user }
    static var allNames: [String] { all.map { $0.fontName } }
    static func isCustom(_ fontName: String) -> Bool { fontName.hasPrefix(prefix) }
    static func style(named fontName: String) -> KeyDoFontStyle? { all.first { $0.fontName == fontName } }

    // MARK: The letters (strokes on a box 0...1 across and 0...1 up)

    private static func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private static func arc(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ from: Double, _ to: Double, _ steps: Int = 14) -> [CGPoint] {
        (0...steps).map { index in
            let angle = (from + (to - from) * Double(index) / Double(steps)) * Double.pi / 180
            return p(cx + rx * cos(angle), cy + ry * sin(angle))
        }
    }

    private static let shapes: [Character: [[CGPoint]]] = {
        var s: [Character: [[CGPoint]]] = [:]
        s["A"] = [[p(0, 0), p(0.5, 1), p(1, 0)], [p(0.18, 0.38), p(0.82, 0.38)]]
        s["B"] = [[p(0, 0), p(0, 1)], [p(0, 1), p(0.6, 1)] + arc(0.6, 0.76, 0.38, 0.24, 90, -90) + [p(0, 0.52)],
                  [p(0, 0.52), p(0.65, 0.52)] + arc(0.65, 0.26, 0.35, 0.26, 90, -90) + [p(0, 0)]]
        s["C"] = [arc(0.52, 0.5, 0.52, 0.5, 40, 320, 24)]
        s["D"] = [[p(0, 0), p(0, 1), p(0.45, 1)] + arc(0.45, 0.5, 0.55, 0.5, 90, -90, 16) + [p(0, 0)]]
        s["E"] = [[p(1, 1), p(0, 1), p(0, 0), p(1, 0)], [p(0, 0.52), p(0.75, 0.52)]]
        s["F"] = [[p(1, 1), p(0, 1), p(0, 0)], [p(0, 0.52), p(0.75, 0.52)]]
        s["G"] = [arc(0.5, 0.5, 0.5, 0.5, 40, 360, 26) + [p(0.55, 0.5)]]
        s["H"] = [[p(0, 0), p(0, 1)], [p(1, 0), p(1, 1)], [p(0, 0.5), p(1, 0.5)]]
        s["I"] = [[p(0.5, 0), p(0.5, 1)]]
        s["J"] = [[p(1, 1), p(1, 0.3)] + arc(0.5, 0.3, 0.5, 0.3, 0, -180, 14)]
        s["K"] = [[p(0, 0), p(0, 1)], [p(1, 1), p(0, 0.42)], [p(0.22, 0.58), p(1, 0)]]
        s["L"] = [[p(0, 1), p(0, 0), p(1, 0)]]
        s["M"] = [[p(0, 0), p(0, 1), p(0.5, 0.35), p(1, 1), p(1, 0)]]
        s["N"] = [[p(0, 0), p(0, 1), p(1, 0), p(1, 1)]]
        s["O"] = [arc(0.5, 0.5, 0.5, 0.5, 0, 360, 30)]
        s["P"] = [[p(0, 0), p(0, 1), p(0.6, 1)] + arc(0.6, 0.75, 0.4, 0.25, 90, -90) + [p(0, 0.5)]]
        s["Q"] = [arc(0.5, 0.5, 0.5, 0.5, 0, 360, 30), [p(0.6, 0.3), p(1, -0.02)]]
        s["R"] = [[p(0, 0), p(0, 1), p(0.6, 1)] + arc(0.6, 0.75, 0.4, 0.25, 90, -90) + [p(0, 0.5)], [p(0.5, 0.5), p(1, 0)]]
        s["S"] = [arc(0.5, 0.75, 0.5, 0.25, 30, 270, 12) + arc(0.5, 0.25, 0.5, 0.25, 90, -150, 12)]
        s["T"] = [[p(0, 1), p(1, 1)], [p(0.5, 1), p(0.5, 0)]]
        s["U"] = [[p(0, 1), p(0, 0.5)] + arc(0.5, 0.5, 0.5, 0.5, 180, 360, 16) + [p(1, 1)]]
        s["V"] = [[p(0, 1), p(0.5, 0), p(1, 1)]]
        s["W"] = [[p(0, 1), p(0.25, 0), p(0.5, 0.6), p(0.75, 0), p(1, 1)]]
        s["X"] = [[p(0, 0), p(1, 1)], [p(0, 1), p(1, 0)]]
        s["Y"] = [[p(0, 1), p(0.5, 0.5), p(1, 1)], [p(0.5, 0.5), p(0.5, 0)]]
        s["Z"] = [[p(0, 1), p(1, 1), p(0, 0), p(1, 0)]]
        s["0"] = [arc(0.5, 0.5, 0.5, 0.5, 0, 360, 30)]
        s["1"] = [[p(0.15, 0.78), p(0.55, 1), p(0.55, 0)]]
        s["2"] = [arc(0.5, 0.72, 0.5, 0.28, 170, -30, 12) + [p(0, 0), p(1, 0)]]
        s["3"] = [arc(0.5, 0.75, 0.45, 0.25, 150, -90, 10) + arc(0.5, 0.25, 0.5, 0.25, 90, -150, 10)]
        s["4"] = [[p(0.75, 0), p(0.75, 1), p(0, 0.3), p(1, 0.3)]]
        s["5"] = [[p(0.95, 1), p(0.1, 1), p(0.05, 0.55)] + arc(0.48, 0.3, 0.52, 0.3, 110, -160, 14)]
        s["6"] = [arc(0.5, 0.3, 0.5, 0.3, 0, 360, 22), [p(0.85, 1), p(0.15, 0.62), p(0, 0.3)]]
        s["7"] = [[p(0, 1), p(1, 1), p(0.35, 0)]]
        s["8"] = [arc(0.5, 0.75, 0.42, 0.25, 0, 360, 20), arc(0.5, 0.27, 0.5, 0.27, 0, 360, 22)]
        s["9"] = [arc(0.5, 0.7, 0.5, 0.3, 0, 360, 22), [p(0.15, 0), p(0.85, 0.38), p(1, 0.7)]]
        s["."] = [[p(0.5, 0), p(0.5, 0.001)]]
        s[","] = [[p(0.5, 0.06), p(0.35, -0.16)]]
        s["-"] = [[p(0.05, 0.45), p(0.95, 0.45)]]
        s["!"] = [[p(0.5, 1), p(0.5, 0.3)], [p(0.5, 0), p(0.5, 0.001)]]
        s["?"] = [arc(0.5, 0.74, 0.45, 0.26, 160, -60, 12) + [p(0.5, 0.35), p(0.5, 0.28)], [p(0.5, 0), p(0.5, 0.001)]]
        s["'"] = [[p(0.5, 1), p(0.5, 0.74)]]
        s[":"] = [[p(0.5, 0.7), p(0.5, 0.701)], [p(0.5, 0.05), p(0.5, 0.051)]]
        let xh = 0.62
        s["a"] = [arc(0.45, 0.31, 0.45, 0.31, 0, 360, 24), [p(0.9, xh), p(0.9, 0)]]
        s["b"] = [[p(0, 1), p(0, 0)], arc(0.5, 0.31, 0.5, 0.31, 0, 360, 24)]
        s["c"] = [arc(0.5, 0.31, 0.5, 0.31, 40, 320, 18)]
        s["d"] = [[p(1, 1), p(1, 0)], arc(0.5, 0.31, 0.5, 0.31, 0, 360, 24)]
        s["e"] = [[p(0, 0.31), p(1, 0.31)] + arc(0.5, 0.31, 0.5, 0.31, 0, 320, 22)]
        s["f"] = [[p(0.35, 0), p(0.35, 0.85)] + arc(0.65, 0.85, 0.3, 0.15, 180, 60, 8), [p(0.02, xh), p(0.75, xh)]]
        s["g"] = [arc(0.5, 0.31, 0.5, 0.31, 0, 360, 24), [p(1, xh), p(1, -0.05)] + arc(0.5, -0.05, 0.5, 0.25, 0, -180, 12)]
        s["h"] = [[p(0, 1), p(0, 0)], [p(0, 0.35)] + arc(0.5, 0.35, 0.5, 0.27, 180, 0, 12) + [p(1, 0)]]
        s["i"] = [[p(0.5, xh), p(0.5, 0)], [p(0.5, 0.88), p(0.5, 0.881)]]
        s["j"] = [[p(0.6, xh), p(0.6, -0.05)] + arc(0.3, -0.05, 0.3, 0.22, 0, -180, 10), [p(0.6, 0.88), p(0.6, 0.881)]]
        s["k"] = [[p(0, 1), p(0, 0)], [p(0.9, xh), p(0, 0.25)], [p(0.3, 0.38), p(1, 0)]]
        s["l"] = [[p(0.5, 1), p(0.5, 0)]]
        s["m"] = [[p(0, xh), p(0, 0)], [p(0, 0.3)] + arc(0.25, 0.3, 0.25, 0.32, 180, 0, 10) + [p(0.5, 0)], [p(0.5, 0.3)] + arc(0.75, 0.3, 0.25, 0.32, 180, 0, 10) + [p(1, 0)]]
        s["n"] = [[p(0, xh), p(0, 0)], [p(0, 0.3)] + arc(0.5, 0.3, 0.5, 0.32, 180, 0, 12) + [p(1, 0)]]
        s["o"] = [arc(0.5, 0.31, 0.5, 0.31, 0, 360, 26)]
        s["p"] = [[p(0, xh), p(0, -0.3)], arc(0.5, 0.31, 0.5, 0.31, 0, 360, 24)]
        s["q"] = [[p(1, xh), p(1, -0.3)], arc(0.5, 0.31, 0.5, 0.31, 0, 360, 24)]
        s["r"] = [[p(0, xh), p(0, 0)], [p(0, 0.3)] + arc(0.5, 0.3, 0.5, 0.32, 180, 60, 8)]
        s["s"] = [arc(0.5, 0.465, 0.45, 0.155, 30, 270, 10) + arc(0.5, 0.155, 0.5, 0.155, 90, -150, 10)]
        s["t"] = [[p(0.4, 0.95), p(0.4, 0.1)] + arc(0.7, 0.1, 0.3, 0.1, 180, 270, 6), [p(0.05, xh), p(0.8, xh)]]
        s["u"] = [[p(0, xh), p(0, 0.3)] + arc(0.5, 0.3, 0.5, 0.3, 180, 360, 12), [p(1, xh), p(1, 0)]]
        s["v"] = [[p(0, xh), p(0.5, 0), p(1, xh)]]
        s["w"] = [[p(0, xh), p(0.25, 0), p(0.5, 0.4), p(0.75, 0), p(1, xh)]]
        s["x"] = [[p(0, xh), p(1, 0)], [p(0, 0), p(1, xh)]]
        s["y"] = [[p(0, xh), p(0.5, 0)], [p(1, xh), p(0.3, -0.3)]]
        s["z"] = [[p(0, xh), p(1, xh), p(0, 0), p(1, 0)]]
        s["("] = [arc(0.9, 0.5, 0.6, 0.7, 120, 240, 10)]
        s[")"] = [arc(0.1, 0.5, 0.6, 0.7, 60, -60, 10)]
        s["/"] = [[p(0, 0), p(1, 1)]]
        s["+"] = [[p(0.1, 0.5), p(0.9, 0.5)], [p(0.5, 0.15), p(0.5, 0.85)]]
        s["&"] = [[p(1, 0), p(0.1, 0.7), p(0.3, 1), p(0.6, 0.8), p(0.0, 0.2), p(0.3, 0), p(0.75, 0.2), p(1, 0.5)]]
        return s
    }()

    /// The width of a letter's box, in letter heights.
    static func boxWidth(_ ch: Character) -> CGFloat {
        switch ch {
        case "I", ".", "!", "'", ":", ",": return 0.02
        case "-": return 0.5
        case "M", "W": return 0.92
        case "J", "L", "1", "7": return 0.55
        case "0"..."9": return 0.58
        case "i", "l": return 0.02
        case "j": return 0.3
        case "m", "w": return 0.85
        case "f", "t", "r": return 0.45
        case "a"..."z": return 0.56
        case "(", ")": return 0.25
        case "/": return 0.5
        case "+": return 0.6
        case " ": return 0.45
        default: return 0.7
        }
    }

    // MARK: Letters cut from a picture

    private static let glyphLock = NSLock()
    private static var glyphImages: [String: NSImage] = [:]

    /// The letter's own cut-out. A capital's cut-out also serves its small letter when the picture has no small one.
    static func glyph(_ style: KeyDoFontStyle, _ ch: Character) -> KeyDoGlyph? {
        guard let all = style.glyphs, !all.isEmpty else { return nil }
        if let exact = all[String(ch)] { return exact }
        let upper = String(ch).uppercased()
        if upper != String(ch), let capital = all[upper] { return capital }
        return nil
    }

    private static func glyphImage(_ style: KeyDoFontStyle, _ ch: Character, _ cut: KeyDoGlyph, tint: NSColor) -> NSImage? {
        let name = glyphKey(style, ch)
        let cacheKey = style.id + "|" + name + "|" + (cut.colored ? "" : tint.templateHex)
        glyphLock.lock()
        if let hit = glyphImages[cacheKey] { glyphLock.unlock(); return hit }
        glyphLock.unlock()
        guard let base = NSImage(data: cut.png) else { return nil }
        var result = base
        if !cut.colored {
            let size = PhotoCanvas.pixelSize(base)
            if let rep = PhotoCanvas.bitmap(width: Int(size.width), height: Int(size.height), draw: { canvas in
                let rect = NSRect(origin: .zero, size: canvas)
                base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                tint.setFill()
                rect.fill(using: .sourceIn)
            }), let tinted = PhotoCanvas.image(rep) { result = tinted }
        }
        glyphLock.lock()
        if glyphImages.count > 500 { glyphImages.removeAll() }
        glyphImages[cacheKey] = result
        glyphLock.unlock()
        return result
    }

    private static func glyphKey(_ style: KeyDoFontStyle, _ ch: Character) -> String {
        if let all = style.glyphs, all[String(ch)] != nil { return String(ch) }
        return String(ch).uppercased()
    }

    // MARK: Measuring and drawing

    private static func advance(_ ch: Character, _ style: KeyDoFontStyle, _ height: CGFloat) -> CGFloat {
        if ch == " " { return boxWidth(ch) * CGFloat(style.width) * height }
        if let cut = glyph(style, ch) { return CGFloat(cut.aspect * cut.ratio) * height + CGFloat(style.spacing) * height }
        return boxWidth(ch) * CGFloat(style.width) * height + CGFloat(style.weight) * height * 0.95 + CGFloat(style.spacing) * height + CGFloat(style.serif ?? 0) * height * 2
    }

    private static func lineWidth(_ text: String, _ style: KeyDoFontStyle, _ height: CGFloat) -> CGFloat {
        text.reduce(CGFloat(0)) { $0 + advance($1, style, height) }
    }

    /// Words packed into lines no wider than `maxWidth`, or nil when one word alone is too wide.
    private static func lines(_ text: String, _ style: KeyDoFontStyle, _ height: CGFloat, _ maxWidth: CGFloat) -> [String]? {
        var result: [String] = []
        for paragraph in text.components(separatedBy: "\n") {
            var current = ""
            for word in paragraph.split(separator: " ").map(String.init) {
                if lineWidth(word, style, height) > maxWidth { return nil }
                let joined = current.isEmpty ? word : current + " " + word
                if lineWidth(joined, style, height) <= maxWidth { current = joined } else { result.append(current); current = word }
            }
            result.append(current)
        }
        return result
    }

    private static func lineStep(_ style: KeyDoFontStyle, _ height: CGFloat) -> CGFloat { height * 1.25 + CGFloat(style.weight) * height }

    /// The tallest letter height at which the text fits the box.
    private static func fit(_ text: String, _ style: KeyDoFontStyle, in box: CGRect, maxHeight: CGFloat) -> CGFloat {
        func fits(_ height: CGFloat) -> Bool {
            guard let wrapped = lines(text, style, height, box.width) else { return false }
            return lineStep(style, height) * CGFloat(wrapped.count) - height * 0.25 <= box.height
        }
        var high = max(6, min(maxHeight, box.height))
        if fits(high) { return high }
        var low: CGFloat = 4
        for _ in 0..<16 {
            let mid = (low + high) / 2
            if fits(mid) { low = mid } else { high = mid }
        }
        return low
    }

    private static func color(_ hex: String) -> NSColor { NSColor(templateHex: hex) }

    /// Draws the text inside `box` in the current graphics context (flipped or not).
    static func draw(_ text: String, style: KeyDoFontStyle, in box: CGRect, maxHeight: CGFloat, color base: NSColor, align: String) {
        guard let context = NSGraphicsContext.current?.cgContext, box.width > 2, box.height > 2 else { return }
        let flipped = NSGraphicsContext.current?.isFlipped ?? false
        let upper = text
        let height = fit(upper, style, in: box, maxHeight: maxHeight)
        let wrapped: [String] = lines(upper, style, height, box.width) ?? [upper]
        let step = lineStep(style, height)
        let blockHeight = step * CGFloat(wrapped.count) - height * 0.25
        let weight = CGFloat(style.weight) * height
        let tangent = CGFloat(tan(style.slant * Double.pi / 180))
        var counter = 0
        for (row, line) in wrapped.enumerated() {
            let widthOfLine = lineWidth(line, style, height) - (line.isEmpty ? 0 : CGFloat(style.spacing) * height)
            var x: CGFloat
            switch align {
            case "left": x = box.minX + weight / 2
            case "right": x = box.maxX - widthOfLine - weight / 2
            default: x = box.midX - widthOfLine / 2
            }
            // The distance of this line's top from the top of the block.
            let fromTop = (box.height - blockHeight) / 2 + CGFloat(row) * step
            for ch in line {
                defer { x += advance(ch, style, height) }
                if let cut = glyph(style, ch) {
                    let cutHeight = height * CGFloat(cut.ratio)
                    let cutWidth = cutHeight * CGFloat(cut.aspect)
                    let baseline = flipped ? box.minY + fromTop + height : box.maxY - fromTop - height
                    let lower = height * CGFloat(cut.drop)
                    let originY = flipped ? baseline + lower - cutHeight : baseline - lower
                    if let picture = glyphImage(style, ch, cut, tint: base) {
                        picture.draw(in: CGRect(x: x, y: originY, width: cutWidth, height: cutHeight), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                    }
                    counter += 1
                    continue
                }
                guard let strokes = shapes[ch] else { continue }
                let boxW = boxWidth(ch) * CGFloat(style.width) * height
                let serifPad = CGFloat(style.serif ?? 0) * height
                func device(_ point: CGPoint) -> CGPoint {
                    let up = point.y * height
                    let px = x + weight / 2 + serifPad + point.x * boxW + up * tangent
                    let py = flipped ? box.minY + fromTop + (height - up) : box.maxY - fromTop - height + up
                    return CGPoint(x: px, y: py)
                }
                var drawn: [[CGPoint]] = strokes.map { $0.map { device($0) } }
                if serifPad > 0.5 { drawn += serifLines(strokes, ch: ch, device: device, length: serifPad, down: flipped ? 1 : -1) }
                let path = CGMutablePath()
                for stroke in drawn {
                    guard let first = stroke.first else { continue }
                    path.move(to: first)
                    if stroke.count == 1 { path.addLine(to: first) }
                    for point in stroke.dropFirst() { path.addLine(to: point) }
                }
                let thinThick = style.mode == 0 && (style.contrast ?? 0) > 0.04
                let shape: CGPath? = thinThick ? contrastShape(drawn, style: style, weight: weight) : nil
                let tint = style.palette.isEmpty ? base : color(style.palette[counter % style.palette.count])
                counter += 1
                paint(path, shape: shape, style: style, weight: weight, height: height, tint: tint, in: context)
            }
        }
    }

    private static func paint(_ path: CGPath, shape: CGPath? = nil, style: KeyDoFontStyle, weight: CGFloat, height: CGFloat, tint: NSColor, in context: CGContext) {
        context.saveGState()
        context.setLineCap(style.cap == 1 ? .round : (style.cap == 2 ? .square : .butt))
        context.setLineJoin(style.join == 1 ? .round : (style.join == 2 ? .bevel : .miter))
        context.setMiterLimit(6)
        func stroke(_ width: CGFloat, _ colour: NSColor, dash: [CGFloat] = [], offset: CGSize = .zero) {
            context.saveGState()
            if offset != .zero { context.translateBy(x: offset.width, y: offset.height) }
            context.setStrokeColor(colour.cgColor)
            context.setLineWidth(width)
            context.setLineDash(phase: 0, lengths: dash)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        }
        switch style.mode {
        case 1:
            context.addPath(path)
            context.setLineWidth(weight)
            context.replacePathWithStrokedPath()
            context.setStrokeColor(tint.cgColor)
            context.setLineWidth(max(1, height * 0.022))
            context.strokePath()
        case 2:
            stroke(weight, tint, dash: [0.01, weight * 1.7])
        case 3:
            stroke(weight, tint, dash: [height * 0.3, height * 0.07])
        case 4:
            stroke(weight * 2.6, tint.withAlphaComponent(0.18))
            stroke(weight * 1.6, tint.withAlphaComponent(0.35))
            stroke(weight, tint)
            stroke(weight * 0.35, NSColor.white.withAlphaComponent(0.9))
        case 5:
            stroke(weight, NSColor.black.withAlphaComponent(0.35), offset: CGSize(width: weight * 0.35, height: -weight * 0.35))
            stroke(weight, tint)
        case 6:
            stroke(weight, tint)
            stroke(weight * 0.3, NSColor.white.withAlphaComponent(0.9))
        case 7:
            let dark = tint.blended(withFraction: 0.45, of: NSColor.black) ?? tint
            let depth = weight * 0.55
            for step in stride(from: 10, through: 1, by: -1) {
                let shift = depth * CGFloat(step) / 10
                stroke(weight, dark, offset: CGSize(width: shift, height: -shift))
            }
            stroke(weight, tint)
        case 8:
            stroke(weight + height * 0.07, NSColor.black.withAlphaComponent(0.25), offset: CGSize(width: weight * 0.12, height: -weight * 0.18))
            stroke(weight + height * 0.07, NSColor.white)
            stroke(weight, tint)
        case 9:
            let light = tint.blended(withFraction: 0.55, of: NSColor.white) ?? tint
            stroke(weight, tint)
            stroke(weight * 0.4, light, offset: CGSize(width: -weight * 0.12, height: weight * 0.12))
        default:
            if let shape {
                context.addPath(shape)
                context.setFillColor(tint.cgColor)
                context.fillPath(using: .winding)
            } else {
                stroke(weight, tint)
            }
        }
        context.restoreGState()
    }

    // MARK: Serifs and thick-and-thin strokes

    private static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared < 0.000001 { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// Small feet where stems and bars end on the baseline, the top line or the small-letter line. Drawn in device space.
    private static func serifLines(_ strokes: [[CGPoint]], ch: Character, device: (CGPoint) -> CGPoint, length: CGFloat, down: CGFloat) -> [[CGPoint]] {
        guard ch.isLetter || ch.isNumber else { return [] }
        let lower = ch.isLowercase
        func level(_ y: CGFloat) -> Int {
            if abs(y) < 0.07 { return 0 }
            if abs(y - 1) < 0.07 { return 1 }
            if lower, abs(y - 0.62) < 0.05 { return 1 }
            return -1
        }
        func touchesOther(_ point: CGPoint, _ own: Int) -> Bool {
            for (index, stroke) in strokes.enumerated() where index != own {
                for i in 0..<max(0, stroke.count - 1) where segmentDistance(point, stroke[i], stroke[i + 1]) < 0.05 { return true }
            }
            return false
        }
        var result: [[CGPoint]] = []
        for (index, stroke) in strokes.enumerated() where stroke.count >= 2 {
            if hypot(stroke[0].x - stroke[stroke.count - 1].x, stroke[0].y - stroke[stroke.count - 1].y) < 0.02 { continue }
            let ends: [(CGPoint, CGPoint)] = [(stroke[0], stroke[1]), (stroke[stroke.count - 1], stroke[stroke.count - 2])]
            for (end, neighbour) in ends {
                let lvl = level(end.y)
                if lvl < 0 || touchesOther(end, index) { continue }
                let a = device(end), b = device(neighbour)
                if abs(b.y - a.y) >= abs(b.x - a.x) * 0.5 {
                    result.append([CGPoint(x: a.x - length, y: a.y), CGPoint(x: a.x + length, y: a.y)])
                } else {
                    let sign: CGFloat = lvl == 1 ? down : -down
                    result.append([a, CGPoint(x: a.x, y: a.y + sign * length * 0.8)])
                }
            }
        }
        return result
    }

    private static func addPolygon(_ path: CGMutablePath, _ points: [CGPoint]) {
        guard points.count >= 3 else { return }
        var area: CGFloat = 0
        for i in 0..<points.count {
            let a = points[i], b = points[(i + 1) % points.count]
            area += a.x * b.y - b.x * a.y
        }
        let ordered = area < 0 ? Array(points.reversed()) : points
        path.move(to: ordered[0])
        for point in ordered.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
    }

    private static func addDisc(_ path: CGMutablePath, _ centre: CGPoint, _ diameter: CGFloat) {
        let r = max(0.5, diameter / 2)
        addPolygon(path, (0..<14).map { k in
            let angle = Double(k) / 14 * 2 * Double.pi
            return CGPoint(x: centre.x + r * CGFloat(cos(angle)), y: centre.y + r * CGFloat(sin(angle)))
        })
    }

    /// The letter as a filled shape whose horizontal strokes are thinner than its vertical ones.
    private static func contrastShape(_ lines: [[CGPoint]], style: KeyDoFontStyle, weight: CGFloat) -> CGPath {
        let c = CGFloat(min(0.75, max(0, style.contrast ?? 0)))
        func horizontalness(_ a: CGPoint, _ b: CGPoint) -> CGFloat { abs(b.x - a.x) / max(0.0001, hypot(b.x - a.x, b.y - a.y)) }
        func width(_ a: CGPoint, _ b: CGPoint) -> CGFloat { let h = horizontalness(a, b); return max(1, weight * (1 - c * h * h)) }
        let path = CGMutablePath()
        for line in lines {
            if line.count == 1 { addDisc(path, line[0], weight); continue }
            guard line.count >= 2 else { continue }
            for i in 0..<(line.count - 1) {
                var a = line[i], b = line[i + 1]
                let w = width(a, b)
                let dx = b.x - a.x, dy = b.y - a.y, length = hypot(dx, dy)
                if length < 0.0001 { addDisc(path, a, w); continue }
                let ux = dx / length, uy = dy / length
                if style.cap == 2 {
                    if i == 0 { a = CGPoint(x: a.x - ux * w / 2, y: a.y - uy * w / 2) }
                    if i == line.count - 2 { b = CGPoint(x: b.x + ux * w / 2, y: b.y + uy * w / 2) }
                }
                let nx = -uy * w / 2, ny = ux * w / 2
                addPolygon(path, [CGPoint(x: a.x + nx, y: a.y + ny), CGPoint(x: b.x + nx, y: b.y + ny), CGPoint(x: b.x - nx, y: b.y - ny), CGPoint(x: a.x - nx, y: a.y - ny)])
            }
            for i in 0..<line.count {
                let first = i == 0, last = i == line.count - 1
                if first || last {
                    if style.cap == 1 { addDisc(path, line[i], first ? width(line[0], line[1]) : width(line[i - 1], line[i])) }
                    continue
                }
                let wa = width(line[i - 1], line[i]), wb = width(line[i], line[i + 1])
                let d1 = CGPoint(x: line[i].x - line[i - 1].x, y: line[i].y - line[i - 1].y)
                let d2 = CGPoint(x: line[i + 1].x - line[i].x, y: line[i + 1].y - line[i].y)
                let l1 = max(0.0001, hypot(d1.x, d1.y)), l2 = max(0.0001, hypot(d2.x, d2.y))
                let smooth = (d1.x * d2.x + d1.y * d2.y) / (l1 * l2) > 0.9
                if smooth || style.join == 1 {
                    addDisc(path, line[i], min(wa, wb))
                } else {
                    let verticalFirst = horizontalness(line[i - 1], line[i]) < horizontalness(line[i], line[i + 1])
                    let across = verticalFirst ? wa : wb, tall = verticalFirst ? wb : wa
                    let p = line[i]
                    addPolygon(path, [CGPoint(x: p.x - across / 2, y: p.y - tall / 2), CGPoint(x: p.x + across / 2, y: p.y - tall / 2), CGPoint(x: p.x + across / 2, y: p.y + tall / 2), CGPoint(x: p.x - across / 2, y: p.y + tall / 2)])
                }
            }
        }
        return path
    }

    // MARK: Pictures of text

    /// A picture of the text in this style, for previews and the alphabet sheet.
    static func image(_ text: String, style: KeyDoFontStyle, width: Int, height: Int, color: NSColor, background: NSColor?) -> NSImage? {
        let rep = PhotoCanvas.bitmap(width: width, height: height) { canvas in
            if let background { background.setFill(); NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill() }
            draw(text, style: style, in: CGRect(x: 10, y: 10, width: canvas.width - 20, height: canvas.height - 20), maxHeight: canvas.height * 0.7, color: color, align: "center")
        }
        return PhotoCanvas.image(rep)
    }

    static func alphabetSheet(style: KeyDoFontStyle, sample: String, color: NSColor) -> NSImage? {
        let rows = ["ABCDEFGHIJKLM", "NOPQRSTUVWXYZ", "0123456789 .,!?&-", sample.isEmpty ? "Happy Birthday" : sample]
        let width = 1600, rowHeight = 260
        let rep = PhotoCanvas.bitmap(width: width, height: rowHeight * rows.count) { canvas in
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()
            for (index, row) in rows.enumerated() {
                let top = canvas.height - CGFloat(index + 1) * CGFloat(rowHeight)
                draw(row, style: style, in: CGRect(x: 30, y: top + 20, width: canvas.width - 60, height: CGFloat(rowHeight) - 40), maxHeight: 160, color: color, align: "center")
            }
        }
        return PhotoCanvas.image(rep)
    }
}

// MARK: - Reading a letter from a picture

enum KeyDoFontAnalyzer {
    /// Looks at a picture of one letter and chooses a style that matches its stroke weight, corners, slant and colours.
    static func analyze(_ source: NSImage) -> KeyDoFontStyle {
        var style = KeyDoFontStyle(id: "mine-" + String(UUID().uuidString.prefix(8)).lowercased(), name: "My font")
        let size = PhotoCanvas.scaled(PhotoCanvas.pixelSize(source), maxSide: 140)
        guard let rep = PhotoCanvas.bitmap(width: Int(size.width), height: Int(size.height), draw: { canvas in
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()
            source.draw(in: NSRect(origin: .zero, size: canvas), from: .zero, operation: .sourceOver, fraction: 1)
        }), let data = rep.bitmapData else { return style }
        let width = rep.pixelsWide, height = rep.pixelsHigh, stride = rep.bytesPerRow
        func channel(_ x: Int, _ y: Int, _ c: Int) -> Int { Int(data[y * stride + x * 4 + c]) }

        var bgR = 0, bgG = 0, bgB = 0
        for (x, y) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)] { bgR += channel(x, y, 0); bgG += channel(x, y, 1); bgB += channel(x, y, 2) }
        bgR /= 4; bgG /= 4; bgB /= 4
        func isInk(_ x: Int, _ y: Int) -> Bool {
            let dr = channel(x, y, 0) - bgR, dg = channel(x, y, 1) - bgG, db = channel(x, y, 2) - bgB
            return dr * dr + dg * dg + db * db > 70 * 70
        }

        var area = 0, minX = width, maxX = 0, minY = height, maxY = 0
        var mask = [Bool](repeating: false, count: width * height)
        for y in 0..<height { for x in 0..<width where isInk(x, y) {
            mask[y * width + x] = true; area += 1
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard area > 20, maxX > minX, maxY > minY else { return style }
        let boxW = Double(maxX - minX + 1), boxH = Double(maxY - minY + 1)

        var perimeter = 0
        for y in minY...maxY { for x in minX...maxX where mask[y * width + x] {
            let edge = x == 0 || y == 0 || x == width - 1 || y == height - 1
                || !mask[y * width + x - 1] || !mask[y * width + x + 1] || !mask[(y - 1) * width + x] || !mask[(y + 1) * width + x]
            if edge { perimeter += 1 }
        } }
        let thickness = 2 * Double(area) / Double(max(1, perimeter))
        style.weight = min(0.3, max(0.05, thickness / boxH))

        // Square corners (blocky letters) against round ones.
        let cw = max(1, Int(boxW * 0.15)), ch = max(1, Int(boxH * 0.15))
        var cornerInk = 0
        for (cx, cy) in [(minX, minY), (maxX - cw + 1, minY), (minX, maxY - ch + 1), (maxX - cw + 1, maxY - ch + 1)] {
            for y in cy..<(cy + ch) { for x in cx..<(cx + cw) where mask[y * width + x] { cornerInk += 1 } }
        }
        let squareCorners = Double(cornerInk) / Double(max(1, 4 * cw * ch)) > 0.45
        style.cap = squareCorners ? 2 : 1
        style.join = squareCorners ? 0 : 1
        style.width = min(1.3, max(0.75, boxW / boxH * 1.1))

        // Lean: how far the top of the letter sits from its bottom.
        var topSum = 0.0, topCount = 0.0, bottomSum = 0.0, bottomCount = 0.0
        for y in minY...maxY { for x in minX...maxX where mask[y * width + x] {
            let fraction = Double(y - minY) / boxH
            if fraction < 0.33 { topSum += Double(x); topCount += 1 } else if fraction > 0.67 { bottomSum += Double(x); bottomCount += 1 }
        } }
        if topCount > 0, bottomCount > 0 {
            let lean = atan((topSum / topCount - bottomSum / bottomCount) / (boxH * 0.66)) * 180 / Double.pi
            if abs(lean) > 4 { style.slant = min(20, max(-20, lean)) }
        }

        // Thick and thin: a pixel whose shortest run is sideways belongs to an upright stem, one whose shortest run is up and down to a bar.
        var runAcross = [Int](repeating: 0, count: width * height), runUp = [Int](repeating: 0, count: width * height)
        for y in minY...maxY {
            var x = minX
            while x <= maxX {
                if mask[y * width + x] {
                    var e = x
                    while e + 1 <= maxX && mask[y * width + e + 1] { e += 1 }
                    for k in x...e { runAcross[y * width + k] = e - x + 1 }
                    x = e + 1
                } else { x += 1 }
            }
        }
        for x in minX...maxX {
            var y = minY
            while y <= maxY {
                if mask[y * width + x] {
                    var e = y
                    while e + 1 <= maxY && mask[(e + 1) * width + x] { e += 1 }
                    for k in y...e { runUp[k * width + x] = e - y + 1 }
                    y = e + 1
                } else { y += 1 }
            }
        }
        var stemSamples: [Int] = [], barSamples: [Int] = []
        for y in minY...maxY { for x in minX...maxX where mask[y * width + x] {
            let a = runAcross[y * width + x], u = runUp[y * width + x]
            if a < u { stemSamples.append(a) } else if u < a { barSamples.append(u) }
        } }
        func median(_ list: [Int]) -> Double { list.isEmpty ? 0 : Double(list.sorted()[list.count / 2]) }
        let stem = median(stemSamples), bar = median(barSamples)
        if stemSamples.count > 40, barSamples.count > 40, stem > 1 {
            let c = 1 - bar / stem
            if c > 0.2 { style.contrast = min(0.75, c); style.weight = min(0.3, max(0.05, stem / boxH)) }
        }

        // Serifs: the same number of runs just above the baseline (or below the top) but clearly wider at the very end.
        func rowRuns(_ y: Int) -> [Int] {
            var runs: [Int] = [], current = 0
            for x in minX...maxX {
                if mask[y * width + x] { current += 1 } else if current > 0 { runs.append(current); current = 0 }
            }
            if current > 0 { runs.append(current) }
            return runs
        }
        if boxH >= 30 {
            let band = max(1, Int(boxH * 0.03)), gap = Int(boxH * 0.14)
            var best = 0.0
            for (edge, inside) in [(maxY - band, maxY - gap), (minY + band, minY + gap)] {
                let ends = rowRuns(edge), body = rowRuns(inside)
                guard ends.count >= 2, ends.count == body.count else { continue }
                let endMean = Double(ends.reduce(0, +)) / Double(ends.count), bodyMean = Double(body.reduce(0, +)) / Double(body.count)
                if bodyMean > 0, endMean > bodyMean * 1.6 { best = max(best, (endMean - bodyMean) / 2 / boxH) }
            }
            if best > 0 { style.serif = min(0.22, max(0.05, best)) }
        }

        // Colours: the ones that cover a fair share of the letter.
        var buckets: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        for y in minY...maxY { for x in minX...maxX where mask[y * width + x] {
            let r = channel(x, y, 0), g = channel(x, y, 1), b = channel(x, y, 2)
            let key = (r >> 5) << 6 | (g >> 5) << 3 | (b >> 5)
            var entry = buckets[key] ?? (0, 0, 0, 0)
            entry.count += 1; entry.r += r; entry.g += g; entry.b += b
            buckets[key] = entry
        } }
        var found: [String] = []
        for entry in buckets.values.sorted(by: { $0.count > $1.count }) where Double(entry.count) / Double(area) >= 0.12 && found.count < 3 {
            let r = entry.r / entry.count, g = entry.g / entry.count, b = entry.b / entry.count
            found.append(String(format: "#%02X%02X%02X", r, g, b))
        }
        let dark = found.count == 1 && (found[0] == "#000000" || NSColor(templateHex: found[0]).brightnessComponent < 0.2)
        style.palette = dark ? [] : found
        return style
    }
}

// MARK: - Cutting the letters out of a picture

extension KeyDoFontAnalyzer {
    struct Capture {
        var glyphs: [String: KeyDoGlyph] = [:]
        var palette: [String] = []
        var found = 0
        var expected = 0
    }

    /// Cuts every letter out of the picture (left to right, row by row) and names them from `letters`, for example "HES".
    /// Parts that belong to one letter, such as the dot inside a block or the dot of an i, stay with it.
    static func capture(_ source: NSImage, letters: String) -> Capture {
        let names = letters.filter { !$0.isWhitespace }.map { String($0) }
        var best = Capture()
        best.expected = names.count
        guard !names.isEmpty else { return best }
        // Try a few strictness levels, so pale, shadowed or photographed letters are still found.
        for threshold in [70, 45, 110, 30] {
            let attempt = captureOnce(source, names: names, threshold: threshold)
            if attempt.found == names.count { return attempt }
            if attempt.found > best.found { best = attempt }
        }
        return best
    }

    private static func captureOnce(_ source: NSImage, names: [String], threshold: Int) -> Capture {
        var result = Capture()
        result.expected = names.count
        let size = PhotoCanvas.scaled(PhotoCanvas.pixelSize(source), maxSide: 640)
        guard let rep = PhotoCanvas.bitmap(width: Int(size.width), height: Int(size.height), draw: { canvas in
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()
            source.draw(in: NSRect(origin: .zero, size: canvas), from: .zero, operation: .sourceOver, fraction: 1)
        }), let data = rep.bitmapData else { return result }
        let width = rep.pixelsWide, height = rep.pixelsHigh, stride = rep.bytesPerRow
        func channel(_ x: Int, _ y: Int, _ c: Int) -> Int { Int(data[y * stride + x * 4 + c]) }

        var bg = [0, 0, 0]
        for (x, y) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)] { for c in 0..<3 { bg[c] += channel(x, y, c) } }
        bg = bg.map { $0 / 4 }
        var dist = [Int](repeating: 0, count: width * height)
        var ink = [Bool](repeating: false, count: width * height)
        var totalInk = 0
        for y in 0..<height { for x in 0..<width {
            let dr = channel(x, y, 0) - bg[0], dg = channel(x, y, 1) - bg[1], db = channel(x, y, 2) - bg[2]
            let d = Int(Double(dr * dr + dg * dg + db * db).squareRoot())
            dist[y * width + x] = d
            if d > threshold { ink[y * width + x] = true; totalInk += 1 }
        } }
        guard totalInk > 30 else { return result }

        // Pieces: groups of touching ink pixels.
        var label = [Int32](repeating: -1, count: width * height)
        var boxes: [(minX: Int, maxX: Int, minY: Int, maxY: Int, area: Int)] = []
        var pending: [Int] = []
        for start in 0..<(width * height) where label[start] == -1 && ink[start] {
            let id = Int32(boxes.count)
            var box = (minX: width, maxX: 0, minY: height, maxY: 0, area: 0)
            label[start] = id
            pending.append(start)
            while let current = pending.popLast() {
                let x = current % width, y = current / width
                box.area += 1
                box.minX = min(box.minX, x); box.maxX = max(box.maxX, x)
                box.minY = min(box.minY, y); box.maxY = max(box.maxY, y)
                if x + 1 < width, label[current + 1] == -1, ink[current + 1] { label[current + 1] = id; pending.append(current + 1) }
                if x > 0, label[current - 1] == -1, ink[current - 1] { label[current - 1] = id; pending.append(current - 1) }
                if y + 1 < height, label[current + width] == -1, ink[current + width] { label[current + width] = id; pending.append(current + width) }
                if y > 0, label[current - width] == -1, ink[current - width] { label[current - width] = id; pending.append(current - width) }
            }
            boxes.append(box)
            if boxes.count > 600 { break }
        }

        // Join the parts of one letter: pieces inside another piece, and dots sitting above a stem.
        var parent = Array(0..<boxes.count)
        func root(_ index: Int) -> Int { var i = index; while parent[i] != i { i = parent[i] }; return i }
        let bySize = boxes.indices.sorted { boxes[$0].area > boxes[$1].area }
        for j in bySize {
            let small = boxes[j]
            for i in bySize where i != j && boxes[i].area > small.area {
                let big = boxes[i]
                let inside = small.minX >= big.minX - 3 && small.maxX <= big.maxX + 3 && small.minY >= big.minY - 3 && small.maxY <= big.maxY + 3
                let overlap = min(small.maxX, big.maxX) - max(small.minX, big.minX) + 1
                let gap = max(small.minY - big.maxY, big.minY - small.maxY)
                let dot = overlap > 0 && Double(overlap) >= 0.6 * Double(small.maxX - small.minX + 1)
                    && Double(small.area) < 0.8 * Double(big.area) && (small.maxY - small.minY) * 10 < (big.maxY - big.minY) * 6 && gap < (big.maxY - big.minY + 1) / 2
                if inside || dot { parent[root(j)] = root(i); break }
            }
        }
        var groups: [Int: (minX: Int, maxX: Int, minY: Int, maxY: Int, area: Int)] = [:]
        for index in boxes.indices {
            let key = root(index)
            let b = boxes[index]
            if var g = groups[key] {
                g.minX = min(g.minX, b.minX); g.maxX = max(g.maxX, b.maxX); g.minY = min(g.minY, b.minY); g.maxY = max(g.maxY, b.maxY); g.area += b.area
                groups[key] = g
            } else { groups[key] = b }
        }
        var kept = groups.filter { Double($0.value.area) >= Double(totalInk) * 0.004 }.map { (root: $0.key, box: $0.value) }
        // More pieces than letters: join the pieces that are closest together until the count matches.
        while kept.count > names.count && kept.count > 1 {
            var pair = (0, 1)
            var nearest = Double.greatestFiniteMagnitude
            for a in 0..<kept.count { for b in (a + 1)..<kept.count {
                let ba = kept[a].box, bb = kept[b].box
                let dx = Double(max(0, max(bb.minX - ba.maxX, ba.minX - bb.maxX)))
                let dy = Double(max(0, max(bb.minY - ba.maxY, ba.minY - bb.maxY)))
                let gap = (dx * dx + dy * dy).squareRoot()
                if gap < nearest { nearest = gap; pair = (a, b) }
            } }
            let first = kept[pair.0], second = kept[pair.1]
            parent[root(second.root)] = root(first.root)
            let joined = (minX: min(first.box.minX, second.box.minX), maxX: max(first.box.maxX, second.box.maxX),
                          minY: min(first.box.minY, second.box.minY), maxY: max(first.box.maxY, second.box.maxY), area: first.box.area + second.box.area)
            kept[pair.0] = (root: root(first.root), box: joined)
            kept.remove(at: pair.1)
        }
        guard !kept.isEmpty else { return result }

        // Reading order: rows from the top, then left to right.
        let heights = kept.map { $0.box.maxY - $0.box.minY + 1 }.sorted()
        let median = Double(heights[heights.count / 2])
        var rows: [[(root: Int, box: (minX: Int, maxX: Int, minY: Int, maxY: Int, area: Int))]] = []
        for piece in kept.sorted(by: { ($0.box.minY + $0.box.maxY) < ($1.box.minY + $1.box.maxY) }) {
            let centre = Double(piece.box.minY + piece.box.maxY) / 2
            if let last = rows.last, let first = last.first, abs(centre - Double(first.box.minY + first.box.maxY) / 2) < 0.6 * median { rows[rows.count - 1].append(piece) }
            else { rows.append([piece]) }
        }
        var ordered: [(root: Int, box: (minX: Int, maxX: Int, minY: Int, maxY: Int, area: Int), row: Int)] = []
        for (rowIndex, row) in rows.enumerated() { for piece in row.sorted(by: { $0.box.minX < $1.box.minX }) { ordered.append((piece.root, piece.box, rowIndex)) } }
        let used = Array(ordered.prefix(names.count))
        let tallest = Double(used.map { $0.box.maxY - $0.box.minY + 3 }.max() ?? 1)

        // Where each row's writing line is: the bottom of its letters that have no tail.
        var baseline: [Int: Int] = [:]
        for rowIndex in Set(used.map { $0.row }) {
            var bottoms: [Int] = []
            for (k, piece) in used.enumerated() where piece.row == rowIndex && !"gjpqyQ,;".contains(names[k]) { bottoms.append(piece.box.maxY + 1) }
            if bottoms.isEmpty { bottoms = used.filter { $0.row == rowIndex }.map { $0.box.maxY + 1 } }
            bottoms.sort()
            baseline[rowIndex] = bottoms[bottoms.count / 2]
        }

        var colours: [String] = []
        var anyLight = false
        for (k, piece) in used.enumerated() {
            let x0 = max(0, piece.box.minX - 1), x1 = min(width - 1, piece.box.maxX + 1)
            let y0 = max(0, piece.box.minY - 1), y1 = min(height - 1, piece.box.maxY + 1)
            let w = x1 - x0 + 1, h = y1 - y0 + 1
            guard w > 1, h > 1, let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let target = out.bitmapData else { continue }
            let outStride = out.bytesPerRow
            var sums = [0, 0, 0], count = 0
            for y in 0..<h { for x in 0..<w {
                let sx = x0 + x, sy = y0 + y
                let index = sy * width + sx
                let own = label[index] < 0 || root(Int(label[index])) == piece.root
                let d = dist[index]
                let alpha = own ? min(1.0, max(0.0, Double(d - 25) / 50.0)) : 0
                var rgb = [0, 0, 0]
                if alpha > 0 {
                    for c in 0..<3 {
                        let value = Double(channel(sx, sy, c))
                        let plain = alpha >= 0.999 ? value : (value - Double(bg[c]) * (1 - alpha)) / alpha
                        rgb[c] = Int(min(255, max(0, plain)))
                    }
                    if alpha >= 0.999 { for c in 0..<3 { sums[c] += rgb[c] }; count += 1 }
                }
                let o = y * outStride + x * 4
                target[o] = UInt8(Double(rgb[0]) * alpha)
                target[o + 1] = UInt8(Double(rgb[1]) * alpha)
                target[o + 2] = UInt8(Double(rgb[2]) * alpha)
                target[o + 3] = UInt8(alpha * 255)
            } }
            guard let png = out.representation(using: .png, properties: [:]) else { continue }
            let drop = max(0, Double(piece.box.maxY + 1 - (baseline[piece.row] ?? (piece.box.maxY + 1)))) / tallest
            let average = count > 0 ? (sums[0] / count, sums[1] / count, sums[2] / count) : (0, 0, 0)
            let hex = String(format: "#%02X%02X%02X", average.0, average.1, average.2)
            let tint = NSColor(templateHex: hex)
            if tint.brightnessComponent > 0.3 || tint.saturationComponent > 0.25 { anyLight = true }
            if !colours.contains(hex) { colours.append(hex) }
            result.glyphs[names[k]] = KeyDoGlyph(png: png, aspect: Double(w) / Double(h), ratio: Double(h) / tallest, drop: drop, colored: true)
        }
        // A picture in one dark colour takes the colour of the text box instead.
        if !anyLight { for key in result.glyphs.keys { result.glyphs[key]?.colored = false } }
        result.palette = anyLight ? Array(colours.prefix(6)) : []
        result.found = result.glyphs.count
        return result
    }
}

extension KeyDoFontAnalyzer {
    /// Fits the width of the drawn letters to the proportions of the letters cut from the picture.
    static func calibrate(_ style: inout KeyDoFontStyle, glyphs: [String: KeyDoGlyph]) {
        var estimates: [Double] = []
        for (key, glyph) in glyphs {
            guard key.count == 1, let ch = key.first, ch.isUppercase || ch.isNumber, glyph.ratio > 0.9 else { continue }
            let box = Double(KeyDoFonts.boxWidth(ch))
            guard box >= 0.55 else { continue }
            estimates.append((glyph.aspect * glyph.ratio - style.weight - 2 * (style.serif ?? 0)) / box)
        }
        guard !estimates.isEmpty else { return }
        let sorted = estimates.sorted()
        style.width = min(1.5, max(0.6, sorted[sorted.count / 2]))
    }
}
