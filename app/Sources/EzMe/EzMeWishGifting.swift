// WishStudio "Gifting": 30 same-size VYBES gift boxes (Rs 3,000 to Rs 10,000), changed by one spoken sentence.
// Shows the closed box, how the items sit inside, an unboxing, the card, a gift-experience note and an order.
// The VYBES logo (Resources/VybesLogo.png) is on the box, inside the lid, on the card and on every order.
import Foundation
import SwiftUI
import AppKit

// MARK: - Logo

enum VybesLogo {
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "VybesLogo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

struct VybesLogoView: View {
    var body: some View {
        if let img = VybesLogo.image {
            Image(nsImage: img).resizable().scaledToFit()
        } else {
            Text("VYBES").font(.system(size: 16, weight: .bold, design: .serif)).minimumScaleFactor(0.3).lineLimit(1)
        }
    }
}

// MARK: - Colours

enum GiftColor {
    static func rgb(_ hex: String) -> (Double, Double, Double) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if s.count != 6 { s = "888888" }
        let v = UInt32(s, radix: 16) ?? 0x888888
        return (Double((v >> 16) & 255) / 255.0, Double((v >> 8) & 255) / 255.0, Double(v & 255) / 255.0)
    }

    static func hex(_ r: Double, _ g: Double, _ b: Double) -> String {
        let ri = Int((min(1, max(0, r)) * 255).rounded())
        let gi = Int((min(1, max(0, g)) * 255).rounded())
        let bi = Int((min(1, max(0, b)) * 255).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    /// factor below 1 darkens, above 1 moves towards white.
    static func shade(_ hex: String, _ factor: Double) -> String {
        let c = rgb(hex)
        if factor <= 1 { return GiftColor.hex(c.0 * factor, c.1 * factor, c.2 * factor) }
        let t = factor - 1
        return GiftColor.hex(c.0 + (1 - c.0) * t, c.1 + (1 - c.1) * t, c.2 + (1 - c.2) * t)
    }

    static let swatches: [String] = [
        "#7A1F3D", "#C62828", "#E8789C", "#F2C9D2", "#EE8A2E", "#D4A84A", "#F2C230", "#2E9467", "#1F5A45", "#146B73",
        "#3B6FD6", "#1D2F5C", "#6D4AB0", "#5B2A6B", "#7A4B2A", "#2B2B30", "#F3EBDD", "#FFFFFF", "#C9CED8", "#B76E79",
    ]

    static let names: [String: String] = [
        "red": "#C62828", "maroon": "#7A1F3D", "burgundy": "#6D1A36", "wine": "#722F37", "pink": "#E8789C", "rose": "#D96B8A",
        "rose gold": "#B76E79", "blush": "#F2C9D2", "orange": "#EE8A2E", "saffron": "#E67E00", "gold": "#D4A84A", "golden": "#D4A84A",
        "yellow": "#F2C230", "mustard": "#D1A21B", "green": "#2E9467", "emerald": "#1F6F54", "olive": "#6B7B3A", "mint": "#CDEBD9",
        "teal": "#146B73", "turquoise": "#2BA6A0", "blue": "#3B6FD6", "royal blue": "#2A4DB0", "navy": "#1D2F5C", "sky blue": "#8DBBEA",
        "purple": "#6D4AB0", "violet": "#7B52B8", "lavender": "#C9B6E8", "lilac": "#D9C3EE", "plum": "#5B2A6B", "black": "#1E1E22",
        "charcoal": "#2B2B30", "white": "#FFFFFF", "ivory": "#F3EBDD", "cream": "#F7EEDC", "beige": "#E6D8BF", "brown": "#7A4B2A",
        "copper": "#B87333", "bronze": "#A9713A", "silver": "#C9CED8", "grey": "#9AA0A8", "gray": "#9AA0A8", "peach": "#F8C9B0",
        "coral": "#EF6F5E", "terracotta": "#C0603A", "magenta": "#C2288F",
    ]
}

func giftRupees(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_IN")
    return "\u{20B9}" + (f.string(from: NSNumber(value: n)) ?? String(n))
}

// MARK: - Catalogue of items, decorations and boxes

struct GiftItem: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let price: Int
    let words: [String]
}

struct GiftDecor: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let words: [String]
}

enum GiftRange {
    static let min = 3000
    static let max = 10000
    static let slots = 6
    /// The same-size VYBES box, ribbon, lining and card, added to the products inside.
    static let boxFee = 500
}

/// Product photographs cropped from the Diwali catalogues, bundled in Resources/Gifting.
enum GiftPhoto {
    private static var cache: [String: NSImage] = [:]

    static func image(_ id: String) -> NSImage? {
        if let c = cache[id] { return c }
        guard let url = Bundle.main.url(forResource: id, withExtension: "jpg", subdirectory: "Gifting"), let img = NSImage(contentsOf: url) else { return nil }
        cache[id] = img
        return img
    }
}

struct GiftPhotoView: View {
    let id: String
    var body: some View {
        if let img = GiftPhoto.image(id) {
            Image(nsImage: img).resizable().scaledToFill()
        } else {
            Color.gray.opacity(0.25)
        }
    }
}

