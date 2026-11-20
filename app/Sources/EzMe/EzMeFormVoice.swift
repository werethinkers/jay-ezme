// Fill by voice for every screen, and voice-friendly choice lists.
//
//  * "Fill by voice" reads the boxes and choice controls on the screen you are looking at, top to bottom, and
//    walks through them one at a time. You say the answer; say "next", "back", "clear" or "done", or
//    "<box name> is <answer>" to jump to a box.
//  * When it reaches a choice (a menu, a tab bar, a switch) it opens the list of options in a small panel.
//    Say "scroll down" or "scroll up" to see more, and say an option's name or number to pick it.
//  * The same icon is used everywhere: the top bar, the builders, MyDatabase and the Ezyourlife apps.
import SwiftUI
import AppKit
import WebKit
import Combine

// MARK: - Icons

/// The two KeyDo voice icons, cropped from the brand reference.
struct KeyDoVoiceIcon: View {
    enum Kind { case command, fill, one }
    var kind: Kind
    var size: CGFloat = 24
    var active = false

    var body: some View {
        Group {
            if let image = keyDoVoiceImage(kind == .command ? "KeyDoVoiceCommand" : (kind == .fill ? "KeyDoFillByVoice" : "KeyDoVoiceOne")) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: kind == .command ? "mic.fill" : "text.badge.plus").resizable().scaledToFit().padding(size * 0.2)
                    .foregroundStyle(Butter.cocoa)
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 0.28).stroke(Butter.coral, lineWidth: active ? 2.5 : 0))
        .shadow(color: active ? Butter.coral.opacity(0.55) : .clear, radius: 5)
    }
}

/// The same Fill by voice button wherever there is a form: icon and words, or the icon alone.
struct FillByVoiceButton: View {
    var compact = false
    @ObservedObject private var form = FormVoice.shared

    var body: some View {
        Button { form.toggle() } label: {
            HStack(spacing: 7) {
                KeyDoVoiceIcon(kind: .fill, size: compact ? 28 : 26, active: form.active)
                if !compact {
                    Text(form.active ? "Stop voice" : "Fill by voice")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Butter.cocoa)
                }
            }
            .padding(.horizontal, compact ? 0 : 10).padding(.vertical, compact ? 0 : 4)
            .background(Capsule().fill(compact ? Color.clear : (form.active ? Butter.coral.opacity(0.18) : Butter.cream)))
            .overlay(Capsule().stroke(compact ? Color.clear : Butter.honey, lineWidth: 1.2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Fill by voice: speak your answers box by box. For choices, say the option you want.")
    }
}

/// The two voice icons in the top bar: Voice command (talk to KeyDo) and Fill by voice (talk into the form).
struct FormVoiceTopButtons: View {
    @ObservedObject private var form = FormVoice.shared
    @ObservedObject private var keydo = KeyDoVoice.shared

    private var commandOn: Bool { keydo.phase == .listening && !keydo.wakeOnly }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if commandOn { keydo.userStop() } else { keydo.start(.app) }
            } label: {
                KeyDoVoiceIcon(kind: .command, size: 30, active: commandOn)
            }
            .buttonStyle(.plain)
            .help(commandOn ? "Voice command is on. Click to stop." : "Voice command: say what to open or run. Or say \u{201C}Hey KeyDo\u{201D}.")
            FillByVoiceButton(compact: true)
        }
    }
}

// MARK: - What is on the screen

struct FormItem: Identifiable {
    enum Kind { case text, popup, segmented, toggle, custom }
    let id = UUID()
    var kind: Kind
    var view: NSView?
    /// Stays the same between scans, so the same box is found again.
    var key: String
    /// For choices that live in the SwiftUI screen itself (a row of tab buttons, for example).
    var handler: ((Int) -> Void)?
    var label: String
    var rect: CGRect
    var multiline = false
    /// Choices, as shown to the person.
    var options: [String] = []
    /// For each shown option, its position in the control.
    var positions: [Int] = []
    var selected: Int?

    var isChoice: Bool { kind != .text }
}

