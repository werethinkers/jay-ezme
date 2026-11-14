// Voice commands for KeyDo: one engine, used by the backslash popup and by the assistant at the bottom right.
//
//   "Start listening"  begin, or resume after a pause
//   "Pause listening"  the mic keeps hearing, but only "start listening" and "stop listening" are acted on
//   "Stop listening"   turn the microphone off
//   "Enter"            use the highlighted result (pastes the shortcut in the popup)
//   "Scroll down/up"   move through more matching results
//   "Clear search"     empty the search words
//   "Close popup"      close the popup
//   "Open popup"       open the backslash popup (when listening in the background)
//
// Any other words are the search. They are collected until you say "enter".
import Foundation
import AVFoundation
import Speech
import SwiftUI
import AppKit

extension Notification.Name {
    /// Posted by the keyboard hook when the backslash key is pressed twice.
    static let keydoVoiceActivate = Notification.Name("KeyDoVoiceActivate")
    /// The popup should grow or shrink because voice controls appeared or went away.
    static let keydoVoiceLayoutChanged = Notification.Name("KeyDoVoiceLayoutChanged")
}

/// UserDefaults keys for the voice settings. Plain constants, so the keyboard hook can read them from any thread.
enum VoiceKeys {
    static let continuous = "ezmeVoiceContinuous"
    static let doubleBackslash = "ezmeVoiceDoubleBackslash"
    static let sounds = "ezmeVoiceSounds"
    static let locale = "ezmeVoiceLocale"
    static let wakeAlways = "keydoWakeAlways"
}

enum VoiceCommand: Equatable {
    case start, pause, stop, enter, scrollDown, scrollUp, clear, closePopup, openPopup
}

/// The words KeyDo listens for. Plain data and functions, so it is not tied to the main actor.
enum VoiceGrammar {
    static func normalized(_ text: String) -> [String] {
        let keep = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'"))
        return text.lowercased().components(separatedBy: keep.inverted).filter { !$0.isEmpty }
    }

    static let phrases: [(words: [String], command: VoiceCommand)] = [
        (["start", "listening"], .start), (["resume", "listening"], .start),
        (["pause", "listening"], .pause),
        (["stop", "listening"], .stop),
        (["scroll", "down"], .scrollDown), (["page", "down"], .scrollDown),
        (["scroll", "up"], .scrollUp), (["page", "up"], .scrollUp),
        (["enter"], .enter), (["select", "it"], .enter), (["paste", "it"], .enter), (["insert", "it"], .enter),
        (["clear", "search"], .clear), (["clear", "all"], .clear), (["start", "over"], .clear),
        (["close", "popup"], .closePopup), (["close", "panel"], .closePopup),
        (["open", "popup"], .openPopup), (["show", "popup"], .openPopup), (["show", "shortcuts"], .openPopup),
        (["keydo"], .openPopup), (["hey", "keydo"], .openPopup), (["key", "do"], .openPopup), (["hey", "key", "do"], .openPopup), (["kido"], .openPopup), (["keido"], .openPopup), (["keyedo"], .openPopup), (["kiado"], .openPopup),
    ]

    /// Words that begin a longer command. They are held back until the next word arrives.
    static let starters: Set<String> = ["start", "resume", "pause", "stop", "scroll", "page", "select", "paste", "insert", "clear", "close", "open", "show"]

    static func match(_ words: [String], at index: Int) -> (VoiceCommand, Int)? {
        for entry in phrases.sorted(by: { $0.words.count > $1.words.count }) {
            let end = index + entry.words.count
            if end <= words.count, Array(words[index..<end]) == entry.words { return (entry.command, entry.words.count) }
        }
        return nil
    }
}

@MainActor
final class KeyDoVoice: ObservableObject {
    static let shared = KeyDoVoice()

    enum Phase { case off, listening, paused }
    enum Context { case app, popup }

    struct Handlers {
        var search: (String) -> Void = { _ in }
        var enter: () -> Void = {}
        var move: (Int) -> Void = { _ in }
        var close: () -> Void = {}
        var open: (String) -> Void = { _ in }
        var vocabulary: () -> [String] = { [] }
    }

