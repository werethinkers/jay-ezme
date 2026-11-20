// WishStudio "Gifting": one fixed-size VYBES box (34 x 24 x 9 cm) in wood, metal, leather, rubber or PU.
// Only the finish changes; the jars (shape, material, size), what is inside them, the filling and the lid flowers are chosen on top.
// The model and prices are in EzMeGiftModel.swift, the drawing in EzMeGiftArt.swift.
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

// MARK: - Product photos (style reference thumbnails)

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
    @Published var message: String = "Choose a box finish, then the jars. Or say, for example, \u{201C}teak box, trio, octagon jars with chocolates, gold flowers\u{201D}."
    @Published var placed: GiftOrder?
    @Published var activeJar: Int = 0

    private var undoStack: [GiftConfig] = []
    private var unboxTask: Task<Void, Never>?
    private static let key = "keydoGiftingConfig3"

    init() {
        if let data = UserDefaults.standard.data(forKey: GiftingState.key), let saved = try? JSONDecoder().decode(GiftConfig.self, from: data) {
            config = saved
        } else {
            config = GiftConfig()
        }
        normalise()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: GiftingState.key)
        }
    }

    private func normalise() {
        let n = config.layout.slots.count
        var jars = config.jars
        while jars.count < n { jars.append(jars.last ?? JarSpec(styleID: "facet", materialID: "crystal", sizeID: "M", contentID: "candle")) }
        if jars.count > n { jars = Array(jars.prefix(n)) }
        if jars != config.jars { config.jars = jars }
        if activeJar >= n { activeJar = 0 }
    }

    // MARK: Changing the gift

    func change(_ block: (inout GiftConfig) -> Void) {
        undoStack.append(config)
        if undoStack.count > 40 { undoStack.removeFirst() }
        var c = config
        block(&c)
        config = c
        normalise()
        placed = nil
    }

    func undo() {
        guard let last = undoStack.popLast() else {
            message = "Nothing to undo."
            return
        }
        config = last
        normalise()
        message = "Undone."
    }

    func setFinish(_ id: String) {
        change { $0.finishID = id }
        message = "\(GiftCatalogue.finish(id).name): same 34 \u{00D7} 24 \u{00D7} 9 cm box, new finish."
    }

    func setMaterial(_ m: BoxMaterial) {
        if config.finish.material == m { return }
        if let f = GiftCatalogue.finishList(of: m).first { setFinish(f.id) }
    }

    func setLayout(_ id: String) {
        change { $0.layoutID = id }
        message = "\(GiftCatalogue.layout(id).name): \(config.jars.count) jars in the same box."
    }

    func setJar(_ index: Int, _ block: (inout JarSpec) -> Void) {
        guard index >= 0, index < config.jars.count else { return }
        change { c in block(&c.jars[index]) }
    }

    func applyToAllJars(from index: Int) {
        guard index >= 0, index < config.jars.count else { return }
        let src = config.jars[index]
        change { c in for i in 0..<c.jars.count { c.jars[i] = src } }
        message = "All jars now match jar \(index + 1)."
    }

    func setAllJarStyle(_ id: String) {
        change { c in for i in 0..<c.jars.count { c.jars[i].styleID = id } }
        message = "All jars are now \(GiftCatalogue.jarStyle(id).name). Same box, same size."
    }

    func show(_ v: GiftView) {
        if v != .unbox { stopUnbox() }
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
                if step == 3 {
                    let n = max(1, self.config.jars.count)
                    for k in 1...n {
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        if Task.isCancelled { return }
                        withAnimation(.spring()) { self.itemsShown = k }
                    }
                }
                if step >= 4 { self.itemsShown = 99 }
                try? await Task.sleep(nanoseconds: 1_300_000_000)
            }
            self.isPlaying = false
        }
    }

    func caption(_ step: Int) -> String {
        switch step {
        case 0: return "The closed \(config.finish.material.title.lowercased()) box, 34 \u{00D7} 24 \u{00D7} 9 cm, with the VYBES label."
        case 1: return "The clasp opens and the lid lifts."
        case 2: return "Inside: the lining and the filling, before the jars."
        case 3: return "Each jar is set into its slot, one at a time."
        case 4: return "Every jar sits in its own slot, with filling between."
        case 5: return "Nothing moves: each jar fits its slot."
        default: return "The card is tucked in, ready to be read."
        }
    }

    // MARK: Experience note

    var suggestedNote: String {
        var parts: [String] = []
        parts.append("A \(config.finish.name.lowercased()) \(config.finish.material.title.lowercased()) box. Open the lid")
        let names: [String] = config.jars.map { j in
            let content = GiftCatalogue.content(j.contentID)
            let jar = GiftCatalogue.jarStyle(j.styleID).name.lowercased()
            return content.id == "none" ? jar : "\(content.name.lowercased()) in a \(jar)"
        }
        if !names.isEmpty { parts.append("to find " + names.joined(separator: ", ")) }
        let fill = GiftCatalogue.filling(config.fillingID)
        if fill.id != "none" { parts.append("resting in \(fill.name.lowercased())") }
        var text = parts.joined(separator: " ") + "."
        let fl = GiftCatalogue.flower(config.flowerID)
        if fl.id != "none" { text += " The lid carries \(fl.name.lowercased())." }
        return text
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
        let f = config.finish
        var lines: [String] = ["VYBES \u{2014} Gift the Vibe", "Order \(id)", ""]
        lines.append("Box: \(f.name) (\(f.material.title)), \(GiftBoxSpec.cm(GiftBoxSpec.outerW)) x \(GiftBoxSpec.cm(GiftBoxSpec.outerD)) x \(GiftBoxSpec.cm(GiftBoxSpec.height)) cm, inner \(GiftBoxSpec.cm(GiftBoxSpec.innerW)) x \(GiftBoxSpec.cm(GiftBoxSpec.innerD)) cm: \(giftRupees(config.boxPrice))")
        lines.append("Layout: \(config.layout.name)")
        let layout = config.layout
        for (i, j) in config.jars.enumerated() {
            let style = GiftCatalogue.jarStyle(j.styleID)
            let mat = GiftCatalogue.jarMaterial(j.materialID)
            let dia = i < layout.slots.count ? GiftBoxSpec.cm(GiftCatalogue.jarDiameter(slot: layout.slots[i], size: j.sizeID)) : "-"
            let content = GiftCatalogue.content(j.contentID)
            lines.append("Jar \(i + 1): \(style.name), \(mat.name), size \(j.sizeID) (\u{00D8} \(dia) cm), with \(content.name.lowercased()): \(giftRupees(config.jarPrice(j) + content.price))")
        }
        lines.append("Filling: \(GiftCatalogue.filling(config.fillingID).name) \(config.fillingHex): \(giftRupees(config.fillingPrice))")
        lines.append("Lid decoration: \(GiftCatalogue.flower(config.flowerID).name): \(giftRupees(config.flowerPrice))")
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
        if config.unitPrice < GiftRange.min {
            message = "This gift is \(giftRupees(config.unitPrice)). A gift starts at \(giftRupees(GiftRange.min)): add contents, a bigger jar or a lid decoration."
            return
        }
        if config.unitPrice > GiftRange.max {
            message = "This gift is \(giftRupees(config.unitPrice)). A gift can be at most \(giftRupees(GiftRange.max)): use a smaller jar or fewer contents."
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
            GiftLidView(config: config, dims: true, detail: true).frame(width: 540, height: 400)
            GiftBoxTop(config: config, jarsShown: 99, dims: true, detail: true).frame(width: 540, height: 400)
            GiftCardArt(config: config, compact: false).frame(width: 400, height: 276)
        }
        .padding(24)
        .background(Color(wishHex: "#F2EBDD"))
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

    private let markers: [(String, String)] = [
        ("card message ", "msg"), ("card to ", "to"), ("card for ", "to"), ("card from ", "from"),
        ("experience note ", "note"), ("gift note ", "note"), ("note ", "note"), ("message ", "msg"),
        ("order name ", "cust"), ("customer ", "cust"), ("my name is ", "cust"),
        ("deliver to ", "addr"), ("deliver at ", "addr"), ("ship to ", "addr"), ("address ", "addr"),
        ("phone ", "phone"), ("mobile ", "phone"),
    ]

    private struct MarkerHit {
        var start: String.Index
        var end: String.Index
        var key: String
    }

    private func splitFields(_ raw: String) -> (fields: [String: String], rest: String) {
        var hits: [MarkerHit] = []
        let ordered = markers.sorted { $0.0.count > $1.0.count }
        for (word, key) in ordered {
            guard let r = raw.range(of: word, options: .caseInsensitive) else { continue }
            var overlaps = false
            for h in hits where r.lowerBound < h.end && r.upperBound > h.start { overlaps = true; break }
            if !overlaps { hits.append(MarkerHit(start: r.lowerBound, end: r.upperBound, key: key)) }
        }
        hits.sort { $0.start < $1.start }
        guard let first = hits.first else { return ([:], raw) }
        var fields: [String: String] = [:]
        for (i, h) in hits.enumerated() {
            let stop = i + 1 < hits.count ? hits[i + 1].start : raw.endIndex
            var value = String(raw[h.end..<stop]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.;"))
            for tail in [" and", " then"] where value.lowercased().hasSuffix(tail) { value = String(value.dropLast(tail.count)) }
            fields[h.key] = value.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;"))
        }
        return (fields, String(raw[raw.startIndex..<first.start]))
    }

    private func table<T>(_ items: [T], _ id: (T) -> String, _ words: (T) -> [String]) -> [(String, [String])] {
        return items.map { (id($0), words($0)) }
    }

    private func match(_ clause: String, _ rows: [(String, [String])]) -> String? {
        var best: String?
        var bestLen = 0
        for (id, words) in rows {
            for w in words where clause.contains(" " + w + " ") && w.count > bestLen {
                best = id
                bestLen = w.count
            }
        }
        return best
    }

    private func normalised(_ s: String) -> String {
        let cleaned = s.lowercased().replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: ".", with: " ")
        return " " + cleaned.split(separator: " ").joined(separator: " ") + " "
    }

    private func slotIndices(_ c: String) -> [Int]? {
        let layout = config.layout
        let count = config.jars.count
        let digits: [(String, Int)] = [("1", 0), ("2", 1), ("3", 2), ("4", 3)]
        for (d, i) in digits where c.contains(" jar \(d) ") || c.contains(" jar number \(d) ") || c.contains(" bottle \(d) ") {
            return i < count ? [i] : nil
        }
        let ordinals: [(String, Int)] = [("first", 0), ("second", 1), ("third", 2), ("fourth", 3), ("last", count - 1)]
        for (w, i) in ordinals where c.contains(" \(w) ") && i >= 0 && i < count { return [i] }
        let names = layout.slotNames.enumerated().sorted { $0.element.count > $1.element.count }
        for (i, n) in names where c.contains(" \(n) ") || (n == "centre" && c.contains(" center ")) { return [i] }
        return nil
    }

    func handle(_ text: String) {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return }
        var working = raw
        var wantsOrder = false
        for phrase in ["and place the order", "and place order", "place the order", "place order", "place my order"] {
            if let r = working.range(of: phrase, options: .caseInsensitive) {
                wantsOrder = true
                working.removeSubrange(r)
            }
        }
        let parts = splitFields(working)
        var did: [String] = []
        if let v = parts.fields["to"] { change { $0.cardTo = v }; did.append("card to \(v)") }
        if let v = parts.fields["from"] { change { $0.cardFrom = v }; did.append("card from \(v)") }
        if let v = parts.fields["msg"] { change { $0.cardMessage = v }; did.append("card message") }
        if let v = parts.fields["note"] { change { $0.note = v }; did.append("experience note") }
        if let v = parts.fields["cust"] { change { $0.customer = v }; did.append("name \(v)") }
        if let v = parts.fields["addr"] { change { $0.address = v }; did.append("delivery address") }
        if let v = parts.fields["phone"] {
            let digits = v.filter { $0.isNumber }
            change { $0.phone = digits }
            did.append("phone")
        }

        let rest = normalised(parts.rest)
        if rest.contains(" undo ") || rest.contains(" go back ") {
            undo()
            return
        }
        if rest.contains(" unbox ") || rest.contains(" unboxing ") || rest.contains(" open the gift ") {
            show(.unbox)
            did.append("unboxing")
        } else if rest.contains(" show inside ") || rest.contains(" inside view ") || rest.contains(" open the box ") || rest.contains(" open it ") || rest.contains(" show jars ") {
            show(.inside)
            did.append("inside view")
        } else if rest.contains(" close the box ") || rest.contains(" closed view ") || rest.contains(" show closed ") || rest.contains(" show lid ") || rest.contains(" show the lid ") {
            show(.closed)
            did.append("closed view")
        } else if rest.contains(" show card ") || rest.contains(" show the card ") || rest.contains(" card view ") {
            show(.card)
            did.append("card view")
        }
        if rest.contains(" save picture ") || rest.contains(" save image ") || rest.contains(" save the picture ") {
            savePicture()
            return
        }
        if rest.contains(" whatsapp ") { shareWhatsApp(); return }
        if rest.contains(" email it ") || rest.contains(" send email ") { shareEmail(); return }

        let clauses = splitClauses(parts.rest)
        var carry: [Int]? = nil
        for clause in clauses { did.append(contentsOf: applyClause(normalised(clause), carry: &carry)) }

        if wantsOrder {
            placeOrder()
            return
        }
        if did.isEmpty {
            message = "I did not catch that. Try \u{201C}walnut box\u{201D}, \u{201C}trio\u{201D}, \u{201C}jar 2 octagon crystal with chocolates\u{201D}, \u{201C}silk filling in gold\u{201D}, \u{201C}blush flowers\u{201D} or \u{201C}show unboxing\u{201D}."
        } else {
            message = "Done: " + did.joined(separator: ", ") + "."
        }
    }

    private func splitClauses(_ s: String) -> [String] {
        var out: [String] = []
        var current = ""
        let seps = [",", ";", " and ", " then ", " also ", " with "]
        var rest = s
        while !rest.isEmpty {
            var cut: Range<String.Index>?
            for sep in seps {
                if let r = rest.range(of: sep, options: .caseInsensitive), cut == nil || r.lowerBound < cut!.lowerBound { cut = r }
            }
            guard let r = cut else { current += rest; break }
            current += String(rest[rest.startIndex..<r.lowerBound])
            out.append(current)
            current = ""
            rest = String(rest[r.upperBound...])
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { out.append(current) }
        return out
    }

    private func applyClause(_ c: String, carry: inout [Int]?) -> [String] {
        if c.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        var did: [String] = []
        let mentionsBox = c.contains(" box ") || c.contains(" casing ")
        let jarWords = [" jar ", " jars ", " bottle ", " bottles ", " container ", " containers ", " lid ", " inside "]
        let mentionsJar = jarWords.contains { c.contains($0) }

        let layoutRows = table(GiftCatalogue.layouts, { $0.id }, { $0.words })
        let layoutMatch = match(c, layoutRows)
        if let l = layoutMatch {
            setLayout(l)
            did.append(GiftCatalogue.layout(l).name.lowercased() + " layout")
        }

        let finishRows = table(GiftCatalogue.finishes, { $0.id }, { $0.words })
        if let f = match(c, finishRows) {
            setFinish(f)
            did.append(GiftCatalogue.finish(f).name.lowercased())
        } else if !mentionsJar || mentionsBox {
            let materialRows: [(String, [String])] = [
                ("wood", ["wood", "wooden", "teakwood"]), ("metal", ["metal", "metallic", "brass box"]), ("leather", ["leather"]),
                ("rubber", ["rubber", "soft touch", "soft-touch"]), ("pu", ["pu", "p u", "faux leather", "vegan leather"]),
            ]
            if let m = match(c, materialRows), let mat = BoxMaterial(rawValue: m) {
                setMaterial(mat)
                did.append(mat.title.lowercased() + " box")
            }
        }

        let own = layoutMatch == nil ? slotIndices(c) : nil
        if c.contains(" all ") || c.contains(" every ") || c.contains(" both ") { carry = nil }
        let slots = own ?? (layoutMatch == nil && !(c.contains(" all ") || c.contains(" every ") || c.contains(" both ")) ? carry : nil)
        if own != nil { carry = own }
        let targets: [Int] = slots ?? Array(0..<config.jars.count)

        let styleRows = table(GiftCatalogue.jarStyles, { $0.id }, { $0.words })
        if let s = match(c, styleRows) {
            if slots == nil { setAllJarStyle(s) } else { for i in targets { setJar(i) { $0.styleID = s } } }
            did.append(GiftCatalogue.jarStyle(s).name.lowercased())
        }

        let matRows = table(GiftCatalogue.jarMaterials, { $0.id }, { $0.words })
        if let m = match(c, matRows) {
            let ambiguous = m == "metal" || m == "wood"
            if !ambiguous || (mentionsJar && !mentionsBox) {
                for i in targets { setJar(i) { $0.materialID = m } }
                did.append("jar material " + GiftCatalogue.jarMaterial(m).name.lowercased())
            }
        }

        let sizeRows: [(String, [String])] = [("S", ["small", "smaller", "mini"]), ("M", ["medium", "regular"]), ("L", ["large", "larger", "big", "bigger"])]
        if let sz = match(c, sizeRows), mentionsJar || slots != nil {
            for i in targets { setJar(i) { $0.sizeID = sz } }
            did.append("size " + sz)
        }

        let fillRows = table(GiftCatalogue.fillings, { $0.id }, { $0.words })
        let fillMatch = match(c, fillRows)
        if let f = fillMatch {
            change { $0.fillingID = f }
            did.append(GiftCatalogue.filling(f).name.lowercased())
        }
        if fillMatch != nil || c.contains(" filling ") || c.contains(" fill ") {
            if let hex = colourIn(c) {
                change { $0.fillingHex = hex }
                did.append("filling colour")
            }
        }

        let contentRows = table(GiftCatalogue.contents, { $0.id }, { $0.words })
        let namesStyle = c.contains(" perfume bottle ") || c.contains(" diffuser bottle ") || c.contains(" candle bowl ")
        if let ct = match(c, contentRows), !(fillMatch != nil && ct == "potpourri"), !namesStyle {
            let useAll = slots == nil
            for i in targets { setJar(i) { $0.contentID = ct } }
            did.append(GiftCatalogue.content(ct).name.lowercased() + (useAll ? " in every jar" : " in jar \((targets.first ?? 0) + 1)"))
        }

        let flowerRows = table(GiftCatalogue.flowers, { $0.id }, { $0.words })
        if let fl = match(c, flowerRows), fillMatch == nil || fl == "none" {
            change { $0.flowerID = fl }
            did.append(GiftCatalogue.flower(fl).name.lowercased() + " on the lid")
        }
        return did
    }

    private func colourIn(_ c: String) -> String? {
        var best: String?
        var bestLen = 0
        for (name, hex) in GiftColor.names where c.contains(" " + name + " ") && name.count > bestLen {
            best = hex
            bestLen = name.count
        }
        return best
    }
}

