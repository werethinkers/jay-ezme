// WishStudio: its own menu in EzMe, separate from AppBuilder.
//   Cover page  - the apps (Happy Birthday, Happy Anniversary, Happy Diwali, Infographics and your own).
//   App tabs    - like AppBuilder: a tab per app with its cover picture, GIF or video.
//   Studio      - an app opens as a web page you can change live: details, theme, media, templates.
//   WishBuilder - create an app from a prompt, or edit the five steps of an app (EzMeWishBuilder.swift).
//   Bottom bar  - the only microphone, with hints for what to say or type.
import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

enum WishTheme {
    static let accent = Color(wishHex: "#6D4AB0")
    static let accentSoft = Color(wishHex: "#F1EAFB")
    static let page = Color(wishHex: "#FBFAFE")
    static let line = Color(wishHex: "#E5DEF2")
    static let ink = Color(wishHex: "#2B1E45")
    static let muted = Color(wishHex: "#7A6F8F")
    static let swatches = ["#EC6AA8", "#D63B3B", "#F28A2E", "#F2C230", "#3FA66A", "#3B6FD6", "#7B52B8", "#1A1A1A", "#FFFFFF", "#8B5A2B"]
}

struct WishPalette: Identifiable {
    let id: String
    let name: String
    let bg: String
    let accent: String
    let ink: String
}

enum WishPalettes {
    static let all: [WishPalette] = [
        WishPalette(id: "lavender", name: "Lavender", bg: "#EFE6FA", accent: "#7B52B8", ink: "#2B1E45"),
        WishPalette(id: "blush", name: "Blush", bg: "#FBE3E6", accent: "#D9577A", ink: "#4A1F2C"),
        WishPalette(id: "mint", name: "Mint", bg: "#E0F3E8", accent: "#2E9467", ink: "#173D2B"),
        WishPalette(id: "sky", name: "Sky", bg: "#E3EEFB", accent: "#3B6FD6", ink: "#1B2C52"),
        WishPalette(id: "gold", name: "Golden", bg: "#FBF0D5", accent: "#B98A12", ink: "#463408"),
        WishPalette(id: "peach", name: "Peach", bg: "#FFE7DA", accent: "#E2703A", ink: "#4F2410"),
        WishPalette(id: "rose", name: "Rose", bg: "#F8DDE8", accent: "#B83A72", ink: "#47182F"),
        WishPalette(id: "sage", name: "Sage", bg: "#E6EDDD", accent: "#6B8F4E", ink: "#26361A"),
        WishPalette(id: "midnight", name: "Midnight", bg: "#1F1B3A", accent: "#F2C45A", ink: "#F6F1FF"),
        WishPalette(id: "saffron", name: "Saffron", bg: "#FFEDCC", accent: "#E67E00", ink: "#4A2A00"),
        WishPalette(id: "ivory", name: "Ivory", bg: "#F7F2E8", accent: "#2D2A26", ink: "#1F1D1A"),
        WishPalette(id: "ocean", name: "Ocean", bg: "#0F2A43", accent: "#4FC3F7", ink: "#EAF6FF"),
    ]
}

func wishHex(from color: Color) -> String {
    let converted = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
    return wishHexString(Double(converted.redComponent), Double(converted.greenComponent), Double(converted.blueComponent))
}

struct WishChipGroup: Identifiable {
    var id: String
    var title: String
    var fieldKey: String
    var chips: [WishChip]
}

enum WishPage: Equatable {
    case home
    case app(String)
    case builder
}

enum WishInspectorTab: String, CaseIterable {
    case details = "Details"
    case theme = "Theme"
    case media = "Media"
    case templates = "Templates"
}

// MARK: - Model

@MainActor
final class WishStudioModel: ObservableObject {
    let store = WishStore()
    let voice = WishVoiceController()
    let web = WishWebController()
    let builder = WishBuilderState()

    @Published var page: WishPage = .home
    @Published var appID: String = ""
    @Published var card = WishCard(appID: "", designID: "g-lavender") {
        didSet { persistCard() }
    }
    @Published var selected: String? = nil
    @Published var status: String = ""
    @Published var commandText: String = ""
    @Published private(set) var undoStack: [WishCard] = []
    @Published private(set) var redoStack: [WishCard] = []
    @Published var chipGroups: [WishChipGroup] = []
    @Published var inspector: WishInspectorTab = .details
    @Published var voiceChoice: String = "auto"
    @Published var collections: [String] = []

    var focusKey = ""
    var hovering = false
    var records: [CollectionRecord] = []
    var clips: [Clip] = []

    private var selectionTask: Task<Void, Never>?
    private var started = false
    private var typingKey = ""
    private var typingTime = Date.distantPast
    private var colorStamp = Date.distantPast

    // MARK: Current app

    var app: WishApp {
        return store.app(id: appID) ?? store.apps.first ?? WishApp(name: "WishStudio")
    }

    var designs: [WishDesign] { return WishDesigns.designs(for: app.kind) }
    var design: WishDesign { return WishDesigns.design(id: card.designID, kind: app.kind) }
    var context: WishContext { return store.context(for: card, app: app) }

    var stateJSON: String {
        let files = store
        return WishHTML.stateJSON(app: app, card: card, design: design, context: context, selected: selected) { file in
            return files.mediaURL(file)?.absoluteString ?? ""
        }
    }

    var environment: WishCommandEnvironment {
        return WishCommandEnvironment(app: app, apps: store.apps, designs: designs, chips: chipGroups.flatMap { $0.chips })
    }

    var isOnApp: Bool {
        if case .app = page { return true }
        return false
    }

    func start(directory: URL) {
        guard !started else { return }
        started = true
        store.load(directory: directory)
        builder.model = self
        let remembered = store.app(id: store.lastAppID) != nil ? store.lastAppID : (store.apps.first?.id ?? "")
        loadApp(remembered, saveCurrent: false)
        status = defaultStatus
    }

    var defaultStatus: String {
        switch page {
        case .home: return "Pick an app, or say its name."
        case .builder: return "Describe the app you want, or say it with the mic."
        case .app: return "Tap the mic and say one thing to change, like \u{201C}make it pink\u{201D}."
        }
    }

    func goHome() {
        voiceGuard()
        page = .home
        selected = nil
        status = defaultStatus
    }

    func openBuilder() {
        voiceGuard()
        page = .builder
        selected = nil
        status = defaultStatus
    }

    func openApp(_ id: String) {
        guard store.app(id: id) != nil else { return }
        loadApp(id, saveCurrent: true)
        page = .app(id)
        status = defaultStatus
    }

    private func voiceGuard() {
        if voice.isListening { syncVoice() }
    }

    func loadApp(_ id: String, saveCurrent: Bool) {
        if saveCurrent && !appID.isEmpty { store.cards[appID] = card }
        guard let target = store.app(id: id) else { return }
        appID = id
        store.lastAppID = id
        let options = WishDesigns.designs(for: target.kind)
        let startDesign = options.contains(where: { $0.id == target.designID }) ? (target.designID ?? options[0].id) : options[0].id
        var next = store.cards[id] ?? WishCard.make(for: target, designID: startDesign)
        if !options.contains(where: { $0.id == next.designID }) { next.designID = startDesign }
        for field in target.fields where next.values[field.key] == nil {
            next.values[field.key] = field.value
            next.valuesHi[field.key] = field.valueHi.isEmpty ? field.value : field.valueHi
        }
        card = next
        selected = nil
        undoStack = []
        redoStack = []
        refreshChips()
        if voice.isListening { syncVoice() }
    }

    /// Called after WishBuilder changes the open app, so the card picks up new fields.
    func appDefinitionChanged() {
        guard let target = store.app(id: appID) else { return }
        var next = card
        for field in target.fields where next.values[field.key] == nil {
            next.values[field.key] = field.value
            next.valuesHi[field.key] = field.valueHi.isEmpty ? field.value : field.valueHi
        }
        let options = WishDesigns.designs(for: target.kind)
        if !options.contains(where: { $0.id == next.designID }) { next.designID = options[0].id }
        if next != card { card = next }
        refreshChips()
    }

