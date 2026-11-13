// Deleting apps (AppBuilder and WishStudio) with one optional 6-digit passcode.
//
// The three built-in AppBuilder apps (Collection Builder, MyDatabase, Prompt Builder) can never be deleted.
// The passcode is one code for the whole app. It stops accidental or casual deletes; it is stored as a salted
// hash, never as the digits. If it is forgotten, the Mac login (password or Touch ID) can reset it.
import SwiftUI
import CryptoKit
import LocalAuthentication

enum AppPasscode {
    static let hashKey = "ezmeAppDeletePasscodeHash"
    private static let saltKey = "ezmeAppDeletePasscodeSalt"

    static var isSet: Bool { !(UserDefaults.standard.string(forKey: hashKey) ?? "").isEmpty }

    static func isValid(_ code: String) -> Bool {
        code.count == 6 && code.allSatisfy { "0123456789".contains($0) }
    }

    private static func digest(_ code: String, salt: String) -> String {
        SHA256.hash(data: Data((salt + code).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func set(_ code: String) {
        guard isValid(code) else { return }
        let salt = UUID().uuidString
        UserDefaults.standard.set(salt, forKey: saltKey)
        UserDefaults.standard.set(digest(code, salt: salt), forKey: hashKey)
    }

    /// True when no passcode is set, or when the code matches.
    static func verify(_ code: String) -> Bool {
        guard let hash = UserDefaults.standard.string(forKey: hashKey), !hash.isEmpty else { return true }
        let salt = UserDefaults.standard.string(forKey: saltKey) ?? ""
        return digest(code, salt: salt) == hash
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: hashKey)
        UserDefaults.standard.removeObject(forKey: saltKey)
    }

    /// Asks for the Mac password or Touch ID, then calls back on the main thread.
    static func authenticateWithMac(_ done: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { done(false); return }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Reset the KeyDo delete passcode") { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }
}

enum AppDeletion {
    static let protectedNames: Set<String> = ["collection builder", "mydatabase", "prompt builder"]
    private static let deletedKey = "ezmeDeletedBuilderApps"

    static func canDelete(_ name: String) -> Bool {
        !protectedNames.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func isDeleted(_ name: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: deletedKey) ?? []).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Lets an app come back (for example when the person adds the same preset or creates the same name again).
    static func restore(_ name: String) {
        let kept = (UserDefaults.standard.stringArray(forKey: deletedKey) ?? []).filter { $0.caseInsensitiveCompare(name) != .orderedSame }
        UserDefaults.standard.set(kept, forKey: deletedKey)
    }

    /// Removes an AppBuilder app and all of its settings. Remembered, so the launch-time preset installer does not bring it back.
    static func deleteBuilderApp(_ name: String) {
        guard canDelete(name) else { return }
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: "ezmeCustomBuilderAppsJSON") ?? "[]"
        let apps = ((try? JSONDecoder().decode([String].self, from: Data(stored.utf8))) ?? []).filter { $0.caseInsensitiveCompare(name) != .orderedSame }
        defaults.set(String(decoding: (try? JSONEncoder().encode(apps)) ?? Data("[]".utf8), as: UTF8.self), forKey: "ezmeCustomBuilderAppsJSON")
        let created = (defaults.stringArray(forKey: "ezmeUserCreatedBuilderApps") ?? []).filter { $0.caseInsensitiveCompare(name) != .orderedSame }
        defaults.set(created, forKey: "ezmeUserCreatedBuilderApps")
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("ezmeBuilder") {
            guard let dot = key.firstIndex(of: ".") else { continue }
            if String(key[key.index(after: dot)...]) == name { defaults.removeObject(forKey: key) }
        }
        if defaults.string(forKey: "ezmeAIBuilderApp") == name { defaults.removeObject(forKey: "ezmeAIBuilderApp") }
        var deleted = defaults.stringArray(forKey: deletedKey) ?? []
        if !deleted.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { deleted.append(name) }
        defaults.set(deleted, forKey: deletedKey)
    }
}

/// Confirmation for deleting an app. Asks for the passcode when one is set, and lets the person set, change or remove it.
struct DeleteAppSheet: View {
    let appName: String
    let onDelete: () -> Void
    let onCancel: () -> Void

    @AppStorage(AppPasscode.hashKey) private var storedHash = ""
    @State private var code = ""
    @State private var error = ""
    @State private var showPasscodeSettings = false
    @State private var newCode = ""
    @State private var repeatCode = ""
    @State private var currentCode = ""
    @State private var settingsMessage = ""

    private var hasPasscode: Bool { !storedHash.isEmpty }

    private func digitsOnly(_ text: String) -> String { String(text.filter { "0123456789".contains($0) }.prefix(6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "trash.circle.fill").font(.system(size: 30)).foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete \u{201C}\(appName)\u{201D}?").font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Its settings are removed. Shortcuts it already made are kept.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if hasPasscode {
                VStack(alignment: .leading, spacing: 4) {
                    SecureField("6-digit passcode", text: $code)
                        .textFieldStyle(.roundedBorder).frame(width: 190)
                        .onChange(of: code) { _ in code = digitsOnly(code); error = "" }
                        .onSubmit { attemptDelete() }
                    if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }.keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive) { attemptDelete() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(hasPasscode && code.count != 6)
            }
            Divider()
            DisclosureGroup(hasPasscode ? "Delete passcode is on" : "Add a 6-digit passcode for deleting apps", isExpanded: $showPasscodeSettings) {
                passcodeSettings.padding(.top, 6)
            }.font(.system(size: 12, weight: .semibold))
        }
        .padding(20)
        .frame(width: 400)
    }

    private func attemptDelete() {
        if hasPasscode && !AppPasscode.verify(code) { error = "That passcode is not right."; code = ""; return }
        onDelete()
    }

    @ViewBuilder private var passcodeSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasPasscode {
                SecureField("Current passcode", text: $currentCode).textFieldStyle(.roundedBorder).frame(width: 190)
                    .onChange(of: currentCode) { _ in currentCode = digitsOnly(currentCode) }
            }
            SecureField(hasPasscode ? "New passcode (6 digits)" : "New passcode (6 digits)", text: $newCode).textFieldStyle(.roundedBorder).frame(width: 190)
                .onChange(of: newCode) { _ in newCode = digitsOnly(newCode) }
            SecureField("Repeat passcode", text: $repeatCode).textFieldStyle(.roundedBorder).frame(width: 190)
                .onChange(of: repeatCode) { _ in repeatCode = digitsOnly(repeatCode) }
            HStack(spacing: 8) {
                Button(hasPasscode ? "Change passcode" : "Set passcode") { saveNewCode() }
                    .disabled(newCode.count != 6 || repeatCode.count != 6)
                if hasPasscode {
                    Button("Remove passcode") { removeCode() }.disabled(currentCode.count != 6)
                    Button("Forgot? Use Mac login") {
                        AppPasscode.authenticateWithMac { ok in
                            if ok { AppPasscode.clear(); settingsMessage = "Passcode removed."; currentCode = "" }
                            else { settingsMessage = "Mac login was not confirmed." }
                        }
                    }.buttonStyle(.link)
                }
            }
            if !settingsMessage.isEmpty { Text(settingsMessage).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func saveNewCode() {
        if hasPasscode && !AppPasscode.verify(currentCode) { settingsMessage = "Enter the current passcode first."; return }
        guard newCode == repeatCode else { settingsMessage = "The two passcodes do not match."; return }
        AppPasscode.set(newCode)
        settingsMessage = "Passcode saved."
        newCode = ""; repeatCode = ""; currentCode = ""
    }

    private func removeCode() {
        guard AppPasscode.verify(currentCode) else { settingsMessage = "That passcode is not right."; return }
        AppPasscode.clear()
        settingsMessage = "Passcode removed."
        currentCode = ""
    }
}
