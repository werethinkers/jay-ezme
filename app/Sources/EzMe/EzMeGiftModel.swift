// Gifting model: ONE fixed-size box in five real materials, jar styles and materials, contents, filling, lid flowers.
// Prices are placeholders until Izzhaar supplies real ones. Sizes are a proposed design size, in centimetres.
import Foundation
import SwiftUI

enum GiftBoxSpec {
    static let outerW = 34.0
    static let outerD = 24.0
    static let height = 9.0
    static let wall = 1.2
    static var innerW: Double { return outerW - 2 * wall }
    static var innerD: Double { return outerD - 2 * wall }
    /// The lid is a 1.2 cm slab on a 7.8 cm base; the tray is 1.2 cm thick and each jar sits 0.6 cm into it.
    static let baseH = 7.8
    static let lidH = 1.2
    static let trayH = 1.2
    static let recess = 0.6
    /// Clear height inside with the lid shut (floor and lid slab taken off).
    static var clearHeight: Double { return height - 2 * wall }
    static var innerHeight: Double { return clearHeight }
    /// The tallest jar, with its lid on, that still lets the box close.
    static var maxJarHeight: Double { return clearHeight - (trayH - recess) }

    static func cm(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        if r == r.rounded() { return String(Int(r)) }
        return String(format: "%.1f", r)
    }
}

enum GiftRange {
    static let min = 3000
    static let max = 10000
}

enum BoxMaterial: String, CaseIterable, Codable {
    case wood, metal, leather, rubber, pu

    var title: String {
        switch self {
        case .wood: return "Wood"
        case .metal: return "Metal"
        case .leather: return "Leather"
        case .rubber: return "Rubber"
        case .pu: return "PU"
        }
    }

    var detail: String {
        switch self {
        case .wood: return "Solid wood with visible grain, hinged lid, brass fittings."
        case .metal: return "Brushed metal sheet over a rigid core, riveted hinges."
        case .leather: return "Leather wrapped over board, stitched edge, soft lining."
        case .rubber: return "Matte soft-touch rubber coating, shock absorbing, easy to wipe."
        case .pu: return "Smooth PU (faux leather) wrap with a sheen and stitched edge."
        }
    }

    /// Price of the empty box in this material. The size is the same for all.
    var basePrice: Int {
        switch self {
        case .wood: return 1800
        case .metal: return 2000
        case .leather: return 2200
        case .rubber: return 1500
        case .pu: return 1600
        }
    }
}

struct BoxFinish: Identifiable {
    let id: String
    let material: BoxMaterial
    let name: String
    let hex: String
    let stitchHex: String
    let hardwareHex: String
    let linerHex: String
    let words: [String]
}

struct GiftLayoutSlot {
    let x: Double
    let y: Double
    let maxD: Double
}

struct GiftLayout: Identifiable {
    let id: String
    let name: String
    let slots: [GiftLayoutSlot]
    let slotNames: [String]
    let words: [String]
}

enum JarShape { case round, octagon, square }

struct JarStyle: Identifiable {
    let id: String
    let name: String
    let photo: String
    let shape: JarShape
    let facets: Int
    let price: Int
    let words: [String]
}

struct JarMaterial: Identifiable {
    let id: String
    let name: String
    let hex: String
    let add: Int
    let words: [String]
}

struct JarContent: Identifiable {
    let id: String
    let name: String
    let price: Int
    let hex: String
    let words: [String]
}

struct GiftFilling: Identifiable {
    let id: String
    let name: String
    let price: Int
    let words: [String]
}

struct GiftFlower: Identifiable {
    let id: String
    let name: String
    let price: Int
    let words: [String]
}

