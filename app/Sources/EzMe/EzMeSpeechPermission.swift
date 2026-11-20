// The one place that asks macOS for speech and microphone access.
// macOS answers on a background queue, so this is deliberately not tied to the main actor: the answer is handed
// back on the main queue and nothing here touches the interface.
import Foundation
import AVFoundation
import Speech

enum SpeechPermission {
    enum Answer { case ready, speechDenied, micDenied }

    static func request(_ done: @escaping @Sendable (Answer) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async { done(.speechDenied) }
                return
            }
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                DispatchQueue.main.async { done(.ready) }
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async { done(granted ? .ready : .micDenied) }
                }
            default:
                DispatchQueue.main.async { done(.micDenied) }
            }
        }
    }
}
