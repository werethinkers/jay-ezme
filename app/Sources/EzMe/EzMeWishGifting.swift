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
    let emoji: String
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
}

enum GiftCatalogue {
    static let items: [GiftItem] = [
        GiftItem(id: "reed", name: "Reed diffuser", emoji: "\u{1F3FA}", category: "Diffuser", price: 1450, words: ["reed diffuser", "diffuser", "diffusers", "reed"]),
        GiftItem(id: "ultra", name: "Ultrasonic diffuser", emoji: "\u{1F4A8}", category: "Diffuser", price: 2400, words: ["ultrasonic diffuser", "ultrasonic", "aroma lamp"]),
        GiftItem(id: "candle", name: "Soy candle", emoji: "\u{1F56F}\u{FE0F}", category: "Candle", price: 650, words: ["soy candle", "candle", "candles"]),
        GiftItem(id: "trio", name: "Candle trio", emoji: "\u{1F56F}\u{FE0F}", category: "Candle", price: 1250, words: ["candle trio", "candle set", "three candles"]),
        GiftItem(id: "incense", name: "Incense and holder", emoji: "\u{1F33F}", category: "Diffuser", price: 480, words: ["incense", "agarbatti", "incense sticks"]),
        GiftItem(id: "edp", name: "Eau de parfum", emoji: "\u{1F9F4}", category: "Perfume", price: 2200, words: ["eau de parfum", "perfume", "perfumes", "fragrance", "parfum"]),
        GiftItem(id: "luxe", name: "Luxe perfume 50ml", emoji: "\u{1F9F4}", category: "Perfume", price: 3200, words: ["luxe perfume", "luxury perfume", "premium perfume"]),
        GiftItem(id: "attar", name: "Oud attar", emoji: "\u{1F4A7}", category: "Perfume", price: 1900, words: ["oud attar", "attar", "oud"]),
        GiftItem(id: "minis", name: "Perfume minis", emoji: "\u{1F9F4}", category: "Perfume", price: 1100, words: ["perfume minis", "mini perfumes", "miniatures", "perfume set"]),
        GiftItem(id: "choc", name: "Belgian chocolates", emoji: "\u{1F36B}", category: "Eatable", price: 1100, words: ["belgian chocolates", "chocolate", "chocolates"]),
        GiftItem(id: "truffle", name: "Truffle box", emoji: "\u{1F36B}", category: "Eatable", price: 1600, words: ["truffle box", "truffle", "truffles"]),
        GiftItem(id: "dry", name: "Premium dry fruits", emoji: "\u{1F95C}", category: "Eatable", price: 1400, words: ["dry fruits", "dry fruit", "dryfruits", "nuts", "almonds", "cashews"]),
        GiftItem(id: "cookies", name: "Artisan cookies", emoji: "\u{1F36A}", category: "Eatable", price: 700, words: ["artisan cookies", "cookie", "cookies", "biscuits"]),
        GiftItem(id: "mithai", name: "Mithai assortment", emoji: "\u{1F36C}", category: "Eatable", price: 1000, words: ["mithai", "sweets", "sweet", "ladoo", "barfi"]),
        GiftItem(id: "honey", name: "Wild honey", emoji: "\u{1F36F}", category: "Eatable", price: 550, words: ["wild honey", "honey"]),
        GiftItem(id: "tea", name: "Gourmet tea tin", emoji: "\u{1F375}", category: "Eatable", price: 750, words: ["tea tin", "tea", "chai"]),
        GiftItem(id: "coffee", name: "Specialty coffee", emoji: "\u{2615}", category: "Eatable", price: 850, words: ["specialty coffee", "coffee"]),
        GiftItem(id: "journal", name: "Leather journal", emoji: "\u{1F4D3}", category: "Gift", price: 1500, words: ["leather journal", "journal", "diary", "notebook"]),
        GiftItem(id: "pen", name: "Signature pen", emoji: "\u{1F58A}\u{FE0F}", category: "Gift", price: 1200, words: ["signature pen", "pen"]),
        GiftItem(id: "frame", name: "Photo frame", emoji: "\u{1F5BC}\u{FE0F}", category: "Gift", price: 900, words: ["photo frame", "frame"]),
        GiftItem(id: "plant", name: "Mini plant", emoji: "\u{1FAB4}", category: "Gift", price: 600, words: ["mini plant", "plant", "succulent"]),
        GiftItem(id: "scarf", name: "Silk scarf", emoji: "\u{1F9E3}", category: "Gift", price: 1900, words: ["silk scarf", "scarf", "stole"]),
        GiftItem(id: "teddy", name: "Soft teddy", emoji: "\u{1F9F8}", category: "Gift", price: 800, words: ["soft teddy", "teddy", "soft toy"]),
        GiftItem(id: "clock", name: "Desk clock", emoji: "\u{1F570}\u{FE0F}", category: "Gift", price: 1700, words: ["desk clock", "clock"]),
        GiftItem(id: "rose", name: "Preserved rose", emoji: "\u{1F339}", category: "Gift", price: 1300, words: ["preserved rose", "roses"]),
        GiftItem(id: "spa", name: "Spa soap set", emoji: "\u{1F9FC}", category: "Gift", price: 950, words: ["spa soap", "spa set", "soap", "soaps", "spa"]),
        GiftItem(id: "wallet", name: "Leather wallet", emoji: "\u{1F45B}", category: "Gift", price: 2100, words: ["leather wallet", "wallet", "purse"]),
        GiftItem(id: "pendant", name: "Silver pendant", emoji: "\u{1F48E}", category: "Gift", price: 2800, words: ["silver pendant", "pendant", "jewellery", "jewelry"]),
        GiftItem(id: "diya", name: "Diya set", emoji: "\u{1FA94}", category: "Gift", price: 600, words: ["diya set", "diya", "diyas"]),
        GiftItem(id: "bamboo", name: "Lucky bamboo", emoji: "\u{1F38B}", category: "Gift", price: 700, words: ["lucky bamboo", "bamboo"]),
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
    let packaging: Int

    var price: Int {
        var sum = packaging
        for i in items { sum += GiftCatalogue.item(i)?.price ?? 0 }
        return sum
    }
}

enum GiftBoxes {
    static let all: [GiftBox] = build()

