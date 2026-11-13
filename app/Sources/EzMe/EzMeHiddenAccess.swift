// Showing hidden collections and shortcuts needs the same 6-digit passcode that protects deleting apps.
// The first time, KeyDo asks the person to choose one. After a correct entry the switches stay allowed for
// two minutes, so turning on several of them in a row does not ask again.
import SwiftUI
import AppKit

enum HiddenAccess {
    private static var lastUnlock = Date.distantPast
    private static let graceSeconds: TimeInterval = 120

    /// A switch that asks for the passcode before it turns on. Turning it off never asks.
    @MainActor static func gated(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { binding.wrappedValue },
            set: { wanted in
                if !wanted { binding.wrappedValue = false }
                else if unlock() { binding.wrappedValue = true }
            }
        )
    }

    /// True when the person may see hidden items now.
    @MainActor static func unlock() -> Bool {
        if Date().timeIntervalSince(lastUnlock) < graceSeconds { return true }
        NSApp.activate(ignoringOtherApps: true)
        return AppPasscode.isSet ? ask() : create()
    }

    @MainActor private static func ask() -> Bool {
        var message = "Hidden shortcuts are protected. Enter your 6-digit passcode to show them."
        while true {
            let alert = NSAlert()
            alert.messageText = "Show hidden shortcuts"
            alert.informativeText = message
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
            field.placeholderString = "6-digit passcode"
            alert.accessoryView = field
            alert.addButton(withTitle: "Show")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Forgot passcode…")
            alert.window.initialFirstResponder = field
            let result = alert.runModal()
            if result == .alertFirstButtonReturn {
                if AppPasscode.verify(field.stringValue) { lastUnlock = Date(); return true }
                message = "That passcode is not right. Try again."
                continue
            }
            if result == .alertThirdButtonReturn {
                AppPasscode.authenticateWithMac { ok in
                    guard ok else { return }
                    AppPasscode.clear()
                    let done = NSAlert()
                    done.messageText = "Passcode removed"
                    done.informativeText = "Turn on the hidden switch again to choose a new passcode."
                    done.runModal()
                }
            }
            return false
        }
    }

    @MainActor private static func create() -> Bool {
        var message = "Choose a 6-digit passcode. It also protects deleting apps."
        while true {
            let alert = NSAlert()
            alert.messageText = "Protect hidden shortcuts"
            alert.informativeText = message
            let first = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
            first.placeholderString = "New 6-digit passcode"
            let second = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
            second.placeholderString = "Repeat passcode"
            let stack = NSStackView(views: [first, second])
            stack.orientation = .vertical
            stack.spacing = 8
            stack.frame = NSRect(x: 0, y: 0, width: 220, height: 56)
            alert.accessoryView = stack
            alert.addButton(withTitle: "Set passcode and show")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = first
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            guard AppPasscode.isValid(first.stringValue) else { message = "Use exactly 6 digits, numbers only."; continue }
            guard first.stringValue == second.stringValue else { message = "The two passcodes do not match."; continue }
            AppPasscode.set(first.stringValue)
            lastUnlock = Date()
            return true
        }
    }
}
