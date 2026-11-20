// Gifting in 3D (SceneKit): a real box with a hinged lid and a tray, real jars set into the tray, filling, lid flowers and leaves,
// and the sender's card under the lid. Everything is in centimetres, so what fits in the picture fits in the box.
import Foundation
import SwiftUI
import SceneKit
import AppKit

private func v3(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNVector3 { return SCNVector3(x: x, y: y, z: z) }

private func ns(_ hex: String, _ a: CGFloat = 1) -> NSColor {
    let c = GiftColor.rgb(hex)
    return NSColor(red: CGFloat(c.0), green: CGFloat(c.1), blue: CGFloat(c.2), alpha: a)
}

private func plain(_ hex: String, spec: CGFloat = 0.15, shine: CGFloat = 0.3) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .blinn
    m.diffuse.contents = ns(hex)
    m.specular.contents = NSColor(white: spec, alpha: 1)
    m.shininess = shine
    return m
}

private func metalMat(_ hex: String) -> SCNMaterial {
    let m = plain(hex, spec: 0.95, shine: 0.9)
    m.isDoubleSided = true
    return m
}

private func part(_ g: SCNGeometry, _ m: SCNMaterial, _ x: CGFloat = 0, _ y: CGFloat = 0, _ z: CGFloat = 0) -> SCNNode {
    g.materials = [m]
    let n = SCNNode(geometry: g)
    n.position = v3(x, y, z)
    return n
}

// MARK: - Textures (rendered with the same code as the 2D swatches)

struct GiftMaterialSwatch: View {
    let finish: BoxFinish
    var body: some View {
        Canvas { ctx, size in
            GiftArt.material(&ctx, rect: CGRect(origin: .zero, size: size), radius: 0, finish: finish, seed: 3, detail: true)
        }
    }
}

struct GiftPlaqueArt: View {
    let hardware: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26).fill(Color(wishHex: "#FBF6EA"))
            RoundedRectangle(cornerRadius: 20).stroke(Color(wishHex: hardware), lineWidth: 5).padding(14)
            VybesLogoView().padding(46)
        }
    }
}

struct GiftMonogramArt: View {
    let hardware: String
    var body: some View {
        ZStack {
            Color(wishHex: hardware)
            Text("V").font(.system(size: 150, weight: .bold, design: .serif)).foregroundStyle(Color.black.opacity(0.65))
        }
    }
}

@MainActor
enum GiftTex {
    private static var cache: [String: NSImage] = [:]

    static func finish(_ f: BoxFinish) -> NSImage? {
        if let c = cache["f" + f.id] { return c }
        guard let img = WishExport.image(of: GiftMaterialSwatch(finish: f).frame(width: 1024, height: 512), scale: 1) else { return nil }
        cache["f" + f.id] = img
        return img
    }

    static func plaque(_ hardware: String) -> NSImage? {
        if let c = cache["p" + hardware] { return c }
        guard let img = WishExport.image(of: GiftPlaqueArt(hardware: hardware).frame(width: 520, height: 280), scale: 1) else { return nil }
        cache["p" + hardware] = img
        return img
    }

    static func monogram(_ hardware: String) -> NSImage? {
        if let c = cache["m" + hardware] { return c }
        guard let img = WishExport.image(of: GiftMonogramArt(hardware: hardware).frame(width: 300, height: 300), scale: 1) else { return nil }
        cache["m" + hardware] = img
        return img
    }

    static func card(_ config: GiftConfig) -> NSImage? {
        return WishExport.image(of: GiftCardArt(config: config).frame(width: 780, height: 538), scale: 1)
    }
}

// MARK: - Lathe: a jar is a profile turned around its axis

struct JarProfile {
    var body: [(CGFloat, CGFloat)]
    var lid: [(CGFloat, CGFloat)]
    var segments: Int
    var flat: Bool
    var twist: CGFloat
}

enum GiftLathe {
    static func geometry(_ pts: [CGPoint], segments n: Int, flat: Bool, twist: CGFloat) -> SCNGeometry {
        var verts: [SCNVector3] = []
        var norms: [SCNVector3] = []
        var idx: [Int32] = []
        func ring(_ r: CGFloat, _ y: CGFloat, _ k: Int) -> SCNVector3 {
            let a = twist + 2 * CGFloat.pi * CGFloat(k) / CGFloat(n)
            return v3(r * cos(a), y, r * sin(a))
        }
        func dir(_ nr: CGFloat, _ ny: CGFloat, _ angle: CGFloat) -> SCNVector3 {
            return v3(nr * cos(angle), ny, nr * sin(angle))
        }
        if pts.count < 2 { return SCNGeometry() }
        for i in 0..<(pts.count - 1) {
            let p0 = pts[i]
            let p1 = pts[i + 1]
            let dr = p1.x - p0.x
            let dy = p1.y - p0.y
            let len = max(0.0001, hypot(dr, dy))
            let nr = dy / len
            let ny = -dr / len
            for k in 0..<n {
                let k2 = k + 1
                let base = Int32(verts.count)
                verts.append(ring(p0.x, p0.y, k))
                verts.append(ring(p0.x, p0.y, k2))
                verts.append(ring(p1.x, p1.y, k2))
                verts.append(ring(p1.x, p1.y, k))
                if flat {
                    let am = twist + 2 * CGFloat.pi * (CGFloat(k) + 0.5) / CGFloat(n)
                    let nn = dir(nr, ny, am)
                    norms.append(contentsOf: [nn, nn, nn, nn])
                } else {
                    let a0 = twist + 2 * CGFloat.pi * CGFloat(k) / CGFloat(n)
                    let a1 = twist + 2 * CGFloat.pi * CGFloat(k2) / CGFloat(n)
                    norms.append(contentsOf: [dir(nr, ny, a0), dir(nr, ny, a1), dir(nr, ny, a1), dir(nr, ny, a0)])
                }
                idx.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            }
        }
        let src = SCNGeometrySource(vertices: verts)
        let nsrc = SCNGeometrySource(normals: norms)
        let el = SCNGeometryElement(indices: idx, primitiveType: .triangles)
        return SCNGeometry(sources: [src, nsrc], elements: [el])
    }
}