enum GiftCatalogue {
    static let finishes: [BoxFinish] = [
        BoxFinish(id: "walnut", material: .wood, name: "Walnut", hex: "#5A3A22", stitchHex: "#D4A84A", hardwareHex: "#D4A84A", linerHex: "#E9DFCB", words: ["walnut", "dark wood"]),
        BoxFinish(id: "teak", material: .wood, name: "Teak", hex: "#A8703A", stitchHex: "#D4A84A", hardwareHex: "#D4A84A", linerHex: "#F1E6D0", words: ["teak", "light wood"]),
        BoxFinish(id: "whitewash", material: .wood, name: "Whitewash", hex: "#D9CDB8", stitchHex: "#B8941F", hardwareHex: "#C9A24A", linerHex: "#F6EFE2", words: ["whitewash", "white wood", "pale wood"]),
        BoxFinish(id: "brass", material: .metal, name: "Brushed brass", hex: "#C9A24A", stitchHex: "#8A6B1F", hardwareHex: "#E8D08A", linerHex: "#2A2230", words: ["brass", "brushed brass", "golden metal", "gold metal"]),
        BoxFinish(id: "silver", material: .metal, name: "Brushed silver", hex: "#BFC4CC", stitchHex: "#6C727C", hardwareHex: "#E4E7EC", linerHex: "#27304A", words: ["silver metal", "brushed silver", "steel", "silver box"]),
        BoxFinish(id: "copper", material: .metal, name: "Antique copper", hex: "#B0693A", stitchHex: "#6B3A1C", hardwareHex: "#D9A06A", linerHex: "#2B1E1A", words: ["copper", "antique copper"]),
        BoxFinish(id: "tan", material: .leather, name: "Tan leather", hex: "#A8683A", stitchHex: "#F1DDB5", hardwareHex: "#D4A84A", linerHex: "#F3E8D2", words: ["tan leather", "tan", "brown leather"]),
        BoxFinish(id: "blackleather", material: .leather, name: "Black leather", hex: "#232124", stitchHex: "#D4A84A", hardwareHex: "#D4A84A", linerHex: "#EADFCB", words: ["black leather", "black box"]),
        BoxFinish(id: "tealleather", material: .leather, name: "Teal leather", hex: "#1D5E63", stitchHex: "#F1DDB5", hardwareHex: "#D4A84A", linerHex: "#F1E8D6", words: ["teal leather", "teal box"]),
        BoxFinish(id: "charcoal", material: .rubber, name: "Charcoal rubber", hex: "#34353A", stitchHex: "#9AA0A8", hardwareHex: "#C9CED8", linerHex: "#E8E2D4", words: ["charcoal rubber", "charcoal", "grey rubber", "gray rubber"]),
        BoxFinish(id: "sage", material: .rubber, name: "Sage rubber", hex: "#7E8F78", stitchHex: "#E6EDE0", hardwareHex: "#E2D7B2", linerHex: "#F1EFE2", words: ["sage rubber", "sage", "green rubber"]),
        BoxFinish(id: "navyrubber", material: .rubber, name: "Navy rubber", hex: "#26324A", stitchHex: "#9DB0D6", hardwareHex: "#C9CED8", linerHex: "#EDE8DA", words: ["navy rubber", "navy box", "blue rubber"]),
        BoxFinish(id: "ivorypu", material: .pu, name: "Ivory PU", hex: "#EDE4D3", stitchHex: "#B8941F", hardwareHex: "#D4A84A", linerHex: "#7A1F3D", words: ["ivory pu", "ivory box", "white pu", "cream pu"]),
        BoxFinish(id: "burgundypu", material: .pu, name: "Burgundy PU", hex: "#6D1F33", stitchHex: "#E8C77A", hardwareHex: "#D4A84A", linerHex: "#F3E8D2", words: ["burgundy pu", "burgundy box", "maroon pu", "wine pu"]),
        BoxFinish(id: "emeraldpu", material: .pu, name: "Emerald PU", hex: "#1F6B4F", stitchHex: "#E8C77A", hardwareHex: "#D4A84A", linerHex: "#F3EBD8", words: ["emerald pu", "emerald box", "green pu"]),
    ]

    static func finish(_ id: String) -> BoxFinish {
        return finishes.first { $0.id == id } ?? finishes[0]
    }

    static func finishList(of material: BoxMaterial) -> [BoxFinish] {
        return finishes.filter { $0.material == material }
    }

