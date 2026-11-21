// Ask KeyDo: type what you want to do and KeyDo says which app or section helps, with a button that opens it.
// It works on this Mac from a list of KeyDo's own features (no AI key needed).
import SwiftUI

extension Notification.Name {
    /// Opens a section of KeyDo. userInfo: "section" (a navigation id), optional "app" (an AppBuilder app to show first).
    static let keydoOpenSection = Notification.Name("keydoOpenSection")
}

struct KeyDoTopic: Identifiable {
    var id: String { title }
    var title: String
    var line: String
    var keywords: [String]
    var section: String
    var app: String? = nil
}

enum KeyDoTopics {
    static let all: [KeyDoTopic] = [
        KeyDoTopic(title: "Shortcuts", line: "Short words that turn into long text. Type a backslash and the short word in any app.", keywords: ["shortcut", "type less", "text", "snippet", "expand", "backslash", "reply", "template text"], section: "My shortcuts"),
        KeyDoTopic(title: "Collections", line: "Folders of shortcuts, like customers, products or replies. Sort, search, favourite and share them.", keywords: ["collection", "folder", "group", "customers", "products", "list", "organize shortcuts", "favourite", "favorite"], section: "Collections"),
        KeyDoTopic(title: "Media", line: "Pictures, sounds and videos you can paste in one tap.", keywords: ["media", "picture", "photo", "image", "sound", "audio", "video", "gif"], section: "Sound & media"),
        KeyDoTopic(title: "Live values", line: "Words that fill in today's date, time, city, weather and more by themselves.", keywords: ["date", "time", "weather", "city", "live", "today", "place", "location", "weekday", "month", "year"], section: "Live & dynamic"),
        KeyDoTopic(title: "AppDesigner", line: "Design apps by voice from a bill, NDA or agreement: fill its boxes with variables, shortcuts and media.", keywords: ["invoice", "bill", "nda", "agreement", "contract", "pdf", "document design", "form", "quotation", "certificate"], section: "AppDesigner"),
        KeyDoTopic(title: "AppBuilder", line: "Make your own mini app: say what it does and get a PDF or a picture. Also holds the built-in apps.", keywords: ["app", "build", "mini app", "make an app", "builder", "automate", "tool"], section: "AppBuilder"),
        KeyDoTopic(title: "Collection Builder", line: "Research a topic and build up to 100 editable shortcuts with AI.", keywords: ["build a collection", "generate shortcuts", "research", "100 shortcuts", "collection builder", "ai shortcuts"], section: "AppBuilder", app: "Collection Builder"),
        KeyDoTopic(title: "Prompt Builder", line: "Write a prompt by typing or speaking, add collections and media, then send it to ChatGPT, Grok, Claude or Gemini.", keywords: ["prompt", "chatgpt", "claude", "gemini", "grok", "ask ai", "write a message", "email draft"], section: "AppBuilder", app: "Prompt Builder"),
        KeyDoTopic(title: "Database Organizer", line: "Organize files, contacts, links and tables. Search inside documents, tag them, rename in bulk, and see recent files.", keywords: ["organize", "organizer", "files", "contacts", "database", "documents", "recent files", "tag", "tags", "rename", "bulk rename", "downloaded", "opened", "daily task", "pdf", "word"], section: "AppBuilder", app: "MyDatabase"),
        KeyDoTopic(title: "Photo Collage", line: "Put the front, back, top, left or right views of one thing on one sheet.", keywords: ["collage", "views", "front", "back", "four photos", "product photos", "sheet"], section: "AppBuilder", app: "Photo Collage"),
        KeyDoTopic(title: "Logo on Background", line: "Turn a logo into a transparent PNG and place it on any picture.", keywords: ["logo", "watermark", "transparent", "png", "brand", "stamp"], section: "AppBuilder", app: "Logo on Background"),
        KeyDoTopic(title: "Bollywood 80s", line: "Give any picture a warm, grainy 80s Bollywood film poster look.", keywords: ["bollywood", "80s", "retro", "vintage", "film", "poster look", "old style"], section: "AppBuilder", app: "Bollywood 80s"),
        KeyDoTopic(title: "Template Designer", line: "Design picture templates with text boxes, logos and fonts.", keywords: ["template", "design", "text box", "font", "layout", "canvas"], section: "AppBuilder", app: "Template Designer"),
        KeyDoTopic(title: "WishStudio", line: "Make birthday, Diwali, anniversary and other wish cards. Type a command such as hbd-Rahul to get a card.", keywords: ["wish", "birthday", "hbd", "anniversary", "hwa", "diwali", "festival", "greeting", "card", "invitation", "gift", "gifting"], section: "WishStudio"),
        KeyDoTopic(title: "Ez Studio", line: "Draw and fix pictures with AI.", keywords: ["draw", "ai picture", "generate image", "fix picture", "edit picture", "ai image"], section: "Ez Studio"),
        KeyDoTopic(title: "Marketplace", line: "Get or share shortcut packs with other people.", keywords: ["marketplace", "pack", "share", "sell", "buy", "download pack"], section: "Marketplace"),
        KeyDoTopic(title: "Browser", line: "A web browser inside KeyDo with tabs and a side panel for AI sites.", keywords: ["browser", "website", "web", "google", "tabs", "side panel", "open site"], section: "Browser"),
        KeyDoTopic(title: "Credits", line: "Your balance, the price of each service and where credits were used.", keywords: ["credit", "credits", "balance", "price", "cost", "charge", "coins"], section: "KeyDo credits"),
        KeyDoTopic(title: "AI keys", line: "Paste the keys that let the AI features work. Do it once.", keywords: ["api key", "key", "openai", "ai setup", "connect ai", "not working ai"], section: "API configuration"),
        KeyDoTopic(title: "Account & settings", line: "Your account, colours, backups and sync.", keywords: ["account", "settings", "login", "sign in", "backup", "sync", "colour", "theme"], section: "Settings"),
        KeyDoTopic(title: "Guide", line: "A picture guide to using KeyDo.", keywords: ["help", "guide", "how to", "tutorial", "learn", "what can keydo do", "features"], section: "User guide")
    ]

