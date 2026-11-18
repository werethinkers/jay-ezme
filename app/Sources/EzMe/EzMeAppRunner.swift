// Published AppDesigner apps: one form (or one sentence) asks for everything, then the app makes its file.
// Also the ready-made layouts (greeting maker, NDA, catalog) and the strip of apps on the Home page.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - The questions an app asks

struct DesignField: Identifiable, Hashable {
    enum Kind { case text, long, image, choice, wish }
    var key: String
    var label: String
    var kind: Kind
    var collection: String? = nil
    var defaultValue: String = ""
    /// The category of the collection (subcategory) this box takes its choices from.
    var category: String? = nil
    var id: String { key }
}

enum DesignFields {
    private static let tokenRegex = try? NSRegularExpression(pattern: "\\{\\{([^}]+)\\}\\}")

    private static func label(_ key: String) -> String {
        let spaced = key.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    /// A box that takes its choice from a subcategory is named after it ("HBD Wish"), not after its variable.
    private static func pickLabel(_ collection: String, _ variable: String) -> String {
        TemplateFill.normal(variable) == TemplateFill.normal(collection) ? collection : "\(collection) \u{00B7} \(label(variable))"
    }

    /// Everything the pages need from the person: variables used in boxes, boxes with no fixed content, and variables
    /// that were declared. A variable used as {{@Customers/$customer/email}} becomes a pick-list of that collection.
    @MainActor static func fields(pages: [ImageTemplate], variables: [String: String]) -> [DesignField] {
        var result: [DesignField] = []
        var seen = Set<String>()
        func add(_ field: DesignField) {
            let normal = TemplateFill.normal(field.key)
            guard !normal.isEmpty, !seen.contains(normal) else { return }
            seen.insert(normal)
            result.append(field)
        }
        func defaultFor(_ key: String) -> String {
            variables.first(where: { TemplateFill.normal($0.key) == TemplateFill.normal(key) })?.value ?? ""
        }
        for page in pages {
            for slot in page.slots {
                guard let content = slot.content, !content.isEmpty, let regex = tokenRegex else { continue }
                let ns = content as NSString
                for match in regex.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
                    let inner = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                    if inner.lowercased().hasPrefix("shortcut:") { continue }
                    if let pick = WishPick.parse(inner) {
                        add(DesignField(key: pick.variable, label: pickLabel(pick.collection, pick.variable), kind: .wish, collection: pick.collection, defaultValue: defaultFor(pick.variable), category: AppDesignContext.shared.category(of: pick.collection)))
                        continue
                    }
                    if inner.hasPrefix("@") {
                        let parts = String(inner.dropFirst()).split(separator: "/", omittingEmptySubsequences: false).map { String($0) }
                        if parts.count >= 2, parts[1].hasPrefix("$") {
                            let name = String(parts[1].dropFirst())
                            add(DesignField(key: name, label: pickLabel(parts[0], name), kind: .choice, collection: parts[0], defaultValue: defaultFor(name), category: AppDesignContext.shared.category(of: parts[0])))
                        }
                        continue
                    }
                    let value = defaultFor(inner)
                    add(DesignField(key: inner, label: label(inner), kind: value.count > 80 || value.contains("\n") ? .long : .text, defaultValue: value))
                }
            }
        }
        for page in pages {
            for slot in page.slots where slot.kind != .logo && (slot.content ?? "").isEmpty {
                add(DesignField(key: slot.key, label: label(slot.key), kind: slot.kind == .image ? .image : .text, collection: slot.kind == .image ? MediaFinder.collectionNamed(slot.key) : nil, defaultValue: defaultFor(slot.key), category: slot.kind == .image ? MediaFinder.collectionNamed(slot.key).flatMap { AppDesignContext.shared.category(of: $0) } : nil))
            }
        }
        for key in variables.keys.sorted() {
            let value = variables[key] ?? ""
            add(DesignField(key: key, label: label(key), kind: value.count > 80 || value.contains("\n") ? .long : .text, defaultValue: value))
        }
        return result
    }

