// Wish Studio, simple: what a layer is, the canvas where layers are dragged into place, and the small panel that
// makes a layer fixed or dynamic.
import SwiftUI
import AppKit

enum WishLayerKind {
    case variable, collection, function, text, image, logo

    @MainActor static func of(_ slot: TemplateSlot, app: WishApp) -> WishLayerKind {
        if slot.kind == .logo { return .logo }
        if slot.kind == .image { return .image }
        let content = slot.content ?? ""
        if content.hasPrefix("{=") { return .function }
        if content.contains("{{") { return (app.field(slot.key)?.choices ?? []).isEmpty ? .variable : .collection }
        return .text
    }

    var symbol: String {
        switch self {
        case .variable: return "curlybraces"
        case .collection: return "list.bullet"
        case .function: return "function"
        case .text: return "textformat"
        case .image: return "photo"
        case .logo: return "flag"
        }
    }

    func isDynamic(_ slot: TemplateSlot) -> Bool {
        switch self {
        case .variable, .collection, .function: return true
        case .image: return (slot.content ?? "").isEmpty
        case .text, .logo: return false
        }
    }
}

// MARK: - Canvas

struct WishCanvas: View {
    var template: ImageTemplate?
    var preview: NSImage?
    @Binding var selected: String?
    var onMove: (String, Double, Double) -> Void
    var onEnd: () -> Void
    @State private var origin: [String: CGPoint] = [:]

    var body: some View {
        ZStack {
            WishSimpleTheme.stage
            if let template, let preview {
                GeometryReader { geo in
                    let aspect = CGFloat(template.pixelWidth) / CGFloat(max(1, template.pixelHeight))
                    let w = max(50, min(geo.size.width - 32, (geo.size.height - 32) * aspect)), h = w / aspect
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: preview).resizable().interpolation(.high).frame(width: w, height: h)
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                            .onTapGesture { selected = nil }
                        ForEach(template.slots) { slot in
                            let boxW = max(46, w * slot.w), boxH = max(28, h * slot.h)
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(slot.id == selected ? WishSimpleTheme.accent : Color.clear, style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
                                .background(RoundedRectangle(cornerRadius: 5).fill(slot.id == selected ? Color.white.opacity(0.12) : Color.clear))
                                .frame(width: boxW, height: boxH)
                                .contentShape(Rectangle())
                                .position(x: w * slot.cx, y: h * slot.cy)
                                .gesture(
                                    DragGesture(minimumDistance: 1, coordinateSpace: .named("wishCanvas"))
                                        .onChanged { value in
                                            selected = slot.id
                                            let start = origin[slot.id] ?? CGPoint(x: slot.cx, y: slot.cy)
                                            origin[slot.id] = start
                                            onMove(slot.id, Double(start.x + value.translation.width / w), Double(start.y + value.translation.height / h))
                                        }
                                        .onEnded { _ in origin[slot.id] = nil; onEnd() }
                                )
                                .onTapGesture { selected = slot.id }
                        }
                    }
                    .coordinateSpace(name: "wishCanvas")
                    .frame(width: w, height: h)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            } else {
                Text("Choose a background in step 1.").font(.system(size: 13)).foregroundStyle(WishSimpleTheme.muted)
            }
        }
        .frame(height: 480)
    }
}

// MARK: - One layer

struct WishLayerProperties: View {
    @ObservedObject var model: WishStudioModel
    var slotID: String
    @Binding var template: ImageTemplate
    var onRemoved: () -> Void
    @State private var nameDraft = ""
    @State private var size = 0.06
    @State private var optionsDraft = ""
    @State private var message = ""

    private var index: Int? { template.slots.firstIndex { $0.id == slotID } }
    private var slot: TemplateSlot? { index.map { template.slots[$0] } }
    private var kind: WishLayerKind { slot.map { WishLayerKind.of($0, app: model.app) } ?? .text }

    private let inks = ["#26221F", "#FFFFFF", "#A9402D", "#C2415D", "#E9B949", "#3A654E", "#1B2A5C", "#7B52B8"]