    // MARK: Published state
    @Published private(set) var phase: Phase = .off {
        didSet { if oldValue != phase { announceLayout() } }
    }
    @Published private(set) var context: Context = .app
    @Published private(set) var partial = ""
    @Published private(set) var phrase = ""
    @Published private(set) var feedback = ""
    @Published private(set) var level: CGFloat = 0
    @Published var errorMessage = ""
    /// The voice settings panel is open inside the popup.
    @Published var popupSettingsOpen = false {
        didSet { if oldValue != popupSettingsOpen { announceLayout() } }
    }

    var wantsExpandedPopup: Bool { (phase != .off && !wakeOnly) || popupSettingsOpen || !errorMessage.isEmpty }

    // MARK: Settings (also edited with @AppStorage in the settings panel)
    /// Listen quietly for "Hey KeyDo" the whole time the app is open (on unless switched off in voice settings).
    var wakeAlways: Bool { UserDefaults.standard.object(forKey: VoiceKeys.wakeAlways) as? Bool ?? true }
    /// True while the mic only waits for the wake phrase and ignores everything else that is said.
    @Published private(set) var wakeOnly = false

    func startWakeIfNeeded() {
        guard wakeAlways, phase == .off, appHandlers != nil else { return }
        context = .app
        wakeOnly = true
        phraseWords = []
        phrase = ""
        phase = .listening
        feedback = ""
        startIdleTimer()
        ensureRunning()
    }

    /// Go back to quietly waiting for "Hey KeyDo", or switch the mic off when that is turned off.
    func rest() {
        if wakeAlways {
            if phase == .off { startWakeIfNeeded(); return }
            context = .app
            wakeOnly = true
            phraseWords = []
            phrase = ""
            partial = ""
            phase = .listening
            idleLeft = nil
            say("Say \u{201C}Hey KeyDo\u{201D} when you need me", sound: nil)
        } else {
            stop(announce: false)
        }
    }

    var continuous: Bool { UserDefaults.standard.object(forKey: VoiceKeys.continuous) as? Bool ?? false }
    var soundsOn: Bool { UserDefaults.standard.object(forKey: VoiceKeys.sounds) as? Bool ?? true }
    private var localeIdentifier: String {
        let saved = UserDefaults.standard.string(forKey: VoiceKeys.locale) ?? ""
        return saved.isEmpty ? Locale.current.identifier : saved
    }

    // MARK: Wiring
    private var popupHandlers: Handlers?
    private var appHandlers: Handlers?
    private var handlers: Handlers? { context == .popup ? popupHandlers : appHandlers }

    func attach(_ context: Context, _ handlers: Handlers) {
        if context == .popup { popupHandlers = handlers } else { appHandlers = handlers }
    }

    func detach(_ context: Context) {
        if context == .popup { popupHandlers = nil } else { appHandlers = nil }
        if self.context == context && phase != .off && context == .app { stop(announce: false) }
    }

    /// The popup has gone away. Keep listening in the background only if the person asked for continuous listening.
    func popupClosed() {
        popupHandlers = nil
        popupSettingsOpen = false
        errorMessage = ""
        guard context == .popup else { return }
        phraseWords = []
        phrase = ""
        if phase != .off && continuous {
            context = .app
            say("Still listening · say “open popup”", sound: nil)
        } else {
            rest()
        }
    }

    // MARK: Session state
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var sessionToken = 0
    private var consumedWords = 0
    private var debounce: Task<Void, Never>?
    private var feedbackClear: Task<Void, Never>?
    private var phraseWords: [String] = []
    private var lastWordAt = Date.distantPast
    private var quickFailures = 0
    private var lastStart = Date.distantPast
    private var running = false
    private var authorizing = false
    private var lastActivity = Date()
    private var idleTimer: Timer?
    @Published private(set) var idleLeft: Int? = nil

