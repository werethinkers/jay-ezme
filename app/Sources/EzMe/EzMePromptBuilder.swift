// Prompt Builder: a built-in AppBuilder app (like Collection Builder and MyDatabase) that can't be deleted.
//
// Type or speak a prompt. Shortcut codes in it are resolved as you go:
//   #photo.media       a shortcut or collection record: media becomes an attachment, text expands to its text
//   @rahul             a person (collection record) or an app shortcut
//   =date  =2+5        a function, written out (see EzMePromptTokens.swift; spoken commands are there too)
//   /photo or \photo   the older marks still work; a word without a mark is never turned into a shortcut
// The second box shows the prompt live with spelling and capital-letter fixes and the shortcuts written out.
// The buttons (ChatGPT, Grok, Claude, Gemini and any site added later) open the site in the browser side
// panel, type the prompt, attach the media and press send.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension Notification.Name {
    static let keydoSendPrompt = Notification.Name("KeyDoSendPrompt")
    static let keydoPromptTargetsChanged = Notification.Name("KeyDoPromptTargetsChanged")
}

// MARK: - Sites the prompt can be sent to

/// What KeyDo found when it read an AI page: the prompt box, the upload slots and the button that starts the work.
struct LearnedPage: Codable, Equatable {
    var summary: String
    var promptHint: String
    var uploadSlots: Int
    var kind: String          // "video", "image" or "chat"
    var generateLabel: String
}

struct PromptTarget: Codable, Identifiable, Equatable {
    var name: String
    var url: String
    var editor: [String]
    var send: [String]
    var builtIn: Bool = false
    var learned: LearnedPage? = nil
    var id: String { name }
}

enum PromptTargets {
    static let defaults: [PromptTarget] = [
        PromptTarget(name: "ChatGPT", url: "https://chatgpt.com/",
                     editor: ["#prompt-textarea", "div.ProseMirror[contenteditable='true']", "textarea"],
                     send: ["button[data-testid='send-button']", "button[aria-label='Send prompt']", "button[aria-label*='Send' i]"], builtIn: true),
        PromptTarget(name: "Grok", url: "https://grok.com/",
                     editor: ["textarea", "div.ProseMirror[contenteditable='true']", "[contenteditable='true']"],
                     send: ["button[type='submit']", "button[aria-label='Submit']", "button[aria-label*='Send' i]"], builtIn: true),
        PromptTarget(name: "Claude", url: "https://claude.ai/new",
                     editor: ["div.ProseMirror[contenteditable='true']", "[contenteditable='true']"],
                     send: ["button[aria-label='Send message']", "button[aria-label*='Send' i]"], builtIn: true),
        PromptTarget(name: "Gemini", url: "https://gemini.google.com/app",
                     editor: ["rich-textarea .ql-editor", "div.ql-editor[contenteditable='true']", "[contenteditable='true']"],
                     send: ["button.send-button", "button[aria-label*='Send' i]"], builtIn: true),
        PromptTarget(name: "Perplexity", url: "https://www.perplexity.ai/",
                     editor: ["textarea", "[contenteditable='true']"],
                     send: ["button[aria-label*='Submit' i]", "button[type='submit']", "button[aria-label*='Send' i]"], builtIn: true),
    ]

    private static let customKey = "keydoPromptTargetsCustom"

    static func custom() -> [PromptTarget] {
        guard let data = UserDefaults.standard.data(forKey: customKey),
              let items = try? JSONDecoder().decode([PromptTarget].self, from: data) else { return [] }
        return items
    }

    private static let hiddenKey = "keydoPromptTargetsHidden"
    private static let overrideKey = "keydoPromptTargetsURLOverrides"

    static func hidden() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []) }
    private static func overrides() -> [String: String] { UserDefaults.standard.dictionary(forKey: overrideKey) as? [String: String] ?? [:] }

    static func load() -> [PromptTarget] {
        let hiddenNames = hidden()
        let changed = overrides()
        let shown = defaults.filter { !hiddenNames.contains($0.name) }.map { target -> PromptTarget in
            var copy = target
            if let url = changed[target.name], !url.isEmpty { copy.url = url }
            return copy
        }
        return shown + custom()
    }

    /// Takes a link away. The built-in sites are hidden (they can be brought back); added sites are deleted.
    static func delete(_ target: PromptTarget) {
        if target.builtIn {
            UserDefaults.standard.set(Array(hidden().union([target.name])), forKey: hiddenKey)
        } else {
            removeCustom(target.name)
        }
    }

    static func restoreBuiltIns() {
        UserDefaults.standard.removeObject(forKey: hiddenKey)
        UserDefaults.standard.removeObject(forKey: overrideKey)
    }

    /// Changes the address (and for an added site, the name). An added site keeps what was learned only if its address is the same.
    static func edit(_ target: PromptTarget, name: String, url: String) {
        var cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty else { return }
        if !cleanURL.lowercased().hasPrefix("http") { cleanURL = "https://" + cleanURL }
        if target.builtIn {
            var changed = overrides()
            changed[target.name] = cleanURL
            UserDefaults.standard.set(changed, forKey: overrideKey)
            return
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        var items = custom()
        guard let index = items.firstIndex(where: { $0.name == target.name }) else { return }
        if cleanURL != items[index].url { items[index].learned = nil }
        items[index].name = cleanName
        items[index].url = cleanURL
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: customKey) }
    }

    /// Adds a site of the person's choice. It uses general-purpose selectors for the prompt box and send button.
    static func addCustom(name: String, url: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanURL.isEmpty else { return }
        if !cleanURL.lowercased().hasPrefix("http") { cleanURL = "https://" + cleanURL }
        var items = custom().filter { $0.name.caseInsensitiveCompare(cleanName) != .orderedSame }
        items.append(PromptTarget(name: cleanName, url: cleanURL,
                                  editor: ["textarea", "div.ProseMirror[contenteditable='true']", "[contenteditable='true']", "div[role='textbox']"],
                                  send: ["button[type='submit']", "button[aria-label*='Send' i]", "button[aria-label*='Submit' i]"]))
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: customKey) }
    }

    static func setLearned(_ learned: LearnedPage, for name: String) {
        var items = custom()
        guard let index = items.firstIndex(where: { $0.name == name }) else { return }
        items[index].learned = learned
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: customKey) }
    }

    static func removeCustom(_ name: String) {
        let items = custom().filter { $0.name != name }
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: customKey) }
    }
}

// MARK: - Turning the typed text into the live prompt

struct PromptAttachment: Identifiable, Equatable {
    var id: String
    var name: String
    var kind: String
    var paths: [String]
}

struct PromptComposition: Equatable {
    var text: String
    var attachments: [PromptAttachment]
    var fixes: [String]
}

