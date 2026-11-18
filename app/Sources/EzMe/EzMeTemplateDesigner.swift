// The Template Designer: upload a picture, take the text out of it, place named boxes on it (text, picture,
// logo) in any shape and angle, try it with real words, and choose which apps use it.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Small helpers

enum TemplateDialogs {
    @MainActor static func openImage(title: String = "Choose a picture") -> NSImage? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return NSImage(contentsOf: url)
    }

    @MainActor static func openLogo() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a logo"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor static func savePNG(_ data: Data, name: String) -> String {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = name + ".png"
        guard panel.runModal() == .OK, let url = panel.url else { return "Download cancelled." }
        do {
            try data.write(to: url, options: .atomic)
            return "Saved \(url.lastPathComponent)."
        } catch {
            return "Could not save: \(error.localizedDescription)"
        }
    }
}

enum TemplateFonts {
    static let all: [String] = {
        let wanted = ["Helvetica Neue", "Arial", "Georgia", "Times New Roman", "Courier New", "Avenir Next", "Futura", "Gill Sans",
                      "Palatino", "Verdana", "Trebuchet MS", "Optima", "Baskerville", "Didot", "Rockwell", "American Typewriter",
                      "Marker Felt", "Noteworthy", "Snell Roundhand", "Bradley Hand", "Kohinoor Devanagari", "Devanagari Sangam MN"]
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        let list = wanted.filter { installed.contains($0) }
        return list.isEmpty ? ["Helvetica Neue"] : list
    }()
}

private func clamp(_ value: Double, _ low: Double = 0, _ high: Double = 1) -> Double { min(high, max(low, value)) }

private func rotated(_ point: CGPoint, _ radians: Double) -> CGPoint {
    CGPoint(x: point.x * CGFloat(cos(radians)) - point.y * CGFloat(sin(radians)),
            y: point.x * CGFloat(sin(radians)) + point.y * CGFloat(cos(radians)))
}

// MARK: - The library

struct TemplateLibraryView: View {
    /// Where the Wish apps are kept, to list them when choosing which apps use a template.
    var wishDirectory: URL? = nil
    @ObservedObject private var store = TemplateStore.shared
    @State private var editingID: String?
    @State private var usingID: String?
    @State private var deleteID: String?
    @State private var message = ""

    var body: some View {
        if let id = editingID, let template = store.template(id: id) {
            TemplateDesignerView(template: template, onClose: { editingID = nil }).id(id)
        } else {
            gallery
        }
    }

    private var gallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BuilderHeader(symbol: "photo.on.rectangle.angled", title: "Template Designer",
                              subtitle: "Upload any bill, invoice, challan or frame. Remove its text, then place text, picture and logo boxes on it.") {
                    HStack(spacing: 8) {
                        Button { startFromFile() } label: { Label("New from picture", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderedProminent).tint(Butter.coral)
                        Button { startFromClipboard() } label: { Label("Paste picture", systemImage: "doc.on.clipboard") }
                            .buttonStyle(.bordered)
                        Menu {
                            Button("Invoice page (A4)") { startBlank("Invoice", 1654, 2339) }
                            Button("Square post") { startBlank("Square post", 1080, 1080) }
                            Button("Story (tall)") { startBlank("Story", 1080, 1920) }
                            Button("Certificate (wide)") { startBlank("Certificate", 2000, 1414) }
                        } label: { Label("Blank page", systemImage: "doc") }
                            .menuStyle(.borderlessButton).fixedSize()
                    }
                }
                if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(Butter.cocoa.opacity(0.8)) }
                if store.templates.filter({ $0.designID == nil }).isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 300), spacing: 14)], spacing: 14) {
                        ForEach(store.templates.filter { $0.designID == nil }) { template in card(template) }
                    }
                }
                Text("An app fills a box when it has a field with the same name, for example a field called amount fills the box called amount. Text always shrinks to fit its box.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(22)
        }
        .sheet(item: Binding(get: { usingID.map { TemplateSheetID(id: $0) } }, set: { usingID = $0?.id })) { item in
            TemplateUseSheet(templateID: item.id, wishDirectory: wishDirectory)
        }
        .alert("Delete this template?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button("Delete", role: .destructive) { if let id = deleteID { store.delete(id) }; deleteID = nil }
            Button("Cancel", role: .cancel) { deleteID = nil }
        } message: {
            Text("Apps that use it go back to their normal look.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.badge.plus").font(.system(size: 40)).foregroundStyle(Butter.coral)
            Text("No templates yet").font(.system(size: 17, weight: .semibold)).foregroundStyle(Butter.cocoa)
            Text("Upload a picture of a bill, invoice, challan, frame or poster to begin.").font(.system(size: 13)).foregroundStyle(.secondary)
            Button { startFromFile() } label: { Label("Choose a picture", systemImage: "square.and.arrow.up") }
                .buttonStyle(.borderedProminent).tint(Butter.coral)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50)
        .background(RoundedRectangle(cornerRadius: 16).fill(Butter.cream))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Butter.honey, lineWidth: 1))
    }

    private func card(_ template: ImageTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Rectangle().fill(Color(white: 0.94))
                if let picture = store.basePicture(for: template) {
                    Image(nsImage: picture).resizable().scaledToFit().padding(6)
                }
            }
            .frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture { editingID = template.id }
            Text(template.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Butter.cocoa).lineLimit(1)
            Text("\(template.slots.count) boxes \u{00B7} \(template.pixelWidth)\u{00D7}\(template.pixelHeight)").font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button("Edit") { editingID = template.id }.buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.small)
                Button("Use in apps") { usingID = template.id }.buttonStyle(.bordered).controlSize(.small)
                Spacer()
                Menu {
                    Button("Duplicate") { _ = store.duplicate(template.id) }
                    Button("Delete", role: .destructive) { deleteID = template.id }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Butter.honey.opacity(0.7), lineWidth: 1))
    }

    private func startFromFile() {
        guard let image = TemplateDialogs.openImage(title: "Choose a bill, invoice, frame or any picture") else { return }
        open(image, name: "New template")
    }

    private func startFromClipboard() {
        guard let image = TemplateImages.fromPasteboard() else { message = "There is no picture on the clipboard."; return }
        open(image, name: "Pasted template")
    }

    private func startBlank(_ name: String, _ width: Int, _ height: Int) {
        if let made = store.blank(name: name, width: width, height: height) { editingID = made.id }
    }

    private func open(_ image: NSImage, name: String) {
        if let made = store.create(from: image, name: name) { editingID = made.id } else { message = "That picture could not be opened." }
    }
}

private struct TemplateSheetID: Identifiable { let id: String }

// MARK: - Which apps use a template

struct TemplateUseSheet: View {
    var templateID: String
    var wishDirectory: URL?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = TemplateStore.shared
    @State private var refresh = 0

    private var wishApps: [WishApp] {
        guard let wishDirectory else { return [] }
        return WishStoreReader.read(directory: wishDirectory).apps
    }

    private var builderApps: [String] {
        (try? JSONDecoder().decode([String].self, from: Data((UserDefaults.standard.string(forKey: "ezmeCustomBuilderAppsJSON") ?? "[]").utf8))) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use \u{201C}\(TemplateLinks.title(for: templateID))\u{201D} in apps").font(.system(size: 17, weight: .bold)).foregroundStyle(Butter.cocoa)
                    Text("Boxes and variables: \(TemplateLinks.fieldKeys(for: templateID).joined(separator: ", "))").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).tint(Butter.coral)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("WishBuilder apps")
                    if wishApps.isEmpty { Text("No Wish apps found yet. Open Wish Studio once to create them.").font(.system(size: 12)).foregroundStyle(.secondary) }
                    ForEach(wishApps) { app in
                        toggleRow(app.name, isOn: DesignSnapshots.isLinked(current: TemplateStore.wishTemplateID(appID: app.id), to: templateID, app: "wish." + app.id)) { on in
                            if on {
                                if let link = DesignSnapshots.makeCopy(of: templateID, app: "wish." + app.id, appName: app.name) { TemplateStore.setWishTemplate(link, appID: app.id) }
                            } else {
                                TemplateStore.setWishTemplate("", appID: app.id)
                            }
                            refresh += 1
                        }
                    }
                    sectionTitle("AppBuilder apps")
                    if builderApps.isEmpty { Text("No AppBuilder apps of your own yet.").font(.system(size: 12)).foregroundStyle(.secondary) }
                    ForEach(builderApps, id: \.self) { name in
                        toggleRow(name, isOn: DesignSnapshots.isLinked(current: TemplateStore.builderTemplateID(app: name), to: templateID, app: "builder." + name)) { on in
                            if on {
                                if let link = DesignSnapshots.makeCopy(of: templateID, app: "builder." + name, appName: name) { TemplateStore.setBuilderTemplate(link, app: name) }
                            } else {
                                TemplateStore.setBuilderTemplate("", app: name)
                            }
                            refresh += 1
                        }
                    }
                }
            }
            Text("Each app gets its own saved copy with a new name, so the app's default look and this design are never changed. Switch an app off to go back to its default. An app fills a box when it has a field with the same name.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 520, height: 520)
        .id(refresh)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .bold)).foregroundStyle(Butter.cocoa).padding(.top, 6)
    }

    private func toggleRow(_ name: String, isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(Butter.cocoa)
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { set($0) })).toggleStyle(.switch).labelsHidden()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Butter.cream))
    }
}

// MARK: - Picking a template inside WishBuilder

struct WishTemplatePicker: View {
    var appID: String
    var existingFieldKeys: [String]
    var onAddFields: ([String]) -> Void
    @ObservedObject private var store = TemplateStore.shared
    @ObservedObject private var designs = AppDesignStore.shared
    @State private var selected = ""
    @State private var showLibrary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photo template (optional)").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 10) {
                Picker("", selection: $selected) {
                    Text("None: use the built-in looks").tag("")
                    ForEach(store.templates.filter { $0.designID == nil }) { Text($0.name).tag($0.id) }
                    ForEach(designs.designs) { Text($0.name + " (AppDesigner)").tag("design:" + $0.id) }
                }
                .labelsHidden().frame(maxWidth: 320)
                Button { showLibrary = true } label: { Label("Open AppDesigner", systemImage: "paintpalette.fill") }
                    .buttonStyle(.bordered)
            }
            if !selected.isEmpty, !TemplateLinks.pages(for: selected).isEmpty {
                let keys = TemplateLinks.fieldKeys(for: selected)
                let missing = keys.filter { key in !existingFieldKeys.contains(where: { TemplateFill.normal($0) == TemplateFill.normal(key) }) }
                Text("Boxes and variables: \(keys.joined(separator: ", ")). A field with the same name fills its box.")
                    .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
                if !missing.isEmpty {
                    Button { onAddFields(missing) } label: { Label("Create \(missing.count) field\(missing.count == 1 ? "" : "s") from the boxes", systemImage: "plus.rectangle.on.rectangle") }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                Text("Upload a bill, invoice, challan or frame and the cards of this app are made on it.")
                    .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
            }
        }
        .onAppear { selected = TemplateStore.wishTemplateID(appID: appID) }
        .onChange(of: selected) { _, value in TemplateStore.setWishTemplate(value, appID: appID) }
        .sheet(isPresented: $showLibrary) {
            VStack(spacing: 0) {
                HStack { Spacer(); Button("Close") { showLibrary = false }.buttonStyle(.borderedProminent).tint(Butter.coral) }.padding(12)
                AppDesignerView()
            }
            .frame(minWidth: 1100, minHeight: 760)
        }
    }
}

/// The card of a Wish app drawn on its photo template.
struct WishTemplateCard: View {
    @ObservedObject var model: WishStudioModel
    var template: ImageTemplate