    @MainActor static func fields(for design: AppDesign) -> [DesignField] {
        fields(pages: AppDesignStore.shared.activePages(design), variables: design.variables)
    }
}

/// One question of the form.
struct DesignFieldRow: View {
    var field: DesignField
    @Binding var text: String
    /// What an empty box will use instead: the value typed last time, or the app's starting value.
    var fallback: String = ""
    @State private var chooserOpen = false

    /// Text boxes with nothing to fall back on are the ones the person has to fill.
    private var needsValue: Bool {
        (field.kind == .text || field.kind == .long) && fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(field.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(FormVoiceInk.main)
                if needsValue {
                    Text("* Required").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(red: 0.74, green: 0.18, blue: 0.1))
                } else if field.kind == .image && field.collection == nil {
                    Text("Optional").font(.system(size: 10)).foregroundStyle(Butter.cocoa.opacity(0.6))
                }
                if let category = field.category, !category.isEmpty {
                    Text(category).font(.system(size: 9, weight: .semibold)).foregroundStyle(Butter.cocoa.opacity(0.8))
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Butter.honey.opacity(0.35)))
                }
            }
            switch field.kind {
            case .text:
                TextField(fallback.isEmpty ? field.label : fallback, text: $text).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(field.label).help(field.label)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(needsValue && text.trimmingCharacters(in: .whitespaces).isEmpty ? Color.red.opacity(0.55) : Color.clear, lineWidth: 1))
                if text.trimmingCharacters(in: .whitespaces).isEmpty && !fallback.isEmpty {
                    Text("Left empty, it uses \u{201C}\(String(fallback.prefix(40)))\u{201D}").font(.system(size: 10)).foregroundStyle(Butter.cocoa.opacity(0.6))
                }
            case .long:
                TextEditor(text: $text).font(.system(size: 13)).foregroundStyle(Butter.cocoa).scrollContentBackground(.hidden).frame(minHeight: 70, maxHeight: 130).padding(4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white)).overlay(RoundedRectangle(cornerRadius: 8).stroke(needsValue && text.trimmingCharacters(in: .whitespaces).isEmpty ? Color.red.opacity(0.55) : Butter.honey, lineWidth: 1))
                    .accessibilityLabel(field.label).help(field.label)
                if text.trimmingCharacters(in: .whitespaces).isEmpty && !fallback.isEmpty {
                    Text("Left empty, it uses \u{201C}\(String(fallback.replacingOccurrences(of: "\n", with: " ").prefix(40)))\u{201D}").font(.system(size: 10)).foregroundStyle(Butter.cocoa.opacity(0.6))
                }
            case .image:
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField(field.label + " (media name, words about it, or a file)", text: $text).textFieldStyle(.roundedBorder)
                            .accessibilityLabel(field.label).help(field.label)
                            .onSubmit {
                                if celebrationMedia(text, clips: AppDesignContext.shared.clips) == nil, let found = MediaFinder.best(text, in: field.collection) { text = found.key }
                            }
                        if let collection = field.collection {
                            Button { chooserOpen = true } label: { Label("Choose", systemImage: "photo.on.rectangle") }.buttonStyle(.bordered).controlSize(.small)
                                .popover(isPresented: $chooserOpen, arrowEdge: .bottom) {
                                    MediaChooserList(collection: collection) { clip in text = clip.key; chooserOpen = false }.frame(width: 360, height: 440)
                                }
                        }
                        SourcePickerButton(title: "Shortcuts", symbol: "bolt", mediaOnly: true) { text = $0 }.buttonStyle(.bordered).controlSize(.small)
                        Button { choose() } label: { Label("File", systemImage: "photo") }.buttonStyle(.bordered).controlSize(.small)
                    }
                    MediaSuggestions(query: text, collection: field.collection) { clip in text = clip.key }
                }
            case .wish:
                WishChooserRow(field: field, text: $text)
            case .choice:
                RecordChooserRow(field: field, text: $text)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose a picture or video"
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { text = url.path }
    }
}