    static func match(_ question: String, limit: Int = 3) -> [KeyDoTopic] {
        let text = question.lowercased()
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 }
        var scored: [(KeyDoTopic, Int)] = []
        for topic in all {
            var score = 0
            if text.contains(topic.title.lowercased()) { score += 5 }
            for keyword in topic.keywords {
                if text.contains(keyword) { score += keyword.contains(" ") ? 3 : 2 }
                else if words.contains(where: { keyword.hasPrefix($0) && $0.count > 3 }) { score += 1 }
            }
            if score > 0 { scored.append((topic, score)) }
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    static func open(_ topic: KeyDoTopic) {
        var info: [String: String] = ["section": topic.section]
        if let app = topic.app { info["app"] = app }
        NotificationCenter.default.post(name: .keydoOpenSection, object: nil, userInfo: info)
    }
}

struct KeyDoAskCard: View {
    private struct Turn: Identifiable {
        let id = UUID()
        var question: String
        var answer: String
        var topics: [KeyDoTopic]
    }

    @State private var text = ""
    @State private var turns: [Turn] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill").foregroundStyle(Butter.coral)
                Text("Ask KeyDo").font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Say what you want to do. KeyDo shows which app helps and opens it.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField("For example: make a birthday card, rename files, add my logo to a photo", text: $text)
                    .textFieldStyle(.roundedBorder).onSubmit { ask() }
                Button("Ask") { ask() }.buttonStyle(.borderedProminent).tint(Butter.coral).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(turns.suffix(3)) { turn in
                VStack(alignment: .leading, spacing: 6) {
                    Text(turn.question).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    Text(turn.answer).font(.callout)
                    ForEach(turn.topics) { topic in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title).font(.system(size: 13, weight: .semibold))
                                Text(topic.line).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Open") { KeyDoTopics.open(topic) }.buttonStyle(.bordered).controlSize(.small)
                        }
                        .padding(8).background(Butter.coral.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(14)
        .background(Butter.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }

    private func ask() {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        let found = KeyDoTopics.match(question)
        let answer: String
        if found.isEmpty {
            answer = "I could not match that to a feature. Try a few plain words, such as \u{201C}card\u{201D}, \u{201C}invoice\u{201D}, \u{201C}tag files\u{201D} or \u{201C}logo\u{201D}. Here are good places to start."
        } else if found.count == 1 {
            answer = "\(found[0].title) is the one for this."
        } else {
            answer = "These can help, best match first:"
        }
        let list = found.isEmpty ? Array(KeyDoTopics.all.filter { ["WishStudio", "AppBuilder", "Database Organizer"].contains($0.title) }) : found
        turns.append(Turn(question: question, answer: answer, topics: list))
        text = ""
    }
}

// MARK: - The Ask KeyDo tab and the picture guide

enum KeyDoHowTo {
    static func slug(_ title: String) -> String {
        title.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Where the guide's pictures live. They are published with each release at ezme.ezyourlife.com/guide/images/.
    static func imageURL(_ title: String) -> URL? { URL(string: "https://ezme.ezyourlife.com/guide/images/" + slug(title) + ".png") }

    static let steps: [String: [String]] = [
        "Shortcuts": ["Press Add shortcut and give it a short word and the long text.", "In any app type a backslash, then the short word.", "Pick the result, or finish the word and press Space."],
        "Collections": ["Open Collections and pick a folder of shortcuts.", "Use the search, sort and the heart on a tile to find and favourite.", "Press Rename or Share on a collection when you need to."],
        "Prompt Builder": ["Type or speak your prompt, or press a starter under Skip the blank page.", "Press + Add context to bring in collections, media, files, people, apps or functions.", "Check the prompt on the right, then press Send to ChatGPT, Grok, Claude or Gemini."],
        "Database Organizer": ["Open Database Organizer and scan a folder in the Organizer tab.", "Use Recent Files to see what you opened or downloaded; tick files to rename or tag them.", "Use Manage tags to rename or delete a tag everywhere."],
        "Photo Collage": ["Pick up to four pictures from your Mac, the library or the clipboard.", "Choose the sheet shape and colour.", "Press Make picture, then Save PNG or Send to app as template."],
        "Logo on Background": ["Choose your logo and tick Make the plain background transparent.", "Choose the picture to put it on and pick a corner.", "Set size and see-through level, then Make picture."],
        "Bollywood 80s": ["Choose a picture.", "Pick a look and type an optional film title.", "Press Make picture and save it."],
        "WishStudio": ["Open an app such as Happy Birthday and pick or paste artwork.", "Add text layers, drag them, resize them and set the angle and font.", "Choose a command word and press Activate, then type it in the popup."],
        "Ask KeyDo": ["Type what you want to do in plain words.", "Read the matches and press Open on the one you want."]
    ]
}

struct KeyDoFeatureGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(KeyDoTopics.all) { topic in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(topic.title).font(.system(size: 16, weight: .bold, design: .rounded))
                        Spacer()
                        Button("Open") { KeyDoTopics.open(topic) }.buttonStyle(.bordered).controlSize(.small)
                    }
                    Text(topic.line).font(.callout).foregroundStyle(.secondary)
                    if let steps = KeyDoHowTo.steps[topic.title] {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(.white).frame(width: 20, height: 20).background(Butter.coral, in: Circle())
                                Text(step).font(.callout)
                            }
                        }
                    }
                    if let url = KeyDoHowTo.imageURL(topic.title) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Butter.honey))
                            case .failure: Text("Picture of this screen coming soon.").font(.caption).foregroundStyle(.secondary)
                            default: ProgressView().controlSize(.small)
                            }
                        }
                        .frame(maxWidth: 640, alignment: .leading)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Butter.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

