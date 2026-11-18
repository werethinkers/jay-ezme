// A pack of ready-made AppDesigner templates: greeting card, offer letter, leave application, product catalogue,
// discount offer, product ad, appointment letter (two pages), invitation, save the date with a countdown, certificate,
// festival countdown story, hiring post and quotation. Each one is a design with variables, so it works as an app once published.
import SwiftUI
import AppKit

/// One page being laid out. Positions are the top left corner and the size, as fractions of the page.
private struct Sheet {
    let width: Double
    let height: Double
    var slots: [TemplateSlot] = []

    init(width: Double, height: Double) { self.width = width; self.height = height }

    mutating func text(_ key: String, _ content: String, x: Double, y: Double, w: Double, h: Double, size: Double = 0.02, bold: Bool = false,
                       italic: Bool = false, color: String = "#2B1E45", align: String = "center", font: String = "Helvetica Neue",
                       upper: Bool = false, fill: String = "", shape: TemplateShape = .rectangle, angle: Double = 0) {
        var box = TemplateSlot(key: key, kind: .text)
        box.cx = x + w / 2; box.cy = y + h / 2; box.w = w; box.h = h
        box.content = content; box.sample = content
        box.fontName = font; box.fontSize = size; box.bold = bold; box.italic = italic
        box.colorHex = color; box.align = align; box.uppercase = upper; box.fillHex = fill
        box.shape = shape; box.angle = angle
        slots.append(box)
    }

    /// A coloured block with nothing written in it. It holds a space so it never becomes a question in the form.
    mutating func block(_ name: String, x: Double, y: Double, w: Double, h: Double, fill: String, angle: Double = 0) {
        text(name, " ", x: x, y: y, w: w, h: h, fill: fill, angle: angle)
    }

    /// A round dot. `d` is the width as a fraction of the page width; the height is worked out so it stays round.
    mutating func dot(_ name: String, x: Double, y: Double, d: Double, fill: String) {
        text(name, " ", x: x, y: y, w: d, h: d * width / height, fill: fill, shape: .circle)
    }

    mutating func photo(_ key: String, x: Double, y: Double, w: Double, h: Double, shape: TemplateShape = .rectangle, angle: Double = 0) {
        var box = TemplateSlot(key: key, kind: .image)
        box.cx = x + w / 2; box.cy = y + h / 2; box.w = w; box.h = h
        box.shape = shape; box.angle = angle
        box.sample = "Picture"
        slots.append(box)
    }

    /// A round picture of width `d` (fraction of the page width).
    mutating func roundPhoto(_ key: String, x: Double, y: Double, d: Double) {
        photo(key, x: x, y: y, w: d, h: d * width / height, shape: .circle)
    }
}