    static let layouts: [GiftLayout] = [
        GiftLayout(id: "pair", name: "Pair", slots: [GiftLayoutSlot(x: 8.2, y: 10.8, maxD: 13.0), GiftLayoutSlot(x: 23.4, y: 10.8, maxD: 13.0)],
                   slotNames: ["left", "right"], words: ["pair", "two jars", "2 jars", "two"]),
        GiftLayout(id: "trio", name: "Trio", slots: [GiftLayoutSlot(x: 5.3, y: 10.8, maxD: 10.0), GiftLayoutSlot(x: 15.8, y: 10.8, maxD: 10.0), GiftLayoutSlot(x: 26.3, y: 10.8, maxD: 10.0)],
                   slotNames: ["left", "centre", "right"], words: ["trio", "three jars", "3 jars", "three"]),
        GiftLayout(id: "quartet", name: "Quartet", slots: [GiftLayoutSlot(x: 8.2, y: 5.4, maxD: 10.2), GiftLayoutSlot(x: 23.4, y: 5.4, maxD: 10.2),
                                                           GiftLayoutSlot(x: 8.2, y: 16.2, maxD: 10.2), GiftLayoutSlot(x: 23.4, y: 16.2, maxD: 10.2)],
                   slotNames: ["top left", "top right", "bottom left", "bottom right"], words: ["quartet", "four jars", "4 jars", "four", "2 by 2"]),
        GiftLayout(id: "centre", name: "Centre and sides", slots: [GiftLayoutSlot(x: 4.7, y: 10.8, maxD: 8.0), GiftLayoutSlot(x: 15.8, y: 10.8, maxD: 12.0), GiftLayoutSlot(x: 26.9, y: 10.8, maxD: 8.0)],
                   slotNames: ["left", "centre", "right"], words: ["centre and sides", "center and sides", "centrepiece", "centerpiece", "hero jar", "big centre"]),
    ]

    static func layout(_ id: String) -> GiftLayout {
        return layouts.first { $0.id == id } ?? layouts[0]
    }

    /// Small, medium and large take 70%, 85% and 100% of the slot. A jar always fits its slot.
    static func jarDiameter(slot: GiftLayoutSlot, size: String) -> Double {
        let f: Double = size == "S" ? 0.70 : (size == "L" ? 1.0 : 0.85)
        return (slot.maxD * f * 10).rounded() / 10
    }

    static let jarStyles: [JarStyle] = [
        JarStyle(id: "facet", name: "Faceted trinket jar", photo: "blossom-jar", shape: .round, facets: 12, price: 900, words: ["faceted", "facet", "trinket jar", "blossom"]),
        JarStyle(id: "octagon", name: "Octagon crystal jar", photo: "crystal-trinket", shape: .octagon, facets: 8, price: 950, words: ["octagon", "octagonal", "crystal trinket"]),
        JarStyle(id: "relief", name: "Relief ceramic jar", photo: "rose-jar", shape: .round, facets: 0, price: 850, words: ["relief", "rose jar", "floral jar", "ceramic jar"]),
        JarStyle(id: "perfume", name: "Square perfume bottle", photo: "floral-atomizer", shape: .square, facets: 0, price: 1000, words: ["square", "perfume bottle", "atomizer", "atomiser", "bottle"]),
        JarStyle(id: "candlebowl", name: "Candle bowl", photo: "regal-candle-bowl", shape: .round, facets: 0, price: 800, words: ["candle bowl", "bowl", "round jar"]),
        JarStyle(id: "woodlid", name: "Glass jar, wooden lid", photo: "woodland-elegance", shape: .round, facets: 0, price: 950, words: ["wooden lid", "woodland", "lid jar", "glass jar"]),
        JarStyle(id: "diffuser", name: "Reed diffuser bottle", photo: "botanical-diffuser", shape: .square, facets: 0, price: 900, words: ["diffuser bottle", "reed bottle", "botanical"]),
        JarStyle(id: "tin", name: "Floral tin", photo: "tin-duo", shape: .octagon, facets: 0, price: 700, words: ["tin", "floral tin", "tin box"]),
    ]

    static func jarStyle(_ id: String) -> JarStyle {
        return jarStyles.first { $0.id == id } ?? jarStyles[0]
    }