// MARK: - Jars

@MainActor
enum GiftJar3D {
    static func profile(_ id: String) -> JarProfile {
        let pi = CGFloat.pi
        switch id {
        case "octagon":
            return JarProfile(body: [(0, 0), (1, 0), (1, 0.78), (0.84, 0.84)], lid: [(0.86, 0.82), (0.86, 0.9), (0.3, 0.97), (0, 1.0)], segments: 8, flat: true, twist: pi / 8)
        case "relief":
            return JarProfile(body: [(0, 0), (0.72, 0), (0.95, 0.15), (1, 0.45), (0.92, 0.72), (0.64, 0.84)], lid: [(0.68, 0.82), (0.68, 0.88), (0.4, 0.96), (0.14, 0.99), (0, 1.0)], segments: 36, flat: false, twist: 0)
        case "perfume":
            return JarProfile(body: [(0, 0), (1, 0), (1, 0.6), (0.5, 0.68), (0.26, 0.72), (0.26, 0.8)], lid: [(0.3, 0.78), (0.32, 0.86), (0.28, 0.96), (0, 1.0)], segments: 4, flat: true, twist: pi / 4)
        case "candlebowl":
            return JarProfile(body: [(0, 0), (0.78, 0), (0.98, 0.1), (1, 0.7), (0.95, 0.76)], lid: [], segments: 40, flat: false, twist: 0)
        case "woodlid":
            return JarProfile(body: [(0, 0), (1, 0), (1, 0.8), (0.92, 0.84)], lid: [(0.96, 0.8), (0.96, 0.94), (0.9, 1.0), (0, 1.0)], segments: 32, flat: false, twist: 0)
        case "diffuser":
            return JarProfile(body: [(0, 0), (0.98, 0), (1, 0.08), (1, 0.62), (0.42, 0.74), (0.2, 0.82), (0.2, 0.86)], lid: [(0.24, 0.84), (0.24, 0.95), (0, 1.0)], segments: 28, flat: false, twist: 0)
        case "tin":
            return JarProfile(body: [(0, 0), (1, 0), (1, 0.66), (0.96, 0.7)], lid: [(1.02, 0.66), (1.02, 0.86), (0.9, 0.92), (0, 0.94)], segments: 8, flat: true, twist: pi / 8)
        default:
            return JarProfile(body: [(0, 0), (0.84, 0), (1, 0.05), (1, 0.72), (0.9, 0.8), (0.72, 0.86)], lid: [(0.76, 0.84), (0.76, 0.95), (0.55, 1.0), (0, 1.0)], segments: 12, flat: true, twist: 0)
        }
    }