enum GiftCatalogue {
    static let items: [GiftItem] = [
        GiftItem(id: "cheese-popper", name: "Gold Cheese Popper Set", category: "Serving", price: 1000, words: ["cheese popper", "cheese labels"]),
        GiftItem(id: "ice-cream-scoop", name: "Crystal Ice Cream Scoop", category: "Serving", price: 1000, words: ["ice cream scoop", "scoop"]),
        GiftItem(id: "coconut-candle", name: "Coconut Shell Neroli Candle", category: "Candle", price: 1000, words: ["coconut candle", "coconut shell candle", "neroli candle"]),
        GiftItem(id: "botanical-diffuser", name: "Botanical Diffuser Set", category: "Fragrance", price: 1000, words: ["botanical diffuser"]),
        GiftItem(id: "mushroom-chimes", name: "Mushroom Wind Chime Set", category: "Decor", price: 1000, words: ["wind chime", "mushroom chimes", "chimes"]),
        GiftItem(id: "elephant-trunk", name: "Blue Elephant Heritage Trunk", category: "Keepsake", price: 1000, words: ["elephant trunk", "heritage trunk", "blue elephant"]),
        GiftItem(id: "peshkari-frame", name: "Peshkari Peacock Photo Frame", category: "Frame", price: 1000, words: ["peshkari frame", "peacock frame"]),
        GiftItem(id: "roman-frame", name: "Roman Black and White Frame", category: "Frame", price: 1000, words: ["roman frame", "rome frame"]),
        GiftItem(id: "royal-bee-frame", name: "Royal Bee Ivory Frame", category: "Frame", price: 1000, words: ["royal bee frame", "bee frame"]),
        GiftItem(id: "diya-gift-set", name: "Couture Charm Mini Diya Set", category: "Devotion", price: 1000, words: ["mini diya set", "couture diya", "diya set"]),
        GiftItem(id: "silk-candle-box", name: "Turquoise Silk Candle Box", category: "Candle", price: 1000, words: ["silk candle box", "turquoise candle box", "candle gift box"]),
        GiftItem(id: "mustang-frame-3", name: "Mustang 3.0 Photo Frame", category: "Frame", price: 1000, words: ["mustang 3 frame", "mustang three frame"]),
        GiftItem(id: "mustang-frame-2", name: "Mustang 2.0 Photo Frame", category: "Frame", price: 1000, words: ["mustang 2 frame", "mustang two frame", "mustang frame"]),
        GiftItem(id: "blossom-jar", name: "Silver Blossom Trinket Jar", category: "Decor", price: 1000, words: ["blossom jar", "silver blossom", "trinket jar"]),
        GiftItem(id: "crystal-trinket", name: "Crystal Trinket Box Pair", category: "Decor", price: 1000, words: ["crystal trinket", "trinket box"]),
        GiftItem(id: "dot-visage-frame", name: "Dot Visage Photo Frame", category: "Frame", price: 1000, words: ["dot visage frame", "visage frame", "dot frame"]),
        GiftItem(id: "royal-heritage", name: "Royal Heritage Gift Set", category: "Keepsake", price: 1000, words: ["royal heritage", "heritage set"]),
        GiftItem(id: "hammered-dome", name: "Hammered Metal Dessert Dome", category: "Serving", price: 1000, words: ["dessert dome", "hammered dome"]),
        GiftItem(id: "book-chest", name: "Artisan Book Chest", category: "Keepsake", price: 1500, words: ["artisan book chest", "book chest"]),
        GiftItem(id: "literary-legacy", name: "Literary Legacy Keepsake", category: "Keepsake", price: 1500, words: ["literary legacy"]),
        GiftItem(id: "neelam-tea", name: "Neelam Heritage Tea Cups", category: "Tea", price: 1500, words: ["neelam", "tea cups", "chai cups"]),
        GiftItem(id: "lumiere-essence", name: "Lumiere Essence Bottle", category: "Fragrance", price: 1500, words: ["lumiere", "essence bottle"]),
        GiftItem(id: "shubh-aarambh", name: "Shubh Aarambh Ensemble", category: "Fragrance", price: 1500, words: ["shubh aarambh", "incense box"]),
        GiftItem(id: "heritage-tray", name: "Mustang Heritage Serving Tray", category: "Serving", price: 1500, words: ["heritage tray", "mustang heritage tray"]),
        GiftItem(id: "cake-server", name: "Gold Cake Cutting Set", category: "Serving", price: 1500, words: ["cake cutting set", "cake server", "cake knife"]),
        GiftItem(id: "regal-candle-bowl", name: "Regal Candle Bowl", category: "Candle", price: 1500, words: ["regal candle bowl", "jewelled candle"]),
        GiftItem(id: "three-wick-bowl", name: "Regal Glow Three-Wick Candle", category: "Candle", price: 1500, words: ["three wick", "regal glow"]),
        GiftItem(id: "gold-centrepiece", name: "Antique Gold Centrepiece Bowl", category: "Decor", price: 1500, words: ["centrepiece bowl", "gold bowl", "potpourri bowl"]),
        GiftItem(id: "black-hibiscus", name: "Black Hibiscus Candle", category: "Candle", price: 1500, words: ["black hibiscus"]),
        GiftItem(id: "white-hibiscus", name: "White Hibiscus Candle", category: "Candle", price: 1500, words: ["white hibiscus"]),
        GiftItem(id: "harlequin-tea-box", name: "Harlequin Tea Storage Box", category: "Tea", price: 1500, words: ["harlequin", "tea storage box", "tea box"]),
        GiftItem(id: "arch-tray", name: "Arch Architectural Serving Tray", category: "Serving", price: 1500, words: ["arch tray", "architectural tray"]),
        GiftItem(id: "gita-set", name: "Bhagavad Gita Gift Set", category: "Devotion", price: 1500, words: ["bhagavad gita", "gita set", "gita"]),
        GiftItem(id: "motif-tray", name: "Mustang Horse Motif Tray", category: "Serving", price: 1500, words: ["motif tray", "horse tray"]),
        GiftItem(id: "cheese-utensils", name: "Cheese Serving Utensils", category: "Serving", price: 1500, words: ["cheese utensils", "cheese knives", "cheese set"]),
        GiftItem(id: "dome-candle", name: "Glass Dome Botanical Candle", category: "Candle", price: 1500, words: ["glass dome candle", "dome candle", "botanical candle"]),
        GiftItem(id: "envelope-chest", name: "Decorative Envelope and Tag Chest", category: "Keepsake", price: 1500, words: ["envelope chest", "tag chest", "envelope set"]),
        GiftItem(id: "marble-platter", name: "Marble Inlay Cheese Platter", category: "Serving", price: 1500, words: ["marble platter", "cheese platter"]),
        GiftItem(id: "serenade-tea", name: "Serenade Tea Collection", category: "Tea", price: 2000, words: ["serenade", "tea set", "tea collection", "teapot"]),
        GiftItem(id: "imperial-devotion", name: "Imperial Devotion Collection", category: "Devotion", price: 2000, words: ["imperial devotion", "devotion box", "pooja box"]),
        GiftItem(id: "atelier-office", name: "Atelier Office Collection", category: "Office", price: 2000, words: ["atelier office", "desk set", "office set", "desk organiser"]),
        GiftItem(id: "royal-keepsake", name: "Royal Keepsake Collection", category: "Keepsake", price: 2000, words: ["royal keepsake", "chess bookends", "bookends"]),
        GiftItem(id: "krishna-lantern", name: "Radha Krishna Glow Lantern", category: "Candle", price: 2000, words: ["radha krishna lantern", "glow lantern", "lantern"]),
        GiftItem(id: "marble-tray-set", name: "Marble Finish Tray Set", category: "Decor", price: 2000, words: ["marble tray", "marble finish tray"]),
        GiftItem(id: "triple-glow", name: "Triple Glow Candle Set", category: "Candle", price: 2000, words: ["triple glow", "candle bowls"]),
        GiftItem(id: "mustang-tea-box", name: "Mustang Horse Tea Box", category: "Tea", price: 2000, words: ["mustang tea box", "horse tea box"]),
        GiftItem(id: "blue-glass-diya", name: "Royal Blue Glass Diya Set", category: "Devotion", price: 2000, words: ["blue glass diya", "glass diya"]),
        GiftItem(id: "noorwood", name: "Noorwood Collection", category: "Decor", price: 2500, words: ["noorwood"]),
        GiftItem(id: "marble-aura", name: "Ivory Marble Aura Diyas", category: "Devotion", price: 2500, words: ["marble aura", "marble diyas", "ivory marble"]),
        GiftItem(id: "imperial-glow", name: "Imperial Glow Ensemble", category: "Decor", price: 2500, words: ["imperial glow"]),
        GiftItem(id: "woodland-elegance", name: "Woodland Elegance Ensemble", category: "Decor", price: 2500, words: ["woodland elegance", "woodland"]),
        GiftItem(id: "luna-living", name: "Luna Living Ensemble", category: "Decor", price: 2500, words: ["luna living", "luna"]),
        GiftItem(id: "monochrome-atelier", name: "Monochrome Atelier Tea Set", category: "Tea", price: 2500, words: ["monochrome atelier", "monochrome"]),
        GiftItem(id: "noor-nectar", name: "Noor and Nectar Ensemble", category: "Keepsake", price: 2500, words: ["noor and nectar", "noor nectar", "nectar"]),
        GiftItem(id: "heirloom-showcase", name: "Heirloom Showcase", category: "Keepsake", price: 2500, words: ["heirloom showcase", "heirloom"]),
        GiftItem(id: "aroma-atelier", name: "Aroma Atelier Collection", category: "Fragrance", price: 2500, words: ["aroma atelier", "aroma collection", "aroma oils"]),
        GiftItem(id: "krishna-box", name: "Radha Krishna Keepsake Box", category: "Devotion", price: 2500, words: ["radha krishna box", "krishna box", "keepsake box"]),
        GiftItem(id: "bamboo-set", name: "Bamboo Corporate Gift Set", category: "Office", price: 2500, words: ["bamboo set", "corporate set", "bamboo"]),
        GiftItem(id: "floral-atomizer", name: "Ornate Crystal Perfume Atomizer", category: "Fragrance", price: 2500, words: ["perfume atomizer", "atomizer", "crystal perfume"]),
        GiftItem(id: "rose-jar", name: "Floral Rose Ceramic Jar Pair", category: "Decor", price: 2500, words: ["rose jar", "ceramic jar", "storage jar"]),
        GiftItem(id: "wicker-hamper", name: "Tea and Treats Wicker Hamper", category: "Tea", price: 2500, words: ["wicker hamper", "tea and treats", "tea treats"]),
        GiftItem(id: "art-candle-box", name: "Architectural Art Candle Box", category: "Candle", price: 2500, words: ["art candle", "architectural candle"]),
        GiftItem(id: "tin-duo", name: "Floral Tin Duo Gift Set", category: "Keepsake", price: 2500, words: ["tin duo", "floral tin"]),
    ]

    static func item(_ id: String) -> GiftItem? {
        return items.first { $0.id == id }
    }

    static let categories: [String] = {
        var seen: [String] = []
        for i in items where !seen.contains(i.category) { seen.append(i.category) }
        return seen
    }()

    /// Spoken word or phrase to item id, longest phrase first so "candle trio" wins over "candle".
    static let wordIndex: [(word: String, id: String)] = {
        var out: [(word: String, id: String)] = []
        for i in items {
            for w in i.words { out.append((word: w, id: i.id)) }
        }
        return out.sorted { $0.word.count > $1.word.count }
    }()

    static let decorations: [GiftDecor] = [
        GiftDecor(id: "flowers", name: "Flowers", emoji: "\u{1F338}", words: ["flowers", "flower", "floral", "petals"]),
        GiftDecor(id: "stars", name: "Stars", emoji: "\u{2B50}", words: ["stars", "star", "sparkles", "sparkle"]),
        GiftDecor(id: "hearts", name: "Hearts", emoji: "\u{2764}\u{FE0F}", words: ["hearts", "heart"]),
        GiftDecor(id: "balloons", name: "Balloons", emoji: "\u{1F388}", words: ["balloons", "balloon"]),
        GiftDecor(id: "leaves", name: "Greenery", emoji: "\u{1F343}", words: ["leaves", "leaf", "greenery", "foliage"]),
        GiftDecor(id: "butterflies", name: "Butterflies", emoji: "\u{1F98B}", words: ["butterflies", "butterfly"]),
        GiftDecor(id: "confetti", name: "Confetti", emoji: "\u{1F389}", words: ["confetti", "party poppers"]),
    ]

    static func decorEmoji(_ id: String) -> String? {
        return decorations.first { $0.id == id }?.emoji
    }
}

struct GiftBox: Identifiable, Hashable {
    let id: Int
    let name: String
    let boxHex: String
    let ribbonHex: String
    let tissueHex: String
    let decor: [String]
    let items: [String]

    var price: Int {
        var sum = GiftRange.boxFee
        for i in items { sum += GiftCatalogue.item(i)?.price ?? 0 }
        return sum
    }
}

