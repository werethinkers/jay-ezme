// One microphone, one voice at a time. Every dictation button (Prompt Builder, forms, designers) and the KeyDo voice
// bubble go through here: when one starts, the others stop, and the "Hey KeyDo" listener waits until the mic is free.
import Foundation

extension EzMeSpeechDictation {
    private static let live = NSHashTable<EzMeSpeechDictation>.weakObjects()

    /// Called when a dictation button starts: stops every other dictation, the voice bubble and the form filler.
    static func takeMic(for me: EzMeSpeechDictation) {
        live.add(me)
        for other in live.allObjects where other !== me { other.stop() }
        KeyDoVoice.shared.suspended = true
        if KeyDoVoice.shared.phase != .off { KeyDoVoice.shared.stop(announce: false) }
        NotificationCenter.default.post(name: .keydoVoiceTakeover, object: me)
    }

    /// Called when a dictation ends. The wake listener comes back only if no dictation is listening.
    static func releaseMic() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !live.allObjects.contains(where: { $0.isListening }) else { return }
            KeyDoVoice.shared.suspended = false
            KeyDoVoice.shared.startWakeIfNeeded()
        }
    }
}
