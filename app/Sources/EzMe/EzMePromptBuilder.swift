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
import WebKit

extension Notification.Name {
    static let keydoSendPrompt = Notification.Name("KeyDoSendPrompt")
}

// MARK: - Sites the prompt can be sent to

struct PromptTarget: Codable, Identifiable, Equatable {
    var name: String
    var url: String
    var editor: [String]
    var send: [String]
    var builtIn: Bool = false
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

    static func load() -> [PromptTarget] { defaults + custom() }

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

    static func compose(_ raw: String, clips: [Clip], records: [CollectionRecord], vocabulary: Set<String>, autocorrect: Bool) -> PromptComposition {
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

            if let replacement = resolve(core, clips: clips, records: records, attachments: &attachments) {
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
    private static func resolve(_ core: String, clips: [Clip], records: [CollectionRecord], attachments: inout [PromptAttachment]) -> String? {
        guard core.count >= 2, let marker = core.first, "/\\@#".contains(marker) else { return nil }
        let name = String(core.dropFirst()).lowercased()
        guard !name.isEmpty else { return nil }

        if marker == "@", let person = recordText(name, records: records, attachments: &attachments) { return person }
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

struct PromptBuilderView: View {
    let clips: [Clip]
    let records: [CollectionRecord]

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
    @State private var voiceHint = ""
    @State private var showVoiceHelp = false
    @State private var showAddSite = false
    @State private var newSiteName = ""
    @State private var newSiteURL = ""

    private var finalPrompt: String { aiText ?? composition.text }
    private var canSend: Bool { !finalPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !composition.attachments.isEmpty }

    private var collectionNames: [String] {
        Array(Set(records.filter { !$0.alias.isEmpty }.map { $0.collection })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var suggestions: [PromptSuggestion] {
        guard let token = PromptSuggestions.lastToken(in: text) else { return [] }
        return PromptSuggestions.suggestions(for: token, clips: clips, records: records)
    }
    private var appClips: [Clip] { clips.filter { $0.appBundleIdentifier != nil || $0.webURL != nil } }
    private var mediaClips: [Clip] { clips.filter { !PromptComposer.existingFiles($0).isEmpty } }
    private var textClips: [Clip] { clips.filter { PromptComposer.existingFiles($0).isEmpty && !$0.text.isEmpty && $0.appBundleIdentifier == nil && $0.webURL == nil } }

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
        .onAppear { recompute() }
        .task(id: clips.count + records.count) {
            vocabulary = PromptComposer.vocabulary(clips: clips, records: records)
            recompute()
        }
        .onChange(of: text) { _ in recompute() }
        .onChange(of: autoCorrect) { _ in recompute() }
        .sheet(isPresented: $showAddSite) { addSiteSheet }
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
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
            HStack(spacing: 8) {
                VoiceDictationButton(onTranscript: { spoken in applyVoice(spoken) }, onPartial: { spoken in applyVoice(spoken) }, onStart: { voiceBase = text; voiceSent = 0; voiceHint = "Listening… say “enter chatgpt” to send" })
                Menu("# Collections") { collectionsMenu }
                Menu("# Media") { shortcutsMenu(mediaClips) }
                Menu("# Text") { shortcutsMenu(textClips) }
                Menu("@ Apps") { shortcutsMenu(appClips, marker: "@") }
                Menu("= Functions") { functionsMenu }
                Spacer()
                Button("Clear") { text = ""; notice = "" }.disabled(text.isEmpty)
            }
            .menuStyle(.borderlessButton)
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

    private func accept(_ item: PromptSuggestion) {
        guard let token = PromptSuggestions.lastToken(in: text), text.hasSuffix(token) else { return }
        text = String(text.dropLast(token.count)) + item.insert + " "
    }

    private func applyVoice(_ spoken: String) {
        let result = PromptVoice.apply(base: voiceBase, spoken: spoken, targets: targets)
        text = result.text
        if !result.notice.isEmpty { voiceHint = result.notice }
        if result.sends.count > voiceSent, let target = result.sends.last {
            voiceSent = result.sends.count
            voiceHint = "Sending to \(target.name)…"
            DispatchQueue.main.async {
                recompute()
                send(to: target)
            }
        }
    }

    @ViewBuilder private var collectionsMenu: some View {
        if collectionNames.isEmpty {
            Text("No collection records yet")
        } else {
            ForEach(collectionNames, id: \.self) { name in
                Menu(name) {
                    ForEach(records.filter { $0.collection == name && !$0.alias.isEmpty }.prefix(80)) { record in
                        Button(record.name.isEmpty ? record.alias : "\(record.name) · \(record.alias)") { insert("#" + record.alias) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func shortcutsMenu(_ items: [Clip], marker: String = "#") -> some View {
        if items.isEmpty {
            Text("Nothing here yet")
        } else {
            ForEach(items.prefix(120)) { clip in
                Button("\(clip.name.isEmpty ? clip.key : clip.name) · \(clip.key)") {
                    insert(marker + clip.key.trimmingCharacters(in: CharacterSet(charactersIn: "/\\")))
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
        composition = PromptComposer.compose(text, clips: clips, records: records, vocabulary: vocabulary, autocorrect: autoCorrect)
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
        aiBusy = true
        notice = ""
        Task { @MainActor in
            do {
                let instruction = "Rewrite the text below as one clear, well-structured prompt for an AI assistant. Keep every name, number, date and bracketed attachment label such as [Image: Name] exactly as written. Do not add facts or ask questions. Return only the prompt.\n\n" + source
                let result = try await SharedAIClient.generate(profile: profile, key: key, prompt: instruction, maxTokens: 2000)
                let clean = result.trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.isEmpty { notice = "The AI returned nothing. Your own words are kept." } else { aiText = clean }
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
                    Button { send(to: target) } label: {
                        Label(target.name, systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(!canSend)
                    .contextMenu {
                        if !target.builtIn {
                            Button("Remove \(target.name)") { PromptTargets.removeCustom(target.name); targets = PromptTargets.load() }
                        }
                    }
                }
                Button { showAddSite = true } label: { Label("Add site", systemImage: "plus").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
            Text("Attached media is pasted into the site, so the site's own sign-in is used. The clipboard is used for that step.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func send(to target: PromptTarget) {
        let files = composition.attachments.flatMap { $0.paths }
        NotificationCenter.default.post(name: .keydoSendPrompt, object: PromptDispatchRequest(target: target, prompt: finalPrompt, files: files))
        notice = "Opening \(target.name) in the side panel…"
    }

    private var addSiteSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add an AI site").font(.title3.weight(.bold))
            TextField("Name, for example Mistral", text: $newSiteName)
            TextField("Address, for example chat.mistral.ai", text: $newSiteURL)
            Text("KeyDo looks for the site's prompt box and send button on its own. Sign in to the site in the side panel once.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { showAddSite = false }
                Button("Add") {
                    PromptTargets.addCustom(name: newSiteName, url: newSiteURL)
                    targets = PromptTargets.load()
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

    init(target: PromptTarget, prompt: String, files: [String]) {
        self.target = target
        self.prompt = prompt
        self.files = files
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

    private static func run(_ request: PromptDispatchRequest, tabID: String, browser: EzMeBrowserTabs) async {
        let name = request.target.name
        let editors = literal(request.target.editor)
        let senders = literal(request.target.send)

        // 1. Wait for the page and its prompt box.
        var web: WKWebView?
        for _ in 0..<90 {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let candidate = browser.webViews[tabID], !candidate.isLoading else { continue }
            let found = try? await candidate.evaluateJavaScript("(function(){\(findScript) return kdFind(\(editors))?'yes':'no';})()")
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

        // 3. Paste the media, like pasting files into the site by hand.
        let files = request.files.filter { FileManager.default.fileExists(atPath: $0) }
        if !files.isEmpty {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if files.count == 1, let image = NSImage(contentsOfFile: files[0]), ["png", "jpg", "jpeg", "heic", "tiff", "bmp"].contains(URL(fileURLWithPath: files[0]).pathExtension.lowercased()) {
                pasteboard.writeObjects([image])
            } else {
                pasteboard.writeObjects(files.map { URL(fileURLWithPath: $0) as NSURL })
            }
            web.window?.makeFirstResponder(web)
            _ = NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
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