    private func persistCard() {
        guard !appID.isEmpty else { return }
        store.cards[appID] = card
    }

    // MARK: Undo

    private func pushUndo() {
        undoStack.append(card)
        if undoStack.count > 80 { undoStack.removeFirst() }
        redoStack = []
    }

    func undo() {
        guard let previous = undoStack.popLast() else {
            status = "Nothing to undo."
            return
        }
        redoStack.append(card)
        card = previous
        status = "Undone."
    }

    func redo() {
        guard let next = redoStack.popLast() else {
            status = "Nothing to redo."
            return
        }
        undoStack.append(card)
        card = next
        status = "Redone."
    }

    // MARK: Editing from the panels

    func edit(_ key: String, to value: String) {
        guard let field = app.field(key) else { return }
        let now = Date()
        if typingKey != key || now.timeIntervalSince(typingTime) > 1.5 { pushUndo() }
        typingKey = key
        typingTime = now
        card.set(key, to: value, universal: field.universal)
    }

    /// Used when a function chip is dropped on a box (or tapped): the whole box becomes the function, or it is
    /// added inside the text, like "Happy birthday {=Date}".
    func insertFormula(_ formula: String, into key: String) {
        let clean = formula.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, app.field(key) != nil else { return }
        let current = card.value(for: key)
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let inner = clean.hasPrefix("=") ? clean : "=" + clean
        let next: String
        if trimmed.isEmpty || WishFormula.isFormula(trimmed) {
            next = inner
        } else {
            next = current + " {" + inner + "}"
        }
        typingTime = .distantPast
        edit(key, to: next)
        status = "\(inner) added to \(app.field(key)?.label ?? key)."
    }

    func chooseDesign(_ id: String) {
        guard id != card.designID else { return }
        pushUndo()
        card.designID = id
        card.backgroundHex = nil
        card.accentHex = nil
        card.inkHex = nil
    }

    func applyPalette(_ palette: WishPalette) {
        pushUndo()
        card.backgroundHex = palette.bg
        card.accentHex = palette.accent
        card.inkHex = palette.ink
        status = "Theme \u{2192} \(palette.name)"
    }

    func resetColors() {
        pushUndo()
        card.backgroundHex = nil
        card.accentHex = nil
        card.inkHex = nil
        status = "Colours reset to the design."
    }

    private func coalescedColorUndo() {
        let now = Date()
        if now.timeIntervalSince(colorStamp) > 1.2 { pushUndo() }
        colorStamp = now
    }

    func setBackground(_ hex: String) {
        coalescedColorUndo()
        card.backgroundHex = hex
        if card.inkHex == nil { card.inkHex = wishIsDark(hex) ? "#F6F1FF" : design.ink }
    }

    func setAccent(_ hex: String) {
        coalescedColorUndo()
        card.accentHex = hex
    }

    func setInk(_ hex: String) {
        coalescedColorUndo()
        card.inkHex = hex
    }

    func setLanguage(_ language: WishLanguage) {
        guard language != card.language else { return }
        pushUndo()
        card.language = language
        if voice.isListening { syncVoice() }
    }

    func setArtwork(_ symbol: String) {
        pushUndo()
        card.artwork = symbol
    }

    func setFontStyle(_ style: WishFontStyle) {
        pushUndo()
        card.fontStyle = style
    }

    func beginSlider() {
        pushUndo()
    }

    func useChip(_ chip: WishChip) {
        guard let field = app.field(chip.fieldKey) else { return }
        pushUndo()
        card.set(chip.fieldKey, to: chip.value, universal: field.universal)
        status = "\(field.label) \u{2192} \(chip.value)"
    }

    func resetCard() {
        pushUndo()
        card = WishCard.make(for: app, designID: app.designID.flatMap { id in designs.contains(where: { $0.id == id }) ? id : nil } ?? designs[0].id)
        selected = nil
        status = "Card reset."
    }

    // MARK: Media