    var body: some View {
        Group {
            if let image = model.templateCardImage(template, maxSide: 1600) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(12)
            } else {
                Text("The template picture is missing. Choose another template in WishBuilder, step 1.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.96))
    }
}

// MARK: - The designer

struct TemplateDesignerView: View {
    enum Mode: String, CaseIterable { case design = "Design", erase = "Erase", fill = "Try it" }
    private struct Snapshot { var image: NSImage; var slots: [TemplateSlot] }

    @ObservedObject private var store = TemplateStore.shared
    @State private var template: ImageTemplate
    @State private var base: NSImage
    @State private var preview: NSImage?
    @State private var mode: Mode = .design
    @State private var selectedID: String?
    @State private var undo: [Snapshot] = []
    @State private var busy: String?
    @State private var message = ""
    @State private var moveStart: (id: String, cx: Double, cy: Double)?
    @State private var resizeStart: TemplateSlot?
    @State private var eraseStart: CGPoint?
    @State private var eraseNow: CGPoint?
    @State private var eraseTool: EraseTool = .rectangle
    @State private var erasePoints: [CGPoint] = []
    @State private var testTexts: [String: String] = [:]
    @State private var testImages: [String: NSImage] = [:]
    @State private var testVersion = 0
    var onClose: () -> Void
    var pageInfo: (index: Int, count: Int)? = nil
    var onGoToPage: ((Int) -> Void)? = nil
    var onAddPage: (() -> Void)? = nil
    var onRelease: (() -> String)? = nil
    var onVariablesChange: (([String: String]) -> Void)? = nil
    var onReplaceElsewhere: ((String, String) -> Int)? = nil
    var designTitle: String? = nil
    var onOutputFormatChange: ((String) -> Void)? = nil
    var onMakeFile: (([String: String]) -> String)? = nil
    var onRename: ((String) -> (name: String, command: String))? = nil
    enum SideTab: Hashable { case library, box, page }
    @State private var openSections: Set<String> = ["box", "library"]
    @State private var formValues: [String: String] = [:]
    @State private var commandWord = ""
    @State private var appName = ""
    @FocusState private var appNameFocused: Bool
    @FocusState private var commandFocused2: Bool
    @StateObject private var tryGuide = DesignVoiceGuide()
    var onCommandChange: ((String) -> String)? = nil
    @State private var livePreview: NSImage?
    @State private var librarySearch = ""
    @State private var libCategory = ""
    @State private var libSub = ""
    @State private var libField = "name"
    /// The language the command mic listens in. English every time the designer opens.
    @State private var commandLocale = "en-IN"
    @State private var outputFormat: String
    @State private var vars: [String: String]
    @State private var commandText = ""
    @State private var heard = ""
    @State private var newVariable = ""
    @StateObject private var voice = WishVoiceController()
    @FocusState private var commandFocused: Bool

    init(template: ImageTemplate, onClose: @escaping () -> Void, pageInfo: (index: Int, count: Int)? = nil,
         onGoToPage: ((Int) -> Void)? = nil, onAddPage: (() -> Void)? = nil, onRelease: (() -> String)? = nil,
         variables: [String: String] = [:], onVariablesChange: (([String: String]) -> Void)? = nil,
         onReplaceElsewhere: ((String, String) -> Int)? = nil, designTitle: String? = nil,
         outputFormat: String? = nil, onOutputFormatChange: ((String) -> Void)? = nil,
         onMakeFile: (([String: String]) -> String)? = nil, onRename: ((String) -> (name: String, command: String))? = nil,
         command: String? = nil, onCommandChange: ((String) -> String)? = nil) {
        _commandWord = State(initialValue: command ?? "")
        _appName = State(initialValue: designTitle ?? "")
        self.onCommandChange = onCommandChange
        _template = State(initialValue: template)
        _base = State(initialValue: TemplateStore.shared.basePicture(for: template) ?? NSImage(size: NSSize(width: 100, height: 100)))
        _vars = State(initialValue: variables)
        self.onClose = onClose
        self.pageInfo = pageInfo
        self.onGoToPage = onGoToPage
        self.onAddPage = onAddPage
        self.onRelease = onRelease
        self.onVariablesChange = onVariablesChange
        self.onReplaceElsewhere = onReplaceElsewhere
        self.designTitle = designTitle
        _outputFormat = State(initialValue: outputFormat ?? (pageInfo != nil && (pageInfo?.count ?? 1) > 1 ? DesignFormat.pdf.rawValue : DesignFormat.png.rawValue))
        self.onOutputFormatChange = onOutputFormatChange
        self.onMakeFile = onMakeFile
        self.onRename = onRename
    }

    // MARK: Layout

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                VStack(spacing: 0) {
                    canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    commandBar
                }
                .background(Color(white: 0.9))
                Divider()
                previewPane
            }
        }
        .onAppear { refresh() }
        .onChange(of: template) { _, _ in refresh() }
        .onChange(of: mode) { _, _ in refresh() }
        .onChange(of: testTexts) { _, _ in refresh() }
        .onChange(of: testVersion) { _, _ in refresh() }
        .onChange(of: vars) { _, _ in refresh() }
        .onChange(of: formValues) { _, _ in refresh() }
        .onChange(of: selectedID) { _, value in if value != nil { openSections.insert("box") } }
        .onAppear {
            tryGuide.fields = { previewFields }
            tryGuide.values = { formValues }
            tryGuide.setValue = { key, value in formValues[key] = value }
            tryGuide.make = { makeFile() }
            tryGuide.onStart = { voice.stop() }
            fillDefaults()
        }
        .onChange(of: previewFields) { _, _ in fillDefaults() }
        .onDisappear { voice.stop(); tryGuide.stop(); store.save(template) }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { finish() } label: { Label("Templates", systemImage: "chevron.left") }.buttonStyle(.bordered)
            if designTitle != nil {
                HStack(spacing: 4) {
                    Text("App").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    TextField("App name", text: $appName).textFieldStyle(.roundedBorder).font(.system(size: 13, weight: .bold)).frame(maxWidth: 180)
                        .focused($appNameFocused).onSubmit { commitAppName() }
                        .onChange(of: appNameFocused) { _, focused in if !focused { commitAppName() } }
                        .accessibilityLabel("App name").help("The name of the app. Press Return to rename it.")
                }
            }
            TextField(designTitle == nil ? "Template name" : "Page name", text: $template.name).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
            if let info = pageInfo {
                HStack(spacing: 4) {
                    Button { _ = go(to: info.index - 2) } label: { Image(systemName: "chevron.left") }.disabled(info.index <= 1)
                    Text("Page \(info.index) of \(info.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Butter.cocoa)
                    Button { _ = go(to: info.index) } label: { Image(systemName: "chevron.right") }.disabled(info.index >= info.count)
                    Button { _ = perform(.addPage) } label: { Label("Page", systemImage: "plus") }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            Picker("", selection: $mode) { ForEach([Mode.design, Mode.erase], id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
            if let busy { ProgressView().controlSize(.small); Text(busy).font(.system(size: 12)).foregroundStyle(.secondary) }
            else if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(Butter.cocoa.opacity(0.8)).lineLimit(1) }
            Spacer()
            if onRelease != nil {
                Button { message = perform(.release) } label: { Label("Publish", systemImage: "paperplane.fill") }.buttonStyle(.borderedProminent).tint(.green)
            }
            Button { finish() } label: { Label("Save and close", systemImage: "checkmark") }
                .buttonStyle(.borderedProminent).tint(Butter.coral)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func finish() {
        store.save(template)
        onClose()
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let pictureWidth = max(1, CGFloat(template.pixelWidth)), pictureHeight = max(1, CGFloat(template.pixelHeight))
            let scale = max(0.05, min((geo.size.width - 28) / pictureWidth, (geo.size.height - 28) / pictureHeight))
            let width = pictureWidth * scale, height = pictureHeight * scale
            ZStack(alignment: .topLeading) {
                Image(nsImage: preview ?? base).resizable().interpolation(.high).frame(width: width, height: height)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                    .onTapGesture { selectedID = nil }
                if mode == .design { overlays(width: width, height: height) }
                if mode == .erase { eraseLayer(width: width, height: height) }
            }
            .frame(width: width, height: height)
            .coordinateSpace(name: "canvas")
            .onDrop(of: [.plainText, .fileURL], delegate: SlotDropDelegate(size: CGSize(width: width, height: height)) { payload, point in
                _ = applyPayload(payload, at: point)
            })
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func slotIndex(_ id: String) -> Int? { template.slots.firstIndex { $0.id == id } }
    private var selectedIndex: Int? { selectedID.flatMap { slotIndex($0) } }

    @ViewBuilder private func overlays(width: CGFloat, height: CGFloat) -> some View {
        ForEach(template.slots) { slot in slotBox(slot, width: width, height: height) }
        if let index = selectedIndex { handles(template.slots[index], width: width, height: height) }
    }

    private func slotBox(_ slot: TemplateSlot, width: CGFloat, height: CGFloat) -> some View {
        let selected = slot.id == selectedID
        return ZStack {
            Rectangle().fill(Color.clear)
            TemplateOutlineShape(shape: slot.shape, points: slot.points)
                .stroke(Color.black.opacity(0.35), lineWidth: selected ? 4 : 2.4)
            TemplateOutlineShape(shape: slot.shape, points: slot.points)
                .stroke(selected ? Butter.coral : Color.white.opacity(0.95), style: StrokeStyle(lineWidth: selected ? 2 : 1.2, dash: selected ? [] : [5, 3]))
        }
        .frame(width: CGFloat(slot.w) * width, height: CGFloat(slot.h) * height)
        .contentShape(Rectangle())
        .rotationEffect(.degrees(slot.angle))
        .position(x: CGFloat(slot.cx) * width, y: CGFloat(slot.cy) * height)
        .onTapGesture { selectedID = slot.id }
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
                .onChanged { value in
                    if moveStart?.id != slot.id { moveStart = (slot.id, slot.cx, slot.cy); selectedID = slot.id }
                    guard let start = moveStart, let index = slotIndex(slot.id) else { return }
                    template.slots[index].cx = clamp(start.cx + Double(value.translation.width / width))
                    template.slots[index].cy = clamp(start.cy + Double(value.translation.height / height))
                }
                .onEnded { _ in moveStart = nil }
        )
    }

    private static let directions: [(Double, Double)] = [(-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0)]

    @ViewBuilder private func handles(_ slot: TemplateSlot, width: CGFloat, height: CGFloat) -> some View {
        let center = CGPoint(x: CGFloat(slot.cx) * width, y: CGFloat(slot.cy) * height)
        let halfWidth = CGFloat(slot.w) * width / 2, halfHeight = CGFloat(slot.h) * height / 2
        let radians = slot.angle * .pi / 180
        ForEach(0..<Self.directions.count, id: \.self) { number in
            let direction = Self.directions[number]
            let offset = rotated(CGPoint(x: CGFloat(direction.0) * halfWidth, y: CGFloat(direction.1) * halfHeight), radians)
            handleDot()
                .position(x: center.x + offset.x, y: center.y + offset.y)
                .gesture(resizeGesture(slot.id, sx: direction.0, sy: direction.1, width: width, height: height))
        }
        let top = rotated(CGPoint(x: 0, y: -halfHeight), radians)
        let knob = rotated(CGPoint(x: 0, y: -halfHeight - 28), radians)
        Path { path in
            path.move(to: CGPoint(x: center.x + top.x, y: center.y + top.y))
            path.addLine(to: CGPoint(x: center.x + knob.x, y: center.y + knob.y))
        }
        .stroke(Butter.coral, lineWidth: 1.5)
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            .frame(width: 20, height: 20).background(Circle().fill(Butter.coral)).overlay(Circle().stroke(.white, lineWidth: 1.5))
            .position(x: center.x + knob.x, y: center.y + knob.y)
            .help("Drag to turn")
            .gesture(rotateGesture(slot.id, width: width, height: height))
        if slot.shape == .random {
            ForEach(0..<(slot.points.count / 2), id: \.self) { number in
                let local = CGPoint(x: (CGFloat(slot.points[number * 2]) - 0.5) * halfWidth * 2, y: (CGFloat(slot.points[number * 2 + 1]) - 0.5) * halfHeight * 2)
                let offset = rotated(local, radians)
                Circle().fill(Color.yellow).overlay(Circle().stroke(Butter.cocoa, lineWidth: 1.5)).frame(width: 13, height: 13)
                    .position(x: center.x + offset.x, y: center.y + offset.y)
                    .gesture(vertexGesture(slot.id, point: number, width: width, height: height))
            }
        }
    }

    private func handleDot() -> some View {
        Circle().fill(Color.white).overlay(Circle().stroke(Butter.coral, lineWidth: 2)).frame(width: 12, height: 12)
    }

    private func resizeGesture(_ id: String, sx: Double, sy: Double, width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
            .onChanged { value in
                guard let index = slotIndex(id) else { return }
                if resizeStart?.id != id { resizeStart = template.slots[index] }
                guard let start = resizeStart else { return }
                let radians = start.angle * .pi / 180
                let local = rotated(CGPoint(x: value.translation.width, y: value.translation.height), -radians)
                let newWidth = max(14, CGFloat(start.w) * width + CGFloat(sx) * local.x)
                let newHeight = max(14, CGFloat(start.h) * height + CGFloat(sy) * local.y)
                let shift = rotated(CGPoint(x: CGFloat(sx) * (newWidth - CGFloat(start.w) * width) / 2,
                                            y: CGFloat(sy) * (newHeight - CGFloat(start.h) * height) / 2), radians)
                template.slots[index].w = Double(newWidth / width)
                template.slots[index].h = Double(newHeight / height)
                template.slots[index].cx = start.cx + Double(shift.x / width)
                template.slots[index].cy = start.cy + Double(shift.y / height)
            }
            .onEnded { _ in resizeStart = nil }
    }

    private func rotateGesture(_ id: String, width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
            .onChanged { value in
                guard let index = slotIndex(id) else { return }
                let slot = template.slots[index]
                let center = CGPoint(x: CGFloat(slot.cx) * width, y: CGFloat(slot.cy) * height)
                var degrees = atan2(Double(value.location.y - center.y), Double(value.location.x - center.x)) * 180 / .pi + 90
                if degrees > 180 { degrees -= 360 }
                let snapped = (degrees / 15).rounded() * 15
                if abs(degrees - snapped) < 3 { degrees = snapped }
                template.slots[index].angle = (degrees * 10).rounded() / 10
            }
    }

    private func vertexGesture(_ id: String, point: Int, width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
            .onChanged { value in
                guard let index = slotIndex(id) else { return }
                let slot = template.slots[index]
                guard point * 2 + 1 < slot.points.count else { return }
                let center = CGPoint(x: CGFloat(slot.cx) * width, y: CGFloat(slot.cy) * height)
                let local = rotated(CGPoint(x: value.location.x - center.x, y: value.location.y - center.y), -slot.angle * .pi / 180)
                template.slots[index].points[point * 2] = clamp(Double(local.x / (CGFloat(slot.w) * width)) + 0.5)
                template.slots[index].points[point * 2 + 1] = clamp(Double(local.y / (CGFloat(slot.h) * height)) + 0.5)
            }
    }

    // MARK: Erasing by hand

    enum EraseTool: String, CaseIterable, Identifiable {
        case rectangle = "Rectangle", square = "Square", circle = "Circle", triangle = "Triangle", polygon = "Points", freehand = "Free hand"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .rectangle: return "rectangle"
            case .square: return "square"
            case .circle: return "circle"
            case .triangle: return "triangle"
            case .polygon: return "hexagon"
            case .freehand: return "scribble"
            }
        }
    }

    /// The outline of a dragged shape, in canvas points.
    private func eraseOutline(_ tool: EraseTool, from start: CGPoint, to now: CGPoint) -> [CGPoint] {
        var dx = now.x - start.x, dy = now.y - start.y
        if tool == .square { let side = max(abs(dx), abs(dy)); dx = dx < 0 ? -side : side; dy = dy < 0 ? -side : side }
        let rect = CGRect(x: min(start.x, start.x + dx), y: min(start.y, start.y + dy), width: abs(dx), height: abs(dy))
        switch tool {
        case .circle:
            return (0..<64).map { step in
                let angle = Double(step) / 64 * 2 * Double.pi
                return CGPoint(x: rect.midX + cos(angle) * rect.width / 2, y: rect.midY + sin(angle) * rect.height / 2)
            }
        case .triangle:
            return [CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        default:
            return [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        }
    }

    private func outlinePath(_ points: [CGPoint], closed: Bool) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        if closed { path.closeSubpath() }
        return path
    }

    private func finishErase(_ points: [CGPoint], width: CGFloat, height: CGFloat) {
        let normal = points.map { CGPoint(x: min(max($0.x / width, 0), 1), y: min(max($0.y / height, 0), 1)) }
        erasePoints = []
        eraseStart = nil; eraseNow = nil
        eraseShape(normal)
    }

    private func eraseLayer(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)
            if let start = eraseStart, let now = eraseNow, eraseTool != .freehand, eraseTool != .polygon {
                let outline = eraseOutline(eraseTool, from: start, to: now)
                outlinePath(outline, closed: true).fill(Color.red.opacity(0.25))
                outlinePath(outline, closed: true).stroke(Color.red, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            if !erasePoints.isEmpty {
                let closed = eraseTool == .freehand
                if closed { outlinePath(erasePoints, closed: true).fill(Color.red.opacity(0.25)) }
                outlinePath(erasePoints, closed: closed).stroke(Color.red, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                if eraseTool == .polygon, let first = erasePoints.first {
                    Circle().stroke(Color.red, lineWidth: 2).frame(width: 12, height: 12).position(first)
                }
            }
            HStack(spacing: 4) {
                ForEach(EraseTool.allCases) { tool in
                    Button { eraseTool = tool; erasePoints = []; eraseStart = nil; eraseNow = nil } label: {
                        Image(systemName: tool.symbol).font(.system(size: 13, weight: .semibold)).frame(width: 28, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6).fill(eraseTool == tool ? Butter.coral : Color.white.opacity(0.92)))
                            .foregroundStyle(eraseTool == tool ? Color.white : Butter.cocoa)
                    }
                    .buttonStyle(.plain).help(tool.rawValue)
                }
                if eraseTool == .polygon && erasePoints.count >= 3 {
                    Button("Erase it") { finishErase(erasePoints, width: width, height: height) }.buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.small)
                }
                if !erasePoints.isEmpty { Button("Cancel") { erasePoints = [] }.buttonStyle(.bordered).controlSize(.small) }
            }
            .padding(6).background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.35))).padding(8)
        }
        .frame(width: width, height: height)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                .onChanged { value in
                    switch eraseTool {
                    case .freehand:
                        if erasePoints.isEmpty { erasePoints = [value.startLocation] }
                        if let last = erasePoints.last, hypot(last.x - value.location.x, last.y - value.location.y) > 2 { erasePoints.append(value.location) }
                    case .polygon:
                        break
                    default:
                        guard hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y) > 3 else { return }
                        eraseStart = value.startLocation; eraseNow = value.location
                    }
                }
                .onEnded { value in
                    switch eraseTool {
                    case .freehand:
                        let points = erasePoints
                        erasePoints = []
                        if points.count >= 3 { finishErase(points, width: width, height: height) }
                    case .polygon:
                        if hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y) > 6 { return }
                        if erasePoints.count >= 3, let first = erasePoints.first, hypot(first.x - value.location.x, first.y - value.location.y) < 12 {
                            finishErase(erasePoints, width: width, height: height)
                        } else {
                            erasePoints.append(value.location)
                        }
                    default:
                        guard let start = eraseStart, let now = eraseNow else { return }
                        let outline = eraseOutline(eraseTool, from: start, to: now)
                        finishErase(outline, width: width, height: height)
                    }
                }
        )
        .onHover { inside in if inside { NSCursor.crosshair.push() } else { NSCursor.pop() } }
    }

    // MARK: Inspector

    /// One panel: Box, Library and Page sit one under the other, each can be folded, so nothing is hidden behind a tab.
    @ViewBuilder private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                section("box", "Box", "rectangle.dashed") {
                    if let index = selectedIndex { boxEditor(index) } else {
                        hint("Click a box on the page to edit it. Drag it to move, drag the dots to resize, and drag the round arrow to turn it.")
                        boxesCard
                    }
                }
                section("library", "Library", "books.vertical") { libraryPanel }
                section("page", "Page", "doc.richtext") {
                    if mode == .erase { hint("Pick a shape at the top of the page (rectangle, square, circle, triangle, points or free hand), then draw around what to remove. Only the inside of the shape is erased.") }
                    if onVariablesChange != nil { variablesCard }
                    addCard
                    if selectedIndex != nil { boxesCard }
                    pictureCard
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .frame(width: 330).background(Color(nsColor: .windowBackgroundColor))
    }

    private func section<Content: View>(_ id: String, _ title: String, _ symbol: String, @ViewBuilder _ content: () -> Content) -> some View {
        let open = openSections.contains(id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if open { openSections.remove(id) } else { openSections.insert(id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: symbol).foregroundStyle(Butter.coral).frame(width: 18)
                    Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Butter.cocoa)
                    Spacer()
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Butter.cocoa.opacity(0.6))
                }
                .padding(.vertical, 6).padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(Butter.honey.opacity(0.35)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 14) { content() }
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(Butter.cocoa)
            content()
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Butter.cream))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Butter.honey.opacity(0.7), lineWidth: 1))
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Butter.cocoa.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
    }

    private var pictureCard: some View {
        card("Picture") {
            VStack(alignment: .leading, spacing: 6) {
                Button { eraseAllText(makeBoxes: false) } label: { Label("Remove all text from the picture", systemImage: "text.badge.minus") }
                    .disabled(busy != nil)
                Button { eraseAllText(makeBoxes: true) } label: { Label("Remove text and make a box for each line", systemImage: "rectangle.dashed.badge.record") }
                    .disabled(busy != nil)
                HStack {
                    Button { mode = .erase } label: { Label("Erase an area", systemImage: "eraser") }
                    Button { undoLast() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(undo.isEmpty)
                }
                HStack {
                    Button { replacePicture() } label: { Label("Replace picture", systemImage: "photo") }
                    Button { startAgain() } label: { Label("Start again", systemImage: "arrow.counterclockwise") }
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }

    private var addCard: some View {
        card("Add a box") {
            HStack(spacing: 6) {
                Button { addSlot(.text) } label: { Label("Text", systemImage: "textformat") }
                Button { addSlot(.image) } label: { Label("Picture", systemImage: "photo") }
                Menu {
                    ForEach(TemplateLogos.builtIn, id: \.name) { logo in
                        Button { addLogo(logo.name) } label: { Label(logo.name, systemImage: logo.symbol) }
                    }
                    Button { addLogo("KeyDo") } label: { Label("KeyDo", systemImage: "key.fill") }
                    if !store.uploadedLogos.isEmpty {
                        Divider()
                        ForEach(store.uploadedLogos, id: \.self) { file in
                            Button { addLogo("file:" + file) } label: { Label(file, systemImage: "photo") }
                        }
                    }
                    Divider()
                    Button { uploadLogo(addToTemplate: true) } label: { Label("Upload your logo\u{2026}", systemImage: "square.and.arrow.up") }
                } label: { Label("Logo", systemImage: "seal") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            .buttonStyle(.bordered).controlSize(.small)
            HStack(spacing: 6) {
                Button { let name = newVariableName(); addElementBox("{{\(name)}}", name: name) } label: { Label("Variable", systemImage: "curlybraces") }
                Menu {
                    ForEach(DesignElementTokens.functions) { item in
                        Button(item.title) { addElementBox(item.token, name: "function") }
                    }
                } label: { Label("Function", systemImage: "function") }
                    .menuStyle(.borderlessButton).fixedSize()
                Menu {
                    let tree = AppDesignContext.shared.collectionTree
                    if tree.isEmpty { Text("No collections yet") }
                    ForEach(tree) { group in
                        Menu(group.category) {
                            ForEach(group.names, id: \.self) { name in
                                Button { addElementBox(DesignElementTokens.refine("{{wish:\(name)}}"), name: name) } label: {
                                    Label(name, systemImage: MediaFinder.isMediaCollection(name) ? "photo.on.rectangle" : "list.bullet.rectangle")
                                }
                            }
                        }
                    }
                } label: { Label("Dropdown", systemImage: "list.bullet.rectangle") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            .buttonStyle(.bordered).controlSize(.small)
            Text("Or say \u{201C}add variable company\u{201D}, \u{201C}add function date\u{201D}, \u{201C}add dropdown of Diwali wishes\u{201D}. A Picture box is chosen from shortcuts or files when the app runs.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var boxesCard: some View {
        card("Boxes (\(template.slots.count))") {
            if template.slots.isEmpty { hint("No boxes yet. Add a text, picture or logo box.") }
            ForEach(template.slots) { slot in
                HStack(spacing: 8) {
                    Image(systemName: slot.kind.symbol).frame(width: 18).foregroundStyle(Butter.coral)
                    Text(slot.key).font(.system(size: 12, weight: slot.id == selectedID ? .bold : .medium)).foregroundStyle(Butter.cocoa).lineLimit(1)
                    Text(slot.shape.title).font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button { deleteSlot(slot.id) } label: { Image(systemName: "trash").foregroundStyle(.red.opacity(0.8)) }.buttonStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(slot.id == selectedID ? Butter.honey.opacity(0.5) : Color.white.opacity(0.7)))
                .contentShape(Rectangle())
                .onTapGesture { selectedID = slot.id }
            }
        }
    }

    // MARK: Editing one box

    private func boxEditor(_ index: Int) -> some View {
        let slot = template.slots[index]
        return VStack(alignment: .leading, spacing: 12) {
            card("This box") {
                TextField("Box name, like name or amount", text: $template.slots[index].key).textFieldStyle(.roundedBorder)
                hint("Apps fill this box when a field has this name.")
                Button { makeFixed(index) } label: { Label(slot.kind == .image ? "Make this picture fixed" : "Turn variables here into fixed text", systemImage: "pin") }
                    .buttonStyle(.bordered)
                hint("Fixed means the ready value is printed as is and the form stops asking for it.")
                Picker("", selection: $template.slots[index].kind) {
                    ForEach(TemplateSlotKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }
            card("Shape and angle") {
                HStack(spacing: 6) {
                    ForEach(TemplateShape.allCases, id: \.self) { shape in
                        Button { template.slots[index].shape = shape } label: {
                            VStack(spacing: 2) {
                                Image(systemName: shape.symbol).font(.system(size: 15))
                                Text(shape.title).font(.system(size: 8.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(slot.shape == shape ? .white : Butter.cocoa)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(slot.shape == shape ? Butter.coral : Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Butter.honey, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if slot.shape == .random {
                    HStack {
                        Button("Add a corner") { addCorner(index) }
                        Button("Remove a corner") { removeCorner(index) }.disabled(slot.points.count <= 6)
                        Button("Reset") { template.slots[index].points = TemplateSlot.defaultPoints }
                    }.buttonStyle(.bordered).controlSize(.small)
                    hint("Drag the yellow dots on the picture to shape it.")
                }
                HStack {
                    Text("Angle").font(.system(size: 12, weight: .semibold))
                    Slider(value: $template.slots[index].angle, in: -180...180, step: 1)
                    Text("\(Int(slot.angle))\u{00B0}").font(.system(size: 12, design: .monospaced)).frame(width: 44, alignment: .trailing)
                    Button("0\u{00B0}") { template.slots[index].angle = 0 }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            if slot.kind != .logo { contentEditor(index) }
            if slot.kind == .text { textEditor(index) }
            if slot.kind == .logo { logoEditor(index) }
            HStack {
                Button { duplicateSlot(index) } label: { Label("Duplicate box", systemImage: "plus.square.on.square") }
                Button(role: .destructive) { deleteSlot(slot.id) } label: { Label("Delete box", systemImage: "trash") }
            }.buttonStyle(.bordered).controlSize(.small)
        }
    }

    private func color(_ hex: Binding<String>) -> Binding<Color> {
        Binding(get: { Color(nsColor: NSColor(templateHex: hex.wrappedValue)) }, set: { hex.wrappedValue = NSColor($0).templateHex })
    }

    private func textEditor(_ index: Int) -> some View {
        let slot = template.slots[index]
        return card("Text") {
            TextField("Sample text", text: $template.slots[index].sample, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder)
            HStack {
                Text("Font").font(.system(size: 12))
                SearchablePick(title: "Font", options: TemplateFonts.all, selection: $template.slots[index].fontName)
            }
            Toggle("Fit the text to the box automatically", isOn: Binding(get: { slot.fontSize == 0 }, set: { template.slots[index].fontSize = $0 ? 0 : max(0.008, min(0.1, template.slots[index].h * 0.6)) }))
                .toggleStyle(.checkbox).font(.system(size: 12))
            if slot.fontSize > 0 {
                let points = Binding<Double>(get: { (template.slots[index].fontSize * 842).rounded() }, set: { template.slots[index].fontSize = max(0.004, min(0.4, $0 / 842)) })
                HStack(spacing: 8) {
                    Text("Size").font(.system(size: 12, weight: .semibold))
                    Stepper(value: points, in: 4...300, step: 1) { Text("\(Int(points.wrappedValue)) pt").font(.system(size: 12, design: .monospaced)) }
                }
                Slider(value: points, in: 6...160, step: 1)
                hint("This is the biggest the text gets. It still shrinks if it does not fit the box. (Points on an A4 page.)")
            }
            HStack(spacing: 10) {
                Toggle("Bold", isOn: $template.slots[index].bold).toggleStyle(.checkbox)
                Toggle("Italic", isOn: $template.slots[index].italic).toggleStyle(.checkbox)
                Toggle("CAPITALS", isOn: $template.slots[index].uppercase).toggleStyle(.checkbox)
            }.font(.system(size: 12))
            Picker("", selection: $template.slots[index].align) {
                Image(systemName: "text.alignleft").tag("left")
                Image(systemName: "text.aligncenter").tag("center")
                Image(systemName: "text.alignright").tag("right")
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                ColorPicker("Text colour", selection: color($template.slots[index].colorHex), supportsOpacity: false).font(.system(size: 12))
            }
            Toggle("Paint the shape behind the text", isOn: Binding(get: { !slot.fillHex.isEmpty }, set: { template.slots[index].fillHex = $0 ? "#FFE9A8" : "" }))
                .toggleStyle(.checkbox).font(.system(size: 12))
            if !slot.fillHex.isEmpty {
                ColorPicker("Shape colour", selection: color($template.slots[index].fillHex), supportsOpacity: false).font(.system(size: 12))
            }
        }
    }

    private func logoEditor(_ index: Int) -> some View {
        let slot = template.slots[index]
        return card("Logo") {
            Menu {
                ForEach(TemplateLogos.builtIn, id: \.name) { logo in
                    Button { template.slots[index].logo = logo.name } label: { Label(logo.name, systemImage: logo.symbol) }
                }
                Button { template.slots[index].logo = "KeyDo" } label: { Label("KeyDo", systemImage: "key.fill") }
                ForEach(store.uploadedLogos, id: \.self) { file in
                    Button { template.slots[index].logo = "file:" + file } label: { Label(file, systemImage: "photo") }
                }
            } label: { Label(slot.logo.hasPrefix("file:") ? "Your logo" : slot.logo, systemImage: "seal") }
                .menuStyle(.borderlessButton).fixedSize()
            Button { uploadLogo(addToTemplate: false, into: index) } label: { Label("Upload your logo\u{2026}", systemImage: "square.and.arrow.up") }
                .buttonStyle(.bordered).controlSize(.small)
            if !slot.logo.hasPrefix("file:") && slot.logo != "KeyDo" {
                ColorPicker("Logo colour", selection: color($template.slots[index].colorHex), supportsOpacity: false).font(.system(size: 12))
            }
            Toggle("Paint the shape behind it", isOn: Binding(get: { !slot.fillHex.isEmpty }, set: { template.slots[index].fillHex = $0 ? "#FFFFFF" : "" }))
                .toggleStyle(.checkbox).font(.system(size: 12))
            if !slot.fillHex.isEmpty {
                ColorPicker("Shape colour", selection: color($template.slots[index].fillHex), supportsOpacity: false).font(.system(size: 12))
            }
        }
    }

    // MARK: Try it

    private var fillCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            hint("This is exactly what an app makes. Type into the boxes below and watch the picture.")
            card("Fill the boxes") {
                if template.fieldKeys.isEmpty { hint("Add text or picture boxes in the Design tab first.") }
                ForEach(template.slots.filter { $0.kind != .logo }) { slot in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(slot.key).font(.system(size: 11, weight: .semibold)).foregroundStyle(Butter.cocoa)
                        if slot.kind == .text {
                            TextField(slot.sample, text: Binding(get: { testTexts[slot.id] ?? "" }, set: { testTexts[slot.id] = $0 })).textFieldStyle(.roundedBorder)
                        } else {
                            HStack {
                                Button { chooseTestPicture(slot) } label: { Label(testImages[slot.id] == nil ? "Choose a picture" : "Change picture", systemImage: "photo") }
                                if testImages[slot.id] != nil {
                                    Button("Clear") { testImages[slot.id] = nil; testVersion += 1 }
                                }
                            }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            }
            HStack {
                Button { exportPNG() } label: { Label("Download PNG", systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent).tint(Butter.coral)
                Button { copyPNG() } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
    }

    private func chooseTestPicture(_ slot: TemplateSlot) {
        guard let image = TemplateDialogs.openImage() else { return }
        testImages[slot.id] = image
        testVersion += 1
    }

    private func testInputs() -> (texts: [String: String], images: [String: NSImage]) {
        var texts: [String: String] = [:]
        var images: [String: NSImage] = [:]
        for (key, value) in formValues where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { texts[TemplateFill.normal(key)] = value }
        for slot in template.slots {
            if let value = testTexts[slot.id], !value.isEmpty { texts[TemplateFill.normal(slot.key)] = value }
            if let image = testImages[slot.id] { images[TemplateFill.normal(slot.key)] = image }
        }
        return (texts, images)
    }

    private func exportPNG() {
        let made = resolvedInputs(designing: false)
        guard let data = TemplateRenderer.pngData(template, base: base, texts: made.texts, images: made.images) else { message = "The picture could not be made."; return }
        message = TemplateDialogs.savePNG(data, name: template.name)
    }

    private func copyPNG() {
        let made = resolvedInputs(designing: false)
        guard let data = TemplateRenderer.pngData(template, base: base, texts: made.texts, images: made.images), let image = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        message = "Copied the picture."
    }

    // MARK: Actions

    private func refresh() {
        let made = resolvedInputs(designing: true)
        preview = TemplateRenderer.render(template, base: base, texts: made.texts, images: made.images, useSamples: true, maxSide: 1500)
        let live = resolvedInputs(designing: false)
        livePreview = TemplateRenderer.render(template, base: base, texts: live.texts, images: live.images, useSamples: true, maxSide: 1000)
    }

    private func uniqueKey(_ stem: String) -> String {
        var number = 1
        var key = stem
        while template.slots.contains(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) { number += 1; key = stem + String(number) }
        return key
    }

    private func addSlot(_ kind: TemplateSlotKind) {
        var slot = TemplateSlot(key: uniqueKey(kind == .image ? "photo" : "text"), kind: kind)
        if kind == .image { slot.w = 0.25; slot.h = 0.25 * CGFloat(template.pixelWidth) / max(1, CGFloat(template.pixelHeight)); slot.sample = "" }
        template.slots.append(slot)
        selectedID = slot.id
    }

    /// A new text box that holds a variable, a function or a dropdown of a collection.
    private func addElementBox(_ token: String, name: String) {
        if let collection = DesignElementTokens.mediaCollection(in: token) {
            pushUndo()
            addSlot(.image)
            if let index = selectedIndex { template.slots[index].key = uniqueKey(collection) }
            return
        }
        pushUndo()
        addSlot(.text)
        guard let index = selectedIndex else { return }
        template.slots[index].key = uniqueKey(name)
        addToken(index, token)
        if let variable = DesignElementTokens.plainVariable(token), !vars.keys.contains(where: { TemplateFill.normal($0) == TemplateFill.normal(variable) }) {
            vars[variable] = ""
            onVariablesChange?(vars)
        }
    }

    private func newVariableName() -> String {
        var number = 1
        var name = "variable"
        while vars.keys.contains(where: { TemplateFill.normal($0) == TemplateFill.normal(name) }) { number += 1; name = "variable\(number)" }
        return name
    }

    private func addLogo(_ name: String) {
        var slot = TemplateSlot(key: uniqueKey("logo"), kind: .logo)
        slot.logo = name
        slot.w = 0.14
        slot.h = 0.14 * CGFloat(template.pixelWidth) / max(1, CGFloat(template.pixelHeight))
        slot.cx = 0.15; slot.cy = 0.12
        template.slots.append(slot)
        selectedID = slot.id
    }

    private func uploadLogo(addToTemplate: Bool, into index: Int? = nil) {
        guard let url = TemplateDialogs.openLogo(), let name = store.addLogo(from: url) else { return }
        if addToTemplate { addLogo(name) } else if let index, index < template.slots.count { template.slots[index].logo = name }
    }

    private func deleteSlot(_ id: String) {
        template.slots.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    private func duplicateSlot(_ index: Int) {
        var copy = template.slots[index]
        copy.id = UUID().uuidString
        copy.key = uniqueKey(copy.key)
        copy.cx = clamp(copy.cx + 0.03); copy.cy = clamp(copy.cy + 0.03)
        template.slots.append(copy)
        selectedID = copy.id
    }

    private func addCorner(_ index: Int) {
        var points = template.slots[index].points
        guard points.count >= 4 else { return }
        let middle = [(points[0] + points[2]) / 2, (points[1] + points[3]) / 2]
        points.insert(contentsOf: middle, at: 2)
        template.slots[index].points = points
    }

    private func removeCorner(_ index: Int) {
        var points = template.slots[index].points
        guard points.count > 6 else { return }
        points.removeLast(2)
        template.slots[index].points = points
    }

    // MARK: Changing the picture

    private func pushUndo() {
        undo.append(Snapshot(image: base, slots: template.slots))
        if undo.count > 8 { undo.removeFirst() }
    }

    private func applyBase(_ image: NSImage) {
        base = image
        store.setPicture(image, for: template)
        refresh()
    }

    private func undoLast() {
        guard let last = undo.popLast() else { return }
        template.slots = last.slots
        applyBase(last.image)
        message = "Undone."
    }

    private func startAgain() {
        guard let original = store.original(for: template) else { message = "The original picture is not available."; return }
        pushUndo()
        applyBase(original)
        message = "Back to the picture you uploaded."
    }

    private func replacePicture() {
        guard let picked = TemplateDialogs.openImage(title: "Choose a new picture for this template") else { return }
        pushUndo()
        let fitted = TemplateImages.limited(picked, maxSide: 3200)
        let size = TemplateImages.pixelSize(fitted)
        template.pixelWidth = Int(size.width)
        template.pixelHeight = Int(size.height)
        store.setOriginal(fitted, for: template)
        applyBase(fitted)
        message = "Picture replaced. Your boxes stayed where they were."
    }

    /// Erases exactly inside the shape the person drew. Nothing outside it is touched.
    private func eraseShape(_ points: [CGPoint]) {
        let xs = points.map { $0.x }, ys = points.map { $0.y }
        guard points.count >= 3, let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(), maxX - minX > 0.002, maxY - minY > 0.002 else { return }
        pushUndo()
        applyBase(TemplateEraser.erase(base, shapes: [points], pad: false))
        message = "Erased inside the shape. Undo brings it back."
    }

    private func eraseArea(_ rect: CGRect) {
        guard rect.width > 0.002, rect.height > 0.002 else { return }
        pushUndo()
        applyBase(TemplateEraser.erase(base, rects: [rect]))
        message = "Erased."
    }

    private func eraseAllText(makeBoxes: Bool) {
        guard busy == nil else { return }
        let current = base
        busy = "Finding the text\u{2026}"
        Task { @MainActor in
            let found = await TemplateEraser.detect(in: current)
            guard !found.isEmpty else {
                busy = nil
                message = "No text was found in this picture."
                return
            }
            pushUndo()
            let erased = TemplateEraser.erase(current, rects: found.map { $0.rect })
            if makeBoxes { addBoxes(from: found, over: current) }
            applyBase(erased)
            busy = nil
            message = "Removed \(found.count) lines of text." + (makeBoxes ? " Each one is now a box you can edit." : "")
        }
    }

    private func addBoxes(from found: [DetectedText], over picture: NSImage) {
        let ordered = found.sorted { abs($0.rect.minY - $1.rect.minY) > 0.01 ? $0.rect.minY < $1.rect.minY : $0.rect.minX < $1.rect.minX }
        for line in ordered.prefix(60) {
            var slot = TemplateSlot(key: uniqueKey("text"), kind: .text)
            slot.cx = Double(line.rect.midX)
            slot.cy = Double(line.rect.midY)
            slot.w = min(1, Double(line.rect.width) * 1.06 + 0.01)
            slot.h = min(1, Double(line.rect.height) * 1.18)
            slot.sample = line.text
            slot.align = "left"
            slot.colorHex = TemplateEraser.isLight(picture, around: line.rect) ? "#1F2A2E" : "#FFFFFF"
            // Left aligned text starts where the old text started.
            slot.cx = Double(line.rect.minX) + slot.w / 2 - 0.003
            template.slots.append(slot)
        }
        selectedID = nil
    }
}

// MARK: - AppDesigner additions: live content, variables, spoken commands

struct DesignFunction: Identifiable {
    let title: String
    let token: String
    var id: String { token }
    static let items: [DesignFunction] = [
        DesignFunction(title: "Today's date", token: "{=TODAY()}"), DesignFunction(title: "Time now", token: "{=time}"),
        DesignFunction(title: "Date and time", token: "{=now}"), DesignFunction(title: "Month", token: "{=month}"),
        DesignFunction(title: "Year", token: "{=year}"), DesignFunction(title: "Weekday", token: "{=weekday}"),
        DesignFunction(title: "Date + 7 days", token: "{=Date+7}"), DesignFunction(title: "Date + 30 days", token: "{=Date+30}")
    ]
}

extension TemplateDesignerView {
    func luminance(_ hex: String) -> Double {
        guard let color = NSColor(templateHex: hex).usingColorSpace(.deviceRGB) else { return 1 }
        return 0.299 * Double(color.redComponent) + 0.587 * Double(color.greenComponent) + 0.114 * Double(color.blueComponent)
    }

    func mixWithWhite(_ hex: String, _ amount: Double) -> String {
        guard let color = NSColor(templateHex: hex).usingColorSpace(.deviceRGB) else { return hex }
        func blend(_ value: CGFloat) -> CGFloat { value * (1 - CGFloat(amount)) + CGFloat(amount) }
        return NSColor(srgbRed: blend(color.redComponent), green: blend(color.greenComponent), blue: blend(color.blueComponent), alpha: 1).templateHex
    }

    /// Text and pictures for every box: what an app would give it, or its live content worked out.
    func resolvedInputs(designing: Bool) -> (texts: [String: String], images: [String: NSImage]) {
        let inputs = testInputs()
        let values = DesignFill.merge(vars, inputs.texts)
        let made = TemplateFill.resolved(template, values: values, clips: AppDesignContext.shared.clips, designing: designing)
        var images = made.images
        for (key, image) in inputs.images { images[key] = image }
        return (made.texts, images)
    }

    // MARK: Command bar

    var commandBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button { toggleListening() } label: {
                    Image(systemName: voice.isListening ? "mic.fill" : "mic")
                        .foregroundStyle(voice.isListening ? Color.white : Butter.coral)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(voice.isListening ? Butter.coral : Color.white))
                        .overlay(Circle().stroke(Butter.coral.opacity(voice.isListening ? 0.4 + voice.level * 0.6 : 1), lineWidth: 1.5 + CGFloat(voice.level) * 4))
                }
                .buttonStyle(.plain).help(voice.isListening ? "Stop listening" : "Listen: say what to change")
                Picker("", selection: Binding(get: { commandLocale }, set: { value in commandLocale = value; voice.changeLanguage(value) })) {
                    Text("English").tag("en-IN")
                    Text("\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}").tag("hi-IN")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 118).help("Language the command mic listens in")
                TextField("Say or type a change, like \u{201C}make the text pink\u{201D} or \u{201C}go to page 2\u{201D}", text: $commandText)
                    .textFieldStyle(.roundedBorder).focused($commandFocused)
                    .onSubmit { submitCommand() }
                Button("Do it") { submitCommand() }.buttonStyle(.borderedProminent).tint(Butter.coral).disabled(commandText.trimmingCharacters(in: .whitespaces).isEmpty)
                Button { undoLast() } label: { Image(systemName: "arrow.uturn.backward") }.buttonStyle(.bordered).disabled(undo.isEmpty).help("Undo")
            }
            if !voice.errorMessage.isEmpty {
                Text(voice.errorMessage).font(.system(size: 11)).foregroundStyle(.red)
            } else if voice.isListening || !heard.isEmpty {
                Text(voice.isListening ? "Listening\u{2026} \(voice.heard.isEmpty ? heard : voice.heard)" : "Heard: \(heard)").font(.system(size: 11)).foregroundStyle(Butter.cocoa.opacity(0.75)).lineLimit(1)
            }
        }
        .padding(10).background(Color(nsColor: .windowBackgroundColor))
    }

    func submitCommand() {
        let text = commandText
        commandText = ""
        runCommand(text)
        commandFocused = true
    }

    func toggleListening() {
        if voice.isListening { voice.stop(); message = "Mic off."; return }
        message = "Listening. Say one change at a time."
        voice.start(localeIdentifier: commandLocale, commitDelay: 0.9) { text in runCommand(text) }
    }

    // MARK: Variables and live content

    var variablesCard: some View {
        card("Variables") {
            if DesignDataType.names(vars).isEmpty { hint("Variables are values that change for each use, like company or amount. Say \u{201C}replace Acme Ltd with variable company\u{201D}.") }
            ForEach(DesignDataType.names(vars), id: \.self) { key in
                let type = DesignDataType.of(key, in: vars)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(key).font(.system(size: 12, weight: .semibold)).foregroundStyle(Butter.cocoa).frame(width: 84, alignment: .leading).lineLimit(1)
                        TextField(type.example, text: Binding(get: { vars[key] ?? "" }, set: { vars[key] = $0; onVariablesChange?(vars) }))
                            .textFieldStyle(.roundedBorder).onSubmit { tidyVariable(key) }
                        Button { vars[key] = nil; vars[DesignDataType.key(key)] = nil; onVariablesChange?(vars) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain)
                    }
                    HStack(spacing: 6) {
                        Menu {
                            ForEach(DesignDataType.allCases) { option in
                                Button { setType(option, for: key) } label: { Label(option.title, systemImage: option.symbol) }
                            }
                        } label: { Label(type.title, systemImage: type.symbol).font(.system(size: 11)) }
                        .menuStyle(.borderlessButton).fixedSize()
                        if type != .text && type != .long { DesignTypeNote(type: type, text: vars[key] ?? "") }
                    }
                }
            }
            HStack {
                TextField("New variable name", text: $newVariable).textFieldStyle(.roundedBorder)
                Button("Add") {
                    let name = newVariable.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    vars[name] = vars[name] ?? ""
                    onVariablesChange?(vars)
                    newVariable = ""
                }.disabled(newVariable.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }

    func setType(_ type: DesignDataType, for name: String) {
        DesignDataType.set(type, for: name, in: &vars)
        tidyVariable(name)
        onVariablesChange?(vars)
    }

    /// Turns a box that is filled by a variable into fixed text, or fixed media when the box is a picture.
    func makeFixed(_ index: Int) {
        guard index < template.slots.count else { return }
        var slot = template.slots[index]
        let names = DesignDataType.names(vars)
        if slot.kind == .image {
            let value = vars[slot.key] ?? vars[TemplateFill.normal(slot.key)] ?? ""
            guard !value.isEmpty else { message = "Give this picture a ready value first (a shortcut name or a file)."; return }
            pushUndo(); slot.content = value; slot.sample = ""
            template.slots[index] = slot
            message = "This picture is now fixed."
            return
        }
        var text = slot.content ?? "{{\(slot.key)}}"
        var changed = false
        for name in names {
            let token = "{{\(name)}}"
            if text.contains(token) {
                let value = vars[name] ?? ""
                guard !value.isEmpty else { message = "\(name) has no ready value yet. Type one in the variables list first."; return }
                text = text.replacingOccurrences(of: token, with: value); changed = true
            }
        }
        guard changed else { message = "Nothing to fix here: this box has no variable in it."; return }
        pushUndo(); slot.content = text; slot.sample = text
        template.slots[index] = slot
        message = "Those variables are now fixed text."
    }

    func tidyVariable(_ name: String) {
        let type = DesignDataType.of(name, in: vars)
        let check = type.check(vars[name] ?? "")
        if check.ok, check.clean != (vars[name] ?? "") { vars[name] = check.clean }
        onVariablesChange?(vars)
    }

    func addToken(_ index: Int, _ rawToken: String) {
        guard index < template.slots.count else { return }
        var token = rawToken
        var replaces = false
        if let pick = WishPick.parse(String(rawToken.dropFirst(2).dropLast(2))) {
            token = WishPick.token(collection: WishPick.canonicalCollection(pick.collection), variable: rawToken.contains("/$") ? pick.variable : nil)
            replaces = true
        }
        pushUndo()
        if replaces && template.slots[index].kind != .image {
            template.slots[index].content = token
            return
        }
        if template.slots[index].kind == .image {
            template.slots[index].content = token
        } else {
            let sample = template.slots[index].sample == "Your text" ? "" : template.slots[index].sample
            let old = template.slots[index].content ?? sample
            template.slots[index].content = old.isEmpty ? token : old + " " + token
        }
    }

    func chooseSourceFile(_ index: Int) {
        let panel = NSOpenPanel()
        panel.title = "Choose a picture or video"
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, index < template.slots.count else { return }
        pushUndo()
        template.slots[index].content = url.path
    }

    func contentEditor(_ index: Int) -> some View {
        let slot = template.slots[index]
        let names = Array(Set(DesignDataType.names(vars)).union(template.slots.map { $0.key })).sorted()
        return card(slot.kind == .text ? "Live content (shown instead of the sample)" : "Picture or video source") {
            TextField(slot.kind == .text ? "Type text, then add live values with the buttons" : "Shortcut name, a file, or {{variable}}",
                      text: Binding(get: { template.slots[index].content ?? "" }, set: { template.slots[index].content = $0.isEmpty ? nil : $0 }), axis: .vertical)
                .lineLimit(1...5).textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Menu("Variable") {
                    ForEach(names, id: \.self) { name in Button(name) { addToken(index, "{{\(name)}}") } }
                    Divider()
                    Button("New variable") {
                        addToken(index, "{{newvariable}}")
                        vars["newvariable"] = vars["newvariable"] ?? ""
                        onVariablesChange?(vars)
                    }
                }
                SourcePickerButton(title: slot.kind == .image ? "Pick picture" : "Collection / shortcut", symbol: "tray.full", mediaOnly: slot.kind == .image) { addToken(index, $0) }
                Menu("Function") { ForEach(DesignFunction.items) { item in Button(item.title) { addToken(index, item.token) } } }
                if slot.kind == .image { Button("File") { chooseSourceFile(index) } }
            }
            .menuStyle(.borderlessButton).controlSize(.small)
            hint(slot.kind == .text ? "Text shrinks to fit the box. {{@Customers/Rahul/email}} reads a collection item; {=Date+7} is a function." : "Pictures and videos fill the box shape (a video shows its first frame).")
        }
    }

    @ViewBuilder func collectionMenu(_ index: Int) -> some View {
        let records = AppDesignContext.shared.records
        let names = Array(Set(records.map { $0.collection })).sorted()
        if names.isEmpty { Text("No collections yet") }
        ForEach(Array(names.prefix(30)), id: \.self) { name in
            Menu(name) {
                ForEach(Array(records.filter { $0.collection == name }.prefix(30)), id: \.id) { record in
                    let reference = record.alias.isEmpty ? record.name : record.alias
                    Menu(record.name) {
                        Button("Name") { addToken(index, "{{@\(name)/\(reference)}}") }
                        ForEach(record.values.keys.sorted(), id: \.self) { field in
                            Button(field) { addToken(index, "{{@\(name)/\(reference)/\(field)}}") }
                        }
                    }
                }
            }
        }
    }

    // MARK: Commands

    func runCommand(_ raw: String) {
        let text = DesignSpeech.normalize(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        heard = text
        var notes: [String] = []
        DesignFormulaSpeech.variables = Array(Set(DesignDataType.names(vars)).union(template.slots.map { $0.key }))
        for sentence in DesignVoiceTarget.split(text) {
            if let hit = DesignVoiceTarget.find(sentence, slots: template.slots) {
                // The sentence names a box: select it, then do the rest of the sentence to it.
                selectedID = hit.slot.id
                var actions = hit.rest.isEmpty ? [] : DesignCommand.parse(hit.rest)
                if actions.isEmpty { notes.append("Selected \(hit.slot.key).") ; continue }
                if case .unknown = actions[0], let set = DesignVoiceTarget.setAction(hit) { actions = [set] }
                for action in actions {
                    if case .color(let hex, .page) = action { notes.append(perform(.color(hex, .shape))) } else { notes.append(perform(action)) }
                }
                continue
            }
            for action in DesignCommand.parse(sentence) {
                if case .unknown(let loose) = action, let filled = tryGuide.acceptLoose(loose) { notes.append(filled) } else { notes.append(perform(action)) }
            }
        }
        let joined = notes.filter { !$0.isEmpty }.joined(separator: " ")
        if !joined.isEmpty { message = joined }
        refresh()
    }

    private var needBox: String { "Click a box first, or say \u{201C}select <name>\u{201D}." }
    private var noPages: String { "Pages work inside an AppDesigner design." }

    func go(to index: Int) -> String {
        guard let info = pageInfo else { return noPages }
        guard index >= 0, index < info.count else { return "There is no page \(index + 1). This design has \(info.count)." }
        store.save(template)
        onGoToPage?(index)
        return "Page \(index + 1)."
    }

    private func textTargets() -> [Int] {
        if let index = selectedIndex, template.slots[index].kind == .text { return [index] }
        return template.slots.indices.filter { template.slots[$0].kind == .text }
    }

    private func allTextIndices() -> [Int] { template.slots.indices.filter { template.slots[$0].kind == .text } }

    private func setPageColor(_ hex: String) {
        let size = TemplateImages.pixelSize(base)
        guard let rep = TemplateImages.bitmap(width: Int(size.width), height: Int(size.height)),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(templateHex: hex).setFill()
        NSRect(x: 0, y: 0, width: size.width, height: size.height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: size.width, height: size.height))
        image.addRepresentation(rep)
        applyBase(image)
        let dark = luminance(hex) < 0.45
        for index in allTextIndices() {
            let level = luminance(template.slots[index].colorHex)
            if dark && level < 0.45 { template.slots[index].colorHex = "#FFFFFF" }
            if !dark && level > 0.75 { template.slots[index].colorHex = "#1F2A2E" }
        }
    }

    private func applyTheme(_ hex: String) {
        let dark = luminance(hex) < 0.4
        setPageColor(dark ? hex : mixWithWhite(hex, 0.88))
        for index in allTextIndices() {
            template.slots[index].colorHex = dark ? "#FFFFFF" : (template.slots[index].bold ? hex : "#1F2A2E")
        }
    }

    func perform(_ action: DesignAction) -> String {
        switch action {
        case .undo:
            if undo.isEmpty { return "Nothing to undo." }
            undoLast()
            return "Undone."
        case .release:
            guard let onRelease else { return "Release works inside an AppDesigner design." }
            store.save(template)
            return onRelease()
        case .save:
            store.save(template)
            return "Saved."
        case .tryIt:
            return "The live result is on the right. Fill the form there to try it."
        case .fontSize(let points):
            pushUndo()
            for index in textTargets() { template.slots[index].fontSize = max(0.004, min(0.4, points / 842)) }
            return "Font size \(Int(points)) pt."
        case .fontScale(let factor):
            pushUndo()
            for index in textTargets() {
                let base = template.slots[index].fontSize > 0 ? template.slots[index].fontSize : min(0.06, template.slots[index].h * 0.6)
                template.slots[index].fontSize = max(0.004, min(0.4, base * factor))
            }
            return "Font size changed."
        case .outputFormat(let format):
            outputFormat = format.rawValue
            onOutputFormatChange?(format.rawValue)
            return "The app will make \(format.title)."
        case .appName(let name):
            guard let onRename else { return "The app name is set from inside an app design." }
            let done = onRename(name)
            appName = done.name
            if !done.command.isEmpty { commandWord = done.command }
            return "Renamed to \u{201C}\(done.name)\u{201D}. Run it with \\\(done.command)-"
        case .commandWord(let word):
            guard let onCommandChange else { return "Commands are set from inside an app design." }
            commandWord = onCommandChange(word)
            return "Type \\\(commandWord)- and a name in any app to run this app."
        case .designMode:
            mode = .design
            return "Back to designing."
        case .goPage(let number): return go(to: number - 1)
        case .nextPage: return pageInfo.map { go(to: $0.index) } ?? noPages
        case .previousPage: return pageInfo.map { go(to: $0.index - 2) } ?? noPages
        case .firstPage: return go(to: 0)
        case .lastPage: return pageInfo.map { go(to: $0.count - 1) } ?? noPages
        case .addPage:
            guard let onAddPage else { return noPages }
            store.save(template)
            onAddPage()
            return "Added a page."
        case .addBox(let kind, let name, let logo):
            pushUndo()
            switch kind {
            case .text: addSlot(.text)
            case .image: addSlot(.image)
            case .logo: addLogo(logo ?? "Star")
            }
            if let name, kind != .logo, let index = selectedIndex { template.slots[index].key = uniqueKey(name) }
            return "Added a \(kind.title.lowercased()) box. Drag it where you want it."
        case .deleteBox:
            guard let index = selectedIndex else { return needBox }
            pushUndo()
            deleteSlot(template.slots[index].id)
            return "Deleted the box."
        case .select(let name):
            let key = TemplateFill.normal(name)
            if !key.isEmpty, let found = template.slots.first(where: { TemplateFill.normal($0.key) == key }) ?? template.slots.first(where: { TemplateFill.normal($0.key).contains(key) }) {
                selectedID = found.id
                return "Selected \(found.key)."
            }
            if let number = Int(name.filter { $0.isNumber }), number >= 1, number <= template.slots.count {
                selectedID = template.slots[number - 1].id
                return "Selected box \(number)."
            }
            return "I could not find a box called \(name)."
        case .selectOffset(let step):
            guard !template.slots.isEmpty else { return "There are no boxes." }
            let count = template.slots.count
            let current = selectedIndex ?? (step > 0 ? -1 : 0)
            let next = ((current + step) % count + count) % count
            selectedID = template.slots[next].id
            return "Selected \(template.slots[next].key)."
        case .move(let dx, let dy):
            guard let index = selectedIndex else { return needBox }
            pushUndo()
            template.slots[index].cx = min(1, max(0, template.slots[index].cx + dx))
            template.slots[index].cy = min(1, max(0, template.slots[index].cy + dy))
            return ""
        case .center:
            guard let index = selectedIndex else { return needBox }
            pushUndo()
            template.slots[index].cx = 0.5
            return "Centred."
        case .scale(let w, let h):
            guard let index = selectedIndex else { return needBox }
            pushUndo()
            template.slots[index].w = min(1, template.slots[index].w * w)
            template.slots[index].h = min(1, template.slots[index].h * h)
            return ""
        case .angleSet(let value):
            guard let index = selectedIndex else { return needBox }
            pushUndo()
            template.slots[index].angle = max(-180, min(180, value))
            return "Angle \(Int(value))\u{00B0}."
        case .angleAdd(let value):
            guard let index = selectedIndex else { return needBox }
            pushUndo()
            var angle = template.slots[index].angle + value
            while angle > 180 { angle -= 360 }
            while angle < -180 { angle += 360 }
            template.slots[index].angle = angle
            return "Angle \(Int(angle))\u{00B0}."
        case .shape(let shape):
            guard let index = selectedIndex else { return needBox }
            pushUndo()
            template.slots[index].shape = shape
            return "Now a \(shape.title.lowercased())."
        case .bold(let on):
            pushUndo()
            for index in textTargets() { template.slots[index].bold = on }
            return on ? "Bold." : "Not bold."
        case .italic(let on):
            pushUndo()
            for index in textTargets() { template.slots[index].italic = on }
            return on ? "Italic." : "Not italic."
        case .caps(let on):
            pushUndo()
            for index in textTargets() { template.slots[index].uppercase = on }
            return on ? "Capitals." : "Normal case."
        case .align(let value):
            pushUndo()
            for index in textTargets() { template.slots[index].align = value }
            return "Aligned \(value)."
        case .font(let name, let all):
            var chosen = name
            if chosen.isEmpty {
                chosen = selectedIndex.map { template.slots[$0].fontName } ?? TemplateFonts.all.first ?? "Helvetica Neue"
            } else {
                let lower = name.lowercased()
                guard let found = TemplateFonts.all.first(where: { $0.lowercased() == lower })
                        ?? TemplateFonts.all.first(where: { $0.lowercased().contains(lower) || lower.contains($0.lowercased()) }) else {
                    return "I do not have a font called \(name). Try " + TemplateFonts.all.prefix(5).joined(separator: ", ") + "."
                }
                chosen = found
            }
            pushUndo()
            for index in (all ? allTextIndices() : textTargets()) { template.slots[index].fontName = chosen }
            return "Font is now \(chosen)."
        case .color(let hex, let target):
            pushUndo()
            switch target {
            case .text:
                for index in textTargets() { template.slots[index].colorHex = hex }
                return "Text colour changed."
            case .allText:
                for index in allTextIndices() { template.slots[index].colorHex = hex }
                return "All text colour changed."
            case .shape:
                let indices = selectedIndex.map { [$0] } ?? Array(template.slots.indices)
                for index in indices { template.slots[index].fillHex = hex }
                return "Shape colour changed."
            case .logo:
                for index in template.slots.indices where template.slots[index].kind == .logo && (selectedIndex == nil || selectedIndex == index) {
                    template.slots[index].colorHex = hex
                }
                return "Logo colour changed."
            case .page:
                setPageColor(hex)
                return "Page colour changed."
            case .theme:
                applyTheme(hex)
                return "Theme changed."
            }
        case .setText(let value):
            guard let index = selectedIndex else { return needBox }
            guard template.slots[index].kind == .text else { return "That box holds a picture. Select a text box." }
            pushUndo()
            template.slots[index].content = value
            template.slots[index].sample = value
            return "Text changed."
        case .insertToken(let rawToken):
            let token = DesignElementTokens.refine(rawToken)
            if selectedIndex == nil {
                addElementBox(token, name: DesignElementTokens.boxName(token))
                return "Added a box for it. Drag it where you want it."
            }
            guard let index = selectedIndex else { return needBox }
            guard template.slots[index].kind != .logo else { return "Logos do not hold text." }
            addToken(index, token)
            return "Added to \(template.slots[index].key)."
        case .replace(let old, let new, let variable):
            pushUndo()
            var here = 0
            for index in template.slots.indices where template.slots[index].kind == .text {
                let source = template.slots[index].content ?? template.slots[index].sample
                if source.range(of: old, options: .caseInsensitive) != nil {
                    template.slots[index].content = source.replacingOccurrences(of: old, with: new, options: .caseInsensitive)
                    here += 1
                }
            }
            let elsewhere = onReplaceElsewhere?(old, new) ?? 0
            if let variable, here + elsewhere > 0 {
                vars[variable] = vars[variable] ?? old
                onVariablesChange?(vars)
            }
            if here + elsewhere == 0 { return "I could not find \u{201C}\(old)\u{201D} in any text box." }
            return "Replaced in \(here) box\(here == 1 ? "" : "es")" + (elsewhere > 0 ? " and \(elsewhere) on other pages." : ".")
        case .variable(let name, let value):
            vars[name] = value
            onVariablesChange?(vars)
            return "Variable \(name) starts as \u{201C}\(value)\u{201D}."
        case .variableType(let name, let type):
            guard let key = vars.keys.first(where: { !DesignDataType.isHidden($0) && TemplateFill.normal($0) == TemplateFill.normal(name) }) else { return "There is no variable called \(name). Add it first." }
            setType(type, for: key)
            return "\(key) now takes \(type.title.lowercased()) only."
        case .makeTypedVariable(let name, let type):
            let made = perform(.makeVariable(name))
            if vars[name] != nil { setType(type, for: name) }
            return made + " It takes \(type.title.lowercased()) only."
        case .makeVariable(let name):
            guard let index = selectedIndex else { return needBox }
            guard template.slots[index].kind == .text else { return "Select a text box." }
            pushUndo()
            let old = template.slots[index].content ?? template.slots[index].sample
            vars[name] = vars[name] ?? old
            onVariablesChange?(vars)
            template.slots[index].content = "{{\(name)}}"
            return "That box is now the variable \(name)."
        case .imageFrom(let name):
            guard let index = selectedIndex, template.slots[index].kind == .image else { return "Select a picture box first." }
            pushUndo()
            template.slots[index].content = name
            return "The picture box shows \(name)."
        case .unknown(let text):
            return "I did not understand \u{201C}\(text)\u{201D}. " + DesignCommand.help
        }
    }
}

// MARK: - Library (drag and drop), live preview and drop handling

struct SlotDropDelegate: DropDelegate {
    var size: CGSize
    var handle: (String, CGPoint) -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.plainText, .fileURL]) }

    func performDrop(info: DropInfo) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        let point = CGPoint(x: info.location.x / size.width, y: info.location.y / size.height)
        let handler = handle
        let files = info.itemProviders(for: [.fileURL])
        if !files.isEmpty {
            for provider in files {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    var url: URL?
                    if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) } else if let direct = item as? URL { url = direct }
                    guard let url else { return }
                    DispatchQueue.main.async { handler("keydo-media:" + url.path, point) }
                }
            }
            return true
        }
        let texts = info.itemProviders(for: [.plainText])
        for provider in texts {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let string = object as? NSString else { return }
                let value = string as String
                DispatchQueue.main.async { handler(value, point) }
            }
        }
        return !texts.isEmpty
    }
}

extension TemplateDesignerView {
    // MARK: Putting things on the page

    func slotIndex(at point: CGPoint) -> Int? {
        let width = CGFloat(template.pixelWidth), height = CGFloat(template.pixelHeight)
        for index in template.slots.indices.reversed() {
            let slot = template.slots[index]
            let dx = (point.x - CGFloat(slot.cx)) * width, dy = (point.y - CGFloat(slot.cy)) * height
            let local = rotated(CGPoint(x: dx, y: dy), -slot.angle * .pi / 180)
            if abs(local.x) <= CGFloat(slot.w) * width / 2, abs(local.y) <= CGFloat(slot.h) * height / 2 { return index }
        }
        return nil
    }

    /// A dragged or clicked library item: a {{token}} for text, "keydo-media:<shortcut or file>" for pictures and videos,
    /// "keydo-logo:<name>" for logos. With a point it goes onto the box there (or makes a new box); without one it goes
    /// onto the selected box.
    @discardableResult func applyPayload(_ payload: String, at point: CGPoint?) -> String {
        var target: Int?
        if let point { target = slotIndex(at: point) } else { target = selectedIndex }
        let spot = point ?? CGPoint(x: 0.5, y: 0.5)
        let aspect = Double(template.pixelWidth) / Double(max(1, template.pixelHeight))
        if payload.hasPrefix("keydo-logo:") {
            let name = String(payload.dropFirst("keydo-logo:".count))
            pushUndo()
            if let index = target, template.slots[index].kind == .logo {
                template.slots[index].logo = name
                message = "Logo changed."
                return message
            }
            var box = TemplateSlot(key: uniqueKey("logo"), kind: .logo)
            box.logo = name
            box.cx = Double(spot.x); box.cy = Double(spot.y); box.w = 0.14; box.h = 0.14 * aspect
            template.slots.append(box)
            selectedID = box.id
            message = "Added a logo."
            return message
        }
        if payload.hasPrefix("keydo-media:") {
            let media = String(payload.dropFirst("keydo-media:".count))
            if media.hasPrefix("/") {
                let ext = URL(fileURLWithPath: media).pathExtension.lowercased()
                let usable = ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff"] + TemplateFill.videoTypes
                guard usable.contains(ext) else { message = "Drop a picture or video file here."; return message }
            }
            pushUndo()
            if let index = target, template.slots[index].kind != .logo {
                template.slots[index].kind = .image
                template.slots[index].content = media
                selectedID = template.slots[index].id
                message = "That box now shows the picture or video."
                return message
            }
            var box = TemplateSlot(key: uniqueKey("photo"), kind: .image)
            box.content = media
            box.sample = ""
            box.cx = Double(spot.x); box.cy = Double(spot.y); box.w = 0.3; box.h = 0.3 * aspect
            template.slots.append(box)
            selectedID = box.id
            message = "Added a picture box."
            return message
        }
        if let index = target, template.slots[index].kind != .logo {
            addToken(index, payload)
            selectedID = template.slots[index].id
            message = "Added to \(template.slots[index].key)."
            return message
        }
        pushUndo()
        let stem = String(payload.filter { $0.isLetter || $0.isNumber }.prefix(12))
        var box = TemplateSlot(key: uniqueKey(stem.isEmpty ? "text" : stem), kind: .text)
        box.content = payload
        box.sample = payload
        box.cx = Double(spot.x); box.cy = Double(spot.y); box.w = 0.5; box.h = 0.08
        template.slots.append(box)
        selectedID = box.id
        message = "Added a new box."
        return message
    }

    // MARK: Library

    func chip(_ title: String, _ symbol: String, _ payload: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().stroke(Butter.honey, lineWidth: 1))
        .foregroundStyle(Butter.cocoa)
        .onDrag { NSItemProvider(object: payload as NSString) }
        .onTapGesture { applyPayload(payload, at: nil) }
        .help("Drag onto the page, or click to add to the selected box")
    }

    private func chipGrid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) { content() }
    }

    func shortcutChip(_ clip: Clip) -> some View {
        let isMedia = !clip.files.isEmpty
        return chip(clip.name.isEmpty ? clip.key : clip.name, isMedia ? "photo" : "text.quote", isMedia ? "keydo-media:" + clip.key : "{{shortcut:\(clip.key)}}")
    }

    var libraryPanel: some View {
        let context = AppDesignContext.shared
        return VStack(alignment: .leading, spacing: 10) {
            hint("Pick a category and a subcategory, then add it. The person chooses the exact item when the app runs. Select a box first to put it in that box.")
            libraryGroups(context)
        }
    }

    /// Category, then subcategory. That is as deep as a template needs to go.
    @ViewBuilder private func subcategoryPicker(_ context: AppDesignContext) -> some View {
        let tree = context.collectionTree
        if tree.isEmpty {
            hint("Open the AppDesigner from the main app to see your collections here.")
        } else {
            let category = tree.first(where: { $0.category == libCategory }) ?? tree[0]
            let sub = category.names.contains(libSub) ? libSub : (category.names.first ?? "")
            let fields = Array(Set(context.records.filter { $0.collection.caseInsensitiveCompare(sub) == .orderedSame }.prefix(20).flatMap { $0.values.keys })).sorted()
            VStack(alignment: .leading, spacing: 6) {
                Text("Category").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                SearchablePick(title: "Choose a category", options: tree.map { $0.category }, symbol: { _ in "folder" }, selection: Binding(get: { category.category }, set: { value in
                    libCategory = value
                    libSub = tree.first(where: { $0.category == value })?.names.first ?? ""
                    libField = "name"
                }))
                Text("Subcategory").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                SearchablePick(title: "Choose a subcategory", options: category.names, symbol: { MediaFinder.isMediaCollection($0) ? "photo.on.rectangle" : "list.bullet.rectangle" },
                               selection: Binding(get: { sub }, set: { value in libSub = value; libField = "name" }))
                if !fields.isEmpty && WishPick.clips(in: sub).isEmpty {
                    Text("Show").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    SearchablePick(title: "Name", options: ["name"] + fields, selection: $libField)
                }
                Button { addSubcategory(sub, fields: fields) } label: { Label("Add \(sub) to the page", systemImage: "plus.circle.fill") }
                    .buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.small).disabled(sub.isEmpty)
            }
        }
    }

    private func addSubcategory(_ name: String, fields: [String]) {
        var token = DesignElementTokens.refine("{{wish:\(name)}}")
        if token.hasPrefix("{{@"), libField != "name", fields.contains(libField) {
            token = "{{@\(name)/$\(TemplateFill.normal(name))/\(libField)}}"
        }
        if let index = selectedIndex, template.slots[index].kind != .logo { addToken(index, token) } else { addElementBox(token, name: name) }
    }

    @ViewBuilder private func libraryGroups(_ context: AppDesignContext) -> some View {
        subcategoryPicker(context)
        DisclosureGroup("Variables") {
            VStack(alignment: .leading, spacing: 6) {
                chipGrid { ForEach(DesignDataType.names(vars), id: \.self) { chip($0, DesignDataType.of($0, in: vars).symbol, "{{\($0)}}") } }
                if DesignDataType.names(vars).isEmpty { hint("No variables yet. Add one below, or say \u{201C}make this a variable called name\u{201D}.") }
                if onVariablesChange != nil {
                    HStack {
                        TextField("New variable", text: $newVariable).textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let name = newVariable.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            vars[name] = vars[name] ?? ""
                            onVariablesChange?(vars)
                            newVariable = ""
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
        DisclosureGroup("Functions") {
            VStack(alignment: .leading, spacing: 8) {
                chipGrid { ForEach(DesignFunction.items) { chip($0.title, "function", $0.token) } }
                FunctionPickerList { applyPayload($0, at: nil) }
            }
        }
        DisclosureGroup("Pictures and videos") {
            VStack(alignment: .leading, spacing: 6) {
                Button { chooseNewMedia() } label: { Label("Add a picture or video\u{2026}", systemImage: "photo.badge.plus") }.buttonStyle(.bordered).controlSize(.small)
                hint("Or drag files from Finder onto the page. Collections of pictures are in the subcategory list above.")
            }
        }
        DisclosureGroup("Logos") {
            chipGrid {
                chip("KeyDo", "key.fill", "keydo-logo:KeyDo")
                ForEach(TemplateLogos.builtIn, id: \.name) { chip($0.name, $0.symbol, "keydo-logo:" + $0.name) }
                ForEach(TemplateStore.shared.uploadedLogos, id: \.self) { chip($0, "photo", "keydo-logo:file:" + $0) }
            }
        }
    }

    @ViewBuilder private func collectionContents(_ name: String, _ context: AppDesignContext) -> some View {
        let records = context.records.filter { $0.collection.caseInsensitiveCompare(name) == .orderedSame }
        let variable = TemplateFill.normal(name)
        let fields = Array(Set(records.prefix(20).flatMap { $0.values.keys })).sorted()
        let clips = context.clips.filter { $0.allGroups.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
        VStack(alignment: .leading, spacing: 6) {
            if !records.isEmpty {
                Text("Chosen when the app runs").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                chipGrid {
                    chip("name", "person.text.rectangle", "{{@\(name)/$\(variable)/name}}")
                    ForEach(fields, id: \.self) { chip($0, "tag", "{{@\(name)/$\(variable)/\($0)}}") }
                }
                DisclosureGroup("Fixed items (\(records.count))") {
                    chipGrid {
                        ForEach(Array(records.prefix(30)), id: \.id) { record in
                            chip(record.name, "person.crop.rectangle", "{{@\(name)/\(record.alias.isEmpty ? record.name : record.alias)}}")
                        }
                    }
                }
            }
            if !clips.isEmpty {
                Text("Shortcuts (\(clips.count))").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                chipGrid { ForEach(Array(clips.prefix(40)), id: \.id) { shortcutChip($0) } }
            }
            if records.isEmpty && clips.isEmpty { hint("Empty collection.") }
        }
    }

    func chooseNewMedia() {
        let panel = NSOpenPanel()
        panel.title = "Choose a picture or video"
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyPayload("keydo-media:" + url.path, at: nil)
    }

    // MARK: Live preview

    var previewFields: [DesignField] { DesignFields.fields(pages: [template], variables: vars) }

    /// Saves a new app name typed in the top bar, and shows the name and run word that came back.
    private func commitAppName() {
        guard let designTitle else { return }
        let wanted = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { appName = designTitle; return }
        let changed = wanted != designTitle
        if let done = onRename?(wanted) {
            appName = done.name
            if !done.command.isEmpty { commandWord = done.command }
            if changed { message = "App renamed to \u{201C}\(done.name)\u{201D}. Run it with \\\(commandWord)-name." }
        }
    }

    /// New boxes that take a collection start on its first item.
    private func fillDefaults() {
        var next = formValues
        DesignDefaults.fill(previewFields, into: &next)
        if next != formValues { formValues = next }
    }

    @ViewBuilder var exampleCommands: some View {
        let lines = DesignExamples.lines(appName: designTitle == nil ? template.name : (appName.isEmpty ? (designTitle ?? template.name) : appName), word: commandWord, fields: previewFields)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Say or type it like this").font(.system(size: 11, weight: .bold)).foregroundStyle(Butter.cocoa)
                ForEach(lines) { line in
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(line.text, forType: .string)
                        message = "Copied: \(line.text)"
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Text(line.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                            Text(line.text).font(.system(size: 11)).foregroundStyle(Butter.cocoa).multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text("Tap a line to copy it. Say less and KeyDo asks for whatever is missing.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 9).fill(Butter.cream))
        }
    }

    var previewPane: some View {
        let format = DesignFormat.from(outputFormat) ?? .png
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LIVE PREVIEW").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(DesignFormat.allCases) { option in
                        Button { outputFormat = option.rawValue; onOutputFormatChange?(option.rawValue) } label: { Label(option.title, systemImage: option.symbol) }
                    }
                } label: { Label("Output: " + format.title, systemImage: format.symbol).font(.system(size: 12, weight: .semibold)) }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            ZStack {
                Rectangle().fill(Color(white: 0.95))
                if let livePreview { Image(nsImage: livePreview).resizable().interpolation(.high).scaledToFit().padding(6) }
            }
            .frame(maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 10))
            if onCommandChange != nil {
                HStack(spacing: 4) {
                    Text("Type").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\\").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Butter.coral)
                    TextField("hbd", text: $commandWord).textFieldStyle(.roundedBorder).frame(width: 90)
                        .focused($commandFocused2)
                        .onSubmit { commandWord = onCommandChange?(commandWord) ?? commandWord }
                        .onChange(of: commandFocused2) { _, focused in if !focused { commandWord = onCommandChange?(commandWord) ?? commandWord } }
                    Text("-name to run this app anywhere").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            exampleCommands
            DesignVoiceBar(guide: tryGuide, voice: tryGuide.voice)
            Text("Try it").font(.system(size: 12, weight: .bold)).foregroundStyle(Butter.cocoa)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if previewFields.isEmpty { hint("Nothing to fill in yet. Add boxes or variables.") }
                    ForEach(previewFields) { field in
                        DesignFieldRow(field: field, text: Binding(get: { formValues[field.key] ?? "" }, set: { formValues[field.key] = $0 }), fallback: field.defaultValue)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 9).stroke(tryGuide.active && tryGuide.current?.key == field.key ? Butter.coral : Color.clear, lineWidth: 2))
                            .simultaneousGesture(TapGesture().onEnded { tryGuide.select(field.key) })
                    }
                }
            }
            .frame(maxHeight: 230)
            HStack {
                Button { makeFile() } label: { Label("Make \(format.title)", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.borderedProminent).tint(Butter.coral)
                Button { copyPNG() } label: { Label("Copy image", systemImage: "doc.on.doc") }.buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(12).frame(width: 360).background(Color(nsColor: .windowBackgroundColor))
    }

    func makeFile() {
        store.save(template)
        if let onMakeFile { message = onMakeFile(formValues) } else { exportPNG() }
    }
}
