// "Fill by voice" for AppDesigner apps, the same experience as Ezyourlife apps: KeyDo points at one box at a time,
// you say the answer, and it moves on. Say several at once ("name Rahul photo rohit dot media wish ss10") and they all fill.
// Say next, back, clear, "make it" or done at any time.
import SwiftUI

@MainActor final class DesignVoiceGuide: ObservableObject {
    let voice = WishVoiceController()
    @Published var active = false
    @Published var index = 0
    @Published var note = ""
    @Published var language = "en-IN"

    var fields: () -> [DesignField] = { [] }
    var values: () -> [String: String] = { [:] }
    var setValue: (String, String) -> Void = { _, _ in }
    var make: () -> Void = {}
    var onStart: () -> Void = {}

    var current: DesignField? {
        let all = fields()
        return index >= 0 && index < all.count ? all[index] : nil
    }

    private var takeover: NSObjectProtocol?
    init() {
        takeover = NotificationCenter.default.addObserver(forName: .keydoVoiceTakeover, object: nil, queue: .main) { [weak self] event in
            guard (event.object as AnyObject?) !== self else { return }
            Task { @MainActor in if self?.active == true { self?.stop() } }
        }
    }

    func toggle() { active ? stop() : start() }

    func start() {
        FormVoice.shared.stop(message: nil)
        onStart()
        NotificationCenter.default.post(name: .keydoVoiceTakeover, object: self)
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

    func skip() { move(to: index + 1) }
    func back() { move(to: max(0, index - 1)) }

    /// The person clicked into a box: voice answers go there now.
    func select(_ key: String) {
        guard active, let position = fields().firstIndex(where: { $0.key == key }), position != index else { return }
        index = position
        note = ""
    }

    private func firstEmptyIndex() -> Int {
        let all = fields(), current = values()
        return all.firstIndex { (current[$0.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty } ?? 0
    }

    private func move(to next: Int) {
        if next >= fields().count {
            note = "That was the last box. Say \u{201C}make it\u{201D} when you are ready."
            index = max(0, fields().count - 1)
        } else {
            index = next
            note = ""
        }
    }

    private func clean(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
    }

    /// A sentence heard by the designer's own mic that is not a design change: it fills boxes or makes the file, so the
    /// whole page answers to voice. Returns what happened, or nil when the sentence meant nothing here.
    func acceptLoose(_ raw: String) -> String? {
        let spoken = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return nil }
        if DesignVoiceFill.isMakeCommand(spoken) { make(); return "Making it\u{2026}" }
        let all = fields()
        let found = DesignVoiceFill.parse(spoken, fields: all)
        guard !found.isEmpty else { return nil }
        var done: [String] = []
        for field in all {
            guard let value = found[field.key] else { continue }
            if commit(value, to: field) { done.append(field.label) }
        }
        return done.isEmpty ? (note.isEmpty ? nil : note) : "Filled " + done.joined(separator: ", ") + "."
    }

    /// One spoken sentence.
    func handle(_ raw: String) {
        guard active else { return }
        let spoken = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        let lower = clean(spoken)
        let all = fields()

        if ["done", "finish", "finished", "stop", "that's all", "thats all", "i am done"].contains(lower) { note = "Voice fill finished."; stop(); return }
        if DesignVoiceFill.isMakeCommand(spoken) { note = "Making it\u{2026}"; stop(); make(); return }
        if ["next", "skip", "next one", "next box", "next field"].contains(lower) { skip(); return }
        if ["back", "previous", "go back", "previous box"].contains(lower) { back(); return }
        if ["clear", "clear this", "clear it", "delete"].contains(lower), let field = current { setValue(field.key, ""); note = "Cleared \(field.label)."; return }

        // Several boxes in one sentence, or "box name is answer".
        let found = DesignVoiceFill.parse(spoken, fields: all)
        if !found.isEmpty {
            var done: [String] = []
            for field in all {
                guard let value = found[field.key] else { continue }
                if commit(value, to: field) { done.append(field.label) }
            }
            index = firstEmptyIndex()
            if !done.isEmpty { note = "Filled " + done.joined(separator: ", ") + "." + hint() }
            return
        }
        // Naming a box on its own jumps to it.
        if let position = all.firstIndex(where: { clean($0.label) == lower }) { index = position; note = ""; return }
        guard let field = current else { return }
        if commit(spoken, to: field) {
            if field.kind == .long { note = "Added to \(field.label). Say next when you are done with this box." }
            else { move(to: index + 1); note = "\(field.label) done." + hint() }
        }
    }

    private func hint() -> String {
        let all = fields(), current = values()
        let empty = all.filter { (current[$0.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        return empty.isEmpty ? " Everything is filled. Say \u{201C}make it\u{201D}." : ""
    }

    /// Puts one answer into one box. Returns false when it could not be used.
    private func commit(_ answer: String, to field: DesignField) -> Bool {
        var value = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let hintText = (field.key + " " + field.label).lowercased()
        switch field.kind {
        case .image:
            let said = value
            value = value.replacingOccurrences(of: " dot ", with: ".", options: .caseInsensitive)
                .replacingOccurrences(of: " dash ", with: "-", options: .caseInsensitive)
                .replacingOccurrences(of: " ", with: "")
            if celebrationMedia(value, clips: AppDesignContext.shared.clips) == nil && !FileManager.default.fileExists(atPath: value) {
                // Not a shortcut name: look for media whose name or description has the words that were said.
                if let found = MediaFinder.best(said, in: field.collection) {
                    setValue(field.key, found.key)
                    return true
                }
                note = "No shortcut called \u{201C}\(value)\u{201D}. Say the shortcut name again, or press Shortcuts to pick one."
                return false
            }
            setValue(field.key, value)
            return true
        case .choice:
            let wanted = clean(value)
            let options = DesignVoiceFill.options(for: field)
            guard let match = options.first(where: { clean($0.name) == wanted || clean($0.alias) == wanted })
                ?? options.first(where: { clean($0.name).contains(wanted) || wanted.contains(clean($0.name)) })
                ?? PickerRank.records(value, in: field.collection ?? "", limit: 1).first else {
                note = "I did not find \u{201C}\(value)\u{201D}. Say one of: " + options.prefix(6).map { $0.name }.joined(separator: ", ")
                return false
            }
            setValue(field.key, match.alias.isEmpty ? match.name : match.alias)
            return true
        case .wish:
            guard let clip = WishPick.find(value, in: field.collection ?? "") ?? WishPick.spotted(in: value, collection: field.collection ?? "") else {
                note = "No wish matches \u{201C}\(value)\u{201D}. Say a shortcut like ss10, a number, or words from the wish."
                return false
            }
            setValue(field.key, clip.key)
            return true
        case .long:
            let existing = (values()[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            setValue(field.key, existing.isEmpty ? value : existing + " " + value)
            return true
        case .text:
            if hintText.contains("email") {
                value = value.lowercased().replacingOccurrences(of: " at the rate ", with: "@").replacingOccurrences(of: " at ", with: "@")
                    .replacingOccurrences(of: " dot ", with: ".").replacingOccurrences(of: " ", with: "")
            } else if hintText.contains("phone") || hintText.contains("mobile") {
                let compact = value.replacingOccurrences(of: " ", with: "")
                if compact.allSatisfy({ $0.isNumber || $0 == "+" || $0 == "-" }) { value = compact }
            }
            setValue(field.key, value)
            return true
        }
    }
}

/// The strip above the boxes.
struct DesignVoiceBar: View {
    @ObservedObject var guide: DesignVoiceGuide
    @ObservedObject var voice: WishVoiceController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { guide.toggle() } label: {
                    HStack(spacing: 6) {
                        KeyDoVoiceIcon(kind: .fill, size: 22, active: guide.active)
                        Text(guide.active ? "Stop voice" : "Fill by voice")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(guide.active ? Butter.coral : Butter.honey))
                    .overlay(Capsule().stroke(Butter.cocoa, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help("Speak your answers. KeyDo guides you through the boxes one by one.")
                Picker("", selection: Binding(get: { guide.language }, set: { guide.changeLanguage($0) })) {
                    Text("English").tag("en-IN")
                    Text("\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}").tag("hi-IN")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 130)
                if guide.active { ProgressView(value: voice.level).frame(width: 46).tint(.teal) }
                Spacer(minLength: 0)
            }
            if guide.active {
                VStack(alignment: .leading, spacing: 4) {
                    if let field = guide.current {
                        Text("Say: \(field.label)").font(.system(size: 13, weight: .bold))
                        Text(example(field)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if !voice.heard.isEmpty { Text("Hearing: \(voice.heard)").font(.system(size: 12)).foregroundStyle(.teal) }
                    if !guide.note.isEmpty { Text(guide.note).font(.system(size: 11)).foregroundStyle(.secondary) }
                    HStack(spacing: 6) {
                        Button("Back") { guide.back() }.disabled(guide.index == 0)
                        Button("Skip") { guide.skip() }
                        Button("Done") { guide.stop() }
                        Text("Or say next, back, clear, \u{201C}make it\u{201D}, or several boxes at once.").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Butter.cream))
            }
            if !voice.errorMessage.isEmpty { Text(voice.errorMessage).font(.system(size: 11)).foregroundStyle(.red) }
        }
    }

    private func example(_ field: DesignField) -> String {
        switch field.kind {
        case .image: return "Say the media name, like \u{201C}rohit dot media\u{201D}, or words about it, like \u{201C}birthday cake\u{201D}."
        case .choice: return "Choose from: " + DesignVoiceFill.options(for: field).prefix(6).map { $0.name }.joined(separator: ", ")
        case .wish: return "Say a shortcut like ss10, a number, or words from the wish."
        case .long: return "Keep talking to add more, then say next."
        case .text: return "Say the answer."
        }
    }
}
