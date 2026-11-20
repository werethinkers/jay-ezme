// Gifting drawing: one fixed-size box (real materials), jars drawn to scale from above, contents, filling and lid flowers.
// Everything is drawn in centimetres first and scaled, so a jar that fits in the picture fits in the box.
import Foundation
import SwiftUI
import AppKit

struct GiftRNG {
    var s: UInt64
    init(_ seed: Int) { s = UInt64(truncatingIfNeeded: seed) &* 0x9E3779B97F4A7C15 &+ 0x1234567 }
    mutating func next() -> CGFloat {
        s = s &+ 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        let top: UInt64 = z >> 11
        return CGFloat(Double(top) / 9007199254740992.0)
    }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
}

/// Where the box sits inside a drawing area.
struct GiftFrame {
    var scale: CGFloat
    var origin: CGPoint

    init(size: CGSize, dims: Bool) {
        let ml: CGFloat = dims ? 30 : 8
        let mb: CGFloat = dims ? 28 : 8
        let mt: CGFloat = 8
        let mr: CGFloat = 8
        let sx = (size.width - ml - mr) / CGFloat(GiftBoxSpec.outerW)
        let sy = (size.height - mt - mb) / CGFloat(GiftBoxSpec.outerD)
        let s = max(1, min(sx, sy))
        let w = s * CGFloat(GiftBoxSpec.outerW)
        let h = s * CGFloat(GiftBoxSpec.outerD)
        scale = s
        origin = CGPoint(x: ml + (size.width - ml - mr - w) / 2, y: mt + (size.height - mt - mb - h) / 2)
    }

    var outer: CGRect {
        return CGRect(x: origin.x, y: origin.y, width: scale * CGFloat(GiftBoxSpec.outerW), height: scale * CGFloat(GiftBoxSpec.outerD))
    }

    var inner: CGRect {
        let w = scale * CGFloat(GiftBoxSpec.wall)
        return outer.insetBy(dx: w, dy: w)
    }

    func point(_ x: Double, _ y: Double) -> CGPoint {
        let w = scale * CGFloat(GiftBoxSpec.wall)
        return CGPoint(x: origin.x + w + scale * CGFloat(x), y: origin.y + w + scale * CGFloat(y))
    }

    func lidPoint(_ x: Double, _ y: Double) -> CGPoint {
        return CGPoint(x: origin.x + scale * CGFloat(x), y: origin.y + scale * CGFloat(y))
    }
}

enum GiftArt {
    static func col(_ hex: String, _ a: Double = 1) -> Color { Color(wishHex: hex).opacity(a) }

    // MARK: Materials

    static func material(_ ctx: inout GraphicsContext, rect: CGRect, radius: CGFloat, finish: BoxFinish, seed: Int, detail: Bool) {
        let path = Path(roundedRect: rect, cornerRadius: radius)
        var c = ctx
        let light = GiftColor.shade(finish.hex, 1.16)
        let dark = GiftColor.shade(finish.hex, 0.8)
        let grad = Gradient(colors: [col(light), col(finish.hex), col(dark)])
        c.fill(path, with: .linearGradient(grad, startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        c.clip(to: path)
        var rng = GiftRNG(seed)
        switch finish.material {
        case .wood: wood(&c, rect, finish, &rng, detail)
        case .metal: metal(&c, rect, &rng, detail)
        case .leather: leather(&c, rect, finish, &rng, detail)
        case .rubber: rubber(&c, rect, &rng, detail)
        case .pu: pu(&c, rect, finish, &rng, detail)
        }
        ctx.stroke(path, with: .color(Color.black.opacity(0.35)), lineWidth: 1.4)
    }

    private static func wood(_ c: inout GraphicsContext, _ r: CGRect, _ f: BoxFinish, _ rng: inout GiftRNG, _ detail: Bool) {
        let n = detail ? 52 : 18
        let darkHex = GiftColor.shade(f.hex, 0.6)
        for i in 0..<n {
            let y = r.minY + r.height * CGFloat(i) / CGFloat(n) + rng.range(-1.5, 1.5)
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: y))
            var x = r.minX
            let step = max(20, r.width / 7)
            while x < r.maxX {
                let nx = x + step
                let cy = y + rng.range(-3.5, 3.5)
                p.addQuadCurve(to: CGPoint(x: nx, y: y + rng.range(-1.5, 1.5)), control: CGPoint(x: x + step / 2, y: cy))
                x = nx
            }
            c.stroke(p, with: .color(col(darkHex, Double(rng.range(0.10, 0.30)))), lineWidth: rng.range(0.5, 1.5))
        }
        if detail {
            for _ in 0..<2 {
                let cx = rng.range(r.minX + r.width * 0.15, r.maxX - r.width * 0.15)
                let cy = rng.range(r.minY + r.height * 0.15, r.maxY - r.height * 0.15)
                for k in 1...3 {
                    let rx = CGFloat(k) * 6
                    let ring = Path(ellipseIn: CGRect(x: cx - rx * 1.8, y: cy - rx * 0.7, width: rx * 3.6, height: rx * 1.4))
                    c.stroke(ring, with: .color(col(darkHex, 0.25)), lineWidth: 0.8)
                }
            }
        }
    }