@MainActor enum FormScanner {
    static func targetWindow() -> NSWindow? {
        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }
        return window?.attachedSheet ?? window
    }

    static func scan(_ window: NSWindow) -> [FormItem] {
        guard let root = window.contentView else { return [] }
        var found: [FormItem] = []
        walk(root, into: &found)
        let height = root.bounds.height
        for entry in VoiceChoiceRegistry.shared.entries.values where !entry.options.isEmpty {
            var item = FormItem(kind: .custom, view: nil, key: "c" + entry.id.uuidString, label: entry.label,
                                rect: CGRect(x: entry.frame.minX, y: height - entry.frame.maxY, width: entry.frame.width, height: entry.frame.height))
            item.options = entry.options
            item.positions = Array(entry.options.indices)
            item.selected = entry.selected
            item.handler = entry.onPick
            found.append(item)
        }
        found.sort { a, b in
            if abs(a.rect.maxY - b.rect.maxY) > 14 { return a.rect.maxY > b.rect.maxY }
            return a.rect.minX < b.rect.minX
        }
        var number = 0
        for position in found.indices where found[position].label.isEmpty {
            number += 1
            found[position].label = found[position].isChoice ? "Choice \(number)" : "Box \(number)"
        }
        return found
    }

    private static func walk(_ view: NSView, into found: inout [FormItem]) {
        if view.isHidden || view is WKWebView { return }
        if let entry = makeItem(for: view) { found.append(entry) }
        for child in view.subviews { walk(child, into: &found) }
    }

    private static func label(_ view: NSView, fallback: String? = nil) -> String {
        var candidates: [String?] = []
        if let field = view as? NSTextField {
            candidates += [field.placeholderString, field.placeholderAttributedString?.string]
        }
        candidates += [view.accessibilityLabel(), view.accessibilityPlaceholderValue(), view.toolTip, fallback]
        let text = candidates.compactMap { $0 }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
        return String(text.prefix(48))
    }

    private static func key(_ view: NSView) -> String { "v\(ObjectIdentifier(view).hashValue)" }

    private static let unsafe = ["delete", "remove", "erase", "reset", "sign out", "log out", "quit"]

    private static func makeItem(for view: NSView) -> FormItem? {
        let rect = view.convert(view.bounds, to: nil)
        guard rect.width > 16, rect.height > 8 else { return nil }

        if let field = view as? NSTextField {
            guard field.isEditable, field.isEnabled, !(field is NSSecureTextField) else { return nil }
            return FormItem(kind: .text, view: field, key: key(field), label: label(field), rect: rect, multiline: field.frame.height > 44)
        }
        if let text = view as? NSTextView {
            guard text.isEditable, !text.isFieldEditor, !text.isHidden else { return nil }
            return FormItem(kind: .text, view: text, key: key(text), label: label(text), rect: rect, multiline: true)
        }
        if let popup = view as? NSPopUpButton, popup.isEnabled, popup.numberOfItems > 0 {
            var item = FormItem(kind: .popup, view: popup, key: key(popup), label: label(popup), rect: rect)
            let first = popup.pullsDown ? 1 : 0
            for position in first..<popup.numberOfItems {
                guard let entry = popup.item(at: position), !entry.isSeparatorItem, entry.isEnabled else { continue }
                let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, !unsafe.contains(where: { title.lowercased().hasPrefix($0) }) else { continue }
                item.options.append(title)
                item.positions.append(position)
                if !popup.pullsDown, popup.indexOfSelectedItem == position { item.selected = item.options.count - 1 }
            }
            guard !item.options.isEmpty else { return nil }
            if item.label.isEmpty { item.label = popup.pullsDown ? String(popup.title.prefix(40)) : "" }
            return item
        }
        if let segmented = view as? NSSegmentedControl, segmented.isEnabled, segmented.segmentCount > 0 {
            var item = FormItem(kind: .segmented, view: segmented, key: key(segmented), label: label(segmented), rect: rect)
            for position in 0..<segmented.segmentCount {
                let title = (segmented.label(forSegment: position) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                item.options.append(title.isEmpty ? "Option \(position + 1)" : title)
                item.positions.append(position)
                if segmented.selectedSegment == position { item.selected = position }
            }
            return item
        }
        if let toggle = view as? NSSwitch, toggle.isEnabled {
            var item = FormItem(kind: .toggle, view: toggle, key: key(toggle), label: label(toggle), rect: rect)
            item.options = ["On", "Off"]
            item.positions = [0, 1]
            item.selected = toggle.state == .on ? 0 : 1
            return item
        }
        if let box = view as? NSButton, box.isEnabled, box.accessibilityRole() == .checkBox {
            var item = FormItem(kind: .toggle, view: box, key: key(box), label: label(box, fallback: box.title), rect: rect)
            item.options = ["On", "Off"]
            item.positions = [0, 1]
            item.selected = box.state == .off ? 1 : 0
            return item
        }
        return nil
    }
}

// MARK: - The controller

@MainActor final class FormVoice: ObservableObject {
    static let shared = FormVoice()

    enum Mode { case filling, options }
    static let pageSize = 6
    private static let idleLimit = 20

    @Published private(set) var active = false
    @Published private(set) var items: [FormItem] = []
    @Published private(set) var index = 0
    @Published private(set) var mode: Mode = .filling
    @Published private(set) var optionTop = 0
    @Published private(set) var idleLeft: Int?
    @Published var note = ""
    @Published var language: String = UserDefaults.standard.string(forKey: "keydoVoiceLocale") ?? "en-IN"