enum PromptComposer {
    private static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff", "bmp"]
    private static let videoTypes: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]

    static func existingFiles(_ clip: Clip) -> [String] {
        clip.files.filter { FileManager.default.fileExists(atPath: $0) }
    }

    private static func kind(of path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if imageTypes.contains(ext) { return "Image" }
        if videoTypes.contains(ext) { return "Video" }
        return "File"
    }

    private static func cleanKey(_ key: String) -> String {
        key.trimmingCharacters(in: CharacterSet(charactersIn: "/\\")).lowercased()
    }

    /// Words that are names or codes in the person's own data. They are never auto-corrected.
    static func vocabulary(clips: [Clip], records: [CollectionRecord]) -> Set<String> {
        var words = Set<String>()
        func add(_ text: String) {
            for piece in text.lowercased().components(separatedBy: CharacterSet.letters.inverted) where piece.count > 1 { words.insert(piece) }
        }
        for clip in clips { add(clip.key); add(clip.name) }
        for record in records.prefix(5000) {
            add(record.alias); add(record.name)
            for value in record.values.values.prefix(20) { add(String(value.prefix(80))) }
        }
        return words
    }

    private struct Segment {
        var text: String
        var isWord: Bool
    }

    private static func segments(_ raw: String) -> [Segment] {
        var result: [Segment] = []
        var current = ""
        var currentIsWord = false
        for ch in raw {
            let isSeparator = ch == " " || ch == "\n" || ch == "\t"
            if current.isEmpty {
                current = String(ch)
                currentIsWord = !isSeparator
            } else if isSeparator == !currentIsWord {
                current.append(ch)
            } else {
                result.append(Segment(text: current, isWord: currentIsWord))
                current = String(ch)
                currentIsWord = !isSeparator
            }
        }
        if !current.isEmpty { result.append(Segment(text: current, isWord: currentIsWord)) }
        return result
    }

    static func compose(_ raw: String, clips: [Clip], records: [CollectionRecord], apps: [PromptAppEntry] = [], vocabulary: Set<String>, autocorrect: Bool) -> PromptComposition {
        let leadSet = CharacterSet(charactersIn: "(\"'“‘[")
        let trailSet = CharacterSet(charactersIn: ",.;:!?)\"'”’]")
        var output = ""
        var attachments: [PromptAttachment] = []
        var fixes: [String] = []
        var startOfSentence = true
        let checker = NSSpellChecker.shared
        var checked = 0

        for segment in segments(raw) {
            if !segment.isWord {
                if segment.text.contains("\n") { output += segment.text; startOfSentence = true }
                else { output += segment.text.count > 1 ? " " : segment.text }
                continue
            }
            var lead = ""
            var core = segment.text
            var trail = ""
            while let first = core.unicodeScalars.first, leadSet.contains(first) { lead.unicodeScalars.append(first); core.unicodeScalars.removeFirst() }
            while let last = core.unicodeScalars.last, trailSet.contains(last) { trail = String(last) + trail; core.unicodeScalars.removeLast() }
            let endsSentence = trail.contains(".") || trail.contains("!") || trail.contains("?")

            if core.hasPrefix("=") {
                var value = PromptFunctions.evaluate(core)
                var rest = trail
                if value == nil, trail.hasPrefix(")"), let whole = PromptFunctions.evaluate(core + ")") {
                    value = whole
                    rest = String(trail.dropFirst())
                }
                if let value = value {
                    output += lead + value + rest
                    startOfSentence = endsSentence
                    continue
                }
            }

            if let replacement = resolve(core, clips: clips, records: records, apps: apps, attachments: &attachments) {
                output += lead + replacement + trail
                startOfSentence = endsSentence
                continue
            }

            var word = core
            if autocorrect, !word.isEmpty {
                let lower = word.lowercased()
                let contractions = ["i": "I", "i'm": "I'm", "i'll": "I'll", "i've": "I've", "i'd": "I'd", "im": "I'm", "dont": "don't", "cant": "can't", "wont": "won't", "didnt": "didn't", "doesnt": "doesn't", "isnt": "isn't", "thats": "that's"]
                if let fixed = contractions[lower], word != fixed {
                    fixes.append("\(word) → \(fixed)")
                    word = fixed
                } else if word.count >= 4, checked < 300, word.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }),
                          word == lower, !vocabulary.contains(lower) {
                    checked += 1
                    let miss = checker.checkSpelling(of: word, startingAt: 0)
                    if miss.location != NSNotFound, miss.length == (word as NSString).length,
                       let guess = checker.correction(forWordRange: miss, in: word, language: checker.language(), inSpellDocumentWithTag: 0),
                       !guess.isEmpty, guess.lowercased() != lower, !guess.contains(" "), abs(guess.count - word.count) <= 2 {
                        fixes.append("\(word) → \(guess)")
                        word = guess
                    }
                }
                if startOfSentence, let first = word.first, first.isLowercase, word.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) || $0 == "'" }) {
                    let capitalised = first.uppercased() + word.dropFirst()
                    if capitalised != word {
                        if fixes.last != "\(word) → \(capitalised)" { fixes.append("\(word) → \(capitalised)") }
                        word = capitalised
                    }
                }
            }
            output += lead + word + trail
            startOfSentence = endsSentence
        }
        return PromptComposition(text: output.trimmingCharacters(in: .whitespacesAndNewlines), attachments: attachments, fixes: Array(fixes.prefix(12)))
    }

    private static func matchClip(_ name: String, _ clips: [Clip]) -> Clip? {
        if let exact = clips.first(where: { cleanKey($0.key) == name }) { return exact }
        return clips.first(where: { cleanKey($0.key).hasPrefix(name + ".") })
    }

    private static func recordText(_ name: String, records: [CollectionRecord], attachments: inout [PromptAttachment]) -> String? {
        guard let record = records.first(where: { $0.alias.lowercased() == name }) else { return nil }
        let details = record.values.sorted { $0.key < $1.key }.filter { !$0.value.isEmpty }.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
        let title = record.name.isEmpty ? record.alias : record.name
        for path in record.files where FileManager.default.fileExists(atPath: path) {
            let id = record.id + path
            if !attachments.contains(where: { $0.id == id }) {
                attachments.append(PromptAttachment(id: id, name: title, kind: kind(of: path), paths: [path]))
            }
        }
        return details.isEmpty ? title : "\(title) (\(details))"
    }

    /// #shortcut, #record, @person or app, /shortcut and \\shortcut, written out. Nil for an ordinary word.
    /// A word without one of these marks is never touched, so ordinary words cannot turn into shortcuts by accident.
    private static func resolve(_ core: String, clips: [Clip], records: [CollectionRecord], apps: [PromptAppEntry], attachments: inout [PromptAttachment]) -> String? {
        guard core.count >= 2, let marker = core.first, "/\\@#".contains(marker) else { return nil }
        let name = String(core.dropFirst()).lowercased()
        guard !name.isEmpty else { return nil }

        if marker == "@" {
            if let person = recordText(name, records: records, attachments: &attachments) { return person }
            if let app = apps.first(where: { $0.compact.lowercased() == name }) { return "[App: \(app.name)]" }
        }
        if let clip = matchClip(name, clips) {
            let label = clip.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? name : clip.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let isApp = clip.appBundleIdentifier != nil || clip.webURL != nil
            if marker == "@", isApp { return label }
            let files = existingFiles(clip)
            if !files.isEmpty {
                let first = kind(of: files[0])
                if !attachments.contains(where: { $0.id == clip.id.uuidString }) {
                    attachments.append(PromptAttachment(id: clip.id.uuidString, name: label, kind: first, paths: files))
                }
                return "[\(first): \(label)]"
            }
            if !clip.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return clip.text }
            if isApp { return label }
        }
        return recordText(name, records: records, attachments: &attachments)
    }
}

