// Voice for Wish Studio, Fill by voice, the designers and the library: ONE microphone.
//
// There is a single recogniser in the app, the one behind the KeyDo voice bubble (KeyDoVoice). This class used to run a
// second recogniser of its own, and two of them listening at once fought over the microphone and heard each other's
// commands. Now it only asks the bubble to hand over finished sentences while a screen wants them; when that screen goes
// away, or another one starts, the sentences go back to the bubble's normal commands.
import Foundation
import Combine

extension Notification.Name {
    /// A dictation button is about to listen, or the bubble is: any other plain dictation stops.
    static let keydoDictationYield = Notification.Name("KeyDoDictationYield")
}

@MainActor
final class WishVoiceController: ObservableObject {
    @Published private(set) var isListening = false
    /// 0...1, how loud the mic is right now.
    @Published private(set) var level: Double = 0
    /// The sentence being heard, live.
    @Published private(set) var heard = ""
    @Published var errorMessage = "" {
        didSet { if errorMessage.isEmpty, !KeyDoVoice.shared.errorMessage.isEmpty { KeyDoVoice.shared.errorMessage = "" } }
    }

    /// Only one screen can have the sentences at a time; starting another gives way to it.
    private static weak var current: WishVoiceController?

    private var wanted = false
    private var ownsMic = false
    private var watching: AnyCancellable?

    func start(localeIdentifier: String, commitDelay: Double, onCommand: @escaping (String) -> Void) {
        guard !wanted else { return }
        if let other = Self.current, other !== self { other.stop() }
        Self.current = self
        wanted = true
        errorMessage = ""
        let voice = KeyDoVoice.shared
        voice.sentenceSink = { text in onCommand(text) }
        voice.sentencePause = max(0.3, commitDelay)
        ownsMic = voice.phase == .off
        watching = voice.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        voice.start(.app, yielding: false)
        refresh()
    }

    func stop() {
        guard wanted else { return }
        wanted = false
        watching = nil
        let voice = KeyDoVoice.shared
        voice.sentenceSink = nil
        if ownsMic { voice.stop(announce: false) }
        ownsMic = false
        if Self.current === self { Self.current = nil }
        if isListening { isListening = false }
        if level != 0 { level = 0 }
        if !heard.isEmpty { heard = "" }
    }

    /// The person said another language: the bubble listens in it too.
    func changeLanguage(_ identifier: String) {
        guard wanted, !identifier.isEmpty, UserDefaults.standard.string(forKey: VoiceKeys.locale) != identifier else { return }
        UserDefaults.standard.set(identifier, forKey: VoiceKeys.locale)
        UserDefaults.standard.set(identifier, forKey: "keydoVoiceLocale")
        KeyDoVoice.shared.languageChanged()
    }

    func updatePause(_ seconds: Double) {
        guard wanted else { return }
        KeyDoVoice.shared.sentencePause = max(0.3, seconds)
    }

    /// Mirrors the bubble, so every Wish screen shows the same mic.
    private func refresh() {
        guard wanted else { return }
        let voice = KeyDoVoice.shared
        if voice.phase == .off {
            // The bubble was stopped (stop listening, Stop button): this screen is no longer listening either.
            let message = voice.errorMessage
            stop()
            if !message.isEmpty { errorMessage = message }
            return
        }
        let listening = voice.phase == .listening
        if isListening != listening { isListening = listening }
        let newLevel = Double(voice.level)
        if abs(level - newLevel) > 0.02 { level = newLevel }
        if heard != voice.partial { heard = voice.partial }
        if errorMessage != voice.errorMessage, !voice.errorMessage.isEmpty { errorMessage = voice.errorMessage }
    }
}