enum GiftBoxes {
    static let all: [GiftBox] = [
        GiftBox(id: 1, name: "Calm Hour", boxHex: "#7A1F3D", ribbonHex: "#D4A84A", tissueHex: "#F8E1E7", decor: ["flowers"], items: ["coconut-candle", "silk-candle-box", "botanical-diffuser"]),
        GiftBox(id: 2, name: "Velvet Whisper", boxHex: "#2B2B30", ribbonHex: "#D8AE55", tissueHex: "#F4EFE6", decor: ["stars"], items: ["mustang-tea-box", "cheese-popper"]),
        GiftBox(id: 3, name: "Golden Pause", boxHex: "#EFE4D0", ribbonHex: "#C9A24B", tissueHex: "#FBF4E6", decor: ["hearts"], items: ["diya-gift-set", "gita-set"]),
        GiftBox(id: 4, name: "Blush Bloom", boxHex: "#1F5A45", ribbonHex: "#E0B85A", tissueHex: "#DDF0E5", decor: ["leaves"], items: ["mustang-frame-3", "mustang-frame-2", "dot-visage-frame"]),
        GiftBox(id: 5, name: "Ivory Embrace", boxHex: "#C0603A", ribbonHex: "#F4E3C8", tissueHex: "#FDE6D8", decor: ["butterflies"], items: ["shubh-aarambh", "botanical-diffuser"]),
        GiftBox(id: 6, name: "Plum Reverie", boxHex: "#5B2A6B", ribbonHex: "#C27C4E", tissueHex: "#EBDDF3", decor: ["confetti"], items: ["motif-tray", "cheese-utensils"]),
        GiftBox(id: 7, name: "Teal Escape", boxHex: "#1D2F5C", ribbonHex: "#C9CED8", tissueHex: "#E3ECFA", decor: ["balloons"], items: ["atelier-office", "elephant-trunk"]),
        GiftBox(id: 8, name: "Midnight Muse", boxHex: "#2A4DB0", ribbonHex: "#E6B94F", tissueHex: "#E1EAFB", decor: ["flowers"], items: ["literary-legacy", "envelope-chest", "elephant-trunk"]),
        GiftBox(id: 9, name: "Terracotta Glow", boxHex: "#146B73", ribbonHex: "#E2B04A", tissueHex: "#DCF2F2", decor: ["stars"], items: ["marble-tray-set", "mushroom-chimes", "blossom-jar"]),
        GiftBox(id: 10, name: "Royal Cheer", boxHex: "#E9B8C2", ribbonHex: "#B76E79", tissueHex: "#FFF6F0", decor: ["hearts"], items: ["mustang-tea-box", "monochrome-atelier"]),
        GiftBox(id: 11, name: "Aroma Haven", boxHex: "#7A1F3D", ribbonHex: "#D4A84A", tissueHex: "#F8E1E7", decor: ["leaves"], items: ["coconut-candle", "silk-candle-box", "regal-candle-bowl", "botanical-diffuser"]),
        GiftBox(id: 12, name: "Sweet Surrender", boxHex: "#2B2B30", ribbonHex: "#D8AE55", tissueHex: "#F4EFE6", decor: ["butterflies"], items: ["mustang-tea-box", "monochrome-atelier"]),
        GiftBox(id: 13, name: "Garden Grace", boxHex: "#EFE4D0", ribbonHex: "#C9A24B", tissueHex: "#FBF4E6", decor: ["confetti"], items: ["diya-gift-set", "gita-set", "imperial-devotion"]),
        GiftBox(id: 14, name: "Festive Spark", boxHex: "#1F5A45", ribbonHex: "#E0B85A", tissueHex: "#DDF0E5", decor: ["balloons"], items: ["mustang-frame-3", "mustang-frame-2", "dot-visage-frame", "peshkari-frame", "roman-frame"]),
        GiftBox(id: 15, name: "Boardroom Thanks", boxHex: "#C0603A", ribbonHex: "#F4E3C8", tissueHex: "#FDE6D8", decor: ["flowers"], items: ["shubh-aarambh", "aroma-atelier", "botanical-diffuser"]),
        GiftBox(id: 16, name: "Wellness Ritual", boxHex: "#5B2A6B", ribbonHex: "#C27C4E", tissueHex: "#EBDDF3", decor: ["stars"], items: ["cheese-popper", "ice-cream-scoop", "hammered-dome", "heritage-tray", "cake-server"]),
        GiftBox(id: 17, name: "Rose and Ritual", boxHex: "#1D2F5C", ribbonHex: "#C9CED8", tissueHex: "#E3ECFA", decor: ["hearts"], items: ["atelier-office", "bamboo-set", "literary-legacy"]),
        GiftBox(id: 18, name: "Gourmet Delight", boxHex: "#2A4DB0", ribbonHex: "#E6B94F", tissueHex: "#E1EAFB", decor: ["leaves"], items: ["noor-nectar", "heirloom-showcase", "elephant-trunk"]),
        GiftBox(id: 19, name: "Little Joy", boxHex: "#146B73", ribbonHex: "#E2B04A", tissueHex: "#DCF2F2", decor: ["butterflies"], items: ["marble-tray-set", "noorwood", "mushroom-chimes", "blossom-jar"]),
        GiftBox(id: 20, name: "Warm Welcome", boxHex: "#E9B8C2", ribbonHex: "#B76E79", tissueHex: "#FFF6F0", decor: ["confetti"], items: ["mustang-tea-box", "monochrome-atelier", "wicker-hamper"]),
        GiftBox(id: 21, name: "Cedar and Silk", boxHex: "#7A1F3D", ribbonHex: "#D4A84A", tissueHex: "#F8E1E7", decor: ["balloons"], items: ["coconut-candle", "silk-candle-box", "regal-candle-bowl", "three-wick-bowl", "black-hibiscus"]),
        GiftBox(id: 22, name: "Opal Evening", boxHex: "#2B2B30", ribbonHex: "#D8AE55", tissueHex: "#F4EFE6", decor: ["flowers"], items: ["mustang-tea-box", "monochrome-atelier", "wicker-hamper"]),
        GiftBox(id: 23, name: "Saffron Dusk", boxHex: "#EFE4D0", ribbonHex: "#C9A24B", tissueHex: "#FBF4E6", decor: ["stars"], items: ["diya-gift-set", "gita-set", "imperial-devotion", "blue-glass-diya", "coconut-candle"]),
        GiftBox(id: 24, name: "Heirloom Hamper", boxHex: "#1F5A45", ribbonHex: "#E0B85A", tissueHex: "#DDF0E5", decor: ["hearts"], items: ["mustang-frame-3", "mustang-frame-2", "dot-visage-frame", "peshkari-frame", "roman-frame", "royal-bee-frame"]),
        GiftBox(id: 25, name: "Crystal Morning", boxHex: "#C0603A", ribbonHex: "#F4E3C8", tissueHex: "#FDE6D8", decor: ["leaves"], items: ["shubh-aarambh", "aroma-atelier", "floral-atomizer", "botanical-diffuser"]),
        GiftBox(id: 26, name: "Imperial Oud", boxHex: "#5B2A6B", ribbonHex: "#C27C4E", tissueHex: "#EBDDF3", decor: ["butterflies"], items: ["heritage-tray", "cake-server", "arch-tray", "motif-tray", "cheese-utensils", "cheese-popper"]),
        GiftBox(id: 27, name: "Moonlit Indulgence", boxHex: "#1D2F5C", ribbonHex: "#C9CED8", tissueHex: "#E3ECFA", decor: ["confetti"], items: ["atelier-office", "bamboo-set", "noor-nectar", "elephant-trunk"]),
        GiftBox(id: 28, name: "Grand Gratitude", boxHex: "#2A4DB0", ribbonHex: "#E6B94F", tissueHex: "#E1EAFB", decor: ["balloons"], items: ["elephant-trunk", "royal-heritage", "book-chest", "literary-legacy", "envelope-chest", "royal-keepsake"]),
        GiftBox(id: 29, name: "Signature Vybe", boxHex: "#146B73", ribbonHex: "#E2B04A", tissueHex: "#DCF2F2", decor: ["flowers"], items: ["marble-tray-set", "noorwood", "imperial-glow", "mushroom-chimes", "blossom-jar"]),
        GiftBox(id: 30, name: "The Maharaja Edit", boxHex: "#E9B8C2", ribbonHex: "#B76E79", tissueHex: "#FFF6F0", decor: ["stars"], items: ["mustang-tea-box", "monochrome-atelier", "wicker-hamper", "neelam-tea"]),
    ]

    static func box(_ id: Int) -> GiftBox {
        return all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - The gift being customised

struct GiftConfig: Codable, Equatable {
    var boxID: Int = 1
    var boxName: String = ""
    var boxHex: String = "#7A1F3D"
    var ribbonHex: String = "#D4A84A"
    var tissueHex: String = "#F8E1E7"
    var decor: [String] = []
    var items: [String] = []
    var packaging: Int = GiftRange.boxFee
    var cardStyle: String = "classic"
    var cardTo: String = ""
    var cardFrom: String = ""
    var cardMessage: String = ""
    var note: String = ""
    var quantity: Int = 1
    var customer: String = ""
    var phone: String = ""
    var address: String = ""

    init() {}

    init(box: GiftBox) {
        boxID = box.id
        boxName = box.name
        boxHex = box.boxHex
        ribbonHex = box.ribbonHex
        tissueHex = box.tissueHex
        decor = box.decor
        items = box.items
        packaging = GiftRange.boxFee
    }

    var itemsTotal: Int {
        var sum = 0
        for i in items { sum += GiftCatalogue.item(i)?.price ?? 0 }
        return sum
    }

    var extraDecor: Int { return max(0, decor.count - 1) * 200 }
    var unitPrice: Int { return packaging + itemsTotal + extraDecor }
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
}

// MARK: - State and voice

@MainActor
final class GiftingState: ObservableObject {
    @Published var config: GiftConfig {
        didSet { persist() }
    }
    @Published var view: GiftView = .closed
    @Published var unboxStep: Int = 0
    @Published var itemsShown: Int = 99
    @Published var isPlaying = false
    @Published var message: String = "Pick a box, or say what you want, like \u{201C}make it burgundy with a gold ribbon and add perfume\u{201D}."
    @Published var search: String = ""
    @Published var itemCategory: String = "All"
    @Published var maxPrice: Int = GiftRange.max
    @Published var placed: GiftOrder? = nil

    private var history: [GiftConfig] = []
    private var unboxTask: Task<Void, Never>?
    private static let key = "keydoGiftingConfig2"

    init() {
        if let data = UserDefaults.standard.data(forKey: GiftingState.key), let saved = try? JSONDecoder().decode(GiftConfig.self, from: data) {
            config = saved
        } else {
            config = GiftConfig(box: GiftBoxes.all[0])
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: GiftingState.key)
        }
    }

    var boxes: [GiftBox] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return GiftBoxes.all.filter { box in
            if box.price > maxPrice { return false }
            if q.isEmpty { return true }
            if box.name.lowercased().contains(q) { return true }
            for id in box.items {
                if let item = GiftCatalogue.item(id), item.name.lowercased().contains(q) || item.category.lowercased().contains(q) { return true }
            }
            return false
        }
    }

    func tileConfig(_ box: GiftBox) -> GiftConfig {
        return config.boxID == box.id ? config : GiftConfig(box: box)
    }

    // MARK: Changing the gift

    func pushHistory() {
        history.append(config)
        if history.count > 40 { history.removeFirst() }
    }

    func change(_ f: (inout GiftConfig) -> Void) {
        var work = config
        f(&work)
        if work != config {
            pushHistory()
            config = work
        }
    }

