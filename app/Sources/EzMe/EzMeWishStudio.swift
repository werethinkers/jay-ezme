// WishStudio: its own menu in EzMe, separate from AppBuilder.
//   Studio      - pick an app (Birthday, Anniversary, Diwali, Infographics, or your own), pick a design,
//                 fill in the details and change the card live with one voice command at a time.
//   WishBuilder - define what kind of apps WishStudio can make (Application, Information, Collection,
//                 Function, Live Changes). See EzMeWishBuilder.swift.
import SwiftUI
import AppKit
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

struct WishChipGroup: Identifiable {
    var id: String
    var title: String
    var fieldKey: String
    var chips: [WishChip]
}

// MARK: - Model

@MainActor
final class WishStudioModel: ObservableObject {
    let store = WishStore()
    let voice = WishVoiceController()

    @Published var appID: String = ""
    @Published var card = WishCard(appID: "", designID: "g-lavender") {
        didSet { persistCard() }
    }
    @Published var selected: String? = nil
    @Published var status: String = "Tap the mic and say one thing to change, like \u{201C}make it pink\u{201D}."
    @Published var commandText: String = ""
    @Published private(set) var undoStack: [WishCard] = []
    @Published private(set) var redoStack: [WishCard] = []
    @Published var chipGroups: [WishChipGroup] = []
    @Published var replayToken = 0

    var hovering = false
    var records: [CollectionRecord] = []
    var clips: [Clip] = []

    private var selectionTask: Task<Void, Never>?
    private var started = false
    private var typingKey = ""
    private var typingTime = Date.distantPast

    // MARK: Current app

    var app: WishApp {
        return store.app(id: appID) ?? store.apps.first ?? WishApp(name: "WishStudio")
    }

    var designs: [WishDesign] { return WishDesigns.designs(for: app.kind) }
    var design: WishDesign { return WishDesigns.design(id: card.designID, kind: app.kind) }
    var context: WishContext { return store.context(for: card, app: app) }

    var environment: WishCommandEnvironment {
        return WishCommandEnvironment(app: app, apps: store.apps, designs: designs, chips: chipGroups.flatMap { $0.chips })
    }

    func start(directory: URL) {
        guard !started else { return }
        started = true
        store.load(directory: directory)
        let remembered = store.app(id: store.lastAppID) != nil ? store.lastAppID : (store.apps.first?.id ?? "")
        openApp(remembered, saveCurrent: false)
    }

