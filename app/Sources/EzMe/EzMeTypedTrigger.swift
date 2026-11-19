// Removes the backslash and command the person typed in the app they were using, once KeyDo has what it needs.
// Without this, a result that leaves by Share or by hand keeps the typed command in the text box.
import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor enum TypedTrigger {
    /// Deletes what was typed for this popup (the backslash and the command), once. Does nothing if nothing was typed,
    /// if it was already removed, or if Accessibility is not allowed.
    static func clear() {
        guard let delegate = MiniJAppDelegate.current, !delegate.typedCleared else { return }
        let count = delegate.triggerBuffer.utf16.count
        guard count > 0, AXIsProcessTrusted() else { return }
        delegate.typedCleared = true
        delegate.triggerTracking = false
        delegate.triggerBuffer = ""
        let target = delegate.lastExternalApp
        target?.activate(options: [])
        // Give the other app a moment to take focus, so the deletes land in its text box and not in KeyDo.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let source = CGEventSource(stateID: .hidSystemState)
            for _ in 0..<min(count, 80) {
                CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Delete), keyDown: true)?.post(tap: .cghidEventTap)
                CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Delete), keyDown: false)?.post(tap: .cghidEventTap)
            }
        }
    }
}