    static func bodyMaterial(_ id: String) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.isDoubleSided = true
        switch id {
        case "crystal":
            m.diffuse.contents = ns("#CFE4EA")
            m.specular.contents = NSColor.white
            m.shininess = 1.0
            m.transparency = 0.34
            m.transparencyMode = .dualLayer
        case "frosted":
            m.diffuse.contents = ns("#F2F5F6")
            m.specular.contents = NSColor(white: 0.5, alpha: 1)
            m.shininess = 0.3
            m.transparency = 0.8
            m.transparencyMode = .dualLayer
        case "ceramic":
            m.diffuse.contents = ns("#F3ECDF")
            m.specular.contents = NSColor(white: 0.8, alpha: 1)
            m.shininess = 0.7
        case "metal":
            m.diffuse.contents = ns("#C9A24A")
            m.specular.contents = NSColor.white
            m.shininess = 0.9
        default:
            m.diffuse.contents = ns("#8A5A32")
            m.specular.contents = NSColor(white: 0.25, alpha: 1)
            m.shininess = 0.3
        }
        return m
    }

    static func lidMaterial(style: String, material: String, hardware: String) -> SCNMaterial {
        if style == "woodlid" || material == "wood" { return plain("#8A5A32", spec: 0.25, shine: 0.3) }
        if material == "ceramic" { return bodyMaterial("ceramic") }
        return metalMat(hardware)
    }

    static func node(_ spec: JarSpec, diameter d: CGFloat, height h: CGFloat, seed: Int, hardware: String) -> SCNNode {
        let style = GiftCatalogue.jarStyle(spec.styleID)
        let prof = profile(style.id)
        let r = d / 2
        let root = SCNNode()
        let bodyPts = prof.body.map { CGPoint(x: $0.0 * r, y: $0.1 * h) }
        let body = GiftLathe.geometry(bodyPts, segments: prof.segments, flat: prof.flat, twist: prof.twist)
        body.materials = [bodyMaterial(spec.materialID)]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.renderingOrder = 10
        root.addChildNode(bodyNode)
        let glass = spec.materialID == "crystal" || spec.materialID == "frosted"
        let lidOn = spec.lid && !prof.lid.isEmpty
        if lidOn {
            let lidPts = prof.lid.map { CGPoint(x: $0.0 * r, y: $0.1 * h) }
            let lid = GiftLathe.geometry(lidPts, segments: prof.segments, flat: prof.flat, twist: prof.twist)
            lid.materials = [lidMaterial(style: style.id, material: spec.materialID, hardware: hardware)]
            root.addChildNode(SCNNode(geometry: lid))
        }
        if (glass || !lidOn) && spec.contentID != "none" {
            let inner = prof.flat ? r * 0.78 : r * 0.9
            let c = contents(spec.contentID, r: inner, h: h * 0.8, seed: seed)
            c.renderingOrder = 1
            root.addChildNode(c)
        }
        return root
    }

    static func contents(_ id: String, r: CGFloat, h: CGFloat, seed: Int) -> SCNNode {
        let root = SCNNode()
        var rng = GiftRNG(seed)
        let y0: CGFloat = 0.25
        func spot(_ rad: CGFloat) -> (CGFloat, CGFloat) {
            let a = rng.range(0, 6.2832)
            let d = sqrt(rng.next()) * rad
            return (d * cos(a), d * sin(a))
        }
        switch id {
        case "candle":
            let hc = h * 0.78
            root.addChildNode(part(SCNCylinder(radius: r * 0.96, height: hc), plain("#F3E6C8", spec: 0.3, shine: 0.4), 0, y0 + hc / 2, 0))
            root.addChildNode(part(SCNCylinder(radius: 0.06, height: 0.7), plain("#2A2118"), 0, y0 + hc + 0.3, 0))
        case "perfume", "diffuser":
            let hc = h * 0.62
            let m = plain(id == "perfume" ? "#D9A441" : "#8A6B2E", spec: 0.9, shine: 0.9)
            m.transparency = 0.82
            root.addChildNode(part(SCNCylinder(radius: r * 0.96, height: hc), m, 0, y0 + hc / 2, 0))
        case "cookies":
            for k in 0..<9 {
                let p = spot(r * 0.55)
                let layer = CGFloat(k / 3)
                let hex = k % 2 == 0 ? "#C48A4A" : "#A8692F"
                root.addChildNode(part(SCNCylinder(radius: r * 0.42, height: 0.4), plain(hex), p.0, y0 + 0.2 + layer * 0.42, p.1))
            }
        case "dryfruits", "potpourri":
            let hexes = id == "dryfruits" ? ["#C9A25C", "#8B3A2E", "#6B7B3A", "#D9B77A", "#7A4B2A"] : ["#E8789C", "#F2C230", "#C62828", "#EE8A2E", "#F3EBDD"]
            let size: CGFloat = id == "dryfruits" ? 0.5 : 0.3
            for _ in 0..<(id == "dryfruits" ? 26 : 40) {
                let p = spot(r * 0.88)
                let y = y0 + size + rng.range(0, h * 0.55)
                let n = part(SCNSphere(radius: size), plain(hexes[Int(rng.range(0, 4.99))], spec: 0.3, shine: 0.4), p.0, y, p.1)
                n.scale = v3(1.2, id == "dryfruits" ? 0.8 : 0.45, 0.9)
                n.eulerAngles = v3(0, rng.range(0, 6.28), 0)
                root.addChildNode(n)
            }
        case "chocolates":
            for _ in 0..<16 {
                let p = spot(r * 0.8)
                let y = y0 + 0.3 + rng.range(0, h * 0.5)
                let n = part(SCNBox(width: 1.1, height: 0.6, length: 1.1, chamferRadius: 0.1), plain(rng.next() > 0.5 ? "#4A2A1C" : "#6B3F26", spec: 0.5, shine: 0.6), p.0, y, p.1)
                n.eulerAngles = v3(0, rng.range(0, 6.28), 0)
                root.addChildNode(n)
            }
        case "tea":
            let hc = h * 0.6
            root.addChildNode(part(SCNCone(topRadius: r * 0.3, bottomRadius: r * 0.95, height: hc), plain("#5C7A33"), 0, y0 + hc / 2, 0))
            for _ in 0..<14 {
                let p = spot(r * 0.3)
                let n = part(SCNBox(width: 0.5, height: 0.05, length: 0.18, chamferRadius: 0), plain("#7E9B3F"), p.0, y0 + hc * 0.9, p.1)
                n.eulerAngles = v3(0, rng.range(0, 6.28), rng.range(-0.4, 0.4))
                root.addChildNode(n)
            }
        default:
            break
        }
        return root
    }
}

// MARK: - Flowers and leaves

@MainActor
enum GiftFlora {
    static func leaf(_ len: CGFloat, _ hex: String) -> SCNNode {
        let n = SCNNode()
        let g = SCNSphere(radius: len / 2)
        let leafNode = part(g, plain(hex, spec: 0.3, shine: 0.4), len / 2, 0, 0)
        leafNode.scale = v3(1, 0.07, 0.42)
        n.addChildNode(leafNode)
        n.addChildNode(part(SCNCylinder(radius: 0.03, height: len * 0.9), plain(GiftColor.shade(hex, 0.7)), len * 0.47, 0.02, 0))
        n.childNodes[1].eulerAngles = v3(0, 0, CGFloat.pi / 2)
        return n
    }

    static func stem(_ len: CGFloat, _ hex: String) -> SCNNode {
        let n = part(SCNCylinder(radius: 0.05, height: len), plain(hex), len / 2, 0, 0)
        n.eulerAngles = v3(0, 0, CGFloat.pi / 2)
        return n
    }

    static func rose(_ r: CGFloat, _ hex: String) -> SCNNode {
        let n = SCNNode()
        n.addChildNode(part(SCNSphere(radius: r * 0.3), plain(GiftColor.shade(hex, 0.82), spec: 0.3, shine: 0.4), 0, r * 0.4, 0))
        for ring in 0..<3 {
            let count = 4 + ring * 2
            let rad = r * (0.26 + CGFloat(ring) * 0.2)
            for k in 0..<count {
                let a = 2 * CGFloat.pi * (CGFloat(k) + 0.5 * CGFloat(ring)) / CGFloat(count)
                let tone = GiftColor.shade(hex, 0.96 - Double(ring) * 0.05)
                let p = part(SCNSphere(radius: r * 0.55), plain(tone, spec: 0.35, shine: 0.45), rad * cos(a), r * (0.5 - CGFloat(ring) * 0.1), rad * sin(a))
                p.scale = v3(1, 0.4, 0.8)
                p.eulerAngles = v3(0, -a, 0.55 - CGFloat(ring) * 0.2)
                n.addChildNode(p)
            }
        }
        return n
    }