    /// Height of each jar with its lid on, at the large size. Small is 80% and medium 90%. Never above what the closed box allows.
    static func jarHeight(_ styleID: String, _ size: String) -> Double {
        let large: Double
        switch styleID {
        case "octagon": large = 5.8
        case "relief": large = 5.8
        case "perfume": large = 6.0
        case "candlebowl": large = 4.4
        case "woodlid": large = 6.0
        case "diffuser": large = 6.0
        case "tin": large = 4.0
        default: large = 6.0
        }
        let f: Double = size == "S" ? 0.8 : (size == "L" ? 1.0 : 0.9)
        return min(GiftBoxSpec.maxJarHeight, (large * f * 10).rounded() / 10)
    }

    static let jarMaterials: [JarMaterial] = [
        JarMaterial(id: "crystal", name: "Crystal glass", hex: "#BFD6DE", add: 250, words: ["crystal", "clear glass", "glass"]),
        JarMaterial(id: "frosted", name: "Frosted glass", hex: "#E6ECEF", add: 200, words: ["frosted", "frosted glass", "matte glass"]),
        JarMaterial(id: "ceramic", name: "Ceramic", hex: "#F1E9DC", add: 150, words: ["ceramic", "porcelain", "clay"]),
        JarMaterial(id: "metal", name: "Metal", hex: "#C9A24A", add: 300, words: ["metal", "brass", "gold"]),
        JarMaterial(id: "wood", name: "Wood", hex: "#8A5A32", add: 200, words: ["wood", "wooden"]),
    ]

    static func jarMaterial(_ id: String) -> JarMaterial {
        return jarMaterials.first { $0.id == id } ?? jarMaterials[0]
    }

    static let contents: [JarContent] = [
        JarContent(id: "candle", name: "Scented candle", price: 450, hex: "#F3E6C8", words: ["candle", "candles", "wax"]),
        JarContent(id: "perfume", name: "Perfume", price: 600, hex: "#D4A84A", words: ["perfume", "fragrance", "attar", "scent"]),
        JarContent(id: "diffuser", name: "Diffuser sticks", price: 500, hex: "#8A6B2E", words: ["diffuser", "reed", "sticks", "aroma"]),
        JarContent(id: "cookies", name: "Cookies", price: 350, hex: "#C48A4A", words: ["cookie", "cookies", "biscuits"]),
        JarContent(id: "dryfruits", name: "Dry fruits", price: 550, hex: "#C9A25C", words: ["dry fruits", "dry fruit", "nuts", "almonds", "cashews"]),
        JarContent(id: "chocolates", name: "Chocolates", price: 400, hex: "#4A2A1C", words: ["chocolate", "chocolates", "truffles"]),
        JarContent(id: "tea", name: "Tea leaves", price: 350, hex: "#6E8B3D", words: ["tea", "chai", "tea leaves"]),
        JarContent(id: "potpourri", name: "Potpourri", price: 250, hex: "#E8789C", words: ["potpourri", "petals mix", "dried flowers"]),
        JarContent(id: "none", name: "Empty", price: 0, hex: "#000000", words: ["empty", "nothing", "no contents"]),
    ]

    static func content(_ id: String) -> JarContent {
        return contents.first { $0.id == id } ?? contents[contents.count - 1]
    }

    static let fillings: [GiftFilling] = [
        GiftFilling(id: "silk", name: "Silk shred", price: 200, words: ["silk", "silk shred", "silk filling"]),
        GiftFilling(id: "petals", name: "Dried petals", price: 250, words: ["petals", "dried petals", "rose petals"]),
        GiftFilling(id: "beads", name: "Golden beads", price: 300, words: ["beads", "golden beads", "gold beads"]),
        GiftFilling(id: "pearls", name: "Pearls", price: 300, words: ["pearls", "pearl"]),
        GiftFilling(id: "paper", name: "Paper shred", price: 100, words: ["paper", "paper shred", "shredded paper"]),
        GiftFilling(id: "none", name: "No filling", price: 0, words: ["no filling", "empty gaps", "plain"]),
    ]

    static func filling(_ id: String) -> GiftFilling {
        return fillings.first { $0.id == id } ?? fillings[fillings.count - 1]
    }