    var body: some View {
        if let slot {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Layer").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Remove") { remove() }.buttonStyle(.plain).foregroundStyle(WishSimpleTheme.accent).font(.system(size: 12))
                }
                if kind != .function && kind != .logo { modeSwitch(slot) }
                Text(explanation(slot)).font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted)
                labelled("Name") {
                    TextField("name", text: $nameDraft).textFieldStyle(.roundedBorder).onSubmit { rename() }
                }
                valueEditor(slot)
                if slot.kind == .text {
                    labelled("Text size") {
                        Slider(value: $size, in: 0.02...0.16, onEditingChanged: { editing in
                            if !editing, let i = index { template.slots[i].fontSize = size }
                        })
                    }
                    labelled("Colour") {
                        HStack(spacing: 6) {
                            ForEach(inks, id: \.self) { hex in
                                Button { if let i = index { template.slots[i].colorHex = hex } } label: {
                                    Circle().fill(Color(wishHex: hex)).frame(width: 20, height: 20)
                                        .overlay(Circle().strokeBorder(hex.caseInsensitiveCompare(slot.colorHex) == .orderedSame ? WishSimpleTheme.accent : Color.black.opacity(0.2), lineWidth: hex.caseInsensitiveCompare(slot.colorHex) == .orderedSame ? 2 : 1))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Toggle("Bold", isOn: Binding(get: { slot.bold }, set: { if let i = index { template.slots[i].bold = $0 } })).toggleStyle(.checkbox).font(.system(size: 12))
                }
                if !message.isEmpty { Text(message).font(.system(size: 11)).foregroundStyle(WishSimpleTheme.muted) }
            }
            .onAppear { load() }
            .onChange(of: slotID) { _, _ in load() }
        }
    }

    private func load() {
        guard let slot else { return }
        nameDraft = slot.key
        size = slot.fontSize > 0 ? slot.fontSize : 0.06
        optionsDraft = (model.app.field(slot.key)?.choices ?? []).joined(separator: ", ")
        message = ""
    }

    private func explanation(_ slot: TemplateSlot) -> String {
        switch kind {
        case .variable: return "Dynamic: whoever makes a card types this each time."
        case .collection: return "Dynamic: whoever makes a card chooses one of your options."
        case .function: return "Calculated for you each time the card is made."
        case .text: return "Fixed: saved once with the template."
        case .image: return kind.isDynamic(slot) ? "Dynamic: a picture is added each time." : "Fixed: the same picture on every card."
        case .logo: return "Your logo, the same on every card."
        }
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(WishSimpleTheme.muted)
            content()
        }
    }

    private func modeSwitch(_ slot: TemplateSlot) -> some View {
        let isDyn = kind.isDynamic(slot)
        return HStack(spacing: 0) {
            ForEach(["Fixed", "Dynamic"], id: \.self) { title in
                let on = (title == "Dynamic") == isDyn
                Button { if !on { title == "Dynamic" ? makeDynamic() : makeFixed() } } label: {
                    Text(title).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? WishSimpleTheme.accent : Color.clear))
                        .foregroundStyle(on ? Color.white : WishSimpleTheme.ink)
                }.buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(wishHex: "#EEE9E0")))
    }

    // MARK: Values

    @ViewBuilder private func valueEditor(_ slot: TemplateSlot) -> some View {
        switch kind {
        case .text:
            labelled("Saved text") {
                TextField("Your text", text: Binding(get: { slot.content ?? slot.sample }, set: { value in
                    if let i = index { template.slots[i].content = value; template.slots[i].sample = value }
                })).textFieldStyle(.roundedBorder)
            }
        case .variable:
            labelled("Example shown while designing") {
                TextField("Rohit", text: Binding(get: { slot.sample }, set: { value in
                    if let i = index { template.slots[i].sample = value; setPlaceholder(slot.key, value) }
                })).textFieldStyle(.roundedBorder)
            }
        case .collection:
            labelled("Options, separated by commas") {
                TextField("Option A, Option B", text: $optionsDraft).textFieldStyle(.roundedBorder).onSubmit { applyOptions() }
                Button("Save options") { applyOptions() }.buttonStyle(SimpleQuietMini())
            }
        case .function:
            labelled("What it works out") {
                Picker("", selection: Binding(get: { functionChoice(slot) }, set: { setFunction($0) })) {
                    Text("Today's date").tag("date")
                    Text("Time now").tag("time")
                    Text("Good morning, afternoon or evening").tag("greeting")
                    ForEach(askedNames(excluding: slot.key), id: \.self) { name in Text("CAPITALS of \(name)").tag("upper:" + name) }
                }.labelsHidden()
            }
        case .image:
            if !kind.isDynamic(slot) {
                Button { uploadPicture() } label: { Label("Choose the picture", systemImage: "photo") }.buttonStyle(SimpleQuietMini())
            }
        case .logo:
            Button { uploadLogo() } label: { Label("Upload your logo", systemImage: "flag") }.buttonStyle(SimpleQuietMini())
        }
    }

    private func askedNames(excluding key: String) -> [String] {
        template.slots.compactMap { other -> String? in
            guard other.id != slotID, let content = other.content, content.contains("{{") else { return nil }
            return other.key
        }
    }

    private func functionChoice(_ slot: TemplateSlot) -> String {
        let content = (slot.content ?? "").lowercased()
        if content.contains("time") { return "time" }
        if content.contains("greeting") { return "greeting" }
        if content.contains("upper("), let open = content.firstIndex(of: "("), let close = content.firstIndex(of: ")") {
            return "upper:" + String(content[content.index(after: open)..<close])
        }
        return "date"
    }

    private func setFunction(_ choice: String) {
        guard let i = index else { return }
        let formatter = DateFormatter()
        switch choice {
        case "time":
            formatter.timeStyle = .short
            template.slots[i].content = "{=Time}"; template.slots[i].sample = formatter.string(from: Date())
        case "greeting":
            template.slots[i].content = "{=GREETING()}"; template.slots[i].sample = "Good morning"
        default:
            if choice.hasPrefix("upper:") {
                let name = String(choice.dropFirst(6))
                template.slots[i].content = "{=UPPER(\(name))}"
                template.slots[i].sample = (template.slots.first { $0.key == name }?.sample ?? name).uppercased()
            } else {
                formatter.dateStyle = .medium
                template.slots[i].content = "{=Date}"; template.slots[i].sample = formatter.string(from: Date())
            }
        }
    }

    // MARK: Changes

    private func setPlaceholder(_ key: String, _ value: String) {
        var app = model.app
        guard let at = app.fields.firstIndex(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) else { return }
        app.fields[at].placeholder = value
        model.store.updateApp(app)
    }

    private func applyOptions() {
        guard let slot, let i = index else { return }
        let options = optionsDraft.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !options.isEmpty else { message = "Add at least one option."; return }
        var app = model.app
        if let at = app.fields.firstIndex(where: { $0.key.caseInsensitiveCompare(slot.key) == .orderedSame }) { app.fields[at].choices = options }
        else { var field = WishField(key: slot.key, label: slot.key.prefix(1).uppercased() + slot.key.dropFirst()); field.choices = options; app.fields.append(field) }
        model.store.updateApp(app)
        template.slots[i].sample = options[0]
        message = "Options saved."
    }

    private func makeFixed() {
        guard let slot, let i = index else { return }
        if kind == .image { template.slots[i].content = nil; uploadPicture(); return }
        var app = model.app
        let first = app.field(slot.key)?.choices?.first
        let value = first ?? (slot.sample.isEmpty ? "Your text" : slot.sample)
        template.slots[i].content = value
        template.slots[i].sample = value
        app.fields.removeAll { $0.key.caseInsensitiveCompare(slot.key) == .orderedSame }
        model.store.updateApp(app)
        load()
    }

    private func makeDynamic() {
        guard let slot, let i = index else { return }
        if kind == .image { template.slots[i].content = nil; return }
        var app = model.app
        template.slots[i].content = "{{\(slot.key)}}"
        if app.field(slot.key) == nil {
            var field = WishField(key: slot.key, label: slot.key.prefix(1).uppercased() + slot.key.dropFirst())
            field.placeholder = slot.sample
            app.fields.append(field)
            model.store.updateApp(app)
        }
        load()
    }

    private func rename() {
        guard let slot, let i = index else { return }
        let clean = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "-")
        guard !clean.isEmpty, clean != slot.key else { return }
        if template.slots.contains(where: { $0.id != slotID && $0.key.caseInsensitiveCompare(clean) == .orderedSame }) { message = "Another layer already has that name."; return }
        var app = model.app
        if let at = app.fields.firstIndex(where: { $0.key.caseInsensitiveCompare(slot.key) == .orderedSame }) {
            app.fields[at].key = clean
            app.fields[at].label = clean.prefix(1).uppercased() + clean.dropFirst()
            model.store.updateApp(app)
        }
        if let content = slot.content, content.contains("{{\(slot.key)}}") { template.slots[i].content = content.replacingOccurrences(of: "{{\(slot.key)}}", with: "{{\(clean)}}") }
        template.slots[i].key = clean
        nameDraft = clean
    }

    private func remove() {
        guard let slot else { return }
        var app = model.app
        app.fields.removeAll { $0.key.caseInsensitiveCompare(slot.key) == .orderedSame }
        model.store.updateApp(app)
        template.slots.removeAll { $0.id == slotID }
        onRemoved()
    }

    private func uploadPicture() {
        guard let i = index, let image = TemplateDialogs.openImage(title: "Choose a picture"), let data = TemplateImages.png(image) else { return }
        let file = "pic-" + String(UUID().uuidString.prefix(8)) + ".png"
        let url = TemplateStore.shared.logoURL(file)
        guard (try? data.write(to: url, options: .atomic)) != nil else { message = "Could not save the picture."; return }
        template.slots[i].content = url.path
    }

    private func uploadLogo() {
        guard let i = index, let image = TemplateDialogs.openImage(title: "Choose your logo"), let data = TemplateImages.png(image) else { return }
        let file = "logo-" + String(UUID().uuidString.prefix(8)) + ".png"
        guard (try? data.write(to: TemplateStore.shared.logoURL(file), options: .atomic)) != nil else { message = "Could not save the logo."; return }
        template.slots[i].logo = "file:" + file
    }
}

private struct SimpleQuietMini: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(WishSimpleTheme.ink)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(WishSimpleTheme.white.opacity(configuration.isPressed ? 0.7 : 1)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(WishSimpleTheme.line, lineWidth: 1))
    }
}