    static func box(_ id: Int) -> GiftBox {
        return all.first { $0.id == id } ?? all[0]
    }

    private static func build() -> [GiftBox] {
        let names = [
            "Calm Hour", "Velvet Whisper", "Golden Pause", "Blush Bloom", "Ivory Embrace", "Plum Reverie", "Teal Escape", "Midnight Muse",
            "Terracotta Glow", "Royal Cheer", "Aroma Haven", "Sweet Surrender", "Garden Grace", "Festive Spark", "Boardroom Thanks",
            "Wellness Ritual", "Rose and Ritual", "Gourmet Delight", "Little Joy", "Warm Welcome", "Cedar and Silk", "Opal Evening",
            "Saffron Dusk", "Heirloom Hamper", "Crystal Morning", "Imperial Oud", "Moonlit Indulgence", "Grand Gratitude", "Signature Vybe", "The Maharaja Edit",
        ]
        let themes: [[String]] = [
            ["reed", "candle", "spa", "tea"], ["edp", "attar", "choc", "rose"], ["choc", "mithai", "cookies", "dry"], ["candle", "frame", "plant", "tea"],
            ["diya", "dry", "mithai", "candle"], ["journal", "pen", "coffee", "tea"], ["tea", "honey", "spa", "reed"], ["edp", "rose", "truffle", "candle"],
            ["coffee", "honey", "cookies", "dry"], ["teddy", "choc", "cookies", "plant"],
        ]
        let palettes: [(String, String, String)] = [
            ("#7A1F3D", "#D4A84A", "#F8E1E7"), ("#1F5A45", "#E0B85A", "#DDF0E5"), ("#1D2F5C", "#C9CED8", "#E3ECFA"), ("#F2C9D2", "#B76E79", "#FFF6F0"),
            ("#F3EBDD", "#C9A24B", "#FBF4E6"), ("#5B2A6B", "#C27C4E", "#EBDDF3"), ("#146B73", "#E2B04A", "#DCF2F2"), ("#2B2B30", "#D8AE55", "#F4EFE6"),
            ("#C0603A", "#F4E3C8", "#FDE6D8"), ("#2A4DB0", "#E6B94F", "#E1EAFB"),
        ]
        let decors = ["flowers", "stars", "hearts", "leaves", "butterflies", "confetti", "balloons"]
        let expensiveFirst = GiftCatalogue.items.sorted { $0.price > $1.price }.map { $0.id }
        let cheapFirst = Array(expensiveFirst.reversed())
        var out: [GiftBox] = []
        for i in 0..<names.count {
            let target = 3000 + Int((Double(i) * 699.0 / Double(names.count - 1)).rounded()) * 10
            let budget = target - 450
            let pool = themes[i % themes.count] + (i < 10 ? cheapFirst : expensiveFirst)
            var ids: [String] = []
            var sum = 0
            for id in pool {
                if ids.count >= GiftRange.slots { break }
                if ids.contains(id) { continue }
                guard let item = GiftCatalogue.item(id) else { continue }
                if sum + item.price <= budget {
                    ids.append(id)
                    sum += item.price
                }
            }
            let p = palettes[(i * 7) % palettes.count]
            out.append(GiftBox(id: i + 1, name: names[i], boxHex: p.0, ribbonHex: p.1, tissueHex: p.2,
                               decor: [decors[i % decors.count]], items: ids, packaging: target - sum))
        }
        return out
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
    var packaging: Int = 600
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
        packaging = box.packaging
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
    @Published var maxPrice: Int = GiftRange.max
    @Published var placed: GiftOrder? = nil

    private var history: [GiftConfig] = []
    private var unboxTask: Task<Void, Never>?
    private static let key = "keydoGiftingConfig"

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
        if cats.contains("Perfume") { sentences.append("A first spritz of fragrance sets the mood.") }
        if cats.contains("Diffuser") || cats.contains("Candle") { sentences.append("Set the aroma going and the room slowly fills with calm.") }
        if cats.contains("Eatable") { sentences.append("Something sweet to taste and share.") }
        if cats.contains("Gift") { sentences.append("Small keepsakes stay long after the box is gone.") }
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
            if let item = GiftCatalogue.item(itemID) { lines.append("\u{2022} \(item.emoji) \(item.name): \(giftRupees(item.price))") }
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
            GiftBoxOutside(config: config).frame(width: 380, height: 380)
            GiftBoxInside(config: config, tissueOpen: 1, itemsShown: 99, showCard: true, labels: true).frame(width: 380, height: 380)
            GiftCardArt(config: config, compact: false).frame(width: 380, height: 270)
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
            notes.append("Showing all boxes.")
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
            for id in findItems(in: rest).ids {
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

// MARK: - Drawing: closed box

struct GiftBoxOutside: View {
    let config: GiftConfig
    var lid: CGFloat = 0
    var ribbonOn: Bool = true

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Ellipse().fill(Color.black.opacity(0.14)).frame(width: s * 0.8, height: s * 0.07).position(x: s / 2, y: s * 0.94)
                bodyPart(s)
                lidPart(s)
            }
            .frame(width: s, height: s)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func bodyPart(_ s: CGFloat) -> some View {
        let box = Color(wishHex: config.boxHex)
        let band = Color(wishHex: config.ribbonHex)
        return ZStack {
            RoundedRectangle(cornerRadius: s * 0.03).fill(box).frame(width: s * 0.80, height: s * 0.46)
            RoundedRectangle(cornerRadius: s * 0.03)
                .fill(LinearGradient(colors: [Color.white.opacity(0.16), Color.clear, Color.black.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: s * 0.80, height: s * 0.46)
            Rectangle().fill(band).frame(width: s * 0.09, height: s * 0.46).opacity(ribbonOn ? 1 : 0)
            plate(s)
        }
        .frame(width: s * 0.80, height: s * 0.46)
        .position(x: s / 2, y: s * 0.70)
    }

    private func plate(_ s: CGFloat) -> some View {
        return RoundedRectangle(cornerRadius: s * 0.02)
            .fill(Color(wishHex: "#FAF4F0"))
            .frame(width: s * 0.42, height: s * 0.27)
            .overlay(VybesLogoView().padding(s * 0.012))
            .overlay(RoundedRectangle(cornerRadius: s * 0.02).stroke(Color(wishHex: config.ribbonHex), lineWidth: max(1, s * 0.006)))
            .shadow(color: Color.black.opacity(0.2), radius: s * 0.01, x: 0, y: s * 0.004)
    }

    private func lidPart(_ s: CGFloat) -> some View {
        let lidColor = Color(wishHex: GiftColor.shade(config.boxHex, 0.86))
        let band = Color(wishHex: config.ribbonHex)
        return ZStack {
            RoundedRectangle(cornerRadius: s * 0.03).fill(lidColor).frame(width: s * 0.86, height: s * 0.20)
            Rectangle().fill(band).frame(width: s * 0.09, height: s * 0.20).opacity(ribbonOn ? 1 : 0)
            decorations(s)
            bow(s).opacity(ribbonOn ? 1 : 0)
        }
        .frame(width: s * 0.86, height: s * 0.20)
        .rotationEffect(.degrees(Double(lid) * -9))
        .opacity(1 - Double(lid) * 0.3)
        .position(x: s / 2, y: s * 0.40 - lid * s * 0.30)
    }

    private func bow(_ s: CGFloat) -> some View {
        let band = Color(wishHex: config.ribbonHex)
        let knot = Color(wishHex: GiftColor.shade(config.ribbonHex, 0.8))
        return ZStack {
            Ellipse().fill(band).frame(width: s * 0.16, height: s * 0.09).rotationEffect(.degrees(-22)).offset(x: -s * 0.07, y: -s * 0.115)
            Ellipse().fill(band).frame(width: s * 0.16, height: s * 0.09).rotationEffect(.degrees(22)).offset(x: s * 0.07, y: -s * 0.115)
            Circle().fill(knot).frame(width: s * 0.05, height: s * 0.05).offset(x: 0, y: -s * 0.10)
        }
    }

    private func decorations(_ s: CGFloat) -> some View {
        let symbols = config.decor.compactMap { GiftCatalogue.decorEmoji($0) }
        let slots: [(CGFloat, CGFloat, CGFloat)] = [(-0.34, 0.0, 0.085), (0.34, 0.0, 0.085), (-0.22, 0.0, 0.07), (0.22, 0.0, 0.07), (-0.40, -0.13, 0.07), (0.40, -0.13, 0.07)]
        return ZStack {
            if !symbols.isEmpty {
                ForEach(0..<slots.count, id: \.self) { i in
                    Text(symbols[i % symbols.count])
                        .font(.system(size: s * slots[i].2))
                        .offset(x: s * slots[i].0, y: s * slots[i].1)
                }
            }
        }
    }
}

// MARK: - Drawing: inside the box

struct GiftBoxInside: View {
    let config: GiftConfig
    var tissueOpen: CGFloat = 1
    var itemsShown: Int = 99
    var showCard: Bool = true
    var labels: Bool = true

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                lidUnderside(s)
                walls(s)
                cells(s)
                flaps(s)
                cardPiece(s)
            }
            .frame(width: s, height: s)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func lidUnderside(_ s: CGFloat) -> some View {
        return RoundedRectangle(cornerRadius: s * 0.03)
            .fill(Color(wishHex: GiftColor.shade(config.boxHex, 0.8)))
            .frame(width: s * 0.86, height: s * 0.17)
            .overlay(
                RoundedRectangle(cornerRadius: s * 0.015)
                    .fill(Color(wishHex: "#FAF4F0"))
                    .frame(width: s * 0.26, height: s * 0.13)
                    .overlay(VybesLogoView().padding(s * 0.006))
            )
            .position(x: s / 2, y: s * 0.09)
    }

    private func walls(_ s: CGFloat) -> some View {
        return ZStack {
            RoundedRectangle(cornerRadius: s * 0.03).fill(Color(wishHex: config.boxHex)).frame(width: s * 0.92, height: s * 0.76)
            RoundedRectangle(cornerRadius: s * 0.02).fill(Color(wishHex: GiftColor.shade(config.tissueHex, 0.97))).frame(width: s * 0.82, height: s * 0.66)
        }
        .position(x: s / 2, y: s * 0.62)
    }

    private func cells(_ s: CGFloat) -> some View {
        return ZStack {
            ForEach(0..<GiftRange.slots, id: \.self) { i in
                cell(i, s)
                    .position(x: s * (0.5 + (CGFloat(i % 3) - 1) * 0.265), y: s * (0.62 + (CGFloat(i / 3) - 0.5) * 0.32))
            }
        }
    }

    @ViewBuilder
    private func cell(_ i: Int, _ s: CGFloat) -> some View {
        if i < config.items.count, i < itemsShown, let item = GiftCatalogue.item(config.items[i]) {
            VStack(spacing: s * 0.008) {
                Text(item.emoji).font(.system(size: s * 0.12))
                if labels {
                    Text(item.name)
                        .font(.system(size: max(7, s * 0.032), weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .foregroundStyle(Color(wishHex: "#3A2A20"))
                }
            }
            .frame(width: s * 0.245, height: s * 0.30)
            .background(RoundedRectangle(cornerRadius: s * 0.02).fill(Color.white.opacity(0.75)))
            .shadow(color: Color.black.opacity(0.12), radius: s * 0.01, x: 0, y: s * 0.004)
            .transition(.scale.combined(with: .opacity))
        } else {
            RoundedRectangle(cornerRadius: s * 0.02)
                .stroke(Color.black.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: s * 0.245, height: s * 0.30)
        }
    }

    private func flaps(_ s: CGFloat) -> some View {
        let tissue = Color(wishHex: config.tissueHex)
        let open = Double(tissueOpen)
        return ZStack {
            Rectangle().fill(tissue).frame(width: s * 0.41, height: s * 0.66)
                .rotationEffect(.degrees(-open * 18))
                .offset(x: -s * 0.205 - CGFloat(open) * s * 0.35)
            Rectangle().fill(tissue.opacity(0.94)).frame(width: s * 0.41, height: s * 0.66)
                .rotationEffect(.degrees(open * 18))
                .offset(x: s * 0.205 + CGFloat(open) * s * 0.35)
        }
        .opacity(1 - open * 0.92)
        .position(x: s / 2, y: s * 0.62)
    }

    private func cardPiece(_ s: CGFloat) -> some View {
        return GiftCardArt(config: config, compact: true)
            .frame(width: s * 0.30, height: s * 0.22)
            .rotationEffect(.degrees(7))
            .position(x: s * 0.80, y: s * 0.86)
            .offset(x: showCard ? 0 : s * 0.6)
            .opacity(showCard ? 1 : 0)
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
                .fill(LinearGradient(colors: [Color(wishHex: GiftColor.shade(state.config.tissueHex, 1.15)), Color(wishHex: GiftColor.shade(state.config.tissueHex, 0.98))], startPoint: .top, endPoint: .bottom))
            content.padding(16)
        }
        .animation(.easeInOut(duration: 0.5), value: state.unboxStep)
    }

    @ViewBuilder
    private var content: some View {
        switch state.view {
        case .closed:
            GiftBoxOutside(config: state.config, lid: 0, ribbonOn: true)
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
            GiftBoxOutside(config: state.config, lid: 0, ribbonOn: state.unboxStep == 0).transition(.opacity)
        } else if state.unboxStep == 2 {
            GiftBoxOutside(config: state.config, lid: 1, ribbonOn: false).transition(.opacity)
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
    @State private var category = "All"

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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 12)], spacing: 12) {
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
                GiftBoxOutside(config: cfg).frame(height: 118)
                Text("\(box.id). \(box.name)").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(cfg.items.compactMap { GiftCatalogue.item($0)?.emoji }.joined()).font(.system(size: 12)).lineLimit(1)
                Text(giftRupees(cfg.unitPrice)).font(.system(size: 12, weight: .bold)).foregroundStyle(WishTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 196)
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
                GiftStage(state: state).frame(height: 360)
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
        return category == "All" ? GiftCatalogue.items : GiftCatalogue.items.filter { $0.category == category }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Inside the box", "Tap to add or remove, or say \u{201C}add a diffuser and perfume, remove the candle\u{201D}. Stays within \(giftRupees(GiftRange.min))\u{2013}\(giftRupees(GiftRange.max)).")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["All"] + GiftCatalogue.categories, id: \.self) { c in
                        Button(c) { category = c }
                            .buttonStyle(.bordered).controlSize(.small)
                            .tint(category == c ? WishTheme.accent : Color.gray)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(shownItems) { item in
                    let included = state.config.items.contains(item.id)
                    Button { state.toggleItem(item.id) } label: {
                        VStack(spacing: 3) {
                            Text(item.emoji).font(.system(size: 26))
                            Text(item.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Text(giftRupees(item.price)).font(.system(size: 10)).foregroundStyle(WishTheme.muted)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
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
                        HStack { Text("\(item.emoji) \(item.name)"); Spacer(); Text(giftRupees(item.price)) }.font(.system(size: 12))
                    }
                }
                HStack { Text("Box, ribbon, tissue and VYBES packaging"); Spacer(); Text(giftRupees(state.config.packaging)) }.font(.system(size: 12))
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