@MainActor enum StarterPack {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let make: @MainActor () -> AppDesign?
    }

    private static let installedKey = "ezmeStarterPackInstalled.v1"

    /// The collection whose name has one of these words in it, if the person has one.
    private static func collection(like words: [String]) -> String? {
        AppDesignContext.shared.collections.first { name in words.contains { name.lowercased().contains($0) } }
    }

    private static func wishToken(_ words: [String]) -> String? {
        collection(like: words).map { WishPick.token(collection: $0) }
    }

    /// Adds the whole pack, once. Later it is only added when the person asks for it.
    static func installOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: installedKey) else { return }
        defaults.set(true, forKey: installedKey)
        for entry in entries { _ = entry.make() }
    }

    static func installAll() -> Int { entries.reduce(0) { $0 + ($1.make() == nil ? 0 : 1) } }

    // MARK: Building

    private static func build(_ name: String, width: Int, height: Int, color: String, format: DesignFormat, variables: [String: String],
                              pages: [(inout Sheet) -> Void]) -> AppDesign? {
        let store = AppDesignStore.shared
        guard let started = store.newBlank(name: name, width: width, height: height, colorHex: color),
              let firstID = started.pages.first, let first = TemplateStore.shared.template(id: firstID) else { return nil }
        for (index, layout) in pages.enumerated() {
            var page: ImageTemplate
            if index == 0 { page = first } else {
                guard let added = store.addPage(to: started.id, like: first) else { continue }
                page = added
            }
            var sheet = Sheet(width: Double(width), height: Double(height))
            layout(&sheet)
            page.slots = sheet.slots
            TemplateStore.shared.save(page)
        }
        guard var design = store.design(id: started.id) else { return nil }
        design.variables = variables
        design.outputFormat = format.rawValue
        design.appTitle = design.name
        store.save(design)
        return design
    }

    static var entries: [Entry] {
        [
            Entry(id: "greeting", title: "Greeting card", detail: "Photo in a ring, name and a wish from your collection. Image.", symbol: "party.popper.fill", make: greetingCard),
            Entry(id: "offer", title: "Offer letter", detail: "One page with letterhead, terms table and signature. PDF.", symbol: "doc.richtext.fill", make: offerLetter),
            Entry(id: "leave", title: "Leave application", detail: "One page; counts the days between the dates. PDF.", symbol: "calendar.badge.clock", make: leaveApplication),
            Entry(id: "catalogue", title: "Product catalogue page", detail: "One product with photo, price badge and three features. PDF.", symbol: "shippingbox.fill", make: productCatalogue),
            Entry(id: "discount", title: "Discount offer", detail: "Big percent-off burst, new price, code and valid-till date. Image.", symbol: "tag.fill", make: discountOffer),
            Entry(id: "ad", title: "Product ad", detail: "Headline, round product photo, benefit pills and a button. Image.", symbol: "megaphone.fill", make: productAd),
            Entry(id: "appointment", title: "Appointment letter (2 pages)", detail: "Letter with details table, then terms and acceptance. PDF.", symbol: "doc.on.doc.fill", make: appointmentLetter),
            Entry(id: "invite", title: "Invitation", detail: "Gold on midnight: event, host, date, venue and RSVP. Image.", symbol: "envelope.open.fill", make: invitation),
            Entry(id: "savethedate", title: "Save the date with countdown", detail: "Counts the days to go from today. Image.", symbol: "heart.circle.fill", make: saveTheDate),
            Entry(id: "certificate", title: "Certificate of appreciation", detail: "Wide certificate with a gold seal. PDF.", symbol: "rosette", make: certificate),
            Entry(id: "festival", title: "Festival countdown story", detail: "Tall story with days-to-go and your wish. Image.", symbol: "sparkles", make: festivalStory),
            Entry(id: "hiring", title: "We are hiring post", detail: "Role, three requirements, pay and how to apply. Image.", symbol: "person.badge.plus", make: hiringPost),
            Entry(id: "quotation", title: "Quotation", detail: "Three items; works out amounts, GST and total. PDF.", symbol: "indianrupeesign.circle.fill", make: quotation)
        ]
    }

    // MARK: 1. Greeting card

    private static func greetingCard() -> AppDesign? {
        let wish = wishToken(["hbd", "birthday"])
        var vars = ["occasion": "Birthday", "name": "Rahul", "from": "Priya"]
        if wish == nil { vars["message"] = "Wishing you a day full of joy and a year full of success." }
        return build("Greeting card", width: 1080, height: 1350, color: "#FFF1E0", format: .png, variables: vars, pages: [{ s in
            s.block("Top band", x: 0, y: 0, w: 1, h: 0.07, fill: "#FF6B6B")
            s.dot("Confetti 1", x: 0.06, y: 0.11, d: 0.05, fill: "#06D6A0")
            s.dot("Confetti 2", x: 0.89, y: 0.10, d: 0.045, fill: "#118AB2")
            s.dot("Confetti 3", x: 0.05, y: 0.33, d: 0.035, fill: "#118AB2")
            s.dot("Confetti 4", x: 0.91, y: 0.36, d: 0.04, fill: "#06D6A0")
            s.dot("Confetti 5", x: 0.08, y: 0.52, d: 0.04, fill: "#FFD166")
            s.dot("Confetti 6", x: 0.88, y: 0.55, d: 0.05, fill: "#EF476F")
            s.text("Title", "Happy {{occasion}}!", x: 0.05, y: 0.085, w: 0.9, h: 0.095, size: 0.075, bold: true, color: "#D1495B", font: "Snell Roundhand")
            s.dot("Ring", x: 0.25, y: 0.195, d: 0.5, fill: "#FFD166")
            s.roundPhoto("Photo", x: 0.28, y: 0.219, d: 0.44)
            s.text("Name", "{{name}}", x: 0.08, y: 0.62, w: 0.84, h: 0.07, size: 0.05, bold: true, color: "#2B1E45", font: "Didot")
            s.text("Message", wish ?? "{{message}}", x: 0.09, y: 0.705, w: 0.82, h: 0.155, size: 0.026, italic: true, color: "#5A4A6A", fill: "#FFFFFF")
            s.text("From", "With love, {{from}}", x: 0.1, y: 0.875, w: 0.8, h: 0.05, size: 0.03, bold: true, color: "#D1495B")
            s.block("Bottom band", x: 0, y: 0.94, w: 1, h: 0.06, fill: "#FF6B6B")
        }])
    }

    // MARK: 2. Offer letter

    private static func offerLetter() -> AppDesign? {
        let vars = ["company": "Acme Pvt Ltd", "companyaddress": "12 Park Street, Mumbai", "companycontact": "hr@acme.com", "date": "{=TODAY()}", "refno": "HR/OFFER/001",
                    "candidate": "Rahul Sharma", "address": "Andheri East, Mumbai", "role": "Marketing Manager", "department": "Marketing", "ctc": "\u{20B9}12,00,000 per year",
                    "joining": "{=Date+30}", "reporting": "Head of Marketing", "location": "Mumbai", "probation": "3 months", "acceptby": "{=Date+7}",
                    "signatory": "Priya Mehta", "signtitle": "Head of HR"]
        return build("Offer letter", width: 1654, height: 2339, color: "#FFFFFF", format: .pdf, variables: vars, pages: [{ s in
            s.block("Letterhead", x: 0, y: 0, w: 1, h: 0.1, fill: "#1F3A5F")
            s.text("Company", "{{company}}", x: 0.06, y: 0.027, w: 0.55, h: 0.046, size: 0.032, bold: true, color: "#FFFFFF", align: "left", font: "Didot", upper: true)
            s.text("Letter kind", "Offer of employment", x: 0.55, y: 0.033, w: 0.39, h: 0.034, size: 0.016, color: "#F2A541", align: "right", upper: true)
            s.block("Accent line", x: 0, y: 0.1, w: 1, h: 0.006, fill: "#F2A541")
            s.text("Date line", "Date: {{date}}", x: 0.06, y: 0.13, w: 0.4, h: 0.03, size: 0.014, align: "left")
            s.text("Reference", "Ref: {{refno}}", x: 0.54, y: 0.13, w: 0.4, h: 0.03, size: 0.014, align: "right")
            s.text("Address block", "To,\n{{candidate}}\n{{address}}", x: 0.06, y: 0.175, w: 0.5, h: 0.085, size: 0.0145, align: "left")
            s.text("Subject", "Subject: Offer of employment for the position of {{role}}", x: 0.06, y: 0.275, w: 0.88, h: 0.04, size: 0.0155, bold: true, color: "#1F3A5F", align: "left")
            s.text("Greeting", "Dear {{candidate}},", x: 0.06, y: 0.325, w: 0.6, h: 0.03, size: 0.0145, align: "left")
            s.text("Opening", "We are delighted to offer you the position of {{role}} in our {{department}} team at {{company}}. We were impressed by your skills and experience, and we believe you will be a valuable addition to us. The main terms of your employment are below.", x: 0.06, y: 0.36, w: 0.88, h: 0.085, size: 0.0138, align: "left")
            s.block("Terms box", x: 0.06, y: 0.455, w: 0.88, h: 0.2, fill: "#EEF3FA")
            let rows: [(String, String)] = [("Position", "{{role}}"), ("Annual CTC", "{{ctc}}"), ("Date of joining", "{{joining}}"), ("Reporting to", "{{reporting}}"), ("Work location", "{{location}}"), ("Probation", "{{probation}}")]
            for (index, row) in rows.enumerated() {
                let y = 0.465 + Double(index) * 0.0315
                s.text("Term label \(index + 1)", row.0, x: 0.09, y: y, w: 0.28, h: 0.028, size: 0.0138, bold: true, color: "#1F3A5F", align: "left")
                s.text("Term value \(index + 1)", row.1, x: 0.4, y: y, w: 0.52, h: 0.028, size: 0.0138, align: "left")
            }
            s.text("Conditions", "This offer depends on satisfactory background verification and on you sharing the documents listed by HR. Please sign and return a copy of this letter by {{acceptby}} to confirm that you accept.", x: 0.06, y: 0.675, w: 0.88, h: 0.07, size: 0.0138, align: "left")
            s.text("Welcome", "We look forward to welcoming you to the team.", x: 0.06, y: 0.755, w: 0.88, h: 0.03, size: 0.0138, italic: true, align: "left")
            s.text("Sign off", "Yours sincerely,\n\n\n{{signatory}}\n{{signtitle}}, {{company}}", x: 0.06, y: 0.81, w: 0.4, h: 0.125, size: 0.0138, align: "left")
            s.text("Acceptance", "I accept this offer.\n\n\n______________________\n{{candidate}}      Date: ____________", x: 0.52, y: 0.81, w: 0.42, h: 0.125, size: 0.0138, align: "left")
            s.block("Footer band", x: 0, y: 0.962, w: 1, h: 0.038, fill: "#1F3A5F")
            s.text("Footer", "{{company}}  \u{00B7}  {{companyaddress}}  \u{00B7}  {{companycontact}}", x: 0.05, y: 0.969, w: 0.9, h: 0.024, size: 0.0115, color: "#FFFFFF")
        }])
    }

    // MARK: 3. Leave application

    private static func leaveApplication() -> AppDesign? {
        let vars = ["name": "Rahul Sharma", "designation": "Marketing Executive", "department": "Marketing", "empid": "EMP-1042", "date": "{=TODAY()}",
                    "manager": "Priya Mehta", "company": "Acme Pvt Ltd", "leavetype": "casual leave", "fromdate": "{=Date+10}", "todate": "{=Date+12}",
                    "reason": "a family function", "handover": "my colleague Anita", "phone": "98765 43210"]
        return build("Leave application", width: 1654, height: 2339, color: "#FFFFFF", format: .pdf, variables: vars, pages: [{ s in
            s.block("Side bar", x: 0, y: 0, w: 0.03, h: 1, fill: "#2A9D8F")
            s.text("Title", "Leave application", x: 0.09, y: 0.06, w: 0.7, h: 0.055, size: 0.032, bold: true, color: "#264653", align: "left", font: "Futura", upper: true)
            s.block("Title line", x: 0.09, y: 0.12, w: 0.14, h: 0.005, fill: "#E9C46A")
            s.text("From block", "From,\n{{name}}\n{{designation}}, {{department}}\nEmployee ID: {{empid}}", x: 0.09, y: 0.15, w: 0.5, h: 0.1, size: 0.0145, align: "left")
            s.text("Date", "Date: {{date}}", x: 0.6, y: 0.15, w: 0.31, h: 0.03, size: 0.0145, align: "right")
            s.text("To block", "To,\n{{manager}}\n{{company}}", x: 0.09, y: 0.27, w: 0.5, h: 0.075, size: 0.0145, align: "left")
            s.text("Subject", "Subject: Application for {{leavetype}} from {{fromdate}} to {{todate}}", x: 0.09, y: 0.365, w: 0.82, h: 0.05, size: 0.0155, bold: true, color: "#264653", align: "left")
            s.text("Greeting", "Dear {{manager}},", x: 0.09, y: 0.425, w: 0.6, h: 0.03, size: 0.0145, align: "left")
            s.text("Body", "I would like to request {{leavetype}} from {{fromdate}} to {{todate}} because of {{reason}}. I will finish my pending work and hand it over to {{handover}} before I leave. If anything urgent comes up, you can reach me on {{phone}}.\n\nI kindly request you to approve my leave. Thank you for your understanding.", x: 0.09, y: 0.465, w: 0.82, h: 0.18, size: 0.0145, align: "left")
            s.block("Summary strip", x: 0.09, y: 0.665, w: 0.82, h: 0.075, fill: "#E3F2F0")
            s.text("Summary", "{{fromdate}}   to   {{todate}}   \u{00B7}   {=DAYS(\"{{todate}}\", \"{{fromdate}}\")+1} days", x: 0.1, y: 0.682, w: 0.8, h: 0.04, size: 0.0185, bold: true, color: "#264653")
            s.text("Sign off", "Yours sincerely,\n\n\n{{name}}", x: 0.09, y: 0.775, w: 0.4, h: 0.09, size: 0.0145, align: "left")
            s.block("Office box", x: 0.09, y: 0.885, w: 0.82, h: 0.085, fill: "#F5F5F5")
            s.text("Office use", "FOR OFFICE USE\nApproved  \u{25A1}      Not approved  \u{25A1}      Manager signature: ______________      Date: __________", x: 0.1, y: 0.893, w: 0.8, h: 0.07, size: 0.0125, color: "#555555", align: "left")
        }])
    }

    // MARK: 4. Product catalogue page

    private static func productCatalogue() -> AppDesign? {
        let vars = ["brand": "Green Harvest", "product": "Cold-pressed Coconut Oil", "tagline": "Pure, slow-pressed and bottled the day it is made.", "price": "\u{20B9}449",
                    "unit": "500 ml", "feature1": "100% natural, no additives or preservatives", "feature2": "Cold-pressed in small batches to keep the goodness",
                    "feature3": "Good for cooking, hair and skin", "sku": "GH-CO-500", "size": "500 ml", "stock": "In stock", "contact": "+91 98765 43210", "website": "greenharvest.in"]
        return build("Product catalogue page", width: 1654, height: 2339, color: "#FBF7F0", format: .pdf, variables: vars, pages: [{ s in
            s.block("Hero", x: 0, y: 0, w: 1, h: 0.46, fill: "#1B4332")
            s.text("Brand", "{{brand}}", x: 0.07, y: 0.06, w: 0.4, h: 0.03, size: 0.0135, color: "#95D5B2", align: "left", upper: true)
            s.text("Product", "{{product}}", x: 0.07, y: 0.1, w: 0.4, h: 0.14, size: 0.05, bold: true, color: "#FFFFFF", align: "left", font: "Didot")
            s.text("Tagline", "{{tagline}}", x: 0.07, y: 0.25, w: 0.38, h: 0.07, size: 0.0165, italic: true, color: "#D8F3DC", align: "left")
            s.text("Price badge", "{{price}}", x: 0.07, y: 0.33, w: 0.2, h: 0.2 * 1654 / 2339, size: 0.032, bold: true, color: "#1B4332", fill: "#F4A261", shape: .circle)
            s.text("Unit", "per {{unit}}", x: 0.29, y: 0.385, w: 0.2, h: 0.03, size: 0.015, color: "#D8F3DC", align: "left")
            s.photo("Product photo", x: 0.5, y: 0.06, w: 0.44, h: 0.35, angle: 3)
            s.text("Why heading", "Why you will love it", x: 0.07, y: 0.5, w: 0.6, h: 0.04, size: 0.026, bold: true, color: "#1B4332", align: "left", font: "Didot")
            for index in 0..<3 {
                let y = 0.565 + Double(index) * 0.08
                s.dot("Bullet \(index + 1)", x: 0.07, y: y + 0.006, d: 0.04, fill: "#95D5B2")
                s.text("Feature \(index + 1)", "{{feature\(index + 1)}}", x: 0.13, y: y, w: 0.8, h: 0.06, size: 0.0165, align: "left")
            }
            s.block("Details strip", x: 0, y: 0.82, w: 1, h: 0.075, fill: "#D8F3DC")
            s.text("SKU", "Code: {{sku}}", x: 0.07, y: 0.842, w: 0.28, h: 0.03, size: 0.0145, bold: true, color: "#1B4332", align: "left")
            s.text("Size", "Size: {{size}}", x: 0.38, y: 0.842, w: 0.24, h: 0.03, size: 0.0145, bold: true, color: "#1B4332")
            s.text("Stock", "{{stock}}", x: 0.66, y: 0.842, w: 0.27, h: 0.03, size: 0.0145, bold: true, color: "#1B4332", align: "right")
            s.block("Footer", x: 0, y: 0.91, w: 1, h: 0.09, fill: "#1B4332")
            s.text("Order line", "Order now  \u{00B7}  {{contact}}\n{{website}}", x: 0.05, y: 0.925, w: 0.9, h: 0.06, size: 0.0165, color: "#FFFFFF")
        }])
    }

    // MARK: 5. Discount offer

    private static func discountOffer() -> AppDesign? {
        let vars = ["headline": "Festive\nSale", "discount": "30", "product": "Cold-pressed Coconut Oil", "oldprice": "\u{20B9}449", "newprice": "\u{20B9}314",
                    "code": "FEST30", "validtill": "{=Date+7}", "shop": "Green Harvest", "contact": "greenharvest.in"]
        return build("Discount offer", width: 1080, height: 1080, color: "#0B132B", format: .png, variables: vars, pages: [{ s in
            s.text("Headline", "{{headline}}", x: 0.06, y: 0.06, w: 0.5, h: 0.2, size: 0.07, bold: true, color: "#FFFFFF", align: "left", font: "Futura", upper: true)
            s.dot("Burst outer", x: 0.56, y: 0.03, d: 0.4, fill: "#FF3366")
            s.text("Burst", "{{discount}}%\nOFF", x: 0.6, y: 0.07, w: 0.32, h: 0.32, size: 0.075, bold: true, color: "#FFFFFF", fill: "#FF5C8A", shape: .circle)
            s.dot("Photo ring", x: 0.04, y: 0.28, d: 0.5, fill: "#1C2541")
            s.roundPhoto("Product photo", x: 0.07, y: 0.31, d: 0.44)
            s.text("Product", "{{product}}", x: 0.56, y: 0.45, w: 0.38, h: 0.12, size: 0.04, bold: true, color: "#FFD60A", align: "left")
            s.text("Old price", "Was {{oldprice}}", x: 0.56, y: 0.58, w: 0.38, h: 0.05, size: 0.028, color: "#8D99AE", align: "left")
            s.text("New price", "Now {{newprice}}", x: 0.56, y: 0.64, w: 0.4, h: 0.09, size: 0.06, bold: true, color: "#FFFFFF", align: "left")
            s.block("Code band", x: 0, y: 0.8, w: 1, h: 0.1, fill: "#FFD60A")
            s.text("Code", "Use code {{code}}   \u{00B7}   Valid till {{validtill}}", x: 0.04, y: 0.815, w: 0.92, h: 0.07, size: 0.034, bold: true, color: "#0B132B")
            s.text("Shop", "{{shop}}  \u{00B7}  {{contact}}", x: 0.05, y: 0.925, w: 0.9, h: 0.05, size: 0.028, color: "#FFFFFF")
        }])
    }

    // MARK: 6. Product ad

    private static func productAd() -> AppDesign? {
        let vars = ["headline": "Glow from the inside out", "subline": "Skin care made with plants, not promises.", "benefit1": "100% natural", "benefit2": "Dermatologist tested",
                    "benefit3": "Free delivery", "price": "\u{20B9}599", "pricenote": "Launch price for the first 100 orders", "cta": "Order now", "website": "glowbotanics.in"]
        return build("Product ad", width: 1080, height: 1350, color: "#FFE8D6", format: .png, variables: vars, pages: [{ s in
            s.block("Slant", x: -0.1, y: 0.2, w: 1.2, h: 0.34, fill: "#FFB4A2", angle: -6)
            s.text("Headline", "{{headline}}", x: 0.06, y: 0.04, w: 0.88, h: 0.15, size: 0.07, bold: true, color: "#6D2E46", align: "left", font: "Didot")
            s.text("Subline", "{{subline}}", x: 0.06, y: 0.2, w: 0.88, h: 0.055, size: 0.028, italic: true, color: "#6D2E46", align: "left")
            s.dot("Halo", x: 0.19, y: 0.255, d: 0.62, fill: "#FFFFFF")
            s.roundPhoto("Product photo", x: 0.26, y: 0.292, d: 0.48)
            for index in 0..<3 {
                s.text("Benefit \(index + 1)", "{{benefit\(index + 1)}}", x: 0.06 + Double(index) * 0.3, y: 0.695, w: 0.28, h: 0.05, size: 0.021, bold: true, color: "#FFFFFF", fill: "#6D2E46")
            }
            s.text("Price", "Only {{price}}", x: 0.06, y: 0.765, w: 0.88, h: 0.085, size: 0.07, bold: true, color: "#6D2E46")
            s.text("Price note", "{{pricenote}}", x: 0.06, y: 0.85, w: 0.88, h: 0.04, size: 0.022, italic: true, color: "#8A5A6B")
            s.text("Button", "{{cta}}", x: 0.25, y: 0.9, w: 0.5, h: 0.06, size: 0.03, bold: true, color: "#FFFFFF", fill: "#E56B6F")
            s.text("Website", "{{website}}", x: 0.1, y: 0.965, w: 0.8, h: 0.03, size: 0.02, color: "#6D2E46")
        }])
    }

    // MARK: 7. Appointment letter, two pages

    private static func appointmentLetter() -> AppDesign? {
        let vars = ["company": "Acme Pvt Ltd", "companyaddress": "12 Park Street, Mumbai", "companycontact": "hr@acme.com", "date": "{=TODAY()}", "refno": "HR/APPT/001",
                    "employee": "Rahul Sharma", "address": "Andheri East, Mumbai", "designation": "Marketing Manager", "department": "Marketing", "joining": "{=Date+30}",
                    "location": "Mumbai", "reporting": "Head of Marketing", "probation": "6 months", "ctc": "\u{20B9}12,00,000 per year", "signatory": "Priya Mehta", "signtitle": "Head of HR"]
        let footer: (inout Sheet, Int) -> Void = { s, number in
            s.block("Footer band", x: 0, y: 0.962, w: 1, h: 0.038, fill: "#3D348B")
            s.text("Footer", "{{company}}  \u{00B7}  {{companyaddress}}  \u{00B7}  {{companycontact}}  \u{00B7}  Page \(number) of 2", x: 0.05, y: 0.969, w: 0.9, h: 0.024, size: 0.0115, color: "#FFFFFF")
        }
        return build("Appointment letter", width: 1654, height: 2339, color: "#FFFFFF", format: .pdf, variables: vars, pages: [{ s in
            s.block("Letterhead", x: 0, y: 0, w: 1, h: 0.09, fill: "#3D348B")
            s.text("Company", "{{company}}", x: 0.06, y: 0.022, w: 0.6, h: 0.046, size: 0.032, bold: true, color: "#FFFFFF", align: "left", font: "Didot", upper: true)
            s.block("Accent line", x: 0, y: 0.09, w: 1, h: 0.006, fill: "#F7B801")
            s.text("Title", "Appointment letter", x: 0.06, y: 0.115, w: 0.88, h: 0.045, size: 0.027, bold: true, color: "#3D348B", font: "Futura", upper: true)
            s.text("Date line", "Date: {{date}}", x: 0.06, y: 0.175, w: 0.4, h: 0.03, size: 0.014, align: "left")
            s.text("Reference", "Ref: {{refno}}", x: 0.54, y: 0.175, w: 0.4, h: 0.03, size: 0.014, align: "right")
            s.text("Address block", "To,\n{{employee}}\n{{address}}", x: 0.06, y: 0.215, w: 0.5, h: 0.085, size: 0.0145, align: "left")
            s.text("Greeting", "Dear {{employee}},", x: 0.06, y: 0.315, w: 0.6, h: 0.03, size: 0.0145, align: "left")
            s.text("Opening", "With reference to your application and the interviews you attended, we are pleased to appoint you as {{designation}} in the {{department}} department of {{company}}. Your appointment is on the terms set out below and on the next page.", x: 0.06, y: 0.355, w: 0.88, h: 0.075, size: 0.0138, align: "left")
            s.block("Details box", x: 0.06, y: 0.445, w: 0.88, h: 0.235, fill: "#F1EFFE")
            let rows: [(String, String)] = [("Designation", "{{designation}}"), ("Department", "{{department}}"), ("Date of joining", "{{joining}}"), ("Place of posting", "{{location}}"),
                                            ("Reporting to", "{{reporting}}"), ("Probation", "{{probation}}"), ("Compensation (CTC)", "{{ctc}}")]
            for (index, row) in rows.enumerated() {
                let y = 0.455 + Double(index) * 0.0315
                s.text("Detail label \(index + 1)", row.0, x: 0.09, y: y, w: 0.3, h: 0.028, size: 0.0138, bold: true, color: "#3D348B", align: "left")
                s.text("Detail value \(index + 1)", row.1, x: 0.42, y: y, w: 0.5, h: 0.028, size: 0.0138, align: "left")
            }
            s.text("Closing", "Please read the terms and conditions on the next page, sign the acceptance there and return it on or before your date of joining. We welcome you and look forward to a long and happy association.", x: 0.06, y: 0.7, w: 0.88, h: 0.075, size: 0.0138, align: "left")
            s.text("Sign off", "Yours sincerely,\n\n\n{{signatory}}\n{{signtitle}}, {{company}}", x: 0.06, y: 0.81, w: 0.5, h: 0.125, size: 0.0138, align: "left")
            footer(&s, 1)
        }, { s in
            s.block("Header band", x: 0, y: 0, w: 1, h: 0.05, fill: "#3D348B")
            s.text("Header", "{{company}}  \u{00B7}  Appointment of {{employee}}", x: 0.05, y: 0.012, w: 0.9, h: 0.028, size: 0.0135, color: "#FFFFFF", align: "left")
            s.text("Terms title", "Terms and conditions", x: 0.06, y: 0.08, w: 0.88, h: 0.04, size: 0.026, bold: true, color: "#3D348B", font: "Futura", upper: true)
            s.text("Terms", "1. Probation. You will be on probation for {{probation}} from the date of joining. Your appointment will be confirmed in writing after a satisfactory review.\n\n2. Working hours. Your normal hours are those of {{department}}. You may be asked to work extra hours or on other days when the work needs it.\n\n3. Compensation. You will be paid {{ctc}}, less tax and other deductions required by law, in monthly instalments.\n\n4. Leave. You can take leave as set out in the company leave policy, which HR will share with you.\n\n5. Confidentiality. You must keep all non-public information about {{company}}, its clients and its work secret, during your employment and after it.\n\n6. Conduct. You must follow the company code of conduct and all policies in force from time to time.\n\n7. Notice. Either side can end this appointment by giving written notice as set out in the company policy, or by pay in place of notice.\n\n8. Place of work. Your first posting is {{location}}. The company may transfer you to any other place of business with reasonable notice.", x: 0.06, y: 0.14, w: 0.88, h: 0.6, size: 0.0132, align: "left")
            s.block("Acceptance box", x: 0.06, y: 0.77, w: 0.88, h: 0.16, fill: "#F1EFFE")
            s.text("Acceptance", "ACCEPTANCE\nI, {{employee}}, have read and understood these terms, and I accept the appointment as {{designation}}.\n\n\nSignature: ______________________        Date: ______________", x: 0.08, y: 0.78, w: 0.84, h: 0.14, size: 0.0135, align: "left")
            footer(&s, 2)
        }])
    }

    // MARK: 8. Invitation

    private static func invitation() -> AppDesign? {
        let vars = ["event": "Anaya's 5th Birthday", "host": "Neha and Arjun", "date": "Saturday, 13 March 2027", "time": "4:00 pm onwards", "venue": "The Garden Terrace",
                    "address": "Bandra West, Mumbai", "rsvp": "98765 43210", "dresscode": "Come dressed as your favourite animal"]
        return build("Invitation", width: 1080, height: 1350, color: "#1D1A39", format: .png, variables: vars, pages: [{ s in
            s.block("Gold line top", x: 0.06, y: 0.035, w: 0.88, h: 0.004, fill: "#E8B04B")
            s.block("Gold line bottom", x: 0.06, y: 0.961, w: 0.88, h: 0.004, fill: "#E8B04B")
            s.text("Kicker", "You are invited", x: 0.1, y: 0.07, w: 0.8, h: 0.04, size: 0.024, color: "#E8B04B", upper: true, font: "Futura")
            s.text("Event", "{{event}}", x: 0.06, y: 0.115, w: 0.88, h: 0.15, size: 0.085, color: "#FFFFFF", font: "Snell Roundhand")
            s.text("Host", "hosted by {{host}}", x: 0.1, y: 0.28, w: 0.8, h: 0.045, size: 0.027, italic: true, color: "#C9B8F2")
            s.dot("Photo ring", x: 0.315, y: 0.335, d: 0.37, fill: "#E8B04B")
            s.roundPhoto("Photo", x: 0.33, y: 0.346, d: 0.34)
            s.text("Date", "{{date}}", x: 0.06, y: 0.645, w: 0.88, h: 0.07, size: 0.045, bold: true, color: "#FFFFFF", font: "Didot")
            s.text("Time", "{{time}}", x: 0.1, y: 0.72, w: 0.8, h: 0.05, size: 0.032, color: "#E8B04B")
            s.text("Venue", "{{venue}}\n{{address}}", x: 0.1, y: 0.785, w: 0.8, h: 0.09, size: 0.027, color: "#FFFFFF")
            s.text("RSVP", "RSVP  {{rsvp}}", x: 0.1, y: 0.885, w: 0.8, h: 0.04, size: 0.026, bold: true, color: "#E8B04B")
            s.text("Dress code", "{{dresscode}}", x: 0.1, y: 0.922, w: 0.8, h: 0.03, size: 0.02, italic: true, color: "#C9B8F2")
        }])
    }

    // MARK: 9. Save the date with a countdown

    private static func saveTheDate() -> AppDesign? {
        let vars = ["couple": "Aarav & Meera", "eventdate": "14 February 2027", "venue": "Udaipur, Rajasthan", "note": "Formal invitation to follow"]
        return build("Save the date", width: 1080, height: 1080, color: "#FDF0F0", format: .png, variables: vars, pages: [{ s in
            s.dot("Outer ring", x: 0.07, y: 0.07, d: 0.86, fill: "#F2A7B5")
            s.dot("Inner disc", x: 0.1, y: 0.1, d: 0.8, fill: "#FFF8F6")
            s.text("Kicker", "Save the date", x: 0.2, y: 0.2, w: 0.6, h: 0.05, size: 0.03, color: "#B23A5B", upper: true, font: "Futura")
            s.text("Couple", "{{couple}}", x: 0.15, y: 0.26, w: 0.7, h: 0.17, size: 0.095, color: "#7A1F3D", font: "Snell Roundhand")
            s.text("Date", "{{eventdate}}", x: 0.15, y: 0.45, w: 0.7, h: 0.08, size: 0.052, bold: true, color: "#7A1F3D", font: "Didot")
            s.text("Venue", "{{venue}}", x: 0.2, y: 0.54, w: 0.6, h: 0.05, size: 0.03, italic: true, color: "#7A1F3D")
            s.text("Countdown", "{=DAYS(\"{{eventdate}}\", TODAY())} days to go", x: 0.28, y: 0.64, w: 0.44, h: 0.1, size: 0.038, bold: true, color: "#FFFFFF", fill: "#B23A5B")
            s.text("Note", "{{note}}", x: 0.2, y: 0.78, w: 0.6, h: 0.04, size: 0.024, italic: true, color: "#8A5A6B")
        }])
    }

    // MARK: 10. Certificate

    private static func certificate() -> AppDesign? {
        let vars = ["awardtype": "Appreciation", "recipient": "Rahul Sharma", "reason": "for outstanding dedication, teamwork and a result that lifted the whole team this year.",
                    "signer1": "Priya Mehta", "signtitle1": "Head of HR", "signer2": "Arjun Rao", "signtitle2": "Managing Director", "year": "{=YEAR(TODAY())}"]
        return build("Certificate of appreciation", width: 2000, height: 1414, color: "#FFFBEF", format: .pdf, variables: vars, pages: [{ s in
            s.block("Frame", x: 0.02, y: 0.03, w: 0.96, h: 0.94, fill: "#1F3A5F")
            s.block("Frame paper", x: 0.03, y: 0.05, w: 0.94, h: 0.9, fill: "#FFFBEF")
            s.block("Gold frame", x: 0.04, y: 0.07, w: 0.92, h: 0.86, fill: "#C9A227")
            s.block("Inner paper", x: 0.043, y: 0.0775, w: 0.914, h: 0.845, fill: "#FFFBEF")
            s.text("Title", "Certificate", x: 0.1, y: 0.12, w: 0.8, h: 0.14, size: 0.09, bold: true, color: "#1F3A5F", font: "Didot", upper: true)
            s.text("Kind", "of {{awardtype}}", x: 0.2, y: 0.26, w: 0.6, h: 0.06, size: 0.034, color: "#C9A227", font: "Futura", upper: true)
            s.text("Presented", "This certificate is proudly presented to", x: 0.2, y: 0.35, w: 0.6, h: 0.05, size: 0.025, italic: true, color: "#555555")
            s.text("Recipient", "{{recipient}}", x: 0.1, y: 0.41, w: 0.8, h: 0.17, size: 0.105, color: "#1F3A5F", font: "Snell Roundhand")
            s.block("Name line", x: 0.28, y: 0.59, w: 0.44, h: 0.003, fill: "#C9A227")
            s.text("Reason", "{{reason}}", x: 0.17, y: 0.62, w: 0.66, h: 0.13, size: 0.028, color: "#333333")
            s.dot("Seal", x: 0.44, y: 0.745, d: 0.12, fill: "#C9A227")
            s.text("Seal text", "{{year}}", x: 0.455, y: 0.775, w: 0.09, h: 0.07, size: 0.034, bold: true, color: "#FFFFFF", fill: "#B8901A", shape: .circle)
            s.block("Signature line 1", x: 0.1, y: 0.82, w: 0.28, h: 0.003, fill: "#1F3A5F")
            s.text("Signer 1", "{{signer1}}\n{{signtitle1}}", x: 0.1, y: 0.83, w: 0.28, h: 0.08, size: 0.022, color: "#1F3A5F")
            s.block("Signature line 2", x: 0.62, y: 0.82, w: 0.28, h: 0.003, fill: "#1F3A5F")
            s.text("Signer 2", "{{signer2}}\n{{signtitle2}}", x: 0.62, y: 0.83, w: 0.28, h: 0.08, size: 0.022, color: "#1F3A5F")
        }])
    }

    // MARK: 11. Festival countdown story

    private static func festivalStory() -> AppDesign? {
        let wish = wishToken(["festival", "diwali", "holi", "navratri", "eid", "christmas"])
        var vars = ["festival": "Happy Diwali", "festivaldate": "8 November 2027", "name": "Dear Rahul", "from": "Priya and family"]
        if wish == nil { vars["greeting"] = "May the festival of lights fill your home with joy, prosperity and sweet moments." }
        return build("Festival countdown story", width: 1080, height: 1920, color: "#2D0A4E", format: .png, variables: vars, pages: [{ s in
            s.dot("Glow", x: 0.1, y: 0.05, d: 0.8, fill: "#6A1B9A")
            s.dot("Sun", x: 0.15, y: 0.08, d: 0.7, fill: "#FF9E00")
            s.dot("Sun inner", x: 0.2, y: 0.115, d: 0.6, fill: "#FFC300")
            s.text("Days", "{=DAYS(\"{{festivaldate}}\", TODAY())}", x: 0.25, y: 0.17, w: 0.5, h: 0.14, size: 0.11, bold: true, color: "#2D0A4E", font: "Futura")
            s.text("Days label", "days to go", x: 0.25, y: 0.315, w: 0.5, h: 0.05, size: 0.03, bold: true, color: "#2D0A4E", upper: true)
            s.text("Festival", "{{festival}}", x: 0.05, y: 0.5, w: 0.9, h: 0.11, size: 0.08, color: "#FFFFFF", font: "Snell Roundhand")
            s.text("Greeting", wish ?? "{{greeting}}", x: 0.1, y: 0.63, w: 0.8, h: 0.16, size: 0.032, italic: true, color: "#FFD6A5")
            s.text("Name", "{{name}}", x: 0.1, y: 0.8, w: 0.8, h: 0.05, size: 0.04, bold: true, color: "#FFFFFF")
            s.text("From", "With love, {{from}}", x: 0.1, y: 0.855, w: 0.8, h: 0.045, size: 0.03, color: "#FFC300")
            s.block("Bottom band", x: 0, y: 0.93, w: 1, h: 0.07, fill: "#FF9E00")
            s.text("Date", "{{festivaldate}}", x: 0.1, y: 0.945, w: 0.8, h: 0.04, size: 0.03, bold: true, color: "#2D0A4E")
        }])
    }

    // MARK: 12. Hiring post

    private static func hiringPost() -> AppDesign? {
        let vars = ["role": "Sales Executive", "company": "Acme Pvt Ltd", "req1": "1 to 3 years in field or inside sales", "req2": "Fluent in English and Hindi", "req3": "Comfortable with targets and travel",
                    "location": "Mumbai", "salary": "\u{20B9}3 to 5 lakh per year + incentives", "apply": "careers@acme.com", "lastdate": "{=Date+14}"]
        return build("Hiring post", width: 1080, height: 1080, color: "#F1FAEE", format: .png, variables: vars, pages: [{ s in
            s.block("Left panel", x: 0, y: 0, w: 0.38, h: 1, fill: "#1D3557")
            s.dot("Dot 1", x: 0.04, y: 0.78, d: 0.12, fill: "#E63946")
            s.dot("Dot 2", x: 0.2, y: 0.86, d: 0.08, fill: "#A8DADC")
            s.text("We are", "We are\nhiring", x: 0.03, y: 0.1, w: 0.32, h: 0.3, size: 0.066, bold: true, color: "#FFFFFF", align: "left", font: "Futura", upper: true)
            s.text("Role", "{{role}}", x: 0.43, y: 0.07, w: 0.52, h: 0.15, size: 0.06, bold: true, color: "#1D3557", align: "left", font: "Didot")
            s.text("Company", "at {{company}}", x: 0.43, y: 0.23, w: 0.52, h: 0.05, size: 0.03, color: "#E63946", align: "left", bold: true)
            for index in 0..<3 {
                s.text("Requirement \(index + 1)", "\u{2022}  {{req\(index + 1)}}", x: 0.43, y: 0.33 + Double(index) * 0.095, w: 0.52, h: 0.085, size: 0.027, color: "#1D3557", align: "left")
            }
            s.text("Place", "Location: {{location}}", x: 0.43, y: 0.62, w: 0.52, h: 0.045, size: 0.027, bold: true, color: "#1D3557", align: "left")
            s.text("Pay", "Pay: {{salary}}", x: 0.43, y: 0.67, w: 0.52, h: 0.07, size: 0.027, color: "#1D3557", align: "left")
            s.text("Apply", "Apply: {{apply}}", x: 0.43, y: 0.79, w: 0.52, h: 0.09, size: 0.03, bold: true, color: "#FFFFFF", fill: "#E63946")
            s.text("Last date", "Last date to apply: {{lastdate}}", x: 0.43, y: 0.9, w: 0.52, h: 0.05, size: 0.024, italic: true, color: "#1D3557", align: "left")
        }])
    }

    // MARK: 13. Quotation

    private static func quotation() -> AppDesign? {
        let vars = ["company": "Acme Pvt Ltd", "number": "Q-2027-014", "date": "{=TODAY()}", "validtill": "{=Date+15}", "client": "Beta Industries LLP", "clientaddress": "Pune, Maharashtra",
                    "item1": "Brand film (60 seconds)", "qty1": "1", "rate1": "85000", "item2": "Social media posts", "qty2": "12", "rate2": "2500", "item3": "Photo shoot (half day)", "qty3": "1", "rate3": "18000",
                    "gst": "18", "terms": "50% advance, balance on delivery. Prices are valid for 15 days. Taxes extra as shown.", "payto": "Acme Pvt Ltd, A/c 0000 0000, IFSC ABCD0000000"]
        let subtotal = "{{qty1}}*{{rate1}}+{{qty2}}*{{rate2}}+{{qty3}}*{{rate3}}"
        return build("Quotation", width: 1654, height: 2339, color: "#FFFFFF", format: .pdf, variables: vars, pages: [{ s in
            s.block("Top band", x: 0, y: 0, w: 1, h: 0.12, fill: "#0F4C5C")
            s.text("Company", "{{company}}", x: 0.07, y: 0.032, w: 0.5, h: 0.05, size: 0.035, bold: true, color: "#FFFFFF", align: "left", font: "Didot")
            s.text("Kind", "Quotation", x: 0.55, y: 0.028, w: 0.38, h: 0.04, size: 0.03, bold: true, color: "#FB9F57", align: "right", upper: true, font: "Futura")
            s.text("Number", "No. {{number}}", x: 0.55, y: 0.074, w: 0.38, h: 0.03, size: 0.015, color: "#FFFFFF", align: "right")
            s.text("Bill to", "Quote for\n{{client}}\n{{clientaddress}}", x: 0.07, y: 0.15, w: 0.45, h: 0.09, size: 0.0145, align: "left")
            s.text("Dates", "Date: {{date}}\nValid till: {{validtill}}", x: 0.55, y: 0.15, w: 0.38, h: 0.07, size: 0.0145, align: "right")
            s.block("Table head", x: 0.07, y: 0.275, w: 0.86, h: 0.036, fill: "#E36414")
            s.text("Head item", "Item", x: 0.08, y: 0.281, w: 0.4, h: 0.024, size: 0.0135, bold: true, color: "#FFFFFF", align: "left")
            s.text("Head qty", "Qty", x: 0.5, y: 0.281, w: 0.1, h: 0.024, size: 0.0135, bold: true, color: "#FFFFFF")
            s.text("Head rate", "Rate", x: 0.6, y: 0.281, w: 0.15, h: 0.024, size: 0.0135, bold: true, color: "#FFFFFF", align: "right")
            s.text("Head amount", "Amount", x: 0.77, y: 0.281, w: 0.15, h: 0.024, size: 0.0135, bold: true, color: "#FFFFFF", align: "right")
            for index in 1...3 {
                let y = 0.315 + Double(index - 1) * 0.045
                if index % 2 == 1 { s.block("Row shade \(index)", x: 0.07, y: y, w: 0.86, h: 0.043, fill: "#F6F6F6") }
                s.text("Row item \(index)", "{{item\(index)}}", x: 0.08, y: y + 0.008, w: 0.4, h: 0.028, size: 0.0138, align: "left")
                s.text("Row qty \(index)", "{{qty\(index)}}", x: 0.5, y: y + 0.008, w: 0.1, h: 0.028, size: 0.0138)
                s.text("Row rate \(index)", "{=INR({{rate\(index)}})}", x: 0.6, y: y + 0.008, w: 0.15, h: 0.028, size: 0.0138, align: "right")
                s.text("Row amount \(index)", "{=INR({{qty\(index)}}*{{rate\(index)}})}", x: 0.77, y: y + 0.008, w: 0.15, h: 0.028, size: 0.0138, align: "right")
            }
            s.text("Subtotal label", "Subtotal", x: 0.5, y: 0.47, w: 0.25, h: 0.03, size: 0.0145, align: "right")
            s.text("Subtotal", "{=INR(\(subtotal))}", x: 0.77, y: 0.47, w: 0.15, h: 0.03, size: 0.0145, align: "right")
            s.text("GST label", "GST ({{gst}}%)", x: 0.5, y: 0.505, w: 0.25, h: 0.03, size: 0.0145, align: "right")
            s.text("GST", "{=INR((\(subtotal))*{{gst}}/100)}", x: 0.77, y: 0.505, w: 0.15, h: 0.03, size: 0.0145, align: "right")
            s.block("Total band", x: 0.5, y: 0.545, w: 0.43, h: 0.045, fill: "#0F4C5C")
            s.text("Total label", "Total", x: 0.51, y: 0.555, w: 0.22, h: 0.026, size: 0.0165, bold: true, color: "#FFFFFF", align: "left")
            s.text("Total", "{=INR((\(subtotal))*(1+{{gst}}/100))}", x: 0.7, y: 0.555, w: 0.22, h: 0.026, size: 0.0165, bold: true, color: "#FFFFFF", align: "right")
            s.text("Terms", "Terms\n{{terms}}", x: 0.07, y: 0.64, w: 0.86, h: 0.1, size: 0.0138, align: "left")
            s.text("Pay to", "Pay to: {{payto}}", x: 0.07, y: 0.76, w: 0.86, h: 0.04, size: 0.0138, bold: true, color: "#0F4C5C", align: "left")
            s.block("Footer band", x: 0, y: 0.94, w: 1, h: 0.06, fill: "#0F4C5C")
            s.text("Thanks", "Thank you for your business", x: 0.1, y: 0.955, w: 0.8, h: 0.03, size: 0.016, color: "#FFFFFF")
        }])
    }
}