    func openApp(_ id: String, saveCurrent: Bool = true) {
        if saveCurrent && !appID.isEmpty { store.cards[appID] = card }
        guard let target = store.app(id: id) else { return }
        appID = id
        store.lastAppID = id
        let options = WishDesigns.designs(for: target.kind)
        var next = store.cards[id] ?? WishCard.make(for: target, designID: options[0].id)
        if !options.contains(where: { $0.id == next.designID }) { next.designID = options[0].id }
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

    // MARK: Typing in the Make it personal panel

    func edit(_ key: String, to value: String) {
        guard let field = app.field(key) else { return }
        let now = Date()
        if typingKey != key || now.timeIntervalSince(typingTime) > 1.5 { pushUndo() }
        typingKey = key
        typingTime = now
        card.set(key, to: value, universal: field.universal)
    }

    func chooseDesign(_ id: String) {
        guard id != card.designID else { return }
        pushUndo()
        card.designID = id
        card.backgroundHex = nil
        card.accentHex = nil
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

    func setTextScale(_ value: Double) {
        card.textScale = value
    }

    func setMagic(_ value: Int) {
        card.magic = value
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
        card = WishCard.make(for: app, designID: designs[0].id)
        selected = nil
        status = "Card reset."
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

    // MARK: Voice and typed commands

    var recognitionLocale: String {
        switch app.live.recognition {
        case "english": return "en-IN"
        case "hindi": return "hi-IN"
        default: return card.language.speechIdentifier
        }
    }

    func toggleVoice() {
        if voice.isListening {
            voice.stop()
            status = "Mic off."
            return
        }
        status = "Listening. Say one command at a time."
        voice.start(localeIdentifier: recognitionLocale, commitDelay: app.live.commitDelay) { [weak self] text in
            self?.handleTranscript(text)
        }
    }

    func syncVoice() {
        voice.changeLanguage(recognitionLocale)
        voice.updatePause(app.live.commitDelay)
    }

    /// The one entry point for a command, spoken or typed.
    func handleTranscript(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        commandText = ""
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
                if let before = baseline, card != before { undoStack.append(before); redoStack = [] }
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
            return true
        case .stepDesign(let step):
            let list = designs
            let current = list.firstIndex(where: { $0.id == card.designID }) ?? 0
            let next = ((current + step) % list.count + list.count) % list.count
            card.designID = list[next].id
            card.backgroundHex = nil
            card.accentHex = nil
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
            } else if wishLuminance(hex) > 0.85 {
                card.backgroundHex = hex
            } else {
                card.accentHex = hex
                card.backgroundHex = wishMix(hex, with: "#FFFFFF", amount: 0.84)
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

    // MARK: Output

    private func renderedImage() -> NSImage? {
        let canvas = WishCardCanvas(app: app, card: card, design: design, context: context, selected: nil, animated: false)
        return WishExport.image(of: canvas, scale: 2)
    }

    func exportPNG() {
        guard let image = renderedImage(), let data = WishExport.pngData(from: image) else {
            status = "Could not make the image."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.png]
        panel.nameFieldStringValue = "\(app.name) card.png"
        guard panel.runModal() == .OK, let url = panel.url else {
            status = "Download cancelled."
            return
        }
        do {
            try data.write(to: url)
            status = "Saved \(url.lastPathComponent)."
        } catch {
            status = "Could not save: \(error.localizedDescription)"
        }
    }

    func copyImage() {
        guard let image = renderedImage() else {
            status = "Could not make the image."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        status = "Image copied. Paste it into a message."
    }

    func shareImage() {
        guard let image = renderedImage(), let view = NSApp.keyWindow?.contentView else {
            status = "Could not make the image."
            return
        }
        let picker = NSSharingServicePicker(items: [image])
        let anchor = NSRect(x: view.bounds.midX, y: 40, width: 1, height: 1)
        picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }
}

// MARK: - Workspace

enum WishTab: String, CaseIterable {
    case studio = "Studio"
    case builder = "WishBuilder"
}

struct WishStudioWorkspace: View {
    let directory: URL
    let collections: [String]
    let records: [CollectionRecord]
    let clips: [Clip]

    @StateObject private var model = WishStudioModel()
    @State private var tab: WishTab = .studio

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(WishTheme.line)
            content
        }
        .background(WishTheme.page)
        .environment(\.colorScheme, .light)
        .tint(WishTheme.accent)
        .foregroundStyle(WishTheme.ink)
        .onAppear {
            model.records = records
            model.clips = clips
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
        .onDisappear { model.voice.stop() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(WishTheme.accent)
            Text("wishstudio")
                .font(.system(size: 24, weight: .semibold, design: .serif))
            Text("Little moments. Beautifully celebrated.")
                .font(.system(size: 12))
                .foregroundStyle(WishTheme.muted)
            Spacer()
            Picker("", selection: $tab) {
                ForEach(WishTab.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .studio:
            WishStudioView(model: model, store: model.store)
        case .builder:
            WishBuilderView(model: model, store: model.store, collections: collections, records: records, clips: clips, openStudio: { tab = .studio })
        }
    }
}

// MARK: - Studio tab

struct WishStudioView: View {
    @ObservedObject var model: WishStudioModel
    @ObservedObject var store: WishStore

    var body: some View {
        VStack(spacing: 0) {
            appTabs
            HStack(alignment: .top, spacing: 16) {
                WishDesignGallery(model: model)
                    .frame(width: 262)
                WishPreviewPane(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                WishPersonalPanel(model: model)
                    .frame(width: 330)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            Divider().overlay(WishTheme.line)
            WishCommandBar(model: model, voice: model.voice)
        }
    }

    private var appTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.apps) { item in
                    let active = item.id == model.appID
                    Button {
                        model.openApp(item.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 18))
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title(model.card.language)).font(.system(size: 14, weight: .semibold))
                                Text(item.tagline).font(.system(size: 11)).foregroundStyle(WishTheme.muted)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 12).fill(active ? WishTheme.accentSoft : Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(active ? WishTheme.accent : WishTheme.line, lineWidth: active ? 1.4 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
        }
    }
}

struct WishDesignGallery: View {
    @ObservedObject var model: WishStudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Find your kind of lovely").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(model.designs.count) designs")
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(WishTheme.accentSoft))
            }
            Text("A starting point for something special.").font(.system(size: 12)).foregroundStyle(WishTheme.muted)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
                    ForEach(model.designs) { item in
                        tile(item)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WishTheme.line, lineWidth: 1))
    }

    private func tile(_ item: WishDesign) -> some View {
        let active = item.id == model.card.designID
        let symbol = model.app.kind == .greeting ? model.card.artwork : "chart.pie.fill"
        return Button {
            model.chooseDesign(item.id)
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color(wishHex: item.background))
                    Image(systemName: symbol)
                        .font(.system(size: 26))
                        .foregroundStyle(Color(wishHex: item.accent))
                }
                .frame(height: 92)
                .overlay(alignment: .topTrailing) {
                    if active {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(WishTheme.accent)
                            .background(Circle().fill(Color.white))
                            .padding(5)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(active ? WishTheme.accent : Color.clear, lineWidth: 2))
                Text(item.name)
                    .font(.system(size: 11))
                    .foregroundStyle(active ? WishTheme.accent : WishTheme.muted)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct WishPreviewPane: View {
    @ObservedObject var model: WishStudioModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Circle().fill(Color.green.opacity(0.7)).frame(width: 7, height: 7)
                Text("LIVE PREVIEW").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(WishTheme.muted)
                Spacer()
                Button("Replay magic") { model.replayToken += 1 }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(WishTheme.muted)
            }
            GeometryReader { geo in
                let scale = max(0.2, min(geo.size.width / WishCardCanvas.size.width, geo.size.height / WishCardCanvas.size.height))
                WishCardCanvas(app: model.app, card: model.card, design: model.design, context: model.context, selected: model.selected, animated: true, onSelect: { key in model.select(key) })
                    .id(model.replayToken)
                    .shadow(color: Color.black.opacity(0.14), radius: 18, y: 8)
                    .scaleEffect(scale)
                    .frame(width: WishCardCanvas.size.width * scale, height: WishCardCanvas.size.height * scale)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .onHover { inside in model.hovering = inside }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(WishTheme.accentSoft.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WishTheme.line, lineWidth: 1))
    }
}

// MARK: - Make it personal

struct WishPersonalPanel: View {
    @ObservedObject var model: WishStudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Make it personal").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button {
                        model.resetCard()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Reset this card")
                }
                Text("The details that make it theirs.").font(.system(size: 12)).foregroundStyle(WishTheme.muted)

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