    func chooseMedia(placement: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image, UTType.movie]
        panel.allowsMultipleSelection = false
        panel.message = placement == "hero" ? "Choose a picture, GIF or video for the middle of the card" : "Choose a picture, GIF or video for the background"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let imported = store.importMedia(from: url) else {
            status = "That file type is not supported. Use PNG, JPG, GIF, MP4 or MOV."
            return
        }
        pushUndo()
        var list = (card.media ?? []).filter { $0.placement != placement }
        list.append(WishMedia(file: imported.file, kind: imported.kind, placement: placement))
        card.media = list
        status = "\(imported.kind.capitalized) added."
    }

    func removeMedia(placement: String) {
        pushUndo()
        let list = (card.media ?? []).filter { $0.placement != placement }
        card.media = list.isEmpty ? nil : list
    }

    func media(_ placement: String) -> WishMedia? {
        return card.media?.first { $0.placement == placement }
    }

    func chooseCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image, UTType.movie]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the cover picture, GIF or video for this app"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let imported = store.importMedia(from: url) else {
            status = "That file type is not supported."
            return
        }
        var updated = app
        updated.coverFile = imported.file
        updated.coverFraming = nil
        store.updateApp(updated)
        status = "Cover updated. Use Crop and position to choose what shows."
    }

    func setCoverFraming(_ framing: WishFraming) {
        var updated = app
        updated.coverFraming = framing
        store.updateApp(updated)
    }

    func setMediaFraming(placement: String, _ framing: WishFraming) {
        var list = card.media ?? []
        guard let index = list.firstIndex(where: { $0.placement == placement }) else { return }
        list[index].framing = framing
        card.media = list
    }

    func removeCover() {
        var updated = app
        updated.coverFile = nil
        updated.coverFraming = nil
        store.updateApp(updated)
    }

    // MARK: Templates

    var templatesForApp: [WishTemplate] {
        return store.templates.filter { $0.appID == appID }
    }

    func saveTemplate(name: String, includeText: Bool) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var template = WishTemplate(name: clean, appID: appID, designID: card.designID)
        template.backgroundHex = card.backgroundHex
        template.accentHex = card.accentHex
        template.inkHex = card.inkHex
        template.fontStyle = card.fontStyle
        template.textScale = card.textScale
        template.magic = card.magic
        template.artwork = card.artwork
        if includeText {
            template.values = card.values
            template.valuesHi = card.valuesHi
        }
        store.templates.append(template)
        status = "Saved the template \u{201C}\(clean)\u{201D}."
    }

    func applyTemplate(_ template: WishTemplate) {
        pushUndo()
        if designs.contains(where: { $0.id == template.designID }) { card.designID = template.designID }
        card.backgroundHex = template.backgroundHex
        card.accentHex = template.accentHex
        card.inkHex = template.inkHex
        card.fontStyle = template.fontStyle
        card.textScale = template.textScale
        card.magic = template.magic
        card.artwork = template.artwork
        if let values = template.values { card.values = values }
        if let valuesHi = template.valuesHi { card.valuesHi = valuesHi }
        status = "Template \u{201C}\(template.name)\u{201D} applied."
    }

    func deleteTemplate(_ template: WishTemplate) {
        store.templates.removeAll { $0.id == template.id }
    }

    // MARK: Selection

    func select(_ key: String?) {
        selectionTask?.cancel()
        selected = key
        if key != nil { scheduleSelectionClear() }
    }

    private func scheduleSelectionClear() {
        selectionTask?.cancel()
        let seconds = max(1, app.live.selectionSeconds)
        selectionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self = self else { return }
            if self.hovering {
                self.scheduleSelectionClear()
            } else {
                self.selected = nil
            }
        }
    }

    // MARK: Voice and typed commands (one path for everything)

    var recognitionLocale: String {
        switch voiceChoice {
        case "english": return "en-IN"
        case "hindi": return "hi-IN"
        default:
            guard isOnApp else { return "en-IN" }
            switch app.live.recognition {
            case "english": return "en-IN"
            case "hindi": return "hi-IN"
            default: return card.language.speechIdentifier
            }
        }
    }

    func setVoiceChoice(_ choice: String) {
        voiceChoice = choice
        if voice.isListening { syncVoice() }
    }

    func toggleVoice() {
        if voice.isListening {
            voice.stop()
            status = "Mic off."
            return
        }
        status = "Listening. Say one command at a time."
        voice.start(localeIdentifier: recognitionLocale, commitDelay: isOnApp ? app.live.commitDelay : 0.9) { [weak self] text in
            self?.handleTranscript(text)
        }
    }

    func syncVoice() {
        voice.changeLanguage(recognitionLocale)
        voice.updatePause(isOnApp ? app.live.commitDelay : 0.9)
    }

    /// The one entry point for a command, spoken or typed, on every page.
    func handleTranscript(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        commandText = ""
        switch page {
        case .builder:
            builder.handle(text)
        case .home:
            handleHome(text)
        case .app:
            handleStudio(text)
        }
    }

    private func handleHome(_ text: String) {
        let lower = text.lowercased()
        if lower.contains("builder") || lower.contains("create") || lower.contains("new app") || lower.contains("\u{092C}\u{093F}\u{0932}\u{094D}\u{0921}\u{0930}") || lower.contains("\u{0928}\u{092F}\u{093E}") {
            openBuilder()
            return
        }
        let env = WishCommandEnvironment(app: app, apps: store.apps.filter { $0.id != "__none__" }, designs: designs, chips: [])
        for command in WishCommandParser.parse(text, env: env) {
            if case .switchApp(let id) = command.action {
                openApp(id)
                return
            }
        }
        for item in store.apps {
            let name = item.name.lowercased()
            let short = name.hasPrefix("happy ") ? String(name.dropFirst(6)) : name
            if lower.contains(short) || (!item.nameHi.isEmpty && text.contains(item.nameHi)) {
                openApp(item.id)
                return
            }
        }
        status = "Say the name of an app, like \u{201C}Happy Birthday\u{201D}, or \u{201C}WishBuilder\u{201D}."
    }

    private func handleStudio(_ text: String) {
        let env = environment
        let commands = WishCommandParser.parse(text, env: env)
        if commands.isEmpty {
            status = "I did not catch a command in \u{201C}\(text)\u{201D}. Try \u{201C}make it pink\u{201D}, \u{201C}bigger\u{201D} or \u{201C}name Yogesh\u{201D}."
            return
        }
        run(commands, env: env, heard: text)
    }

    private func run(_ commands: [WishCommand], env: WishCommandEnvironment, heard: String) {
        let enabled = Set(app.live.enabledGroups)
        var done: [String] = []
        var blocked = Set<String>()
        var baseline: WishCard? = card

        for command in commands {
            if let group = command.action.group, !enabled.contains(group) {
                blocked.insert(group)
                continue
            }
            switch command.action {
            case .undo:
                undo()
                baseline = card
                done.append("Undo")
            case .redo:
                redo()
                baseline = card
                done.append("Redo")
            case .switchApp(let id):
                openApp(id)
                baseline = nil
                done.append(WishCommandParser.summary(of: command, env: env))
            case .newCard, .reset:
                if let before = baseline, card != before {
                    undoStack.append(before)
                    redoStack = []
                }
                resetCard()
                baseline = card
                done.append(WishCommandParser.summary(of: command, env: env))
            case .export:
                exportPNG()
                done.append("Download PNG")
            case .copyImage:
                copyImage()
                done.append("Copy image")
            case .clearSelection:
                select(nil)
                done.append("Whole card")
            default:
                if mutate(command) { done.append(WishCommandParser.summary(of: command, env: env)) }
            }
        }

        if let before = baseline, card != before {
            undoStack.append(before)
            if undoStack.count > 80 { undoStack.removeFirst() }
            redoStack = []
        }
        if selected != nil { scheduleSelectionClear() }
        if commands.contains(where: { if case .language = $0.action { return true } else { return false } }), voice.isListening { syncVoice() }

        if !done.isEmpty {
            status = "Applied \u{00B7} " + done.joined(separator: " \u{00B7} ")
        } else if !blocked.isEmpty {
            status = "\u{201C}\(heard)\u{201D} needs the \(blocked.sorted().joined(separator: ", ")) control, which is switched off in WishBuilder \u{2192} Live Changes."
        }
    }

    private func edit(element: String?, _ change: (inout WishElementStyle) -> Void) {
        let keys: [String] = element.map { [$0] } ?? app.fields.map { $0.key }
        for key in keys {
            var style = card.styles[key] ?? WishElementStyle()
            change(&style)
            card.styles[key] = style
        }
    }

    /// Changes the card for one command. Returns false when nothing could be done.
    private func mutate(_ command: WishCommand) -> Bool {
        let element = command.target ?? selected
        switch command.action {
        case .setField(let key, let value), .useRecord(let key, let value):
            guard let field = app.field(key) else { return false }
            card.set(key, to: value, universal: field.universal)
            return true
        case .color(let target, let hex, _):
            return applyColor(target, hex: hex, element: element)
        case .scale(let factor):
            if let element = element {
                edit(element: element) { $0.scale = min(3, max(0.4, $0.scale * factor)) }
            } else {
                card.textScale = min(1.8, max(0.6, card.textScale * factor))
            }
            return true
        case .move(let dx, let dy):
            guard let element = element else {
                status = "Tap an element first, or name it, like \u{201C}move the title left\u{201D}."
                return false
            }
            edit(element: element) {
                $0.dx = min(260, max(-260, $0.dx + dx))
                $0.dy = min(300, max(-300, $0.dy + dy))
            }
            return true
        case .bold:
            edit(element: element) { $0.bold = true }
            return true
        case .italic:
            edit(element: element) { $0.italic = true }
            return true
        case .plain:
            edit(element: element) {
                $0.bold = false
                $0.italic = false
            }
            return true
        case .hide:
            guard let element = element else {
                status = "Say what to hide, like \u{201C}hide the date\u{201D}."
                return false
            }
            edit(element: element) { $0.hidden = true }
            return true
        case .show:
            edit(element: element) { $0.hidden = false }
            return true
        case .fontStyle(let style):
            card.fontStyle = style
            return true
        case .design(let id):
            card.designID = id
            card.backgroundHex = nil
            card.accentHex = nil
            card.inkHex = nil
            return true
        case .stepDesign(let step):
            let list = designs
            let current = list.firstIndex(where: { $0.id == card.designID }) ?? 0
            let next = ((current + step) % list.count + list.count) % list.count
            card.designID = list[next].id
            card.backgroundHex = nil
            card.accentHex = nil
            card.inkHex = nil
            return true
        case .language(let language):
            card.language = language
            return true
        case .magicDelta(let delta):
            card.magic = min(3, max(0, card.magic + delta))
            return true
        case .magicLevel(let level):
            card.magic = level
            return true
        default:
            return false
        }
    }

    private func applyColor(_ target: WishColorTarget, hex: String, element: String?) -> Bool {
        switch target {
        case .background:
            card.backgroundHex = hex
            card.inkHex = wishIsDark(hex) ? "#F6F1FF" : (wishIsDark(design.ink) ? design.ink : "#2B2B2B")
        case .accent:
            card.accentHex = hex
        case .text:
            edit(element: element) { $0.colorHex = hex }
        case .auto:
            if let element = element {
                edit(element: element) { $0.colorHex = hex }
            } else if wishIsDark(hex) {
                card.backgroundHex = hex
                card.accentHex = wishMix(hex, with: "#FFFFFF", amount: 0.65)
                card.inkHex = "#F6F1FF"
            } else if wishLuminance(hex) > 0.85 {
                card.backgroundHex = hex
                card.inkHex = wishIsDark(design.ink) ? design.ink : "#2B2B2B"
            } else {
                card.accentHex = hex
                card.backgroundHex = wishMix(hex, with: "#FFFFFF", amount: 0.84)
                card.inkHex = wishIsDark(design.ink) ? design.ink : "#2B2B2B"
            }
        }
        return true
    }

    // Element tools used by the panel buttons (same code path as voice).
    func quick(_ action: WishAction) {
        let command = WishCommand(action: action, target: selected)
        let before = card
        if mutate(command) && card != before {
            undoStack.append(before)
            redoStack = []
        }
        if selected != nil { scheduleSelectionClear() }
    }

    func resetSelectedStyle() {
        guard let key = selected else { return }
        pushUndo()
        card.styles[key] = nil
    }

    // MARK: Collections

    func refreshChips() {
        var groups: [WishChipGroup] = []
        for link in app.links {
            guard let field = app.field(link.fieldKey) else { continue }
            var chips: [WishChip] = []
            var seen = Set<String>()
            if link.useShortcutText {
                for clip in clips where clip.allGroups.contains(where: { $0.caseInsensitiveCompare(link.collection) == .orderedSame }) {
                    let value = clip.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, seen.insert(value).inserted else { continue }
                    chips.append(WishChip(fieldKey: field.key, value: value, label: clip.name.isEmpty ? clip.key : clip.name))
                    if chips.count >= 40 { break }
                }
            } else {
                for record in records where record.collection.caseInsensitiveCompare(link.collection) == .orderedSame {
                    let value = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, seen.insert(value).inserted else { continue }
                    chips.append(WishChip(fieldKey: field.key, value: value, label: value))
                    if chips.count >= 40 { break }
                }
            }
            if !chips.isEmpty {
                groups.append(WishChipGroup(id: link.id, title: link.collection, fieldKey: field.key, chips: chips))
            }
        }
        chipGroups = groups
    }

    // MARK: Hints for the bottom bar

    var hints: [String] {
        switch page {
        case .home:
            return ["open Happy Birthday", "open Happy Diwali", "open Infographics", "WishBuilder", "\u{0916}\u{094B}\u{0932}\u{094B} \u{0926}\u{093F}\u{0935}\u{093E}\u{0932}\u{0940}"]
        case .builder:
            return builder.hints
        case .app:
            if selected != nil {
                return ["bigger", "smaller", "make it gold", "move left", "bold", "hide it", "done"]
            }
            if app.kind == .infographic {
                return ["next design", "make it blue", "title Our plan", "bigger title", "Hindi", "undo"]
            }
            return ["make it pink", "name Yogesh", "bigger title", "next design", "more magic", "\u{0907}\u{0938}\u{0947} \u{0917}\u{0941}\u{0932}\u{093E}\u{092C}\u{0940} \u{0915}\u{0930}\u{094B}", "undo"]
        }
    }

    var commandPlaceholder: String {
        switch page {
        case .home: return "Say or type an app name, like \u{201C}Happy Birthday\u{201D}"
        case .builder: return builder.placeholder
        case .app: return "Say or type one command, like \u{201C}make it pink\u{201D}"
        }
    }

    var contextLine: String {
        switch page {
        case .home: return "WishStudio \u{00B7} Home"
        case .builder: return "WishBuilder \u{00B7} " + builder.contextLine
        case .app: return app.name + " \u{00B7} " + (selected.map { "\($0) selected" } ?? "whole card")
        }
    }

    // MARK: Output

    private func fallbackImage() -> NSImage? {
        let canvas = WishCardCanvas(app: app, card: card, design: design, context: context, selected: nil, animated: false)
        return WishExport.image(of: canvas, scale: 2)
    }

    private func snapshotImage(_ done: @escaping (NSImage?) -> Void) {
        if isOnApp {
            web.snapshot { [weak self] image in
                done(image ?? self?.fallbackImage())
            }
        } else {
            done(fallbackImage())
        }
    }

    func exportPNG() {
        snapshotImage { [weak self] image in
            guard let self = self else { return }
            guard let image = image, let data = WishExport.pngData(from: image) else {
                self.status = "Could not make the image."
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType.png]
            panel.nameFieldStringValue = "\(self.app.name) card.png"
            guard panel.runModal() == .OK, let url = panel.url else {
                self.status = "Download cancelled."
                return
            }
            do {
                try data.write(to: url)
                self.status = "Saved \(url.lastPathComponent)."
            } catch {
                self.status = "Could not save: \(error.localizedDescription)"
            }
        }
    }

    func copyImage() {
        snapshotImage { [weak self] image in
            guard let self = self else { return }
            guard let image = image else {
                self.status = "Could not make the image."
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            self.status = "Image copied. Paste it into a message."
        }
    }

    func shareImage() {
        snapshotImage { [weak self] image in
            guard let self = self else { return }
            guard let image = image, let view = NSApp.keyWindow?.contentView else {
                self.status = "Could not make the image."
                return
            }
            let picker = NSSharingServicePicker(items: [image])
            let anchor = NSRect(x: view.bounds.midX, y: 40, width: 1, height: 1)
            picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
        }
    }

    /// Saves the card as a real web page (with its pictures, GIFs and videos) and opens it in the browser.
    func openAsWebPage() {
        guard let base = store.directory else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let folder = base.appendingPathComponent("WishPages", isDirectory: true)
            .appendingPathComponent("\(app.name) \(formatter.string(from: Date()))", isDirectory: true)
        let mediaFolder = folder.appendingPathComponent("media", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
            for item in card.media ?? [] {
                if let source = store.mediaURL(item.file) {
                    try? FileManager.default.copyItem(at: source, to: mediaFolder.appendingPathComponent(item.file))
                }
            }
            let json = WishHTML.stateJSON(app: app, card: card, design: design, context: context, selected: nil) { file in
                return "media/" + file
            }
            let index = folder.appendingPathComponent("index.html")
            try WishHTML.page(stateJSON: json, interactive: false).write(to: index, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(index)
            status = "Opened as a web page. It is saved in \(folder.path)."
        } catch {
            status = "Could not save the web page: \(error.localizedDescription)"
        }
    }
}

// MARK: - Workspace

struct WishStudioWorkspace: View {
    let directory: URL
    let collections: [String]
    let records: [CollectionRecord]
    let clips: [Clip]

    @StateObject private var model = WishStudioModel()

    var body: some View {
        VStack(spacing: 0) {
            WishHeader(model: model, store: model.store)
            Divider().overlay(WishTheme.line)
            content
            Divider().overlay(WishTheme.line)
            WishCommandBar(model: model, voice: model.voice)
        }
        .background(WishTheme.page)
        .environment(\.colorScheme, .light)
        .tint(WishTheme.accent)
        .foregroundStyle(WishTheme.ink)
        .onAppear {
            model.records = records
            model.clips = clips
            model.collections = collections
            model.start(directory: directory)
        }
        .onChange(of: records.count) { _ in
            model.records = records
            model.refreshChips()
        }
        .onChange(of: clips.count) { _ in
            model.clips = clips
            model.refreshChips()
        }
        .onChange(of: collections) { _ in
            model.collections = collections
        }
        .onDisappear { model.voice.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.page {
        case .home:
            WishHomeView(model: model, store: model.store)
        case .builder:
            WishBuilderView(model: model, store: model.store, builder: model.builder)
        case .app:
            WishStudioView(model: model, store: model.store)
        }
    }
}

// MARK: - Cover thumbnail

struct WishCover: View {
    let app: WishApp
    let store: WishStore
    var emojiSize: CGFloat = 34

    private var url: URL? {
        guard let file = app.coverFile else { return nil }
        return store.mediaURL(file)
    }

    private var isVideo: Bool {
        guard let url = url else { return false }
        return ["mp4", "mov", "m4v", "webm"].contains(url.pathExtension.lowercased())
    }

    var body: some View {
        ZStack {
            if let url = url, FileManager.default.fileExists(atPath: url.path) {
                WishCoverMedia(url: url, isVideo: isVideo, framing: app.coverFraming ?? WishFraming())
            } else {
                // Same look as an AppBuilder app without a cover: a clear icon on a warm gradient.
                LinearGradient(colors: [Butter.coral.opacity(0.86), Color.pink.opacity(0.75), Color.orange.opacity(0.62)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: app.artwork)
                    .font(.system(size: emojiSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.white)
            }
        }
        .clipped()
    }
}

// Plays a cover video (muted, looping, at most 10 seconds) or an animated GIF. A plain SwiftUI Image only shows the first frame.
struct WishCoverMedia: NSViewRepresentable {
    let url: URL
    let isVideo: Bool
    let framing: WishFraming

    func makeNSView(context: Context) -> WishCoverMediaView {
        let view = WishCoverMediaView()
        view.load(url: url, isVideo: isVideo, framing: framing)
        return view
    }

    func updateNSView(_ view: WishCoverMediaView, context: Context) {
        if view.loadedURL != url {
            view.load(url: url, isVideo: isVideo, framing: framing)
        } else {
            view.update(framing: framing)
        }
    }

    static func dismantleNSView(_ view: WishCoverMediaView, coordinator: ()) {
        view.stop()
    }
}

final class WishCoverMediaView: NSView {
    private(set) var loadedURL: URL?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private let imageView = NSImageView()
    private var contentSize = CGSize.zero
    private var duration: Double = 0
    private var framing = WishFraming()
    private var isVideo = false
    private var generation = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        imageView.animates = true
        imageView.imageScaling = .scaleAxesIndependently
        imageView.isHidden = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func load(url: URL, isVideo: Bool, framing: WishFraming) {
        stop()
        generation += 1
        let mine = generation
        loadedURL = url
        self.isVideo = isVideo
        self.framing = framing
        if isVideo {
            imageView.isHidden = true
            let asset = AVURLAsset(url: url)
            let pl = AVPlayerLayer()
            pl.videoGravity = .resizeAspectFill
            pl.frame = bounds
            layer?.addSublayer(pl)
            playerLayer = pl
            Task { @MainActor [weak self] in
                guard let size = await Self.naturalSize(of: asset), let total = try? await asset.load(.duration).seconds else { return }
                guard let self = self, self.generation == mine else { return }
                self.contentSize = size
                self.duration = total.isFinite ? total : 0
                self.startPlayback(asset: asset)
                self.needsLayout = true
            }
        } else if let image = NSImage(contentsOf: url) {
            contentSize = image.size
            imageView.image = image
            imageView.animates = true
            imageView.isHidden = false
        }
        needsLayout = true
    }

    func update(framing newValue: WishFraming) {
        let startChanged = abs(newValue.ps() - framing.ps()) > 0.01
        framing = newValue
        if isVideo && startChanged, let asset = player?.currentItem?.asset {
            startPlayback(asset: asset)
        }
        needsLayout = true
    }

    /// Plays from `start` for at most 10 seconds, then loops.
    private func startPlayback(asset: AVAsset) {
        player?.pause()
        looper?.disableLooping()
        let start = duration > 0 ? min(framing.ps(), max(0, duration - 0.5)) : 0
        let length = duration > 0 ? min(WishFraming.maxSeconds, duration - start) : WishFraming.maxSeconds
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                duration: CMTime(seconds: length, preferredTimescale: 600))
        let queue = AVQueuePlayer()
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(asset: asset), timeRange: range)
        playerLayer?.player = queue
        player = queue
        queue.play()
    }

    private static func naturalSize(of asset: AVAsset) async -> CGSize? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return nil }
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    func stop() {
        generation += 1
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        imageView.image = nil
        imageView.isHidden = true
        contentSize = .zero
    }

    override func layout() {
        super.layout()
        guard contentSize.width > 0, contentSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            playerLayer?.frame = bounds
            return
        }
        // Aspect fill, then zoom, then slide so the chosen part shows. y = 0 is the top edge.
        let scale = max(bounds.width / contentSize.width, bounds.height / contentSize.height) * CGFloat(framing.pz())
        let w = contentSize.width * scale
        let h = contentSize.height * scale
        let originX = (bounds.width - w) * CGFloat(framing.px())
        let originY = (bounds.height - h) * CGFloat(1 - framing.py(video: isVideo))
        let frame = NSRect(x: originX, y: originY, width: w, height: h)
        if isVideo {
            playerLayer?.videoGravity = .resize
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer?.frame = frame
            CATransaction.commit()
        } else {
            imageView.frame = frame
        }
    }

    deinit { player?.pause() }
}