    private static func metal(_ c: inout GraphicsContext, _ r: CGRect, _ rng: inout GiftRNG, _ detail: Bool) {
        let n = detail ? 150 : 45
        for i in 0..<n {
            let y = r.minY + r.height * CGFloat(i) / CGFloat(n)
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: y))
            p.addLine(to: CGPoint(x: r.maxX, y: y + rng.range(-0.4, 0.4)))
            let light = i % 2 == 0
            c.stroke(p, with: .color(light ? Color.white.opacity(Double(rng.range(0.05, 0.16))) : Color.black.opacity(Double(rng.range(0.04, 0.12)))), lineWidth: 0.7)
        }
        let sheen = Gradient(colors: [Color.white.opacity(0), Color.white.opacity(0.30), Color.white.opacity(0)])
        c.fill(Path(r), with: .linearGradient(sheen, startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
    }

    private static func leather(_ c: inout GraphicsContext, _ r: CGRect, _ f: BoxFinish, _ rng: inout GiftRNG, _ detail: Bool) {
        let n = detail ? 1000 : 220
        for _ in 0..<n {
            let x = rng.range(r.minX, r.maxX)
            let y = rng.range(r.minY, r.maxY)
            let d = rng.range(0.8, 2.0)
            let dark = rng.next() > 0.5
            let dot = Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d))
            c.fill(dot, with: .color(dark ? Color.black.opacity(0.16) : Color.white.opacity(0.10)))
        }
        stitch(&c, r, f)
    }

    private static func rubber(_ c: inout GraphicsContext, _ r: CGRect, _ rng: inout GiftRNG, _ detail: Bool) {
        let n = detail ? 700 : 160
        for _ in 0..<n {
            let x = rng.range(r.minX, r.maxX)
            let y = rng.range(r.minY, r.maxY)
            let d = rng.range(0.6, 1.4)
            let dot = Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d))
            c.fill(dot, with: .color(rng.next() > 0.5 ? Color.black.opacity(0.14) : Color.white.opacity(0.07)))
        }
        let ridge = Path(roundedRect: r.insetBy(dx: r.width * 0.03, dy: r.width * 0.03), cornerRadius: 6)
        c.stroke(ridge, with: .color(Color.black.opacity(0.16)), lineWidth: 2)
    }

    private static func pu(_ c: inout GraphicsContext, _ r: CGRect, _ f: BoxFinish, _ rng: inout GiftRNG, _ detail: Bool) {
        let sheen = Gradient(colors: [Color.white.opacity(0), Color.white.opacity(0.34), Color.white.opacity(0.02)])
        c.fill(Path(r), with: .linearGradient(sheen, startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX * 0.75, y: r.maxY)))
        let n = detail ? 160 : 40
        for _ in 0..<n {
            let x = rng.range(r.minX, r.maxX)
            let y = rng.range(r.minY, r.maxY)
            let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 1.1, height: 1.1))
            c.fill(dot, with: .color(Color.black.opacity(0.08)))
        }
        stitch(&c, r, f)
    }

    private static func stitch(_ c: inout GraphicsContext, _ r: CGRect, _ f: BoxFinish) {
        let inset = max(5, r.width * 0.022)
        let p = Path(roundedRect: r.insetBy(dx: inset, dy: inset), cornerRadius: 4)
        c.stroke(p, with: .color(col(f.stitchHex, 0.95)), style: StrokeStyle(lineWidth: 1.3, dash: [5, 3]))
    }

    // MARK: Open box (top view, lid off)

    static func openBox(_ ctx: inout GraphicsContext, size: CGSize, config: GiftConfig, jarsShown: Int, dims: Bool, detail: Bool) {
        let fr = GiftFrame(size: size, dims: dims)
        let finish = config.finish
        let outer = fr.outer
        let radius = fr.scale * 1.0
        var sc = ctx
        sc.addFilter(.shadow(color: Color.black.opacity(0.28), radius: 8, x: 3, y: 5))
        sc.fill(Path(roundedRect: outer, cornerRadius: radius), with: .color(col(finish.hex)))
        material(&ctx, rect: outer, radius: radius, finish: finish, seed: 11, detail: detail)

        let inner = fr.inner
        let innerPath = Path(roundedRect: inner, cornerRadius: fr.scale * 0.5)
        let liner = Gradient(colors: [col(GiftColor.shade(finish.linerHex, 0.82)), col(finish.linerHex), col(GiftColor.shade(finish.linerHex, 0.9))])
        ctx.fill(innerPath, with: .linearGradient(liner, startPoint: CGPoint(x: inner.minX, y: inner.minY), endPoint: CGPoint(x: inner.maxX, y: inner.maxY)))

        let layout = GiftCatalogue.layout(config.layoutID)
        var clipped = ctx
        clipped.clip(to: innerPath)
        filling(&clipped, fr: fr, config: config, layout: layout, detail: detail)
        let count = min(jarsShown, min(config.jars.count, layout.slots.count))
        if count > 0 {
            for i in 0..<count {
                let slot = layout.slots[i]
                let d = GiftCatalogue.jarDiameter(slot: slot, size: config.jars[i].sizeID)
                let centre = fr.point(slot.x, slot.y)
                jar(&clipped, centre: centre, diameter: CGFloat(d) * fr.scale, spec: config.jars[i], seed: 100 + i, detail: detail)
            }
        }
        ctx.stroke(innerPath, with: .color(Color.black.opacity(0.35)), lineWidth: 1.6)

        if dims {
            dimensions(&ctx, fr: fr)
            if count > 0 { jarLabels(&ctx, fr: fr, config: config, layout: layout, count: count) }
        }
    }

    private static func dimensions(_ ctx: inout GraphicsContext, fr: GiftFrame) {
        let o = fr.outer
        let ink = Color(wishHex: "#5B5668")
        let y = o.maxY + 14
        var h = Path()
        h.move(to: CGPoint(x: o.minX, y: y)); h.addLine(to: CGPoint(x: o.maxX, y: y))
        h.move(to: CGPoint(x: o.minX, y: y - 4)); h.addLine(to: CGPoint(x: o.minX, y: y + 4))
        h.move(to: CGPoint(x: o.maxX, y: y - 4)); h.addLine(to: CGPoint(x: o.maxX, y: y + 4))
        ctx.stroke(h, with: .color(ink), lineWidth: 1)
        let label = "\(GiftBoxSpec.cm(GiftBoxSpec.outerW)) cm outer \u{00B7} inner \(GiftBoxSpec.cm(GiftBoxSpec.innerW)) cm"
        let hl = ctx.resolve(Text(label).font(.system(size: 10, weight: .semibold)).foregroundColor(ink))
        ctx.draw(hl, at: CGPoint(x: o.midX, y: y + 9), anchor: .center)

        let x = o.minX - 14
        var v = Path()
        v.move(to: CGPoint(x: x, y: o.minY)); v.addLine(to: CGPoint(x: x, y: o.maxY))
        v.move(to: CGPoint(x: x - 4, y: o.minY)); v.addLine(to: CGPoint(x: x + 4, y: o.minY))
        v.move(to: CGPoint(x: x - 4, y: o.maxY)); v.addLine(to: CGPoint(x: x + 4, y: o.maxY))
        ctx.stroke(v, with: .color(ink), lineWidth: 1)
        var r = ctx
        r.translateBy(x: x - 9, y: o.midY)
        r.rotate(by: .degrees(-90))
        let vl = r.resolve(Text("\(GiftBoxSpec.cm(GiftBoxSpec.outerD)) cm").font(.system(size: 10, weight: .semibold)).foregroundColor(ink))
        r.draw(vl, at: .zero, anchor: .center)
    }

    private static func jarLabels(_ ctx: inout GraphicsContext, fr: GiftFrame, config: GiftConfig, layout: GiftLayout, count: Int) {
        for i in 0..<count {
            let slot = layout.slots[i]
            let d = GiftCatalogue.jarDiameter(slot: slot, size: config.jars[i].sizeID)
            let c = fr.point(slot.x, slot.y)
            let guide = Path(ellipseIn: CGRect(x: c.x - CGFloat(slot.maxD) * fr.scale / 2, y: c.y - CGFloat(slot.maxD) * fr.scale / 2,
                                               width: CGFloat(slot.maxD) * fr.scale, height: CGFloat(slot.maxD) * fr.scale))
            ctx.stroke(guide, with: .color(Color.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            let text = ctx.resolve(Text("\u{00D8} \(GiftBoxSpec.cm(d)) cm").font(.system(size: 9, weight: .bold)).foregroundColor(Color.white))
            let y = c.y + CGFloat(slot.maxD) * fr.scale / 2 + 8
            let bg = Path(roundedRect: CGRect(x: c.x - 25, y: y - 7, width: 50, height: 14), cornerRadius: 7)
            ctx.fill(bg, with: .color(Color.black.opacity(0.55)))
            ctx.draw(text, at: CGPoint(x: c.x, y: y), anchor: .center)
        }
    }

    // MARK: Filling (between the jars)

    private static func filling(_ ctx: inout GraphicsContext, fr: GiftFrame, config: GiftConfig, layout: GiftLayout, detail: Bool) {
        if config.fillingID == "none" { return }
        var rng = GiftRNG(77)
        let inner = fr.inner
        let total = detail ? 420 : 130
        var placed: [(CGPoint, CGFloat)] = []
        for i in 0..<min(config.jars.count, layout.slots.count) {
            let slot = layout.slots[i]
            let d = GiftCatalogue.jarDiameter(slot: slot, size: config.jars[i].sizeID)
            placed.append((fr.point(slot.x, slot.y), CGFloat(d) * fr.scale / 2 + 2))
        }
        var drawn = 0
        var tries = 0
        while drawn < total && tries < total * 6 {
            tries += 1
            let x = rng.range(inner.minX, inner.maxX)
            let y = rng.range(inner.minY, inner.maxY)
            var blocked = false
            for (c, r) in placed where hypot(c.x - x, c.y - y) < r { blocked = true; break }
            if blocked { continue }
            drawn += 1
            fillPiece(&ctx, config: config, at: CGPoint(x: x, y: y), scale: fr.scale, rng: &rng)
        }
    }

    private static func fillPiece(_ ctx: inout GraphicsContext, config: GiftConfig, at p: CGPoint, scale: CGFloat, rng: inout GiftRNG) {
        let hex = config.fillingHex
        switch config.fillingID {
        case "silk", "paper":
            var path = Path()
            let len = scale * rng.range(0.8, 1.8)
            let a = rng.range(0, 6.28)
            let dx = cos(a) * len
            let dy = sin(a) * len
            path.move(to: p)
            if config.fillingID == "silk" {
                path.addQuadCurve(to: CGPoint(x: p.x + dx, y: p.y + dy), control: CGPoint(x: p.x + dx * 0.5 - dy * 0.5, y: p.y + dy * 0.5 + dx * 0.5))
            } else {
                path.addLine(to: CGPoint(x: p.x + dx, y: p.y + dy))
            }
            let tone = rng.next() > 0.5 ? GiftColor.shade(hex, 1.12) : GiftColor.shade(hex, 0.86)
            ctx.stroke(path, with: .color(col(tone, 0.92)), lineWidth: max(1, scale * 0.07))
        case "petals":
            var c = ctx
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .radians(Double(rng.range(0, 6.28))))
            let w = scale * rng.range(0.5, 0.9)
            let petal = Path(ellipseIn: CGRect(x: -w / 2, y: -w / 3, width: w, height: w * 0.66))
            let tone = rng.next() > 0.5 ? GiftColor.shade(hex, 1.1) : GiftColor.shade(hex, 0.9)
            c.fill(petal, with: .color(col(tone, 0.95)))
        case "beads", "pearls":
            let d = scale * rng.range(0.35, 0.6)
            let rect = CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)
            let pearl = config.fillingID == "pearls"
            let a = pearl ? "#FFFFFF" : "#F6DE8D"
            let b = pearl ? "#CFC8C0" : "#B5842A"
            let g = Gradient(colors: [col(a), col(b)])
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(g, center: CGPoint(x: p.x - d * 0.15, y: p.y - d * 0.15), startRadius: 0, endRadius: d * 0.7))
        default:
            break
        }
    }

    // MARK: Jars from above

    static func jar(_ ctx: inout GraphicsContext, centre: CGPoint, diameter: CGFloat, spec: JarSpec, seed: Int, detail: Bool) {
        let style = GiftCatalogue.jarStyle(spec.styleID)
        let mat = GiftCatalogue.jarMaterial(spec.materialID)
        let r = diameter / 2
        let body = shapePath(style.shape, centre, r)
        var shadow = ctx
        shadow.addFilter(.shadow(color: Color.black.opacity(0.4), radius: max(2, r * 0.12), x: r * 0.06, y: r * 0.1))
        shadow.fill(body, with: .color(col(mat.hex)))

        let g = Gradient(colors: [col(GiftColor.shade(mat.hex, 1.25)), col(mat.hex), col(GiftColor.shade(mat.hex, 0.7))])
        ctx.fill(body, with: .linearGradient(g, startPoint: CGPoint(x: centre.x - r, y: centre.y - r), endPoint: CGPoint(x: centre.x + r, y: centre.y + r)))
        ctx.stroke(body, with: .color(col(GiftColor.shade(mat.hex, 0.55), 0.9)), lineWidth: max(1, r * 0.04))

        var rng = GiftRNG(seed)
        if style.facets > 0 {
            var cuts = Path()
            for k in 0..<style.facets {
                let a = Double(k) / Double(style.facets) * 6.2832
                cuts.move(to: CGPoint(x: centre.x + CGFloat(cos(a)) * r * 0.62, y: centre.y + CGFloat(sin(a)) * r * 0.62))
                cuts.addLine(to: CGPoint(x: centre.x + CGFloat(cos(a)) * r, y: centre.y + CGFloat(sin(a)) * r))
            }
            ctx.stroke(cuts, with: .color(Color.white.opacity(0.55)), lineWidth: max(0.8, r * 0.025))
        }
        if mat.id == "ceramic" {
            for k in 0..<10 {
                let a = Double(k) / 10.0 * 6.2832
                let pc = CGPoint(x: centre.x + CGFloat(cos(a)) * r * 0.82, y: centre.y + CGFloat(sin(a)) * r * 0.82)
                let dot = Path(ellipseIn: CGRect(x: pc.x - r * 0.07, y: pc.y - r * 0.07, width: r * 0.14, height: r * 0.14))
                ctx.fill(dot, with: .color(Color(wishHex: "#C99AA6").opacity(0.8)))
            }
        }
        if mat.id == "wood" {
            for k in 1...3 {
                let ring = shapePath(style.shape, centre, r * (1 - CGFloat(k) * 0.07))
                ctx.stroke(ring, with: .color(Color.black.opacity(0.18)), lineWidth: 0.8)
            }
        }
        let opening = shapePath(style.shape, centre, r * 0.7)
        ctx.fill(opening, with: .color(col(GiftColor.shade(mat.hex, 0.5), 0.9)))
        var inside = ctx
        inside.clip(to: opening)
        contents(&inside, centre: centre, r: r * 0.7, id: spec.contentID, rng: &rng, detail: detail)
        ctx.stroke(opening, with: .color(Color.black.opacity(0.4)), lineWidth: max(1, r * 0.035))

        let shine = Path(ellipseIn: CGRect(x: centre.x - r * 0.62, y: centre.y - r * 0.78, width: r * 0.5, height: r * 0.22))
        ctx.fill(shine, with: .color(Color.white.opacity(mat.id == "crystal" || mat.id == "frosted" ? 0.4 : 0.22)))
    }

    private static func shapePath(_ shape: JarShape, _ c: CGPoint, _ r: CGFloat) -> Path {
        switch shape {
        case .round:
            return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        case .octagon:
            var p = Path()
            for k in 0..<8 {
                let a = (Double(k) + 0.5) / 8.0 * 6.2832
                let pt = CGPoint(x: c.x + CGFloat(cos(a)) * r * 1.04, y: c.y + CGFloat(sin(a)) * r * 1.04)
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            return p
        case .square:
            return Path(roundedRect: CGRect(x: c.x - r * 0.92, y: c.y - r * 0.92, width: r * 1.84, height: r * 1.84), cornerRadius: r * 0.22)
        }
    }

    private static func contents(_ ctx: inout GraphicsContext, centre c: CGPoint, r: CGFloat, id: String, rng: inout GiftRNG, detail: Bool) {
        let content = GiftCatalogue.content(id)
        switch id {
        case "candle":
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(col(content.hex)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.6, y: c.y - r * 0.7, width: r * 0.7, height: r * 0.4)), with: .color(Color.white.opacity(0.35)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.07, y: c.y - r * 0.07, width: r * 0.14, height: r * 0.14)), with: .color(Color(wishHex: "#2A2118")))
        case "perfume":
            let g = Gradient(colors: [col("#F3C77A"), col("#B8741F")])
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .radialGradient(g, center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.2))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.25, y: c.y - r * 0.25, width: r * 0.5, height: r * 0.5)), with: .color(Color(wishHex: "#D4A84A")))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.25, y: c.y - r * 0.25, width: r * 0.5, height: r * 0.5)), with: .color(Color.black.opacity(0.35)), lineWidth: 1)
        case "diffuser":
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(col("#8A6B2E")))
            for k in 0..<7 {
                let a = Double(k) / 7.0 * 6.2832 + 0.3
                var s = Path()
                s.move(to: c)
                s.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * r * 1.3, y: c.y + CGFloat(sin(a)) * r * 1.3))
                ctx.stroke(s, with: .color(col("#C99B5A")), lineWidth: max(1.2, r * 0.07))
            }
        case "none":
            break
        default:
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Color.black.opacity(0.35)))
            let n = detail ? 26 : 12
            for _ in 0..<n {
                let a = rng.range(0, 6.28)
                let d = sqrt(rng.next()) * r * 0.82
                let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
                piece(&ctx, id: id, at: p, size: r * 0.3, rng: &rng)
            }
        }
    }

    private static func piece(_ ctx: inout GraphicsContext, id: String, at p: CGPoint, size s: CGFloat, rng: inout GiftRNG) {
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(Double(rng.range(0, 6.28))))
        switch id {
        case "cookies":
            c.fill(Path(ellipseIn: CGRect(x: -s * 0.6, y: -s * 0.6, width: s * 1.2, height: s * 1.2)), with: .color(col(rng.next() > 0.5 ? "#C48A4A" : "#A8692F")))
            c.fill(Path(ellipseIn: CGRect(x: -s * 0.1, y: -s * 0.2, width: s * 0.25, height: s * 0.25)), with: .color(col("#4B2A14")))
        case "dryfruits":
            let hexes = ["#C9A25C", "#8B3A2E", "#6B7B3A", "#D9B77A", "#7A4B2A"]
            let hex = hexes[Int(rng.range(0, 4.99))]
            c.fill(Path(ellipseIn: CGRect(x: -s * 0.7, y: -s * 0.4, width: s * 1.4, height: s * 0.8)), with: .color(col(hex)))
        case "chocolates":
            c.fill(Path(roundedRect: CGRect(x: -s * 0.6, y: -s * 0.6, width: s * 1.2, height: s * 1.2), cornerRadius: s * 0.2), with: .color(col(rng.next() > 0.5 ? "#4A2A1C" : "#6B3F26")))
            c.fill(Path(roundedRect: CGRect(x: -s * 0.3, y: -s * 0.3, width: s * 0.6, height: s * 0.6), cornerRadius: s * 0.1), with: .color(Color.white.opacity(0.12)))
        case "tea":
            var p = Path()
            p.move(to: CGPoint(x: -s * 0.7, y: 0))
            p.addQuadCurve(to: CGPoint(x: s * 0.7, y: 0), control: CGPoint(x: 0, y: -s * 0.6))
            c.stroke(p, with: .color(col(rng.next() > 0.5 ? "#6E8B3D" : "#4F6B2A")), lineWidth: max(1, s * 0.25))
        default:
            let hexes = ["#E8789C", "#F2C230", "#C62828", "#EE8A2E", "#F3EBDD"]
            let hex = hexes[Int(rng.range(0, 4.99))]
            c.fill(Path(ellipseIn: CGRect(x: -s * 0.55, y: -s * 0.3, width: s * 1.1, height: s * 0.6)), with: .color(col(hex)))
        }
    }

    // MARK: Lid (closed box)

    static func lid(_ ctx: inout GraphicsContext, size: CGSize, config: GiftConfig, dims: Bool, detail: Bool) {
        let fr = GiftFrame(size: size, dims: dims)
        let finish = config.finish
        let outer = fr.outer
        let radius = fr.scale * 1.0
        var sc = ctx
        sc.addFilter(.shadow(color: Color.black.opacity(0.3), radius: 9, x: 3, y: 6))
        sc.fill(Path(roundedRect: outer, cornerRadius: radius), with: .color(col(finish.hex)))
        material(&ctx, rect: outer, radius: radius, finish: finish, seed: 21, detail: detail)

        let groove = Path(roundedRect: outer.insetBy(dx: fr.scale * 0.9, dy: fr.scale * 0.9), cornerRadius: fr.scale * 0.5)
        ctx.stroke(groove, with: .color(Color.black.opacity(0.28)), lineWidth: 1.6)
        ctx.stroke(groove, with: .color(Color.white.opacity(0.14)), lineWidth: 0.8)

        let hw = finish.hardwareHex
        let clasp = CGRect(x: outer.midX - fr.scale * 1.4, y: outer.maxY - fr.scale * 1.55, width: fr.scale * 2.8, height: fr.scale * 1.7)
        let cg = Gradient(colors: [col(GiftColor.shade(hw, 1.3)), col(hw), col(GiftColor.shade(hw, 0.7))])
        ctx.fill(Path(roundedRect: clasp, cornerRadius: fr.scale * 0.3), with: .linearGradient(cg, startPoint: CGPoint(x: clasp.minX, y: clasp.minY), endPoint: CGPoint(x: clasp.maxX, y: clasp.maxY)))
        ctx.stroke(Path(roundedRect: clasp, cornerRadius: fr.scale * 0.3), with: .color(Color.black.opacity(0.4)), lineWidth: 1)
        let keyhole = Path(ellipseIn: CGRect(x: clasp.midX - fr.scale * 0.22, y: clasp.midY - fr.scale * 0.22, width: fr.scale * 0.44, height: fr.scale * 0.44))
        ctx.fill(keyhole, with: .color(Color.black.opacity(0.6)))
        for i in 0..<2 {
            let hx = outer.minX + fr.scale * (i == 0 ? 6.0 : 28.0)
            let hinge = CGRect(x: hx - fr.scale * 1.2, y: outer.minY - fr.scale * 0.02, width: fr.scale * 2.4, height: fr.scale * 0.8)
            ctx.fill(Path(roundedRect: hinge, cornerRadius: fr.scale * 0.15), with: .linearGradient(cg, startPoint: CGPoint(x: hinge.minX, y: hinge.minY), endPoint: CGPoint(x: hinge.maxX, y: hinge.maxY)))
        }

        let label = CGRect(x: outer.midX - fr.scale * 5.2, y: outer.midY - fr.scale * 3.0, width: fr.scale * 10.4, height: fr.scale * 6.0)
        ctx.fill(Path(roundedRect: label, cornerRadius: fr.scale * 0.4), with: .color(Color(wishHex: "#FBF6EA")))
        ctx.stroke(Path(roundedRect: label.insetBy(dx: 3, dy: 3), cornerRadius: fr.scale * 0.3), with: .color(col(hw)), lineWidth: 1.2)

        flowers(&ctx, fr: fr, id: config.flowerID, finish: finish)
        if dims { dimensions(&ctx, fr: fr) }
    }

    // MARK: Flowers on the lid

    private static func flowers(_ ctx: inout GraphicsContext, fr: GiftFrame, id: String, finish: BoxFinish) {
        let s = fr.scale
        switch id {
        case "roses":
            leaves(&ctx, fr: fr)
            rose(&ctx, c: fr.lidPoint(5.4, 5.2), r: s * 2.0, hex: "#F4EBDD")
            rose(&ctx, c: fr.lidPoint(8.6, 4.2), r: s * 1.5, hex: "#F7E4E4")
            rose(&ctx, c: fr.lidPoint(4.6, 8.8), r: s * 1.5, hex: "#EFE2CB")
            rose(&ctx, c: fr.lidPoint(29.2, 19.4), r: s * 1.3, hex: "#F4EBDD")
        case "blush":
            leaves(&ctx, fr: fr)
            for (i, p) in [(5.0, 5.0), (8.4, 3.8), (4.4, 8.6), (7.6, 7.6), (29.4, 19.2), (26.8, 20.2)].enumerated() {
                blossom(&ctx, c: fr.lidPoint(p.0, p.1), r: s * (i < 4 ? 1.5 : 1.1), petal: i % 2 == 0 ? "#F2B8C6" : "#F8D7DE", gold: false)
            }
        case "gold":
            leaves(&ctx, fr: fr)
            for (i, p) in [(5.2, 5.2), (8.6, 4.0), (4.6, 8.8), (7.8, 7.8), (29.2, 19.4)].enumerated() {
                blossom(&ctx, c: fr.lidPoint(p.0, p.1), r: s * (i < 3 ? 1.6 : 1.2), petal: "#D9B24A", gold: true)
            }
        case "monogram":
            let plate = CGRect(x: fr.outer.midX - s * 2.2, y: fr.outer.minY + s * 3.0, width: s * 4.4, height: s * 2.2)
            let g = Gradient(colors: [col(GiftColor.shade(finish.hardwareHex, 1.3)), col(finish.hardwareHex), col(GiftColor.shade(finish.hardwareHex, 0.7))])
            ctx.fill(Path(roundedRect: plate, cornerRadius: s * 0.3), with: .linearGradient(g, startPoint: CGPoint(x: plate.minX, y: plate.minY), endPoint: CGPoint(x: plate.maxX, y: plate.maxY)))
            ctx.stroke(Path(roundedRect: plate, cornerRadius: s * 0.3), with: .color(Color.black.opacity(0.4)), lineWidth: 1)
            let t = ctx.resolve(Text("V").font(.system(size: max(10, s * 1.3), weight: .bold, design: .serif)).foregroundColor(Color.black.opacity(0.65)))
            ctx.draw(t, at: CGPoint(x: plate.midX, y: plate.midY), anchor: .center)
        default:
            break
        }
    }

    private static func leaves(_ ctx: inout GraphicsContext, fr: GiftFrame) {
        let s = fr.scale
        let spots: [(Double, Double, Double)] = [(3.2, 5.8, 20), (6.0, 2.4, 80), (9.8, 5.6, 140), (6.8, 10.2, 200), (3.0, 10.4, 250), (28.0, 18.0, 30), (30.6, 20.6, 100)]
        for sp in spots {
            var c = ctx
            let p = fr.lidPoint(sp.0, sp.1)
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .degrees(sp.2))
            let leaf = Path(ellipseIn: CGRect(x: 0, y: -s * 0.45, width: s * 2.6, height: s * 0.9))
            c.fill(leaf, with: .color(Color(wishHex: "#4C7A4B")))
            var vein = Path()
            vein.move(to: CGPoint(x: 0, y: 0)); vein.addLine(to: CGPoint(x: s * 2.4, y: 0))
            c.stroke(vein, with: .color(Color(wishHex: "#2F5530")), lineWidth: 1)
        }
    }

    private static func rose(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat, hex: String) {
        for i in 0..<6 {
            let a = Double(i) / 6.0 * 6.2832
            let pc = CGPoint(x: c.x + CGFloat(cos(a)) * r * 0.5, y: c.y + CGFloat(sin(a)) * r * 0.5)
            let tone = i % 2 == 0 ? GiftColor.shade(hex, 0.95) : GiftColor.shade(hex, 0.86)
            let petal = Path(ellipseIn: CGRect(x: pc.x - r * 0.5, y: pc.y - r * 0.5, width: r, height: r))
            ctx.fill(petal, with: .color(col(tone)))
            ctx.stroke(petal, with: .color(Color.black.opacity(0.15)), lineWidth: 0.8)
        }
        let rings: [(CGFloat, Double)] = [(0.62, 0.94), (0.44, 0.84), (0.27, 0.74), (0.12, 0.64)]
        for ring in rings {
            let circle = Path(ellipseIn: CGRect(x: c.x - r * ring.0, y: c.y - r * ring.0, width: r * ring.0 * 2, height: r * ring.0 * 2))
            ctx.fill(circle, with: .color(col(GiftColor.shade(hex, ring.1))))
            ctx.stroke(circle, with: .color(Color.black.opacity(0.18)), lineWidth: 0.8)
        }
    }

    private static func blossom(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat, petal: String, gold: Bool) {
        for i in 0..<5 {
            var q = ctx
            q.translateBy(x: c.x, y: c.y)
            q.rotate(by: .radians(Double(i) / 5.0 * 6.2832))
            let shape = Path(ellipseIn: CGRect(x: 0, y: -r * 0.42, width: r * 1.1, height: r * 0.84))
            if gold {
                let g = Gradient(colors: [col("#F6DE8D"), col("#B5842A")])
                q.fill(shape, with: .linearGradient(g, startPoint: .zero, endPoint: CGPoint(x: r, y: 0)))
            } else {
                q.fill(shape, with: .color(col(petal)))
            }
            q.stroke(shape, with: .color(Color.black.opacity(0.2)), lineWidth: 0.7)
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.2, y: c.y - r * 0.2, width: r * 0.4, height: r * 0.4)), with: .color(col(gold ? "#7A5A1A" : "#D9A441")))
    }
}

