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
                if store.templates.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 300), spacing: 14)], spacing: 14) {
                        ForEach(store.templates) { template in card(template) }
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
        let template = store.template(id: templateID)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use \u{201C}\(template?.name ?? "template")\u{201D} in apps").font(.system(size: 17, weight: .bold)).foregroundStyle(Butter.cocoa)
                    Text("Boxes: \((template?.fieldKeys ?? []).joined(separator: ", "))").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
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
    @State private var selected = ""
    @State private var showLibrary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photo template (optional)").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 10) {
                Picker("", selection: $selected) {
                    Text("None: use the built-in looks").tag("")
                    ForEach(store.templates) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().frame(maxWidth: 320)
                Button { showLibrary = true } label: { Label("Design or upload templates", systemImage: "photo.on.rectangle.angled") }
                    .buttonStyle(.bordered)
            }
            if let template = store.template(id: selected) {
                let missing = template.fieldKeys.filter { key in !existingFieldKeys.contains(where: { TemplateFill.normal($0) == TemplateFill.normal(key) }) }
                Text("Boxes: \(template.fieldKeys.joined(separator: ", ")). A field with the same name fills its box.")
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
                TemplateLibraryView()
            }
            .frame(minWidth: 1040, minHeight: 720)
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

    init(template: ImageTemplate, onClose: @escaping () -> Void) {
        _template = State(initialValue: template)
        _base = State(initialValue: TemplateStore.shared.basePicture(for: template) ?? NSImage(size: NSSize(width: 100, height: 100)))
        self.onClose = onClose
    }

    // MARK: Layout

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                canvas.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(white: 0.9))
                Divider()
                ScrollView { inspector.padding(14) }.frame(width: 350).background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .onAppear { refresh() }
        .onChange(of: template) { _, _ in refresh() }
        .onChange(of: mode) { _, _ in refresh() }
        .onChange(of: testTexts) { _, _ in refresh() }
        .onChange(of: testVersion) { _, _ in refresh() }
        .onDisappear { store.save(template) }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { finish() } label: { Label("Templates", systemImage: "chevron.left") }.buttonStyle(.bordered)
            TextField("Template name", text: $template.name).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
            Picker("", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(width: 230)
            if let busy { ProgressView().controlSize(.small); Text(busy).font(.system(size: 12)).foregroundStyle(.secondary) }
            else if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(Butter.cocoa.opacity(0.8)).lineLimit(1) }
            Spacer()
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
            fillCard
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
        let inputs = testInputs()
        guard let data = TemplateRenderer.pngData(template, base: base, texts: inputs.texts, images: inputs.images) else { message = "The picture could not be made."; return }
        message = TemplateDialogs.savePNG(data, name: template.name)
    }

    private func copyPNG() {
        let inputs = testInputs()
        guard let data = TemplateRenderer.pngData(template, base: base, texts: inputs.texts, images: inputs.images), let image = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        message = "Copied the picture."
    }

    // MARK: Actions

    private func refresh() {
        let inputs = testInputs()
        preview = TemplateRenderer.render(template, base: base, texts: mode == .fill ? inputs.texts : nil, images: inputs.images,
                                          useSamples: mode != .fill, maxSide: 1500)
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