    func undo() {
        guard let last = history.popLast() else {
            message = "Nothing to undo."
            return
        }
        config = last
        message = "Undone. Now \(giftRupees(config.unitPrice))."
    }

    func select(_ id: Int) {
        let box = GiftBoxes.box(id)
        pushHistory()
        var fresh = GiftConfig(box: box)
        fresh.cardStyle = config.cardStyle
        fresh.cardTo = config.cardTo
        fresh.cardFrom = config.cardFrom
        fresh.cardMessage = config.cardMessage
        fresh.customer = config.customer
        fresh.phone = config.phone
        fresh.address = config.address
        fresh.quantity = config.quantity
        config = fresh
        placed = nil
        message = "Box \(box.id), \(box.name): \(giftRupees(box.price)). Say what to change."
    }

    func toggleItem(_ id: String) {
        var work = config
        var note: String? = nil
        if work.items.contains(id) {
            note = removeItem(id, from: &work)
        } else {
            note = addItem(id, to: &work)
        }
        if work != config {
            pushHistory()
            config = work
        }
        message = note ?? "Now \(giftRupees(config.unitPrice))."
    }

    /// Returns a message when the item is refused, nil when it went in.
    func addItem(_ id: String, to work: inout GiftConfig) -> String? {
        guard let item = GiftCatalogue.item(id) else { return nil }
        if work.items.contains(id) { return "\(item.name) is already inside." }
        if work.items.count >= GiftRange.slots { return "The box is full (\(GiftRange.slots) items). Remove one first." }
        var trial = work
        trial.items.append(id)
        if trial.unitPrice > GiftRange.max { return "Skipped \(item.name): that would go over \(giftRupees(GiftRange.max))." }
        work = trial
        return nil
    }

    func removeItem(_ id: String, from work: inout GiftConfig) -> String? {
        guard let item = GiftCatalogue.item(id), work.items.contains(id) else { return nil }
        var trial = work
        trial.items.removeAll { $0 == id }
        if trial.unitPrice < GiftRange.min { return "Kept \(item.name): a gift stays at \(giftRupees(GiftRange.min)) or more." }
        work = trial
        return nil
    }

    func toggleDecor(_ id: String) {
        change { c in
            if c.decor.contains(id) {
                c.decor.removeAll { $0 == id }
            } else {
                c.decor.append(id)
                if c.decor.count > 3 { c.decor.removeFirst() }
            }
        }
        message = "Now \(giftRupees(config.unitPrice))."
    }

    // MARK: Views and unboxing

    func show(_ v: GiftView) {
        stopUnbox()
        if v == .unbox {
            startUnbox()
        } else {
            withAnimation(.easeInOut(duration: 0.4)) { view = v }
        }
    }

    func stopUnbox() {
        unboxTask?.cancel()
        unboxTask = nil
        isPlaying = false
    }