    let voice = WishVoiceController()
    private var window: NSWindow?
    private var panel: FormVoicePanel?
    private var idleTimer: Timer?
    private var lastActivity = Date()
    private var listeners: Set<AnyCancellable> = []
    private var highlighted: (view: NSView, width: CGFloat, color: CGColor?)?

    var current: FormItem? { index >= 0 && index < items.count ? items[index] : nil }

    init() {
        NotificationCenter.default.addObserver(forName: .keydoVoicePriority, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop(message: nil) }
        }
        voice.$heard.dropFirst().sink { [weak self] text in
            if !text.isEmpty { self?.lastActivity = Date() }
        }.store(in: &listeners)
        NotificationCenter.default.addObserver(forName: .keydoVoiceTakeover, object: nil, queue: .main) { [weak self] event in
            guard (event.object as AnyObject?) !== self else { return }
            Task { @MainActor in self?.stop(message: nil) }
        }
    }

    func toggle() { active ? stop(message: nil) : start() }

    /// Dictation: when a text box has the cursor, the words go straight into it, like macOS dictation.
    static func dictateIntoFocus(_ text: String) -> Bool {
        guard !FormVoice.shared.active, let window = NSApp.keyWindow, !(window is FormVoicePanel),
              let editor = window.firstResponder as? NSTextView, editor.isEditable,
              !(editor.delegate is NSSecureTextField) else { return false }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return false }
        let lead = editor.string.isEmpty || editor.string.hasSuffix(" ") || editor.string.hasSuffix("\n") ? "" : " "
        editor.insertText(lead + words, replacementRange: editor.selectedRange())
        editor.scrollRangeToVisible(editor.selectedRange())
        return true
    }

    // MARK: Start and stop

    func start() {
        guard !active else { return }
        guard let target = FormScanner.targetWindow() else { return }
        NotificationCenter.default.post(name: .keydoVoiceTakeover, object: self)
        window = target
        KeyDoVoice.shared.suspended = true
        KeyDoVoice.shared.stop(announce: false)
        active = true
        note = ""
        mode = .filling
        lastActivity = Date()
        idleLeft = nil
        items = FormScanner.scan(target)
        index = items.firstIndex { item in item.kind == .text && textValue(of: item).isEmpty } ?? 0
        showPanel(on: target)
        if items.isEmpty {
            note = "I could not find any boxes on this screen. Open a form, then say \u{201C}Fill by voice\u{201D}."
        } else {
            focus(index)
        }
        voice.start(localeIdentifier: language, commitDelay: 1.1) { [weak self] sentence in
            Task { @MainActor in self?.handle(sentence) }
        }
        startIdleTimer()
    }

    func stop(message: String?) {
        guard active else { return }
        active = false
        idleTimer?.invalidate(); idleTimer = nil
        idleLeft = nil
        voice.stop()
        clearHighlight()
        releaseSpace()
        panel?.close()
        if let window, let panel { window.removeChildWindow(panel) }
        panel = nil
        mode = .filling
        if let message { note = message }
        KeyDoVoice.shared.suspended = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            KeyDoVoice.shared.startWakeIfNeeded()
        }
    }

    func changeLanguage(_ identifier: String) {
        language = identifier
        UserDefaults.standard.set(identifier, forKey: "keydoVoiceLocale")
        voice.changeLanguage(identifier)
    }

    // MARK: Idle timer

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard active else { return }
        let idle = Int(Date().timeIntervalSince(lastActivity))
        if idle >= Self.idleLimit {
            stop(message: "Voice fill turned off after a quiet moment.")
        } else if idle >= Self.idleLimit - 3 {
            idleLeft = Self.idleLimit - idle
        } else if idleLeft != nil {
            idleLeft = nil
        }
    }

    private func touch() { lastActivity = Date(); idleLeft = nil }

    // MARK: Moving around

    func next() { touch(); move(1) }
    func back() { touch(); move(-1) }

    private func move(_ step: Int) {
        let target = index + step
        if target < 0 { note = "This is the first box."; return }
        if target >= items.count {
            note = "That was the last box here. For another tab or page, say its name, then keep talking."
            mode = .filling
            return
        }
        focus(target)
    }

    private func focus(_ position: Int) {
        guard position >= 0, position < items.count else { return }
        index = position
        mode = .filling
        note = ""
        let item = items[position]
        item.view?.scrollToVisible(item.view?.bounds ?? .zero)
        if item.kind == .text { window?.makeFirstResponder(item.view) }
        highlight(item.kind == .text ? nil : item.view)
        if item.isChoice { openOptions() }
        relayout()
        keepClearOfPanel(item.view)
    }

    /// Looks at the screen again, so a box that appeared (a new tab, a revealed section) is found.
    private func rescan() {
        guard let window else { return }
        let keep = current?.key
        let fresh = FormScanner.scan(window)
        items = fresh
        if let keep, let position = fresh.firstIndex(where: { $0.key == keep }) { index = position } else { index = min(index, max(0, fresh.count - 1)) }
    }

    private func textValue(of item: FormItem) -> String {
        if let field = item.view as? NSTextField { return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let text = item.view as? NSTextView { return text.string.trimmingCharacters(in: .whitespacesAndNewlines) }
        return ""
    }

    // MARK: Options

    func openOptions() {
        guard let item = current, item.isChoice else {
            if let position = items.indices.first(where: { $0 > index && items[$0].isChoice }) ?? items.indices.first(where: { items[$0].isChoice }) {
                focus(position)
            } else {
                note = "There are no choices on this screen."
            }
            return
        }
        mode = .options
        optionTop = ((item.selected ?? 0) / Self.pageSize) * Self.pageSize
        note = ""
        relayout()
    }

    func closeOptions() { mode = .filling; note = ""; relayout() }

    func scrollOptions(_ direction: Int) {
        touch()
        guard let item = current else { return }
        let target = optionTop + direction * Self.pageSize
        if target < 0 { note = "This is the top of the list."; optionTop = 0; return }
        if target >= item.options.count { note = "That is the end of the list."; return }
        optionTop = target
        note = ""
    }

    /// Picks an option on the control that is on screen. Returns true when it worked.
    @discardableResult func pick(_ option: Int) -> Bool {
        touch()
        guard let item = current, option >= 0, option < item.options.count else { return false }
        let position = item.positions[option]
        switch item.kind {
        case .popup:
            guard let popup = item.view as? NSPopUpButton else { return false }
            if popup.pullsDown {
                popup.menu?.performActionForItem(at: position)
            } else {
                popup.selectItem(at: position)
                if let action = popup.action { popup.sendAction(action, to: popup.target) } else { popup.menu?.performActionForItem(at: position) }
            }
        case .segmented:
            guard let segmented = item.view as? NSSegmentedControl else { return false }
            segmented.selectedSegment = position
            if let action = segmented.action { segmented.sendAction(action, to: segmented.target) }
        case .toggle:
            if let toggle = item.view as? NSSwitch {
                toggle.state = position == 0 ? .on : .off
                if let action = toggle.action { toggle.sendAction(action, to: toggle.target) }
            } else if let box = item.view as? NSButton {
                box.state = position == 0 ? .on : .off
                if let action = box.action { box.sendAction(action, to: box.target) }
            } else { return false }
        case .custom:
            item.handler?(position)
        case .text:
            return false
        }
        note = "\(item.label): \(item.options[option])"
        mode = .filling
        // The screen may change after a choice (for example a new tab), so look again before moving on.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard self.active else { return }
            self.rescan()
            if let position = self.items.firstIndex(where: { $0.key == item.key }) { self.index = position }
            self.move(1)
        }
        return true
    }

    // MARK: Spoken words

    private static let numbers: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10
    ]

    private func clean(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
    }

    private func matchOption(_ spoken: String, in item: FormItem) -> Int? {
        var wanted = clean(spoken)
        for prefix in ["select ", "choose ", "pick ", "option ", "number ", "item ", "the "] where wanted.hasPrefix(prefix) { wanted.removeFirst(prefix.count) }
        for prefix in ["option ", "number "] where wanted.hasPrefix(prefix) { wanted.removeFirst(prefix.count) }
        if let number = Int(wanted) ?? Self.numbers[wanted], number >= 1, number <= item.options.count { return number - 1 }
        if wanted == "last" { return item.options.count - 1 }
        if item.kind == .toggle {
            if ["on", "yes", "enable", "enabled", "turn on", "true"].contains(wanted) { return 0 }
            if ["off", "no", "disable", "disabled", "turn off", "false"].contains(wanted) { return 1 }
        }
        let names = item.options.map { clean($0) }
        if let exact = names.firstIndex(of: wanted) { return exact }
        if let prefix = names.firstIndex(where: { $0.hasPrefix(wanted) && wanted.count >= 3 }) { return prefix }
        if let contains = names.firstIndex(where: { ($0.contains(wanted) && wanted.count >= 3) || (wanted.contains($0) && $0.count >= 3) }) { return contains }
        let spokenWords = Set(wanted.split(separator: " ").map(String.init).filter { $0.count > 2 })
        guard !spokenWords.isEmpty else { return nil }
        var best: (Int, Int)?
        for (position, name) in names.enumerated() {
            let overlap = spokenWords.intersection(Set(name.split(separator: " ").map(String.init))).count
            if overlap > 0, overlap > (best?.1 ?? 0) { best = (position, overlap) }
        }
        return best?.0
    }

    func handle(_ raw: String) {
        guard active else { return }
        let spoken = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        touch()
        rescan()
        let lower = clean(spoken)

        if ["done", "finish", "finished", "stop", "that's all", "thats all", "i am done", "stop voice", "stop listening", "close"].contains(lower), mode == .filling {
            stop(message: "Voice fill finished.")
            return
        }

        if mode == .options, let item = current, item.isChoice {
            handleOption(spoken, lower: lower, item: item)
            return
        }

        if ["next", "skip", "next one", "next box", "next field"].contains(lower) { move(1); return }
        if ["back", "previous", "go back", "previous box", "previous one"].contains(lower) { move(-1); return }
        if ["scroll down", "page down", "go down"].contains(lower) { scrollPage(1); return }
        if ["scroll up", "page up", "go up"].contains(lower) { scrollPage(-1); return }
        if ["options", "show options", "open options", "list options", "choices", "show choices", "choose", "show list", "what are the options"].contains(lower) {
            openOptions()
            return
        }

        if ["clear", "clear this", "clear it", "delete", "start again"].contains(lower), let item = current, item.kind == .text {
            replaceText(of: item, with: "")
            note = "Cleared \(item.label)."
            return
        }

        // "go to <box>" jumps to a box.
        for joiner in ["go to ", "jump to ", "open "] where lower.hasPrefix(joiner) {
            let name = String(lower.dropFirst(joiner.count))
            if let position = items.firstIndex(where: { clean($0.label) == name || clean($0.label).contains(name) && name.count >= 3 }) { focus(position); return }
        }

        // "<box name> is <answer>"
        for (position, item) in items.enumerated() {
            let label = clean(item.label)
            guard label.count >= 2, !label.hasPrefix("box "), !label.hasPrefix("choice ") else { continue }
            for joiner in [" is ", " as ", " to ", ": ", " equals "] where lower.hasPrefix(label + joiner) {
                let answer = String(spoken.dropFirst(label.count + joiner.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                focusQuietly(position)
                answerCurrent(answer)
                return
            }
        }
        // Naming a box on its own jumps to it.
        if let position = items.firstIndex(where: { clean($0.label) == lower && !lower.hasPrefix("box ") }) { focus(position); return }

        answerCurrent(spoken)
    }

    /// Moves to a box without opening its list, for "<box> is <answer>".
    private func focusQuietly(_ position: Int) {
        guard position >= 0, position < items.count else { return }
        index = position
        mode = .filling
        let item = items[position]
        item.view?.scrollToVisible(item.view?.bounds ?? .zero)
        if item.kind == .text { window?.makeFirstResponder(item.view) }
        highlight(item.kind == .text ? nil : item.view)
        keepClearOfPanel(item.view)
    }

    private func handleOption(_ spoken: String, lower: String, item: FormItem) {
        if ["scroll down", "down", "page down", "next page", "more", "go down", "show more"].contains(lower) { scrollOptions(1); return }
        if ["scroll up", "up", "page up", "previous page", "go up", "show previous"].contains(lower) { scrollOptions(-1); return }
        if ["close", "cancel", "hide", "hide options", "never mind", "back", "close options"].contains(lower) { closeOptions(); return }
        if ["next", "skip", "next box", "next one"].contains(lower) { closeOptions(); move(1); return }
        if let option = matchOption(spoken, in: item) {
            pick(option)
        } else {
            note = "I did not find \u{201C}\(spoken)\u{201D}. Say a name or a number, or say scroll down."
        }
    }

    /// The words are the answer for the box that is selected now.
    private func answerCurrent(_ spoken: String) {
        guard let item = current else {
            note = "There is nothing to fill on this screen."
            return
        }
        switch item.kind {
        case .text:
            if fill(item, with: spoken), !item.multiline { move(1) }
        default:
            if let option = matchOption(spoken, in: item) {
                pick(option)
            } else if let (position, option) = optionAnywhere(spoken) {
                // A tab or choice somewhere else on the screen: switch to it and choose.
                focusQuietly(position)
                pick(option)
            } else {
                note = "I did not find \u{201C}\(spoken)\u{201D} here. Say a name or a number."
                openOptions()
            }
        }
    }

    /// An exact option name that belongs to some other choice on the screen, such as a tab name.
    private func optionAnywhere(_ spoken: String) -> (Int, Int)? {
        let wanted = clean(spoken)
        guard wanted.count >= 3 else { return nil }
        for (position, item) in items.enumerated() where item.isChoice {
            if let option = item.options.firstIndex(where: { clean($0) == wanted }) { return (position, option) }
        }
        return nil
    }

    // MARK: Typing into a box

    private func formatted(_ text: String, label: String) -> String {
        let hint = label.lowercased()
        if hint.contains("email") {
            return text.lowercased().replacingOccurrences(of: " at the rate ", with: "@").replacingOccurrences(of: " at ", with: "@")
                .replacingOccurrences(of: " dot ", with: ".").replacingOccurrences(of: " ", with: "")
        }
        if hint.contains("phone") || hint.contains("mobile") {
            let compact = text.replacingOccurrences(of: " ", with: "")
            if compact.allSatisfy({ $0.isNumber || $0 == "+" || $0 == "-" }) { return compact }
        }
        return text
    }

    private func editor(for item: FormItem) -> NSTextView? {
        guard item.kind == .text else { return nil }
        window?.makeFirstResponder(item.view)
        if let text = item.view as? NSTextView { return text }
        return (item.view as? NSTextField)?.currentEditor() as? NSTextView
    }

    @discardableResult private func fill(_ item: FormItem, with spoken: String) -> Bool {
        let value = formatted(spoken, label: item.label)
        guard let editor = editor(for: item) else {
            note = "I could not type into \(item.label)."
            return false
        }
        if item.multiline {
            editor.moveToEndOfDocument(nil)
            let lead = editor.string.isEmpty ? "" : " "
            editor.insertText(lead + value, replacementRange: editor.selectedRange())
            editor.scrollRangeToVisible(editor.selectedRange())
            note = "Added to \(item.label). Say next when this box is done."
        } else {
            editor.selectAll(nil)
            editor.insertText(value, replacementRange: editor.selectedRange())
            editor.scrollRangeToVisible(editor.selectedRange())
            note = "\(item.label): \(value)"
        }
        return true
    }

    private func replaceText(of item: FormItem, with text: String) {
        guard let editor = editor(for: item) else { return }
        editor.selectAll(nil)
        if text.isEmpty { editor.delete(nil) } else { editor.insertText(text, replacementRange: editor.selectedRange()) }
    }

    // MARK: Scrolling the page

    private func outerScrollView(of view: NSView?) -> NSScrollView? {
        var found: NSScrollView?
        var node = view
        while let here = node {
            if let scroll = here as? NSScrollView, scroll.documentView != nil { found = scroll }
            node = here.superview
        }
        return found
    }

    private func biggestScrollView(in root: NSView) -> NSScrollView? {
        var best: NSScrollView?
        func visit(_ view: NSView) {
            if view.isHidden || view is WKWebView { return }
            if let scroll = view as? NSScrollView, scroll.documentView != nil {
                if best == nil || scroll.frame.width * scroll.frame.height > (best?.frame.width ?? 0) * (best?.frame.height ?? 0) { best = scroll }
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        return best
    }

    private func scrollPage(_ direction: CGFloat) {
        let scroll = outerScrollView(of: current?.view) ?? window?.contentView.flatMap { biggestScrollView(in: $0) }
        guard let scroll, let document = scroll.documentView else { note = "Nothing to scroll here."; return }
        let clip = scroll.contentView
        let step = clip.bounds.height * 0.8
        var origin = clip.bounds.origin
        origin.y += document.isFlipped ? step * direction : -step * direction
        origin.y = max(0, min(origin.y, document.bounds.height - clip.bounds.height))
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
        note = direction > 0 ? "Scrolled down." : "Scrolled up."
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard self.active else { return }
            self.rescan()
        }
    }

    // MARK: Room for the panel

    private var reserved: [ObjectIdentifier: (scroll: NSScrollView, insets: NSEdgeInsets, auto: Bool)] = [:]

    /// Adds blank space under the content, the height of the panel, so the last box is never hidden behind it.
    private func reserveSpace(_ height: CGFloat) {
        guard let root = window?.contentView else { return }
        func visit(_ view: NSView) {
            if view.isHidden || view is WKWebView { return }
            if let scroll = view as? NSScrollView, scroll.documentView != nil, scroll.frame.width > 220, scroll.frame.height > 160 {
                let key = ObjectIdentifier(scroll)
                if reserved[key] == nil { reserved[key] = (scroll, scroll.contentInsets, scroll.automaticallyAdjustsContentInsets) }
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        for entry in reserved.values {
            var insets = entry.insets
            insets.bottom += height
            entry.scroll.automaticallyAdjustsContentInsets = false
            entry.scroll.contentInsets = insets
        }
    }

    private func releaseSpace() {
        for entry in reserved.values {
            entry.scroll.contentInsets = entry.insets
            entry.scroll.automaticallyAdjustsContentInsets = entry.auto
        }
        reserved.removeAll()
    }

    /// Scrolls so the box being filled is above the panel, not behind it.
    private func keepClearOfPanel(_ view: NSView?) {
        guard let view else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard self.active, let window = self.window, let panel = self.panel, view.window === window,
                  let scroll = self.outerScrollView(of: view), let document = scroll.documentView else { return }
            let box = window.convertToScreen(view.convert(view.bounds, to: nil))
            let limit = panel.frame.maxY + 16
            guard box.minY < limit else { return }
            let clip = scroll.contentView
            var origin = clip.bounds.origin
            let delta = limit - box.minY
            origin.y += document.isFlipped ? delta : -delta
            let maxY = max(0, document.bounds.height + scroll.contentInsets.bottom - clip.bounds.height)
            origin.y = max(0, min(origin.y, maxY))
            clip.scroll(to: origin)
            scroll.reflectScrolledClipView(clip)
        }
    }

    // MARK: Highlight

    private func highlight(_ view: NSView?) {
        clearHighlight()
        guard let view else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        highlighted = (view, layer.borderWidth, layer.borderColor)
        layer.borderWidth = 2
        layer.borderColor = NSColor(Butter.coral).cgColor
        layer.cornerRadius = 7
    }

    private func clearHighlight() {
        if let saved = highlighted {
            saved.view.layer?.borderWidth = saved.width
            saved.view.layer?.borderColor = saved.color
        }
        highlighted = nil
    }

    // MARK: Panel

    private func showPanel(on target: NSWindow) {
        panel?.close()
        let view = FormVoicePanelView(form: self, voice: voice)
        let hosting = NSHostingView(rootView: view)
        let created = FormVoicePanel(content: hosting)
        panel = created
        target.addChildWindow(created, ordered: .above)
        relayout()
        created.orderFront(nil)
    }

    private func relayout() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, let window = self.window else { return }
            panel.fit(to: window)
            self.reserveSpace(panel.frame.height + 26 + 14)
        }
    }
}

extension Notification.Name {
    /// One voice feature started and the others should let go of the microphone.
    static let keydoVoiceTakeover = Notification.Name("keydoVoiceTakeover")
}

/// A small floating panel that never takes the keyboard from the window behind it.
final class FormVoicePanel: NSPanel {
    private let hosting: NSHostingView<FormVoicePanelView>

    init(content: NSHostingView<FormVoicePanelView>) {
        hosting = content
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 140), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func fit(to window: NSWindow) {
        let size = hosting.fittingSize
        let width = max(480, size.width)
        let origin = NSPoint(x: window.frame.midX - width / 2, y: window.frame.minY + 26)
        setFrame(NSRect(origin: origin, size: NSSize(width: width, height: size.height)), display: true)
    }
}

// MARK: - The panel

struct FormVoicePanelView: View {
    @ObservedObject var form: FormVoice
    @ObservedObject var voice: WishVoiceController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if form.mode == .options, let item = form.current, item.isChoice {
                optionList(item)
            } else {
                currentBox
            }
            if !voice.heard.isEmpty {
                Text("Hearing: \(voice.heard)").font(.system(size: 13, weight: .medium)).foregroundStyle(FormVoiceInk.accent).lineLimit(2)
            }
            if !form.note.isEmpty { Text(form.note).font(.system(size: 12)).foregroundStyle(FormVoiceInk.main).lineLimit(3) }
            if !voice.errorMessage.isEmpty { Text(voice.errorMessage).font(.system(size: 12)).foregroundStyle(.red) }
            footer
        }
        .padding(14)
        .frame(width: 480, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(red: 1.0, green: 0.985, blue: 0.95)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Butter.coral.opacity(0.7), lineWidth: 1.5))
        .padding(6)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(spacing: 10) {
            KeyDoVoiceIcon(kind: .fill, size: 34, active: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Fill by voice").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Butter.cocoa)
                if form.items.isEmpty {
                    Text("No boxes found").font(.system(size: 12)).foregroundStyle(FormVoiceInk.soft)
                } else {
                    Text("\(form.index + 1) of \(form.items.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(FormVoiceInk.soft)
                }
            }
            Spacer(minLength: 6)
            ProgressView(value: voice.level).frame(width: 40).tint(Butter.coral)
            Picker("", selection: Binding(get: { form.language }, set: { form.changeLanguage($0) })) {
                Text("English").tag("en-IN")
                Text("\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}").tag("hi-IN")
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 120)
            Button { form.stop(message: nil) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(FormVoiceInk.soft)
            }
            .buttonStyle(.plain).help("Stop Fill by voice")
        }
    }

    @ViewBuilder private var currentBox: some View {
        if let item = form.current {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.label).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Butter.cocoa).lineLimit(2)
                Text(item.isChoice ? "Say an option, or say \u{201C}options\u{201D} to see the list." : "Say the answer. It goes straight into the box.")
                    .font(.system(size: 12)).foregroundStyle(FormVoiceInk.soft)
            }
        }
    }

    private func optionList(_ item: FormItem) -> some View {
        let top = min(form.optionTop, max(0, item.options.count - 1))
        let end = min(top + FormVoice.pageSize, item.options.count)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Choose: \(item.label)").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Butter.cocoa).lineLimit(1)
                Spacer()
                Text("\(top + 1)\u{2013}\(end) of \(item.options.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(FormVoiceInk.soft)
            }
            HStack(spacing: 6) {
                Button { form.scrollOptions(-1) } label: { Label("Scroll up", systemImage: "chevron.up") }
                    .disabled(top == 0)
                Button { form.scrollOptions(1) } label: { Label("Scroll down", systemImage: "chevron.down") }
                    .disabled(end >= item.options.count)
                Spacer()
                Button("Close list") { form.closeOptions() }
            }
            .buttonStyle(VoicePillStyle())
            ForEach(top..<end, id: \.self) { position in
                Button { form.pick(position) } label: {
                    HStack(spacing: 10) {
                        Text("\(position + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Circle().fill(Butter.coral))
                        Text(item.options[position]).font(.system(size: 14, weight: .medium)).foregroundStyle(Butter.cocoa).lineLimit(1)
                        Spacer()
                        if item.selected == position { Image(systemName: "checkmark.circle.fill").foregroundStyle(Butter.coral) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(item.selected == position ? Butter.honey.opacity(0.55) : Color.white.opacity(0.7)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("Say a name or number to choose \u{00B7} \u{201C}scroll down\u{201D} \u{00B7} \u{201C}scroll up\u{201D} \u{00B7} \u{201C}close\u{201D}")
                .font(.system(size: 12)).foregroundStyle(FormVoiceInk.soft)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button("Back") { form.back() }.disabled(form.index == 0)
            Button("Next") { form.next() }.disabled(form.index >= form.items.count - 1)
            if form.current?.isChoice == true, form.mode == .filling {
                Button("Options") { form.openOptions() }
            }
            Button("Done") { form.stop(message: "Voice fill finished.") }
            Spacer(minLength: 4)
            if let left = form.idleLeft {
                Text("Turning off in \(left)\u{2026}").font(.system(size: 12, weight: .semibold)).foregroundStyle(Butter.coral)
            } else {
                Text("Say next, back, clear, options or done").font(.system(size: 12)).foregroundStyle(FormVoiceInk.soft)
            }
        }
        .buttonStyle(VoicePillStyle())
    }
}



/// Dark-on-light colours for the panel, so it reads the same in light and dark mode.
enum FormVoiceInk {
    static let main = Color(red: 0.16, green: 0.11, blue: 0.08)
    static let soft = Color(red: 0.34, green: 0.26, blue: 0.21)
    static let accent = Color(red: 0.70, green: 0.28, blue: 0.19)
}

struct VoicePillStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(enabled ? FormVoiceInk.main : FormVoiceInk.soft.opacity(0.5))
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.7 : 1)))
            .overlay(Capsule().stroke(Butter.honey, lineWidth: 1.2))
            .opacity(enabled ? 1 : 0.6)
    }
}

