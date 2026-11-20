// Wish Studio, simple: four steps. 1 Prompt (get four transparent backgrounds from KeyDo or ChatGPT), 2 Design (place
// variables, collections, functions, text, images and a logo; each fixed or dynamic), 3 Activate (the word that runs
// the app), 4 Use (fill in the blanks and make a card).
import SwiftUI
import AppKit

enum WishSimpleTheme {
    static let ink = Color(wishHex: "#26221F")
    static let muted = Color(wishHex: "#655F58")
    static let paper = Color(wishHex: "#F9F7F3")
    static let white = Color(wishHex: "#FFFEFA")
    static let line = Color(wishHex: "#E7E0D7")
    static let accent = Color(wishHex: "#A9402D")
    static let soft = Color(wishHex: "#F8E7E0")
    static let green = Color(wishHex: "#3A654E")
    static let stage = Color(wishHex: "#F2EDE6")
    static func serif(_ size: CGFloat) -> Font { .custom("Georgia", size: size) }
}

private struct SimpleCard<Content: View>: View {
    var title: String = ""
    var trailing: String = ""
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !title.isEmpty {
                HStack {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if !trailing.isEmpty { Text(trailing).font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted) }
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
                Divider().overlay(WishSimpleTheme.line)
            }
            content()
        }
        .background(RoundedRectangle(cornerRadius: 15).fill(WishSimpleTheme.white))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(WishSimpleTheme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }
}

private struct SimplePrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(WishSimpleTheme.accent.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

private struct SimpleQuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(WishSimpleTheme.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(WishSimpleTheme.white.opacity(configuration.isPressed ? 0.7 : 1)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WishSimpleTheme.line, lineWidth: 1))
    }
}

// MARK: - The studio

struct WishSimpleStudio: View {
    @ObservedObject var model: WishStudioModel
    @ObservedObject private var designs = AppDesignStore.shared
    @ObservedObject private var templates = TemplateStore.shared
    @State private var step = 0
    @State private var started = false
    @State private var note = ""
    @State private var showPrompt = false
    @State private var selectedSlot: String?
    @State private var draft: ImageTemplate?
    @State private var preview: NSImage?
    @State private var shortcut = ""
    @State private var lookFiles: [String] = []

    private var appID: String { model.appID }
    private var heading: String { UserDefaults.standard.string(forKey: "wishHeading." + appID) ?? model.app.name }
    private var designID: String? { WishAppLink.designID(model) }
    private var design: AppDesign? { designs.design(id: designID) }
    private var workingTemplate: ImageTemplate? { design.flatMap { $0.pages.first }.flatMap { templates.template(id: $0) } }
    private var template: ImageTemplate? { draft ?? workingTemplate }
    private var active: Bool { (design?.version ?? 0) > 0 }

