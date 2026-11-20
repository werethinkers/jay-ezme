// Wish Studio looks: transparent PNG backgrounds. KeyDo draws four starter Happy Birthday looks itself; people can also
// import PNGs made by ChatGPT. Looks are kept per app, as files next to the template pictures.
import SwiftUI
import AppKit

@MainActor enum WishLookStore {
    private static var cache: [String: NSImage] = [:]
    private static func key(_ appID: String) -> String { "wishLooks." + appID }

    static func files(_ appID: String) -> [String] { UserDefaults.standard.stringArray(forKey: key(appID)) ?? [] }

    @discardableResult static func add(_ image: NSImage, appID: String) -> String? {
        guard let data = TemplateImages.png(image) else { return nil }
        let file = "look-" + String(UUID().uuidString.prefix(8)) + ".png"
        do { try data.write(to: TemplateStore.shared.logoURL(file), options: .atomic) } catch { return nil }
        UserDefaults.standard.set(files(appID) + [file], forKey: key(appID))
        return file
    }

    static func remove(_ file: String, appID: String) {
        UserDefaults.standard.set(files(appID).filter { $0 != file }, forKey: key(appID))
        try? FileManager.default.removeItem(at: TemplateStore.shared.logoURL(file))
        cache[file] = nil
    }

    static func image(_ file: String) -> NSImage? {
        if let known = cache[file] { return known }
        guard let loaded = NSImage(contentsOf: TemplateStore.shared.logoURL(file)) else { return nil }
        cache[file] = loaded
        return loaded
    }

    static func selectedFile(_ appID: String) -> String? { UserDefaults.standard.string(forKey: "wishLookSelected." + appID) }
    static func select(_ file: String?, appID: String) { UserDefaults.standard.set(file, forKey: "wishLookSelected." + appID) }

    static func backgroundHex(_ appID: String) -> String { UserDefaults.standard.string(forKey: "wishBackground." + appID) ?? "#FFF4DC" }
    static func setBackgroundHex(_ hex: String, appID: String) { UserDefaults.standard.set(hex, forKey: "wishBackground." + appID) }
}

// MARK: - KeyDo draws four looks

@MainActor enum WishLookMaker {
    static let names = ["Ribbon", "Midnight", "Party", "Marigold"]

    static func make(size: Int = 1600) -> [NSImage] { (0..<4).compactMap { draw($0, size: size) } }

    private static func color(_ hex: String, _ alpha: CGFloat = 1) -> NSColor { NSColor(templateHex: hex).withAlphaComponent(alpha) }