    func startUnbox() {
        stopUnbox()
        view = .unbox
        unboxStep = 0
        itemsShown = 0
        isPlaying = true
        unboxTask = Task { [weak self] in
            guard let self = self else { return }
            for step in 0...6 {
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.9)) { self.unboxStep = step }
                if step == 5 {
                    let n = max(1, self.config.items.count)
                    for k in 1...n {
                        try? await Task.sleep(nanoseconds: 650_000_000)
                        if Task.isCancelled { return }
                        withAnimation(.spring()) { self.itemsShown = k }
                    }
                }
                if step == 6 { self.itemsShown = 99 }
                try? await Task.sleep(nanoseconds: 1_400_000_000)
            }
            self.isPlaying = false
        }
    }

    func caption(_ step: Int) -> String {
        switch step {
        case 0: return "Your VYBES box arrives, wrapped and ribboned."
        case 1: return "Slip off the ribbon."
        case 2: return "Lift the lid. The VYBES mark waits underneath."
        case 3: return "Tissue paper covers the surprise."
        case 4: return "The tissue parts."
        case 5: return "Each gift is revealed, one at a time."
        default: return "The card is tucked in, ready to be read."
        }
    }

    // MARK: Experience note

    var suggestedNote: String {
        var sentences: [String] = []
        sentences.append("The ribbon slips off, the lid lifts and the VYBES mark is the first thing they see.")
        var cats: [String] = []
        for id in config.items {
            if let item = GiftCatalogue.item(id), !cats.contains(item.category) { cats.append(item.category) }
        }
        if cats.contains("Fragrance") || cats.contains("Candle") { sentences.append("Light a candle or open a fragrance and the room slowly fills with calm.") }
        if cats.contains("Tea") || cats.contains("Serving") { sentences.append("Pour, serve and share: the set turns a quiet moment into an occasion.") }
        if cats.contains("Devotion") { sentences.append("A few diyas and a prayer corner make the festival feel complete.") }
        if cats.contains("Frame") || cats.contains("Keepsake") || cats.contains("Decor") { sentences.append("Keepsakes for a shelf or console stay long after the box is gone.") }
        if cats.contains("Office") { sentences.append("A desk set that makes everyday work feel a little more special.") }
        sentences.append("The card makes it personal before anything else is opened.")
        return sentences.joined(separator: " ")
    }

    var experienceNote: String {
        return config.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? suggestedNote : config.note
    }

    // MARK: Order

    private var ordersDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KeyDo/GiftOrders", isDirectory: true)
    }

    func orderSummary(id: String) -> String {
        var lines: [String] = ["VYBES \u{2014} Gift the Vibe", "Order \(id)", ""]
        lines.append("Box \(config.boxID): \(config.boxName)")
        for itemID in config.items {
            if let item = GiftCatalogue.item(itemID) { lines.append("\u{2022} \(item.name): \(giftRupees(item.price))") }
        }
        let decorNames = config.decor.compactMap { d in GiftCatalogue.decorations.first { $0.id == d }?.name }
        if !decorNames.isEmpty { lines.append("Decoration: " + decorNames.joined(separator: ", ")) }
        lines.append("Box colour \(config.boxHex), ribbon \(config.ribbonHex), tissue \(config.tissueHex)")
        lines.append("")
        lines.append("Card to: \(config.cardTo.isEmpty ? "-" : config.cardTo)  from: \(config.cardFrom.isEmpty ? "-" : config.cardFrom)")
        if !config.cardMessage.isEmpty { lines.append("Card message: \(config.cardMessage)") }
        lines.append("Experience note: \(experienceNote)")
        lines.append("")
        lines.append("Quantity: \(config.quantity) x \(giftRupees(config.unitPrice))")
        lines.append("Total: \(giftRupees(config.total))")
        lines.append("Deliver to: \(config.customer), \(config.phone)")
        lines.append(config.address)
        return lines.joined(separator: "\n")
    }

    func placeOrder() {
        var missing: [String] = []
        if config.customer.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("your name") }
        if config.phone.filter({ $0.isNumber }).count < 10 { missing.append("a 10-digit phone number") }
        if config.address.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("the delivery address") }
        if !missing.isEmpty {
            message = "To place the order I still need " + missing.joined(separator: ", ") + ". Say, for example, \u{201C}order name Asha, phone 9876543210, address 12 MG Road\u{201D}."
            return
        }
        guard config.unitPrice >= GiftRange.min, config.unitPrice <= GiftRange.max else {
            message = "A gift must be between \(giftRupees(GiftRange.min)) and \(giftRupees(GiftRange.max))."
            return
        }
        let fm = FileManager.default
        try? fm.createDirectory(at: ordersDirectory, withIntermediateDirectories: true)
        let count = ((try? fm.contentsOfDirectory(atPath: ordersDirectory.path)) ?? []).filter { $0.hasSuffix(".json") }.count
        let stamp = DateFormatter()
        stamp.dateFormat = "yyMMdd"
        let id = "VYB-" + stamp.string(from: Date()) + "-" + String(format: "%03d", count + 1)
        let summary = orderSummary(id: id)
        let order = GiftOrder(id: id, date: Date(), config: config, total: config.total, summary: summary)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(order) {
            try? data.write(to: ordersDirectory.appendingPathComponent(id + ".json"))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        placed = order
        message = "Order \(id) saved on this Mac and the summary is copied. Send it on WhatsApp or email below."
    }

    func shareWhatsApp() {
        guard let order = placed else { return }
        let enc = order.summary.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        if let url = URL(string: "https://wa.me/?text=" + enc) { NSWorkspace.shared.open(url) }
    }

    func shareEmail() {
        guard let order = placed else { return }
        let body = order.summary.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let subject = ("VYBES gift order " + order.id).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        if let url = URL(string: "mailto:?subject=\(subject)&body=\(body)") { NSWorkspace.shared.open(url) }
    }

    func savePicture() {
        let sheet = HStack(spacing: 14) {
            GiftLidTop(config: config).frame(width: 540, height: 360)
            GiftBoxInside(config: config, tissueOpen: 1, itemsShown: 99, showCard: true, labels: true).frame(width: 540, height: 360)
            GiftCardArt(config: config, compact: false).frame(width: 400, height: 276)
        }
        .padding(24)
        .background(Color(wishHex: GiftColor.shade(config.tissueHex, 1.1)))
        guard let image = WishExport.image(of: sheet, scale: 2), let data = WishExport.pngData(from: image) else {
            message = "Could not draw the picture."
            return
        }
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let name = "VYBES-" + config.boxName.replacingOccurrences(of: " ", with: "-") + ".png"
        do {
            try data.write(to: desktop.appendingPathComponent(name))
            message = "Saved \(name) on your Desktop."
        } catch {
            message = "Could not save the picture: \(error.localizedDescription)"
        }
    }

    // MARK: Spoken commands

    private struct Field {
        var kind: String
        var value: String
    }

    private let kinds: [(String, [String])] = [
        ("Candle", ["candle", "candles"]), ("Frame", ["frame", "frames", "photo frame", "photo frames"]), ("Tea", ["tea", "chai"]),
        ("Serving", ["tray", "trays", "platter", "serving"]), ("Devotion", ["diya", "diyas", "pooja", "devotion"]),
        ("Fragrance", ["perfume", "perfumes", "fragrance", "diffuser", "diffusers", "aroma", "incense"]), ("Office", ["office", "desk"]),
        ("Keepsake", ["keepsake", "keepsakes", "chest"]), ("Decor", ["decor", "showpiece", "showpieces"]),
    ]

    private let markers: [(String, String)] = [
        ("card to ", "to"), ("card for ", "to"), ("card from ", "from"), ("card message ", "msg"), ("message ", "msg"),
        ("gift note ", "note"), ("experience note ", "note"), ("note ", "note"),
        ("order name ", "cust"), ("customer ", "cust"), ("my name is ", "cust"),
        ("address ", "addr"), ("deliver to ", "addr"), ("deliver at ", "addr"), ("ship to ", "addr"),
        ("phone ", "phone"), ("mobile ", "phone"),
    ]

    private func capture(_ pattern: String, in s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        var out: [String] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            out.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return out
    }

    private func clean(_ s: String) -> String {
        var t = s.lowercased()
        t = t.replacingOccurrences(of: "&", with: " and ")
        for ch in [",", ".", ";", ":", "!", "?", "\u{201C}", "\u{201D}", "\""] { t = t.replacingOccurrences(of: ch, with: " ") }
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private func has(_ text: String, _ words: [String]) -> Bool {
        for w in words where text.contains(" " + w + " ") { return true }
        return false
    }

    private func splitFields(_ original: String) -> (head: String, fields: [Field], orderWord: Bool) {
        var hits: [(range: Range<String.Index>, kind: String)] = []
        for (marker, kind) in markers {
            if let r = original.range(of: marker, options: .caseInsensitive) {
                if r.lowerBound > original.startIndex {
                    let before = original[original.index(before: r.lowerBound)]
                    if !(before == " " || before == "," || before == ".") { continue }
                }
                hits.append((range: r, kind: kind))
            }
        }
        hits.sort { $0.range.lowerBound < $1.range.lowerBound }
        var kept: [(range: Range<String.Index>, kind: String)] = []
        for h in hits {
            if let last = kept.last, h.range.lowerBound < last.range.upperBound { continue }
            kept.append(h)
        }
        guard let first = kept.first else { return (original, [], false) }
        var fields: [Field] = []
        var orderWord = false
        for (i, h) in kept.enumerated() {
            let end = i + 1 < kept.count ? kept[i + 1].range.lowerBound : original.endIndex
            var value = String(original[h.range.upperBound..<end])
            if let m = capture("\\s+(?:and\\s+)?(?:please\\s+)?(?:place|confirm)\\s+(?:the\\s+|my\\s+)?order.*$", in: value) {
                value = value.replacingOccurrences(of: m[0], with: "")
                orderWord = true
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:\u{201C}\u{201D}\""))
            if value.lowercased().hasSuffix(" and") { value = String(value.dropLast(4)) }
            if h.kind == "phone" { value = value.filter { $0.isNumber } }
            if !value.isEmpty { fields.append(Field(kind: h.kind, value: value)) }
        }
        return (String(original[..<first.range.lowerBound]), fields, orderWord)
    }

    private func nounTarget(_ w: String) -> String? {
        switch w {
        case "ribbon", "ribbons", "bow", "bows": return "ribbon"
        case "tissue", "wrap", "wrapping", "paper", "filler", "shredded", "padding": return "tissue"
        case "card", "cards": return "card"
        case "box", "boxes", "gift", "hamper", "lid", "outside", "packaging": return "box"
        default: return nil
        }
    }

    private func colourTarget(_ tokens: [String], start: Int, len: Int) -> String {
        let fillers: Set<String> = ["colour", "color", "coloured", "colored", "shade", "tone"]
        var j = start + len
        while j < tokens.count && fillers.contains(tokens[j]) { j += 1 }
        if j < tokens.count, let t = nounTarget(tokens[j]) { return t }
        let skip: Set<String> = ["in", "to", "as", "is", "into", "a", "the", "of", "with", "for", "use", "make", "set", "change", "be", "should"]
        var k = start - 1
        while k >= 0 && k >= start - 4 && skip.contains(tokens[k]) { k -= 1 }
        if k >= 0, let t = nounTarget(tokens[k]) { return t }
        return "box"
    }

    private func applyColours(_ text: String, _ work: inout GiftConfig, _ notes: inout [String]) -> (rest: String, changed: Bool) {
        var tokens = text.split(separator: " ").map { String($0) }
        var changed = false
        var i = 0
        while i < tokens.count {
            var hex: String? = nil
            var len = 1
            if i + 1 < tokens.count, let h = GiftColor.names[tokens[i] + " " + tokens[i + 1]] {
                hex = h
                len = 2
            } else if let h = GiftColor.names[tokens[i]] {
                hex = h
            }
            guard let value = hex else {
                i += 1
                continue
            }
            let target = colourTarget(tokens, start: i, len: len)
            if target == "ribbon" {
                work.ribbonHex = value
                notes.append("Ribbon colour changed.")
            } else if target == "tissue" {
                work.tissueHex = value
                notes.append("Tissue colour changed.")
            } else if target == "box" {
                work.boxHex = value
                notes.append("Box colour changed.")
            }
            changed = true
            for k in i..<(i + len) { tokens[k] = "" }
            i += len
        }
        return (tokens.filter { !$0.isEmpty }.joined(separator: " "), changed)
    }

    private func findItems(in s: String) -> (ids: [String], rest: String) {
        var c = " " + s + " "
        var ids: [String] = []
        for entry in GiftCatalogue.wordIndex {
            let needle = " " + entry.word + " "
            if c.contains(needle) {
                if !ids.contains(entry.id) { ids.append(entry.id) }
                c = c.replacingOccurrences(of: needle, with: "  ")
            }
        }
        return (ids, c)
    }

    private func clauses(_ text: String) -> [String] {
        var t = " " + text + " "
        for w in [" and ", " then ", " also ", " plus ", " with "] { t = t.replacingOccurrences(of: w, with: " | ") }
        return t.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// One entry point for a spoken or typed sentence. It can change many things at once.
    func handle(_ raw: String) {
        let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return }
        let split = splitFields(original)
        var text = " " + clean(split.head) + " "
        var work = config
        var notes: [String] = []
        var changed = false
        var wantOrder = split.orderWord
        var nextView: GiftView? = nil

        if has(text, ["undo", "revert"]) {
            undo()
            return
        }
        if has(text, ["stop"]) {
            stopUnbox()
            message = "Stopped."
            return
        }
        if has(text, ["reset", "start over"]) {
            work = GiftConfig(box: GiftBoxes.box(work.boxID))
            notes.append("Back to the original box.")
            changed = true
        }

        // Which box
        var chosen: Int? = nil
        if let m = capture("\\b(?:box|gift|hamper|number|no)\\s*(\\d{1,2})\\b", in: text), let n = Int(m[1]), n >= 1, n <= GiftBoxes.all.count, !has(text, ["quantity", "qty"]) {
            chosen = n
            text = text.replacingOccurrences(of: m[0], with: " ")
        }
        if chosen == nil {
            for box in GiftBoxes.all.sorted(by: { $0.name.count > $1.name.count }) {
                let name = box.name.lowercased()
                if text.contains(" " + name + " ") {
                    chosen = box.id
                    text = text.replacingOccurrences(of: name, with: " ")
                    break
                }
            }
        }
        if chosen == nil {
            if has(text, ["next box", "next gift", "next one", "next", "more premium", "more expensive"]) {
                chosen = min(GiftBoxes.all.count, work.boxID + 1)
            } else if has(text, ["previous box", "previous gift", "previous one", "previous", "cheaper", "less expensive"]) {
                chosen = max(1, work.boxID - 1)
            }
            if chosen != nil { text = " " + text.replacingOccurrences(of: "next", with: " ").replacingOccurrences(of: "previous", with: " ") + " " }
        }
        if let id = chosen {
            var fresh = GiftConfig(box: GiftBoxes.box(id))
            fresh.cardStyle = work.cardStyle
            fresh.cardTo = work.cardTo
            fresh.cardFrom = work.cardFrom
            fresh.cardMessage = work.cardMessage
            fresh.customer = work.customer
            fresh.phone = work.phone
            fresh.address = work.address
            fresh.quantity = work.quantity
            work = fresh
            notes.append("Box \(id), \(work.boxName).")
            changed = true
            placed = nil
        }

        // Filtering the catalogue
        if has(text, ["show all", "all boxes", "clear filter", "reset filter"]) {
            search = ""
            maxPrice = GiftRange.max
            itemCategory = "All"
            notes.append("Showing all boxes and items.")
        }
        if has(text, ["show", "see", "browse", "list"]) {
            for (kind, words) in kinds where has(text, words) {
                itemCategory = kind
                notes.append("Showing \(kind.lowercased()) items.")
                var t = text
                for w in words { t = t.replacingOccurrences(of: " " + w + " ", with: "  ") }
                text = t
            }
        }
        if let m = capture("(?:under|below|within|upto|up to|budget|less than)\\s*(\\d+)\\s*(k|thousand)?", in: text), var n = Int(m[1]) {
            if !m[2].isEmpty || n < 100 { n *= 1000 }
            maxPrice = min(GiftRange.max, max(GiftRange.min, n))
            notes.append("Showing boxes up to \(giftRupees(maxPrice)).")
            text = text.replacingOccurrences(of: m[0], with: " ")
        }
        if let m = capture("(?:find|search|filter|boxes with|show boxes with)\\s+([a-z ]+)", in: text) {
            search = m[1].trimmingCharacters(in: .whitespaces)
            notes.append("Showing boxes matching \u{201C}\(search)\u{201D}.")
            text = text.replacingOccurrences(of: m[0], with: " ")
        }

        // Quantity
        if let m = capture("(?:quantity|qty)\\s*(\\d{1,3})", in: text) ?? capture("(\\d{1,3})\\s*(?:boxes|gifts|copies|pieces)", in: text) {
            if let n = Int(m[1]), n >= 1, n <= 500 {
                work.quantity = n
                notes.append("Quantity \(n).")
                changed = true
            }
            text = text.replacingOccurrences(of: m[0], with: " ")
        }

        // Card style
        for style in ["classic", "modern", "festive", "dark"] where has(text, [style + " card", "card " + style, style + " style"]) {
            work.cardStyle = style
            notes.append("Card style: \(style).")
            changed = true
        }

        // Views
        if has(text, ["unbox", "unboxing", "unwrap", "play", "replay"]) {
            nextView = .unbox
        } else if has(text, ["show card", "show the card", "see card", "see the card", "card view"]) {
            nextView = .card
        } else if has(text, ["inside", "open the box", "open it", "open box", "show items", "see items", "show what is inside"]) {
            nextView = .inside
        } else if has(text, ["closed", "close", "close the box", "wrap it", "outside", "front"]) {
            nextView = .closed
        }

        // Order intent
        if has(text, ["order", "checkout", "buy", "confirm"]) { wantOrder = true }

        // Colours
        let coloured = applyColours(text, &work, &notes)
        text = " " + coloured.rest + " "
        if coloured.changed { changed = true }

        // Replace one item with another
        if let m = capture("(?:replace|swap|change)\\s+(.+?)\\s+(?:with|for|to)\\s+(.+)", in: text) {
            let out = findItems(in: m[1]).ids
            let into = findItems(in: m[2]).ids
            if !out.isEmpty && !into.isEmpty {
                var trial = work
                trial.items.removeAll { out.contains($0) }
                var refusal: String? = nil
                for id in into where refusal == nil { refusal = addItem(id, to: &trial) }
                if refusal == nil && trial.unitPrice >= GiftRange.min && trial.unitPrice <= GiftRange.max {
                    work = trial
                    notes.append("Swapped the items.")
                    changed = true
                } else {
                    notes.append(refusal ?? "That swap would leave the \(giftRupees(GiftRange.min))\u{2013}\(giftRupees(GiftRange.max)) range.")
                }
                text = text.replacingOccurrences(of: m[0], with: " ")
            }
        }

        // Items and decorations, clause by clause
        let removeWords = ["remove", "without", "take out", "delete", "drop", "no", "skip", "less", "minus"]
        let addWords = ["add", "put", "include", "place", "want", "give", "more", "need", "plus", "insert", "keep"]
        var mode = "add"
        for clause in clauses(text) {
            let c = " " + clause + " "
            if has(c, removeWords) {
                mode = "remove"
            } else if has(c, addWords) {
                mode = "add"
            }
            if mode == "remove" && has(c, ["decoration", "decorations", "decor", "decorated", "plain"]) {
                if !work.decor.isEmpty {
                    work.decor = []
                    notes.append("Decorations removed.")
                    changed = true
                }
            }
            var rest = c
            for d in GiftCatalogue.decorations {
                for w in d.words where rest.contains(" " + w + " ") {
                    rest = rest.replacingOccurrences(of: " " + w + " ", with: "  ")
                    if mode == "remove" {
                        if work.decor.contains(d.id) {
                            work.decor.removeAll { $0 == d.id }
                            notes.append("\(d.name) removed.")
                            changed = true
                        }
                    } else if !work.decor.contains(d.id) {
                        work.decor.append(d.id)
                        if work.decor.count > 3 { work.decor.removeFirst() }
                        notes.append("\(d.name) on the box.")
                        changed = true
                    }
                }
            }
            let foundIDs = findItems(in: rest).ids
            if foundIDs.isEmpty {
                for (kind, words) in kinds where has(rest, words) {
                    if mode == "remove" {
                        for owned in work.items where GiftCatalogue.item(owned)?.category == kind {
                            if removeItem(owned, from: &work) == nil {
                                notes.append("\(GiftCatalogue.item(owned)?.name ?? owned) removed.")
                                changed = true
                            }
                        }
                    } else {
                        let options = GiftCatalogue.items.filter { $0.category == kind && !work.items.contains($0.id) }.sorted { $0.price < $1.price }
                        var added = false
                        for o in options where !added {
                            if addItem(o.id, to: &work) == nil {
                                notes.append("\(o.name) added.")
                                changed = true
                                added = true
                            }
                        }
                        if !added { notes.append("No \(kind.lowercased()) item fits right now.") }
                    }
                }
            }
            for id in foundIDs {
                let name = GiftCatalogue.item(id)?.name ?? id
                if mode == "remove" {
                    if work.items.contains(id) {
                        if let refusal = removeItem(id, from: &work) {
                            notes.append(refusal)
                        } else {
                            notes.append("\(name) removed.")
                            changed = true
                        }
                    }
                } else if let refusal = addItem(id, to: &work) {
                    notes.append(refusal)
                } else {
                    notes.append("\(name) added.")
                    changed = true
                }
            }
        }

        // Card text, note, order details
        for f in split.fields {
            switch f.kind {
            case "to": work.cardTo = f.value; notes.append("Card is for \(f.value).")
            case "from": work.cardFrom = f.value; notes.append("Card is from \(f.value).")
            case "msg": work.cardMessage = f.value; notes.append("Card message set.")
            case "note": work.note = f.value; notes.append("Gift experience note set.")
            case "cust": work.customer = f.value; notes.append("Order name \(f.value).")
            case "addr": work.address = f.value; notes.append("Delivery address set.")
            default: work.phone = f.value; notes.append("Phone set.")
            }
            changed = true
        }

        if work != config {
            pushHistory()
            config = work
        }
        if let v = nextView {
            show(v)
        } else if changed && view == .card && !split.fields.contains(where: { $0.kind == "msg" || $0.kind == "to" || $0.kind == "from" }) {
            show(.inside)
        }
        if wantOrder {
            placeOrder()
            if let first = notes.first, placed == nil { message = first + " " + message }
            return
        }
        if notes.isEmpty && nextView == nil {
            message = "I did not catch a change. Try \u{201C}make it navy with a silver ribbon\u{201D}, \u{201C}add chocolates and a candle\u{201D} or \u{201C}show unboxing\u{201D}."
        } else {
            let price = changed ? " Now \(giftRupees(config.unitPrice))." : ""
            message = (notes.joined(separator: " ") + price).trimmingCharacters(in: .whitespaces)
        }
    }
}