// Crop and position controls for a cover, a middle picture or a background.
struct WishFramingControls: View {
    @Binding var framing: WishFraming
    let isVideo: Bool
    let url: URL?
    var startsOpen: Bool = false
    @State private var open = false
    @State private var videoSeconds: Double = 0

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: Binding(
                    get: { nearest(framing.py(video: isVideo)) },
                    set: { framing.y = $0 }
                )) {
                    Text("Top").tag(0.0)
                    Text("Middle").tag(0.5)
                    Text("Bottom").tag(1.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                slider("Up / down", value: Binding(get: { framing.py(video: isVideo) }, set: { framing.y = $0 }), range: 0...1)
                slider("Left / right", value: Binding(get: { framing.px() }, set: { framing.x = $0 }), range: 0...1)
                slider("Zoom (crop)", value: Binding(get: { framing.pz() }, set: { framing.zoom = $0 }), range: 1...3)
                if isVideo {
                    let total = videoSeconds
                    if total > WishFraming.maxSeconds + 0.5 {
                        slider("Start at \(Int(framing.ps()))s", value: Binding(get: { framing.ps() }, set: { framing.start = $0.rounded() }), range: 0...max(1, total - WishFraming.maxSeconds))
                    }
                    Text(total > 0 ? "Plays 10 seconds at most, then loops. This video is \(Int(total.rounded()))s long." : "Plays 10 seconds at most, then loops.")
                        .font(.system(size: 11))
                        .foregroundStyle(WishTheme.muted)
                }
                Button("Reset position") { framing = WishFraming() }
                    .controlSize(.small)
            }
            .padding(.top, 6)
        } label: {
            Text("Crop and position").font(.system(size: 12, weight: .semibold))
        }
        .onAppear { if startsOpen { open = true } }
        .task(id: url) {
            guard isVideo, let url = url else { videoSeconds = 0; return }
            let seconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            videoSeconds = seconds.isFinite ? seconds : 0
        }
    }

    private func nearest(_ value: Double) -> Double {
        return [0.0, 0.5, 1.0].min { abs($0 - value) < abs($1 - value) } ?? 0
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(WishTheme.muted).frame(width: 84, alignment: .leading)
            Slider(value: value, in: range)
        }
    }
}