    private let steps = [("Prompt", "Get your backgrounds"), ("Design", "Place your layers"), ("Activate", "Save your shortcut"), ("Use", "Make a card")]

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(WishSimpleTheme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        switch step {
                        case 0: PromptStep(model: model, heading: headingBinding, lookFiles: $lookFiles, note: $note, showPrompt: $showPrompt, onPick: pickLook, onDesign: { generate() }, onNext: { go(1) })
                        case 1: designStep
                        case 2: activateStep
                        default: useStep
                        }
                    }
                    if !note.isEmpty { Text(note).font(.system(size: 12)).foregroundStyle(WishSimpleTheme.muted).padding(.top, 14) }
                }
                .padding(.horizontal, 40).padding(.vertical, 30)
                .frame(maxWidth: 1180, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(WishSimpleTheme.paper)
        .foregroundStyle(WishSimpleTheme.ink)
        .onAppear {
            guard !started else { return }
            started = true
            lookFiles = WishLookStore.files(appID)
            draft = workingTemplate
            shortcut = design?.command ?? WishAppLink.currentWord(model.app.name)
            if designID != nil && !lookFiles.isEmpty { step = 1 }
            refreshPreview()
        }
        .sheet(isPresented: $showPrompt) { WishPromptSheet(prompt: chatGPTPrompt) }
        .onChange(of: model.appID) { _, _ in
            started = false
            step = 0
            draft = nil
        }
    }

    private var headingBinding: Binding<String> {
        Binding(get: { heading }, set: { UserDefaults.standard.set($0, forKey: "wishHeading." + appID); model.objectWillChange.send() })
    }

    private var chatGPTPrompt: String {
        let brief = UserDefaults.standard.string(forKey: "wishBrief." + appID) ?? "Elegant artwork with celebratory details around the edges. Leave the centre clear for the recipient's name."
        return "Create 4 different square \(heading) artwork PNGs at 2160 \u{00D7} 2160. Use real alpha transparency throughout the background, with no solid fill or painted checkerboard. Keep the centre and sign-off areas clear so I can place text and a name in KeyDo. Include decorative artwork only: no words and no letters. Creative direction: \(brief)"
    }

    // MARK: Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.app.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(WishSimpleTheme.muted).padding(.leading, 10).padding(.bottom, 10)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, item in
                let done = index == 0 ? designID != nil : index == 1 ? !(template?.slots.isEmpty ?? true) : index == 2 ? active : false
                Button { go(index) } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7).fill(step == index ? WishSimpleTheme.accent : done ? Color(wishHex: "#E7EEE4") : Color(wishHex: "#EEE9E0"))
                            if done && step != index { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(WishSimpleTheme.green) }
                            else { Text("\(index + 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(step == index ? .white : Color(wishHex: "#5E5149")) }
                        }
                        .frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0).font(.system(size: 13, weight: .semibold))
                            Text(item.1).font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(step == index ? Color(wishHex: "#F4E5DE") : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(step == index ? Color(wishHex: "#833625") : WishSimpleTheme.ink)
            }
            Spacer()
            Button { model.simple = false } label: { Label("Advanced tools", systemImage: "slider.horizontal.3").font(.system(size: 12)) }
                .buttonStyle(.plain).foregroundStyle(WishSimpleTheme.muted).padding(10)
                .help("Voice commands, templates, credits and the full designer.")
        }
        .padding(.top, 28).padding(.horizontal, 14).padding(.bottom, 14)
        .frame(width: 210)
    }

    private func go(_ index: Int) {
        if index >= 1 && designID == nil {
            note = "Choose a background in step 1 first."
            step = 0
            return
        }
        note = ""
        step = index
        if index >= 1 { draft = workingTemplate; refreshPreview() }
    }

    private func header(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wish Studio / \(model.app.name)").font(.system(size: 12)).foregroundStyle(WishSimpleTheme.muted)
            Text(title).font(WishSimpleTheme.serif(40)).tracking(-1.4)
            Text(detail).font(.system(size: 14)).foregroundStyle(WishSimpleTheme.muted)
        }
        .padding(.bottom, 24)
    }

    // MARK: Looks

    private func generate() {
        let made = WishLookMaker.make()
        guard !made.isEmpty else { note = "Could not draw the backgrounds."; return }
        var first: String?
        for image in made { if let file = WishLookStore.add(image, appID: appID), first == nil { first = file } }
        lookFiles = WishLookStore.files(appID)
        note = "KeyDo drew 4 transparent backgrounds. Pick one, then continue."
        if let first { pickLook(first, advance: false) }
    }

    private func pickLook(_ file: String, advance: Bool = false) {
        guard let image = WishLookStore.image(file) else { return }
        WishLookStore.select(file, appID: appID)
        var page: ImageTemplate
        if let existing = workingTemplate {
            page = existing
        } else {
            guard let made = AppDesignStore.shared.newFromPicture(image, name: model.app.name) else { note = "Could not start the design."; return }
            TemplateStore.setWishTemplate("design:" + made.id, appID: appID)
            guard let first = TemplateLinks.pages(for: "design:" + made.id).first else { return }
            page = first
            seedLayers(into: &page)
        }
        let fitted = TemplateImages.limited(image, maxSide: 3200)
        let size = TemplateImages.pixelSize(fitted)
        page.pixelWidth = Int(size.width)
        page.pixelHeight = Int(size.height)
        TemplateStore.shared.setOriginal(fitted, for: page)
        TemplateStore.shared.save(page)
        recolour(&page, hex: WishLookStore.backgroundHex(appID), save: true)
        draft = page
        model.objectWillChange.send()
        refreshPreview()
        if advance { go(1) }
    }

    /// The heading, a name to fill in and the sign-off, like the sample wish.
    private func seedLayers(into page: inout ImageTemplate) {
        func slot(_ key: String, _ content: String?, _ sample: String, _ y: Double, _ size: Double, h: Double) -> TemplateSlot {
            var s = TemplateSlot(key: key, kind: .text)
            s.content = content; s.sample = sample
            s.cx = 0.5; s.cy = y; s.w = 0.8; s.h = h; s.fontSize = size
            s.fontName = "Georgia"; s.colorHex = "#26221F"
            return s
        }
        let sender = UserDefaults.standard.string(forKey: "wishSender." + appID) ?? "From Jay Jain & Family"
        let example = UserDefaults.standard.string(forKey: "wishExample." + appID) ?? "Rohit"
        page.slots = [
            slot("heading", heading, heading, 0.26, 0.085, h: 0.12),
            slot("name", "{{name}}", example, 0.5, 0.12, h: 0.16),
            slot("sign-off", sender, sender, 0.87, 0.045, h: 0.08)
        ]
        page.slots[1].bold = true
        var app = model.app
        if app.field("name") == nil {
            var field = WishField(key: "name", label: "Name", type: .text)
            field.placeholder = example
            app.fields.append(field)
            model.store.updateApp(app)
        }
    }

    private func recolour(_ page: inout ImageTemplate, hex: String, save: Bool) {
        TemplateBackground.clearCache()
        let result = TemplateBackground.recoloured(page, hex: hex)
        guard let image = result.image else { if !result.message.isEmpty { note = result.message }; return }
        TemplateStore.shared.setPicture(image, for: page)
        let dark = (NSColor(templateHex: hex).usingColorSpace(.deviceRGB)).map { 0.299 * $0.redComponent + 0.587 * $0.greenComponent + 0.114 * $0.blueComponent < 0.45 } ?? false
        for index in page.slots.indices where page.slots[index].kind == .text {
            let level = NSColor(templateHex: page.slots[index].colorHex).usingColorSpace(.deviceRGB).map { 0.299 * $0.redComponent + 0.587 * $0.greenComponent + 0.114 * $0.blueComponent } ?? 0.5
            if dark && level < 0.45 { page.slots[index].colorHex = "#FFFFFF" }
            if !dark && level > 0.75 { page.slots[index].colorHex = "#26221F" }
        }
        if save { TemplateStore.shared.save(page) }
    }

    func refreshPreview() {
        guard let page = template, let base = TemplateStore.shared.basePicture(for: page) else { preview = nil; return }
        preview = TemplateRenderer.render(page, base: base, texts: nil, images: [:], useSamples: true, maxSide: 1000)
    }

    private func commit(_ page: ImageTemplate) {
        draft = page
        TemplateStore.shared.save(page)
        refreshPreview()
        WishDesignSync.sync(model)
        model.objectWillChange.send()
    }

    // MARK: Step 2: design

    private var designStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                header("Design your wish", "Choose the artwork, then drag each layer into place.")
                Spacer()
                Button("Continue \u{2192}") { go(2) }.buttonStyle(SimplePrimaryButton()).padding(.bottom, 24)
            }
            HStack(alignment: .top, spacing: 19) {
                SimpleCard(title: "Card canvas") {
                    VStack(spacing: 0) {
                        WishCanvas(template: template, preview: preview, selected: $selectedSlot,
                                   onMove: { id, x, y in moveSlot(id, x, y) }, onEnd: { if let page = draft { commit(page) } })
                        backgroundBar
                        LooksStrip(files: lookFiles, selected: WishLookStore.selectedFile(appID)) { pickLook($0) }
                    }
                }
                .frame(minWidth: 460)
                layersCard.frame(width: 330)
            }
        }
    }

    private func moveSlot(_ id: String, _ x: Double, _ y: Double) {
        guard var page = draft ?? workingTemplate, let index = page.slots.firstIndex(where: { $0.id == id }) else { return }
        page.slots[index].cx = min(0.98, max(0.02, x))
        page.slots[index].cy = min(0.98, max(0.02, y))
        draft = page
    }

    private var backgroundBar: some View {
        let hex = WishLookStore.backgroundHex(appID)
        let colours = ["#FFFFFF", "#FFF4DC", "#F6D1D5", "#EC6AA8", "#F28A2E", "#F2C230", "#CFEFD9", "#8FC8EE", "#E6DCF7", "#1B2A5C", "#111111"]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Background colour").font(.system(size: 12, weight: .semibold))
                ForEach(colours, id: \.self) { item in
                    Button {
                        WishLookStore.setBackgroundHex(item, appID: appID)
                        if var page = draft ?? workingTemplate { recolour(&page, hex: item, save: true); draft = page; refreshPreview() }
                    } label: {
                        Circle().fill(Color(wishHex: item)).frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(item == hex ? WishSimpleTheme.accent : Color.black.opacity(0.2), lineWidth: item == hex ? 2 : 1))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button { importPNGs() } label: { Label("Import PNGs", systemImage: "square.and.arrow.up") }.buttonStyle(SimpleQuietButton())
            }
            Text("Tip: use PNGs with a transparent background so the colour can change. A flat photo keeps its own colours.")
                .font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .top) { Divider().overlay(WishSimpleTheme.line) }
    }

    private func importPNGs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = true
        panel.message = "Choose PNG backgrounds with a transparent background"
        guard panel.runModal() == .OK else { return }
        var last: String?
        for url in panel.urls { if let image = NSImage(contentsOf: url), let file = WishLookStore.add(image, appID: appID) { last = file } }
        lookFiles = WishLookStore.files(appID)
        if let last { pickLook(last) }
    }

    // Layers

    private var layersCard: some View {
        SimpleCard(title: "Layers", trailing: "\(template?.slots.count ?? 0) placed") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add to card").font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                    addButton("Variable", "curlybraces", "variable")
                    addButton("Collection", "list.bullet", "collection")
                    addButton("Function", "function", "function")
                    addButton("Text", "textformat", "text")
                    addButton("Image", "photo", "image")
                    addButton("Logo", "flag", "logo")
                }
                VStack(spacing: 5) {
                    ForEach(template?.slots ?? []) { slot in layerRow(slot) }
                }
                if let page = template, let slot = page.slots.first(where: { $0.id == selectedSlot }) {
                    Divider().overlay(WishSimpleTheme.line)
                    WishLayerProperties(model: model, slotID: slot.id, template: Binding(get: { draft ?? workingTemplate ?? page }, set: { commit($0) }), onRemoved: { selectedSlot = nil })
                } else { Text("Choose a layer to edit it.").font(.system(size: 12)).foregroundStyle(WishSimpleTheme.muted) }
            }
            .padding(16)
        }
    }

    private func addButton(_ title: String, _ symbol: String, _ kind: String) -> some View {
        Button { addLayer(kind) } label: {
            HStack(spacing: 4) { Image(systemName: symbol).font(.system(size: 11)); Text(title).font(.system(size: 11, weight: .semibold)) }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .buttonStyle(SimpleQuietButton())
    }

    private func layerRow(_ slot: TemplateSlot) -> some View {
        let kind = WishLayerKind.of(slot, app: model.app)
        return Button { selectedSlot = slot.id } label: {
            HStack(spacing: 8) {
                Image(systemName: kind.symbol).font(.system(size: 12)).frame(width: 18)
                Text(slot.key).font(.system(size: 12)).lineLimit(1)
                Spacer()
                Text(kind.isDynamic(slot) ? "Dynamic" : "Fixed").font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(kind.isDynamic(slot) ? Color(wishHex: "#F6E4DC") : Color(wishHex: "#E9EFE6")))
                    .foregroundStyle(kind.isDynamic(slot) ? Color(wishHex: "#8B3D2F") : Color(wishHex: "#3A6049"))
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(slot.id == selectedSlot ? Color(wishHex: "#FAF0EB") : WishSimpleTheme.white))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(slot.id == selectedSlot ? Color(wishHex: "#DFBFB0") : WishSimpleTheme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addLayer(_ kind: String) {
        guard var page = draft ?? workingTemplate else { note = "Choose a background first."; return }
        var app = model.app
        func unique(_ base: String) -> String {
            var key = base, number = 1
            while page.slots.contains(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) || app.field(key) != nil { number += 1; key = base + String(number) }
            return key
        }
        let aspect = Double(page.pixelWidth) / Double(max(1, page.pixelHeight))
        var slot: TemplateSlot
        switch kind {
        case "variable":
            let key = unique("variable")
            slot = TemplateSlot(key: key, kind: .text); slot.content = "{{\(key)}}"; slot.sample = "Type here"
            var field = WishField(key: key, label: key.prefix(1).uppercased() + key.dropFirst()); field.placeholder = "Type here"
            app.fields.append(field)
        case "collection":
            let key = unique("choice")
            slot = TemplateSlot(key: key, kind: .text); slot.content = "{{\(key)}}"; slot.sample = "Option A"
            var field = WishField(key: key, label: key.prefix(1).uppercased() + key.dropFirst())
            field.choices = ["Option A", "Option B", "Option C"]
            app.fields.append(field)
        case "function":
            slot = TemplateSlot(key: unique("today"), kind: .text); slot.content = "{=Date}"
            let formatter = DateFormatter(); formatter.dateStyle = .medium
            slot.sample = formatter.string(from: Date())
        case "image":
            slot = TemplateSlot(key: unique("photo"), kind: .image); slot.sample = ""
            slot.w = 0.3; slot.h = 0.3 * aspect
        case "logo":
            slot = TemplateSlot(key: unique("logo"), kind: .logo); slot.w = 0.16; slot.h = 0.16 * aspect
        default:
            slot = TemplateSlot(key: unique("text"), kind: .text); slot.content = "Your text"; slot.sample = "Your text"
        }
        if slot.kind == .text {
            slot.fontName = "Georgia"; slot.fontSize = 0.06; slot.w = 0.7; slot.h = 0.09
            slot.colorHex = page.slots.first(where: { $0.kind == .text })?.colorHex ?? "#26221F"
        }
        slot.cx = 0.5; slot.cy = min(0.9, 0.34 + 0.07 * Double(page.slots.count % 6))
        page.slots.append(slot)
        model.store.updateApp(app)
        selectedSlot = slot.id
        commit(page)
    }

    // MARK: Step 3: activate

    private var activateStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                header("Activate your wish app", "Save this design and name the shortcut you will use to open it.")
                Spacer()
                Button { go(1) } label: { Text("\u{2190} Design") }.buttonStyle(SimpleQuietButton()).padding(.bottom, 24)
                Button { activate() } label: { Label(active ? "Update app" : "Activate app", systemImage: "checkmark") }.buttonStyle(SimplePrimaryButton()).padding(.bottom, 24)
            }
            HStack(alignment: .top, spacing: 19) {
                SimpleCard(title: "Card preview") {
                    VStack(spacing: 0) {
                        ZStack {
                            WishSimpleTheme.stage
                            if let preview { Image(nsImage: preview).resizable().scaledToFit().padding(18) }
                        }
                        .frame(height: 430)
                        HStack { Text(active ? "Active \u{00B7} version \(design?.version ?? 0)" : "Not active yet").font(.system(size: 11)).foregroundStyle(active ? WishSimpleTheme.green : WishSimpleTheme.muted); Spacer() }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                    }
                }
                SimpleCard(title: "App shortcut") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Shortcut word").font(.system(size: 12, weight: .semibold))
                        HStack(spacing: 4) {
                            Text("\\").font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(WishSimpleTheme.accent)
                            TextField("bday", text: $shortcut).textFieldStyle(.roundedBorder).frame(maxWidth: 180)
                        }
                        let ideas = DesignNameIdeas.words(for: model.app.name).filter { !WishAppLink.wordsUsed(byOthersThan: model.app.name).contains($0) }
                        if !ideas.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(ideas.prefix(4), id: \.self) { word in Button("\\" + word) { shortcut = word }.buttonStyle(SimpleQuietButton()).font(.system(.caption, design: .monospaced)) }
                            }
                        }
                        Text(displayShortcut).font(.system(size: 14, design: .monospaced)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color(wishHex: "#F4EFE8")))
                        Text("Type this in any app to make a card with your words.").font(.system(size: 12)).foregroundStyle(WishSimpleTheme.muted)
                        Divider().overlay(WishSimpleTheme.line)
                        Text("What people fill in").font(.system(size: 13, weight: .semibold))
                        let asked = askedFields
                        if asked.isEmpty { Text("Nothing. Every layer is fixed.").font(.system(size: 12)).foregroundStyle(WishSimpleTheme.muted) }
                        ForEach(asked, id: \.id) { field in
                            HStack(spacing: 6) {
                                Image(systemName: (field.choices ?? []).isEmpty ? "curlybraces" : "list.bullet").font(.system(size: 11))
                                Text(field.label).font(.system(size: 12))
                                if !(field.choices ?? []).isEmpty { Text("choose one").font(.system(size: 10)).foregroundStyle(WishSimpleTheme.muted) }
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(width: 340)
            }
        }
    }

    private var displayShortcut: String {
        let word = DesignCommands.sanitize(shortcut)
        let example = model.app.fields.first(where: { askedKeys.contains($0.key.lowercased()) })?.placeholder ?? "Rohit"
        return "\\" + (word.isEmpty ? "bday" : word) + "-" + (example.isEmpty ? "Rohit" : example)
    }

    private var askedKeys: Set<String> {
        var keys = Set<String>()
        for slot in template?.slots ?? [] {
            guard let content = slot.content, let start = content.range(of: "{{"), let end = content.range(of: "}}", range: start.upperBound..<content.endIndex) else { continue }
            keys.insert(String(content[start.upperBound..<end.lowerBound]).lowercased())
        }
        return keys
    }

    private var askedFields: [WishField] { model.app.fields.filter { askedKeys.contains($0.key.lowercased()) } }

    private func activate() {
        guard let id = designID, var current = designs.design(id: id) else { note = "Choose a background first."; return }
        let clean = DesignCommands.sanitize(shortcut)
        guard !clean.isEmpty else { note = "Use one word with letters or numbers only."; return }
        if WishAppLink.wordsUsed(byOthersThan: model.app.name).contains(clean) { note = "\\\(clean) is already used by another app. Choose a different word."; return }
        if let page = draft { TemplateStore.shared.save(page) }
        WishDesignSync.sync(model)
        current.command = clean
        designs.save(current)
        let message = designs.release(id)
        if let released = designs.design(id: id) { shortcut = DesignCommands.register(released) }
        if let target = WishAppLink.builderApp(model) { UserDefaults.standard.set(shortcut, forKey: "ezmeBuilderPrefix." + target.name) }
        model.status = "Activated. Type \\\(shortcut)- and a name in any app."
        note = message.isEmpty ? "Activated. Type \\\(shortcut)- and a name in any app to run it." : message
        model.objectWillChange.send()
    }

    // MARK: Step 4: use

    private var useStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Make a \(heading) card", "Fill in the blanks and the card changes as you type.")
            HStack(alignment: .top, spacing: 19) {
                SimpleCard(title: "Live card") {
                    ZStack {
                        WishSimpleTheme.stage
                        if let page = model.linkedTemplate, let image = model.templateCardImage(page, maxSide: 1000) {
                            Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(18)
                        } else {
                            Text("Choose a background in step 1.").font(.system(size: 13)).foregroundStyle(WishSimpleTheme.muted)
                        }
                    }
                    .frame(height: 470)
                }
                SimpleCard(title: "Fill in") {
                    VStack(alignment: .leading, spacing: 14) {
                        let asked = askedFields
                        if asked.isEmpty { Text("This card has nothing to fill in. Add a variable in Design.").font(.system(size: 12)).foregroundStyle(WishSimpleTheme.muted) }
                        ForEach(asked, id: \.id) { field in WishFieldEditor(model: model, field: field) }
                        Divider().overlay(WishSimpleTheme.line)
                        HStack(spacing: 8) {
                            Button { model.exportPNG() } label: { Label("Download PNG", systemImage: "arrow.down.to.line") }.buttonStyle(SimplePrimaryButton())
                            Button { model.copyImage() } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(SimpleQuietButton())
                            Button { model.shareImage() } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(SimpleQuietButton())
                        }
                        Text("\(model.useCost) credits for each card you save, copy or share.").font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted)
                        if !model.status.isEmpty { Text(model.status).font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted) }
                    }
                    .padding(16)
                }
                .frame(width: 340)
            }
        }
    }
}