// MARK: - Views

struct GiftBoxTop: View {
    let config: GiftConfig
    var jarsShown: Int = 99
    var dims: Bool = true
    var detail: Bool = true

    var body: some View {
        Canvas { ctx, size in
            GiftArt.openBox(&ctx, size: size, config: config, jarsShown: jarsShown, dims: dims, detail: detail)
        }
    }
}

struct GiftLidView: View {
    let config: GiftConfig
    var dims: Bool = true
    var detail: Bool = true

    var body: some View {
        GeometryReader { geo in
            let fr = GiftFrame(size: geo.size, dims: dims)
            ZStack {
                Canvas { ctx, size in
                    GiftArt.lid(&ctx, size: size, config: config, dims: dims, detail: detail)
                }
                VybesLogoView()
                    .frame(width: fr.scale * 8.6, height: fr.scale * 4.6)
                    .position(x: fr.outer.midX, y: fr.outer.midY)
            }
        }
    }
}

/// A small swatch of the real texture, used when choosing a finish.
struct GiftMaterialChip: View {
    let finish: BoxFinish

    var body: some View {
        Canvas { ctx, size in
            GiftArt.material(&ctx, rect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), radius: 6, finish: finish, seed: 5, detail: false)
        }
    }
}

/// Slot diagram for a layout.
struct GiftLayoutChip: View {
    let layout: GiftLayout

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / CGFloat(GiftBoxSpec.innerW), size.height / CGFloat(GiftBoxSpec.innerD))
            let w = s * CGFloat(GiftBoxSpec.innerW)
            let h = s * CGFloat(GiftBoxSpec.innerD)
            let ox = (size.width - w) / 2
            let oy = (size.height - h) / 2
            ctx.stroke(Path(roundedRect: CGRect(x: ox, y: oy, width: w, height: h), cornerRadius: 3), with: .color(Color.gray), lineWidth: 1)
            for slot in layout.slots {
                let d = CGFloat(slot.maxD) * s
                let rect = CGRect(x: ox + CGFloat(slot.x) * s - d / 2, y: oy + CGFloat(slot.y) * s - d / 2, width: d, height: d)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color(wishHex: "#6D4AB0").opacity(0.35)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(Color(wishHex: "#6D4AB0")), lineWidth: 1)
            }
        }
    }
}