    static func daisy(_ r: CGFloat, petal: String, centre: String, layers: Int, petals: Int) -> SCNNode {
        let n = SCNNode()
        for layer in 0..<layers {
            let rad = r * (0.62 - CGFloat(layer) * 0.14)
            for k in 0..<petals {
                let a = 2 * CGFloat.pi * (CGFloat(k) + 0.5 * CGFloat(layer)) / CGFloat(petals)
                let tone = GiftColor.shade(petal, 1.0 - Double(layer) * 0.07)
                let p = part(SCNSphere(radius: r * 0.3), plain(tone, spec: 0.2, shine: 0.3), rad * cos(a), r * 0.15 + CGFloat(layer) * r * 0.08, rad * sin(a))
                p.scale = v3(1.7, 0.28, 0.6)
                p.eulerAngles = v3(0, -a, 0.2 + CGFloat(layer) * 0.1)
                n.addChildNode(p)
            }
        }
        n.addChildNode(part(SCNSphere(radius: r * 0.2), plain(centre, spec: 0.2, shine: 0.3), 0, r * 0.28 + CGFloat(layers) * r * 0.05, 0))
        return n
    }

    static func lotus(_ r: CGFloat, _ hex: String) -> SCNNode {
        let n = SCNNode()
        for layer in 0..<2 {
            let count = 7 + layer * 2
            for k in 0..<count {
                let a = 2 * CGFloat.pi * (CGFloat(k) + 0.5 * CGFloat(layer)) / CGFloat(count)
                let rad = r * (0.5 - CGFloat(layer) * 0.2)
                let tone = layer == 0 ? GiftColor.shade(hex, 1.0) : GiftColor.shade(hex, 1.12)
                let p = part(SCNSphere(radius: r * 0.5), plain(tone, spec: 0.35, shine: 0.45), rad * cos(a), r * (0.35 + CGFloat(layer) * 0.2), rad * sin(a))
                p.scale = v3(1, 0.32, 0.5)
                p.eulerAngles = v3(0, -a, 0.9 - CGFloat(layer) * 0.3)
                n.addChildNode(p)
            }
        }
        n.addChildNode(part(SCNSphere(radius: r * 0.16), plain("#E8B93C"), 0, r * 0.3, 0))
        return n
    }

    static func eucalyptus(_ len: CGFloat) -> SCNNode {
        let n = SCNNode()
        n.addChildNode(stem(len, "#6C7F68"))
        let pairs = 7
        for k in 1...pairs {
            let x = len * CGFloat(k) / CGFloat(pairs + 1)
            let size = 0.5 + (1 - CGFloat(k) / CGFloat(pairs)) * 0.3
            for side in [-1.0, 1.0] {
                let leaf = part(SCNSphere(radius: size), plain("#8FA58C", spec: 0.2, shine: 0.3), x, 0, CGFloat(side) * 0.55)
                leaf.scale = v3(1, 0.1, 1)
                n.addChildNode(leaf)
            }
        }
        return n
    }

    static func fern(_ len: CGFloat) -> SCNNode {
        let n = SCNNode()
        n.addChildNode(stem(len, "#3F6B3F"))
        for k in 1...9 {
            let x = len * CGFloat(k) / 10
            let size = len * 0.1 * (1.2 - CGFloat(k) / 10)
            for side in [-1.0, 1.0] {
                let l = part(SCNSphere(radius: size), plain("#4C7A4B", spec: 0.2, shine: 0.3), x, 0, CGFloat(side) * size * 1.1)
                l.scale = v3(0.9, 0.08, 1.9)
                n.addChildNode(l)
            }
        }
        return n
    }

    static func pampas(_ len: CGFloat) -> SCNNode {
        let n = SCNNode()
        n.addChildNode(stem(len, "#B79B6A"))
        for k in 0..<5 {
            let a = (CGFloat(k) - 2) * 0.25
            let plume = part(SCNCapsule(capRadius: 0.3, height: len * 0.55), plain("#E8DAC0", spec: 0.05, shine: 0.1), len * 0.8, 0, 0)
            plume.eulerAngles = v3(0, a, CGFloat.pi / 2 + a * 0.5)
            n.addChildNode(plume)
        }
        return n
    }

    static func goldSprig(_ len: CGFloat) -> SCNNode {
        let n = SCNNode()
        n.addChildNode(stem(len, "#B5842A"))
        for k in 1...6 {
            let x = len * CGFloat(k) / 7
            for side in [-1.0, 1.0] {
                let l = part(SCNSphere(radius: 0.55), metalMat("#E1BF5F"), x, 0, CGFloat(side) * 0.5)
                l.scale = v3(1.2, 0.08, 0.6)
                l.eulerAngles = v3(0, CGFloat(side) * 0.6, 0)
                n.addChildNode(l)
            }
        }
        return n
    }

    static func bow(_ size: CGFloat, _ hex: String) -> SCNNode {
        let n = SCNNode()
        let m = plain(hex, spec: 0.7, shine: 0.7)
        m.isDoubleSided = true
        for side in [-1.0, 1.0] {
            let loop = part(SCNTorus(ringRadius: size * 0.5, pipeRadius: size * 0.13), m, CGFloat(side) * size * 0.55, size * 0.3, 0)
            loop.scale = v3(1.1, 1, 0.5)
            loop.eulerAngles = v3(CGFloat.pi / 2, 0, 0)
            n.addChildNode(loop)
            let tail = part(SCNBox(width: size * 0.22, height: 0.05, length: size * 1.6, chamferRadius: 0), m, CGFloat(side) * size * 0.25, 0.1, size * 0.9)
            tail.eulerAngles = v3(0, CGFloat(side) * 0.35, 0)
            n.addChildNode(tail)
        }
        n.addChildNode(part(SCNSphere(radius: size * 0.2), m, 0, size * 0.3, 0))
        return n
    }

    static func berry(_ r: CGFloat, _ hex: String) -> SCNNode {
        return part(SCNSphere(radius: r), plain(hex, spec: 0.8, shine: 0.8), 0, r, 0)
    }

