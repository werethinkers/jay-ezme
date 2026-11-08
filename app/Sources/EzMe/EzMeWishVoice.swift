// WishStudio voice control: ONE microphone, ONE command per sentence.
//
// Turn the mic on once and keep talking. Each sentence is applied a single time: either when the speech
// recogniser finishes it, or when you pause for a moment (the pause is adjustable in WishBuilder). The
// recogniser is then restarted so the same words can never be applied twice. A level meter makes the
// mic feel alive.
import Foundation
import Speech
import AVFoundation

private func wishRMS(_ buffer: AVAudioPCMBuffer) -> Double {
    guard let channel = buffer.floatChannelData?[0] else { return 0 }
    let count = Int(buffer.frameLength)
    if count == 0 { return 0 }
    var sum: Float = 0
    for index in 0..<count {
        let sample = channel[index]
        sum += sample * sample
    }
    let rms = (sum / Float(count)).squareRoot()
    return Double(min(1, rms * 9))
}

@MainActor
final class WishVoiceController: ObservableObject {
    @Published private(set) var isListening = false
    /// 0...1, how loud the mic is right now.
    @Published private(set) var level: Double = 0
    /// The sentence being heard, live.
    @Published private(set) var heard = ""
    @Published var errorMessage = ""

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var commitTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var onCommand: ((String) -> Void)?
    private var localeIdentifier = "en-IN"
    private var commitDelay = 0.9
    private var wanted = false
    private var generation = 0
    private var silentRestarts = 0
    private var lastCommit = ""
    private var lastCommitTime = Date.distantPast

    // MARK: Start and stop

    func start(localeIdentifier: String, commitDelay: Double, onCommand: @escaping (String) -> Void) {
        guard !wanted else { return }
        errorMessage = ""
        self.onCommand = onCommand
        self.localeIdentifier = localeIdentifier
        self.commitDelay = commitDelay
        wanted = true
        silentRestarts = 0
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self = self, self.wanted else { return }
                guard status == .authorized else {
                    self.fail("Enable Speech Recognition for EzMe in System Settings \u{2192} Privacy & Security.")
                    return
                }
                let audio = AVCaptureDevice.authorizationStatus(for: .audio)
                if audio == .denied || audio == .restricted {
                    self.fail("Enable Microphone access for EzMe in System Settings \u{2192} Privacy & Security.")
                    return
                }
                if audio == .authorized {
                    self.begin()
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in
                        guard self.wanted else { return }
                        if granted {
                            self.begin()
                        } else {
                            self.fail("Microphone access is needed for voice commands.")
                        }
                    }
                }
            }
        }
    }

    func stop() {
        wanted = false
        generation += 1
        restartTask?.cancel()
        teardown()
        isListening = false
        heard = ""
        level = 0
    }

    /// Switches the language being understood without turning the mic off.
    func changeLanguage(_ identifier: String) {
        guard identifier != localeIdentifier else { return }
        localeIdentifier = identifier
        if wanted { restartSoon(delay: 0.05) }
    }

    func updatePause(_ seconds: Double) {
        commitDelay = seconds
    }

    private func fail(_ message: String) {
        wanted = false
        generation += 1
        teardown()
        isListening = false
        heard = ""
        level = 0
        errorMessage = message
    }

    // MARK: Recognition

    private func begin() {
        guard wanted else { return }
        teardown()
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) ?? SFSpeechRecognizer()
        guard let recognizer = recognizer, recognizer.isAvailable else {
            fail("Speech recognition is not available right now.")
            return
        }
        generation += 1
        let current = generation
        let audioRequest = SFSpeechAudioBufferRecognitionRequest()
        audioRequest.shouldReportPartialResults = true
        audioRequest.taskHint = .dictation
        request = audioRequest

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            audioRequest.append(buffer)
            let value = wishRMS(buffer)
            Task { @MainActor in
                self?.level = value
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            fail("Could not start the microphone: \(error.localizedDescription)")
            return
        }
        isListening = true
        task = recognizer.recognitionTask(with: audioRequest) { [weak self] result, error in
            Task { @MainActor in
                self?.handle(result: result, error: error, generation: current)
            }
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, generation current: Int) {
        guard current == generation, wanted else { return }
        if let result = result {
            let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.isFinal {
                commit(text)
                return
            }
            guard !text.isEmpty else { return }
            silentRestarts = 0
            heard = text
            scheduleCommit(text, generation: current)
            return
        }
        if error != nil {
            let pending = heard
            if pending.isEmpty {
                silentRestarts += 1
                if silentRestarts > 12 {
                    fail("Voice stopped because nothing was heard. Tap the mic to start again.")
                    return
                }
                restartSoon(delay: 0.4)
            } else {
                commit(pending)
            }
        }
    }

    /// Applies the sentence once the speaker pauses.
    private func scheduleCommit(_ text: String, generation current: Int) {
        commitTask?.cancel()
        let delay = commitDelay
        commitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self = self else { return }
            guard current == self.generation, self.heard == text else { return }
            self.commit(text)
        }
    }

    /// The single place where a sentence leaves the recogniser. Afterwards the recogniser is replaced, so the
    /// same words cannot arrive a second time.
    private func commit(_ raw: String) {
        commitTask?.cancel()
        commitTask = nil
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        heard = ""
        generation += 1
        if !text.isEmpty {
            let now = Date()
            let repeated = text.caseInsensitiveCompare(lastCommit) == .orderedSame && now.timeIntervalSince(lastCommitTime) < 2.0
            if !repeated {
                lastCommit = text
                lastCommitTime = now
                onCommand?(text)
            }
        }
        restartSoon(delay: 0.1)
    }

    private func restartSoon(delay: Double) {
        generation += 1
        teardown()
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self = self, self.wanted else { return }
            self.begin()
        }
    }

    private func teardown() {
        commitTask?.cancel()
        commitTask = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        level = 0
    }
}
