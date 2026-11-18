// Pictures and voice in the backslash popup form of an AppDesigner app.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension DesignCommands {
    /// The boxes a popup command asks for, with their kinds, in the same order as the command's slots.
    @MainActor static func popupFields(app: String) -> [DesignField] {
        guard let id = designID(forApp: app), let design = AppDesignStore.shared.design(id: id) else { return [] }
        return slots(for: design)
    }

    @MainActor static func field(app: String, label: String) -> DesignField? {
        popupFields(app: app).first { $0.label.caseInsensitiveCompare(label) == .orderedSame }
    }
}

@MainActor enum PopupMedia {
    /// What the picture box should hold for words that were typed or said: a shortcut key, or a file that exists.
    static func resolve(_ said: String, collection: String?) -> String? {
        let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if FileManager.default.fileExists(atPath: text) { return text }
        let clips = AppDesignContext.shared.clips
        if celebrationMedia(text, clips: clips) != nil { return text }
        if let clip = MediaFinder.best(text, in: collection) ?? (collection == nil ? nil : MediaFinder.best(text)) { return clip.key }
        return nil
    }

    /// Lets the person choose a picture from the Mac. Returns its path.
    static func choose() -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Add an image"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// Puts what was said into the boxes it names. A picture that cannot be found is reported, never guessed.
    static func apply(_ sentence: String, app: String, slotNames: [String], set: (Int, String) -> Void) -> String {
        let fields = DesignCommands.popupFields(app: app)
        var parsed = DesignVoiceFill.parse(sentence, fields: fields)
        if parsed.isEmpty, let first = DesignVoiceFill.firstEmpty(fields, values: [:]) {
            let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { parsed[first.key] = text }
        }
        var missing: [String] = []
        for (key, value) in parsed {
            guard let field = fields.first(where: { $0.key == key }),
                  let index = slotNames.firstIndex(where: { $0.caseInsensitiveCompare(field.label) == .orderedSame }) else { continue }
            if field.kind == .image {
                if let found = resolve(value, collection: field.collection) { set(index, found) } else { missing.append(value) }
            } else {
                set(index, value)
            }
        }
        if let first = missing.first { return "No media called \u{201C}\(first)\u{201D} yet. Tap Add image to pick one." }
        return parsed.isEmpty ? "Nothing heard. Say a box name and its value, like \u{201C}name Rahul\u{201D}." : ""
    }
}

/// A picture box of the popup: type or say a shortcut name, tap a match, or add an image from the Mac.
struct PopupImageField: View {
    var collection: String?
    @Binding var text: String

    var body: some View {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = PopupMedia.resolve(typed, collection: collection) != nil
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("Media shortcut name (optional)", text: $text).textFieldStyle(.roundedBorder)
                Button { if let path = PopupMedia.choose() { text = path } } label: { Label("Add image", systemImage: "photo.badge.plus") }
                    .controlSize(.small)
                if !typed.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            if typed.isEmpty {
                Text("Optional. Type or say a media shortcut, or add an image. Left empty, the app uses the last picture or the template's own.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else if found {
                Text("Using this picture.").font(.system(size: 10)).foregroundStyle(.green)
            } else {
                Text("No media called \u{201C}\(typed)\u{201D} yet. Pick a match below or tap Add image.").font(.system(size: 10)).foregroundStyle(.orange)
            }
            MediaSuggestions(query: text, collection: collection) { clip in text = clip.key }
        }
    }
}
