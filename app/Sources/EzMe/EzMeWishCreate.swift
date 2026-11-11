// WishBuilder, create from a prompt: describe an app, answer what is missing, preview, create.
// The drafting reads keywords in the description (occasion, names, dates, lists). It is not AI, so the
// result is a good starting point that the person checks and can edit in the five steps.
import SwiftUI

// MARK: - Questions and drafts

struct WishQuestion: Identifiable, Equatable {
    enum Kind { case text, collection }
    var id: String
    var kind: Kind
    var fieldKey: String
    var ask: String
    var askHi: String
    var placeholder: String
    var answer: String = ""
    var longAnswer: Bool = false
    var skipped: Bool = false
}

struct WishDraft {
    var app: WishApp
    var questions: [WishQuestion]
}

private struct WishOccasion {
    let keys: [String]
    let name: String
    let nameHi: String
    let title: String
    let titleHi: String
    let eyebrow: String
    let message: String
    let messageHi: String
    let symbol: String
    let design: String
}

enum WishDrafter {
    private static let occasions: [WishOccasion] = [
        WishOccasion(keys: ["birthday", "bday", "b'day", "जन्मदिन", "जन्म दिन"], name: "Happy Birthday", nameHi: "जन्मदिन", title: "Happy Birthday", titleHi: "जन्मदिन मुबारक", eyebrow: "TODAY IS ALL ABOUT YOU", message: "May your day be filled with laughter, love and every little thing that makes you smile.", messageHi: "आपका दिन हँसी, प्यार और छोटी-छोटी खुशियों से भरा रहे।", symbol: "birthday.cake.fill", design: "g-blush"),
        WishOccasion(keys: ["anniversary", "सालगिरह"], name: "Happy Anniversary", nameHi: "सालगिरह", title: "Happy Anniversary", titleHi: "सालगिरह मुबारक", eyebrow: "TWO HEARTS, ONE STORY", message: "Here is to the love you share and every beautiful year still ahead.", messageHi: "आपके प्यार और आने वाले हर खूबसूरत साल के नाम।", symbol: "heart.fill", design: "g-rose"),
        WishOccasion(keys: ["diwali", "deepavali", "दिवाली", "दीपावली"], name: "Happy Diwali", nameHi: "दिवाली", title: "Happy Diwali", titleHi: "दीपावली की शुभकामनाएँ", eyebrow: "A FESTIVAL OF LIGHT", message: "May the lamps of Diwali bring you joy, health and prosperity.", messageHi: "दीपों का यह पर्व आपके जीवन में सुख, स्वास्थ्य और समृद्धि लाए।", symbol: "flame.fill", design: "g-saffron"),
        WishOccasion(keys: ["holi", "होली"], name: "Happy Holi", nameHi: "होली", title: "Happy Holi", titleHi: "होली की शुभकामनाएँ", eyebrow: "COLOURS OF JOY", message: "May your life be as bright and happy as the colours of Holi.", messageHi: "होली के रंगों की तरह आपका जीवन भी रंगीन और खुशहाल रहे।", symbol: "sparkles", design: "g-coral"),
        WishOccasion(keys: ["eid", "ईद"], name: "Eid Mubarak", nameHi: "ईद मुबारक", title: "Eid Mubarak", titleHi: "ईद मुबारक", eyebrow: "BLESSINGS FOR YOU", message: "May this Eid bring peace, happiness and togetherness to you and your family.", messageHi: "यह ईद आपके और आपके परिवार के लिए सुख, शांति और खुशियाँ लाए।", symbol: "moon.stars.fill", design: "g-mint"),
        WishOccasion(keys: ["christmas", "xmas", "क्रिसमस"], name: "Merry Christmas", nameHi: "क्रिसमस", title: "Merry Christmas", titleHi: "क्रिसमस की शुभकामनाएँ", eyebrow: "SEASON OF JOY", message: "Wishing you warmth, joy and a very merry Christmas.", messageHi: "आपको क्रिसमस की ढेर सारी खुशियाँ और गर्मजोशी भरी शुभकामनाएँ।", symbol: "gift.fill", design: "g-night"),
        WishOccasion(keys: ["new year", "नया साल", "नव वर्ष", "नववर्ष"], name: "Happy New Year", nameHi: "नव वर्ष", title: "Happy New Year", titleHi: "नव वर्ष की शुभकामनाएँ", eyebrow: "A FRESH START", message: "May the year ahead bring you health, happiness and every success.", messageHi: "नया साल आपके लिए सेहत, खुशियाँ और सफलता लेकर आए।", symbol: "star.fill", design: "g-gold"),
        WishOccasion(keys: ["rakhi", "raksha bandhan", "rakshabandhan", "राखी", "रक्षाबंधन"], name: "Happy Raksha Bandhan", nameHi: "रक्षाबंधन", title: "Happy Raksha Bandhan", titleHi: "रक्षाबंधन की शुभकामनाएँ", eyebrow: "A BOND LIKE NO OTHER", message: "Thank you for always being by my side.", messageHi: "हमेशा मेरे साथ खड़े रहने के लिए धन्यवाद।", symbol: "heart.fill", design: "g-peach"),
        WishOccasion(keys: ["ganesh", "ganpati", "गणेश"], name: "Ganesh Chaturthi", nameHi: "गणेश चतुर्थी", title: "Ganesh Chaturthi", titleHi: "गणेश चतुर्थी की शुभकामनाएँ", eyebrow: "BLESSINGS", message: "May Lord Ganesha remove every obstacle and bless you with happiness.", messageHi: "भगवान गणेश आपके सभी विघ्न दूर करें और खुशियाँ दें।", symbol: "flame.fill", design: "g-saffron"),
        WishOccasion(keys: ["mother's day", "mothers day", "मदर्स डे"], name: "Happy Mother's Day", nameHi: "मदर्स डे", title: "Happy Mother's Day", titleHi: "मदर्स डे की शुभकामनाएँ", eyebrow: "FOR THE ONE WHO DOES IT ALL", message: "Thank you for your love, patience and everything you do.", messageHi: "आपके प्यार, धैर्य और हर कोशिश के लिए धन्यवाद।", symbol: "camera.macro", design: "g-blush"),
        WishOccasion(keys: ["father's day", "fathers day", "फादर्स डे"], name: "Happy Father's Day", nameHi: "फादर्स डे", title: "Happy Father's Day", titleHi: "फादर्स डे की शुभकामनाएँ", eyebrow: "MY FIRST HERO", message: "Thank you for always believing in me.", messageHi: "हमेशा मुझ पर भरोसा करने के लिए धन्यवाद।", symbol: "crown.fill", design: "g-sky"),
        WishOccasion(keys: ["wedding", "invitation", "invite", "शादी", "विवाह", "निमंत्रण"], name: "Invitation", nameHi: "निमंत्रण", title: "You are invited", titleHi: "आप आमंत्रित हैं", eyebrow: "WITH JOY WE INVITE YOU", message: "Please join us to celebrate this special day.", messageHi: "इस खास दिन का जश्न मनाने के लिए हमारे साथ जुड़िए।", symbol: "bell.fill", design: "g-ink"),
        WishOccasion(keys: ["thank you", "thanks", "धन्यवाद", "शुक्रिया"], name: "Thank You", nameHi: "धन्यवाद", title: "Thank you", titleHi: "धन्यवाद", eyebrow: "WITH GRATITUDE", message: "Thank you for everything you do. It means more than words can say.", messageHi: "आपके हर सहयोग के लिए धन्यवाद। यह शब्दों से कहीं ज़्यादा मायने रखता है।", symbol: "hands.clap.fill", design: "g-sky"),
        WishOccasion(keys: ["congratulations", "congrats", "बधाई"], name: "Congratulations", nameHi: "बधाई", title: "Congratulations", titleHi: "बधाई हो", eyebrow: "WELL DESERVED", message: "So proud of you. Here is to your success and many more wins ahead.", messageHi: "आप पर बहुत गर्व है। आपकी सफलता और आने वाली जीतों के नाम।", symbol: "trophy.fill", design: "g-gold"),
        WishOccasion(keys: ["get well", "feel better", "जल्दी ठीक"], name: "Get Well Soon", nameHi: "जल्दी ठीक हो जाइए", title: "Get well soon", titleHi: "जल्दी ठीक हो जाइए", eyebrow: "THINKING OF YOU", message: "Sending healing wishes and warm thoughts. Rest well and feel better soon.", messageHi: "आपके लिए दुआएँ और ढेर सारी शुभकामनाएँ। आराम करें, जल्दी ठीक हो जाएँ।", symbol: "leaf.fill", design: "g-sage"),
        WishOccasion(keys: ["good morning", "सुप्रभात"], name: "Good Morning", nameHi: "सुप्रभात", title: "Good morning", titleHi: "सुप्रभात", eyebrow: "A NEW DAY", message: "Wishing you a bright morning and a day full of good things.", messageHi: "आपकी सुबह उजली हो और दिन अच्छी बातों से भरा रहे।", symbol: "sun.max.fill", design: "g-peach"),
    ]

