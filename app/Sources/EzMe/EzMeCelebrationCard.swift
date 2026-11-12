// Local renderer for the HBD / HWA cards. No AI key and no network are needed.
//
// The card is the lavender greeting from the KeyDo demo: a small line on top, a cake (or trophy) or the
// person's photo, "Happy Birthday" / "Happy Work Anniversary", the name in italics, one warm line and the
// sender's first name. hbd / hwa save it as a PNG picture; hbdweb / hwaweb save it as one self-contained
// web page (the picture is embedded, so the file can be moved or sent on its own).
import AppKit

enum CelebrationCard {
    enum Kind { case birthday, anniversary }

    struct Spec {
        let kind: Kind
        let web: Bool
    }

    /// Which card an AppBuilder app makes, or nil for a normal app.
    static func spec(forApp app: String) -> Spec? {
        switch UserDefaults.standard.string(forKey: "ezmeBuilderEngine." + app) ?? "" {
        case "card-birthday": return Spec(kind: .birthday, web: false)
        case "card-anniversary": return Spec(kind: .anniversary, web: false)
        case "card-web-birthday": return Spec(kind: .birthday, web: true)
        case "card-web-anniversary": return Spec(kind: .anniversary, web: true)
        default: return nil
        }
    }

    // MARK: - Words

    static func eyebrow(_ kind: Kind) -> String {
        kind == .birthday ? "TODAY IS ALL ABOUT YOU" : "THANK YOU FOR BEING PART OF THE TEAM"
    }

    static func titleLines(_ kind: Kind) -> (String, String) {
        kind == .birthday ? ("Happy", "Birthday") : ("Happy Work", "Anniversary")
    }

    static func message(_ kind: Kind) -> String {
        kind == .birthday
            ? "May your day be filled with little joys, big dreams, and all the magic you bring to the world."
            : "Thank you for your dedication, your ideas and your energy. Here is to many more years of great work together."
    }

