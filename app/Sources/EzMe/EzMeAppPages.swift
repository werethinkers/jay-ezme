// Shared pieces so the AppBuilder and WishStudio home pages look and behave the same:
// covers that play video (10 seconds at most) and animate GIFs, with a chosen position and zoom.
import SwiftUI
import AppKit

enum EzCoverFraming {
    private static func key(_ app: String) -> String { "ezmeBuilderAppCoverFraming." + app }

    static func load(_ app: String) -> WishFraming {
        guard let text = UserDefaults.standard.string(forKey: key(app)),
              let value = try? JSONDecoder().decode(WishFraming.self, from: Data(text.utf8)) else { return WishFraming() }
        return value
    }

    static func save(_ framing: WishFraming, app: String) {
        if framing == WishFraming() {
            UserDefaults.standard.removeObject(forKey: key(app))
        } else if let data = try? JSONEncoder().encode(framing) {
            UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: key(app))
        }
    }
}

enum EzMediaKind {
    static let videoExtensions = ["mp4", "mov", "m4v", "avi", "webm"]
    static func isVideo(_ path: String) -> Bool {
        return videoExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }
}

/// A cover picture, GIF or video filling its box. Videos start at the top unless moved and play 10 seconds at most.
struct EzCoverMedia: View {
    let path: String
    var framing: WishFraming = WishFraming()

    var body: some View {
        WishCoverMedia(url: URL(fileURLWithPath: path), isVideo: EzMediaKind.isVideo(path), framing: framing)
    }
}

/// "Crop and position" for an AppBuilder cover. Changes apply at once and refresh both pages.
struct EzCoverFramingSheet: View {
    let app: String
    let path: String
    @Environment(\.dismiss) private var dismiss
    @State private var framing: WishFraming

    init(app: String, path: String) {
        self.app = app
        self.path = path
        _framing = State(initialValue: EzCoverFraming.load(app))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Crop and position").font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            EzCoverMedia(path: path, framing: framing)
                .frame(height: 164)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Butter.coral.opacity(0.3), lineWidth: 1))
            Text("This is the size of the card on the home page.").font(.caption).foregroundStyle(.secondary)
            WishFramingControls(framing: $framing, isVideo: EzMediaKind.isVideo(path), url: URL(fileURLWithPath: path), startsOpen: true)
        }
        .padding(20)
        .frame(width: 380)
        .onChange(of: framing) { _, value in
            EzCoverFraming.save(value, app: app)
            NotificationCenter.default.post(name: .ezmeBuilderIconChanged, object: nil)
        }
    }
}