// MARK: - Header: cover title or app tabs

struct WishHeader: View {
    @ObservedObject var model: WishStudioModel
    @ObservedObject var store: WishStore

    var body: some View {
        if model.page == .home {
            home
        } else {
            tabs
        }
    }

    private var home: some View {
        HStack(spacing: 14) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.white)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Butter.coral.opacity(0.9), Color.pink.opacity(0.8), Color.orange.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 3) {
                Text("WishStudio").font(.system(size: 23, weight: .bold, design: .rounded))
                Text("Greetings and infographics that open like a web page, with photos, GIFs and video.")
                    .font(.subheadline)
                    .foregroundStyle(WishTheme.muted)
            }
            Spacer()
            Button {
                model.openBuilder()
            } label: {
                Label("Create with WishBuilder", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .tint(Butter.coral)
        }
        .padding(18)
    }

    private var tabs: some View {
        HStack(spacing: 12) {
            Button {
                model.goHome()
            } label: {
                Label("WishStudio", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 112, height: 58)
            }
            .buttonStyle(.bordered)
            .tint(Butter.coral)
            Divider().frame(height: 38)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.apps) { item in
                        appTab(item)
                    }
                    builderTab
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(LinearGradient(colors: [Color.white.opacity(0.70), Butter.cream], startPoint: .leading, endPoint: .trailing))
        .overlay(alignment: .bottom) { Rectangle().fill(Butter.coral.opacity(0.12)).frame(height: 1) }
    }

    // Same size, colours and layout as an AppBuilder tab.
    private func tabBackground(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(active
                  ? LinearGradient(colors: [Color.white, Color(red: 0.95, green: 0.89, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                  : LinearGradient(colors: [Color.white.opacity(0.88), Butter.cream], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func appTab(_ item: WishApp) -> some View {
        let active = model.page == .app(item.id)
        return Button {
            model.openApp(item.id)
        } label: {
            HStack(spacing: 10) {
                WishCover(app: item, store: store, emojiSize: 22)
                    .frame(width: 64, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(item.kind.title.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(active ? Butter.coral : Color.secondary)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Image(systemName: "party.popper.fill")
                        Text("WISH APP")
                    }
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.secondary.opacity(0.85))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(width: 192, height: 66)
            .background(tabBackground(active: active))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(active ? Butter.coral.opacity(0.75) : Butter.coral.opacity(0.16), lineWidth: active ? 2 : 1))
            .shadow(color: Butter.coral.opacity(active ? 0.14 : 0.035), radius: active ? 8 : 3, y: 3)
        }
        .buttonStyle(.plain)
        .hoverInfo(title: item.name, detail: item.kind.title, footnote: "Click to open", symbol: "arrow.up.right", edge: .bottom)
    }

    private var builderTab: some View {
        let active = model.page == .builder
        return Button {
            model.openBuilder()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    LinearGradient(colors: [Butter.coral.opacity(0.86), Color.pink.opacity(0.75), Color.orange.opacity(0.62)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 64, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text("WishBuilder").font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1)
                    Text("CREATE APPS").font(.system(size: 8, weight: .bold)).foregroundStyle(active ? Butter.coral : Color.secondary)
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                        Text("FROM A PROMPT")
                    }
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.secondary.opacity(0.85))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(width: 192, height: 66)
            .background(tabBackground(active: active))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(active ? Butter.coral.opacity(0.75) : Butter.coral.opacity(0.16), lineWidth: active ? 2 : 1))
            .shadow(color: Butter.coral.opacity(active ? 0.14 : 0.035), radius: active ? 8 : 3, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cover page

struct WishHomeView: View {
    @ObservedObject var model: WishStudioModel
    @ObservedObject var store: WishStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose an app to get started").font(.system(size: 25, weight: .bold, design: .rounded))
                    Text("Each app is a small web page you fill in, restyle and save as a template. Or describe a new one and WishBuilder makes it.")
                        .foregroundStyle(WishTheme.muted)
                        .frame(maxWidth: 780, alignment: .leading)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 236, maximum: 300), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(store.apps) { item in
                        appCard(item)
                    }
                    builderCard
                }
                if !store.templates.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your templates").font(.system(size: 17, weight: .semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 12)], alignment: .leading, spacing: 12) {
                            ForEach(store.templates) { template in
                                templateCard(template)
                            }
                        }
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: 1260, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func appCard(_ item: WishApp) -> some View {
        let cover = item.coverFile.flatMap { store.mediaURL($0)?.path } ?? ""
        return AppGalleryCard(
            title: item.name,
            description: item.tagline.isEmpty ? item.prompt : item.tagline,
            sample: "",
            category: item.kind.title,
            icon: item.artwork,
            iconPath: "",
            coverPath: cover,
            credits: "",
            colors: [Butter.coral.opacity(0.86), Color.pink.opacity(0.75), Color.orange.opacity(0.62)],
            action: { model.openApp(item.id) },
            coverFraming: item.coverFraming ?? WishFraming(),
            showsCredits: false,
            badge: "WISH"
        )
    }

    private var builderCard: some View {
        Button {
            model.openBuilder()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 34))
                    .foregroundStyle(WishTheme.accent)
                Text("Create with WishBuilder").font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Describe the app. WishBuilder asks for anything missing, maps your collections and builds it.")
                    .font(.system(size: 12))
                    .foregroundStyle(WishTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 262)
            .background(RoundedRectangle(cornerRadius: 16).fill(WishTheme.accentSoft.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WishTheme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.4, dash: [6, 4])))
        }
        .buttonStyle(.plain)
    }

    private func templateCard(_ template: WishTemplate) -> some View {
        let appName = store.app(id: template.appID)?.name ?? "App"
        let design = store.app(id: template.appID).map { WishDesigns.design(id: template.designID, kind: $0.kind) }
        let bg = template.backgroundHex ?? design?.background ?? "#EFE6FA"
        let accent = template.accentHex ?? design?.accent ?? "#7B52B8"
        return Button {
            model.openApp(template.appID)
            model.applyTemplate(template)
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(wishHex: bg), Color(wishHex: accent)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(appName).font(.system(size: 11)).foregroundStyle(WishTheme.muted)
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WishTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - An open app

struct WishStudioView: View {
    @ObservedObject var model: WishStudioModel
    @ObservedObject var store: WishStore

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            preview
            WishInspector(model: model, store: store)
                .frame(width: 350)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var preview: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Circle().fill(Color.green.opacity(0.7)).frame(width: 7, height: 7)
                Text("LIVE PAGE").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(WishTheme.muted)
                Text("Tap any text on the card to select it.").font(.system(size: 11)).foregroundStyle(WishTheme.muted)
                Spacer()
                Button {
                    model.web.replay()
                } label: {
                    Label("Replay", systemImage: "play.circle")
                }
                Button {
                    model.openAsWebPage()
                } label: {
                    Label("Open as web page", systemImage: "safari")
                }
                Menu {
                    Button("Download PNG\u{2026}") { model.exportPNG() }
                    Button("Copy image") { model.copyImage() }
                    Button("Share\u{2026}") { model.shareImage() }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            WishWebView(stateJSON: model.stateJSON, controller: model.web) { key in
                model.select(key.isEmpty ? nil : key)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WishTheme.line, lineWidth: 1))
            .onHover { inside in model.hovering = inside }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Inspector

struct WishInspector: View {
    @ObservedObject var model: WishStudioModel
    @ObservedObject var store: WishStore

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.inspector) {
                ForEach(WishInspectorTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            Divider().overlay(WishTheme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.inspector {
                    case .details: WishDetailsTab(model: model)
                    case .theme: WishThemeTab(model: model)
                    case .media: WishMediaTab(model: model)
                    case .templates: WishTemplatesTab(model: model)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WishTheme.line, lineWidth: 1))
    }
}

func wishCaption(_ text: String) -> some View {
    Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(WishTheme.muted)
}

// MARK: Details

struct WishDetailsTab: View {
    @ObservedObject var model: WishStudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Make it personal").font(.system(size: 17, weight: .semibold))
                Text("Fill these in. Drag a function onto any box, or type = for one.")
                    .font(.system(size: 12))
                    .foregroundStyle(WishTheme.muted)
            }
            Picker("", selection: Binding(get: { model.card.language }, set: { model.setLanguage($0) })) {
                ForEach(WishLanguage.allCases, id: \.self) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ForEach(model.app.fields) { field in
                WishFieldEditor(model: model, field: field)
            }

            if model.selected != nil {
                WishSelectionTools(model: model)
            }

            WishFunctionShelf(store: model.store, tap: { formula in
                let key = model.app.field(model.focusKey) != nil ? model.focusKey : (model.app.fields.first(where: { $0.type == .date })?.key ?? model.app.fields.first?.key ?? "")
                model.insertFormula(formula, into: key)
            })
        }
    }
}

struct WishFieldEditor: View {
    @ObservedObject var model: WishStudioModel
    let field: WishField
    @FocusState private var focused: Bool

    private var label: String {
        if model.card.language == .hindi && !field.labelHi.isEmpty { return field.labelHi }
        return field.label
    }

    private var binding: Binding<String> {
        return Binding(get: { model.card.value(for: field.key) }, set: { model.edit(field.key, to: $0) })
    }

    private var shown: String? {
        let raw = model.card.value(for: field.key)
        guard WishFormula.isFormula(raw) || raw.contains("{=") else { return nil }
        return model.context.variables[field.key.lowercased()]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 12, weight: .semibold))
                if model.selected?.lowercased() == field.key.lowercased() {
                    Text("selected").font(.system(size: 10)).foregroundStyle(WishTheme.accent)
                }
                Spacer()
            }
            if field.type == .longText || field.type == .list {
                TextEditor(text: binding)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(minHeight: field.type == .list ? 96 : 72)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WishTheme.line, lineWidth: 1))
            } else {
                TextField(field.placeholder.isEmpty ? label : field.placeholder, text: binding)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
            }
            if field.type == .list {
                Text("One item per line. Add a number after a comma for charts, like Sales, 40.")
                    .font(.system(size: 10))
                    .foregroundStyle(WishTheme.muted)
            }
            if let shown = shown {
                Text("= \(shown)").font(.system(size: 11)).foregroundStyle(WishTheme.accent)
            }
            ForEach(model.chipGroups.filter { $0.fieldKey == field.key }) { group in
                VStack(alignment: .leading, spacing: 4) {
                    wishCaption(group.title)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 5)], alignment: .leading, spacing: 5) {
                        ForEach(group.chips, id: \.self) { chip in
                            Button {
                                model.useChip(chip)
                            } label: {
                                Text(chip.label)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(WishTheme.accentSoft))
                                    .overlay(Capsule().strokeBorder(WishTheme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.clear))
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first else { return false }
            model.insertFormula(first, into: field.key)
            return true
        }
        .onChange(of: focused) { isFocused in
            if isFocused { model.focusKey = field.key }
        }
    }
}