// MARK: - The app

struct PromptAutoMark: Identifiable, Equatable {
    var word: String
    var token: String
    var key: String
    var id: String { token + "|" + word }
}

struct PromptBuilderView: View {
    let clips: [Clip]
    let records: [CollectionRecord]
    var builderApps: [String] = []
    var dataDirectory: URL? = nil

    @AppStorage("keydoPromptBuilderText") private var text = ""
    @AppStorage("keydoPromptAutoCorrect") private var autoCorrect = true
    @State private var vocabulary = Set<String>()
    @State private var composition = PromptComposition(text: "", attachments: [], fixes: [])
    @State private var aiText: String?
    @State private var aiBusy = false
    @State private var notice = ""
    @State private var voiceBase = ""
    @State private var hovered: String?
    @State private var targets = PromptTargets.load()
    @State private var voiceSent = 0
    @State private var markIndex = PromptMarkIndex()
    @State private var apps = [PromptAppEntry]()
    @State private var autoMarks = [PromptAutoMark]()
    @State private var mediaList = [Clip]()
    @State private var plainList = [Clip]()
    @State private var dismissed = Set<String>()
    @State private var heard = ""
    @State private var dictating = false
    @State private var lastText = ""
    @State private var programmatic: String?
    @State private var flashTarget: String?
    @State private var recomputeTask: Task<Void, Never>?
    @FocusState private var editorFocused: Bool
    @State private var voiceHint = ""
    @State private var showVoiceHelp = false
    @State private var showAddSite = false
    @State private var editingSites = false
    @State private var siteBeingEdited: PromptTarget?
    @State private var editSiteName = ""
    @State private var editSiteURL = ""
    @State private var newSiteName = ""
    @State private var newSiteURL = ""

    private var finalPrompt: String { aiText ?? composition.text }
    private var canSend: Bool { !finalPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !composition.attachments.isEmpty }

