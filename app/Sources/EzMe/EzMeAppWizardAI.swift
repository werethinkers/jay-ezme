// Creative AI help for the New App wizard: a design pass that places boxes and picks fonts and colours, and "upload a
// reference" that reads a picture or PDF of an existing form and builds the variables and fixed text from it.
import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Looks of one box that AI (or the person) chose. Empty values mean "leave the default".
struct WizardStyle: Equatable {
    var fontName = ""
    var fontSize = 0.0
    var bold = false
    var italic = false
    var colorHex = ""
    var fillHex = ""
    var align = ""
    var uppercase = false

    var isEmpty: Bool { self == WizardStyle() }

    func apply(to slot: inout TemplateSlot) {
        if !fontName.isEmpty { slot.fontName = fontName }
        if fontSize > 0 { slot.fontSize = fontSize }
        slot.bold = bold || slot.bold
        slot.italic = italic || slot.italic
        if !colorHex.isEmpty { slot.colorHex = colorHex }
        if !fillHex.isEmpty { slot.fillHex = fillHex }
        if !align.isEmpty { slot.align = align }
        if uppercase { slot.uppercase = true }
    }

    /// Reads font, size, color, fill, bold, italic, align and uppercase from one JSON item.
    static func from(_ item: [String: Any]) -> WizardStyle {
        var style = WizardStyle()
        if let font = item["font"] as? String, let real = Self.installedFont(font) { style.fontName = real }
        if let size = (item["size"] as? Double) ?? (item["size"] as? Int).map(Double.init), size > 0 { style.fontSize = min(0.14, max(0.012, size)) }
        style.bold = (item["bold"] as? Bool) ?? false
        style.italic = (item["italic"] as? Bool) ?? false
        style.uppercase = (item["uppercase"] as? Bool) ?? false
        if let color = hex(item["color"]) { style.colorHex = color }
        if let fill = hex(item["fill"]) { style.fillHex = fill }
        if let align = (item["align"] as? String)?.lowercased(), ["left", "center", "right"].contains(align) { style.align = align }
        return style
    }

    static func hex(_ value: Any?) -> String? {
        guard var text = (value as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if !text.hasPrefix("#") { text = "#" + text }
        let digits = text.dropFirst()
        guard digits.count == 6, digits.allSatisfy({ $0.isHexDigit }) else { return nil }
        return text.uppercased()
    }

    static func installedFont(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if NSFont(name: trimmed, size: 12) != nil { return trimmed }
        return nil
    }

    /// Fonts that ship with every Mac, offered to AI so the result always renders.
    static let palette = "Helvetica Neue, Avenir Next, Futura, Optima, Gill Sans, Georgia, Palatino, Baskerville, Didot, Copperplate, Snell Roundhand, Marker Felt, American Typewriter, Menlo"
}

extension NewAppWizardModel {
    private func aiProfile() -> (CollectionAIModelProfile, String) {
        let profiles = AIModelProfileStore.load()
        let selectedID = UserDefaults.standard.string(forKey: "ezmeSelectedAIModelProfile") ?? UserDefaults.standard.string(forKey: "ezmeCollectionSelectedProfile") ?? CollectionAIModelProfile.starter.id
        let profile = profiles.first(where: { $0.id == selectedID }) ?? .starter
        return (profile, KeyStore.load(account: profile.keyAccount) ?? "")
    }