    private static func put(_ parent: SCNNode, _ n: SCNNode, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, yaw: CGFloat = 0, tilt: CGFloat = 0) {
        n.position = v3(x, y, z)
        n.eulerAngles = v3(0, yaw, tilt)
        parent.addChildNode(n)
    }

    private static func ring(_ parent: SCNNode, count: Int, offset: CGFloat, _ make: (Int) -> SCNNode, tilt: CGFloat, y: CGFloat) {
        for k in 0..<count {
            let a = offset + 2 * CGFloat.pi * CGFloat(k) / CGFloat(count)
            put(parent, make(k), 0, y, 0, yaw: -a, tilt: tilt)
        }
    }

    /// One arrangement, centred on the lid surface (y = 0 is the lid top).
    static func arrangement(_ id: String, hardware: String, small: Bool) -> SCNNode {
        let n = SCNNode()
        switch id {
        case "roses":
            ring(n, count: 7, offset: 0.2, { _ in leaf(5.0, "#4C7A4B") }, tilt: 0.12, y: 0.3)
            put(n, eucalyptus(6.5), 0, 0.5, 0, yaw: 0.6, tilt: 0.1)
            put(n, eucalyptus(6.0), 0, 0.5, 0, yaw: 3.0, tilt: 0.1)
            put(n, rose(1.9, "#F4EBDD"), 0, 0.5, 0)
            put(n, rose(1.5, "#F2C9D2"), 2.6, 0.4, 1.4)
            put(n, rose(1.5, "#F4EBDD"), -2.4, 0.4, 1.6)
            put(n, rose(1.3, "#F2C9D2"), 0.6, 0.4, -2.6)
            put(n, berry(0.3, "#FFFFFF"), 3.4, 0.4, -1.2)
            put(n, berry(0.3, "#FFFFFF"), -3.2, 0.4, -0.6)
        case "blush":
            ring(n, count: 5, offset: 0.4, { _ in fern(6.0) }, tilt: 0.12, y: 0.3)
            put(n, daisy(1.7, petal: "#F2B8C6", centre: "#D9A441", layers: 2, petals: 11), 0, 0.5, 0)
            put(n, daisy(1.4, petal: "#F8D7DE", centre: "#D9A441", layers: 2, petals: 10), 2.8, 0.4, 1.6)
            put(n, daisy(1.4, petal: "#F2B8C6", centre: "#D9A441", layers: 2, petals: 10), -2.6, 0.4, 1.4)
            put(n, daisy(1.1, petal: "#FFFFFF", centre: "#E8B93C", layers: 1, petals: 9), 0.4, 0.4, -2.6)
        case "marigold":
            ring(n, count: 6, offset: 0.1, { _ in leaf(6.5, "#3E7A3A") }, tilt: 0.15, y: 0.3)
            put(n, daisy(2.0, petal: "#EE8A2E", centre: "#C0601A", layers: 3, petals: 16), 0, 0.5, 0)
            put(n, daisy(1.7, petal: "#F2B52E", centre: "#C0601A", layers: 3, petals: 15), 2.8, 0.4, 1.5)
            put(n, daisy(1.7, petal: "#EE8A2E", centre: "#C0601A", layers: 3, petals: 15), -2.7, 0.4, 1.7)
            put(n, daisy(1.4, petal: "#F6C846", centre: "#C0601A", layers: 2, petals: 13), 0.8, 0.4, -2.8)
            put(n, daisy(0.8, petal: "#FFFFFF", centre: "#E8B93C", layers: 1, petals: 8), 3.6, 0.4, -1.4)
            put(n, daisy(0.8, petal: "#FFFFFF", centre: "#E8B93C", layers: 1, petals: 8), -3.4, 0.4, -1.0)
        case "lotus":
            for k in 0..<3 {
                let big = part(SCNSphere(radius: 2.6), plain("#4C7A4B", spec: 0.3, shine: 0.4), 0, 0.15, 0)
                big.scale = v3(1, 0.05, 1)
                put(n, big, CGFloat(k - 1) * 4.2, 0, CGFloat(k % 2) * 2.0 - 1.5)
            }
            put(n, lotus(2.4, "#F4B6C8"), 0, 0.3, 0)
            put(n, lotus(1.9, "#FFFFFF"), 3.4, 0.3, 1.2)
            put(n, lotus(1.2, "#F4B6C8"), -3.4, 0.3, 0.8)
        case "natural":
            for k in 0..<4 { put(n, pampas(8.0), 0, 0.4, 0, yaw: CGFloat(k) * 1.5 + 0.3, tilt: 0.55) }
            for k in 0..<3 { put(n, eucalyptus(7.0), 0, 0.4, 0, yaw: CGFloat(k) * 2.1, tilt: 0.2) }
            put(n, daisy(1.1, petal: "#EFE4CF", centre: "#B5842A", layers: 1, petals: 10), 1.0, 0.5, 1.0)
            put(n, daisy(1.1, petal: "#EFE4CF", centre: "#B5842A", layers: 1, petals: 10), -1.4, 0.5, -0.4)
            put(n, berry(0.35, "#8E1B3A"), 2.2, 0.4, -1.6)
            put(n, berry(0.35, "#8E1B3A"), -2.4, 0.4, 1.8)
        case "gold":
            for k in 0..<6 { put(n, goldSprig(7.0), 0, 0.4, 0, yaw: CGFloat(k) * 1.05, tilt: 0.2) }
            put(n, daisy(1.5, petal: "#E1BF5F", centre: "#7A5A1A", layers: 2, petals: 10), 0, 0.6, 0)
            for k in 0..<7 { put(n, berry(0.38, "#FFFFFF"), 1.7 * cos(CGFloat(k)), 0.4, 1.7 * sin(CGFloat(k))) }
        case "bow":
            put(n, bow(5.5, hardware), 0, 0.3, 0)
            put(n, rose(1.1, "#F4EBDD"), 0, 0.9, 0.2)
        case "monogram":
            let plate = SCNBox(width: 5.0, height: 0.25, length: 2.8, chamferRadius: 0.1)
            let plateNode = part(plate, metalMat(hardware), 0, 0.12, 0)
            n.addChildNode(plateNode)
            if let img = GiftTex.monogram(hardware) {
                let face = SCNPlane(width: 2.2, height: 2.2)
                let m = SCNMaterial()
                m.diffuse.contents = img
                m.lightingModel = .constant
                face.materials = [m]
                let fn = SCNNode(geometry: face)
                fn.position = v3(0, 0.27, 0)
                fn.eulerAngles = v3(-CGFloat.pi / 2, 0, 0)
                n.addChildNode(fn)
            }
        default:
            break
        }
        if small { n.scale = v3(0.62, 0.62, 0.62) }
        return n
    }
}