    private var suggestions: [PromptSuggestion] {
        guard let token = PromptSuggestions.lastToken(in: text) else { return [] }
        return PromptSuggestions.suggestions(for: token, clips: clips, records: records, apps: apps)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                HStack(alignment: .top, spacing: 16) {
                    typingBox
                    liveBox
                }
                sendBox
                if !notice.isEmpty { Text(notice).font(.callout).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: 1240, alignment: .leading)
            .padding(26)
        }
        .onAppear { recompute(); lastText = text }
        .task(id: clips.count + records.count + builderApps.count) {
            vocabulary = PromptComposer.vocabulary(clips: clips, records: records)
            let catalog = await MainActor.run { PromptAppCatalog.load(builderApps: builderApps, wishDirectory: dataDirectory) }
            apps = catalog
            markIndex = PromptMarkIndex.build(clips: clips, records: records, apps: catalog)
            mediaList = clips.filter { !PromptComposer.existingFiles($0).isEmpty }
            let mediaIDs = Set(mediaList.map { $0.id })
            plainList = clips.filter { !mediaIDs.contains($0.id) }
            EzMeSpeechDictation.contextualHints = PromptVoice.contextualHints(targets: targets, clips: clips, records: records)
            recompute()
        }
        .onChange(of: text) { value in textChanged(value) }
        .onChange(of: autoCorrect) { _ in recompute() }
        .sheet(isPresented: $showAddSite) { addSiteSheet }
        .sheet(item: $siteBeingEdited) { _ in editSiteSheet }
        .onReceive(NotificationCenter.default.publisher(for: .keydoPromptTargetsChanged)) { _ in targets = PromptTargets.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prompt Builder").font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Type or speak a prompt, then send it to an AI site in the side panel.")
                .font(.subheadline).foregroundStyle(.secondary)
            tokenGuide.padding(.top, 6)
        }
    }

    private var tokenGuide: some View {
        HStack(spacing: 10) {
            guideCard("#", "Shortcuts and collections", "#rohit.media", .purple)
            guideCard("@", "People and apps", "@priya", .blue)
            guideCard("=", "Functions", "=date  =2+5", .orange)
            Button { showVoiceHelp.toggle() } label: { Label("Voice commands", systemImage: "waveform") }
                .buttonStyle(.bordered)
                .popover(isPresented: $showVoiceHelp, arrowEdge: .bottom) { voiceHelp }
        }
    }

    private func guideCard(_ mark: String, _ title: String, _ example: String, _ tint: Color) -> some View {
        Button { startToken(mark) } label: {
            HStack(spacing: 8) {
                Text(mark).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(tint)
                    .frame(width: 30, height: 30).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption.weight(.semibold))
                    Text(example).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Click to start typing \(mark)")
    }

    private var voiceHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Say these while listening").font(.headline)
            ForEach(Array(PromptVoice.helpRows.enumerated()), id: \.offset) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("“\(entry.element.say)”").font(.callout.weight(.semibold))
                    Text(entry.element.result).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 460, alignment: .leading)
    }

    // MARK: Typing

    private var typingBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR PROMPT · TYPE OR SPEAK").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(size: 15))
                .frame(minHeight: 200)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(editorFocused ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.25), lineWidth: editorFocused ? 2 : 1))
                .focused($editorFocused)
            HStack(spacing: 8) {
                PromptMicButton(
                    onStart: { voiceBase = text; voiceSent = 0; dictating = false; voiceHint = "Listening… try “hash”, “equals date”, “accept suggestion 1” or “enter chatgpt”" },
                    onStop: { heard = ""; if voiceHint.hasPrefix("Listening") { voiceHint = "" } },
                    onText: { spoken, final in heardSpeech(spoken, final: final) }
                )
                Button { toggleDictation() } label: {
                    Label(dictating ? "Stop macOS dictation" : "macOS dictation", systemImage: dictating ? "stop.circle.fill" : "keyboard")
                        .foregroundStyle(dictating ? .red : .blue)
                }
                .buttonStyle(.bordered)
                .help("Use the Mac's own keyboard dictation. The command words still work.")
                Spacer()
                Button("Clear") { text = ""; notice = ""; heard = ""; voiceHint = ""; dismissed = [] }.disabled(text.isEmpty)
            }
            HStack(spacing: 4) {
                Menu("# Collections") { collectionsMenu }
                Menu("# Media") { mediaMenu }
                Menu("@ Apps") { appsMenu }
                Menu("= Functions") { functionsMenu }
                Spacer(minLength: 0)
            }
            .menuStyle(.borderlessButton)
            if !heard.isEmpty { Label("Heard: \(heard)", systemImage: "ear").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            markStrip
            suggestionStrip
            if !voiceHint.isEmpty { Label(voiceHint, systemImage: "mic.fill").font(.caption).foregroundStyle(.secondary) }
            attachmentChips
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var suggestionStrip: some View {
        let items = suggestions
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items) { item in
                        Button { accept(item) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: item.symbol).font(.caption)
                                Text(item.title).font(.caption.weight(.semibold))
                                if !item.detail.isEmpty { Text(item.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private var functionsMenu: some View {
        ForEach(Array(PromptFunctions.names.enumerated()), id: \.offset) { entry in
            Button("=\(entry.element.name) · \(entry.element.detail)") { insert("=" + entry.element.name) }
        }
        Button("=2+5 · a sum") { insert("=2+5") }
    }

    private var shownMarks: [PromptAutoMark] { autoMarks.filter { text.contains($0.token) } }

    @ViewBuilder private var markStrip: some View {
        let items = shownMarks
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Label("Marked for you · tap ✕ to undo", systemImage: "sparkles").font(.caption.weight(.bold)).foregroundStyle(.orange)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        HStack(spacing: 6) {
                            Text(item.word).font(.caption).strikethrough().lineLimit(1)
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                            Text(item.token).font(.caption.monospaced().weight(.semibold)).lineLimit(1)
                            Button { reject(item) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain).help("Not this one: put back \(item.word)")
                        }
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }

    private func reject(_ mark: PromptAutoMark) {
        dismissed.insert(mark.key)
        autoMarks.removeAll { $0.id == mark.id }
        let restored = text.replacingOccurrences(of: mark.token, with: mark.word)
        programmatic = restored
        text = restored
    }

    /// Plain words that match a shortcut, collection record, person or app get their # or @ on their own.
    /// The word still being typed or heard is left alone until it is finished.
    private func autoMarked(_ source: String, final: Bool) -> String {
        let list = PromptFixes.fixes(in: source, index: markIndex, dismissed: dismissed, limit: 200)
        var chosen = list
        if !final {
            let end = (source as NSString).length
            chosen = list.filter { $0.range.location + $0.range.length < end }
        }
        guard !chosen.isEmpty else { return source }
        for fix in chosen {
            let item = PromptAutoMark(word: fix.word, token: fix.token, key: fix.key)
            if !autoMarks.contains(where: { $0.id == item.id }) { autoMarks.append(item) }
        }
        if autoMarks.count > 8 { autoMarks.removeFirst(autoMarks.count - 8) }
        return PromptFixes.applyAll(chosen, to: source)
    }

    // MARK: Voice

    private func heardSpeech(_ spoken: String, final: Bool) {
        heard = spoken
        let result = PromptVoice.apply(base: voiceBase, spoken: spoken, targets: targets, index: markIndex, dismissed: dismissed)
        dismissed.formUnion(result.dismissed)
        let marked = autoMarked(result.text, final: final)
        programmatic = marked
        text = marked
        if !result.notice.isEmpty { voiceHint = result.notice }
        if result.sends.count > voiceSent, let target = result.sends.last {
            voiceSent = result.sends.count
            sendByVoice(target)
        }
        if final {
            voiceBase = marked
            voiceSent = 0
            heard = ""
        }
    }

    private func sendByVoice(_ target: PromptTarget) {
        voiceHint = "Sending to \(target.name)…"
        // Finish marking the last word first, so a shortcut said just before "enter chatgpt" is attached too.
        let ready = autoMarked(text, final: true)
        if ready != text {
            programmatic = ready
            text = ready
        }
        send(to: target, raw: ready)
    }

    /// The Mac's own keyboard dictation types into the box. Command words in what it types are still understood.
    private func toggleDictation() {
        dictating.toggle()
        if dictating {
            editorFocused = true
            lastText = text
            voiceHint = "macOS dictation is on. Speak; “hashtag”, “equals date” and “enter chatgpt” still work. If nothing happens, turn on Dictation in System Settings → Keyboard."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                _ = NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil)
            }
        } else {
            _ = NSApp.sendAction(Selector(("stopDictation:")), to: nil, from: nil)
            voiceHint = ""
        }
    }

    private func textChanged(_ value: String) {
        defer { lastText = value }
        if value == programmatic { scheduleRecompute(); return }
        var current = value
        var target: PromptTarget?
        if dictating, value.count >= lastText.count + 2, value.hasPrefix(lastText) {
            let chunk = String(value.dropFirst(lastText.count))
            let result = PromptVoice.apply(base: lastText, spoken: chunk, targets: targets, index: markIndex, dismissed: dismissed)
            dismissed.formUnion(result.dismissed)
            current = result.text
            target = result.sends.last
            if !result.notice.isEmpty { voiceHint = result.notice }
        }
        // Typing or dictating at the end: finished words that match a shortcut get their mark.
        if current.count > lastText.count, current.count - lastText.count <= 80, current.hasPrefix(lastText) {
            current = autoMarked(current, final: false)
        }
        if current != value {
            programmatic = current
            text = current
        }
        if let target = target { sendByVoice(target) }
        scheduleRecompute()
    }

    private func scheduleRecompute() {
        recomputeTask?.cancel()
        recomputeTask = Task {
            try? await Task.sleep(nanoseconds: 140_000_000)
            if !Task.isCancelled { recompute() }
        }
    }

    private func accept(_ item: PromptSuggestion) {
        guard let token = PromptSuggestions.lastToken(in: text), text.hasSuffix(token) else { return }
        text = String(text.dropLast(token.count)) + item.insert + " "
    }

    private func byKey(_ a: Clip, _ b: Clip) -> Bool {
        PromptSuggestions.trimmedKey(a.key).localizedStandardCompare(PromptSuggestions.trimmedKey(b.key)) == .orderedAscending
    }

    private func shortcutButton(_ clip: Clip) -> some View {
        let key = PromptSuggestions.trimmedKey(clip.key)
        return Button("\(clip.name.isEmpty ? key : clip.name) · \(key)") { insert("#" + key) }
    }

    /// Every collection, A to Z. The first three entries are the shortcuts made most recently.
    /// Media shortcuts are not here: they are in the # Media menu.
    @ViewBuilder private var collectionsMenu: some View {
        let recent = Array(plainList.prefix(3))
        let names = groupNames
        if plainList.isEmpty && names.isEmpty {
            Text("Nothing here yet")
        } else {
            if !recent.isEmpty {
                Section("Recent") {
                    ForEach(recent) { clip in shortcutButton(clip) }
                }
            }
            ForEach(names, id: \.self) { name in
                Menu(name) { groupItems(name) }
            }
        }
    }

    private var groupNames: [String] {
        var names = Set<String>()
        for clip in plainList { for group in clip.allGroups { names.insert(group) } }
        for record in records where !record.alias.isEmpty { names.insert(record.collection) }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    @ViewBuilder private func groupItems(_ name: String) -> some View {
        let shortcuts = Array(plainList.filter { clip in clip.allGroups.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) }.sorted(by: byKey).prefix(80))
        let people = Array(records.filter { $0.collection == name && !$0.alias.isEmpty }.sorted { $0.alias.localizedStandardCompare($1.alias) == .orderedAscending }.prefix(80))
        ForEach(shortcuts) { clip in shortcutButton(clip) }
        if !shortcuts.isEmpty && !people.isEmpty { Divider() }
        ForEach(people) { record in
            Button(record.name.isEmpty ? record.alias : "\(record.name) · \(record.alias)") { insert("#" + record.alias) }
        }
    }

    @ViewBuilder private var mediaMenu: some View {
        if mediaList.isEmpty {
            Text("No media shortcuts yet")
        } else {
            Section("Recent") {
                ForEach(Array(mediaList.prefix(3))) { clip in shortcutButton(clip) }
            }
            Divider()
            ForEach(Array(mediaList.sorted(by: byKey).prefix(150))) { clip in shortcutButton(clip) }
        }
    }

    /// Apps made in KeyDo: AppBuilder, WishStudio and Ezyourlife apps.
    @ViewBuilder private var appsMenu: some View {
        if apps.isEmpty {
            Text("No apps yet")
        } else {
            ForEach(["AppBuilder", "WishStudio", "Ezyourlife"], id: \.self) { source in
                let items = Array(apps.filter { $0.source == source }.prefix(150))
                if !items.isEmpty {
                    Menu(source) {
                        ForEach(items, id: \.name) { app in
                            Button(app.name) { insert("@" + app.compact) }
                        }
                    }
                }
            }
        }
    }

    private func joined(_ base: String, _ spoken: String) -> String {
        let piece = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        if piece.isEmpty { return base }
        return base + (base.isEmpty || base.hasSuffix(" ") || base.hasSuffix("\n") ? "" : " ") + piece
    }

    /// Writes just the mark (no space after it), so the suggestions for it appear right away.
    private func startToken(_ mark: String) {
        text += (text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " ") + mark
    }

    private func insert(_ token: String) {
        text += (text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " ") + token + " "
    }

    // MARK: Attachments with hover preview

    @ViewBuilder private var attachmentChips: some View {
        if !composition.attachments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("ATTACHED MEDIA · HOVER TO PREVIEW").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(composition.attachments) { item in chip(item) }
                }
            }
        }
    }

    private func chip(_ item: PromptAttachment) -> some View {
        HStack(spacing: 6) {
            thumbnail(item, size: 26)
            Text(item.name).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.purple.opacity(0.10), in: Capsule())
        .onHover { inside in
            if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
        }
        .popover(isPresented: Binding(get: { hovered == item.id }, set: { if !$0 && hovered == item.id { hovered = nil } }), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(item.paths.prefix(3), id: \.self) { path in
                    if let image = NSImage(contentsOfFile: path), item.kind == "Image" {
                        Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 280, maxHeight: 280)
                    } else {
                        Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: item.kind == "Video" ? "film" : "doc")
                    }
                }
                if item.paths.count > 3 { Text("+ \(item.paths.count - 3) more").font(.caption).foregroundStyle(.secondary) }
            }
            .padding(12)
        }
    }

    @ViewBuilder private func thumbnail(_ item: PromptAttachment, size: CGFloat) -> some View {
        if item.kind == "Image", let path = item.paths.first, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: item.kind == "Video" ? "film" : "doc.fill").frame(width: size, height: size).foregroundStyle(.purple)
        }
    }

    // MARK: Live prompt

    private var liveBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(aiText == nil ? "LIVE PROMPT · CORRECTED AS YOU TYPE" : "LIVE PROMPT · POLISHED BY AI")
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
                Toggle("Auto-correct", isOn: $autoCorrect).toggleStyle(.switch).controlSize(.mini)
            }
            ScrollView {
                Text(finalPrompt.isEmpty ? "Your corrected prompt appears here as you type." : finalPrompt)
                    .font(.system(size: 15))
                    .foregroundStyle(finalPrompt.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 200, maxHeight: 260)
            .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.25)))
            if aiText == nil && !composition.fixes.isEmpty {
                Text("Fixed: " + composition.fixes.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            HStack(spacing: 8) {
                Button { polishWithAI() } label: { Label(aiBusy ? "Polishing…" : "Polish with AI", systemImage: "wand.and.stars") }
                    .disabled(aiBusy || composition.text.isEmpty)
                if aiText != nil { Button("Use my words") { aiText = nil } }
                Spacer()
                Button { copyPrompt() } label: { Label("Copy", systemImage: "doc.on.doc") }.disabled(finalPrompt.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func recompute() {
        composition = PromptComposer.compose(text, clips: clips, records: records, apps: apps, vocabulary: vocabulary, autocorrect: autoCorrect)
        aiText = nil
    }

    private func copyPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(finalPrompt, forType: .string)
        notice = "Prompt copied."
    }

    private func polishWithAI() {
        let profiles = AIModelProfileStore.load()
        let selectedID = UserDefaults.standard.string(forKey: "ezmeSelectedAIModelProfile") ?? UserDefaults.standard.string(forKey: "ezmeCollectionSelectedProfile") ?? CollectionAIModelProfile.starter.id
        let profile = profiles.first(where: { $0.id == selectedID }) ?? .starter
        let key = KeyStore.load(account: profile.keyAccount) ?? ""
        guard !key.isEmpty else { notice = "Add an API key in API configuration to polish with AI."; return }
        let source = composition.text
        let snapshot = text
        aiBusy = true
        notice = ""
        Task { @MainActor in
            do {
                let instruction = "Rewrite the text below as one clear, well-structured prompt for an AI assistant. Keep every name, number, date and bracketed attachment label such as [Image: Name] exactly as written. Do not add facts or ask questions. Return only the prompt.\n\n" + source
                let result = try await SharedAIClient.generate(profile: profile, key: key, prompt: instruction, maxTokens: 2000)
                let clean = result.trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.isEmpty { notice = "The AI returned nothing. Your own words are kept." } else if snapshot != text { notice = "You changed the prompt while the AI was working, so its version was not used." } else { aiText = clean }
            } catch {
                notice = "Could not polish: \(error.localizedDescription)"
            }
            aiBusy = false
        }
    }

    // MARK: Send

    private var sendBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SEND TO · OPENS IN THE SIDE PANEL AND STARTS RUNNING").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(targets) { target in
                    if editingSites {
                        HStack(spacing: 4) {
                            Text(target.name).font(.callout.weight(.semibold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Button { beginEdit(target) } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).help("Edit \(target.name)")
                            Button { PromptTargets.delete(target); targets = PromptTargets.load() } label: { Image(systemName: "trash") }.buttonStyle(.borderless).foregroundStyle(.red).help("Delete \(target.name)")
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.12)))
                    } else {
                    Button { send(to: target) } label: {
                        Label(flashTarget == target.name ? "Sending…" : target.name, systemImage: flashTarget == target.name ? "checkmark.circle.fill" : "paperplane.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(flashTarget == target.name ? .green : .purple)
                    .scaleEffect(flashTarget == target.name ? 1.06 : 1)
                    .animation(.easeInOut(duration: 0.2), value: flashTarget)
                    .disabled(!canSend)
                    .contextMenu {
                        Button("Edit \(target.name)\u{2026}") { beginEdit(target) }
                        if !target.builtIn { Button("Read the page again") { learn(target) } }
                        Button("Delete \(target.name)", role: .destructive) { PromptTargets.delete(target); targets = PromptTargets.load() }
                    }
                    }
                }
                Button { showAddSite = true } label: { Label("Add site", systemImage: "plus").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Button { editingSites.toggle() } label: { Label(editingSites ? "Done" : "Edit links", systemImage: editingSites ? "checkmark" : "pencil").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                if editingSites, !PromptTargets.hidden().isEmpty {
                    Button { PromptTargets.restoreBuiltIns(); targets = PromptTargets.load() } label: { Label("Bring back removed sites", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                }
            }
            Text("Attached media goes into the site's own upload box, so the site's own sign-in is used.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(targets.filter { $0.learned != nil }) { target in
                Text("\(target.name): \(target.learned?.summary ?? "")").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func send(to target: PromptTarget, raw: String? = nil) {
        // Work out the prompt and the media fresh from the text, so nothing is stale or missed.
        let source = raw ?? text
        let fresh = PromptComposer.compose(source, clips: clips, records: records, apps: apps, vocabulary: vocabulary, autocorrect: autoCorrect)
        let prompt = (raw == nil ? aiText : nil) ?? fresh.text
        let files = fresh.attachments.flatMap { $0.paths }
        NotificationCenter.default.post(name: .keydoSendPrompt, object: PromptDispatchRequest(target: target, prompt: prompt, files: files))
        let attached = fresh.attachments.count
        notice = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && files.isEmpty
            ? "Opening \(target.name). The prompt is empty, so there is nothing to send yet."
            : "Opening \(target.name) in the side panel and sending your prompt" + (attached > 0 ? " with \(attached) attached media…" : "…")
        flashTarget = target.name
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { if flashTarget == target.name { flashTarget = nil } }
    }

    private func beginEdit(_ target: PromptTarget) {
        editSiteName = target.name
        editSiteURL = target.url
        siteBeingEdited = target
    }

    private var editSiteSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit AI link").font(.title3.weight(.bold))
            TextField("Name", text: $editSiteName).disabled(siteBeingEdited?.builtIn == true)
            TextField("Address", text: $editSiteURL)
            Text(siteBeingEdited?.builtIn == true
                 ? "The name of a built-in site stays the same. You can point it at another address."
                 : "If you change the address, KeyDo reads the new page again.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { siteBeingEdited = nil }
                Button("Save") {
                    guard let target = siteBeingEdited else { return }
                    let oldURL = target.url
                    PromptTargets.edit(target, name: editSiteName, url: editSiteURL)
                    targets = PromptTargets.load()
                    siteBeingEdited = nil
                    if !target.builtIn, let updated = targets.first(where: { $0.name == editSiteName.trimmingCharacters(in: .whitespacesAndNewlines) }), updated.url != oldURL, updated.learned == nil { learn(updated) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(editSiteURL.trimmingCharacters(in: .whitespaces).isEmpty || editSiteName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func learn(_ target: PromptTarget) {
        NotificationCenter.default.post(name: .keydoSendPrompt, object: PromptDispatchRequest(target: target, prompt: "", files: [], learnOnly: true))
        notice = "Opening \(target.name) in the side panel to read the page. Sign in there if it asks."
    }

    private var addSiteSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add an AI site").font(.title3.weight(.bold))
            TextField("Name, for example Mistral", text: $newSiteName)
            TextField("Address, for example chat.mistral.ai", text: $newSiteURL)
            Text("KeyDo opens the page in the side panel and reads it once: the prompt box, the places to add pictures or video, and the Generate or Send button. Sign in there if it asks. Then your prompt and media are put in the right places and it starts running. Image and video sites may use up credits when it presses Generate.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { showAddSite = false }
                Button("Add") {
                    let addedName = newSiteName.trimmingCharacters(in: .whitespacesAndNewlines)
                    PromptTargets.addCustom(name: newSiteName, url: newSiteURL)
                    targets = PromptTargets.load()
                    if let added = targets.first(where: { $0.name == addedName }) { learn(added) }
                    newSiteName = ""
                    newSiteURL = ""
                    showAddSite = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newSiteName.trimmingCharacters(in: .whitespaces).isEmpty || newSiteURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - Sending to the browser side panel

final class PromptDispatchRequest {
    let target: PromptTarget
    let prompt: String
    let files: [String]
    /// Only open the page and read it (prompt box, upload slots, start button); send nothing.
    var learnOnly = false

    init(target: PromptTarget, prompt: String, files: [String], learnOnly: Bool = false) {
        self.target = target
        self.prompt = prompt
        self.files = files
        self.learnOnly = learnOnly
    }
}

@MainActor enum PromptDispatcher {
    /// Opens the site in a new browser tab, then types the prompt, pastes the media and presses send.
    static func start(_ request: PromptDispatchRequest, browser: EzMeBrowserTabs) {
        let linked = browser.splitIsLinked
        browser.newTab(request.target.url)
        let tabID = linked ? browser.secondaryID : browser.selectedID
        browser.browserMessage = "Opening \(request.target.name)…"
        Task { await run(request, tabID: tabID, browser: browser) }
    }

    private static func literal(_ items: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: items), let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    private static func literal(_ item: String) -> String {
        let wrapped = literal([item])
        return String(wrapped.dropFirst().dropLast())
    }

    private static let findScript = """
    function kdFind(sels){for(var i=0;i<sels.length;i++){var c=document.querySelectorAll(sels[i]);for(var j=0;j<c.length;j++){var r=c[j].getBoundingClientRect();if(r.width>0&&r.height>0){return c[j];}}}return null;}
    """

    /// Reads the page: visible prompt boxes, file upload inputs and buttons that look like "Generate" or "Send".
    private static let analyzeScript = """
    (function(){
      function vis(e){var r=e.getBoundingClientRect();var s=getComputedStyle(e);return r.width>20&&r.height>10&&s.visibility!=='hidden'&&s.display!=='none';}
      function label(e){return (e.getAttribute('aria-label')||e.getAttribute('placeholder')||e.getAttribute('data-placeholder')||e.title||'').trim().slice(0,90);}
      var eds=[].slice.call(document.querySelectorAll('textarea,[contenteditable="true"],[role="textbox"],input[type="text"],input:not([type])')).filter(vis).map(function(e){var r=e.getBoundingClientRect();return {label:label(e),area:r.width*r.height};}).sort(function(a,b){return b.area-a.area;});
      var files=[].slice.call(document.querySelectorAll('input[type=file]')).map(function(i){return (i.getAttribute('accept')||'').toLowerCase();});
      var btns=[].slice.call(document.querySelectorAll('button,[role=button],a[class*=btn],div[class*=btn],div[class*=button]')).filter(vis).map(function(b){var r=b.getBoundingClientRect();return {text:(b.innerText||b.getAttribute('aria-label')||'').replace(/\\s+/g,' ').trim().slice(0,40),area:r.width*r.height};}).filter(function(b){return b.text.length>0&&b.text.length<=30&&/^(generate|create|send|submit|run|start|make|animate|render|go|imagine|produce)\\b/i.test(b.text);}).sort(function(a,b){return b.area-a.area;});
      return JSON.stringify({editors:eds.slice(0,4),files:files,buttons:btns.slice(0,4),title:document.title});
    })()
    """

    private struct AnalysisEditor: Decodable { var label: String }
    private struct AnalysisButton: Decodable { var text: String }
    private struct Analysis: Decodable { var editors: [AnalysisEditor]; var files: [String]; var buttons: [AnalysisButton]; var title: String }

    private static func learn(_ request: PromptDispatchRequest, tabID: String, browser: EzMeBrowserTabs) async {
        let name = request.target.name
        browser.browserMessage = "Reading \(name)… Sign in there if it asks."
        var steady = 0
        for _ in 0..<110 {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let web = browser.webViews[tabID], !web.isLoading else { continue }
            guard let json = try? await web.evaluateJavaScript(analyzeScript) as? String, let data = json.data(using: .utf8),
                  let found = try? JSONDecoder().decode(Analysis.self, from: data) else { continue }
            guard !found.editors.isEmpty || !found.files.isEmpty else { steady = 0; continue }
            steady += 1
            guard steady >= 2 else { continue } // the page has stopped changing
            let accept = found.files.joined(separator: " ")
            let kind = accept.contains("video") ? "video" : (accept.contains("image") || !found.files.isEmpty ? "image" : "chat")
            let hint = found.editors.first?.label ?? ""
            let button = found.buttons.first?.text ?? ""
            var parts: [String] = []
            parts.append(found.editors.isEmpty ? "no prompt box" : "prompt box" + (hint.isEmpty ? "" : " \u{201C}\(hint)\u{201D}"))
            parts.append(found.files.isEmpty ? "no upload slots" : "\(found.files.count) upload slot" + (found.files.count == 1 ? "" : "s"))
            parts.append(button.isEmpty ? "no start button found yet" : "button \u{201C}\(button)\u{201D}")
            let learned = LearnedPage(summary: parts.joined(separator: " · "), promptHint: hint, uploadSlots: found.files.count, kind: kind, generateLabel: button)
            PromptTargets.setLearned(learned, for: name)
            NotificationCenter.default.post(name: .keydoPromptTargetsChanged, object: nil)
            browser.browserMessage = "Read \(name): \(learned.summary)."
            return
        }
        browser.browserMessage = "Could not read \(name) yet. Sign in to it in the side panel, then choose \u{201C}Read the page again\u{201D}."
    }

    /// Puts files into the page like a person would: into its file inputs, else as a paste, else as a drop.
    /// Returns where they went ("input", "paste", "drop") or "none".
    private static func attach(_ files: [String], to web: WKWebView, editors: String) async -> String {
        _ = try? await web.evaluateJavaScript("window.__kdF={};window.__kdM={};'ok'")
        var index = 0
        for path in files {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count <= 120_000_000 else { continue }
            let ext = URL(fileURLWithPath: path).pathExtension
            let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
            _ = try? await web.evaluateJavaScript("window.__kdM[\(index)]={name:\(literal(URL(fileURLWithPath: path).lastPathComponent)),type:\(literal(mime))};window.__kdF[\(index)]='';'ok'")
            let chunk = 1_500_000 // a multiple of 3, so every piece is valid base64 on its own
            var offset = 0
            while offset < data.count {
                let piece = data.subdata(in: offset..<min(offset + chunk, data.count)).base64EncodedString()
                _ = try? await web.evaluateJavaScript("window.__kdF[\(index)]+='\(piece)';'ok'")
                offset += chunk
            }
            index += 1
        }
        guard index > 0 else { return "none" }
        let script = """
        (function(){\(findScript)
        var metas=window.__kdM||{},data=window.__kdF||{},files=[];
        Object.keys(metas).sort(function(a,b){return a-b;}).forEach(function(k){var bin=atob(data[k]||'');var arr=new Uint8Array(bin.length);for(var i=0;i<bin.length;i++)arr[i]=bin.charCodeAt(i);files.push(new File([arr],metas[k].name,{type:metas[k].type}));});
        window.__kdF={};window.__kdM={};
        if(!files.length)return 'none';
        function accepts(inp,f){var a=(inp.getAttribute('accept')||'').toLowerCase().trim();if(!a)return true;var ext='.'+f.name.split('.').pop().toLowerCase(),t=(f.type||'').toLowerCase();return a.split(',').some(function(p){p=p.trim();if(p===ext||p===t)return true;if(p.slice(-2)==='/*')return t.indexOf(p.slice(0,-1))===0;return false;});}
        function put(inp,list){var dt=new DataTransfer();list.forEach(function(f){dt.items.add(f);});inp.files=dt.files;inp.dispatchEvent(new Event('input',{bubbles:true}));inp.dispatchEvent(new Event('change',{bubbles:true}));}
        var remaining=files.slice(),placed=0;
        [].slice.call(document.querySelectorAll('input[type=file]')).filter(function(i){return !i.disabled;}).forEach(function(inp){
          var ok=remaining.filter(function(f){return accepts(inp,f);});if(!ok.length)return;
          if(inp.multiple){put(inp,ok);remaining=remaining.filter(function(f){return ok.indexOf(f)<0;});placed+=ok.length;}
          else{put(inp,[ok[0]]);remaining=remaining.filter(function(f){return f!==ok[0];});placed+=1;}
        });
        if(placed>0)return 'input';
        var el=kdFind(\(editors))||document.activeElement||document.body;el.focus();
        var dt=new DataTransfer();files.forEach(function(f){dt.items.add(f);});
        var ev;try{ev=new ClipboardEvent('paste',{bubbles:true,cancelable:true,clipboardData:dt});}catch(e){ev=new Event('paste',{bubbles:true,cancelable:true});try{Object.defineProperty(ev,'clipboardData',{value:dt});}catch(e2){}}
        if(!el.dispatchEvent(ev))return 'paste';
        var target=el.closest('[class*=drop],[class*=upload]')||el,handled=false;
        ['dragenter','dragover','drop'].forEach(function(type){var d;try{d=new DragEvent(type,{bubbles:true,cancelable:true,dataTransfer:dt});}catch(e){d=new Event(type,{bubbles:true,cancelable:true});try{Object.defineProperty(d,'dataTransfer',{value:dt});}catch(e2){}}
          if(!target.dispatchEvent(d)&&type==='drop')handled=true;});
        return handled?'drop':'none';})()
        """
        let result = try? await web.evaluateJavaScript(script)
        return (result as? String) ?? "none"
    }

    private static func run(_ request: PromptDispatchRequest, tabID: String, browser: EzMeBrowserTabs) async {
        if request.learnOnly { await learn(request, tabID: tabID, browser: browser); return }
        let name = request.target.name
        let editors = literal(request.target.editor)
        let senders = literal(request.target.send)

        // 1. Wait for the page and its prompt box (or, for pages that only take pictures, its upload input).
        var web: WKWebView?
        for _ in 0..<90 {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let candidate = browser.webViews[tabID], !candidate.isLoading else { continue }
            let found = try? await candidate.evaluateJavaScript("(function(){\(findScript) return (kdFind(\(editors))||document.querySelector('input[type=file]'))?'yes':'no';})()")
            if (found as? String) == "yes" { web = candidate; break }
        }
        guard let web else {
            browser.browserMessage = "Could not find the \(name) prompt box. Sign in to \(name) in the side panel, then press the button again."
            return
        }

        // 2. Type the prompt.
        if !request.prompt.isEmpty {
            let script = """
            (function(){\(findScript)
            var el=kdFind(\(editors)); if(!el) return 'none'; el.focus();
            var text=\(literal(request.prompt));
            if(el.tagName==='TEXTAREA'||el.tagName==='INPUT'){
              var proto=el.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;
              Object.getOwnPropertyDescriptor(proto,'value').set.call(el,text);
              el.dispatchEvent(new Event('input',{bubbles:true}));
            } else {
              document.execCommand('selectAll',false,null);
              document.execCommand('insertText',false,text);
            }
            return 'ok';})()
            """
            _ = try? await web.evaluateJavaScript(script)
        } else {
            _ = try? await web.evaluateJavaScript("(function(){\(findScript) var el=kdFind(\(editors)); if(el){el.focus();} return 'ok';})()")
        }

        // 3. Attach the media: into the page's own upload inputs when it has them, else as a paste or a drop.
        let files = request.files.filter { FileManager.default.fileExists(atPath: $0) }
        if !files.isEmpty {
            try? await Task.sleep(nanoseconds: 400_000_000)
            var placed = await attach(files, to: web, editors: editors)
            if placed == "none" {
                // Last resort: a real paste from the clipboard, with the prompt box focused.
                _ = try? await web.evaluateJavaScript("(function(){\(findScript) var el=kdFind(\(editors)); if(el){el.focus();} return 'ok';})()")
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                if files.count == 1, let image = NSImage(contentsOfFile: files[0]), ["png", "jpg", "jpeg", "heic", "tiff", "bmp"].contains(URL(fileURLWithPath: files[0]).pathExtension.lowercased()) {
                    pasteboard.writeObjects([image])
                } else {
                    pasteboard.writeObjects(files.map { URL(fileURLWithPath: $0) as NSURL })
                }
                NSApp.activate(ignoringOtherApps: true)
                web.window?.makeKeyAndOrderFront(nil)
                web.window?.makeFirstResponder(web)
                _ = web.tryToPerform(#selector(NSText.paste(_:)), with: nil)
                placed = "clipboard"
            }
            browser.browserMessage = "Attached \(files.count) file\(files.count == 1 ? "" : "s") to \(name) (\(placed))…"
            let bytes = files.reduce(0.0) { total, path in
                total + Double((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.doubleValue ?? 0)
            }
            let wait = min(3.0 + bytes / 1_000_000 * 0.6, 25.0)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        } else {
            try? await Task.sleep(nanoseconds: 700_000_000)
        }

        // 4. Press send as soon as the site allows it.
        let click = """
        (function(){\(findScript)
        var sels=\(senders);
        for(var i=0;i<sels.length;i++){var c=document.querySelectorAll(sels[i]);for(var j=0;j<c.length;j++){var b=c[j];var r=b.getBoundingClientRect();
          if(r.width>0&&r.height>0&&!b.disabled&&b.getAttribute('aria-disabled')!=='true'){b.click();return 'clicked';}}}
        var want=\(literal(request.target.learned?.generateLabel ?? "")).toLowerCase();
        var all=document.querySelectorAll('button,[role=button],a[class*=btn],div[class*=btn],div[class*=button]');
        for(var k=0;k<all.length;k++){var b=all[k];var r=b.getBoundingClientRect();if(!(r.width>0&&r.height>0))continue;
          var t=(b.innerText||b.getAttribute('aria-label')||'').replace(/\\s+/g,' ').trim().toLowerCase();if(!t||t.length>30)continue;
          var hit=want?(t===want||t.indexOf(want)===0):/^(generate|create|send|submit|run|start|animate|make|imagine)\\b/.test(t);
          var off=b.disabled||b.getAttribute('aria-disabled')==='true'||/disabled/.test(b.className||'');
          if(hit&&!off){b.click();return 'clicked';}}
        return 'wait';})()
        """
        for _ in 0..<40 {
            let result = try? await web.evaluateJavaScript(click)
            if (result as? String) == "clicked" {
                browser.browserMessage = "Sent to \(name)."
                return
            }
            try? await Task.sleep(nanoseconds: 750_000_000)
        }
        let enter = "(function(){\(findScript) var el=kdFind(\(editors)); if(!el) return 'none'; el.focus(); ['keydown','keypress','keyup'].forEach(function(t){el.dispatchEvent(new KeyboardEvent(t,{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));}); return 'enter';})()"
        _ = try? await web.evaluateJavaScript(enter)
        browser.browserMessage = "The prompt is in \(name). Press send there if it did not start."
    }
}