    /// Step 2: upload a picture or PDF of an app you like. AI works out what changes each time (variables) and what stays
    /// (fixed text), and lays the boxes out like the reference.
    func importReference() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.message = "Choose a picture or PDF of the form, card or app you want to copy."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let (profile, key) = aiProfile()
        guard !key.isEmpty else { message = "Reference reading needs an AI key. Add one in Setup, then try again."; return }
        guard let jpeg = Self.referenceJPEG(url) else { message = "I could not read that file as a picture."; return }
        let prompt = """
        This image is a reference for an app that makes a \(kind.title.lowercased()). Work out which pieces change every time the app is used and which stay the same.
        Things that change (a person's name, a date, an amount, an invoice number, an address, a phone number, a photo) are "variable" boxes, or "picture" for photos.
        Things that stay the same (headings, labels like "Bill to", the company name, a tagline, fixed wording, terms) are "text" boxes with exactly those words.
        Ignore the logo, it already has its own spot. For each variable put a believable example in "text". The new page has width divided by height of \(String(format: "%.3f", aspect)); give positions as fractions of the page (cx, cy centre, w, h size), matching the reference layout.
        Also read the look: "font" from this list only: \(WizardStyle.palette). "size" is the text height as a fraction of page height (0.02 small, 0.05 heading), "color" and "fill" are hex like #1F2A2E (fill may be empty), "bold", "italic", "uppercase" are true or false, "align" is left, center or right.
        For a variable also give "type": one of text, long, number, whole, currency, date, time, phone, email, link, and "name" as a short_snake_case word.
        Reply with ONLY JSON: {"appName": "...", "items": [{"kind":"variable|text|picture","name":"...","type":"text","text":"...","cx":0.5,"cy":0.3,"w":0.6,"h":0.06,"font":"Georgia","size":0.04,"color":"#222222","fill":"","bold":true,"italic":false,"uppercase":false,"align":"center"}]}. At most 24 items.
        """
        busy = true
        message = "Reading the reference\u{2026}"
        Task { [weak self] in
            guard let self else { return }
            do {
                let reply = try await SharedAIClient.generate(profile: profile, key: key, prompt: prompt, images: [(jpeg, "image/jpeg")], maxTokens: 4000)
                self.applyReference(reply)
            } catch {
                self.busy = false
                self.message = "AI could not be reached, so nothing was added. Check the key and try again."
            }
        }
    }

    private func applyReference(_ reply: String) {
        busy = false
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let data = String(reply[start...end]).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]], !items.isEmpty else {
            message = "AI answered in a way I could not use. Try a clearer picture."
            return
        }
        var variables = 0, fixed = 0, pictures = 0
        for item in items.prefix(24) {
            func number(_ name: String) -> Double? { (item[name] as? Double) ?? (item[name] as? Int).map(Double.init) }
            let kindWord = (item["kind"] as? String ?? "text").lowercased()
            let sample = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let base = TemplateFill.normal(item["name"] as? String ?? "")
            var e: WizardElement
            switch kindWord {
            case "variable":
                e = WizardElement(kind: .variable, name: uniqueName(base.isEmpty ? "variable" : base))
                if let word = item["type"] as? String, let type = DesignDataType(rawValue: word.lowercased()) { e.type = type }
                let check = e.type.check(sample)
                e.defaultValue = check.ok ? check.clean : ""
                variables += 1
            case "picture":
                e = WizardElement(kind: .picture, name: uniqueName(base.isEmpty ? "photo" : base))
                pictures += 1
            default:
                guard !sample.isEmpty else { continue }
                e = WizardElement(kind: .text, name: uniqueName(base.isEmpty ? "label" : base))
                e.text = sample
                fixed += 1
            }
            if let cx = number("cx"), let cy = number("cy"), let w = number("w"), let h = number("h") {
                e.w = min(0.95, max(0.05, w)); e.h = min(0.6, max(0.03, h))
                e.cx = min(1 - e.w / 2, max(e.w / 2, cx))
                e.cy = min(1 - e.h / 2, max(e.h / 2, cy))
            }
            e.style = WizardStyle.from(item)
            elements.append(e)
        }
        if let name = root["appName"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty,
           appName == kind.title || appName == "My app" || appName.isEmpty {
            appName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            command = Self.suggestCommand(appName)
        }
        commit()
        message = "From the reference: \(variables) variable\(variables == 1 ? "" : "s"), \(fixed) fixed text\(fixed == 1 ? "" : "s")\(pictures > 0 ? ", \(pictures) picture box\(pictures == 1 ? "" : "es")" : ""). Fix any box that is not right, or ask AI to polish the look."
    }

    /// The first page of a PDF, or the picture itself, shrunk and saved as a JPEG for the AI.
    static func referenceJPEG(_ url: URL) -> Data? {
        var image: NSImage?
        if url.pathExtension.lowercased() == "pdf" {
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            let box = page.bounds(for: .mediaBox)
            let scale = 1500 / max(box.width, box.height)
            image = page.thumbnail(of: NSSize(width: box.width * scale, height: box.height * scale), for: .mediaBox)
        } else {
            image = NSImage(contentsOf: url)
        }
        guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let longest = Double(max(rep.pixelsWide, rep.pixelsHigh))
        var output = rep
        if longest > 1600, let source = rep.cgImage {
            let scale = 1600 / longest
            let width = Int(Double(rep.pixelsWide) * scale), height = Int(Double(rep.pixelsHigh) * scale)
            if let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                context.interpolationQuality = .high
                context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
                if let small = context.makeImage() { output = NSBitmapImageRep(cgImage: small) }
            }
        }
        return output.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
