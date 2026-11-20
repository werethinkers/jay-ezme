// Wish Studio, Design mode: the whole App Designer editor on the app's own background. Choose a background, replace it
// any time, add variables, collections, functions, text and picture boxes and drag them into place, choose the app name
// and the word after the backslash, then launch. Colours and looks can be changed by voice before and after.
import SwiftUI
import AppKit

// MARK: - Voice for looks on a template card

/// Colour and style commands ("make the name blue", "all text gold", "bigger", "bold", "font Georgia") for the
/// template an app uses, so the look can always be changed by voice from the Wish Studio bar.
@MainActor enum WishTemplateVoice {
    static func handle(_ raw: String, model: WishStudioModel) -> Bool {
        guard var template = model.linkedTemplate else { return false }
        let text = DesignSpeech.normalize(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        var notes: [String] = []
        var changed = false

        for sentence in DesignVoiceTarget.split(text) {
            var target = model.selected
            var actions: [DesignAction]
            if let hit = DesignVoiceTarget.find(sentence, slots: template.slots) {
                target = hit.slot.key
                actions = hit.rest.isEmpty ? [] : DesignCommand.parse(hit.rest)
            } else {
                actions = DesignCommand.parse(sentence)
            }
            for action in actions {
                if let note = apply(action, to: &template, target: target) { notes.append(note); changed = true }
            }
        }
        guard changed else { return false }
        TemplateStore.shared.save(template)
        model.status = notes.joined(separator: " ")
        model.objectWillChange.send()
        return true
    }

    private static func textIndices(_ template: ImageTemplate, target: String?, all: Bool = false) -> [Int] {
        let texts = template.slots.indices.filter { template.slots[$0].kind == .text }
        if !all, let target, let match = texts.first(where: { template.slots[$0].key.caseInsensitiveCompare(target) == .orderedSame }) { return [match] }
        return texts
    }

    private static func apply(_ action: DesignAction, to template: inout ImageTemplate, target: String?) -> String? {
        switch action {
        case .color(let hex, let part):
            switch part {
            case .text:
                for i in textIndices(template, target: target) { template.slots[i].colorHex = hex }
                return "Text colour changed."
            case .allText:
                for i in textIndices(template, target: target, all: true) { template.slots[i].colorHex = hex }
                return "All text colour changed."
            case .shape:
                let indices = template.slots.indices.filter { target == nil || template.slots[$0].key.caseInsensitiveCompare(target ?? "") == .orderedSame }
                for i in indices { template.slots[i].fillHex = hex }
                return "Shape colour changed."
            case .logo:
                for i in template.slots.indices where template.slots[i].kind == .logo { template.slots[i].colorHex = hex }
                return "Logo colour changed."
            case .page, .theme:
                let result = TemplateBackground.recoloured(template, hex: hex)
                guard let image = result.image else { return result.message }
                TemplateStore.shared.setPicture(image, for: template)
                TemplateBackground.clearCache()
                let dark = NSColor(templateHex: hex).usingColorSpace(.deviceRGB).map { 0.299 * $0.redComponent + 0.587 * $0.greenComponent + 0.114 * $0.blueComponent < 0.45 } ?? false
                for i in textIndices(template, target: nil, all: true) {
                    let text = NSColor(templateHex: template.slots[i].colorHex).usingColorSpace(.deviceRGB)
                    let level = text.map { 0.299 * $0.redComponent + 0.587 * $0.greenComponent + 0.114 * $0.blueComponent } ?? 0.5
                    if dark && level < 0.45 { template.slots[i].colorHex = "#FFFFFF" }
                    if !dark && level > 0.75 { template.slots[i].colorHex = "#1F2A2E" }
                }
                return "Background colour changed."
            }
        case .bold(let on):
            for i in textIndices(template, target: target) { template.slots[i].bold = on }
            return on ? "Bold." : "Not bold."
        case .italic(let on):
            for i in textIndices(template, target: target) { template.slots[i].italic = on }
            return on ? "Italic." : "Not italic."
        case .caps(let on):
            for i in textIndices(template, target: target) { template.slots[i].uppercase = on }
            return on ? "Capitals." : "Normal case."
        case .align(let value):
            for i in textIndices(template, target: target) { template.slots[i].align = value }
            return "Aligned \(value)."
        case .fontSize(let points):
            for i in textIndices(template, target: target) { template.slots[i].fontSize = max(0.004, min(0.4, points / 842)) }
            return "Font size \(Int(points)) pt."
        case .fontScale(let factor):
            for i in textIndices(template, target: target) {
                let base = template.slots[i].fontSize > 0 ? template.slots[i].fontSize : min(0.06, template.slots[i].h * 0.6)
                template.slots[i].fontSize = max(0.004, min(0.4, base * factor))
            }
            return "Font size changed."
        case .font(let name, let all):
            let lower = name.lowercased()
            guard !lower.isEmpty,
                  let found = TemplateFonts.all.first(where: { $0.lowercased() == lower })
                    ?? TemplateFonts.all.first(where: { $0.lowercased().contains(lower) || lower.contains($0.lowercased()) }) else { return nil }
            for i in textIndices(template, target: target, all: all) { template.slots[i].fontName = found }
            return "Font is now \(found)."
        default:
            return nil
        }
    }
}

// MARK: - Design mode

struct WishDesignMode: View {
    @ObservedObject var model: WishStudioModel
    @ObservedObject private var designs = AppDesignStore.shared
    @ObservedObject private var templates = TemplateStore.shared
    @State private var pageIndex = 0
    @State private var message = ""