    private static let infographicWords = ["infographic", "chart", "graph", "timeline", "steps", "ranking", "comparison", "statistics", "roadmap", "इन्फोग्राफिक", "चार्ट"]
    private static let notNames: Set<String> = ["diwali", "holi", "eid", "christmas", "birthday", "anniversary", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december", "mother", "father", "ganesh", "rakhi", "new", "happy"]

    private static func mentions(_ lower: String, _ key: String) -> Bool {
        if key.unicodeScalars.contains(where: { $0.value > 127 }) { return lower.contains(key) }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: key) + "\\b"
        return lower.range(of: pattern, options: .regularExpression) != nil
    }

    private static let appNamePattern = "(?i)\\b(?:called|named)\\s+[\"\u{201C}]?([A-Za-z0-9]+(?: [A-Za-z0-9]+){0,2})"

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 else { return nil }
        let range = match.range(at: 1)
        if range.location == NSNotFound { return nil }
        return ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func field(_ key: String, _ label: String, _ labelHi: String, _ type: WishFieldType, _ value: String, _ valueHi: String? = nil, universal: Bool = false) -> WishField {
        return WishField(key: key, label: label, labelHi: labelHi, type: type, value: value, valueHi: valueHi ?? value, universal: universal)
    }

    static func draft(prompt: String, collections: [String]) -> WishDraft {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let hindi = text.unicodeScalars.contains { $0.value >= 0x0900 && $0.value <= 0x097F }
        let isInfographic = infographicWords.contains { mentions(lower, $0) }
        var questions: [WishQuestion] = []

        var app = WishApp(name: "My wish app", tagline: "Made with WishBuilder", symbol: "sparkles", artwork: "sparkles", kind: isInfographic ? .infographic : .greeting, prompt: text)
        app.defaultLanguage = hindi ? .hindi : .english

        let calledName = firstMatch(appNamePattern, in: text)
        if let called = calledName { app.name = called }
        let explicitName = calledName != nil

        // MARK: Infographic
        if isInfographic {
            app.symbol = "chart.pie.fill"
            app.artwork = "chart.pie.fill"
            app.designID = "i-circles"
            if !explicitName { app.name = "My infographic" }
            var title = firstMatch("(?i)\\b(?:about|on|of|for)\\s+([^:.,]{3,50})", in: text) ?? ""
            title = title.trimmingCharacters(in: .whitespaces)
            if let first = title.first { title = first.uppercased() + title.dropFirst() }
            var items = ""
            if let tail = firstMatch(":\\s*(.+)$", in: text) {
                let parts = tail.replacingOccurrences(of: " and ", with: ",").replacingOccurrences(of: " और ", with: ",").replacingOccurrences(of: ";", with: ",").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                items = parts.joined(separator: "\n")
            }
            app.fields = [
                field("eyebrow", "Top line", "ऊपर की पंक्ति", .text, "IDEAS, BEAUTIFULLY CONNECTED"),
                field("title", "Infographic title", "इन्फोग्राफिक शीर्षक", .text, title.isEmpty ? "Your title here" : title),
                field("data", "Data", "डेटा", .list, items.isEmpty ? "One, 30\nTwo, 20\nThree, 50" : items),
            ]
            if title.isEmpty {
                questions.append(WishQuestion(id: "t-title", kind: .text, fieldKey: "title", ask: "What is the title?", askHi: "शीर्षक क्या होगा?", placeholder: "Four steps to a better day"))
            }
            if items.isEmpty {
                questions.append(WishQuestion(id: "t-data", kind: .text, fieldKey: "data", ask: "What should it show? One item per line. Add a number after a comma for a chart.", askHi: "इसमें क्या दिखाना है? हर पंक्ति में एक चीज़। चार्ट के लिए कॉमा के बाद संख्या लिखें।", placeholder: "Plan, 40\nBuild, 35\nLaunch, 25", longAnswer: true))
            }
            return WishDraft(app: app, questions: questions)
        }

        // MARK: Greeting
        let occasion = occasions.first { item in item.keys.contains { mentions(lower, $0) } }
        if let occasion = occasion {
            if !explicitName { app.name = occasion.name }
            app.nameHi = occasion.nameHi
            app.tagline = "Made with WishBuilder"
            app.symbol = occasion.symbol
            app.artwork = occasion.symbol
            app.designID = occasion.design
        } else {
            app.designID = "g-lavender"
            if !explicitName { app.name = "My greeting" }
        }
        let title = occasion?.title ?? "Greetings"
        let titleHi = occasion?.titleHi ?? "शुभकामनाएँ"
        let defaultMessage = occasion?.message ?? "Write something warm here."
        let defaultMessageHi = occasion?.messageHi ?? "यहाँ कुछ अपनापन भरा लिखें।"

        // Recipient and sender
        let namePattern = "\\b(?i:for|to|dear)\\s+(?i:my\\s+|our\\s+)?(?i:(?:friend|brother|sister|mom|dad|mother|father|wife|husband|boss|colleague|teacher|son|daughter|uncle|aunt|cousin|bhai|didi)\\s+)?([A-Z][a-z]+(?:\\s+(?:and|&)\\s+[A-Z][a-z]+)?)"
        var recipient = firstMatch(namePattern, in: text)
        if let found = recipient, notNames.contains(found.lowercased()) { recipient = nil }
        var sender = firstMatch("\\b(?i:from|by)\\s+([A-Z][a-z]+)", in: text)
        if let found = sender, notNames.contains(found.lowercased()) { sender = nil }
        let quoted = firstMatch("[\"“]([^\"”]{4,200})[\"”]", in: text)

        // Date
        var date = ""
        if lower.contains("tomorrow") { date = "=Date+1" }
        else if lower.contains("today") || lower.contains("आज") { date = "=Date" }
        else if lower.contains("next week") { date = "=Date+7" }
        else if lower.contains("next month") { date = "=Date+30" }

        var fields: [WishField] = [
            field("eyebrow", "Top line", "ऊपर की पंक्ति", .text, occasion?.eyebrow ?? "A LITTLE NOTE", occasion == nil ? nil : "शुभकामनाओं के साथ"),
            field("title", "Title", "शीर्षक", .text, title, titleHi),
            field("name", "Name", "नाम", .text, recipient ?? "Dear friend", recipient ?? "प्रिय मित्र", universal: recipient != nil),
            field("message", "Message", "संदेश", .longText, quoted ?? defaultMessage, quoted ?? defaultMessageHi),
            field("from", "From", "की ओर से", .text, sender ?? "With love", sender ?? "प्यार के साथ"),
            field("date", "Date", "तारीख़", .date, date.isEmpty ? "=Date" : date, date.isEmpty ? "=Date" : date, universal: true),
        ]
        if lower.contains("venue") || lower.contains("where") || lower.contains("स्थान") {
            fields.append(field("venue", "Venue", "स्थान", .text, "At our place", universal: true))
            questions.append(WishQuestion(id: "t-venue", kind: .text, fieldKey: "venue", ask: "Where is it?", askHi: "यह कहाँ है?", placeholder: "Hotel Grand, Indore"))
        }
        if lower.contains(" time") || lower.contains("o'clock") || lower.contains("समय") {
            fields.append(field("time", "Time", "समय", .text, "=Time", universal: true))
            questions.append(WishQuestion(id: "t-time", kind: .text, fieldKey: "time", ask: "What time? Type a time, or =Time for now.", askHi: "कितने बजे? समय लिखें, या अभी के लिए =Time।", placeholder: "7:30 pm"))
        }
        if lower.contains("phone") || lower.contains("call") || lower.contains("contact") || lower.contains("फ़ोन") {
            fields.append(field("phone", "Phone", "फ़ोन", .text, "", universal: true))
            questions.append(WishQuestion(id: "t-phone", kind: .text, fieldKey: "phone", ask: "Which phone number should it show?", askHi: "कौन सा फ़ोन नंबर दिखाना है?", placeholder: "98765 43210"))
        }
        app.fields = fields

        // Questions for what the description did not say
        var asked: [WishQuestion] = []
        if recipient == nil {
            asked.append(WishQuestion(id: "t-name", kind: .text, fieldKey: "name", ask: "Who is this for?", askHi: "यह किसके लिए है?", placeholder: "Rahul"))
        }
        if quoted == nil {
            asked.append(WishQuestion(id: "t-message", kind: .text, fieldKey: "message", ask: "Anything you want to say? Leave it blank for a warm default.", askHi: "कुछ खास लिखना है? खाली छोड़ें तो एक अच्छा संदेश लग जाएगा।", placeholder: "Wishing you the happiest year yet", longAnswer: true))
        }
        if sender == nil {
            asked.append(WishQuestion(id: "t-from", kind: .text, fieldKey: "from", ask: "Who is it from?", askHi: "यह किसकी ओर से है?", placeholder: "Yogesh"))
        }
        if date.isEmpty {
            asked.append(WishQuestion(id: "t-date", kind: .text, fieldKey: "date", ask: "Which date should it show? Type a date, or =Date+7 for a week from today.", askHi: "कौन सी तारीख़ दिखानी है? तारीख़ लिखें, या एक हफ़्ते बाद के लिए =Date+7।", placeholder: "=Date"))
        }
        if !collections.isEmpty {
            asked.append(WishQuestion(id: "c-name", kind: .collection, fieldKey: "name", ask: "Pick the name from one of your KeyDo collections?", askHi: "नाम अपने KeyDo कलेक्शन से चुनना चाहते हैं?", placeholder: "No, I will type it"))
        }
        return WishDraft(app: app, questions: asked + questions)
    }
}

