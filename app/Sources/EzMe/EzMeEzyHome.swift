// Ezyourlife apps: the home page and voice-guided forms.
//
//  * Home page: every app is a card like the AppBuilder and WishStudio home pages. Each card can have its own
//    cover (picture, GIF or video, with crop and position) and its own icon (gallery or your own picture).
//    Clicking a card opens the app straight away.
//  * Voice guide: "Fill by voice" walks through the boxes of an app one at a time. You say the answer; say
//    "next", "back", "clear" or "done", or name a box ("company name is Astute") to jump to it.
import SwiftUI
import AppKit
import Speech

// MARK: - Look of each app on the home page

@MainActor final class EzyLook: ObservableObject {
    static let shared = EzyLook()
    /// Bumped whenever any cover or icon changes, so the cards redraw.
    @Published var revision = 0
    private let defaults = UserDefaults.standard

    private func coverKey(_ id: String) -> String { "ezmeEzyCover." + id }
    private func iconKey(_ id: String) -> String { "ezmeEzyIcon." + id }
    private func symbolKey(_ id: String) -> String { "ezmeEzySymbol." + id }
    static func framingName(_ id: String) -> String { "ezy-" + id }

    private var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiniJ/EzyCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func coverPath(_ id: String) -> String {
        let path = defaults.string(forKey: coverKey(id)) ?? ""
        return FileManager.default.fileExists(atPath: path) ? path : ""
    }
    func iconPath(_ id: String) -> String {
        let path = defaults.string(forKey: iconKey(id)) ?? ""
        return FileManager.default.fileExists(atPath: path) ? path : ""
    }
    func symbol(_ id: String, name: String) -> String { defaults.string(forKey: symbolKey(id)) ?? automaticAppIcon(name) }
    func selectedSymbol(_ id: String) -> String { defaults.string(forKey: symbolKey(id)) ?? "" }

    func setCover(_ id: String, from source: URL) throws {
        let destination = folder.appendingPathComponent("cover-" + UUID().uuidString + "." + source.pathExtension)
        try FileManager.default.copyItem(at: source, to: destination)
        defaults.set(destination.path, forKey: coverKey(id))
        EzCoverFraming.save(WishFraming(), app: Self.framingName(id))
        revision += 1
    }
    func removeCover(_ id: String) {
        defaults.removeObject(forKey: coverKey(id))
        EzCoverFraming.save(WishFraming(), app: Self.framingName(id))
        revision += 1
    }
    func setIcon(_ id: String, from source: URL) throws {
        let destination = folder.appendingPathComponent("icon-" + UUID().uuidString + "." + source.pathExtension)
        try FileManager.default.copyItem(at: source, to: destination)
        defaults.set(destination.path, forKey: iconKey(id))
        revision += 1
    }
    func setSymbol(_ id: String, _ symbol: String) {
        defaults.set(symbol, forKey: symbolKey(id))
        defaults.removeObject(forKey: iconKey(id))
        revision += 1
    }
    func resetLook(_ id: String) {
        defaults.removeObject(forKey: coverKey(id))
        defaults.removeObject(forKey: iconKey(id))
        defaults.removeObject(forKey: symbolKey(id))
        EzCoverFraming.save(WishFraming(), app: Self.framingName(id))
        revision += 1
    }
}

enum EzyHomeSheet: Identifiable {
    case icon(EzyApp)
    case crop(EzyApp)
    var id: String {
        switch self {
        case .icon(let app): return "icon-" + app.id
        case .crop(let app): return "crop-" + app.id
        }
    }
}

/// The "..." menu on each home card.
struct EzyLookMenu: View {
    let app: EzyApp
    @ObservedObject var look: EzyLook
    @Binding var sheet: EzyHomeSheet?
    @Binding var note: String