// MARK: - Choices that are drawn by SwiftUI itself

/// A row of buttons that acts like a menu (the tabs of a page, the apps of a switcher) can tell Fill by voice what its
/// options are, so they can be spoken like any other choice.
@MainActor final class VoiceChoiceRegistry {
    static let shared = VoiceChoiceRegistry()
    struct Entry {
        var id: UUID
        var label: String
        var options: [String]
        var selected: Int?
        var frame: CGRect
        var onPick: (Int) -> Void
    }
    private(set) var entries: [UUID: Entry] = [:]

    func set(_ entry: Entry) { entries[entry.id] = entry }
    func remove(_ id: UUID) { entries.removeValue(forKey: id) }
}

private struct VoiceChoicesModifier: ViewModifier {
    var label: String
    var options: [String]
    var selected: Int?
    var onPick: (Int) -> Void
    @State private var token = UUID()
    @State private var frame = CGRect.zero

    private func register() {
        VoiceChoiceRegistry.shared.set(.init(id: token, label: label, options: options, selected: selected, frame: frame, onPick: onPick))
    }

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { frame = proxy.frame(in: .global); register() }
                    .onChange(of: proxy.frame(in: .global)) { _, new in frame = new; register() }
            })
            .onChange(of: options) { _, _ in register() }
            .onChange(of: selected) { _, _ in register() }
            .onDisappear { VoiceChoiceRegistry.shared.remove(token) }
    }
}

extension View {
    /// Lets Fill by voice choose from these options (for example the tabs of a page).
    func voiceChoices(_ label: String, options: [String], selected: Int?, onPick: @escaping (Int) -> Void) -> some View {
        modifier(VoiceChoicesModifier(label: label, options: options, selected: selected, onPick: onPick))
    }
}