/// The Ask KeyDo tab: chat, a list of what every app does, and the guide with pictures.
struct KeyDoChatPage: View {
    @State private var tab = "Ask"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EzMeSectionHero(title: "Ask KeyDo", subtitle: "Say what you want to do. KeyDo shows which app helps and opens it.", symbol: "bubble.left.and.text.bubble.right.fill", eyebrow: "YOUR HELPER")
            Picker("", selection: $tab) {
                Text("Ask").tag("Ask"); Text("What each app does").tag("Apps"); Text("How to use, with pictures").tag("Guide")
            }.pickerStyle(.segmented).labelsHidden().frame(width: 480)
            switch tab {
            case "Apps":
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                    ForEach(KeyDoTopics.all) { topic in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(topic.title).font(.system(size: 15, weight: .bold, design: .rounded))
                            Text(topic.line).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Open") { KeyDoTopics.open(topic) }.buttonStyle(.bordered).controlSize(.small)
                        }
                        .padding(12).frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                        .background(Butter.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            case "Guide":
                KeyDoFeatureGuide()
            default:
                KeyDoAskCard()
                Text("Try: \u{201C}make a birthday card\u{201D}, \u{201C}rename my files\u{201D}, \u{201C}put my logo on a photo\u{201D}, \u{201C}where are my credits\u{201D}.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
    }
}
