// A spoken command for an app in AppBuilder, AppDesigner or WishStudio, with an optional recorded sample of it.
import SwiftUI
import AVFoundation

/// What kind of app a voice command belongs to.
enum AppVoiceKind: String { case builder, designer, wish }

enum AppVoiceStore {
    private static let key = "keydoAppVoiceJSON"
    struct Entry: Codable { var phrase: String = ""; var sample: String = "" }

    private static func load() -> [String: Entry] {
        guard let data = UserDefaults.standard.string(forKey: key)?.data(using: .utf8), let all = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return all
    }
    private static func save(_ all: [String: Entry]) {
        if let data = try? JSONEncoder().encode(all), let text = String(data: data, encoding: .utf8) { UserDefaults.standard.set(text, forKey: key) }
    }
    private static func id(_ kind: AppVoiceKind, _ name: String) -> String { kind.rawValue + "|" + name }

    static func entry(_ kind: AppVoiceKind, _ name: String) -> Entry { load()[id(kind, name)] ?? Entry() }
    static func update(_ kind: AppVoiceKind, _ name: String, _ change: (inout Entry) -> Void) {
        var all = load()
        var item = all[id(kind, name)] ?? Entry()
        change(&item)
        if item.phrase.isEmpty && item.sample.isEmpty { all[id(kind, name)] = nil } else { all[id(kind, name)] = item }
        save(all)
    }

    /// A voice command must not equal another app's command or a section name.
    static func taken(_ phrase: String, except: String) -> Bool {
        let wanted = VoiceRouter.squash(phrase)
        guard !wanted.isEmpty else { return false }
        if VoiceRouter.sections.contains(where: { $0.1.contains { VoiceRouter.squash($0) == wanted } }) { return true }
        return load().contains { $0.key != except && VoiceRouter.squash($0.value.phrase) == wanted }
    }

    /// Every saved command, for the voice router: what to say, and which app it opens.
    static func all() -> [(phrase: String, kind: AppVoiceKind, name: String)] {
        load().compactMap { pair in
            let parts = pair.key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let kind = AppVoiceKind(rawValue: parts[0]), !pair.value.phrase.isEmpty else { return nil }
            return (pair.value.phrase, kind, parts[1])
        }
    }

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("KeyDo/VoiceSamples", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

@MainActor final class AppVoiceRecorder: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var recording = false
    @Published var playing = false
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?

    func record(to url: URL, onDone: @escaping (Bool) -> Void) {
        let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1]
        do {
            let made = try AVAudioRecorder(url: url, settings: settings)
            guard made.record(forDuration: 8) else { onDone(false); return }
            recorder = made
            recording = true
            // Recording stops by itself after 8 seconds so it cannot be left on.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.2) { [weak self] in if self?.recording == true { self?.stop(onDone: onDone) } }
        } catch { onDone(false) }
    }
    func stop(onDone: ((Bool) -> Void)? = nil) {
        recorder?.stop(); recorder = nil
        if recording { recording = false; onDone?(true) }
    }
    func play(_ url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        playing = player?.play() ?? false
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in self.playing = false } }
}

/// The box shown in an app's settings: type what to say, or record yourself saying it.
struct AppVoiceCommandBox: View {
    let kind: AppVoiceKind
    let name: String
    @State private var phrase = ""
    @State private var sample = ""
    @State private var error = ""
    @StateObject private var recorder = AppVoiceRecorder()

    private var sampleURL: URL? { sample.isEmpty ? nil : AppVoiceStore.folder.appendingPathComponent(sample) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic").foregroundStyle(Butter.coral)
                Text("Voice command").font(.system(size: 12, weight: .bold)).foregroundStyle(Butter.cocoa)
                Text("Say it to open this app. Up to three words.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                TextField("For example: bill maker", text: $phrase).textFieldStyle(.roundedBorder).controlSize(.small).onSubmit { commit() }
                Button("Save") { commit() }.controlSize(.small).buttonStyle(.borderedProminent).tint(Butter.coral)
                Button { toggleRecord() } label: { Image(systemName: recorder.recording ? "stop.circle.fill" : "mic.circle.fill") }
                    .buttonStyle(.bordered).controlSize(.small).tint(recorder.recording ? .red : Butter.coral).help(recorder.recording ? "Stop recording" : "Record yourself saying it (up to 8 seconds)")
                if let url = sampleURL {
                    Button { recorder.play(url) } label: { Image(systemName: recorder.playing ? "speaker.wave.2.fill" : "play.circle") }.buttonStyle(.bordered).controlSize(.small).help("Play your recording")
                    Button { remove() } label: { Image(systemName: "trash") }.buttonStyle(.bordered).controlSize(.small).help("Delete the recording")
                }
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
            Text("The recording is kept on this Mac as a reminder of how you say it. KeyDo listens for the written command.").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10).background(Butter.cream, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { load() }
    }

    private func load() { let item = AppVoiceStore.entry(kind, name); phrase = item.phrase; sample = item.sample }

    private func commit() {
        let clean = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.split(separator: " ").count > 3 { error = "Use up to three words."; return }
        if !clean.isEmpty, AppVoiceStore.taken(clean, except: kind.rawValue + "|" + name) { error = "“\(clean)” is already used by another app or a KeyDo section. Choose another."; return }
        error = ""
        AppVoiceStore.update(kind, name) { $0.phrase = clean }
    }

    private func toggleRecord() {
        if recorder.recording { recorder.stop { _ in finishRecording() }; return }
        let file = sampleFile
        let url = AppVoiceStore.folder.appendingPathComponent(file)
        try? FileManager.default.removeItem(at: url)
        recorder.record(to: url) { ok in
            if ok { sample = file; AppVoiceStore.update(kind, name) { $0.sample = file } } else { error = "Recording did not start. Allow the microphone for KeyDo in System Settings." }
        }
    }
    private var sampleFile: String { "\(kind.rawValue)-\(VoiceRouter.squash(name)).m4a" }
    private func finishRecording() { sample = sampleFile; AppVoiceStore.update(kind, name) { $0.sample = sampleFile } }
    private func remove() {
        if let url = sampleURL { try? FileManager.default.removeItem(at: url) }
        sample = ""
        AppVoiceStore.update(kind, name) { $0.sample = "" }
    }
}