// MARK: - Step 1: prompt

private struct PromptStep: View {
    @ObservedObject var model: WishStudioModel
    @Binding var heading: String
    @Binding var lookFiles: [String]
    @Binding var note: String
    @Binding var showPrompt: Bool
    var onPick: (String, Bool) -> Void
    var onDesign: () -> Void
    var onNext: () -> Void
    @State private var example = ""
    @State private var sender = ""
    @State private var brief = ""

    private var appID: String { model.appID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Wish Studio / \(model.app.name)").font(.system(size: 12)).foregroundStyle(WishSimpleTheme.muted)
                Text("Start with a wish").font(WishSimpleTheme.serif(40)).tracking(-1.4)
                Text("Fill in the sample wish, then choose how to get your artwork.").font(.system(size: 14)).foregroundStyle(WishSimpleTheme.muted)
            }
            .padding(.bottom, 24)
            HStack(alignment: .top, spacing: 19) {
                SimpleCard(title: "Your greeting") {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                TextField("Happy Birthday", text: $heading).textFieldStyle(.roundedBorder).font(WishSimpleTheme.serif(20)).frame(maxWidth: 230)
                                TextField("Rohit", text: $example).textFieldStyle(.roundedBorder).font(WishSimpleTheme.serif(20)).frame(maxWidth: 150)
                                    .onChange(of: example) { _, value in UserDefaults.standard.set(value, forKey: "wishExample." + appID) }
                            }
                            HStack(spacing: 8) {
                                Text("From").font(WishSimpleTheme.serif(20))
                                TextField("Jay Jain & Family", text: Binding(get: { sender.hasPrefix("From ") ? String(sender.dropFirst(5)) : sender }, set: { sender = "From " + $0 }))
                                    .textFieldStyle(.roundedBorder).font(WishSimpleTheme.serif(20)).frame(maxWidth: 300)
                                    .onChange(of: sender) { _, value in UserDefaults.standard.set(value, forKey: "wishSender." + appID) }
                            }
                        }
                        Text("The name changes each time you make a card. The heading and sign-off are saved with the template.").font(.system(size: 12)).foregroundStyle(WishSimpleTheme.muted)
                        Text("Artwork prompt").font(.system(size: 12, weight: .semibold))
                        TextEditor(text: $brief).font(.system(size: 13)).frame(height: 96).padding(6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(WishSimpleTheme.white))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WishSimpleTheme.line, lineWidth: 1))
                            .onChange(of: brief) { _, value in UserDefaults.standard.set(value, forKey: "wishBrief." + appID) }
                        HStack(spacing: 8) {
                            Button { onDesign() } label: { Label("Design with KeyDo", systemImage: "wand.and.stars") }.buttonStyle(SimplePrimaryButton())
                            Button { showPrompt = true } label: { Text("Send to ChatGPT") }.buttonStyle(SimpleQuietButton())
                        }
                    }
                    .padding(16)
                    Divider().overlay(WishSimpleTheme.line)
                    HStack {
                        Text("4 transparent PNGs \u{00B7} 2160 \u{00D7} 2160").font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted)
                        Spacer()
                        Button { importPNGs() } label: { Label("Import PNGs", systemImage: "square.and.arrow.up") }.buttonStyle(SimpleQuietButton())
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
                SimpleCard(title: "Artwork options", trailing: "\(lookFiles.count) available") {
                    VStack(alignment: .leading, spacing: 12) {
                        if lookFiles.isEmpty {
                            Text("Nothing yet. Press Design with KeyDo for four starter backgrounds, or send the prompt to ChatGPT and import the PNGs it makes.")
                                .font(.system(size: 12)).foregroundStyle(WishSimpleTheme.muted)
                        } else {
                            LooksStrip(files: lookFiles, selected: WishLookStore.selectedFile(appID), columns: 2) { onPick($0, false) }
                        }
                        Button { onNext() } label: { Text("Continue to design \u{2192}") }.buttonStyle(SimpleQuietButton()).disabled(lookFiles.isEmpty)
                    }
                    .padding(16)
                }
                .frame(width: 380)
            }
        }
        .onAppear {
            example = UserDefaults.standard.string(forKey: "wishExample." + appID) ?? "Rohit"
            sender = UserDefaults.standard.string(forKey: "wishSender." + appID) ?? "From Jay Jain & Family"
            brief = UserDefaults.standard.string(forKey: "wishBrief." + appID) ?? "Elegant artwork with celebratory details around the edges. Leave the centre clear for the recipient's name."
        }
    }

    private func importPNGs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = true
        panel.message = "Choose PNG backgrounds with a transparent background"
        guard panel.runModal() == .OK else { return }
        var last: String?
        for url in panel.urls { if let image = NSImage(contentsOf: url), let file = WishLookStore.add(image, appID: appID) { last = file } }
        lookFiles = WishLookStore.files(appID)
        if let last { onPick(last, false) }
    }
}