// MARK: - The whole gift

struct GiftBuild {
    var root: SCNNode
    var lid: SCNNode
    var jars: [SCNNode]
}

@MainActor
enum GiftScene {
    static let openAngle: CGFloat = 1.85

    static func finishMaterial(_ f: BoxFinish) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        if let t = GiftTex.finish(f) { m.diffuse.contents = t } else { m.diffuse.contents = ns(f.hex) }
        switch f.material {
        case .metal:
            m.specular.contents = NSColor.white
            m.shininess = 0.85
        case .wood:
            m.specular.contents = NSColor(white: 0.35, alpha: 1)
            m.shininess = 0.4
        case .leather:
            m.specular.contents = NSColor(white: 0.3, alpha: 1)
            m.shininess = 0.35
        case .rubber:
            m.specular.contents = NSColor(white: 0.05, alpha: 1)
            m.shininess = 0.1
        case .pu:
            m.specular.contents = NSColor(white: 0.7, alpha: 1)
            m.shininess = 0.7
        }
        return m
    }

    static func build(_ cfg: GiftConfig) -> GiftBuild {
        let W = CGFloat(GiftBoxSpec.outerW)
        let D = CGFloat(GiftBoxSpec.outerD)
        let t = CGFloat(GiftBoxSpec.wall)
        let baseH = CGFloat(GiftBoxSpec.baseH)
        let lidH = CGFloat(GiftBoxSpec.lidH)
        let trayH = CGFloat(GiftBoxSpec.trayH)
        let f = cfg.finish
        let outer = finishMaterial(f)
        let liner = plain(f.linerHex, spec: 0.05, shine: 0.1)
        let root = SCNNode()

        func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ mats: [SCNMaterial], _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, chamfer: CGFloat = 0.25) -> SCNNode {
            let g = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
            g.materials = mats
            let n = SCNNode(geometry: g)
            n.position = v3(x, y, z)
            return n
        }
        // SCNBox faces: front (+z), right (+x), back (-z), left (-x), top, bottom.
        root.addChildNode(box(W, t, D, [outer, outer, outer, outer, liner, outer], 0, t / 2, 0))
        root.addChildNode(box(W, baseH, t, [outer, outer, liner, outer, outer, outer], 0, baseH / 2, D / 2 - t / 2))
        root.addChildNode(box(W, baseH, t, [liner, outer, outer, outer, outer, outer], 0, baseH / 2, -(D / 2 - t / 2)))
        root.addChildNode(box(t, baseH, D - 2 * t, [outer, outer, outer, liner, outer, outer], W / 2 - t / 2, baseH / 2, 0, chamfer: 0.1))
        root.addChildNode(box(t, baseH, D - 2 * t, [outer, liner, outer, outer, outer, outer], -(W / 2 - t / 2), baseH / 2, 0, chamfer: 0.1))

        // Tray with a cut-out for each jar
        let innerW = W - 2 * t
        let innerD = D - 2 * t
        let tray = box(innerW, trayH, innerD, [liner, liner, liner, liner, liner, liner], 0, t + trayH / 2, 0, chamfer: 0.08)
        root.addChildNode(tray)
        let trayTop = t + trayH
        let layout = cfg.layout
        let seatY = trayTop - CGFloat(GiftBoxSpec.recess)
        var jarNodes: [SCNNode] = []
        var avoid: [(CGFloat, CGFloat, CGFloat)] = []
        for i in 0..<min(cfg.jars.count, layout.slots.count) {
            let slot = layout.slots[i]
            let spec = cfg.jars[i]
            let d = CGFloat(GiftCatalogue.jarDiameter(slot: slot, size: spec.sizeID))
            let h = CGFloat(GiftCatalogue.jarHeight(spec.styleID, spec.sizeID))
            let x = CGFloat(slot.x) - innerW / 2
            let z = CGFloat(slot.y) - innerD / 2
            let hole = SCNTube(innerRadius: d / 2 + 0.12, outerRadius: d / 2 + 0.5, height: 0.08)
            root.addChildNode(part(hole, metalMat(f.hardwareHex), x, trayTop + 0.04, z))
            let jar = GiftJar3D.node(spec, diameter: d, height: h, seed: 300 + i, hardware: f.hardwareHex)
            jar.position = v3(x, seatY, z)
            root.addChildNode(jar)
            jarNodes.append(jar)
            avoid.append((x, z, d / 2 + 0.6))
        }
        root.addChildNode(filling(cfg, innerW: innerW, innerD: innerD, y: trayTop, avoid: avoid))

        // Hinged lid
        let pivot = SCNNode()
        pivot.position = v3(0, baseH, -D / 2)
        let lidBody = box(W, lidH, D, [outer, outer, outer, outer, outer, liner], 0, lidH / 2, D / 2)
        pivot.addChildNode(lidBody)
        if let img = GiftTex.plaque(f.hardwareHex) {
            let p = SCNPlane(width: 10.4, height: 5.6)
            let m = SCNMaterial()
            m.diffuse.contents = img
            m.lightingModel = .blinn
            p.materials = [m]
            let pn = SCNNode(geometry: p)
            pn.position = v3(0, lidH + 0.03, D / 2)
            pn.eulerAngles = v3(-CGFloat.pi / 2, 0, 0)
            pivot.addChildNode(pn)
        }
        if let img = GiftTex.card(cfg) {
            let p = SCNPlane(width: 15, height: 15 * 538 / 780)
            let m = SCNMaterial()
            m.diffuse.contents = img
            m.lightingModel = .constant
            p.materials = [m]
            let pn = SCNNode(geometry: p)
            pn.position = v3(0, -0.03, D / 2)
            pn.eulerAngles = v3(CGFloat.pi / 2, 0, 0)
            pivot.addChildNode(pn)
        }
        let hw = metalMat(f.hardwareHex)
        for sx in [-10.0, 10.0] {
            pivot.addChildNode(part(SCNBox(width: 3, height: 1.0, length: 0.5, chamferRadius: 0.1), hw, CGFloat(sx), 0.3, -0.2))
        }
        pivot.addChildNode(part(SCNBox(width: 2.8, height: 1.0, length: 0.4, chamferRadius: 0.1), hw, 0, lidH / 2, D + 0.2))
        root.addChildNode(part(SCNBox(width: 2.8, height: 1.5, length: 0.4, chamferRadius: 0.1), hw, 0, baseH - 0.9, D / 2 + 0.2))
        if cfg.flowerID != "none" {
            let main = GiftFlora.arrangement(cfg.flowerID, hardware: f.hardwareHex, small: false)
            if cfg.flowerID == "monogram" {
                main.position = v3(0, lidH, 5.5)
            } else {
                main.position = v3(-11.5, lidH, 6.0)
            }
            pivot.addChildNode(main)
            if cfg.flowerID != "monogram" && cfg.flowerID != "bow" {
                let side = GiftFlora.arrangement(cfg.flowerID, hardware: f.hardwareHex, small: true)
                side.position = v3(12.5, lidH, 19.5)
                side.eulerAngles = v3(0, 2.2, 0)
                pivot.addChildNode(side)
            }
        }
        root.addChildNode(pivot)
        return GiftBuild(root: root, lid: pivot, jars: jarNodes)
    }

    static func filling(_ cfg: GiftConfig, innerW: CGFloat, innerD: CGFloat, y: CGFloat, avoid: [(CGFloat, CGFloat, CGFloat)]) -> SCNNode {
        let root = SCNNode()
        if cfg.fillingID == "none" { return root }
        var rng = GiftRNG(91)
        let hex = cfg.fillingHex
        let tones = [GiftColor.shade(hex, 1.12), hex, GiftColor.shade(hex, 0.86)]
        let silk = tones.map { plain($0, spec: 0.5, shine: 0.6) }
        let total = cfg.fillingID == "silk" || cfg.fillingID == "paper" ? 260 : 170
        var placed = 0
        var tries = 0
        while placed < total && tries < total * 8 {
            tries += 1
            let x = rng.range(-innerW / 2 + 0.7, innerW / 2 - 0.7)
            let z = rng.range(-innerD / 2 + 0.7, innerD / 2 - 0.7)
            var blocked = false
            for a in avoid where hypot(a.0 - x, a.1 - z) < a.2 { blocked = true; break }
            if blocked { continue }
            placed += 1
            let py = y + rng.range(0.05, 0.6)
            let tone = Int(rng.range(0, 2.99))
            let node: SCNNode
            switch cfg.fillingID {
            case "silk":
                node = part(SCNBox(width: 2.0, height: 0.06, length: 0.14, chamferRadius: 0), silk[tone], x, py, z)
                node.eulerAngles = v3(rng.range(-0.3, 0.3), rng.range(0, 6.28), rng.range(-0.3, 0.3))
            case "paper":
                node = part(SCNBox(width: 2.4, height: 0.03, length: 0.16, chamferRadius: 0), silk[tone], x, py, z)
                node.eulerAngles = v3(rng.range(-0.4, 0.4), rng.range(0, 6.28), rng.range(-0.4, 0.4))
            case "petals":
                node = part(SCNSphere(radius: 0.5), silk[tone], x, py, z)
                node.scale = v3(1, 0.14, 0.6)
                node.eulerAngles = v3(0, rng.range(0, 6.28), rng.range(-0.3, 0.3))
            case "beads":
                node = part(SCNSphere(radius: 0.24), metalMat("#E1BF5F"), x, py, z)
            default:
                node = part(SCNSphere(radius: 0.26), plain("#F6F3EC", spec: 0.9, shine: 0.9), x, py, z)
            }
            root.addChildNode(node)
        }
        return root.flattenedClone()
    }
}

