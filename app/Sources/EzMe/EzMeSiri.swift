// Siri and the Shortcuts app can drive KeyDo through keydo:// links, from any app, when this is switched on in Settings.
import SwiftUI
import AppKit

extension Notification.Name {
    static let keydoSiriSend = Notification.Name("KeyDoSiriSend")
}

enum SiriCommands {
    static let enabledKey = "ezmeSiriEnabled"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// keydo://voice?text=open prompt builder   or   keydo://open/prompt-builder   gives the words to run. Nil when Siri control is off.
    static func text(from url: URL) -> String? {
        guard enabled, url.scheme?.lowercased() == "keydo" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let spoken = items.first(where: { $0.name == "text" || $0.name == "say" })?.value, !spoken.trimmingCharacters(in: .whitespaces).isEmpty {
            return spoken
        }
        let path = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).filter { !$0.isEmpty }
        let words = path.dropFirst(path.first?.lowercased() == "open" || path.first?.lowercased() == "voice" ? 1 : 0).joined(separator: " ").replacingOccurrences(of: "-", with: " ")
        return words.isEmpty ? nil : "open " + words
    }

    /// "send to chatgpt" and its variants: the site name, when the words are a send command.
    static func sendTarget(in normalized: String) -> String? {
        for lead in ["send this to ", "send it to ", "send prompt to ", "send to ", "share with ", "share to ", "paste in ", "paste into ", "post to ", "submit to "] {
            if normalized.hasPrefix(lead) { return String(normalized.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }
}

struct SiriSettings: View {
    @AppStorage(SiriCommands.enabledKey) private var on = false

    private let examples: [(String, String)] = [
        ("Say anything to KeyDo", "keydo://voice?text=Dictated Text"),
        ("Open Prompt Builder", "keydo://open/prompt-builder"),
        ("Open Collection Builder", "keydo://open/collection-builder"),
        ("Open MyDatabase", "keydo://open/mydatabase"),
        ("Send the prompt to ChatGPT", "keydo://voice?text=send to chatgpt")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Use Siri as a voice command across all apps", isOn: $on).toggleStyle(.switch).tint(Butter.coral)
            Text("When this is on, KeyDo accepts keydo:// links from Siri and the Shortcuts app, so you can run any KeyDo voice command while you are in any other app. Siri hears you, Shortcuts passes the words to KeyDo, and KeyDo runs them the same way as its own voice commands, for example “open prompt builder” or “send to chatgpt”.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text("Set it up once").font(.system(size: 13, weight: .bold, design: .rounded))
                Text("1. Open Shortcuts and make a new shortcut named “KeyDo”.\n2. Add the action Dictate Text, then the action Open URLs with  keydo://voice?text=  followed by the Dictated Text.\n3. Say “Hey Siri, KeyDo”, then your command. For a fixed command, make one shortcut per link below (for example “Prompt Builder”).")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(examples, id: \.1) { example in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(example.0).font(.caption.weight(.semibold))
                        Text(example.1).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Copy link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(example.1, forType: .string) }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            HStack {
                Button("Open the Shortcuts app") { if let url = URL(string: "shortcuts://") { NSWorkspace.shared.open(url) } }.buttonStyle(.borderedProminent).tint(Butter.coral)
                if !on { Text("Switch the setting on first, or KeyDo ignores these links.").font(.caption).foregroundStyle(.orange) }
            }
        }
        .padding(8)
    }
}