    private var designID: String? { WishAppLink.designID(model) }
    private var design: AppDesign? { designs.design(id: designID) }

    private var hasBackground: Bool { design != nil }
    private var hasBoxes: Bool {
        guard let design else { return false }
        let slots = design.pages.compactMap { templates.template(id: $0) }.flatMap { $0.slots }
        return slots.contains { $0.kind != .logo } || !design.variables.isEmpty
    }
    private var hasName: Bool { !(design?.appTitle ?? "").isEmpty }
    private var launched: Bool { (design?.version ?? 0) > 0 }

    var body: some View {
        VStack(spacing: 0) {
            stepStrip
            Divider().overlay(WishTheme.line)
            Group {
                if model.designAll {
                    allDesigns
                } else if let id = designID, designs.design(id: id) != nil {
                    AppDesignEditor(designID: id, pageIndex: $pageIndex, onClose: { close() })
                } else {
                    WishChooseBackground(model: model, message: $message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            model.voice.stop()
            AppDesignContext.shared.clips = model.clips
            AppDesignContext.shared.records = model.records
            AppDesignContext.shared.collections = model.collections
        }
    }

    /// The whole App Designer, inside Wish Studio: every design and template, new designs from a picture, bill or agreement.
    private var allDesigns: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Use a design for \(model.app.name):").font(.system(size: 12, weight: .semibold))
                Menu {
                    ForEach(designs.designs) { item in
                        Button(item.appTitle ?? item.name) {
                            TemplateStore.setWishTemplate("design:" + item.id, appID: model.appID)
                            model.designAll = false
                            model.objectWillChange.send()
                        }
                    }
                } label: { Text(design.map { $0.appTitle ?? $0.name } ?? "Choose a design") }
                    .fixedSize()
                Text("Open a design in the list to edit it here, or make a new one.").font(.system(size: 11)).foregroundStyle(WishTheme.muted)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            Divider().overlay(WishTheme.line)
            AppDesignerView(wishDirectory: model.store.directory, clips: model.clips, records: model.records, collections: model.collections)
        }
    }

    private func step(_ number: Int, _ title: String, _ done: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(done ? Color.green : WishTheme.muted)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(done ? WishTheme.ink : WishTheme.muted)
        }
    }