    private static func draw(_ index: Int, size: Int) -> NSImage? {
        guard let rep = TemplateImages.bitmap(width: size, height: size), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let s = CGFloat(size)
        var seed = UInt64(7919 * (index + 3))
        func random() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 10000) / 10000
        }
        func inCentre(_ x: CGFloat, _ y: CGFloat) -> Bool { x > s * 0.13 && x < s * 0.87 && y > s * 0.13 && y < s * 0.87 }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: NSColor) { c.setFill(); NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill() }
        func bit(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ angle: CGFloat, _ c: NSColor) {
            let path = NSBezierPath(rect: NSRect(x: -w / 2, y: -h / 2, width: w, height: h))
            var move = AffineTransform(translationByX: x, byY: y)
            move.rotate(byRadians: angle)
            path.transform(using: move)
            c.setFill(); path.fill()
        }
        func star(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: NSColor) {
            let path = NSBezierPath()
            for point in 0..<10 {
                let radius = point % 2 == 0 ? r : r * 0.42
                let angle = CGFloat.pi / 2 + CGFloat(point) * CGFloat.pi / 5
                let spot = CGPoint(x: x + cos(angle) * radius, y: y + sin(angle) * radius)
                if point == 0 { path.move(to: spot) } else { path.line(to: spot) }
            }
            path.close(); c.setFill(); path.fill()
        }
        func confetti(_ palette: [String], count: Int) {
            for _ in 0..<count {
                let x = random() * s, y = random() * s
                if inCentre(x, y) { continue }
                let c = color(palette[Int(random() * CGFloat(palette.count)) % palette.count], 0.9)
                if random() > 0.5 { circle(x, y, s * (0.004 + random() * 0.006), c) } else { bit(x, y, s * 0.02, s * 0.007, random() * 3, c) }
            }
        }
        func frame(_ inset: CGFloat, _ width: CGFloat, _ c: NSColor, radius: CGFloat = 0.03) {
            let path = NSBezierPath(roundedRect: NSRect(x: s * inset, y: s * inset, width: s * (1 - 2 * inset), height: s * (1 - 2 * inset)), xRadius: s * radius, yRadius: s * radius)
            path.lineWidth = s * width
            c.setStroke(); path.stroke()
        }
        func bow(_ x: CGFloat, _ y: CGFloat, _ c: NSColor, _ light: NSColor) {
            let r = s * 0.045
            for side in [-1.0, 1.0] {
                let wing = NSBezierPath(ovalIn: NSRect(x: -r * 1.2, y: -r * 0.55, width: r * 2.4, height: r * 1.1))
                var move = AffineTransform(translationByX: x + CGFloat(side) * r * 1.05, byY: y)
                move.rotate(byRadians: CGFloat(side) * 0.35)
                wing.transform(using: move)
                c.setFill(); wing.fill()
            }
            circle(x, y, r * 0.5, light)
        }
        func balloon(_ x: CGFloat, _ y: CGFloat, _ c: NSColor) {
            let w = s * 0.085, h = s * 0.1
            let string = NSBezierPath()
            string.move(to: CGPoint(x: x, y: y - h / 2))
            string.curve(to: CGPoint(x: x + s * 0.02, y: y - h / 2 - s * 0.14), controlPoint1: CGPoint(x: x - s * 0.02, y: y - h / 2 - s * 0.05), controlPoint2: CGPoint(x: x + s * 0.03, y: y - h / 2 - s * 0.09))
            string.lineWidth = s * 0.003
            color("#8A7F78", 0.8).setStroke(); string.stroke()
            c.setFill(); NSBezierPath(ovalIn: NSRect(x: x - w / 2, y: y - h / 2, width: w, height: h)).fill()
            color("#FFFFFF", 0.35).setFill(); NSBezierPath(ovalIn: NSRect(x: x - w * 0.28, y: y + h * 0.1, width: w * 0.2, height: h * 0.28)).fill()
        }
        func flower(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ petal: NSColor, _ centre: NSColor) {
            for point in 0..<6 {
                let angle = CGFloat(point) * CGFloat.pi / 3
                circle(x + cos(angle) * r * 0.62, y + sin(angle) * r * 0.62, r * 0.42, petal)
            }
            circle(x, y, r * 0.32, centre)
        }

        switch index {
        case 0:
            let palette = ["#C2415D", "#F4A5B5", "#E8798F", "#F9D3DB"]
            frame(0.035, 0.012, color("#C2415D", 0.9))
            frame(0.058, 0.004, color("#F4A5B5", 0.9))
            for (x, y) in [(0.07, 0.93), (0.93, 0.93), (0.07, 0.07), (0.93, 0.07)] { bow(s * CGFloat(x), s * CGFloat(y), color("#C2415D"), color("#F4A5B5")) }
            confetti(palette, count: 90)
        case 1:
            let palette = ["#E9B949", "#F6D98B", "#B9852B"]
            frame(0.04, 0.006, color("#E9B949", 0.95), radius: 0.01)
            frame(0.056, 0.003, color("#F6D98B", 0.8), radius: 0.01)
            for (x, y) in [(0.09, 0.91), (0.91, 0.91), (0.09, 0.09), (0.91, 0.09)] { star(s * CGFloat(x), s * CGFloat(y), s * 0.045, color("#E9B949")) }
            for _ in 0..<26 {
                let x = random() * s, y = random() * s
                if !inCentre(x, y) { star(x, y, s * (0.01 + random() * 0.016), color(palette[Int(random() * 3) % 3], 0.9)) }
            }
            confetti(palette, count: 40)
        case 2:
            let colours = ["#E5546B", "#F2A83B", "#3FA7A0", "#7B6CC9", "#F27BA8"]
            for (offset, name) in colours.enumerated() {
                let column = CGFloat(offset % 3)
                let row = CGFloat(offset / 3)
                let wobble = CGFloat(offset % 2) * 0.03
                let leftX: CGFloat = s * (0.07 + column * 0.055)
                let rightX: CGFloat = s * (0.93 - column * 0.055)
                let leftY: CGFloat = s * (0.88 - row * 0.06 + wobble)
                let rightY: CGFloat = s * (0.88 - row * 0.06 + 0.03 - wobble)
                balloon(leftX, leftY, color(name))
                balloon(rightX, rightY, color(colours[(offset + 2) % colours.count]))
            }
            let streamer = NSBezierPath()
            streamer.move(to: CGPoint(x: s * 0.15, y: s * 0.965))
            streamer.curve(to: CGPoint(x: s * 0.85, y: s * 0.965), controlPoint1: CGPoint(x: s * 0.35, y: s * 0.9), controlPoint2: CGPoint(x: s * 0.65, y: s * 1.02))
            streamer.lineWidth = s * 0.006
            color("#F2A83B", 0.9).setStroke(); streamer.stroke()
            confetti(colours, count: 110)
        default:
            let petal = color("#F2A83B"), centre = color("#C4552F")
            for (x, y) in [(0.08, 0.92), (0.92, 0.92), (0.08, 0.08), (0.92, 0.08)] { flower(s * CGFloat(x), s * CGFloat(y), s * 0.06, petal, centre) }
            for step in 1..<9 {
                let t = CGFloat(step) / 9
                flower(s * (0.08 + 0.84 * t), s * 0.955, s * 0.022, color("#F7C46A"), color("#C4552F"))
                flower(s * (0.08 + 0.84 * t), s * 0.045, s * 0.022, color("#F7C46A"), color("#C4552F"))
                let leaf = NSBezierPath(ovalIn: NSRect(x: s * (0.08 + 0.84 * t) - s * 0.02, y: s * 0.915, width: s * 0.04, height: s * 0.014))
                color("#4F8A5B", 0.85).setFill(); leaf.fill()
            }
            confetti(["#F2A83B", "#C4552F", "#4F8A5B"], count: 50)
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }
}