/// Function chips you can drag onto a box (or tap). They write =Date, =Date+1 and so on for you.
struct WishFunctionShelf: View {
    @ObservedObject var store: WishStore
    var tap: (String) -> Void
    var expanded: Bool = false
    @State private var isOpen = false

    private let popular: [String] = [
        "=Date", "=Date+1", "=Date-1", "=Date+7", "=Time", "=Time+1", "=Month", "=Month+1", "=Year", "=Weekday", "=Day",
        "=TEXT(Date,\"dddd, d mmmm yyyy\")", "=GREETING()", "=COUNTDOWN(DATE(2027,1,1))", "=UPPER(\"hello\")", "=INR(125000)",
    ]

    var body: some View {
        if expanded {
            chips
        } else {
            DisclosureGroup(isExpanded: $isOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Drag a chip onto a box above, or click it to add it to the box you last used.")
                        .font(.system(size: 11))
                        .foregroundStyle(WishTheme.muted)
                    chips
                }
                .padding(.top, 6)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "function")
                    Text("Functions").font(.system(size: 13, weight: .semibold))
                }
            }
        }
    }

    private var chips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(popular, id: \.self) { formula in
                chip(formula, mine: false)
            }
            ForEach(store.functions) { function in
                chip("=" + function.name, mine: true)
            }
        }
    }

    private func chip(_ formula: String, mine: Bool) -> some View {
        let short = formula.count > 22 ? String(formula.prefix(20)) + "\u{2026}" : formula
        return Text(short)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(mine ? Color(wishHex: "#FBE3E6") : WishTheme.accentSoft))
            .overlay(Capsule().strokeBorder(WishTheme.line, lineWidth: 1))
            .draggable(formula)
            .onTapGesture { tap(formula) }
            .help(formula)
    }
}