    var body: some View {
        Menu {
            Button("Upload cover (picture, GIF or video)…", systemImage: "photo.on.rectangle.angled") { chooseCover() }
            if !look.coverPath(app.id).isEmpty {
                Button("Crop and position…", systemImage: "crop") { sheet = .crop(app) }
                Button("Remove cover", systemImage: "trash", role: .destructive) { look.removeCover(app.id) }
            }
            Divider()
            Button("Icon gallery…", systemImage: "square.grid.3x3.fill") { sheet = .icon(app) }
            Button("Upload icon…", systemImage: "photo.badge.plus") { chooseIcon() }
            Divider()
            Button("Reset cover and icon", systemImage: "arrow.counterclockwise") { look.resetLook(app.id) }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Cover, icon and position for this app")
    }

    private func chooseCover() {
        let panel = NSOpenPanel()
        panel.title = "Choose a cover for \(app.name)"
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try look.setCover(app.id, from: url); note = "Cover saved for \(app.name). Use Crop and position to choose what shows." }
        catch { note = "Could not save the cover: \(error.localizedDescription)" }
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.title = "Choose an icon for \(app.name)"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try look.setIcon(app.id, from: url); note = "Icon saved for \(app.name)." }
        catch { note = "Could not save the icon: \(error.localizedDescription)" }
    }
}

// MARK: - Voice guide for the boxes of an app

@MainActor final class EzyVoiceGuide: ObservableObject {
    let voice = WishVoiceController()
    @Published var active = false
    @Published var index = 0
    @Published var note = ""
    @Published var language = "en-IN"
    weak var model: EzyRunModel?

    var fields: [EzyField] { model?.detail?.fields ?? [] }
    var current: EzyField? { index >= 0 && index < fields.count ? fields[index] : nil }

    func toggle() { active ? stop() : start() }

    func start() {
        guard model?.detail != nil else { return }
        active = true
        index = firstEmptyIndex()
        note = ""
        voice.start(localeIdentifier: language, commitDelay: 1.1) { [weak self] sentence in
            Task { @MainActor in self?.handle(sentence) }
        }
    }

    func stop() {
        active = false
        voice.stop()
    }

    func changeLanguage(_ identifier: String) {
        language = identifier
        voice.changeLanguage(identifier)
    }