// MARK: - Builder state (shared by the screen and the voice commands)

enum WishBuilderMode: String, CaseIterable {
    case create = "Create from a prompt"
    case edit = "Edit an app"
}

enum WishCreateStage: Int {
    case describe = 0
    case questions = 1
    case preview = 2
}

@MainActor
final class WishBuilderState: ObservableObject {
    weak var model: WishStudioModel?

    @Published var mode: WishBuilderMode = .create
    @Published var stage: WishCreateStage = .describe
    @Published var prompt: String = ""
    @Published var draft: WishDraft? = nil
    @Published var editingID: String = ""
    @Published var step: WishStep = .application
    @Published var note: String = ""

    static let examples: [String] = [
        "A Holi greeting for my team with a colourful message",
        "Rakhi card for my brother Rahul from Priya",
        "Anniversary card for Priya and Rahul",
        "Infographic of our plan: Plan, Build, Launch, Grow",
        "Wedding invitation for tomorrow, venue and time",
        "आज के लिए जन्मदिन कार्ड",
    ]

    var hints: [String] {
        if mode == .edit {
            return ["add field venue", "remove field phone", "rename app to Holi", "go to Function", "go to Live Changes", "open in studio"]
        }
        switch stage {
        case .describe:
            return ["a Holi greeting for my team", "rakhi card for my brother Rahul", "infographic of 4 steps", "build"]
        case .questions:
            return ["name is Priya", "from Rahul", "message Wishing you joy", "date =Date+7", "skip", "preview"]
        case .preview:
            return ["create app", "back"]
        }
    }