// MARK: - Drawing: the lid seen from above

/// The box is always the same landscape size, 3 : 2.
private let giftAspect: CGFloat = 1.5

struct GiftLidTop: View {
    let config: GiftConfig
    var lift: CGFloat = 0
    var ribbonOn: Bool = true

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height * giftAspect)
            let h = w / giftAspect
            ZStack {
                lid(w, h)
            }
            .frame(width: w, height: h)
            .scaleEffect(1 + lift * 0.18)
            .offset(y: -lift * h * 0.08)
            .opacity(1 - Double(lift))
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func lid(_ w: CGFloat, _ h: CGFloat) -> some View {
        let top = Color(wishHex: GiftColor.shade(config.boxHex, 1.12))
        let bottom = Color(wishHex: GiftColor.shade(config.boxHex, 0.82))
        let gold = Color(wishHex: config.ribbonHex)
        return ZStack {
            RoundedRectangle(cornerRadius: h * 0.04)
                .fill(LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Color.black.opacity(0.35), radius: h * 0.05, x: 0, y: h * 0.03)
            RoundedRectangle(cornerRadius: h * 0.04).stroke(gold.opacity(0.9), lineWidth: max(1, h * 0.010)).padding(h * 0.02)
            RoundedRectangle(cornerRadius: h * 0.03)
                .stroke(gold.opacity(0.6), style: StrokeStyle(lineWidth: max(1, h * 0.005), dash: [h * 0.02, h * 0.012]))
                .padding(h * 0.05)
            bands(w, h, gold)
            studs(w, h, gold)
            plate(w, h, gold)
            decorations(w, h)
        }
        .frame(width: w, height: h)
    }

    private func bands(_ w: CGFloat, _ h: CGFloat, _ gold: Color) -> some View {
        let dark = Color(wishHex: GiftColor.shade(config.ribbonHex, 0.78))
        return ZStack {
            Rectangle().fill(LinearGradient(colors: [dark, gold, dark], startPoint: .leading, endPoint: .trailing)).frame(width: w * 0.07, height: h)
            Rectangle().fill(LinearGradient(colors: [dark, gold, dark], startPoint: .top, endPoint: .bottom)).frame(width: w, height: h * 0.11)
        }
        .opacity(ribbonOn ? 1 : 0)
        .mask(RoundedRectangle(cornerRadius: h * 0.04))
    }

    private func studs(_ w: CGFloat, _ h: CGFloat, _ gold: Color) -> some View {
        let r = h * 0.022
        let xs: [CGFloat] = [-1, 1, -1, 1]
        let ys: [CGFloat] = [-1, -1, 1, 1]
        return ZStack {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.9), gold, Color(wishHex: GiftColor.shade(config.ribbonHex, 0.7))], center: .topLeading, startRadius: 0, endRadius: r * 1.6))
                    .frame(width: r * 2, height: r * 2)
                    .offset(x: xs[i] * (w / 2 - h * 0.085), y: ys[i] * (h / 2 - h * 0.085))
            }
        }
    }

    private func plate(_ w: CGFloat, _ h: CGFloat, _ gold: Color) -> some View {
        let pw = w * 0.34
        let ph = pw / 1.57
        return RoundedRectangle(cornerRadius: h * 0.02)
            .fill(Color(wishHex: "#FAF4F0"))
            .frame(width: pw, height: ph)
            .overlay(VybesLogoView().padding(ph * 0.04))
            .overlay(RoundedRectangle(cornerRadius: h * 0.02).stroke(gold, lineWidth: max(1, h * 0.008)))
            .shadow(color: Color.black.opacity(0.3), radius: h * 0.02, x: 0, y: h * 0.01)
    }

    private func decorations(_ w: CGFloat, _ h: CGFloat) -> some View {
        let symbols = config.decor.compactMap { GiftCatalogue.decorEmoji($0) }
        let slots: [(CGFloat, CGFloat)] = [(-0.30, -0.26), (0.30, -0.26), (-0.30, 0.26), (0.30, 0.26), (-0.40, 0.0), (0.40, 0.0)]
        return ZStack {
            if !symbols.isEmpty {
                ForEach(0..<slots.count, id: \.self) { i in
                    Text(symbols[i % symbols.count])
                        .font(.system(size: h * 0.12))
                        .shadow(color: Color.black.opacity(0.25), radius: h * 0.01, x: 0, y: h * 0.006)
                        .offset(x: w * slots[i].0, y: h * slots[i].1)
                }
            }
        }
    }
}