// MARK: - Camera

enum GiftCameraPreset: String, CaseIterable {
    case threeQuarter = "3/4"
    case front = "Front"
    case right = "Right"
    case back = "Back"
    case left = "Left"
    case top = "Top"

    var position: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .threeQuarter: return (44, 40, 60)
        case .front: return (0, 18, 72)
        case .right: return (72, 18, 0)
        case .back: return (0, 18, -72)
        case .left: return (-72, 18, 0)
        case .top: return (0, 96, 0.5)
        }
    }
}

// MARK: - SceneKit views

@MainActor
final class GiftSceneCoordinator {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    var giftNode: SCNNode?
    var build: GiftBuild?
    var signature = ""
    var cameraTick = -1
    var lastLid: CGFloat = -1
    var lastJars = -2

    init() {
        let cam = SCNCamera()
        cam.fieldOfView = 34
        cam.zNear = 1
        cam.zFar = 600
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        place(.threeQuarter, animated: false)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        ambient.light?.color = NSColor(red: 1, green: 0.97, blue: 0.92, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.light?.castsShadow = true
        key.light?.shadowRadius = 10
        key.light?.shadowSampleCount = 8
        key.light?.shadowColor = NSColor(white: 0, alpha: 0.35)
        key.position = v3(30, 90, 60)
        key.look(at: v3(0, 0, 0))
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 350
        fill.position = v3(-60, 50, 40)
        scene.rootNode.addChildNode(fill)

        let floor = SCNFloor()
        floor.reflectivity = 0
        let fm = SCNMaterial()
        fm.diffuse.contents = NSColor(red: 0.93, green: 0.89, blue: 0.82, alpha: 1)
        fm.lightingModel = .lambert
        floor.materials = [fm]
        scene.rootNode.addChildNode(SCNNode(geometry: floor))
    }

    func place(_ preset: GiftCameraPreset, animated: Bool) {
        let p = preset.position
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.8
        }
        cameraNode.position = v3(p.0, p.1, p.2)
        cameraNode.look(at: v3(0, 3.5, 0))
        if animated { SCNTransaction.commit() }
    }