    /// Anything heard or said counts as use. The mic turns itself off after 10 quiet seconds, with a 3 second countdown.
    private func touch() {
        lastActivity = Date()
        if idleLeft != nil { idleLeft = nil; feedback = "" }
    }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        lastActivity = Date()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.idleTick() }
        }
    }

    private func idleTick() {
        guard phase != .off else { idleLeft = nil; return }
        if phase == .paused || wakeOnly || (context == .app && continuous) { lastActivity = Date(); idleLeft = nil; return }
        let idle = Date().timeIntervalSince(lastActivity)
        if idle >= 10 {
            idleLeft = nil
            if wakeAlways { rest(); return }
            stop(announce: false)
            say("Mic turned off after 10 seconds of silence. Tap the mic to start again.", sound: .stop)
            return
        }
        if idle >= 7 {
            let left = max(1, Int(ceil(10 - idle)))
            if left != idleLeft { idleLeft = left; say("Turning off in \(left)… say something to keep listening", sound: nil) }
        } else if idleLeft != nil {
            idleLeft = nil
        }
    }

    /// A short message from outside the engine, for example which collection was picked.
    func announce(_ text: String) { say(text, sound: nil); touch() }

    // MARK: Buttons
    func start(_ context: Context) {
        errorMessage = ""
        wakeOnly = false
        if self.context != context { phraseWords = []; phrase = "" }
        self.context = context
        if phase == .listening, running { return }
        phase = .listening
        say("Listening", sound: .start)
        startIdleTimer()
        ensureRunning()
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .listening
        touch()
        say("Listening", sound: .start)
    }

    func pause() {
        guard phase == .listening else { return }
        phase = .paused
        say("Paused · say “start listening”", sound: .pause)
    }

    func stop(announce: Bool = true) {
        let wasOn = phase != .off
        idleTimer?.invalidate()
        idleTimer = nil
        idleLeft = nil
        wakeOnly = false
        debounce?.cancel()
        phase = .off
        tearDown()
        partial = ""
        phraseWords = []
        phrase = ""
        if announce && wasOn { say("Stopped", sound: .stop) } else { feedback = "" }
    }

    func languageChanged() {
        guard phase != .off else { return }
        tearDown()
        ensureRunning()
    }

    // MARK: Recognition
    private func ensureRunning() {
        guard !running, !authorizing else { return }
        authorizing = true
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                self.authorizing = false
                guard self.phase != .off else { return }
                guard status == .authorized else {
                    self.fail("Enable Speech Recognition for KeyDo in System Settings → Privacy & Security.")
                    return
                }
                switch AVCaptureDevice.authorizationStatus(for: .audio) {
                case .authorized:
                    self.beginRecognition()
                case .notDetermined:
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        Task { @MainActor in
                            guard self.phase != .off else { return }
                            if granted { self.beginRecognition() } else { self.fail("Microphone access is needed for voice commands.") }
                        }
                    }
                default:
                    self.fail("Enable Microphone access for KeyDo in System Settings → Privacy & Security.")
                }
            }
        }
    }

    private func beginRecognition() {
        guard phase != .off, !running else { return }
        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            fail("Speech recognition is not available right now.")
            return
        }
        self.recognizer = recognizer
        sessionToken += 1
        let token = sessionToken
        consumedWords = 0
        partial = ""

        let audioRequest = SFSpeechAudioBufferRecognitionRequest()
        audioRequest.shouldReportPartialResults = true
        audioRequest.taskHint = .dictation
        audioRequest.contextualStrings = contextualWords()
        request = audioRequest

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            fail("No microphone was found.")
            return
        }
        Self.installTap(on: input, format: format, request: audioRequest) { [weak self] value in
            DispatchQueue.main.async { self?.pushLevel(value) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            fail("Could not start the microphone: \(error.localizedDescription)")
            return
        }
        running = true
        lastStart = Date()
        task = recognizer.recognitionTask(with: audioRequest) { [weak self] result, error in
            Task { @MainActor in self?.handle(result: result, error: error, token: token) }
        }
    }

    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, request: SFSpeechAudioBufferRecognitionRequest, onLevel: @escaping @Sendable (Float) -> Void) {
        var counter = 0
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            counter += 1
            if counter % 4 == 0 { onLevel(rms(buffer)) }
        }
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count { sum += data[index] * data[index] }
        return (sum / Float(count)).squareRoot()
    }

    private func pushLevel(_ rms: Float) {
        guard phase == .listening else { if level != 0 { level = 0 }; return }
        let decibels = 20 * log10(max(rms, 0.00001))
        let normal = CGFloat(max(0, min(1, (decibels + 50) / 40)))
        let smooth = level * 0.5 + normal * 0.5
        if normal > 0.45 { touch() }
        if abs(smooth - level) > 0.03 { level = smooth }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, token: Int) {
        guard token == sessionToken, phase != .off else { return }
        if let result {
            let text = result.bestTranscription.formattedString
            if text != partial, !text.isEmpty { touch() }
            partial = text
            if result.isFinal {
                debounce?.cancel()
                process(text, final: true)
                recycle(after: 0.15)
                return
            }
            scheduleProcess(text)
        }
        if error != nil, result?.isFinal != true {
            debounce?.cancel()
            if !partial.isEmpty { process(partial, final: true) }
            quickFailures = Date().timeIntervalSince(lastStart) < 2 ? quickFailures + 1 : 0
            if quickFailures >= 5 {
                fail("Voice commands stopped because the speech service is not responding. Check your internet connection, then press Start.")
                return
            }
            recycle(after: 0.4)
        }
    }

    private func scheduleProcess(_ text: String) {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self?.process(text, final: false)
        }
    }

    /// The recognizer ends a task after a pause or about a minute. Begin a new one so listening feels unbroken.
    private func recycle(after delay: TimeInterval) {
        tearDown()
        guard phase != .off else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.phase != .off, !self.running else { return }
            self.beginRecognition()
        }
    }

    private func tearDown() {
        sessionToken += 1
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        running = false
        level = 0
    }

    private func fail(_ message: String) {
        errorMessage = message
        stop(announce: false)
        announceLayout()
    }

    private func contextualWords() -> [String] {
        var words = ["enter", "scroll down", "scroll up", "start listening", "pause listening", "stop listening", "clear search", "close popup", "open popup", "hey keydo", "keydo"]
        words += (handlers?.vocabulary() ?? []).prefix(120)
        return words
    }

    private func process(_ text: String, final: Bool) {
        let words = VoiceGrammar.normalized(text)
        if words.count < consumedWords { consumedWords = 0 }
        guard words.count > consumedWords else { return }
        var fresh = Array(words[consumedWords...])
        if !final, let last = fresh.last, VoiceGrammar.starters.contains(last), VoiceGrammar.match(fresh, at: fresh.count - 1) == nil {
            fresh.removeLast()
        }
        guard !fresh.isEmpty else { return }
        consumedWords += fresh.count
        interpret(fresh)
    }

    private func interpret(_ fresh: [String]) {
        if wakeOnly {
            var at = 0
            while at < fresh.count {
                if let (command, length) = VoiceGrammar.match(fresh, at: at) {
                    if command == .openPopup { run(command); return }
                    at += length
                } else { at += 1 }
            }
            return
        }
        var index = 0
        var gathered: [String] = []
        while index < fresh.count {
            if let (command, length) = VoiceGrammar.match(fresh, at: index) {
                if !gathered.isEmpty { addToPhrase(gathered); gathered = [] }
                run(command)
                index += length
            } else {
                gathered.append(fresh[index])
                index += 1
            }
        }
        if !gathered.isEmpty { addToPhrase(gathered) }
    }

    private func addToPhrase(_ words: [String]) {
        guard phase == .listening else { return }
        if Date().timeIntervalSince(lastWordAt) > 8 { phraseWords = [] }
        lastWordAt = Date()
        phraseWords += words
        phrase = phraseWords.joined(separator: " ")
        handlers?.search(phrase)
        // At the app level, "open the browser" or "go to dashboard" happens straight away.
        if context == .app, let first = phraseWords.first, first == "open" || first == "go",
           phraseWords.count >= 2, !["to", "the", "my", "a"].contains(phraseWords.last ?? "") {
            let spoken = phrase
            phraseWords = []
            phrase = ""
            handlers?.search("")
            say("Opening", sound: .enter)
            handlers?.open(spoken)
        }
    }

    private func run(_ command: VoiceCommand) {
        switch command {
        case .start:
            if phase == .paused { resume() } else if phase == .listening { say("Already listening", sound: nil) }
        case .stop:
            stop()
        case .pause:
            pause()
        default:
            guard phase == .listening, !wakeOnly || command == .openPopup else { return }
            switch command {
            case .enter:
                say("Enter", sound: .enter)
                let handler = handlers
                phraseWords = []
                phrase = ""
                handler?.enter()
                if !continuous && context == .app { stop(announce: false) }
            case .scrollDown:
                say("Scroll down", sound: nil)
                handlers?.move(3)
            case .scrollUp:
                say("Scroll up", sound: nil)
                handlers?.move(-3)
            case .clear:
                phraseWords = []
                phrase = ""
                handlers?.search("")
                say("Cleared", sound: nil)
            case .closePopup:
                if context == .popup { say("Closing", sound: nil); handlers?.close() }
            case .openPopup:
                touch()
                if context == .popup { say("I\u{2019}m listening", sound: nil) }
                if context == .app {
                    wakeOnly = false
                    say("Opening the popup", sound: .enter)
                    NotificationCenter.default.post(name: .miniJOpenPicker, object: nil, userInfo: ["voice": true])
                }
            default:
                break
            }
        }
    }

    // MARK: Feedback
    enum Cue { case start, pause, stop, enter }

    private func say(_ text: String, sound: Cue?) {
        feedback = text
        feedbackClear?.cancel()
        feedbackClear = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            self?.feedback = ""
        }
        guard soundsOn, let sound else { return }
        let name: String
        switch sound {
        case .start: name = "Pop"
        case .pause: name = "Bottle"
        case .stop: name = "Basso"
        case .enter: name = "Tink"
        }
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func announceLayout() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: .keydoVoiceLayoutChanged, object: nil) }
    }

    // MARK: Scrolling a normal screen by voice
    static func scrollMainWindow(_ direction: Int) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }), let root = window.contentView else { return }
        var best: NSScrollView?
        func walk(_ view: NSView) {
            if let scroll = view as? NSScrollView, scroll.documentView != nil, scroll.frame.height > 150 {
                let area = scroll.frame.width * scroll.frame.height
                if let current = best { if area > current.frame.width * current.frame.height { best = scroll } } else { best = scroll }
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        guard let scroll = best, let document = scroll.documentView else { return }
        let clip = scroll.contentView
        let page = clip.bounds.height * 0.8
        let sign: CGFloat = document.isFlipped ? 1 : -1
        let limit = max(0, document.frame.height - clip.bounds.height)
        let target = min(limit, max(0, clip.bounds.origin.y + sign * CGFloat(direction) * page))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            clip.animator().setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: target))
        }
        scroll.reflectScrolledClipView(clip)
    }
}