// MARK: - Drawing: the open box seen from above, products laid out inside

struct GiftBoxInside: View {
    let config: GiftConfig
    var tissueOpen: CGFloat = 1
    var itemsShown: Int = 99
    var showCard: Bool = true
    var labels: Bool = true

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height * giftAspect)
            let h = w / giftAspect
            ZStack {
                shell(w, h)
                strip(w, h)
                cells(w, h)
                flaps(w, h)
            }
            .frame(width: w, height: h)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func shell(_ w: CGFloat, _ h: CGFloat) -> some View {
        let gold = Color(wishHex: config.ribbonHex)
        return ZStack {
            RoundedRectangle(cornerRadius: h * 0.04)
                .fill(LinearGradient(colors: [Color(wishHex: GiftColor.shade(config.boxHex, 1.1)), Color(wishHex: GiftColor.shade(config.boxHex, 0.8))], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color.black.opacity(0.35), radius: h * 0.05, x: 0, y: h * 0.03)
            RoundedRectangle(cornerRadius: h * 0.03)
                .fill(LinearGradient(colors: [Color(wishHex: GiftColor.shade(config.tissueHex, 1.1)), Color(wishHex: GiftColor.shade(config.tissueHex, 0.92))], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(h * 0.03)
            RoundedRectangle(cornerRadius: h * 0.03).stroke(gold.opacity(0.85), lineWidth: max(1, h * 0.007)).padding(h * 0.03)
        }
    }

    /// The top band: VYBES plate in the middle, the card tucked in at the right.
    private func strip(_ w: CGFloat, _ h: CGFloat) -> some View {
        let gold = Color(wishHex: config.ribbonHex)
        let ph = h * 0.115
        return ZStack {
            RoundedRectangle(cornerRadius: h * 0.015)
                .fill(Color(wishHex: "#FAF4F0"))
                .frame(width: ph * 1.57, height: ph)
                .overlay(VybesLogoView().padding(ph * 0.04))
                .overlay(RoundedRectangle(cornerRadius: h * 0.015).stroke(gold, lineWidth: max(1, h * 0.006)))
                .shadow(color: Color.black.opacity(0.2), radius: h * 0.01, x: 0, y: h * 0.005)
            GiftCardArt(config: config, compact: true)
                .frame(width: h * 0.17, height: h * 0.115)
                .rotationEffect(.degrees(4))
                .offset(x: w * 0.30 + (showCard ? 0 : w * 0.4))
                .opacity(showCard ? 1 : 0)
        }
        .position(x: w / 2, y: h * 0.115)
    }

    private func cells(_ w: CGFloat, _ h: CGFloat) -> some View {
        let gap = w * 0.018
        let cw = (w * 0.90 - gap * 2) / 3
        let ch = (h * 0.70 - gap) / 2
        return ZStack {
            ForEach(0..<GiftRange.slots, id: \.self) { i in
                cell(i, cw, ch, h)
                    .position(x: w * 0.05 + cw / 2 + CGFloat(i % 3) * (cw + gap), y: h * 0.23 + ch / 2 + CGFloat(i / 3) * (ch + gap))
            }
        }
    }

    @ViewBuilder
    private func cell(_ i: Int, _ cw: CGFloat, _ ch: CGFloat, _ h: CGFloat) -> some View {
        if i < config.items.count, i < itemsShown, let item = GiftCatalogue.item(config.items[i]) {
            ZStack(alignment: .bottom) {
                GiftPhotoView(id: item.id).frame(width: cw, height: ch).clipped()
                if labels {
                    Text(item.name)
                        .font(.system(size: max(7, h * 0.034), weight: .semibold, design: .serif))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: cw, height: h * 0.07)
                        .background(Color.black.opacity(0.55))
                }
            }
            .frame(width: cw, height: ch)
            .clipShape(RoundedRectangle(cornerRadius: h * 0.02))
            .overlay(RoundedRectangle(cornerRadius: h * 0.02).stroke(Color(wishHex: config.ribbonHex), lineWidth: max(1, h * 0.006)))
            .shadow(color: Color.black.opacity(0.3), radius: h * 0.015, x: 0, y: h * 0.008)
            .transition(.scale.combined(with: .opacity))
        } else {
            RoundedRectangle(cornerRadius: h * 0.02)
                .stroke(Color.black.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: cw, height: ch)
        }
    }

    private func flaps(_ w: CGFloat, _ h: CGFloat) -> some View {
        let tissue = Color(wishHex: config.tissueHex)
        let open = Double(tissueOpen)
        let rw = w * 0.45
        let rh = h * 0.72
        return ZStack {
            Rectangle().fill(tissue).frame(width: rw, height: rh)
                .rotationEffect(.degrees(-open * 14))
                .offset(x: -rw / 2 - CGFloat(open) * w * 0.35)
            Rectangle().fill(tissue.opacity(0.94)).frame(width: rw, height: rh)
                .rotationEffect(.degrees(open * 14))
                .offset(x: rw / 2 + CGFloat(open) * w * 0.35)
        }
        .opacity(1 - open * 0.95)
        .position(x: w / 2, y: h * 0.23 + rh / 2)
        .allowsHitTesting(false)
    }
}

// MARK: - Drawing: the card

struct GiftCardArt: View {
    let config: GiftConfig
    var compact: Bool = false

    private var colors: (bg: Color, ink: Color, accent: Color) {
        switch config.cardStyle {
        case "modern": return (Color.white, Color(wishHex: "#1E1E22"), Color(wishHex: config.boxHex))
        case "festive": return (Color(wishHex: "#FFE9C7"), Color(wishHex: "#5A2A0A"), Color(wishHex: "#E67E00"))
        case "dark": return (Color(wishHex: "#1F1B2E"), Color(wishHex: "#F6EBD0"), Color(wishHex: "#D4A84A"))
        default: return (Color(wishHex: "#FBF4E6"), Color(wishHex: "#3A2A20"), Color(wishHex: config.ribbonHex))
        }
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let c = colors
            ZStack {
                RoundedRectangle(cornerRadius: h * 0.05).fill(c.bg)
                RoundedRectangle(cornerRadius: h * 0.05).stroke(c.accent, lineWidth: max(1, h * 0.012)).padding(h * 0.025)
                VStack(spacing: h * 0.04) {
                    VybesLogoView().frame(height: h * (compact ? 0.5 : 0.26))
                    if !compact { message(h, c.ink) }
                }
                .padding(h * 0.08)
            }
            .shadow(color: Color.black.opacity(0.18), radius: h * 0.03, x: 0, y: h * 0.01)
        }
    }

    private func message(_ h: CGFloat, _ ink: Color) -> some View {
        let to = config.cardTo.isEmpty ? "Someone special" : config.cardTo
        let from = config.cardFrom.isEmpty ? "With love" : config.cardFrom
        let text = config.cardMessage.isEmpty ? "Wishing you joy, today and always." : config.cardMessage
        return VStack(spacing: h * 0.04) {
            Text("To \(to)").font(.system(size: h * 0.07, weight: .semibold, design: .serif)).foregroundStyle(ink)
            Text(text)
                .font(.system(size: h * 0.062, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .minimumScaleFactor(0.6)
                .foregroundStyle(ink)
            Text(from).font(.system(size: h * 0.062, design: .serif)).foregroundStyle(ink.opacity(0.8))
        }
    }
}

// MARK: - Stage

struct GiftStage: View {
    @ObservedObject var state: GiftingState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(RadialGradient(colors: [Color(wishHex: "#F7F1E8"), Color(wishHex: "#D9CDBB")], center: .center, startRadius: 20, endRadius: 360))
            content.padding(18)
        }
        .animation(.easeInOut(duration: 0.5), value: state.unboxStep)
    }

    @ViewBuilder
    private var content: some View {
        switch state.view {
        case .closed:
            GiftLidTop(config: state.config, lift: 0, ribbonOn: true)
        case .inside:
            GiftBoxInside(config: state.config, tissueOpen: 1, itemsShown: 99, showCard: true, labels: true)
        case .card:
            GiftCardArt(config: state.config, compact: false).aspectRatio(1.45, contentMode: .fit).padding(8)
        case .unbox:
            unbox
        }
    }

    @ViewBuilder
    private var unbox: some View {
        if state.unboxStep <= 1 {
            GiftLidTop(config: state.config, lift: 0, ribbonOn: state.unboxStep == 0).transition(.opacity)
        } else if state.unboxStep == 2 {
            ZStack {
                GiftBoxInside(config: state.config, tissueOpen: 0, itemsShown: 0, showCard: false, labels: true)
                GiftLidTop(config: state.config, lift: 1, ribbonOn: false)
            }
            .transition(.opacity)
        } else {
            GiftBoxInside(config: state.config, tissueOpen: state.unboxStep >= 4 ? 1 : 0,
                          itemsShown: state.unboxStep >= 6 ? 99 : state.itemsShown, showCard: state.unboxStep >= 6, labels: true)
                .transition(.opacity)
        }
    }
}

// MARK: - The Gifting page

struct GiftingView: View {
    @ObservedObject var state: GiftingState

    var body: some View {
        HStack(spacing: 0) {
            catalogue.frame(minWidth: 320)
            Divider().overlay(WishTheme.line)
            detail.frame(minWidth: 430, idealWidth: 480, maxWidth: 540)
        }
        .background(WishTheme.page)
    }

    // MARK: Catalogue of 30 boxes