                look
                if model.app.kind == .greeting { artwork }
                functionHint
            }
            .padding(16)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WishTheme.line, lineWidth: 1))
    }

    private var look: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LOOK & FEEL").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(WishTheme.muted)
            Picker("Lettering", selection: Binding(get: { model.card.fontStyle }, set: { model.setFontStyle($0) })) {
                ForEach(WishFontStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }
            HStack {
                Text("Text size").font(.system(size: 12))
                Slider(value: Binding(get: { model.card.textScale }, set: { model.setTextScale($0) }), in: 0.6...1.8) { editing in
                    if editing { model.beginSlider() }
                }
                Text("\(Int((model.card.textScale * 100).rounded()))%").font(.system(size: 11)).foregroundStyle(WishTheme.muted).frame(width: 40)
            }
            HStack {
                Text("Magic").font(.system(size: 12))
                Slider(value: Binding(get: { Double(model.card.magic) }, set: { model.setMagic(Int($0.rounded())) }), in: 0...3, step: 1) { editing in
                    if editing { model.beginSlider() }
                }
                Text(["None", "A little", "Just enough", "Lots"][min(3, max(0, model.card.magic))])
                    .font(.system(size: 11))
                    .foregroundStyle(WishTheme.muted)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }

    private var artwork: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ARTWORK").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(WishTheme.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                ForEach(WishArtwork.choices, id: \.symbol) { choice in
                    let active = model.card.artwork == choice.symbol
                    Button {
                        model.setArtwork(choice.symbol)
                    } label: {
                        Image(systemName: choice.symbol)
                            .font(.system(size: 14))
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

    private var functionHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Functions work in any box").font(.system(size: 12, weight: .semibold))
            Text("Type =Date, =Date+1, =Time, =Month+1 or =TEXT(Date,\"dddd\"). Add your own in WishBuilder \u{2192} Function.")
                .font(.system(size: 11))
                .foregroundStyle(WishTheme.muted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(WishTheme.accentSoft))
    }
}

struct WishFieldEditor: View {
    @ObservedObject var model: WishStudioModel
    let field: WishField

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
                if model.selected == field.key {
                    Text("selected").font(.system(size: 10)).foregroundStyle(WishTheme.accent)
                }
                Spacer()
            }
            if field.type == .longText || field.type == .list {
                TextEditor(text: binding)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: field.type == .list ? 96 : 72)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WishTheme.line, lineWidth: 1))
            } else {
                TextField(field.placeholder.isEmpty ? label : field.placeholder, text: binding)
                    .textFieldStyle(.roundedBorder)
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
                    Text(group.title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(WishTheme.muted)
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
    }
}

struct WishSelectionTools: View {
    @ObservedObject var model: WishStudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SELECTED").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(WishTheme.muted)
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

// MARK: - Command bar (the only microphone)

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
                    Text("EDIT WHERE YOU POINT").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(WishTheme.muted)
                    Text(model.selected.map { "\($0) selected" } ?? "Whole card \u{00B7} No selection")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .disabled(model.undoStack.isEmpty)
                    Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                        .disabled(model.redoStack.isEmpty)
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
                HStack(spacing: 8) {
                    TextField("Say or type one command, like \u{201C}make it pink\u{201D}  \u{00B7}  \u{201C}\u{0907}\u{0938}\u{0947} \u{0917}\u{0941}\u{0932}\u{093E}\u{092C}\u{0940} \u{0915}\u{0930}\u{094B}\u{201D}", text: fieldText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.handleTranscript(model.commandText) }
                    Button("Apply") { model.handleTranscript(model.commandText) }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.commandText.trimmingCharacters(in: .whitespaces).isEmpty)
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