    static let flowers: [GiftFlower] = [
        GiftFlower(id: "roses", name: "Rose garden", price: 400, words: ["roses", "rose", "ivory roses", "rose garden", "flowers", "flower"]),
        GiftFlower(id: "blush", name: "Blush blossoms and ferns", price: 300, words: ["blush", "blossoms", "blossom", "blush flowers", "ferns"]),
        GiftFlower(id: "marigold", name: "Marigold and mango leaves", price: 300, words: ["marigold", "marigolds", "genda", "mango leaves", "diwali flowers"]),
        GiftFlower(id: "lotus", name: "Lotus and lily", price: 450, words: ["lotus", "lily", "lilies", "lotus flowers"]),
        GiftFlower(id: "natural", name: "Eucalyptus and pampas", price: 350, words: ["eucalyptus", "pampas", "dried flowers", "natural flowers", "leaves"]),
        GiftFlower(id: "gold", name: "Gold-leaf sprigs and pearls", price: 450, words: ["gold flowers", "gold blooms", "gold leaf", "golden flowers", "blooms", "gold sprigs"]),
        GiftFlower(id: "bow", name: "Satin bow", price: 250, words: ["bow", "ribbon", "satin bow", "ribbon bow"]),
        GiftFlower(id: "monogram", name: "Brass monogram plate", price: 250, words: ["monogram", "plate", "brass plate", "initial"]),
        GiftFlower(id: "none", name: "No decoration", price: 0, words: ["no flowers", "no decoration", "plain lid", "remove flowers"]),
    ]

    static func flower(_ id: String) -> GiftFlower {
        return flowers.first { $0.id == id } ?? flowers[flowers.count - 1]
    }
}

struct JarSpec: Codable, Equatable {
    var styleID: String
    var materialID: String
    var sizeID: String
    var contentID: String
    var lid: Bool = true
}

struct GiftConfig: Codable {
    var finishID: String = "walnut"
    var layoutID: String = "pair"
    var jars: [JarSpec] = [
        JarSpec(styleID: "facet", materialID: "crystal", sizeID: "M", contentID: "candle"),
        JarSpec(styleID: "octagon", materialID: "crystal", sizeID: "M", contentID: "perfume"),
    ]
    var fillingID: String = "silk"
    var fillingHex: String = "#F2C9D2"
    var flowerID: String = "roses"
    var cardStyle: String = "classic"
    var cardTo: String = ""
    var cardFrom: String = ""
    var cardMessage: String = ""
    var occasion: String = "birthday"
    var tone: String = "heartfelt"
    var note: String = ""
    var quantity: Int = 1
    var customer: String = ""
    var phone: String = ""
    var address: String = ""

    var finish: BoxFinish { return GiftCatalogue.finish(finishID) }
    var boxName: String { return finish.name + " box" }
    var layout: GiftLayout { return GiftCatalogue.layout(layoutID) }

    var boxPrice: Int { return finish.material.basePrice }

    func jarPrice(_ jar: JarSpec) -> Int {
        let style = GiftCatalogue.jarStyle(jar.styleID)
        let mult: Double = jar.sizeID == "S" ? 0.8 : (jar.sizeID == "L" ? 1.25 : 1.0)
        let body = Int((Double(style.price) * mult).rounded())
        return body + GiftCatalogue.jarMaterial(jar.materialID).add
    }

    var jarsPrice: Int {
        var t = 0
        for j in jars { t += jarPrice(j) + GiftCatalogue.content(j.contentID).price }
        return t
    }

    var fillingPrice: Int { return GiftCatalogue.filling(fillingID).price }
    var flowerPrice: Int { return GiftCatalogue.flower(flowerID).price }
    var unitPrice: Int { return boxPrice + jarsPrice + fillingPrice + flowerPrice }
    var total: Int { return unitPrice * max(1, quantity) }
}

struct GiftOrder: Codable, Identifiable {
    var id: String
    var date: Date
    var config: GiftConfig
    var total: Int
    var summary: String
}

enum GiftView: String, CaseIterable {
    case closed = "Closed"
    case inside = "Inside"
    case unbox = "Unboxing"
    case card = "Card"
    case plan = "Plan"
}