    private var catalogue: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("VYBES gift boxes").font(.system(size: 20, weight: .bold, design: .serif))
                    Text("\(GiftBoxes.all.count) boxes, \(giftRupees(GiftRange.min)) to \(giftRupees(GiftRange.max)). Tap one, then change it by voice.")
                        .font(.caption).foregroundStyle(WishTheme.muted)
                }
                Spacer()
                VybesLogoView().frame(width: 92, height: 58)
            }
            HStack(spacing: 8) {
                TextField("Search boxes or items, like perfume", text: $state.search).textFieldStyle(.roundedBorder)
                Picker("", selection: $state.maxPrice) {
                    Text("Any price").tag(GiftRange.max)
                    Text("Up to \u{20B9}5,000").tag(5000)
                    Text("Up to \u{20B9}7,000").tag(7000)
                }
                .labelsHidden()
                .frame(width: 130)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 250), spacing: 12)], spacing: 12) {
                    ForEach(state.boxes) { box in tile(box) }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(16)
    }

    private func tile(_ box: GiftBox) -> some View {
        let cfg = state.tileConfig(box)
        let selected = state.config.boxID == box.id
        return Button {
            state.select(box.id)
        } label: {
            VStack(spacing: 4) {
                GiftBoxInside(config: cfg, tissueOpen: 1, itemsShown: 99, showCard: true, labels: false).aspectRatio(1.5, contentMode: .fit)
                Text("\(box.id). \(box.name)").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(cfg.items.count) products").font(.system(size: 11)).foregroundStyle(WishTheme.muted)
                Text(giftRupees(cfg.unitPrice)).font(.system(size: 12, weight: .bold)).foregroundStyle(WishTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 176)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? WishTheme.accent : WishTheme.line, lineWidth: selected ? 3 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                banner
                titleRow
                Picker("", selection: Binding(get: { state.view }, set: { state.show($0) })) {
                    ForEach(GiftView.allCases, id: \.self) { v in Text(v.rawValue).tag(v) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                GiftStage(state: state).frame(height: 310)
                stageCaption
                colourSection
                decorSection
                itemsSection
                cardSection
                noteSection
                orderSection
            }
            .padding(16)
        }
    }

    private var banner: some View {
        Text(state.message)
            .font(.system(size: 12, weight: .medium))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(WishTheme.accentSoft))
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.config.boxName.isEmpty ? "Your gift" : state.config.boxName).font(.system(size: 20, weight: .bold, design: .serif))
                Text("Box \(state.config.boxID) of \(GiftBoxes.all.count) \u{00B7} \(state.config.items.count) of \(GiftRange.slots) items")
                    .font(.caption).foregroundStyle(WishTheme.muted)
            }
            Spacer()
            Text(giftRupees(state.config.unitPrice)).font(.system(size: 22, weight: .bold)).foregroundStyle(WishTheme.accent)
        }
    }

    @ViewBuilder
    private var stageCaption: some View {
        if state.view == .unbox {
            HStack {
                Text(state.caption(state.unboxStep)).font(.system(size: 12)).foregroundStyle(WishTheme.muted)
                Spacer()
                Button(state.isPlaying ? "Stop" : "Replay") {
                    if state.isPlaying { state.stopUnbox() } else { state.startUnbox() }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private func sectionTitle(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(t).font(.system(size: 14, weight: .bold))
            Text(sub).font(.caption).foregroundStyle(WishTheme.muted)
        }
    }

    // Colours

    private var colourSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Colours", "Or say \u{201C}royal blue box with a silver ribbon and ivory tissue\u{201D}.")
            swatches("Box", state.config.boxHex) { hex in state.change { $0.boxHex = hex } }
            swatches("Ribbon", state.config.ribbonHex) { hex in state.change { $0.ribbonHex = hex } }
            swatches("Tissue", state.config.tissueHex) { hex in state.change { $0.tissueHex = hex } }
        }
    }

    private func swatches(_ title: String, _ current: String, _ pick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 26), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(GiftColor.swatches, id: \.self) { hex in
                    Button { pick(hex) } label: {
                        Circle().fill(Color(wishHex: hex)).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(WishTheme.line, lineWidth: 1))
                            .overlay(Circle().stroke(WishTheme.accent, lineWidth: current.lowercased() == hex.lowercased() ? 3 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Decorations

    private var decorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Decorations on the box", "Up to 3. The first is included, each extra is \u{20B9}200. Say \u{201C}put flowers and stars on top\u{201D}.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(GiftCatalogue.decorations) { d in
                    let on = state.config.decor.contains(d.id)
                    Button { state.toggleDecor(d.id) } label: {
                        Text("\(d.emoji) \(d.name)").font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(on ? WishTheme.accentSoft : Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? WishTheme.accent : WishTheme.line, lineWidth: on ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Items

    private var shownItems: [GiftItem] {
        return state.itemCategory == "All" ? GiftCatalogue.items : GiftCatalogue.items.filter { $0.category == state.itemCategory }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Products inside the box", "Real catalogue products. Prices are the catalogue bands (under \u{20B9}1,000 to \u{20B9}2,500) until exact prices are set. Tap, or say \u{201C}add the coconut candle and a tea set, remove the frame\u{201D}. Stays within \(giftRupees(GiftRange.min))\u{2013}\(giftRupees(GiftRange.max)).")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["All"] + GiftCatalogue.categories, id: \.self) { c in
                        Button(c) { state.itemCategory = c }
                            .buttonStyle(.bordered).controlSize(.small)
                            .tint(state.itemCategory == c ? WishTheme.accent : Color.gray)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(shownItems) { item in
                    let included = state.config.items.contains(item.id)
                    Button { state.toggleItem(item.id) } label: {
                        VStack(spacing: 3) {
                            GiftPhotoView(id: item.id)
                                .aspectRatio(1.5, contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(item.name).font(.system(size: 11, weight: .semibold, design: .serif)).lineLimit(2).multilineTextAlignment(.center)
                            Text(giftRupees(item.price)).font(.system(size: 10)).foregroundStyle(WishTheme.muted)
                        }
                        .frame(maxWidth: .infinity).padding(6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(included ? WishTheme.accentSoft : Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(included ? WishTheme.accent : WishTheme.line, lineWidth: included ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Card

    private func field(_ label: String, _ placeholder: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(WishTheme.muted)
            TextField(placeholder, text: binding).textFieldStyle(.roundedBorder)
        }
    }

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Gift card", "The VYBES logo is on every card. Say \u{201C}card to Priya from Rahul message Happy birthday\u{201D}.")
            HStack(spacing: 8) {
                field("To", "Priya", Binding(get: { state.config.cardTo }, set: { state.config.cardTo = $0 }))
                field("From", "Rahul", Binding(get: { state.config.cardFrom }, set: { state.config.cardFrom = $0 }))
            }
            field("Message", "Wishing you joy, today and always.", Binding(get: { state.config.cardMessage }, set: { state.config.cardMessage = $0 }))
            Picker("", selection: Binding(get: { state.config.cardStyle }, set: { state.config.cardStyle = $0 })) {
                Text("Classic").tag("classic")
                Text("Modern").tag("modern")
                Text("Festive").tag("festive")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // Experience note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Gift experience note", "How the gift should feel to open. Say \u{201C}note\u{201D} and then your words.")
            TextEditor(text: Binding(get: { state.config.note.isEmpty ? state.suggestedNote : state.config.note }, set: { state.config.note = $0 }))
                .font(.system(size: 12))
                .frame(height: 84)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(WishTheme.line, lineWidth: 1))
            HStack {
                Button("Use suggested note") { state.config.note = "" }.buttonStyle(.bordered).controlSize(.small)
                Button("Save picture to Desktop") { state.savePicture() }.buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    // Order

    private var orderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Place order", "Say \u{201C}order name Asha, phone 9876543210, address 12 MG Road, place order\u{201D}.")
            HStack(spacing: 8) {
                field("Name", "Asha", Binding(get: { state.config.customer }, set: { state.config.customer = $0 }))
                field("Phone", "9876543210", Binding(get: { state.config.phone }, set: { state.config.phone = $0 }))
            }
            field("Delivery address", "12 MG Road, Pune", Binding(get: { state.config.address }, set: { state.config.address = $0 }))
            Stepper("Quantity: \(state.config.quantity)", value: Binding(get: { state.config.quantity }, set: { state.config.quantity = max(1, min(500, $0)) }), in: 1...500)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(state.config.items, id: \.self) { id in
                    if let item = GiftCatalogue.item(id) {
                        HStack { Text(item.name); Spacer(); Text(giftRupees(item.price)) }.font(.system(size: 12))
                    }
                }
                HStack { Text("VYBES box, ribbon, lining and card"); Spacer(); Text(giftRupees(state.config.packaging)) }.font(.system(size: 12))
                if state.config.extraDecor > 0 {
                    HStack { Text("Extra decoration"); Spacer(); Text(giftRupees(state.config.extraDecor)) }.font(.system(size: 12))
                }
                Divider()
                HStack {
                    Text("Total for \(state.config.quantity)").font(.system(size: 14, weight: .bold))
                    Spacer()
                    Text(giftRupees(state.config.total)).font(.system(size: 16, weight: .bold)).foregroundStyle(WishTheme.accent)
                }
            }
            Button { state.placeOrder() } label: {
                Label("Place order", systemImage: "bag.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            if let order = state.placed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Order \(order.id) placed").font(.system(size: 13, weight: .bold))
                    Text("Saved on this Mac. The summary is copied, so you can paste it anywhere.").font(.caption).foregroundStyle(WishTheme.muted)
                    HStack {
                        Button("Send on WhatsApp") { state.shareWhatsApp() }.buttonStyle(.bordered).controlSize(.small)
                        Button("Send by email") { state.shareEmail() }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(wishHex: "#E8F3EC")))
            }
            Text("Online payment and delivery are not connected yet: an order is saved here and sent as a message.")
                .font(.caption2).foregroundStyle(WishTheme.muted)
        }
    }
}