    func signature(_ c: GiftConfig) -> String {
        let jars = c.jars.map { "\($0.styleID).\($0.materialID).\($0.sizeID).\($0.contentID).\($0.lid)" }.joined(separator: ",")
        let parts: [String] = [c.finishID, c.layoutID, jars, c.fillingID, c.fillingHex, c.flowerID, c.cardStyle, c.cardTo, c.cardFrom, c.cardMessage]
        return parts.joined(separator: "|")
    }

    func sync(_ state: GiftingState) {
        let sig = signature(state.config)
        var first = false
        if sig != signature || build == nil {
            giftNode?.removeFromParentNode()
            let b = GiftScene.build(state.config)
            scene.rootNode.addChildNode(b.root)
            giftNode = b.root
            build = b
            signature = sig
            lastLid = -1
            lastJars = -2
            first = true
        }
        guard let b = build else { return }
        let lid = state.lidOpenAmount
        if abs(lid - lastLid) > 0.001 {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = first || lastLid < 0 ? 0 : 0.9
            b.lid.eulerAngles = v3(-lid * GiftScene.openAngle, 0, 0)
            SCNTransaction.commit()
            lastLid = lid
        }
        let shown = state.visibleJars
        if shown != lastJars {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = lastJars == -2 ? 0 : 0.5
            for (i, j) in b.jars.enumerated() { j.opacity = i < shown ? 1 : 0 }
            SCNTransaction.commit()
            lastJars = shown
        }
        if state.cameraTick != cameraTick {
            place(state.cameraPreset, animated: cameraTick >= 0)
            cameraTick = state.cameraTick
        }
    }
}

struct GiftSceneView: NSViewRepresentable {
    @ObservedObject var state: GiftingState

    func makeCoordinator() -> GiftSceneCoordinator { return MainActor.assumeIsolated { GiftSceneCoordinator() } }

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = context.coordinator.scene
        v.pointOfView = context.coordinator.cameraNode
        v.allowsCameraControl = true
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = NSColor(red: 0.96, green: 0.93, blue: 0.87, alpha: 1)
        context.coordinator.sync(state)
        DispatchQueue.main.async { state.sceneView = v }
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {
        context.coordinator.sync(state)
    }
}

/// Every jar of the gift on its own turntable, so it can be seen from all sides.
@MainActor
final class GiftJarStudioCoordinator {
    let scene = SCNScene()
    var signature = ""
    let cameraNode = SCNNode()

    init() {
        let cam = SCNCamera()
        cam.fieldOfView = 30
        cam.zNear = 1
        cam.zFar = 400
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 600
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.position = v3(20, 60, 50)
        key.look(at: v3(0, 3, 0))
        scene.rootNode.addChildNode(key)
        let back = SCNNode()
        back.light = SCNLight()
        back.light?.type = .omni
        back.light?.intensity = 400
        back.position = v3(-40, 30, -30)
        scene.rootNode.addChildNode(back)
    }

    func sync(_ cfg: GiftConfig) {
        let sig = cfg.jars.map { "\($0.styleID).\($0.materialID).\($0.sizeID).\($0.contentID).\($0.lid)" }.joined(separator: ",") + cfg.layoutID + cfg.finish.hardwareHex
        if sig == signature { return }
        signature = sig
        for c in scene.rootNode.childNodes where c.name == "studio-jar" { c.removeFromParentNode() }
        let layout = cfg.layout
        var diameters: [CGFloat] = []
        for (i, j) in cfg.jars.enumerated() where i < layout.slots.count {
            diameters.append(CGFloat(GiftCatalogue.jarDiameter(slot: layout.slots[i], size: j.sizeID)))
        }
        let gap: CGFloat = 3
        let total = diameters.reduce(0, +) + gap * CGFloat(max(0, diameters.count - 1))
        var x = -total / 2
        for (i, d) in diameters.enumerated() {
            let spec = cfg.jars[i]
            let h = CGFloat(GiftCatalogue.jarHeight(spec.styleID, spec.sizeID))
            let spinner = SCNNode()
            spinner.name = "studio-jar"
            spinner.position = v3(x + d / 2, 0, 0)
            spinner.addChildNode(GiftJar3D.node(spec, diameter: d, height: h, seed: 300 + i, hardware: cfg.finish.hardwareHex))
            spinner.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 14)))
            scene.rootNode.addChildNode(spinner)
            x += d + gap
        }
        let dist = max(30, total * 1.35)
        cameraNode.position = v3(0, 10, dist)
        cameraNode.look(at: v3(0, 2.8, 0))
    }
}

struct GiftJarStudio: NSViewRepresentable {
    let config: GiftConfig

    func makeCoordinator() -> GiftJarStudioCoordinator { return MainActor.assumeIsolated { GiftJarStudioCoordinator() } }

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = context.coordinator.scene
        v.pointOfView = context.coordinator.cameraNode
        v.allowsCameraControl = true
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = NSColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1)
        context.coordinator.sync(config)
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {
        context.coordinator.sync(config)
    }
}