    /// The sender's first name, taken from this Mac's account. Empty when it is not known.
    static func senderFirstName() -> String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
    }

    static func readyText(name: String) -> String {
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return who.isEmpty ? "✓ Greeting is ready · attach it, then send it from your app." : "✓ \(who)'s greeting is ready · attach it, then send it from your app."
    }

    // MARK: - Picture (PNG)

    private static let width: CGFloat = 1080
    private static let height: CGFloat = 1350
    private static let accent = NSColor(srgbRed: 0.44, green: 0.24, blue: 0.58, alpha: 1)
    private static let softAccent = NSColor(srgbRed: 0.69, green: 0.53, blue: 0.82, alpha: 1)
    private static let paper = NSColor(srgbRed: 0.941, green: 0.882, blue: 0.961, alpha: 1)
    private static let gold = NSColor(srgbRed: 0.95, green: 0.76, blue: 0.31, alpha: 1)

    static func pngData(kind: Kind, name: String, sender: String, photo: String?) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(kind: kind, name: name, sender: sender, photo: photo)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// A rectangle given by its centre and its distance from the top edge (the drawing origin is bottom left).
    private static func box(_ centerX: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: centerX - w / 2, y: height - top - h, width: w, height: h)
    }

    private static func draw(kind: Kind, name: String, sender: String, photo: String?) {
        let midX = width / 2
        paper.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

        // Two thin frames
        accent.withAlphaComponent(0.28).setStroke()
        let outer = NSBezierPath(rect: NSRect(x: 28, y: 28, width: width - 56, height: height - 56))
        outer.lineWidth = 3
        outer.stroke()
        let inner = NSBezierPath(rect: NSRect(x: 48, y: 48, width: width - 96, height: height - 96))
        inner.lineWidth = 1.5
        inner.stroke()

        // Sparkles
        let spots: [(CGFloat, CGFloat, CGFloat)] = [(130, 250, 22), (940, 190, 18), (880, 470, 26), (170, 520, 16), (960, 760, 14), (120, 1010, 20), (900, 1130, 18), (560, 1110, 14)]
        for spot in spots { sparkle(CGPoint(x: spot.0, y: height - spot.1), spot.2, color: softAccent, alpha: 0.55) }

        // Top line
        let eyebrowFont = NSFont(name: "Georgia-Bold", size: 25) ?? NSFont.boldSystemFont(ofSize: 25)
        text(eyebrow(kind), font: eyebrowFont, color: accent, kern: 4, centerX: midX, top: 96, maxWidth: 820, boxHeight: 70)

        // Picture, or a cake / trophy
        if let photo, let image = NSImage(contentsOfFile: photo), image.size.width > 0, image.size.height > 0 {
            drawPhoto(image, centerX: midX, centerTop: 330, diameter: 340)
        } else if kind == .birthday {
            drawCake(centerX: midX, top: 190)
        } else {
            drawTrophy(centerX: midX, top: 190)
        }

        // Title
        let lines = titleLines(kind)
        let titleSize: CGFloat = kind == .birthday ? 128 : 104
        let titleFont = NSFont(name: "Georgia-Bold", size: titleSize) ?? NSFont.boldSystemFont(ofSize: titleSize)
        text(lines.0, font: titleFont, color: accent, kern: 0, centerX: midX, top: 560, maxWidth: 900, boxHeight: titleSize + 30)
        text(lines.1, font: titleFont, color: accent, kern: 0, centerX: midX, top: 560 + titleSize + 6, maxWidth: 900, boxHeight: titleSize + 30)

        // Name
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !who.isEmpty {
            let nameFont = fitted(who, fontName: "Georgia-BoldItalic", start: 84, maxWidth: 820)
            text(who, font: nameFont, color: accent, kern: 0, centerX: midX, top: 560 + 2 * titleSize + 50, maxWidth: 880, boxHeight: 120)
        }

        // Message and sender
        let messageFont = NSFont(name: "Georgia", size: 36) ?? NSFont.systemFont(ofSize: 36)
        text(message(kind), font: messageFont, color: accent.withAlphaComponent(0.85), kern: 0, centerX: midX, top: 1010, maxWidth: 780, boxHeight: 170)
        sparkle(CGPoint(x: midX, y: height - 1205), 18, color: softAccent, alpha: 0.9)
        let from = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        if !from.isEmpty {
            let fromFont = NSFont(name: "Georgia-Bold", size: 32) ?? NSFont.boldSystemFont(ofSize: 32)
            text(from, font: fromFont, color: accent, kern: 0, centerX: midX, top: 1235, maxWidth: 600, boxHeight: 50)
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
        while size > 30 {
            let font = NSFont(name: fontName, size: size) ?? NSFont.boldSystemFont(ofSize: size)
            if (string as NSString).size(withAttributes: [.font: font]).width <= maxWidth { return font }
            size -= 4
        }
        return NSFont(name: fontName, size: 30) ?? NSFont.boldSystemFont(ofSize: 30)
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

    private static func drawPhoto(_ image: NSImage, centerX: CGFloat, centerTop: CGFloat, diameter: CGFloat) {
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

    private static func drawCake(centerX: CGFloat, top: CGFloat) {
        let line = accent
        // Plate
        line.setStroke()
        let plate = NSBezierPath()
        plate.move(to: CGPoint(x: centerX - 200, y: height - (top + 232)))
        plate.line(to: CGPoint(x: centerX + 200, y: height - (top + 232)))
        plate.lineWidth = 4
        plate.stroke()
        // Tiers
        let base = NSBezierPath(roundedRect: box(centerX, top + 150, 330, 82), xRadius: 10, yRadius: 10)
        softAccent.setFill(); base.fill(); line.setStroke(); base.lineWidth = 4; base.stroke()
        let upper = NSBezierPath(roundedRect: box(centerX, top + 88, 226, 62), xRadius: 10, yRadius: 10)
        NSColor(srgbRed: 0.97, green: 0.93, blue: 0.98, alpha: 1).setFill(); upper.fill(); line.setStroke(); upper.lineWidth = 4; upper.stroke()
        // Icing drops
        for index in 0..<6 {
            let x = centerX - 125 + CGFloat(index) * 50
            let drop = NSBezierPath(ovalIn: box(x, top + 140, 44, 34))
            NSColor(srgbRed: 0.97, green: 0.93, blue: 0.98, alpha: 1).setFill(); drop.fill(); line.setStroke(); drop.lineWidth = 3; drop.stroke()
        }
        // Candles and flames
        for offset in [-56, 0, 56] as [CGFloat] {
            let candle = NSBezierPath(rect: box(centerX + offset, top + 30, 8, 58))
            line.setFill(); candle.fill()
            let flame = NSBezierPath(ovalIn: box(centerX + offset, top - 6, 20, 32))
            gold.setFill(); flame.fill()
        }
    }

    private static func drawTrophy(centerX: CGFloat, top: CGFloat) {
        accent.setStroke()
        // Handles
        for side in [-1, 1] as [CGFloat] {
            let handle = NSBezierPath(ovalIn: box(centerX + side * 100, top + 52, 64, 78))
            handle.lineWidth = 9
            handle.stroke()
        }
        // Cup
        let cup = NSBezierPath()
        cup.move(to: CGPoint(x: centerX - 100, y: height - (top + 30)))
        cup.line(to: CGPoint(x: centerX + 100, y: height - (top + 30)))
        cup.curve(to: CGPoint(x: centerX, y: height - (top + 175)),
                  controlPoint1: CGPoint(x: centerX + 100, y: height - (top + 135)),
                  controlPoint2: CGPoint(x: centerX + 56, y: height - (top + 175)))
        cup.curve(to: CGPoint(x: centerX - 100, y: height - (top + 30)),
                  controlPoint1: CGPoint(x: centerX - 56, y: height - (top + 175)),
                  controlPoint2: CGPoint(x: centerX - 100, y: height - (top + 135)))
        cup.close()
        softAccent.setFill(); cup.fill(); cup.lineWidth = 4; cup.stroke()
        // Stem and base
        let stem = NSBezierPath(rect: box(centerX, top + 172, 26, 36))
        accent.setFill(); stem.fill()
        let foot = NSBezierPath(roundedRect: box(centerX, top + 206, 150, 28), xRadius: 8, yRadius: 8)
        foot.fill()
        sparkle(CGPoint(x: centerX, y: height - (top + 100)), 34, color: gold, alpha: 1)
    }

    // MARK: - Web page (HTML)

    static func htmlPage(kind: Kind, name: String, sender: String, photo: String?) -> String {
        let who = escape(name.trimmingCharacters(in: .whitespacesAndNewlines))
        let from = escape(sender.trimmingCharacters(in: .whitespacesAndNewlines))
        let lines = titleLines(kind)
        let picture: String
        if let photo, let uri = dataURI(photo) {
            picture = "<img class=\"photo\" src=\"\(uri)\" alt=\"\">"
        } else {
            picture = kind == .birthday ? cakeSVG : trophySVG
        }
        let nameBlock = who.isEmpty ? "" : "<p class=\"name\">\(who)</p>"
        let fromBlock = from.isEmpty ? "" : "<p class=\"from\">\(from)</p>"
        let title = who.isEmpty ? "\(lines.0) \(lines.1)" : "\(lines.0) \(lines.1) · \(who)"
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(title)</title>
        <style>
        *{box-sizing:border-box}
        body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#f9f6fc;font-family:Georgia,'Times New Roman',serif;color:#703d94}
        .card{position:relative;width:min(92vw,520px);aspect-ratio:4/5;background:#f0e1f5;border:1px solid #d9bfe6;box-shadow:0 18px 50px #5a2d7a2e;text-align:center;padding:9% 8%;display:flex;flex-direction:column;align-items:center;justify-content:space-between;animation:rise .9s ease both;overflow:hidden}
        .card:before{content:"";position:absolute;inset:14px;border:1px solid #703d9440;pointer-events:none}
        .eyebrow{font-weight:bold;font-size:clamp(9px,2.3vw,12px);letter-spacing:.2em;margin:0}
        .art{height:30%;display:flex;align-items:center;justify-content:center}
        .art svg{height:100%;width:auto}
        .photo{height:100%;aspect-ratio:1;object-fit:cover;border-radius:50%;border:5px solid #fff;outline:2px solid #703d94}
        h1{margin:0;font-size:clamp(34px,10vw,58px);line-height:1.02}
        .name{margin:0;font-style:italic;font-weight:bold;font-size:clamp(24px,7vw,40px)}
        .msg{margin:0;font-size:clamp(12px,3.4vw,17px);line-height:1.5;color:#703d94d9;max-width:84%}
        .from{margin:0;font-weight:bold;font-size:clamp(13px,3.4vw,17px)}
        .spark{position:absolute;width:14px;height:14px;background:#b087d1;clip-path:polygon(50% 0,60% 40%,100% 50%,60% 60%,50% 100%,40% 60%,0 50%,40% 40%);animation:twinkle 2.6s ease-in-out infinite}
        @keyframes twinkle{0%,100%{opacity:.25;transform:scale(.7)}50%{opacity:.95;transform:scale(1.15)}}
        @keyframes rise{from{opacity:0;transform:translateY(14px)}to{opacity:1;transform:none}}
        </style></head><body>
        <main class="card">
        <span class="spark" style="left:11%;top:20%"></span><span class="spark" style="right:12%;top:15%;animation-delay:.6s"></span>
        <span class="spark" style="right:9%;top:40%;animation-delay:1.1s"></span><span class="spark" style="left:9%;bottom:20%;animation-delay:1.6s"></span>
        <p class="eyebrow">\(eyebrow(kind))</p>
        <div class="art">\(picture)</div>
        <h1>\(lines.0)<br>\(lines.1)</h1>
        \(nameBlock)
        <p class="msg">\(message(kind))</p>
        \(fromBlock)
        </main></body></html>
        """
    }

    private static let cakeSVG = "<svg viewBox=\"0 0 260 220\" xmlns=\"http://www.w3.org/2000/svg\"><g stroke=\"#703d94\" stroke-width=\"3\" stroke-linejoin=\"round\"><path d=\"M130 18c6 8 6 16 0 22-6-6-6-14 0-22z\" fill=\"#f2c250\" stroke=\"none\"/><path d=\"M84 30c6 8 6 16 0 22-6-6-6-14 0-22z\" fill=\"#f2c250\" stroke=\"none\"/><path d=\"M176 30c6 8 6 16 0 22-6-6-6-14 0-22z\" fill=\"#f2c250\" stroke=\"none\"/><path d=\"M130 44v36M84 56v24M176 56v24\" stroke-width=\"6\"/><rect x=\"62\" y=\"80\" width=\"136\" height=\"46\" rx=\"8\" fill=\"#f8eefb\"/><rect x=\"36\" y=\"126\" width=\"188\" height=\"58\" rx=\"8\" fill=\"#b087d1\"/><path d=\"M20 190h220\"/></g></svg>"

    private static let trophySVG = "<svg viewBox=\"0 0 260 220\" xmlns=\"http://www.w3.org/2000/svg\"><g stroke=\"#703d94\" stroke-width=\"4\" stroke-linejoin=\"round\" fill=\"none\"><ellipse cx=\"58\" cy=\"72\" rx=\"26\" ry=\"34\" stroke-width=\"7\"/><ellipse cx=\"202\" cy=\"72\" rx=\"26\" ry=\"34\" stroke-width=\"7\"/><path d=\"M62 24h136c0 52-26 98-68 98S62 76 62 24z\" fill=\"#b087d1\"/><path d=\"M130 56l8 18 20 2-15 13 5 20-18-11-18 11 5-20-15-13 20-2z\" fill=\"#f2c250\" stroke=\"none\"/><rect x=\"118\" y=\"120\" width=\"24\" height=\"40\" fill=\"#703d94\"/><rect x=\"70\" y=\"158\" width=\"120\" height=\"26\" rx=\"8\" fill=\"#703d94\"/></g></svg>"

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func dataURI(_ path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let mime: String
        switch ext {
        case "png": mime = "image/png"
        case "gif": mime = "image/gif"
        case "webp": mime = "image/webp"
        case "heic": mime = "image/heic"
        default: mime = "image/jpeg"
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}