    var placeholder: String {
        if mode == .edit { return "Say or type, like \u{201C}add field venue\u{201D} or \u{201C}go to Function\u{201D}" }
        switch stage {
        case .describe: return "Describe the app you want, then say \u{201C}build\u{201D}"
        case .questions: return "Answer a question, like \u{201C}name is Priya\u{201D}, or say \u{201C}preview\u{201D}"
        case .preview: return "Say \u{201C}create app\u{201D} when you are happy"
        }
    }

    var contextLine: String {
        if mode == .edit { return "Editing \(editingApp?.name ?? "an app") \u{00B7} \(step.title)" }
        switch stage {
        case .describe: return "Step 1 of 3 \u{00B7} Describe"
        case .questions: return "Step 2 of 3 \u{00B7} Missing information"
        case .preview: return "Step 3 of 3 \u{00B7} Preview"
        }
    }

    var editingApp: WishApp? {
        guard let model = model else { return nil }
        return model.store.app(id: editingID) ?? model.store.apps.first
    }

    // MARK: Creating

    func buildDraft() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            note = "Describe the app first, or tap one of the examples."
            model?.status = note
            return
        }
        draft = WishDrafter.draft(prompt: text, collections: model?.collections ?? [])
        stage = (draft?.questions.isEmpty ?? true) ? .preview : .questions
        note = ""
        model?.status = stage == .questions ? "A few things are missing. Answer them, or say \u{201C}preview\u{201D}." : "Nothing is missing. Check the preview."
    }

    func restart() {
        prompt = ""
        draft = nil
        stage = .describe
        note = ""
    }

    /// Writes an answer into the draft so the preview updates straight away.
    func setAnswer(_ id: String, _ value: String) {
        guard var current = draft, let index = current.questions.firstIndex(where: { $0.id == id }) else { return }
        current.questions[index].answer = value
        let question = current.questions[index]
        switch question.kind {
        case .text:
            if let fieldIndex = current.app.fields.firstIndex(where: { $0.key == question.fieldKey }) {
                let hasHindi = value.unicodeScalars.contains { $0.value >= 0x0900 && $0.value <= 0x097F }
                let shared = ["name", "from", "date", "venue", "time", "phone"].contains(question.fieldKey)
                if !value.trimmingCharacters(in: .whitespaces).isEmpty {
                    current.app.fields[fieldIndex].value = value
                    if shared || hasHindi || current.app.defaultLanguage == .hindi { current.app.fields[fieldIndex].valueHi = value }
                }
            }
        case .collection:
            current.app.links = value.isEmpty ? [] : [WishCollectionLink(collection: value, fieldKey: question.fieldKey, useShortcutText: false)]
        }
        draft = current
    }

    var unanswered: [WishQuestion] {
        return draft?.questions.filter { $0.kind == .text && !$0.skipped && $0.answer.trimmingCharacters(in: .whitespaces).isEmpty } ?? []
    }

    func createApp() {
        guard let model = model, var made = draft?.app else { return }
        let cleanName = made.name.trimmingCharacters(in: .whitespaces)
        if cleanName.isEmpty { made.name = "My wish app" }
        var finalName = made.name
        var count = 2
        while model.store.apps.contains(where: { $0.name.caseInsensitiveCompare(finalName) == .orderedSame }) {
            finalName = made.name + " " + String(count)
            count += 1
        }
        made.name = finalName
        model.store.apps.append(made)
        let id = made.id
        restart()
        model.openApp(id)
        model.status = "\u{201C}\(finalName)\u{201D} is ready. Change anything on the right, or say a command."
    }

    // MARK: Voice and typed commands for WishBuilder

    private func saysAny(_ lower: String, _ words: [String]) -> Bool {
        let count = lower.split(separator: " ").count
        return count <= 4 && words.contains { lower.contains($0) }
    }

    func handle(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        guard !text.isEmpty else { return }
        if mode == .edit {
            handleEdit(text, lower)
            return
        }
        if saysAny(lower, ["start over", "new idea", "\u{092B}\u{093F}\u{0930} \u{0938}\u{0947}"]) {
            restart()
            model?.status = "Starting over."
            return
        }
        switch stage {
        case .describe:
            if !prompt.isEmpty && saysAny(lower, ["build", "next", "continue", "go ahead", "make it", "\u{092C}\u{0928}\u{093E}\u{0913}", "\u{092C}\u{0928}\u{093E} \u{0926}\u{094B}", "\u{0906}\u{0917}\u{0947}", "\u{0905}\u{0917}\u{0932}\u{093E}"]) {
                buildDraft()
            } else {
                prompt = prompt.isEmpty ? text : prompt + " " + text
                model?.status = "Got it. Keep describing, or say \u{201C}build\u{201D}."
            }
        case .questions:
            if saysAny(lower, ["preview", "next", "continue", "done", "\u{0906}\u{0917}\u{0947}", "\u{0905}\u{0917}\u{0932}\u{093E}", "\u{0939}\u{094B} \u{0917}\u{092F}\u{093E}"]) {
                stage = .preview
                model?.status = "Here is the preview. Say \u{201C}create app\u{201D} when you are happy."
            } else if saysAny(lower, ["back", "\u{092A}\u{0940}\u{091B}\u{0947}"]) {
                stage = .describe
            } else if saysAny(lower, ["skip", "\u{091B}\u{094B}\u{0921}\u{093C}\u{094B}"]) {
                if let first = unanswered.first, var current = draft, let index = current.questions.firstIndex(where: { $0.id == first.id }) {
                    current.questions[index].skipped = true
                    draft = current
                    model?.status = "Skipped. The default stays."
                }
            } else {
                answerByVoice(text, lower)
            }
        case .preview:
            if saysAny(lower, ["create", "make", "finish", "done", "\u{092C}\u{0928}\u{093E}\u{0913}", "\u{092C}\u{0928}\u{093E} \u{0926}\u{094B}"]) {
                createApp()
            } else if saysAny(lower, ["back", "\u{092A}\u{0940}\u{091B}\u{0947}"]) {
                stage = (draft?.questions.isEmpty ?? true) ? .describe : .questions
            } else {
                model?.status = "Say \u{201C}create app\u{201D} to finish, or \u{201C}back\u{201D} to change an answer."
            }
        }
    }

    private func answerByVoice(_ text: String, _ lower: String) {
        guard let current = draft, let model = model else { return }
        // A collection name picks that collection for the name.
        if let question = current.questions.first(where: { $0.kind == .collection }),
           let collection = model.collections.first(where: { lower.contains($0.lowercased()) }) {
            setAnswer(question.id, collection)
            model.status = "Names will come from \(collection)."
            return
        }
        // "name is Priya", "from Rahul", "date =Date+7" ...
        let env = WishCommandEnvironment(app: current.app, apps: [], designs: [], chips: [])
        for command in WishCommandParser.parse(text, env: env) {
            if case .setField(let key, let value) = command.action,
               let question = current.questions.first(where: { $0.kind == .text && $0.fieldKey.caseInsensitiveCompare(key) == .orderedSame }) {
                setAnswer(question.id, value)
                model.status = "\(current.app.field(key)?.label ?? key) \u{2192} \(value)"
                return
            }
        }
        // Anything else answers the first open question.
        if let first = unanswered.first {
            setAnswer(first.id, text)
            model.status = "\(current.app.field(first.fieldKey)?.label ?? first.fieldKey) \u{2192} \(text)"
        } else {
            model.status = "All answered. Say \u{201C}preview\u{201D}."
        }
    }

    private func handleEdit(_ text: String, _ lower: String) {
        guard let model = model else { return }
        let stepWords: [(WishStep, [String])] = [
            (.application, ["application"]), (.information, ["information", "fields"]), (.collection, ["collection"]),
            (.function, ["function"]), (.live, ["live", "voice"]),
        ]
        if lower.hasPrefix("go to") || lower.hasPrefix("open step") || lower.hasPrefix("step ") {
            for (item, words) in stepWords where words.contains(where: { lower.contains($0) }) {
                step = item
                model.status = "Step \(item.rawValue + 1) \u{00B7} \(item.title)"
                return
            }
        }
        if saysAny(lower, ["next step"]) {
            step = WishStep(rawValue: min(WishStep.allCases.count - 1, step.rawValue + 1)) ?? step
            return
        }
        if saysAny(lower, ["previous step", "back"]) {
            step = WishStep(rawValue: max(0, step.rawValue - 1)) ?? step
            return
        }
        if saysAny(lower, ["new app", "create app", "create new"]) {
            mode = .create
            restart()
            return
        }
        if saysAny(lower, ["open in studio", "try it", "open studio"]) {
            if let target = editingApp { model.openApp(target.id) }
            return
        }
        guard var target = editingApp else { return }
        if let label = firstWord(after: ["add field ", "new field "], in: text) {
            let key = WishBuilderTools.makeKey(label, existing: target.fields)
            target.fields.append(WishField(key: key, label: label.capitalized, value: ""))
            model.store.updateApp(target)
            model.appDefinitionChanged()
            step = .information
            model.status = "Field \u{201C}\(label.capitalized)\u{201D} added."
            return
        }
        if let label = firstWord(after: ["remove field ", "delete field "], in: text) {
            if let index = target.fields.firstIndex(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame || $0.key.caseInsensitiveCompare(label) == .orderedSame }) {
                target.fields.remove(at: index)
                model.store.updateApp(target)
                model.appDefinitionChanged()
                model.status = "Field \u{201C}\(label)\u{201D} removed."
            } else {
                model.status = "I could not find a field called \u{201C}\(label)\u{201D}."
            }
            return
        }
        if let newName = firstWord(after: ["rename app to ", "call it ", "rename it to "], in: text) {
            target.name = newName
            model.store.updateApp(target)
            model.status = "Renamed to \u{201C}\(newName)\u{201D}."
            return
        }
        model.status = "Try \u{201C}add field venue\u{201D}, \u{201C}go to Function\u{201D} or \u{201C}rename app to Holi\u{201D}."
    }

    private func firstWord(after prefixes: [String], in text: String) -> String? {
        let lower = text.lowercased()
        for prefix in prefixes {
            if let range = lower.range(of: prefix) {
                let start = text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound))
                let value = text[start...].trimmingCharacters(in: CharacterSet(charactersIn: " .\"\u{201C}\u{201D}"))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }
}