// MARK: - Running an app

struct AppDesignRunView: View {
    var designID: String
    var onClose: (() -> Void)? = nil
    /// A sentence to fill the form from as soon as it opens (from the Home command box or a spoken command).
    var startPrompt: String? = nil
    /// Boxes to start with filled in (from a backslash command that was missing something).
    var startValues: [String: String] = [:]
    @ObservedObject private var designs = AppDesignStore.shared
    @StateObject private var guide = DesignVoiceGuide()
    @State private var values: [String: String] = [:]
    @State private var prompt = ""
    @State private var preview: NSImage?
    @State private var result: URL?
    @State private var message = ""
    @State private var busy = false
    @State private var aiBusy = false
    /// "" is the default template; otherwise temp2, a template's name, or tempr for a random one.
    @State private var templateName = ""
    @State private var lastRandom = ""

    private var design: AppDesign? { designs.design(id: designID) }
    /// The template the preview shows: the one chosen, or the one a random pick landed on.
    private var previewToken: String { templateName == "tempr" ? lastRandom : templateName }
    private var fields: [DesignField] {
        guard let design else { return [] }
        return DesignFields.fields(pages: AppDesignStore.shared.activePages(design, token: previewToken), variables: design.variables)
    }
    private var format: DesignFormat { DesignFormat.from(design?.outputFormat) ?? ((design.map { AppDesignStore.shared.activePages($0).count } ?? 1) > 1 ? .pdf : .png) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ScrollView { form.padding(18) }.frame(maxWidth: .infinity)
                Divider()
                previewColumn.frame(width: 380)
            }
        }
        .background(Butter.butter)
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        .onAppear {
            DesignTemplates.ensure(designID)
            guide.fields = { fields }
            guide.values = { values }
            guide.setValue = { key, value in values[key] = value }
            guide.make = { make() }
            // Start from what was typed last time, then the first item of each collection, then anything given with the command.
            if let design {
                let remembered = DesignMemory.last(design.id)
                for field in fields { if let last = remembered[TemplateFill.normal(field.key)], !last.isEmpty { values[field.key] = last } }
            }
            DesignDefaults.fill(fields, into: &values)
            for (key, value) in startValues { values[key] = value }
            refreshPreview()
            if let startPrompt, !startPrompt.trimmingCharacters(in: .whitespaces).isEmpty, prompt.isEmpty {
                prompt = startPrompt
                applyVoice(startPrompt)
            }
        }
        .onDisappear { guide.stop() }
        .onChange(of: values) { _, _ in refreshPreview() }
        .onChange(of: templateName) { _, _ in refreshPreview() }
    }

    /// Fills what the sentence names; falls back to the AI, then to the first empty field.
    private func applyVoice(_ sentence: String) {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if DesignVoiceFill.isMakeCommand(text) { make(); return }
        let found = DesignVoiceFill.parse(text, fields: fields)
        if !found.isEmpty {
            for (key, value) in found { values[key] = value }
            let names = fields.filter { found[$0.key] != nil }.map { $0.label }
            message = "Filled " + names.joined(separator: ", ") + "."
            return
        }
        prompt = prompt.isEmpty ? text : prompt + " " + text
        let profiles = AIModelProfileStore.load()
        let selectedID = UserDefaults.standard.string(forKey: "ezmeSelectedAIModelProfile") ?? UserDefaults.standard.string(forKey: "ezmeCollectionSelectedProfile") ?? CollectionAIModelProfile.starter.id
        let profile = profiles.first(where: { $0.id == selectedID }) ?? .starter
        if !(KeyStore.load(account: profile.keyAccount) ?? "").isEmpty && text.split(separator: " ").count > 3 {
            fillFromPrompt()
        } else if let field = DesignVoiceFill.firstEmpty(fields, values: values) {
            values[field.key] = text
            message = "Put that in \(field.label)."
        } else {
            message = "I did not catch a field name. Say the field name first, like \u{201C}\(fields.first?.label ?? "name") Rahul\u{201D}."
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let logo = keyDoIconImage() {
                Image(nsImage: logo).resizable().scaledToFit().frame(width: 40, height: 40)
                    .padding(4).background(RoundedRectangle(cornerRadius: 11).fill(Color(red: 0.973, green: 0.937, blue: 0.882)))
            } else {
                Image(systemName: format.symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Butter.coral, in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(design?.appTitle ?? design?.name ?? "App").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 0.114, green: 0.125, blue: 0.133))
                Text("Fill what you like and press Make. Anything left empty uses the last value or a ready one, and you get \(format.title).")
                    .font(.system(size: 12)).foregroundStyle(Butter.cocoa.opacity(0.75))
            }
            Spacer()
            if let onClose { Button("Close") { onClose() }.buttonStyle(.bordered).tint(Butter.cocoa) }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Color(red: 0.973, green: 0.937, blue: 0.882))
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                DesignVoiceBar(guide: guide, voice: guide.voice)
                Label("Say it in one go (optional)", systemImage: "sparkles").font(.system(size: 12, weight: .bold)).foregroundStyle(FormVoiceInk.main)
                TextEditor(text: $prompt).font(.system(size: 13)).frame(height: 64).padding(4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Butter.honey, lineWidth: 1))
                HStack {
                    Button { fillFromPrompt() } label: { Label(aiBusy ? "Reading\u{2026}" : "Fill the form from this", systemImage: "wand.and.stars") }
                        .buttonStyle(.bordered).disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || aiBusy)
                }
                .controlSize(.small)
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Butter.cream))

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Details").font(.system(size: 12, weight: .bold)).foregroundStyle(FormVoiceInk.main)
                    Spacer()
                    if let design {
                        let items = DesignTemplates.items(design)
                        Text("Template").font(.system(size: 11)).foregroundStyle(Butter.cocoa.opacity(0.75))
                        Picker("Template", selection: $templateName) {
                            ForEach(items) { item in Text(item.name + (item.isDefault ? " (default)" : "")).tag(item.isDefault ? "" : item.name) }
                            Text("Random (tempr)").tag("tempr")
                        }
                        .labelsHidden().frame(width: 150).help("temp1 is the default. In a command, add -temp2, -temp3 or -tempr.")
                    }
                }
                Text("Red * marks what only you can fill. Everything else already has a value, so you can just press Make.")
                    .font(.system(size: 11)).foregroundStyle(Butter.cocoa.opacity(0.7))
                if fields.isEmpty { Text("This app needs nothing from you. Press Make.").font(.system(size: 12)).foregroundStyle(.secondary) }
                ForEach(fields) { field in
                    DesignFieldRow(field: field, text: Binding(get: { values[field.key] ?? "" }, set: { values[field.key] = $0 }),
                                   fallback: design.map { DesignMemory.fallback($0.id, field: field) } ?? field.defaultValue)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(guide.active && guide.current?.key == field.key ? Butter.coral : Color.clear, lineWidth: 2))
                        .simultaneousGesture(TapGesture().onEnded { guide.select(field.key) })
                }
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.7)))

            HStack {
                Button { make() } label: { Label(busy ? "Making\u{2026}" : "Make \(format.title)", systemImage: "sparkle") }
                    .buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.large).disabled(busy)
                if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(Butter.cocoa.opacity(0.8)) }
            }
        }
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PREVIEW").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
            ZStack {
                Rectangle().fill(Color(white: 0.95))
                if let preview { Image(nsImage: preview).resizable().interpolation(.high).scaledToFit().padding(6) }
            }
            .frame(maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 10))
            if let result {
                VStack(alignment: .leading, spacing: 6) {
                    Label(result.lastPathComponent, systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.green).lineLimit(1)
                    HStack {
                        Button("Save as\u{2026}") { saveAs(result) }
                        Button("Copy") { copy(result) }
                        ShareLink(item: result) { Text("Share") }
                        Button("Open") { NSWorkspace.shared.open(result) }
                        Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([result]) }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .padding(14)
    }

    private func refreshPreview() {
        guard let design, let first = AppDesignStore.shared.activePages(design, token: previewToken).first, let base = TemplateStore.shared.basePicture(for: first) else { preview = nil; return }
        let merged = DesignFill.merge(design.variables, values.filter { !$0.value.isEmpty })
        let made = TemplateFill.resolved(first, values: merged, clips: AppDesignContext.shared.clips)
        preview = TemplateRenderer.render(first, base: base, texts: made.texts, images: made.images, useSamples: true, maxSide: 900)
    }

    private func make() {
        guard let design else { return }
        busy = true
        message = ""
        let chosen = templateName == "tempr" ? (DesignTemplates.items(design).randomElement()?.name ?? "") : templateName
        if templateName == "tempr" { lastRandom = chosen }
        let directory = TemplateStore.shared.directory.appendingPathComponent("Outputs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safe = design.name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let stem = (safe.isEmpty ? "App" : safe) + "-" + String(UUID().uuidString.prefix(5))
        do {
            let file = try DesignFill.renderFile(link: DesignTemplates.link("design:" + design.id, token: chosen), values: values, clips: AppDesignContext.shared.clips, directory: directory, stem: stem)
            result = file
            let blank = fields.filter { $0.kind == .text || $0.kind == .long }.filter { (values[$0.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty && DesignMemory.fallback(design.id, field: $0).isEmpty }.map { $0.label }
            message = "Ready" + (chosen.isEmpty ? "" : " (\(chosen))") + "." + (blank.isEmpty ? "" : " Left blank: " + blank.joined(separator: ", ") + ".")
        } catch {
            message = error.localizedDescription
        }
        busy = false
    }

    private func saveAs(_ file: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? FileManager.default.removeItem(at: destination)
        do { try FileManager.default.copyItem(at: file, to: destination); message = "Saved \(destination.lastPathComponent)." }
        catch { message = "Could not save: \(error.localizedDescription)" }
    }

    private func copy(_ file: URL) {
        NSPasteboard.general.clearContents()
        if let image = NSImage(contentsOf: file), ["png", "gif"].contains(file.pathExtension.lowercased()) {
            NSPasteboard.general.writeObjects([image])
        } else {
            NSPasteboard.general.writeObjects([file as NSURL])
        }
        message = "Copied."
    }

    private func fillFromPrompt() {
        let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        let profiles = AIModelProfileStore.load()
        let selectedID = UserDefaults.standard.string(forKey: "ezmeSelectedAIModelProfile") ?? UserDefaults.standard.string(forKey: "ezmeCollectionSelectedProfile") ?? CollectionAIModelProfile.starter.id
        let profile = profiles.first(where: { $0.id == selectedID }) ?? .starter
        let key = KeyStore.load(account: profile.keyAccount) ?? ""
        guard !key.isEmpty else { message = "Add an AI key in Setup to fill the form from a sentence. You can still fill it by hand."; return }
        let askable = fields.filter { $0.kind != .image }
        var lines: [String] = []
        for field in askable {
            var line = "\(field.key): \(field.label)"
            if field.kind == .choice, let collection = field.collection {
                let options = AppDesignContext.shared.records.filter { $0.collection.caseInsensitiveCompare(collection) == .orderedSame }.prefix(40).map { $0.alias.isEmpty ? $0.name : $0.alias }
                line += " (choose one of: " + options.joined(separator: ", ") + ")"
            }
            if field.kind == .wish, let collection = field.collection {
                let options = WishPick.clips(in: collection).prefix(40).map { "\($0.key) = " + String($0.text.prefix(60)).replacingOccurrences(of: "\n", with: " ") }
                line += " (reply with the shortcut key that fits best: " + options.joined(separator: "; ") + ")"
            }
            lines.append(line)
        }
        let question = "Fill in a form from the request. Reply with only one JSON object whose keys are the field keys below and whose values are short strings. Leave out fields the request does not mention.\n\nFields:\n" + lines.joined(separator: "\n") + "\n\nRequest:\n" + request
        aiBusy = true
        message = ""
        Task {
            defer { aiBusy = false }
            do {
                let reply = try await SharedAIClient.generate(profile: profile, key: key, prompt: question, maxTokens: 900)
                guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
                      let data = String(reply[start...end]).data(using: .utf8),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { message = "I could not read the answer. Please fill the form by hand."; return }
                var filled = 0
                for field in askable {
                    if let value = object[field.key] { values[field.key] = "\(value)"; filled += 1 }
                }
                message = filled == 0 ? "Nothing matched. Please fill the form by hand." : "Filled \(filled) field\(filled == 1 ? "" : "s"). Check them, then press Make."
            } catch {
                message = "The AI could not answer: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Apps on the Home page

struct PublishedAppsStrip: View {
    var clips: [Clip]
    var records: [CollectionRecord]
    var onOpenDesigner: () -> Void
    @ObservedObject private var designs = AppDesignStore.shared
    @State private var running: String?

    private var published: [AppDesign] { designs.designs.filter { $0.version > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Your apps", systemImage: "paintpalette.fill").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Butter.cocoa)
                Spacer()
                Button { onOpenDesigner() } label: { Label("AppDesigner", systemImage: "wand.and.stars") }.buttonStyle(.bordered).controlSize(.small)
            }
            LaunchBox()
            if published.isEmpty {
                Text("Design an app (greeting maker, NDA, catalog and more) in AppDesigner and publish it. It appears here to launch in one click.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 10)], spacing: 10) {
                    ForEach(published) { design in
                        let format = DesignFormat.from(design.outputFormat) ?? (design.pages.count > 1 ? .pdf : .png)
                        Button { running = design.id } label: {
                            HStack(spacing: 10) {
                                Image(systemName: format.symbol).foregroundStyle(.white).frame(width: 34, height: 34).background(Butter.coral, in: RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(design.appTitle ?? design.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Butter.cocoa).lineLimit(1)
                                    Text(format.title).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Butter.honey.opacity(0.7), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Butter.cream))
        .onAppear { sync() }
        .sheet(item: Binding(get: { running.map { RunID(id: $0) } }, set: { running = $0?.id })) { item in
            AppDesignRunView(designID: item.id, onClose: { running = nil }).frame(minWidth: 940, minHeight: 640)
        }
    }

    private func sync() {
        if !clips.isEmpty { AppDesignContext.shared.clips = clips }
        if !records.isEmpty { AppDesignContext.shared.records = records }
    }
}

private struct RunID: Identifiable { let id: String }

// MARK: - Ready-made layouts

enum StarterLayouts {
    enum Kind: String, CaseIterable, Identifiable {
        case greeting, nda, catalog
        var id: String { rawValue }
        var title: String {
            switch self {
            case .greeting: return "Greeting maker"
            case .nda: return "NDA / agreement"
            case .catalog: return "Catalog maker"
            }
        }
        var symbol: String {
            switch self {
            case .greeting: return "party.popper.fill"
            case .nda: return "doc.text.fill"
            case .catalog: return "square.grid.2x2.fill"
            }
        }
        var detail: String {
            switch self {
            case .greeting: return "Name, photo and message on a card. Image or GIF."
            case .nda: return "Parties, date and terms as variables. PDF or Word."
            case .catalog: return "Six products with photo, name and price. Image, PDF or HTML."
            }
        }
    }

    private static func slot(_ key: String, _ kind: TemplateSlotKind, cx: Double, cy: Double, w: Double, h: Double, content: String? = nil,
                             bold: Bool = false, italic: Bool = false, color: String = "#2B1E45", shape: TemplateShape = .rectangle) -> TemplateSlot {
        var box = TemplateSlot(key: key, kind: kind)
        box.cx = cx; box.cy = cy; box.w = w; box.h = h
        box.content = content
        box.sample = content ?? "Your text"
        box.bold = bold; box.italic = italic; box.colorHex = color; box.shape = shape
        return box
    }

    @MainActor static func make(_ kind: Kind) -> AppDesign? {
        let store = AppDesignStore.shared
        switch kind {
        case .greeting:
            guard var design = store.newBlank(name: "Greeting maker", width: 1080, height: 1080, colorHex: "#FBE3EC"), let id = design.pages.first, var page = TemplateStore.shared.template(id: id) else { return nil }
            page.slots = [
                slot("title", .text, cx: 0.5, cy: 0.13, w: 0.86, h: 0.14, content: "Happy {{occasion}}!", bold: true, color: "#B83A6B"),
                slot("photo", .image, cx: 0.5, cy: 0.44, w: 0.4, h: 0.4, shape: .circle),
                slot("name", .text, cx: 0.5, cy: 0.74, w: 0.8, h: 0.1, content: "{{name}}", bold: true),
                slot("message", .text, cx: 0.5, cy: 0.855, w: 0.8, h: 0.1, content: "{{message}}", italic: true, color: "#5A4A6A"),
                slot("from", .text, cx: 0.5, cy: 0.95, w: 0.6, h: 0.05, content: "With love, {{from}}", color: "#7A6F8F")
            ]
            TemplateStore.shared.save(page)
            design.variables = ["occasion": "Birthday", "name": "Rahul", "message": "Wishing you a day full of joy and a year full of success.", "from": "Priya"]
            design.outputFormat = DesignFormat.gif.rawValue
            design.appTitle = "Greeting maker"
            store.save(design)
            return design
        case .nda:
            let clauses = [
                "MUTUAL NON-DISCLOSURE AGREEMENT",
                "This Agreement is made on {{date}} between {{party1}}, of {{address1}} (the \"First Party\"), and {{party2}}, of {{address2}} (the \"Second Party\").",
                "1. PURPOSE",
                "The parties wish to explore {{purpose}} (the \"Purpose\") and may share confidential information for that Purpose only.",
                "2. CONFIDENTIAL INFORMATION",
                "Confidential Information means any non-public information that one party discloses to the other, in any form, that is marked confidential or would reasonably be understood to be confidential.",
                "3. OBLIGATIONS",
                "Each party will keep the other's Confidential Information secret, use it only for the Purpose, and share it only with people who need it and are bound by similar duties.",
                "4. EXCEPTIONS",
                "These duties do not apply to information that is public through no fault of the receiving party, was already known to it, or was developed independently.",
                "5. TERM",
                "This Agreement lasts {{term}} from the date above. The duties of secrecy continue for {{survival}} after it ends.",
                "6. GOVERNING LAW",
                "This Agreement is governed by the laws of {{jurisdiction}}.",
                "SIGNED",
                "{{party1}}: ______________________        {{party2}}: ______________________"
            ]
            guard var design = store.newFromDocument(name: "NDA / agreement", paragraphs: clauses) else { return nil }
            design.variables = ["date": "{=TODAY()}", "party1": "Acme Pvt Ltd", "address1": "Mumbai, India", "party2": "Beta LLP", "address2": "Pune, India",
                                "purpose": "a possible business partnership", "term": "two years", "survival": "three years", "jurisdiction": "India"]
            design.outputFormat = DesignFormat.pdf.rawValue
            design.appTitle = "NDA generator"
            store.save(design)
            return design
        case .catalog:
            guard var design = store.newBlank(name: "Catalog maker", width: 1654, height: 2339, colorHex: "#FFFFFF"), let id = design.pages.first, var page = TemplateStore.shared.template(id: id) else { return nil }
            var slots = [
                slot("title", .text, cx: 0.5, cy: 0.07, w: 0.84, h: 0.07, content: "{{catalogtitle}}", bold: true, color: "#B83A6B"),
                slot("company", .text, cx: 0.5, cy: 0.12, w: 0.6, h: 0.03, content: "{{company}}", color: "#7A6F8F")
            ]
            for index in 0..<6 {
                let column = Double(index % 2), row = Double(index / 2)
                let cx = 0.27 + 0.46 * column, cy = 0.28 + 0.27 * row
                let number = index + 1
                slots.append(slot("photo\(number)", .image, cx: cx, cy: cy, w: 0.38, h: 0.17))
                slots.append(slot("name\(number)", .text, cx: cx, cy: cy + 0.11, w: 0.38, h: 0.035, content: "{{product\(number)}}", bold: true))
                slots.append(slot("price\(number)", .text, cx: cx, cy: cy + 0.15, w: 0.38, h: 0.03, content: "{{price\(number)}}", color: "#D9694F"))
            }
            page.slots = slots
            TemplateStore.shared.save(page)
            var variables = ["catalogtitle": "Our Catalog", "company": "Your company"]
            for number in 1...6 { variables["product\(number)"] = "Product \(number)"; variables["price\(number)"] = "\u{20B9}499" }
            design.variables = variables
            design.outputFormat = DesignFormat.pdf.rawValue
            design.appTitle = "Catalog maker"
            store.save(design)
            return design
        }
    }
}


// MARK: - One box for apps, people and everything else

/// $ looks at apps only, @ at people only, anything else at everything. Words like create, make or send open the app named in the sentence.
struct LaunchBox: View {
    @State private var text = ""
    @State private var items: [LaunchSuggestion] = []
    @State private var note = ""
    @StateObject private var speech = EzMeSpeechDictation()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Say or type: $app, @person, or \u{201C}make a greeting for Rahul\u{201D}", text: $text)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Find an app or person")
                    .onSubmit { go() }
                Button { toggleMic() } label: {
                    Image(systemName: speech.isListening ? "waveform.circle.fill" : "mic.fill").foregroundStyle(speech.isListening ? Color.red : Butter.coral)
                }
                .buttonStyle(.plain).help("Speak a command")
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Butter.honey.opacity(0.7), lineWidth: 1))
            if !items.isEmpty && !text.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        Button { AppLauncher.shared.act(item); text = ""; items = [] } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.symbol).foregroundStyle(Butter.coral).frame(width: 18)
                                Text(item.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Butter.cocoa).lineLimit(1)
                                Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 5).padding(.horizontal, 8).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.85)))
            }
            if !note.isEmpty { Text(note).font(.system(size: 11)).foregroundStyle(.secondary) }
            if !speech.errorMessage.isEmpty { Text(speech.errorMessage).font(.system(size: 11)).foregroundStyle(.red) }
        }
        .onChange(of: text) { _, value in items = AppLauncher.shared.suggestions(for: value) }
    }

    private func go() {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        if AppLauncher.shared.handle(line) { text = ""; items = []; note = "" }
        else { note = "Nothing matched. Try $ for apps, @ for people, or name the app after create, make or send." }
    }

    private func toggleMic() {
        if speech.isListening { speech.stop(); return }
        note = "Listening\u{2026}"
        speech.start(onTranscript: { spoken in
            text = spoken
            if AppLauncher.shared.handle(spoken, spoken: true) { text = ""; items = []; note = "" }
            else { items = AppLauncher.shared.suggestions(for: spoken); note = items.isEmpty ? "I did not find an app or person in that." : "Pick one below." }
        })
    }
}
