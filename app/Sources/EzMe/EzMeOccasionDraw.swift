// Draws an occasion card straight into a picture with AppKit, the same way the hbd and hwa cards are drawn.
// No web view is involved, so the picture can never come out blank.
import AppKit

enum OccasionCardDrawer {
    private static let width: CGFloat = 1080
    private static let height: CGFloat = 1350

    static func color(_ hex: String?, fallback: NSColor) -> NSColor {
        guard var text = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return fallback }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return fallback }
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    static func pngData(card: WishCard, design: WishDesign, photo: String?) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(card: card, design: design, photo: photo)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private static func box(_ centerX: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: centerX - w / 2, y: height - top - h, width: w, height: h)
    }

    private static func serif(_ style: WishFontStyle, bold: Bool, italic: Bool = false) -> String {
        _ = style
        return bold ? (italic ? "Georgia-BoldItalic" : "Georgia-Bold") : "Georgia"
    }

    private static func draw(card: WishCard, design: WishDesign, photo: String?) {
        let paper = color(card.backgroundHex, fallback: color(design.background, fallback: .white))
        let accent = color(card.accentHex, fallback: color(design.accent, fallback: .systemPurple))
        let ink = color(card.inkHex, fallback: color(design.ink, fallback: .black))
        let midX = width / 2
        paper.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

        accent.withAlphaComponent(0.35).setStroke()
        let outer = NSBezierPath(rect: NSRect(x: 28, y: 28, width: width - 56, height: height - 56))
        outer.lineWidth = 3
        outer.stroke()
        let inner = NSBezierPath(rect: NSRect(x: 48, y: 48, width: width - 96, height: height - 96))
        inner.lineWidth = 1.5
        inner.stroke()

        let spots: [(CGFloat, CGFloat, CGFloat)] = [(130, 250, 22), (940, 190, 18), (880, 470, 26), (170, 520, 16), (960, 760, 14), (120, 1010, 20), (900, 1130, 18), (560, 1110, 14)]
        for spot in spots { sparkle(CGPoint(x: spot.0, y: height - spot.1), spot.2, color: accent, alpha: 0.5) }

        let eyebrow = card.value(for: "eyebrow").uppercased()
        if !eyebrow.isEmpty {
            text(eyebrow, font: NSFont(name: "Georgia-Bold", size: 25) ?? .boldSystemFont(ofSize: 25), color: accent, kern: 4, centerX: midX, top: 96, maxWidth: 820, boxHeight: 70)
        }

        if let photo, let image = NSImage(contentsOfFile: photo), image.size.width > 0, image.size.height > 0 {
            drawPhoto(image, centerX: midX, centerTop: 330, diameter: 340, accent: accent)
        } else {
            drawEmblem(symbol: card.artwork, centerX: midX, centerTop: 330, accent: accent, paper: paper)
        }

        let title = card.value(for: "title")
        let titleFont = fitted(title, fontName: "Georgia-Bold", start: 112, maxWidth: 880)
        let titleHeight = (title as NSString).boundingRect(with: NSSize(width: 900, height: 600), options: [.usesLineFragmentOrigin], attributes: [.font: titleFont]).height
        text(title, font: titleFont, color: accent, kern: 0, centerX: midX, top: 560, maxWidth: 900, boxHeight: max(150, titleHeight + 30))

        let who = card.value(for: "name").trimmingCharacters(in: .whitespacesAndNewlines)
        if !who.isEmpty {
            text(who, font: fitted(who, fontName: "Georgia-BoldItalic", start: 92, maxWidth: 820), color: ink, kern: 0, centerX: midX, top: 560 + max(150, titleHeight + 30) + 20, maxWidth: 880, boxHeight: 130)
        }

        let message = card.value(for: "message")
        text(message, font: NSFont(name: "Georgia", size: 36) ?? .systemFont(ofSize: 36), color: ink.withAlphaComponent(0.85), kern: 0, centerX: midX, top: 1010, maxWidth: 780, boxHeight: 170)
        sparkle(CGPoint(x: midX, y: height - 1205), 18, color: accent, alpha: 0.9)
        let from = card.value(for: "from").trimmingCharacters(in: .whitespacesAndNewlines)
        if !from.isEmpty {
            text(from, font: NSFont(name: "Georgia-Bold", size: 32) ?? .boldSystemFont(ofSize: 32), color: accent, kern: 0, centerX: midX, top: 1235, maxWidth: 600, boxHeight: 50)
        }
    }

    private static func text(_ string: String, font: NSFont, color: NSColor, kern: CGFloat, centerX: CGFloat, top: CGFloat, maxWidth: CGFloat, boxHeight: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 10
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style, .kern: kern]
        NSAttributedString(string: string, attributes: attributes).draw(in: box(centerX, top, maxWidth, boxHeight))
    }

    private static func fitted(_ string: String, fontName: String, start: CGFloat, maxWidth: CGFloat) -> NSFont {
        var size = start
        while size > 44 {
            let font = NSFont(name: fontName, size: size) ?? NSFont.boldSystemFont(ofSize: size)
            if (string as NSString).size(withAttributes: [.font: font]).width <= maxWidth { return font }
            size -= 4
        }
        // Long titles wrap onto two lines at a smaller size.
        return NSFont(name: fontName, size: 76) ?? NSFont.boldSystemFont(ofSize: 76)
    }

    private static func sparkle(_ center: CGPoint, _ radius: CGFloat, color: NSColor, alpha: CGFloat) {
        let path = NSBezierPath()
        let innerRadius = radius * 0.22
        for index in 0..<8 {
            let angle = CGFloat(index) * .pi / 4 - .pi / 2
            let distance = index % 2 == 0 ? radius : innerRadius
            let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        color.withAlphaComponent(alpha).setFill()
        path.fill()
    }

    private static func drawEmblem(symbol: String, centerX: CGFloat, centerTop: CGFloat, accent: NSColor, paper: NSColor) {
        let diameter: CGFloat = 300
        let frame = box(centerX, centerTop - diameter / 2, diameter, diameter)
        accent.withAlphaComponent(0.14).setFill()
        NSBezierPath(ovalIn: frame).fill()
        accent.setStroke()
        let ring = NSBezierPath(ovalIn: frame.insetBy(dx: 10, dy: 10))
        ring.lineWidth = 4
        ring.stroke()
        let config = NSImage.SymbolConfiguration(pointSize: 140, weight: .regular)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        guard let base = image?.withSymbolConfiguration(config) else { return }
        let tinted = NSImage(size: base.size)
        tinted.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: base.size))
        accent.set()
        NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let scale = min(170 / max(base.size.width, 1), 170 / max(base.size.height, 1))
        let size = NSSize(width: base.size.width * scale, height: base.size.height * scale)
        tinted.draw(in: NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height))
    }

    private static func drawPhoto(_ image: NSImage, centerX: CGFloat, centerTop: CGFloat, diameter: CGFloat, accent: NSColor) {
        let frame = box(centerX, centerTop - diameter / 2, diameter, diameter)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: frame).addClip()
        let side = min(image.size.width, image.size.height)
        let source = NSRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        image.draw(in: frame, from: source, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.setStroke()
        let ring = NSBezierPath(ovalIn: frame.insetBy(dx: -6, dy: -6))
        ring.lineWidth = 12
        ring.stroke()
        accent.setStroke()
        let edge = NSBezierPath(ovalIn: frame.insetBy(dx: -14, dy: -14))
        edge.lineWidth = 3
        edge.stroke()
    }
}