    private func firstEmptyIndex() -> Int {
        guard let model else { return 0 }
        return fields.firstIndex { (model.values[$0.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty } ?? 0
    }

    /// The person clicked or tabbed into a box: voice answers go there now.
    func select(_ key: String) {
        guard active, let position = fields.firstIndex(where: { $0.key == key }), position != index else { return }
        index = position; note = ""
    }

    func skip() { move(to: index + 1) }
    func back() { move(to: max(0, index - 1)) }

    private func move(to next: Int) {
        if next >= fields.count {
            note = "That was the last box. Check your answers, then press the button."
            stop()
        } else {
            index = next
            note = ""
        }
    }

    private func clean(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
    }

    /// One spoken sentence.
    func handle(_ raw: String) {
        guard active, let model else { return }
        let spoken = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        let lower = clean(spoken)

        if ["done", "finish", "finished", "stop", "that's all", "thats all", "i am done"].contains(lower) { note = "Voice fill finished."; stop(); return }
        if ["next", "skip", "next one", "next box", "next field"].contains(lower) { skip(); return }
        if ["back", "previous", "go back", "previous box"].contains(lower) { back(); return }

        // Plain text boxes (chat, image, or an app with no named boxes).
        if fields.isEmpty {
            if ["clear", "clear this", "start again", "delete"].contains(lower) { setPlain(""); note = "Cleared."; return }
            let existing = plainText(model)
            setPlain(existing.isEmpty ? spoken : existing + " " + spoken)
            note = "Added. Keep talking, or say done."
            return
        }

        if ["clear", "clear this", "clear it", "delete"].contains(lower), let field = current {
            model.values[field.key] = ""; note = "Cleared \(field.label)."; return
        }

        // "<box name> is <answer>"
        for (position, field) in fields.enumerated() {
            let label = clean(field.label)
            for joiner in [" is ", " as ", " to ", ": ", " equals "] where lower.hasPrefix(label + joiner) {
                let answer = String(spoken.dropFirst(label.count + joiner.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if apply(answer, to: field, model: model) { move(to: position + 1) }
                return
            }
        }
        // Naming a box on its own jumps to it.
        if let position = fields.firstIndex(where: { clean($0.label) == lower }) {
            index = position; note = ""; return
        }
        guard let field = current else { return }
        if apply(spoken, to: field, model: model) { move(to: index + 1) }
    }

    private func plainText(_ model: EzyRunModel) -> String {
        guard let mode = model.detail?.mode else { return "" }
        if mode == "chat" || mode == "image" { return model.chatText }
        return model.values["What I need"] ?? model.request
    }

    private func setPlain(_ text: String) {
        guard let mode = model?.detail?.mode else { return }
        if mode == "chat" || mode == "image" { model?.chatText = text } else { model?.values["What I need"] = text }
    }

    /// Fills one box. Returns true when the answer was accepted.
    private func apply(_ answer: String, to field: EzyField, model: EzyRunModel) -> Bool {
        var value = answer
        let hint = (field.key + " " + field.label).lowercased()
        if let options = field.options, !options.isEmpty, field.type == "select" {
            let wanted = clean(answer)
            let match = options.first { clean($0) == wanted }
                ?? options.first { clean($0).contains(wanted) || wanted.contains(clean($0)) }
            guard let match else {
                note = "I did not find “\(answer)”. Say one of: " + options.prefix(6).joined(separator: ", ")
                return false
            }
            model.values[field.key] = match
            note = "\(field.label): \(match)"
            return true
        }
        if hint.contains("email") {
            value = value.lowercased().replacingOccurrences(of: " at the rate ", with: "@").replacingOccurrences(of: " at ", with: "@")
                .replacingOccurrences(of: " dot ", with: ".").replacingOccurrences(of: " ", with: "")
        } else if hint.contains("phone") || hint.contains("mobile") {
            let compact = value.replacingOccurrences(of: " ", with: "")
            if compact.allSatisfy({ $0.isNumber || $0 == "+" || $0 == "-" }) { value = compact }
        }
        if field.type == "textarea" || field.type == "rows" {
            let existing = (model.values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            model.values[field.key] = existing.isEmpty ? value : existing + " " + value
            note = "Added to \(field.label). Say next when you are done with this box."
            return false
        }
        model.values[field.key] = value
        note = "\(field.label): \(value)"
        return true
    }
}

/// The strip at the top of an app's boxes.
struct EzyVoiceBar: View {
    @ObservedObject var guide: EzyVoiceGuide
    @ObservedObject var voice: WishVoiceController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    guide.toggle()
                } label: {
                    Label(guide.active ? "Stop voice" : "Fill by voice", systemImage: guide.active ? "mic.fill" : "mic")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(guide.active ? EzyColor.coral : EzyColor.sun))
                        .overlay(Capsule().stroke(EzyColor.ink, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help("Speak your answers. KeyDo guides you through the boxes one by one.")
                Picker("", selection: Binding(get: { guide.language }, set: { guide.changeLanguage($0) })) {
                    Text("English").tag("en-IN")
                    Text("\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}").tag("hi-IN")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 130)
                if guide.active {
                    ProgressView(value: voice.level).frame(width: 46).tint(EzyColor.teal)
                }
                Spacer(minLength: 0)
            }
            if guide.active {
                VStack(alignment: .leading, spacing: 4) {
                    if let field = guide.current {
                        Text("Say: \(field.label)").font(.system(size: 13, weight: .bold))
                        if let options = field.options, !options.isEmpty, field.type == "select" {
                            Text("Choose from: " + options.prefix(8).joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(EzyColor.muted)
                        } else if let placeholder = field.placeholder, !placeholder.isEmpty {
                            Text("For example: \(placeholder)").font(.system(size: 11)).foregroundStyle(EzyColor.muted)
                        }
                        Text("Box \(guide.index + 1) of \(guide.fields.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(EzyColor.muted)
                    } else {
                        Text("Say what you need. Keep talking to add more.").font(.system(size: 13, weight: .bold))
                    }
                    if !voice.heard.isEmpty { Text("Hearing: \(voice.heard)").font(.system(size: 12)).foregroundStyle(EzyColor.teal) }
                    if !guide.note.isEmpty { Text(guide.note).font(.system(size: 11)).foregroundStyle(EzyColor.muted) }
                    HStack(spacing: 6) {
                        Button("Back") { guide.back() }.disabled(guide.index == 0 || guide.fields.isEmpty)
                        Button("Skip") { guide.skip() }.disabled(guide.fields.isEmpty)
                        Button("Done") { guide.stop() }
                        Text("Or say next, back, clear, done, or “box name is answer”.").font(.system(size: 10)).foregroundStyle(EzyColor.muted)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(EzyColor.sand.opacity(0.6)))
            }
            if !voice.errorMessage.isEmpty { Text(voice.errorMessage).font(.system(size: 11)).foregroundStyle(.red) }
        }
    }
}