// MARK: - Looks strip

struct LooksStrip: View {
    var files: [String]
    var selected: String?
    var columns = 4
    var onSelect: (String) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(Array(files.enumerated()), id: \.element) { index, file in
                Button { onSelect(file) } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5).fill(Color(wishHex: "#FFF4DC"))
                            if let image = WishLookStore.image(file) { Image(nsImage: image).resizable().scaledToFit() }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        Text(index < WishLookMaker.names.count ? WishLookMaker.names[index % WishLookMaker.names.count] : "Look \(index + 1)").font(.system(size: 11)).lineLimit(1)
                    }
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(WishSimpleTheme.white))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(file == selected ? WishSimpleTheme.accent : WishSimpleTheme.line, lineWidth: file == selected ? 2 : 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }
}

// MARK: - The prompt for ChatGPT

struct WishPromptSheet: View {
    let prompt: String
    @Environment(\.dismiss) private var dismiss
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Send to ChatGPT").font(.system(size: 16, weight: .bold)); Spacer(); Button("Close") { dismiss() } }
            TextEditor(text: .constant(prompt)).font(.system(size: 12)).frame(minHeight: 200).padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WishSimpleTheme.line, lineWidth: 1))
            HStack(spacing: 8) {
                Button { send("ChatGPT") } label: { Label("Send to ChatGPT", systemImage: "paperplane.fill") }.buttonStyle(SimplePrimaryButton())
                Button { send("Gemini") } label: { Text("Send to Gemini") }.buttonStyle(SimpleQuietButton())
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(prompt, forType: .string); status = "Prompt copied." } label: { Text("Copy prompt") }.buttonStyle(SimpleQuietButton())
            }
            if !status.isEmpty { Text(status).font(.system(size: 12)).foregroundStyle(WishSimpleTheme.muted) }
            Text("After ChatGPT makes the PNGs, download them and choose Import PNGs here.").font(.system(size: 12)).foregroundStyle(WishSimpleTheme.muted)
        }
        .padding(18).frame(width: 560, height: 400)
    }

    private func send(_ site: String) {
        guard let target = PromptTargets.load().first(where: { $0.name == site }) else { status = "\(site) is not in your Prompt Builder sites. Add it there first."; return }
        NotificationCenter.default.post(name: .keydoSendPrompt, object: PromptDispatchRequest(target: target, prompt: prompt, files: []))
        status = "Opening \(site) in the side panel with your request\u{2026}"
    }
}