// MARK: - Card

struct GiftCardArt: View {
    let config: GiftConfig
    var compact: Bool = false

    private var colors: (bg: Color, ink: Color, accent: Color) {
        switch config.cardStyle {
        case "modern": return (Color.white, Color(wishHex: "#1E1E22"), Color(wishHex: config.finish.hex))
        case "festive": return (Color(wishHex: "#FFE9C7"), Color(wishHex: "#5A2A0A"), Color(wishHex: "#E67E00"))
        case "dark": return (Color(wishHex: "#1F1B2E"), Color(wishHex: "#F6EBD0"), Color(wishHex: "#D4A84A"))
        default: return (Color(wishHex: "#FBF4E6"), Color(wishHex: "#3A2A20"), Color(wishHex: config.finish.hardwareHex))
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
                .fill(RadialGradient(colors: [Color(wishHex: "#F7F1E8"), Color(wishHex: "#D9CDBB")], center: .center, startRadius: 20, endRadius: 420))
            content.padding(14)
        }
        .animation(.easeInOut(duration: 0.5), value: state.unboxStep)
    }

    @ViewBuilder
    private var content: some View {
        switch state.view {
        case .closed:
            GiftLidView(config: state.config)
        case .inside:
            GiftBoxTop(config: state.config)
        case .card:
            GiftCardArt(config: state.config, compact: false).aspectRatio(1.45, contentMode: .fit).padding(8)
        case .unbox:
            unbox
        }
    }