    private var stepStrip: some View {
        HStack(spacing: 16) {
            step(1, "Choose background", hasBackground)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(WishTheme.muted)
            step(2, "Add variables, collections, functions", hasBoxes)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(WishTheme.muted)
            step(3, "Name the app", hasName)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(WishTheme.muted)
            step(4, "Launch", launched)
            Spacer()
            if !message.isEmpty { Text(message).font(.system(size: 11)).foregroundStyle(WishTheme.muted).lineLimit(1) }
            if hasBackground {
                Button { launch() } label: { Label("Launch in Wish Studio", systemImage: "paperplane.fill") }
                    .buttonStyle(.borderedProminent).tint(WishTheme.accent)
                    .help("Publishes this design as the app. Cards, shortcuts and credits then use it.")
            }
            Picker("", selection: $model.designAll) {
                Text("This app").tag(false)
                Text("All designs").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 190)
            Button("Back to card") { close() }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(WishTheme.accentSoft.opacity(0.6))
    }

    private func close() {
        model.designMode = false
        model.objectWillChange.send()
    }

    private func launch() {
        guard let id = designID else { return }
        message = designs.release(id)
        model.status = "Launched. Colours and looks can still be changed by voice."
        close()
    }
}

// MARK: - Step 1: choose a background

struct WishChooseBackground: View {
    @ObservedObject var model: WishStudioModel
    @Binding var message: String
    @ObservedObject private var templates = TemplateStore.shared
    @State private var showIdeas = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose a background for \(model.app.name)").font(.system(size: 20, weight: .semibold))
                    Text("Tip: upload a PNG with a transparent background so you can change the background colour later. A flat photo keeps its own colours.")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(WishTheme.accent)
                    Text("Pick a picture or a template. Then add variables, collections and functions as boxes, drag them where you want them, name the app and launch. You can replace the background any time.")
                        .font(.system(size: 12)).foregroundStyle(WishTheme.muted)
                }
                HStack(spacing: 10) {
                    Button { pickPicture() } label: { Label("Pick a picture…", systemImage: "photo.on.rectangle") }
                        .buttonStyle(.borderedProminent).tint(WishTheme.accent)
                    Button { showIdeas = true } label: { Label("Get backgrounds with ChatGPT", systemImage: "sparkles") }.buttonStyle(.bordered)
                    Button { make(blank: true, landscape: true) } label: { Label("Blank card (wide)", systemImage: "rectangle") }.buttonStyle(.bordered)
                    Button { make(blank: true, landscape: false) } label: { Label("Blank card (tall)", systemImage: "rectangle.portrait") }.buttonStyle(.bordered)
                }
                if !templates.templates.isEmpty {
                    wishCaption("Or use a template background")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(templates.templates.filter { $0.designID == nil }) { template in
                            Button { use(template) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    if let image = templates.basePicture(for: template) {
                                        Image(nsImage: image).resizable().scaledToFit().frame(height: 110).frame(maxWidth: .infinity)
                                            .background(Color(white: 0.95)).clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    Text(template.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WishTheme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(22)
        }
        .sheet(isPresented: $showIdeas) { BackgroundIdeasSheet(appName: model.app.name) }
    }

    private func link(_ design: AppDesign?) {
        guard let design else { message = "Could not start the design."; return }
        TemplateStore.setWishTemplate("design:" + design.id, appID: model.appID)
        model.objectWillChange.send()
    }

    private func pickPicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Tip: choose a PNG with a transparent background so the background colour can be changed later."
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        link(AppDesignStore.shared.newFromPicture(image, name: model.app.name))
    }

    private func make(blank: Bool, landscape: Bool) {
        link(AppDesignStore.shared.newBlank(name: model.app.name, width: landscape ? 1600 : 1000, height: landscape ? 1000 : 1400))
    }

    private func use(_ template: ImageTemplate) {
        guard let image = templates.basePicture(for: template) else { message = "That picture is missing."; return }
        link(AppDesignStore.shared.newFromPicture(image, name: model.app.name))
    }
}
