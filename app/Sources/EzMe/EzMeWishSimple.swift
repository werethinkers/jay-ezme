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
    @State private var showLibrary = false
    @State private var selectedSlot: String?
    @State private var draft: ImageTemplate?
    @State private var preview: NSImage?
    @State private var shortcut = ""
    @State private var lookFiles: [String] = []
    @State private var previewLook: String?
    @State private var phrases = ""

    private var appID: String { model.appID }
    /// The template a card starts with: set in Activate, used in Use. Saved per app.
    private var defaultTemplate: Int {
        let saved = UserDefaults.standard.integer(forKey: "wishDefaultTemplate." + appID)
        return min(max(saved, 1), max(1, lookFiles.count))
    }
    private func setDefaultTemplate(_ number: Int) {
        UserDefaults.standard.set(number, forKey: "wishDefaultTemplate." + appID)
        selectTemplate(number)
        note = "Template \(number) is now the default."
    }
    private var heading: String { UserDefaults.standard.string(forKey: "wishHeading." + appID) ?? model.app.name }
    private var designID: String? { WishAppLink.designID(model) }
    private var design: AppDesign? { designs.design(id: designID) }
    private var workingTemplate: ImageTemplate? { design.flatMap { $0.pages.first }.flatMap { templates.template(id: $0) } }
    private var template: ImageTemplate? { draft ?? workingTemplate }
    private var active: Bool { (design?.version ?? 0) > 0 }
    private var backgroundHex: String { WishLookStore.backgroundHex(appID) }

    private let steps = [("Prompt", "Get your backgrounds"), ("Design", "Place your layers"), ("Activate", "Save your shortcut"), ("Use", "Make a card")]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                rail
                Divider().overlay(WishSimpleTheme.line)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Group {
                            switch step {
                            case 0: PromptStep(model: model, heading: headingBinding, lookFiles: $lookFiles, note: $note, showPrompt: $showPrompt,
                                               onPick: { file, _ in pickLook(file) }, onDesign: { generate() }, onNext: { go(1) }, onSkip: { go(1) }, onLibrary: { showLibrary = true },
                                               onImport: { importPNGs() }, onGreeting: { applyGreeting() })
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
        }
        .background(WishSimpleTheme.paper)
        .foregroundStyle(WishSimpleTheme.ink)
        .onAppear {
            model.simpleVoice = { text in handleVoice(text) }
            guard !started else { return }
            started = true
            lookFiles = WishLookStore.files(appID)
            previewLook = WishLookStore.selectedFile(appID) ?? lookFiles.first
            draft = workingTemplate
            shortcut = design?.command ?? WishAppLink.currentWord(model.app.name)
            phrases = UserDefaults.standard.string(forKey: "wishPhrases." + appID) ?? BuilderPhrases.suggested(for: model.app.name).joined(separator: "\n")
            if designID != nil && !lookFiles.isEmpty { step = 1 }
            refreshPreview()
        }
        .onDisappear { model.simpleVoice = nil }
        .sheet(isPresented: $showPrompt) { WishPromptSheet(prompt: chatGPTPrompt) }
        .sheet(isPresented: $showLibrary) { WishLibrarySheet(appID: appID) { images in useFromLibrary(images) } }
        .onChange(of: model.appID) { _, _ in
            started = false
            step = 0
            draft = nil
        }
    }

    private var headingBinding: Binding<String> {
        Binding(get: { heading }, set: { UserDefaults.standard.set($0, forKey: "wishHeading." + appID); applyGreeting() })
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
            Text(voiceHint).font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted).padding(.horizontal, 10)
            Button { model.simple = false } label: { Label("Advanced tools", systemImage: "slider.horizontal.3").font(.system(size: 12)) }
                .buttonStyle(.plain).foregroundStyle(WishSimpleTheme.muted).padding(10)
                .help("Templates, credits and the full designer.")
        }
        .padding(.top, 28).padding(.horizontal, 14).padding(.bottom, 14)
        .frame(width: 210)
    }

    private var voiceHint: String {
        switch step {
        case 0: return "Say: design with KeyDo, send to ChatGPT, import, next."
        case 1: return "Say: add variable, make it fixed, required, bigger, background pink, move up, next."
        case 2: return "Say: shortcut bday, add voice command make a birthday card, activate the app."
        default: return "Say: name Rohit, template 3, download."
        }
    }

    private func go(_ index: Int) {
        if index >= 1 && designID == nil {
            if lookFiles.isEmpty { generate() } else { createDesign() }
            if designID == nil {
                note = "Could not start the design. Try step 1 again."
                step = 0
                return
            }
        }
        note = ""
        if index >= 2 { syncTemplates() }
        if index >= 3, designID != nil, UserDefaults.standard.integer(forKey: "wishDefaultTemplate." + appID) > 0 { selectTemplate(defaultTemplate) }
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

    // MARK: Templates (looks), numbered 1, 2, 3 ...

    private func generate() {
        let made = WishLookMaker.make()
        guard !made.isEmpty else { note = "Could not draw the backgrounds."; return }
        var first: String?
        for image in made { if let file = WishLookStore.add(image, appID: appID), first == nil { first = file } }
        lookFiles = WishLookStore.files(appID)
        afterLooksChanged(select: first)
        note = "KeyDo drew 4 transparent backgrounds. They are templates 1 to \(lookFiles.count). Pick one, then continue."
    }

    private func useFromLibrary(_ images: [NSImage]) {
        var last: String?
        for image in images { if let file = WishLookStore.add(image, appID: appID) { last = file } }
        lookFiles = WishLookStore.files(appID)
        afterLooksChanged(select: last)
        note = images.isEmpty ? "" : "Added \(images.count) from the library. They are templates \(max(1, lookFiles.count - images.count + 1)) to \(lookFiles.count)."
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
        afterLooksChanged(select: last)
    }

    private func afterLooksChanged(select file: String?) {
        if designID == nil { createDesign() } else { syncTemplates() }
        if let file { pickLook(file) }
        model.objectWillChange.send()
    }

    private func pickLook(_ file: String) {
        WishLookStore.select(file, appID: appID)
        previewLook = file
        if designID == nil { createDesign() }
        refreshPreview()
    }

    private func createDesign() {
        guard let firstFile = lookFiles.first, let image = WishLookStore.image(firstFile) else { return }
        guard let made = AppDesignStore.shared.newFromPicture(image, name: model.app.name) else { note = "Could not start the design."; return }
        TemplateStore.setWishTemplate("design:" + made.id, appID: appID)
        guard var page = TemplateLinks.pages(for: "design:" + made.id).first else { return }
        seedLayers(into: &page)
        TemplateStore.shared.save(page)
        draft = page
        syncTemplates()
        model.objectWillChange.send()
    }

    /// Every look is a template of the app: template 1 is the first look, template 2 the second, and so on. They share the layers.
    private func syncTemplates() {
        guard let id = designID, var current = designs.design(id: id), let mainID = current.pages.first, var main = templates.template(id: mainID) else { return }
        if let page = draft, page.id == mainID { main = page }
        var variants = current.variants ?? []
        for (offset, file) in lookFiles.enumerated() {
            guard let art = WishLookStore.image(file) else { continue }
            let fitted = TemplateImages.limited(art, maxSide: 3200)
            let size = TemplateImages.pixelSize(fitted)
            let base = TemplateBackground.composite(fitted, hex: backgroundHex) ?? fitted
            let layers = main.slots
            func fill(_ page: inout ImageTemplate) {
                page.slots = layers
                page.pixelWidth = Int(size.width)
                page.pixelHeight = Int(size.height)
                TemplateStore.shared.save(page)
                TemplateStore.shared.setOriginal(fitted, for: page)
                TemplateStore.shared.setPicture(base, for: page)
            }
            if offset == 0 {
                fill(&main)
            } else if offset - 1 < variants.count, let variantPage = variants[offset - 1].pages.first, var page = templates.template(id: variantPage) {
                fill(&page)
            } else if var copy = TemplateStore.shared.duplicate(mainID) {
                copy.designID = current.id
                copy.name = "\(current.name) temp\(offset + 1) page 1"
                fill(&copy)
                var variant = DesignVariant(name: "temp\(offset + 1)")
                variant.pages = [copy.id]
                variants.append(variant)
            }
        }
        current.variants = variants
        designs.save(current)
        draft = main
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

    /// Step 1 words reach the design at once: the heading and sign-off are saved as fixed text, the name only as the example.
    private func applyGreeting() {
        model.objectWillChange.send()
        guard var page = draft ?? workingTemplate else { return }
        let sender = UserDefaults.standard.string(forKey: "wishSender." + appID) ?? "From Jay Jain & Family"
        let example = UserDefaults.standard.string(forKey: "wishExample." + appID) ?? "Rohit"
        var changed = false
        for index in page.slots.indices {
            switch page.slots[index].key {
            case "heading": page.slots[index].content = heading; page.slots[index].sample = heading; changed = true
            case "sign-off": page.slots[index].content = sender; page.slots[index].sample = sender; changed = true
            case "name":
                page.slots[index].sample = example
                var app = model.app
                if let at = app.fields.firstIndex(where: { $0.key == "name" }) { app.fields[at].placeholder = example; model.store.updateApp(app) }
                changed = true
            default: break
            }
        }
        if changed { draft = page; TemplateStore.shared.save(page); refreshPreview() }
    }

    private func adjustInk(_ page: inout ImageTemplate, hex: String) {
        let dark = (NSColor(templateHex: hex).usingColorSpace(.deviceRGB)).map { 0.299 * $0.redComponent + 0.587 * $0.greenComponent + 0.114 * $0.blueComponent < 0.45 } ?? false
        for index in page.slots.indices where page.slots[index].kind == .text {
            let level = NSColor(templateHex: page.slots[index].colorHex).usingColorSpace(.deviceRGB).map { 0.299 * $0.redComponent + 0.587 * $0.greenComponent + 0.114 * $0.blueComponent } ?? 0.5
            if dark && level < 0.45 { page.slots[index].colorHex = "#FFFFFF" }
            if !dark && level > 0.75 { page.slots[index].colorHex = "#26221F" }
        }
    }

    private func setBackground(_ hex: String) {
        WishLookStore.setBackgroundHex(hex, appID: appID)
        guard var page = draft ?? workingTemplate else { return }
        adjustInk(&page, hex: hex)
        draft = page
        TemplateStore.shared.save(page)
        refreshPreview()
    }

    func refreshPreview() {
        guard let page = template else { preview = nil; return }
        var base: NSImage?
        if let file = previewLook ?? lookFiles.first, let art = WishLookStore.image(file) {
            base = TemplateBackground.composite(TemplateImages.limited(art, maxSide: 2000), hex: backgroundHex)
        }
        guard let image = base ?? TemplateStore.shared.basePicture(for: page) else { preview = nil; return }
        preview = TemplateRenderer.render(page, base: image, texts: nil, images: [:], useSamples: true, maxSide: 1000)
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
                SimpleCard(title: "Card canvas", trailing: "Template \((lookFiles.firstIndex(of: previewLook ?? "") ?? 0) + 1) of \(max(1, lookFiles.count))") {
                    VStack(spacing: 0) {
                        WishCanvas(template: template, preview: preview, selected: $selectedSlot,
                                   onMove: { id, x, y in moveSlot(id, x, y) }, onEnd: { if let page = draft { commit(page) } })
                        backgroundBar
                        LooksStrip(files: lookFiles, selected: previewLook) { pickLook($0) }
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
        let colours = ["#FFFFFF", "#FFF4DC", "#F6D1D5", "#EC6AA8", "#F28A2E", "#F2C230", "#CFEFD9", "#8FC8EE", "#E6DCF7", "#1B2A5C", "#111111"]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Background colour").font(.system(size: 12, weight: .semibold))
                ForEach(colours, id: \.self) { item in
                    Button { setBackground(item) } label: {
                        Circle().fill(Color(wishHex: item)).frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(item == backgroundHex ? WishSimpleTheme.accent : Color.black.opacity(0.2), lineWidth: item == backgroundHex ? 2 : 1))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button { importPNGs() } label: { Label("Import PNGs", systemImage: "square.and.arrow.up") }.buttonStyle(SimpleQuietButton())
            }
            Text("Tip: use PNGs with a transparent background so the colour can change. A flat photo keeps its own colours. The numbers below are the template numbers.")
                .font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .top) { Divider().overlay(WishSimpleTheme.line) }
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
        let dynamic = kind.isDynamic(slot)
        let must = dynamic && WishLayerOps.isRequired(key: slot.key, model: model)
        return Button { selectedSlot = slot.id } label: {
            HStack(spacing: 8) {
                Image(systemName: kind.symbol).font(.system(size: 12)).frame(width: 18)
                Text(slot.key).font(.system(size: 12)).lineLimit(1)
                Spacer()
                if must { Text("Required").font(.system(size: 10, weight: .semibold)).foregroundStyle(WishSimpleTheme.accent) }
                Text(dynamic ? "Dynamic" : "Fixed").font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(dynamic ? Color(wishHex: "#F6E4DC") : Color(wishHex: "#E9EFE6")))
                    .foregroundStyle(dynamic ? Color(wishHex: "#8B3D2F") : Color(wishHex: "#3A6049"))
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
            var field = WishField(key: key, label: WishLayerOps.label(key)); field.placeholder = "Type here"
            app.fields.append(field)
        case "collection":
            let key = unique("choice")
            slot = TemplateSlot(key: key, kind: .text); slot.content = "{{\(key)}}"; slot.sample = "Option A"
            var field = WishField(key: key, label: WishLayerOps.label(key))
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
                SimpleCard(title: "Card preview", trailing: "\(max(1, lookFiles.count)) templates") {
                    VStack(spacing: 0) {
                        ZStack {
                            WishSimpleTheme.stage
                            if let preview { Image(nsImage: preview).resizable().scaledToFit().padding(18) }
                        }
                        .frame(height: 360)
                        LooksStrip(files: lookFiles, selected: previewLook) { pickLook($0) }
                        HStack { Text(active ? "Active \u{00B7} version \(design?.version ?? 0)" : "Not active yet").font(.system(size: 11)).foregroundStyle(active ? WishSimpleTheme.green : WishSimpleTheme.muted); Spacer() }
                            .padding(.horizontal, 16).padding(.bottom, 10)
                    }
                }
                VStack(spacing: 19) {
                    shortcutCard
                    voiceCard
                }
                .frame(width: 340)
            }
        }
    }

    private var shortcutCard: some View {
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayShortcut).font(.system(size: 14, design: .monospaced))
                    if lookFiles.count > 1 { Text(displayShortcut + "-3").font(.system(size: 14, design: .monospaced)) }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color(wishHex: "#F4EFE8")))
                Text(lookFiles.count > 1 ? "Type this in any app. Add -3 at the end for the third template." : "Type this in any app to make a card with your words.")
                    .font(.system(size: 12)).foregroundStyle(WishSimpleTheme.muted)
                if lookFiles.count > 1 {
                    HStack(spacing: 6) {
                        Text("Default template").font(.system(size: 12, weight: .semibold))
                        ForEach(1...lookFiles.count, id: \.self) { number in
                            Button("\(number)") { setDefaultTemplate(number) }
                                .buttonStyle(SimpleQuietButton())
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(defaultTemplate == number ? WishSimpleTheme.accent : Color.clear, lineWidth: 2))
                        }
                    }
                    Text("The default is the card Use opens with.").font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted)
                }
                Divider().overlay(WishSimpleTheme.line)
                Text("What people fill in").font(.system(size: 13, weight: .semibold))
                let asked = askedFields
                if asked.isEmpty { Text("Nothing. Every layer is fixed.").font(.system(size: 12)).foregroundStyle(WishSimpleTheme.muted) }
                ForEach(asked, id: \.id) { field in
                    HStack(spacing: 6) {
                        Image(systemName: (field.choices ?? []).isEmpty ? "curlybraces" : "list.bullet").font(.system(size: 11))
                        Text(field.label).font(.system(size: 12))
                        if !(field.choices ?? []).isEmpty { Text("choose one").font(.system(size: 10)).foregroundStyle(WishSimpleTheme.muted) }
                        Spacer()
                        Text(isRequired(field.key) ? "Required" : "Optional").font(.system(size: 10, weight: .semibold)).foregroundStyle(isRequired(field.key) ? WishSimpleTheme.accent : WishSimpleTheme.muted)
                    }
                }
            }
            .padding(16)
        }
    }

    private var voiceCard: some View {
        SimpleCard(title: "Voice commands") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Say one of these, then the details, to run the app by voice. One phrase per line.").font(.system(size: 12)).foregroundStyle(WishSimpleTheme.muted)
                TextEditor(text: $phrases).font(.system(size: 12)).frame(height: 78).padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(WishSimpleTheme.white))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WishSimpleTheme.line, lineWidth: 1))
                    .onChange(of: phrases) { _, value in
                        UserDefaults.standard.set(value, forKey: "wishPhrases." + appID)
                        if let target = WishAppLink.builderApp(model) { BuilderPhrases.save(value.components(separatedBy: "\n"), for: target.name) }
                    }
                Button("Use suggestions") { phrases = BuilderPhrases.suggested(for: model.app.name).joined(separator: "\n") }.buttonStyle(SimpleQuietButton())
                Text(active ? "Saved with the app." : "Saved when you press Activate app.").font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted)
            }
            .padding(16)
        }
    }

    private func isRequired(_ key: String) -> Bool { WishLayerOps.isRequired(key: key, model: model) }

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
    private var askedPictures: [TemplateSlot] { (template?.slots ?? []).filter { $0.kind == .image && ($0.content ?? "").isEmpty } }

    private func activate() {
        guard let id = designID, designs.design(id: id) != nil else { note = "Choose a background first."; return }
        let clean = DesignCommands.sanitize(shortcut)
        guard !clean.isEmpty else { note = "Use one word with letters or numbers only."; return }
        if WishAppLink.wordsUsed(byOthersThan: model.app.name).contains(clean) { note = "\\\(clean) is already used by another app. Choose a different word."; return }
        if let page = draft { TemplateStore.shared.save(page) }
        syncTemplates()
        WishDesignSync.sync(model)
        guard var current = designs.design(id: id) else { return }
        current.command = clean
        designs.save(current)
        let message = designs.release(id)
        if let released = designs.design(id: id) { shortcut = DesignCommands.register(released) }
        if let target = WishAppLink.builderApp(model) {
            UserDefaults.standard.set(shortcut, forKey: "ezmeBuilderPrefix." + target.name)
            let lines = phrases.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !lines.isEmpty { BuilderPhrases.save(lines, for: target.name) }
        }
        if designID != nil { selectTemplate(defaultTemplate) }
        model.status = "Activated. Type \\\(shortcut)- and a name in any app."
        note = message.isEmpty ? "Activated. Type \\\(shortcut)- and a name in any app to run it." : message
        model.objectWillChange.send()
    }

    // MARK: Step 4: use

    private var currentTemplateNumber: Int {
        let token = TemplateLinks.token(WishAppLink.link(model)) ?? ""
        if token.hasPrefix("temp"), let number = Int(token.dropFirst(4)) { return number }
        return 1
    }

    private func selectTemplate(_ number: Int) {
        guard let id = designID, number >= 1, number <= max(1, lookFiles.count) else { note = "There is no template \(number)."; return }
        TemplateStore.setWishTemplate(number == 1 ? "design:" + id : "design:" + id + "@temp\(number)", appID: appID)
        note = "Template \(number) is the card now."
        model.objectWillChange.send()
    }

    private var missingRequired: [String] {
        var missing = askedFields.filter { isRequired($0.key) && model.card.value(for: $0.key).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { $0.label }
        for slot in askedPictures where isRequired(slot.key) && !(model.card.media ?? []).contains(where: { $0.placement == slot.key }) { missing.append(slot.key) }
        return missing
    }

    private func chooseMedia(_ key: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the picture for \(key)"
        guard panel.runModal() == .OK, let url = panel.url, let imported = model.store.importMedia(from: url) else { return }
        var list = (model.card.media ?? []).filter { $0.placement != key }
        list.append(WishMedia(file: imported.file, kind: imported.kind, placement: key))
        model.card.media = list
        model.objectWillChange.send()
    }

    private func make(_ action: () -> Void) {
        let missing = missingRequired
        guard missing.isEmpty else { note = "Fill in " + missing.joined(separator: ", ") + " first."; return }
        action()
    }

    private var useStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Make a \(heading) card", "Fill in the blanks and the card changes as you type. Choose the template you want.")
            HStack(alignment: .top, spacing: 19) {
                SimpleCard(title: "Live card", trailing: "Template \(currentTemplateNumber) of \(max(1, lookFiles.count))") {
                    VStack(spacing: 0) {
                        ZStack {
                            WishSimpleTheme.stage
                            if let page = model.linkedTemplate, let image = model.templateCardImage(page, maxSide: 1000) {
                                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(18)
                            } else if let preview {
                                Image(nsImage: preview).resizable().interpolation(.high).scaledToFit().padding(18)
                            } else {
                                Text("Choose a background in step 1.").font(.system(size: 13)).foregroundStyle(WishSimpleTheme.muted)
                            }
                        }
                        .frame(height: 400)
                        if lookFiles.count > 1 {
                            LooksStrip(files: lookFiles, selected: lookFiles.indices.contains(currentTemplateNumber - 1) ? lookFiles[currentTemplateNumber - 1] : nil) { file in
                                if let at = lookFiles.firstIndex(of: file) { selectTemplate(at + 1) }
                            }
                            HStack {
                                Text(currentTemplateNumber == defaultTemplate ? "Template \(currentTemplateNumber) is the default" : "Template \(currentTemplateNumber)").font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted)
                                Spacer()
                                if currentTemplateNumber != defaultTemplate { Button("Make default") { setDefaultTemplate(currentTemplateNumber) }.buttonStyle(SimpleQuietButton()) }
                            }.padding(.horizontal, 14).padding(.bottom, 8)
                        }
                    }
                }
                SimpleCard(title: "Fill in") {
                    VStack(alignment: .leading, spacing: 14) {
                        let asked = askedFields
                        if asked.isEmpty && askedPictures.isEmpty { Text("This card has nothing to fill in. Add a variable in Design.").font(.system(size: 12)).foregroundStyle(WishSimpleTheme.muted) }
                        ForEach(asked, id: \.id) { field in
                            VStack(alignment: .leading, spacing: 2) {
                                if isRequired(field.key) { Text("Required").font(.system(size: 10, weight: .semibold)).foregroundStyle(WishSimpleTheme.accent) }
                                WishFieldEditor(model: model, field: field)
                            }
                        }
                        ForEach(askedPictures) { slot in
                            let has = (model.card.media ?? []).contains { $0.placement == slot.key }
                            HStack {
                                Text(slot.key).font(.system(size: 12, weight: .semibold))
                                if isRequired(slot.key) { Text("Required").font(.system(size: 10, weight: .semibold)).foregroundStyle(WishSimpleTheme.accent) }
                                Spacer()
                                Button { chooseMedia(slot.key) } label: { Label(has ? "Change picture" : "Choose picture", systemImage: "photo") }.buttonStyle(SimpleQuietButton())
                            }
                        }
                        Divider().overlay(WishSimpleTheme.line)
                        HStack(spacing: 8) {
                            Button { make { model.exportPNG() } } label: { Label("Download PNG", systemImage: "arrow.down.to.line") }.buttonStyle(SimplePrimaryButton())
                            Button { make { model.copyImage() } } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(SimpleQuietButton())
                            Button { make { model.shareImage() } } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(SimpleQuietButton())
                        }
                        if !missingRequired.isEmpty { Text("Required: " + missingRequired.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(WishSimpleTheme.accent) }
                        Text("\(model.useCost) credits for each card you save, copy or share.").font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted)
                        if !model.status.isEmpty { Text(model.status).font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted) }
                    }
                    .padding(16)
                }
                .frame(width: 340)
            }
        }
    }

    // MARK: Voice

    private static let colourWords: [(String, String)] = [
        ("white", "#FFFFFF"), ("cream", "#FFF4DC"), ("pink", "#EC6AA8"), ("rose", "#C2415D"), ("red", "#D63B3B"), ("orange", "#F28A2E"),
        ("yellow", "#F2C230"), ("gold", "#E9B949"), ("green", "#3A9A5B"), ("mint", "#CFEFD9"), ("sky", "#8FC8EE"), ("blue", "#2F6FDB"),
        ("navy", "#1B2A5C"), ("lavender", "#E6DCF7"), ("purple", "#7B52B8"), ("brown", "#8B5A2B"), ("grey", "#8A8A8A"), ("gray", "#8A8A8A"), ("black", "#111111")
    ]
    private static let numberWords = ["one": 1, "first": 1, "two": 2, "second": 2, "three": 3, "third": 3, "four": 4, "fourth": 4, "five": 5, "fifth": 5, "six": 6, "sixth": 6]

    private func colour(in text: String) -> String? { Self.colourWords.first { text.contains($0.0) }?.1 }

    private func changeSelected(_ change: (inout TemplateSlot) -> Void) -> Bool {
        guard var page = draft ?? workingTemplate, let id = selectedSlot, let index = page.slots.firstIndex(where: { $0.id == id }) else { note = "Tap a layer first, or say select and its name."; return false }
        change(&page.slots[index])
        commit(page)
        return true
    }

    /// Spoken or typed commands for every step. Returns false only on the last step, so the usual card commands can handle the rest.
    private func handleVoice(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,!?"))).lowercased()
        guard !text.isEmpty else { return true }
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        func after(_ words: String...) -> String? {
            for word in words { if let range = text.range(of: word + " ") { return String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces) } }
            return nil
        }
        let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        func originalAfter(_ words: String...) -> String? {
            for word in words { if let range = original.lowercased().range(of: word + " ") { return String(original[range.upperBound...]).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".,!?"))) } }
            return nil
        }
        // Anywhere
        if has("design with keydo", "make backgrounds", "draw backgrounds", "make the backgrounds") { step = 0; generate(); return true }
        if has("chatgpt", "chat gpt", "gemini") { step = 0; showPrompt = true; return true }
        if text == "import" || has("import png", "import backgrounds") { importPNGs(); return true }
        if has("activate") || text == "launch" || has("launch the app") { go(2); activate(); return true }
        if let phrase = originalAfter("add voice command", "add voice phrase", "add phrase") {
            go(2)
            phrases = (phrases.isEmpty ? "" : phrases + "\n") + phrase
            note = "Voice phrase added. It is saved when you activate."
            return true
        }
        if let word = after("shortcut", "command word", "set the word", "call the app", "word") , step == 2 || has("shortcut") {
            shortcut = DesignCommands.sanitize(word)
            go(2); note = "Shortcut is \\\(shortcut)."
            return true
        }
        // Steps
        let stepWords: [(String, Int)] = [("prompt", 0), ("start", 0), ("design", 1), ("activate", 2), ("live card", 3), ("make a card", 3), ("use", 3)]
        if text == "next" || text == "continue" { go(min(3, step + 1)); return true }
        if text == "back" || text == "previous" { go(max(0, step - 1)); return true }
        if text.hasPrefix("go to ") || text.hasPrefix("open ") || text.hasPrefix("show ") {
            if let target = stepWords.first(where: { text.contains($0.0) }) { go(target.1); return true }
        }
        // Greeting words in step 1
        if step == 0 {
            if let value = originalAfter("heading", "title") { headingBinding.wrappedValue = value; note = "Heading saved."; return true }
            if let value = originalAfter("sign off", "signoff", "from") {
                UserDefaults.standard.set("From " + value, forKey: "wishSender." + appID); applyGreeting(); note = "Sign-off saved."; return true
            }
            if let value = originalAfter("example", "example name") { UserDefaults.standard.set(value, forKey: "wishExample." + appID); applyGreeting(); note = "Example name saved."; return true }
        }
        if step == 3 {
            if has("download", "save the card", "save card", "save png") { make { model.exportPNG() }; return true }
            if text == "copy" || has("copy the card", "copy card", "copy image") { make { model.copyImage() }; return true }
            if text == "share" || has("share the card", "share card") { make { model.shareImage() }; return true }
            if has("template", "number") {
                if let digits = text.split(whereSeparator: { !$0.isNumber }).first, let number = Int(digits) { selectTemplate(number); return true }
                if let number = Self.numberWords.first(where: { text.contains($0.key) })?.value { selectTemplate(number); return true }
            }
            return false
        }
        if step == 2 {
            note = "Say: shortcut and a word, add voice command and a phrase, or activate the app."
            return true
        }
        if step == 0 {
            note = "Say: design with KeyDo, send to ChatGPT, import, or next."
            return true
        }
        // Design step
        if has("add") {
            let kinds: [(String, String)] = [("variable", "variable"), ("collection", "collection"), ("function", "function"), ("text", "text"), ("image", "image"), ("picture", "image"), ("photo", "image"), ("logo", "logo")]
            if let kind = kinds.first(where: { text.contains($0.0) }) { addLayer(kind.1); note = "Added a \(kind.0). Drag it into place."; return true }
        }
        if text.hasPrefix("select ") || text.hasPrefix("choose layer "), let name = after("select", "choose layer"), let page = draft ?? workingTemplate,
           let slot = page.slots.first(where: { $0.key.lowercased().contains(name) || name.contains($0.key.lowercased()) }) {
            selectedSlot = slot.id; note = "Selected \(slot.key)."; return true
        }
        if has("remove layer", "delete layer", "remove it", "delete it") {
            guard var page = draft ?? workingTemplate, let id = selectedSlot else { note = "Tap a layer first."; return true }
            WishLayerOps.remove(&page, slotID: id, model: model); selectedSlot = nil; commit(page); note = "Removed."; return true
        }
        if has("make it fixed", "set fixed", "fixed") || has("make it dynamic", "set dynamic", "dynamic") {
            let toDynamic = has("dynamic")
            guard var page = draft ?? workingTemplate, let id = selectedSlot else { note = "Tap a layer first."; return true }
            if toDynamic { WishLayerOps.makeDynamic(&page, slotID: id, model: model) } else { WishLayerOps.makeFixed(&page, slotID: id, model: model) }
            commit(page); note = toDynamic ? "Dynamic: asked each time." : "Fixed: saved with the template."; return true
        }
        if has("not required", "optional") || has("required", "mandatory") {
            guard let id = selectedSlot, let key = (draft ?? workingTemplate)?.slots.first(where: { $0.id == id })?.key else { note = "Tap a layer first."; return true }
            let on = !has("not required", "optional")
            WishLayerOps.setRequired(on, key: key, model: model); model.objectWillChange.send()
            note = on ? "\(key) is required." : "\(key) is optional."; return true
        }
        if let name = originalAfter("rename to", "rename it to", "call it") {
            guard var page = draft ?? workingTemplate, let id = selectedSlot else { note = "Tap a layer first."; return true }
            if let error = WishLayerOps.rename(&page, slotID: id, to: name, model: model) { note = error } else { commit(page); note = "Renamed." }
            return true
        }
        if text.hasPrefix("background ") || has("background colour", "background color"), let hex = colour(in: text) {
            setBackground(hex); note = "Background changed."; return true
        }
        if has("bigger", "larger", "increase", "grow") { _ = changeSelected { $0.fontSize = min(0.2, ($0.fontSize > 0 ? $0.fontSize : 0.06) * 1.18) }; return true }
        if has("smaller", "decrease", "reduce", "shrink") { _ = changeSelected { $0.fontSize = max(0.015, ($0.fontSize > 0 ? $0.fontSize : 0.06) / 1.18) }; return true }
        if has("bold") { _ = changeSelected { $0.bold = !has("not bold", "unbold") }; return true }
        if has("colour", "color", "make it"), let hex = colour(in: text) { _ = changeSelected { $0.colorHex = hex }; return true }
        if has("move") || text == "center" || text == "centre" {
            let delta: Double = 0.04
            _ = changeSelected { slot in
                if text == "center" || text == "centre" { slot.cx = 0.5; return }
                if text.contains("up") { slot.cy = max(0.02, slot.cy - delta) }
                if text.contains("down") { slot.cy = min(0.98, slot.cy + delta) }
                if text.contains("left") { slot.cx = max(0.02, slot.cx - delta) }
                if text.contains("right") { slot.cx = min(0.98, slot.cx + delta) }
            }
            return true
        }
        note = "I did not catch that. Try: add variable, make it fixed, required, bigger, background pink, move up, next."
        return true
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
    var onSkip: () -> Void
    var onLibrary: () -> Void
    var onImport: () -> Void
    var onGreeting: () -> Void
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
                                    .onChange(of: example) { _, value in UserDefaults.standard.set(value, forKey: "wishExample." + appID); onGreeting() }
                            }
                            HStack(spacing: 8) {
                                Text("From").font(WishSimpleTheme.serif(20))
                                TextField("Jay Jain & Family", text: Binding(get: { sender.hasPrefix("From ") ? String(sender.dropFirst(5)) : sender }, set: { sender = "From " + $0 }))
                                    .textFieldStyle(.roundedBorder).font(WishSimpleTheme.serif(20)).frame(maxWidth: 300)
                                    .onChange(of: sender) { _, value in UserDefaults.standard.set(value, forKey: "wishSender." + appID); onGreeting() }
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
                        Button { onSkip() } label: { Label("Skip: use the 4 default designs", systemImage: "forward.end") }.buttonStyle(SimpleQuietButton())
                    }
                    .padding(16)
                    Divider().overlay(WishSimpleTheme.line)
                    HStack {
                        Text("4 transparent PNGs \u{00B7} 2160 \u{00D7} 2160").font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted)
                        Spacer()
                        Button { onLibrary() } label: { Label("Library", systemImage: "photo.stack") }.buttonStyle(SimpleQuietButton())
                        Button { onImport() } label: { Label("Import PNGs", systemImage: "square.and.arrow.up") }.buttonStyle(SimpleQuietButton())
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
                        Text("\(index + 1)").font(.system(size: 12, weight: .semibold)).lineLimit(1)
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