struct WishSelectionTools: View {
    @ObservedObject var model: WishStudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                wishCaption("Selected")
                Text(model.selected ?? "").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("Done") { model.select(nil) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WishTheme.accent)
            }
            HStack(spacing: 6) {
                ForEach(WishTheme.swatches, id: \.self) { hex in
                    Button {
                        model.quick(.color(.text, hex: hex, name: hex))
                    } label: {
                        Circle().fill(Color(wishHex: hex)).frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(WishTheme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                tool("textformat.size.smaller") { model.quick(.scale(0.9)) }
                tool("textformat.size.larger") { model.quick(.scale(1.1)) }
                tool("arrow.left") { model.quick(.move(dx: -10, dy: 0)) }
                tool("arrow.up") { model.quick(.move(dx: 0, dy: -10)) }
                tool("arrow.down") { model.quick(.move(dx: 0, dy: 10)) }
                tool("arrow.right") { model.quick(.move(dx: 10, dy: 0)) }
                tool("bold") { model.quick(.bold) }
                tool("italic") { model.quick(.italic) }
                tool("eye.slash") { model.quick(.hide) }
                tool("arrow.counterclockwise") { model.resetSelectedStyle() }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(WishTheme.accentSoft))
    }

    private func tool(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(WishTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: Theme

struct WishThemeTab: View {
    @ObservedObject var model: WishStudioModel

    private var backgroundHex: String { return model.card.backgroundHex ?? model.design.background }
    private var accentHex: String { return model.card.accentHex ?? model.design.accent }
    private var inkHex: String { return model.card.inkHex ?? model.design.ink }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Theme").font(.system(size: 17, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                wishCaption("Colour themes")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(WishPalettes.all) { palette in
                        paletteTile(palette)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    wishCaption("Fine-tune")
                    Spacer()
                    Button("Reset colours") { model.resetColors() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(WishTheme.accent)
                }
                colorRow("Background", hex: backgroundHex) { model.setBackground($0) }
                colorRow("Accent", hex: accentHex) { model.setAccent($0) }
                colorRow("Text", hex: inkHex) { model.setInk($0) }
            }

            VStack(alignment: .leading, spacing: 8) {
                wishCaption("Lettering and motion")
                Picker("Lettering", selection: Binding(get: { model.card.fontStyle }, set: { model.setFontStyle($0) })) {
                    ForEach(WishFontStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                HStack {
                    Text("Text size").font(.system(size: 12))
                    Slider(value: Binding(get: { model.card.textScale }, set: { model.card.textScale = $0 }), in: 0.6...1.8) { editing in
                        if editing { model.beginSlider() }
                    }
                    Text("\(Int((model.card.textScale * 100).rounded()))%").font(.system(size: 11)).foregroundStyle(WishTheme.muted).frame(width: 40)
                }
                HStack {
                    Text("Magic").font(.system(size: 12))
                    Slider(value: Binding(get: { Double(model.card.magic) }, set: { model.card.magic = Int($0.rounded()) }), in: 0...3, step: 1) { editing in
                        if editing { model.beginSlider() }
                    }
                    Text(["None", "A little", "Just enough", "Lots"][min(3, max(0, model.card.magic))])
                        .font(.system(size: 11))
                        .foregroundStyle(WishTheme.muted)
                        .frame(width: 64, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                wishCaption("Layout (\(model.designs.count))")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                    ForEach(model.designs) { item in
                        layoutTile(item)
                    }
                }
            }

            if model.app.kind == .greeting {
                VStack(alignment: .leading, spacing: 8) {
                    wishCaption("Artwork")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                        ForEach(WishArtwork.choices, id: \.symbol) { choice in
                            let active = model.card.artwork == choice.symbol
                            Button {
                                model.setArtwork(choice.symbol)
                            } label: {
                                Text(WishArtwork.emoji(choice.symbol))
                                    .font(.system(size: 16))
                                    .frame(width: 28, height: 28)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(active ? WishTheme.accentSoft : Color.clear))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(active ? WishTheme.accent : WishTheme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help(choice.name)
                        }
                    }
                }
            }
        }
    }

    private func paletteTile(_ palette: WishPalette) -> some View {
        let active = model.card.backgroundHex == palette.bg && model.card.accentHex == palette.accent
        return Button {
            model.applyPalette(palette)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(Color(wishHex: palette.bg))
                    Circle().fill(Color(wishHex: palette.accent)).frame(width: 18, height: 18)
                }
                .frame(height: 38)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(active ? WishTheme.accent : WishTheme.line, lineWidth: active ? 2 : 1))
                Text(palette.name).font(.system(size: 9)).foregroundStyle(WishTheme.muted).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func colorRow(_ title: String, hex: String, _ set: @escaping (String) -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Text(hex.uppercased()).font(.system(size: 11, design: .monospaced)).foregroundStyle(WishTheme.muted)
            ColorPicker("", selection: Binding(get: { Color(wishHex: hex) }, set: { set(wishHex(from: $0)) }), supportsOpacity: false)
                .labelsHidden()
        }
    }

    private func layoutTile(_ item: WishDesign) -> some View {
        let active = item.id == model.card.designID
        return Button {
            model.chooseDesign(item.id)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color(wishHex: item.background))
                    Text(model.app.kind == .greeting ? WishArtwork.emoji(model.card.artwork) : "\u{1F4CA}").font(.system(size: 22))
                }
                .frame(height: 64)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? WishTheme.accent : WishTheme.line, lineWidth: active ? 2 : 1))
                Text(item.name).font(.system(size: 9)).foregroundStyle(active ? WishTheme.accent : WishTheme.muted).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: Media

struct WishMediaTab: View {
    @ObservedObject var model: WishStudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pictures, GIFs and video").font(.system(size: 17, weight: .semibold))
                Text("The card is a web page, so a GIF or video plays right on it. PNG, JPG, GIF, MP4 and MOV work.")
                    .font(.system(size: 12))
                    .foregroundStyle(WishTheme.muted)
            }
            if model.app.kind == .greeting {
                slot(title: "Middle of the card", detail: "Replaces the artwork circle.", placement: "hero")
            }
            slot(title: "Background", detail: "Fills the whole card behind the text.", placement: "background")
            VStack(alignment: .leading, spacing: 8) {
                wishCaption("Cover for this app")
                HStack(spacing: 12) {
                    WishCover(app: model.app, store: model.store, emojiSize: 26)
                        .frame(width: 96, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shown on the cover page and in the tab.").font(.system(size: 11)).foregroundStyle(WishTheme.muted)
                        HStack {
                            Button("Choose\u{2026}") { model.chooseCover() }
                            if model.app.coverFile != nil {
                                Button("Remove") { model.removeCover() }
                            }
                        }
                        .controlSize(.small)
                    }
                }
                if model.app.coverFile != nil {
                    WishFramingControls(
                        framing: Binding(get: { model.app.coverFraming ?? WishFraming() }, set: { model.setCoverFraming($0) }),
                        isVideo: coverIsVideo,
                        url: model.app.coverFile.flatMap { model.store.mediaURL($0) }
                    )
                }
            }
            Text("Videos play without sound, 10 seconds at most, then loop. On the saved web page they loop too.")
                .font(.system(size: 11))
                .foregroundStyle(WishTheme.muted)
        }
    }

    private func slot(title: String, detail: String, placement: String) -> some View {
        let current = model.media(placement)
        return VStack(alignment: .leading, spacing: 8) {
            wishCaption(title)
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(WishTheme.accentSoft)
                    Image(systemName: icon(current))
                        .font(.system(size: 22))
                        .foregroundStyle(WishTheme.accent)
                }
                .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(current.map { $0.kind.capitalized + " added" } ?? "Nothing added").font(.system(size: 12, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(WishTheme.muted)
                    HStack {
                        Button(current == nil ? "Add\u{2026}" : "Replace\u{2026}") { model.chooseMedia(placement: placement) }
                        if current != nil {
                            Button("Remove") { model.removeMedia(placement: placement) }
                        }
                    }
                    .controlSize(.small)
                }
            }
            if let current = current {
                WishFramingControls(
                    framing: Binding(get: { current.framing ?? WishFraming() }, set: { model.setMediaFraming(placement: placement, $0) }),
                    isVideo: current.kind == "video",
                    url: model.store.mediaURL(current.file)
                )
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(WishTheme.page))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WishTheme.line, lineWidth: 1))
    }

    private var coverIsVideo: Bool {
        guard let file = model.app.coverFile else { return false }
        return ["mp4", "mov", "m4v", "webm"].contains((file as NSString).pathExtension.lowercased())
    }

    private func icon(_ media: WishMedia?) -> String {
        guard let media = media else { return "photo.on.rectangle.angled" }
        switch media.kind {
        case "video": return "play.rectangle.fill"
        case "gif": return "sparkles.rectangle.stack.fill"
        default: return "photo.fill"
        }
    }
}