// MARK: - Create screens

struct WishCreateView: View {
    @ObservedObject var model: WishStudioModel
    @ObservedObject var builder: WishBuilderState

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    progress
                    switch builder.stage {
                    case .describe: describe
                    case .questions: questions
                    case .preview: summary
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WishTheme.line, lineWidth: 1))

            if builder.draft != nil && builder.stage != .describe {
                draftPreview.frame(width: 360)
            }
        }
    }

    // MARK: Pieces

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach([("Describe", 0), ("Fill what is missing", 1), ("Preview", 2)], id: \.1) { item in
                let active = builder.stage.rawValue == item.1
                let done = builder.stage.rawValue > item.1
                HStack(spacing: 6) {
                    Image(systemName: done ? "checkmark.circle.fill" : "\(item.1 + 1).circle.fill")
                        .foregroundStyle(active || done ? WishTheme.accent : WishTheme.line)
                    Text(item.0).font(.system(size: 12, weight: active ? .semibold : .regular)).foregroundStyle(active ? WishTheme.ink : WishTheme.muted)
                }
                if item.1 < 2 { Rectangle().fill(WishTheme.line).frame(height: 1).frame(maxWidth: 40) }
            }
            Spacer()
        }
    }

    private var describe: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What app do you want to make?").font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Say it in your own words, in English or \u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}. WishBuilder builds the app and asks for anything it does not know.")
                    .font(.system(size: 13))
                    .foregroundStyle(WishTheme.muted)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $builder.prompt)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 130)
                    .background(RoundedRectangle(cornerRadius: 12).fill(WishTheme.page))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WishTheme.line, lineWidth: 1))
                if builder.prompt.isEmpty {
                    Text("For example: a Rakhi card for my brother Rahul from Priya")
                        .font(.system(size: 15))
                        .foregroundStyle(WishTheme.muted.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                wishCaption("Ideas, tap one")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(WishBuilderState.examples, id: \.self) { example in
                        Button {
                            builder.prompt = example
                        } label: {
                            Text(example)
                                .font(.system(size: 12))
                                .multilineTextAlignment(.leading)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 10).fill(WishTheme.accentSoft.opacity(0.6)))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WishTheme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Button {
                    builder.buildDraft()
                } label: {
                    Label("Build my app", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(builder.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("or tap the mic below and talk").font(.system(size: 12)).foregroundStyle(WishTheme.muted)
            }
            Text("WishBuilder reads your words for the occasion, names, dates and lists. It does not use AI, so check the result and edit it in the five steps.")
                .font(.system(size: 11))
                .foregroundStyle(WishTheme.muted)
        }
    }

    private var questions: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("A few things I need").font(.system(size: 22, weight: .bold, design: .rounded))
                Text("These were not in your description. Fill what you know, or leave a box and the default stays.")
                    .font(.system(size: 13))
                    .foregroundStyle(WishTheme.muted)
            }
            ForEach(builder.draft?.questions ?? []) { question in
                questionCard(question)
            }
            HStack {
                Button("Back") { builder.stage = .describe }
                Button {
                    builder.stage = .preview
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func questionCard(_ question: WishQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.ask).font(.system(size: 14, weight: .semibold))
            Text(question.askHi).font(.system(size: 12)).foregroundStyle(WishTheme.muted)
            switch question.kind {
            case .text:
                if question.longAnswer {
                    TextEditor(text: Binding(get: { question.answer }, set: { builder.setAnswer(question.id, $0) }))
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 70)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WishTheme.line, lineWidth: 1))
                } else {
                    TextField(question.placeholder, text: Binding(get: { question.answer }, set: { builder.setAnswer(question.id, $0) }))
                        .textFieldStyle(.roundedBorder)
                }
            case .collection:
                Picker("", selection: Binding(get: { question.answer }, set: { builder.setAnswer(question.id, $0) })) {
                    Text("No, I will type it").tag("")
                    ForEach(model.collections, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(WishTheme.page))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WishTheme.line, lineWidth: 1))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ready to create").font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Check the preview on the right. You can change everything later in the Studio and in the five steps.")
                    .font(.system(size: 13))
                    .foregroundStyle(WishTheme.muted)
            }
            if builder.draft != nil {
                VStack(alignment: .leading, spacing: 5) {
                    Text("App name").font(.system(size: 12, weight: .semibold))
                    TextField("Name", text: Binding(get: { builder.draft?.app.name ?? "" }, set: { builder.draft?.app.name = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                }
                VStack(alignment: .leading, spacing: 5) {
                    wishCaption("What it will have")
                    ForEach(builder.draft?.app.fields ?? []) { field in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(WishTheme.accent).font(.system(size: 11))
                            Text(field.label).font(.system(size: 12, weight: .medium))
                            Text(field.value.replacingOccurrences(of: "\n", with: " \u{00B7} "))
                                .font(.system(size: 12))
                                .foregroundStyle(WishTheme.muted)
                                .lineLimit(1)
                        }
                    }
                    if let link = builder.draft?.app.links.first {
                        HStack(spacing: 8) {
                            Image(systemName: "tray.full.fill").foregroundStyle(WishTheme.accent).font(.system(size: 11))
                            Text("Names from \(link.collection)").font(.system(size: 12, weight: .medium))
                        }
                    }
                }
                if !builder.unanswered.isEmpty {
                    Text("Still using defaults for: " + builder.unanswered.compactMap { builder.draft?.app.field($0.fieldKey)?.label }.joined(separator: ", ") + ".")
                        .font(.system(size: 11))
                        .foregroundStyle(WishTheme.muted)
                }
            }
            HStack {
                Button("Back") { builder.stage = (builder.draft?.questions.isEmpty ?? true) ? .describe : .questions }
                Button {
                    builder.createApp()
                } label: {
                    Label("Create app", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var draftPreview: some View {
        VStack(spacing: 8) {
            HStack {
                Circle().fill(Color.green.opacity(0.7)).frame(width: 7, height: 7)
                Text("PREVIEW").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(WishTheme.muted)
                Spacer()
            }
            WishWebView(stateJSON: previewJSON)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WishTheme.line, lineWidth: 1))
        }
    }

    private var previewJSON: String {
        guard let app = builder.draft?.app else { return "{}" }
        let design = WishDesigns.design(id: app.designID ?? "", kind: app.kind)
        let card = WishCard.make(for: app, designID: design.id)
        let context = model.store.context(for: card, app: app)
        return WishHTML.stateJSON(app: app, card: card, design: design, context: context, selected: nil) { _ in "" }
    }
}