    @ViewBuilder
    private var unbox: some View {
        if state.unboxStep == 0 {
            GiftLidView(config: state.config)
        } else if state.unboxStep == 1 {
            ZStack {
                GiftBoxTop(config: state.config, jarsShown: 0)
                GiftLidView(config: state.config).offset(y: -26).opacity(0.45).scaleEffect(1.03)
            }
        } else {
            ZStack(alignment: .bottomTrailing) {
                GiftBoxTop(config: state.config, jarsShown: state.unboxStep == 2 ? 0 : (state.unboxStep >= 4 ? 99 : state.itemsShown))
                if state.unboxStep >= 6 {
                    GiftCardArt(config: state.config, compact: false).aspectRatio(1.45, contentMode: .fit).frame(width: 190).padding(10).transition(.opacity)
                }
            }
        }
    }
}

// MARK: - The Gifting page

struct GiftingView: View {
    @ObservedObject var state: GiftingState

    var body: some View {
        HStack(spacing: 0) {
            leftPane.frame(minWidth: 420)
            Divider().overlay(WishTheme.line)
            controls.frame(minWidth: 400, idealWidth: 470, maxWidth: 540)
        }
        .background(WishTheme.page)
    }

    // MARK: Left: the box, drawn to scale

    private var leftPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VYBES gift box").font(.system(size: 20, weight: .bold, design: .serif))
                        Text("One box size, 34 \u{00D7} 24 \u{00D7} 9 cm. You change the finish, the jars, what is inside and the filling.")
                            .font(.caption).foregroundStyle(WishTheme.muted)
                    }
                    Spacer()
                    VybesLogoView().frame(width: 92, height: 58)
                }
                HStack {
                    Picker("", selection: Binding(get: { state.view }, set: { state.show($0) })) {
                        ForEach(GiftView.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Spacer(minLength: 12)
                    Text(giftRupees(state.config.unitPrice)).font(.system(size: 22, weight: .bold)).foregroundStyle(WishTheme.accent)
                }
                GiftStage(state: state).frame(height: 400)
                stageCaption
                banner
                specCard
                otherJars
            }
            .padding(16)
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

    private var banner: some View {
        Text(state.message)
            .font(.system(size: 12, weight: .medium))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(WishTheme.accentSoft))
    }

    private func specRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(.system(size: 12, weight: .semibold)).frame(width: 110, alignment: .leading)
            Text(v).font(.system(size: 12)).foregroundStyle(WishTheme.ink)
            Spacer()
        }
    }

    private var specCard: some View {
        let f = state.config.finish
        return VStack(alignment: .leading, spacing: 5) {
            Text("The box").font(.system(size: 14, weight: .bold))
            specRow("Material", "\(f.material.title) \u{00B7} \(f.name)")
            specRow("Outer size", "\(GiftBoxSpec.cm(GiftBoxSpec.outerW)) \u{00D7} \(GiftBoxSpec.cm(GiftBoxSpec.outerD)) \u{00D7} \(GiftBoxSpec.cm(GiftBoxSpec.height)) cm (same for every finish)")
            specRow("Wall", "\(GiftBoxSpec.cm(GiftBoxSpec.wall)) cm")
            specRow("Inside", "\(GiftBoxSpec.cm(GiftBoxSpec.innerW)) \u{00D7} \(GiftBoxSpec.cm(GiftBoxSpec.innerD)) cm, \(GiftBoxSpec.cm(GiftBoxSpec.innerHeight)) cm deep")
            specRow("Finish", f.material.detail)
            Text("Size is a proposed design size. Prices are placeholders until real ones are set.")
                .font(.caption2).foregroundStyle(WishTheme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WishTheme.line, lineWidth: 1))
    }

    private var otherJars: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Same box, other jars").font(.system(size: 14, weight: .bold))
            Text("Tap one to put that jar in every slot. The box does not change.").font(.caption).foregroundStyle(WishTheme.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(GiftCatalogue.jarStyles) { style in
                    Button { state.setAllJarStyle(style.id) } label: {
                        VStack(spacing: 3) {
                            GiftBoxTop(config: sample(style), jarsShown: 99, dims: false, detail: false)
                                .aspectRatio(CGFloat(GiftBoxSpec.outerW / GiftBoxSpec.outerD), contentMode: .fit)
                            Text(style.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(WishTheme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sample(_ style: JarStyle) -> GiftConfig {
        var c = state.config
        for i in 0..<c.jars.count { c.jars[i].styleID = style.id }
        return c
    }

    // MARK: Right: controls

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                finishSection
                layoutSection
                jarsSection
                fillingSection
                flowerSection
                priceSection
                cardSection
                noteSection
                orderSection
            }
            .padding(16)
        }
    }

    private func sectionTitle(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(t).font(.system(size: 14, weight: .bold))
            Text(sub).font(.caption).foregroundStyle(WishTheme.muted)
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12)).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? WishTheme.accentSoft : Color.white))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? WishTheme.accent : WishTheme.line, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    // 1. Finish

    private var finishSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("1. Box material and finish", "Same size. Only the material and finish change. Say \u{201C}black leather box\u{201D}.")
            HStack(spacing: 6) {
                ForEach(BoxMaterial.allCases, id: \.self) { m in
                    chip(m.title, on: state.config.finish.material == m) { state.setMaterial(m) }
                }
            }
            HStack(spacing: 10) {
                ForEach(GiftCatalogue.finishList(of: state.config.finish.material)) { f in
                    Button { state.setFinish(f.id) } label: {
                        VStack(spacing: 4) {
                            GiftMaterialChip(finish: f).frame(width: 92, height: 62)
                            Text(f.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        }
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: 10).fill(state.config.finishID == f.id ? WishTheme.accentSoft : Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(state.config.finishID == f.id ? WishTheme.accent : WishTheme.line, lineWidth: state.config.finishID == f.id ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // 2. Layout

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("2. How many jars", "Slots are measured inside the box. Say \u{201C}trio\u{201D} or \u{201C}centre and sides\u{201D}.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(GiftCatalogue.layouts) { l in
                    Button { state.setLayout(l.id) } label: {
                        VStack(spacing: 4) {
                            GiftLayoutChip(layout: l).frame(height: 54)
                            Text(l.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(state.config.layoutID == l.id ? WishTheme.accentSoft : Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(state.config.layoutID == l.id ? WishTheme.accent : WishTheme.line, lineWidth: state.config.layoutID == l.id ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // 3. Jars

    private var jarsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("3. Jars and what is inside", "Pick the shape, the material, the size and the contents for each jar. Say \u{201C}jar 2 ceramic with cookies\u{201D}.")
            ForEach(0..<state.config.jars.count, id: \.self) { i in
                jarCard(i)
            }
        }
    }

    private func jarCard(_ i: Int) -> some View {
        let jar = state.config.jars[i]
        let layout = state.config.layout
        let slot = layout.slots[min(i, layout.slots.count - 1)]
        let dia = GiftCatalogue.jarDiameter(slot: slot, size: jar.sizeID)
        let clear = (slot.maxD - dia) / 2
        let slotName = i < layout.slotNames.count ? layout.slotNames[i] : ""
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Jar \(i + 1) \u{00B7} \(slotName)").font(.system(size: 13, weight: .bold))
                Spacer()
                Text("\u{00D8} \(GiftBoxSpec.cm(dia)) cm in a \(GiftBoxSpec.cm(slot.maxD)) cm slot \u{00B7} fits, \(GiftBoxSpec.cm(clear)) cm to spare")
                    .font(.caption2).foregroundStyle(Color(wishHex: "#2E7D4F"))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GiftCatalogue.jarStyles) { style in
                        let on = jar.styleID == style.id
                        Button { state.setJar(i) { $0.styleID = style.id } } label: {
                            VStack(spacing: 3) {
                                GiftPhotoView(id: style.photo).frame(width: 84, height: 62).clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(style.name).font(.system(size: 10, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center).frame(width: 84)
                            }
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 10).fill(on ? WishTheme.accentSoft : Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? WishTheme.accent : WishTheme.line, lineWidth: on ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Material").font(.system(size: 11, weight: .semibold)).foregroundStyle(WishTheme.muted)
            HStack(spacing: 6) {
                ForEach(GiftCatalogue.jarMaterials) { m in
                    chip(m.name, on: jar.materialID == m.id) { state.setJar(i) { $0.materialID = m.id } }
                }
            }
            Text("Size").font(.system(size: 11, weight: .semibold)).foregroundStyle(WishTheme.muted)
            HStack(spacing: 6) {
                chip("Small", on: jar.sizeID == "S") { state.setJar(i) { $0.sizeID = "S" } }
                chip("Medium", on: jar.sizeID == "M") { state.setJar(i) { $0.sizeID = "M" } }
                chip("Large", on: jar.sizeID == "L") { state.setJar(i) { $0.sizeID = "L" } }
            }
            Text("Inside the jar").font(.system(size: 11, weight: .semibold)).foregroundStyle(WishTheme.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(GiftCatalogue.contents) { ct in
                    chip(ct.price > 0 ? "\(ct.name) +\(giftRupees(ct.price))" : ct.name, on: jar.contentID == ct.id) { state.setJar(i) { $0.contentID = ct.id } }
                }
            }
            if state.config.jars.count > 1 {
                Button("Copy jar \(i + 1) to all jars") { state.applyToAllJars(from: i) }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WishTheme.line, lineWidth: 1))
    }

    // 4. Filling

    private var fillingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("4. Filling between the jars", "Decorative filling in the gaps. Say \u{201C}golden beads\u{201D} or \u{201C}silk filling in blush\u{201D}.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(GiftCatalogue.fillings) { f in
                    chip(f.price > 0 ? "\(f.name) +\(giftRupees(f.price))" : f.name, on: state.config.fillingID == f.id) { state.change { $0.fillingID = f.id } }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 26), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(GiftColor.swatches, id: \.self) { hex in
                    Button { state.change { $0.fillingHex = hex } } label: {
                        Circle().fill(Color(wishHex: hex)).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(WishTheme.line, lineWidth: 1))
                            .overlay(Circle().stroke(WishTheme.accent, lineWidth: state.config.fillingHex.lowercased() == hex.lowercased() ? 3 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // 5. Flowers

    private var flowerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("5. Flowers on the lid", "Flowers are decoration on top of the box, not inside it. Switch to Closed to see them.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(GiftCatalogue.flowers) { f in
                    chip(f.price > 0 ? "\(f.name) +\(giftRupees(f.price))" : f.name, on: state.config.flowerID == f.id) {
                        state.change { $0.flowerID = f.id }
                        state.show(.closed)
                    }
                }
            }
        }
    }

    // Price

    private func priceRow(_ k: String, _ v: Int) -> some View {
        HStack { Text(k); Spacer(); Text(giftRupees(v)) }.font(.system(size: 12))
    }

    private var priceSection: some View {
        let c = state.config
        return VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Price", "Placeholder prices, between \(giftRupees(GiftRange.min)) and \(giftRupees(GiftRange.max)) per gift.")
            priceRow("\(c.finish.name) box (\(c.finish.material.title))", c.boxPrice)
            ForEach(0..<c.jars.count, id: \.self) { i in
                let j = c.jars[i]
                priceRow("Jar \(i + 1): \(GiftCatalogue.jarStyle(j.styleID).name), \(GiftCatalogue.jarMaterial(j.materialID).name), \(GiftCatalogue.content(j.contentID).name.lowercased())",
                         c.jarPrice(j) + GiftCatalogue.content(j.contentID).price)
            }
            priceRow("Filling: \(GiftCatalogue.filling(c.fillingID).name)", c.fillingPrice)
            priceRow("Lid: \(GiftCatalogue.flower(c.flowerID).name)", c.flowerPrice)
            Divider()
            HStack {
                Text("One gift").font(.system(size: 14, weight: .bold))
                Spacer()
                Text(giftRupees(c.unitPrice)).font(.system(size: 16, weight: .bold)).foregroundStyle(WishTheme.accent)
            }
            if c.unitPrice < GiftRange.min {
                Text("Add contents or a lid decoration: a gift starts at \(giftRupees(GiftRange.min)).").font(.caption).foregroundStyle(Color(wishHex: "#B45309"))
            } else if c.unitPrice > GiftRange.max {
                Text("Over \(giftRupees(GiftRange.max)): choose a smaller jar or fewer contents.").font(.caption).foregroundStyle(Color(wishHex: "#B45309"))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WishTheme.line, lineWidth: 1))
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
                Button("Undo") { state.undo() }.buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private var orderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Place order", "Say \u{201C}order name Asha, phone 9876543210, address 12 MG Road, place order\u{201D}.")
            HStack(spacing: 8) {
                field("Name", "Asha", Binding(get: { state.config.customer }, set: { state.config.customer = $0 }))
                field("Phone", "9876543210", Binding(get: { state.config.phone }, set: { state.config.phone = $0 }))
            }
            field("Delivery address", "12 MG Road, Pune", Binding(get: { state.config.address }, set: { state.config.address = $0 }))
            Stepper("Quantity: \(state.config.quantity)", value: Binding(get: { state.config.quantity }, set: { state.config.quantity = max(1, min(500, $0)) }), in: 1...500)
            HStack {
                Text("Total for \(state.config.quantity)").font(.system(size: 14, weight: .bold))
                Spacer()
                Text(giftRupees(state.config.total)).font(.system(size: 16, weight: .bold)).foregroundStyle(WishTheme.accent)
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