// MARK: Templates

struct WishTemplatesTab: View {
    @ObservedObject var model: WishStudioModel
    @State private var name = ""
    @State private var includeText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Templates").font(.system(size: 17, weight: .semibold))
                Text("Save the colours, lettering and layout you like, then use them again in a click.")
                    .font(.system(size: 12))
                    .foregroundStyle(WishTheme.muted)
            }
            VStack(alignment: .leading, spacing: 8) {
                wishCaption("Save this look")
                TextField("Template name, like Soft pink family", text: $name).textFieldStyle(.roundedBorder)
                Toggle("Also keep my text", isOn: $includeText).toggleStyle(.checkbox).font(.system(size: 12))
                Button {
                    model.saveTemplate(name: name, includeText: includeText)
                    name = ""
                } label: {
                    Label("Save as template", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(WishTheme.accentSoft))

            VStack(alignment: .leading, spacing: 8) {
                wishCaption("Your templates for \(model.app.name)")
                if model.templatesForApp.isEmpty {
                    Text("None yet.").font(.system(size: 12)).foregroundStyle(WishTheme.muted)
                }
                ForEach(model.templatesForApp) { template in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name).font(.system(size: 13, weight: .semibold))
                            Text(template.values == nil ? "Look only" : "Look and text").font(.system(size: 10)).foregroundStyle(WishTheme.muted)
                        }
                        Spacer()
                        Button("Use") { model.applyTemplate(template) }.controlSize(.small)
                        Button(role: .destructive) {
                            model.deleteTemplate(template)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WishTheme.line, lineWidth: 1))
                }
            }
        }
    }
}

// MARK: - Bottom bar (the only microphone)

struct WishCommandBar: View {
    @ObservedObject var model: WishStudioModel
    @ObservedObject var voice: WishVoiceController
    @State private var showError = false

    private var fieldText: Binding<String> {
        return Binding(
            get: { (voice.isListening && !voice.heard.isEmpty) ? voice.heard : model.commandText },
            set: { model.commandText = $0 }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            mic
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(model.contextLine).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Picker("", selection: Binding(get: { model.voiceChoice }, set: { model.setVoiceChoice($0) })) {
                        Text("Auto").tag("auto")
                        Text("English").tag("english")
                        Text("\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}").tag("hindi")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 190)
                    .help("Language the microphone listens for")
                    if model.isOnApp {
                        Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                            .disabled(model.undoStack.isEmpty)
                        Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                            .disabled(model.redoStack.isEmpty)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                HStack(spacing: 8) {
                    TextField(model.commandPlaceholder, text: fieldText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.handleTranscript(model.commandText) }
                    Button("Apply") { model.handleTranscript(model.commandText) }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.commandText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack(spacing: 8) {
                    Text("TRY")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(WishTheme.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(model.hints, id: \.self) { hint in
                                Button {
                                    model.commandText = hint
                                } label: {
                                    Text(hint)
                                        .font(.system(size: 11))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.white))
                                        .overlay(Capsule().strokeBorder(WishTheme.line, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Text(model.status)
                    .font(.system(size: 11))
                    .foregroundStyle(WishTheme.muted)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(WishTheme.accentSoft.opacity(0.5))
        .onChange(of: voice.errorMessage) { value in showError = !value.isEmpty }
        .alert("Voice commands", isPresented: $showError) {
            Button("OK") { voice.errorMessage = "" }
        } message: {
            Text(voice.errorMessage)
        }
    }

    private var mic: some View {
        Button {
            model.toggleVoice()
        } label: {
            ZStack {
                Circle()
                    .fill(WishTheme.accent.opacity(0.18))
                    .frame(width: 66, height: 66)
                    .scaleEffect(voice.isListening ? 1 + CGFloat(voice.level) * 0.45 : 1)
                    .animation(.easeOut(duration: 0.12), value: voice.level)
                Circle()
                    .fill(LinearGradient(colors: voice.isListening ? [Color.red, Color.pink] : [WishTheme.accent, Color(wishHex: "#9B6FE0")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 52, height: 52)
                Image(systemName: voice.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 72, height: 72)
        }
        .buttonStyle(.plain)
        .help(voice.isListening ? "Listening. Click to stop." : "Start listening")
    }
}