// MARK: - Views

struct VoiceMeter: View {
    var level: CGFloat
    var active: Bool
    private let shape: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(active ? Butter.coral : Color.gray.opacity(0.45))
                    .frame(width: 3, height: 5 + (active ? 15 * min(1, level * shape[index] * 1.4 + 0.05) : 0))
            }
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.12), value: level)
    }
}

/// Status, what was heard, and Start / Pause / Stop. Used in the popup and in the bottom-right assistant.
struct VoiceControlBar: View {
    @ObservedObject var voice: KeyDoVoice
    var context: KeyDoVoice.Context
    var onSettings: (() -> Void)? = nil

    private var title: String {
        switch voice.phase {
        case .off: return "Voice commands are off"
        case .listening: return voice.wakeOnly ? "Waiting for \u{201C}Hey KeyDo\u{201D}" : "Listening"
        case .paused: return "Paused"
        }
    }

    private var subtitle: String {
        if !voice.errorMessage.isEmpty { return voice.errorMessage }
        if !voice.feedback.isEmpty { return voice.feedback }
        if voice.wakeOnly { return "Say \u{201C}Hey KeyDo\u{201D} to wake me" }
        if !voice.partial.isEmpty && voice.phase == .listening { return "“\(voice.partial)”" }
        switch voice.phase {
        case .off: return context == .popup ? "Press Start, or press \\ twice" : "Press Start and say a shortcut or “open dashboard”"
        case .listening: return context == .popup ? "Say a shortcut, then “enter”" : "Say a shortcut, then “enter”"
        case .paused: return "Say “start listening” to continue"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(voice.phase == .listening ? Butter.coral.opacity(0.16) : Color.gray.opacity(0.12)).frame(width: 34, height: 34)
                if voice.phase == .listening {
                    VoiceMeter(level: voice.level, active: true)
                } else {
                    Image(systemName: voice.phase == .paused ? "pause.fill" : "mic.slash.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(voice.phase == .paused ? Color.orange : Color.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Butter.cocoa).lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(voice.errorMessage.isEmpty ? Color.secondary : Color.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            HStack(spacing: 5) {
                control("play.fill", "Start", enabled: voice.phase != .listening, tint: Butter.coral, help: voice.phase == .paused ? "Start listening again" : "Start listening") {
                    if voice.phase == .paused { voice.resume() } else { voice.start(context) }
                }
                control("pause.fill", "Pause", enabled: voice.phase == .listening, tint: .orange, help: "Pause listening. Say “start listening” to continue") { voice.pause() }
                control("stop.fill", "Stop", enabled: voice.phase != .off, tint: .red, help: "Stop listening and turn the microphone off") { voice.stop() }
                if let onSettings {
                    Button(action: onSettings) {
                        Image(systemName: "gearshape").font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28)
                            .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).help("Voice settings")
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Butter.coral.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Butter.coral.opacity(voice.phase == .listening ? 0.45 : 0.2)))
        .animation(.easeInOut(duration: 0.18), value: voice.phase)
    }

    private func control(_ symbol: String, _ label: String, enabled: Bool, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(enabled ? tint : Color.secondary.opacity(0.55))
            .padding(.horizontal, 8).frame(height: 28)
            .background((enabled ? tint : Color.gray).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

/// Voice settings. The same panel is used in the popup (gear button) and in the bottom-right assistant.
struct VoiceSettingsPanel: View {
    @ObservedObject var voice: KeyDoVoice
    @AppStorage(VoiceKeys.continuous) private var continuous = false
    @AppStorage(VoiceKeys.wakeAlways) private var wakeAlways = true
    @AppStorage(VoiceKeys.doubleBackslash) private var doubleBackslash = true
    @AppStorage(VoiceKeys.sounds) private var sounds = true
    @AppStorage(VoiceKeys.locale) private var locale = ""

    private let languages: [(String, String)] = [("", "Same as this Mac"), ("en-IN", "English (India)"), ("en-US", "English (US)"), ("en-GB", "English (UK)"), ("hi-IN", "Hindi")]
    private let commands: [(String, String)] = [
        ("Start listening", "Begin or resume"), ("Pause listening", "Hold commands"), ("Stop listening", "Turn the mic off"),
        ("Enter", "Use the highlighted shortcut"), ("Scroll down", "More results"), ("Scroll up", "Previous results"),
        ("Clear search", "Start the search again"), ("Close popup", "Close the popup"), ("Open popup", "Open it by voice"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic").foregroundStyle(Butter.coral)
                Text("Voice settings").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            toggle("Always listen for “Hey KeyDo”", "While KeyDo is open the mic waits quietly and ignores everything except “Hey KeyDo”, which opens the popup. macOS shows its mic indicator while this is on.", $wakeAlways)
                .onChange(of: wakeAlways) { on in if on { voice.startWakeIfNeeded() } else if voice.wakeOnly { voice.stop(announce: false) } }
            toggle("Keep listening after a shortcut is pasted", "The microphone stays on in the background. Say “open popup” to bring the popup back.", $continuous)
            toggle("Press \\ twice to start voice", "A quick double backslash starts listening. Turn this off if you type \\\\ in code or file paths.", $doubleBackslash)
            toggle("Sound cues", "A short sound when listening starts, pauses, stops or when you say enter.", $sounds)
            HStack {
                Text("Language").font(.system(size: 12, weight: .medium))
                Spacer()
                Picker("", selection: $locale) {
                    ForEach(languages, id: \.0) { Text($0.1).tag($0.0) }
                }.labelsHidden().frame(width: 170)
                    .onChange(of: locale) { _ in voice.languageChanged() }
            }
            Divider()
            Text("What you can say").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(commands, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("“\(item.0)”").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Butter.cocoa)
                        Text(item.1).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Text("Anything else you say is the search. Voice recognition uses Apple's speech service, so words you say may be sent to Apple to be turned into text.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Butter.coral.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Butter.coral.opacity(0.22)))
    }

    private func toggle(_ title: String, _ detail: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.toggleStyle(.switch).controlSize(.small)
    }
}

// MARK: - Bottom-right assistant

@MainActor
final class AppVoiceModel: ObservableObject {
    @Published private(set) var query = ""
    @Published var selected = 0
    @Published private(set) var matches: [Clip] = []
    var clips: [Clip] = []
    var collections: [String] = []
    var onOpen: (String) -> Void = { _ in }
    var afterOpen: () -> Void = {}

    func setQuery(_ text: String) {
        query = text
        selected = 0
        refresh()
    }

    var matchingCollection: String? {
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return nil }
        return collections.first { $0.localizedCaseInsensitiveContains(phrase) }
    }

    private func refresh() {
        let words = VoiceGrammar.normalized(query)
        guard !words.isEmpty else { matches = []; return }
        let joined = words.joined()
        func rank(_ clip: Clip) -> Int {
            let key = clip.key.drop(while: { $0 == "/" || $0 == "\\" }).lowercased()
            let name = clip.name.lowercased()
            if key == joined || name == words.joined(separator: " ") { return 0 }
            if key.hasPrefix(words[0]) || name.hasPrefix(words[0]) { return 1 }
            if name.contains(words[0]) || key.contains(words[0]) { return 2 }
            return 3
        }
        let found = clips.filter { clip in
            let haystack = (clip.key + " " + clip.name + " " + clip.text + " " + clip.allGroups.joined(separator: " ")).lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
        matches = Array(found.sorted { rank($0) < rank($1) }.prefix(40))
    }

    func move(_ delta: Int) {
        if matches.isEmpty {
            KeyDoVoice.scrollMainWindow(delta > 0 ? 1 : -1)
        } else {
            selected = min(matches.count - 1, max(0, selected + delta))
        }
    }

    func open(_ clip: Clip) {
        onOpen(clip.key)
        reset()
        afterOpen()
    }

    func enter() {
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if matches.indices.contains(selected) {
            open(matches[selected])
        } else if let collection = matchingCollection {
            onOpen("collection:\(collection)")
            reset()
            afterOpen()
        } else if !phrase.isEmpty {
            onOpen(phrase)
            reset()
            afterOpen()
        }
    }

    func reset() {
        query = ""
        matches = []
        selected = 0
    }
}

/// The voice assistant at the bottom right of the app: the same commands as the popup.
@MainActor
struct VoiceSearchAssistant: View {
    var clips: [Clip]
    var collections: [String]
    var onOpen: (String) -> Void
    @ObservedObject private var voice = KeyDoVoice.shared
    @StateObject private var model = AppVoiceModel()
    @State private var expanded = false
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if expanded { card }
            microphoneButton
        }
        .onAppear { configure() }
        .onChange(of: clips.count) { _ in model.clips = clips }
        .onChange(of: collections) { value in model.collections = value }
        .onDisappear { KeyDoVoice.shared.detach(.app) }
    }

    private func configure() {
        model.clips = clips
        model.collections = collections
        model.onOpen = onOpen
        let expandedBinding = $expanded
        model.afterOpen = { withAnimation(.easeInOut(duration: 0.2)) { expandedBinding.wrappedValue = false } }
        var handlers = KeyDoVoice.Handlers()
        handlers.search = { [weak model] text in model?.setQuery(text) }
        handlers.enter = { [weak model] in model?.enter() }
        handlers.move = { [weak model] delta in model?.move(delta) }
        handlers.open = { [weak model] spoken in model?.onOpen(spoken); model?.afterOpen() }
        handlers.vocabulary = { [weak model] in
            guard let model else { return [] }
            return model.clips.prefix(60).flatMap { clip in [clip.name, String(clip.key.drop(while: { $0 == "/" || $0 == "\\" }))] }.filter { !$0.isEmpty }
        }
        KeyDoVoice.shared.attach(.app, handlers)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { KeyDoVoice.shared.startWakeIfNeeded() }
    }

    private var microphoneButton: some View {
        let listening = voice.phase == .listening
        let paused = voice.phase == .paused
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                if expanded {
                    expanded = false
                    if voice.context == .app && !voice.continuous { voice.rest() }
                } else {
                    expanded = true
                    if voice.phase == .off || voice.wakeOnly { voice.start(.app) }
                }
            }
        } label: {
            Image(systemName: listening ? "waveform" : (paused ? "pause.fill" : "mic.fill"))
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(LinearGradient(colors: listening ? [Butter.coral, Color.red] : (paused ? [Color.orange, Butter.coral] : [Butter.cocoa, Butter.cocoa.opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.82), lineWidth: 2))
                .overlay(Circle().stroke(Butter.coral.opacity(listening ? 0.4 : 0), lineWidth: 2).scaleEffect(1 + (listening ? voice.level * 0.4 : 0)))
                .shadow(color: Butter.coral.opacity(0.28), radius: 9, y: 3)
        }
        .buttonStyle(.plain)
        .help(voice.phase == .off ? "Voice commands" : "Voice commands · \(voice.phase == .listening ? "listening" : "paused")")
        .accessibilityLabel("Voice commands")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic").foregroundStyle(Butter.coral)
                Text("Voice commands").font(.system(size: 14, weight: .semibold)).foregroundStyle(Butter.cocoa)
                Spacer()
                Button { withAnimation { expanded = false } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("Hide")
            }
            if voice.context == .popup && voice.phase != .off {
                Label("Voice is working in the shortcut popup.", systemImage: "keyboard")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                VoiceControlBar(voice: voice, context: .app, onSettings: { withAnimation(.easeInOut(duration: 0.18)) { showSettings.toggle() } })
                if showSettings { ScrollView { VoiceSettingsPanel(voice: voice) }.frame(maxHeight: 260) }
                if !model.query.isEmpty {
                    Text("Search · \(model.query)")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9).background(Butter.coral.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                }
                results
                if let collection = model.matchingCollection {
                    Button("Open collection · \(collection)", systemImage: "folder") {
                        onOpen("collection:\(collection)")
                        model.reset()
                        withAnimation { expanded = false }
                    }.font(.caption).buttonStyle(.bordered)
                }
                Text("Say a shortcut name, then “enter”. “Scroll down” shows more. Or say “open dashboard”, “my shortcuts”, “collections” or “browser”.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Butter.coral.opacity(0.2)))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder private var results: some View {
        if !model.matches.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(model.matches.enumerated()), id: \.element.id) { index, clip in
                            Button { model.selected = index; model.open(clip) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: clip.files.isEmpty ? "text.alignleft" : "paperclip").foregroundStyle(Butter.coral).frame(width: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(clip.key.hasPrefix("/") ? "\\" + clip.key.dropFirst() : clip.key).font(.system(.caption, design: .monospaced).bold()).lineLimit(1)
                                        Text(clip.name + " · " + clip.allGroups.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    if index == model.selected { Text("enter").font(.system(size: 9, weight: .bold)).foregroundStyle(Butter.coral) }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(index == model.selected ? Butter.coral.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .id(clip.id)
                        }
                    }
                }
                .frame(maxHeight: 220)
                .onChange(of: model.selected) { index in
                    guard model.matches.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(model.matches[index].id, anchor: .center) }
                }
            }
            Text("\(model.matches.count) match\(model.matches.count == 1 ? "" : "es")")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
