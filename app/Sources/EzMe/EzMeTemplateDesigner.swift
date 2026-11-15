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
                        toggleRow(app.name, isOn: TemplateStore.wishTemplateID(appID: app.id) == templateID) { on in
                            TemplateStore.setWishTemplate(on ? templateID : "", appID: app.id); refresh += 1
                        }
                    }
                    sectionTitle("AppBuilder apps")
                    if builderApps.isEmpty { Text("No AppBuilder apps of your own yet.").font(.system(size: 12)).foregroundStyle(.secondary) }
                    ForEach(builderApps, id: \.self) { name in
                        toggleRow(name, isOn: TemplateStore.builderTemplateID(app: name) == templateID) { on in
                            TemplateStore.setBuilderTemplate(on ? templateID : "", app: name); refresh += 1
                        }
                    }
                }
            }
            Text("An app fills a box when it has a field with the same name. In WishBuilder, step 1 can also create the fields from the boxes.")
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
    @State private var vars: [String: String]
    @State private var commandText = ""
    @State private var heard = ""
    @State private var newVariable = ""
    @StateObject private var speech = EzMeSpeechDictation()
    @FocusState private var commandFocused: Bool

    init(template: ImageTemplate, onClose: @escaping () -> Void, pageInfo: (index: Int, count: Int)? = nil,
         onGoToPage: ((Int) -> Void)? = nil, onAddPage: (() -> Void)? = nil, onRelease: (() -> String)? = nil,
         variables: [String: String] = [:], onVariablesChange: (([String: String]) -> Void)? = nil,
         onReplaceElsewhere: ((String, String) -> Int)? = nil, designTitle: String? = nil) {
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
    }

    // MARK: Layout

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    commandBar
                }
                .background(Color(white: 0.9))
                Divider()
                ScrollView { inspector.padding(14) }.frame(width: 350).background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .onAppear { refresh() }
        .onChange(of: template) { _, _ in refresh() }
        .onChange(of: mode) { _, _ in refresh() }
        .onChange(of: testTexts) { _, _ in refresh() }
        .onChange(of: testVersion) { _, _ in refresh() }
        .onChange(of: vars) { _, _ in refresh() }
        .onDisappear { speech.stop(); store.save(template) }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { finish() } label: { Label("Templates", systemImage: "chevron.left") }.buttonStyle(.bordered)
            if let designTitle { Text(designTitle).font(.system(size: 13, weight: .bold)).foregroundStyle(Butter.cocoa).lineLimit(1) }
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
            Picker("", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(width: 230)
            if let busy { ProgressView().controlSize(.small); Text(busy).font(.system(size: 12)).foregroundStyle(.secondary) }
            else if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(Butter.cocoa.opacity(0.8)).lineLimit(1) }
            Spacer()
            if onRelease != nil {
                Button { message = perform(.release) } label: { Label("Release", systemImage: "paperplane.fill") }.buttonStyle(.bordered)
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

    private func eraseLayer(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)
            if let start = eraseStart, let now = eraseNow {
                Rectangle().fill(Color.red.opacity(0.25))
                    .overlay(Rectangle().stroke(Color.red, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .frame(width: abs(now.x - start.x), height: abs(now.y - start.y))
                    .offset(x: min(start.x, now.x), y: min(start.y, now.y))
            }
        }
        .frame(width: width, height: height)
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named("canvas"))
                .onChanged { value in eraseStart = value.startLocation; eraseNow = value.location }
                .onEnded { value in
                    let rect = CGRect(x: min(value.startLocation.x, value.location.x) / width, y: min(value.startLocation.y, value.location.y) / height,
                                      width: abs(value.location.x - value.startLocation.x) / width, height: abs(value.location.y - value.startLocation.y) / height)
                    eraseStart = nil; eraseNow = nil
                    eraseArea(rect)
                }
        )
        .onHover { inside in if inside { NSCursor.crosshair.push() } else { NSCursor.pop() } }
    }

    // MARK: Inspector

    @ViewBuilder private var inspector: some View {
        switch mode {
        case .design:
            VStack(alignment: .leading, spacing: 14) {
                if onVariablesChange != nil { variablesCard }
                pictureCard
                addCard
                boxesCard
                if let index = selectedIndex { boxEditor(index) } else {
                    hint("Click a box on the picture to edit it. Drag it to move, drag the dots to resize, and drag the round arrow to turn it.")
                }
            }
        case .erase:
            VStack(alignment: .leading, spacing: 14) {
                hint("Drag a rectangle over any text, mark or stamp on the picture to remove it. The colours around it fill the space.")
                pictureCard
            }
        case .fill:
            VStack(alignment: .leading, spacing: 14) {
                if onVariablesChange != nil { variablesCard }
                fillCard
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
            Picker("Font", selection: $template.slots[index].fontName) {
                ForEach(TemplateFonts.all, id: \.self) { Text($0).tag($0) }
            }
            Toggle("Make the text as large as fits", isOn: Binding(get: { slot.fontSize == 0 }, set: { template.slots[index].fontSize = $0 ? 0 : 0.04 }))
                .toggleStyle(.checkbox).font(.system(size: 12))
            if slot.fontSize > 0 {
                HStack {
                    Text("Largest size").font(.system(size: 12))
                    Slider(value: $template.slots[index].fontSize, in: 0.01...0.2)
                }
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
        let made = resolvedInputs(designing: mode != .fill)
        preview = TemplateRenderer.render(template, base: base, texts: made.texts, images: made.images, useSamples: mode != .fill, maxSide: 1500)
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
        var values: [String: String] = [:]
        for (key, value) in vars { values[key] = value }
        for (key, value) in inputs.texts { values[key] = value }
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
                    Image(systemName: speech.isListening ? "mic.fill" : "mic")
                        .foregroundStyle(speech.isListening ? Color.white : Butter.coral)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(speech.isListening ? Butter.coral : Color.white))
                        .overlay(Circle().stroke(Butter.coral, lineWidth: 1.5))
                }
                .buttonStyle(.plain).help(speech.isListening ? "Stop listening" : "Listen: say what to change")
                TextField("Say or type a change, like \u{201C}make the text pink\u{201D} or \u{201C}go to page 2\u{201D}", text: $commandText)
                    .textFieldStyle(.roundedBorder).focused($commandFocused)
                    .onSubmit { submitCommand() }
                Button("Do it") { submitCommand() }.buttonStyle(.borderedProminent).tint(Butter.coral).disabled(commandText.trimmingCharacters(in: .whitespaces).isEmpty)
                Button { undoLast() } label: { Image(systemName: "arrow.uturn.backward") }.buttonStyle(.bordered).disabled(undo.isEmpty).help("Undo")
            }
            if speech.isListening || !heard.isEmpty {
                Text(speech.isListening ? "Listening\u{2026} \(heard)" : "Heard: \(heard)").font(.system(size: 11)).foregroundStyle(Butter.cocoa.opacity(0.75)).lineLimit(1)
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
        if speech.isListening { speech.stop(); return }
        speech.startContinuous(onTranscript: { text in runCommand(text) }, onPartial: { partial in heard = partial })
    }

    // MARK: Variables and live content

    var variablesCard: some View {
        card("Variables") {
            if vars.isEmpty { hint("Variables are values that change for each use, like company or amount. Say \u{201C}replace Acme Ltd with variable company\u{201D}.") }
            ForEach(vars.keys.sorted(), id: \.self) { key in
                HStack(spacing: 6) {
                    Text(key).font(.system(size: 12, weight: .semibold)).foregroundStyle(Butter.cocoa).frame(width: 84, alignment: .leading).lineLimit(1)
                    TextField("starting value", text: Binding(get: { vars[key] ?? "" }, set: { vars[key] = $0; onVariablesChange?(vars) })).textFieldStyle(.roundedBorder)
                    Button { vars[key] = nil; onVariablesChange?(vars) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain)
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

    func addToken(_ index: Int, _ token: String) {
        guard index < template.slots.count else { return }
        pushUndo()
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
        let names = Array(Set(vars.keys).union(template.slots.map { $0.key })).sorted()
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
                Menu("Collection") { collectionMenu(index) }
                Menu("Function") { ForEach(DesignFunction.items) { item in Button(item.title) { addToken(index, item.token) } } }
                Menu("Shortcut") {
                    ForEach(Array(AppDesignContext.shared.clips.prefix(40)), id: \.id) { clip in
                        Button(clip.key) { addToken(index, slot.kind == .image ? clip.key : "{{shortcut:\(clip.key)}}") }
                    }
                }
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
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        heard = text
        var notes: [String] = []
        for action in DesignCommand.parse(text) { notes.append(perform(action)) }
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
            mode = .fill
            return "Showing the finished result."
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
        case .insertToken(let token):
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
