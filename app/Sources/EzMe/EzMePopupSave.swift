// "Save…" for a card made from the popup: choose where the picture, PDF or text goes.
import AppKit

enum PopupSave {
    @MainActor static func save(_ clip: Clip) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if let path = clip.files.first, FileManager.default.fileExists(atPath: path) {
            let source = URL(fileURLWithPath: path)
            panel.nameFieldStringValue = source.lastPathComponent
            NSApp.activate(ignoringOtherApps: true)
            panel.begin { response in
                guard response == .OK, let target = panel.url else { return }
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.copyItem(at: source, to: target)
            }
        } else if !clip.text.isEmpty {
            let base = clip.name.isEmpty ? "KeyDo" : clip.name
            panel.nameFieldStringValue = base + ".txt"
            NSApp.activate(ignoringOtherApps: true)
            panel.begin { response in
                guard response == .OK, let target = panel.url else { return }
                try? clip.text.write(to: target, atomically: true, encoding: .utf8)
            }
        }
    }
}
