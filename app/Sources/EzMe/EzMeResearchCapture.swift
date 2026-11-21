// Research capture: a button in the browser that, for 10 minutes, saves every picture you copy in the browser
// (right click, Copy Image) into the Database Organizer, in a collection called Research. Pictures only, never videos.
// It turns itself off after 10 minutes and shows the time left.
import SwiftUI
import AppKit
import WebKit
import CryptoKit

@MainActor final class ResearchCapture: ObservableObject {
    static let shared = ResearchCapture()
    static let collection = "Research"
    static let length: TimeInterval = 600

    @Published private(set) var active = false
    @Published private(set) var secondsLeft = 0
    @Published private(set) var saved = 0
    @Published private(set) var message = ""

    private var timer: Timer?
    private var endsAt = Date()
    private var lastChange = NSPasteboard.general.changeCount
    private var seen = Set<String>()
    private var page: () -> String = { "" }
    private static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "bmp"]
    private static let videoTypes: Set<String> = ["mp4", "mov", "m4v", "avi", "webm", "mpeg", "mpg", "mkv"]

    func toggle(page: @escaping () -> String) {
        if active { stop("Research capture is off.") } else { start(page: page) }
    }

    func start(page: @escaping () -> String) {
        self.page = page
        endsAt = Date().addingTimeInterval(Self.length)
        secondsLeft = Int(Self.length)
        saved = 0
        seen = []
        lastChange = NSPasteboard.general.changeCount
        active = true
        message = "On for 10 minutes. Right click a picture and choose Copy Image."
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop(_ text: String) {
        timer?.invalidate()
        timer = nil
        active = false
        secondsLeft = 0
        message = text
    }

    private func tick() {
        let left = Int(ceil(endsAt.timeIntervalSinceNow))
        if left <= 0 { stop("Research capture turned off after 10 minutes. \(saved) picture\(saved == 1 ? "" : "s") saved to Research."); return }
        if left != secondsLeft { secondsLeft = left }
        let board = NSPasteboard.general
        guard board.changeCount != lastChange else { return }
        lastChange = board.changeCount
        // Only a copy made inside the browser counts, never one made somewhere else in KeyDo or in another app.
        guard NSApp.isActive, Self.browserHasFocus() else { return }
        if let png = Self.imageData(from: board) { save(png, ext: "png") }
    }

    private static func browserHasFocus() -> Bool {
        var view = NSApp.keyWindow?.firstResponder as? NSView
        while let current = view {
            if current is WKWebView { return true }
            view = current.superview
        }
        return false
    }

    /// The picture on the clipboard as PNG, or nil: files that are videos, and anything that is not a picture, are ignored.
    private static func imageData(from board: NSPasteboard) -> Data? {
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            for url in urls {
                let ext = url.pathExtension.lowercased()
                if videoTypes.contains(ext) { return nil }
                if imageTypes.contains(ext), let image = NSImage(contentsOf: url) { return PhotoCanvas.png(image) }
            }
            return nil
        }
        if let png = board.data(forType: .png) { return png }
        if let tiff = board.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) { return rep.representation(using: .png, properties: [:]) }
        return nil
    }

    private func save(_ png: Data, ext: String) {
        let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        guard !seen.contains(digest) else { message = "That picture is already in Research."; return }
        seen.insert(digest)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiniJ", isDirectory: true).appendingPathComponent("MyDatabase", isDirectory: true)
            .appendingPathComponent(Self.collection, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let name = "research-\(stamp.string(from: Date()))-\(digest.prefix(6)).\(ext)"
        let url = base.appendingPathComponent(name)
        guard (try? png.write(to: url, options: .atomic)) != nil else { message = "Could not save the picture."; return }
        var record = DBRecord(kind: "media", title: name, value: url.standardizedFileURL.path, collection: Self.collection)
        let source = page().trimmingCharacters(in: .whitespacesAndNewlines)
        record.notes = source.isEmpty ? "Copied from the browser" : "Copied from " + source
        record.tags = "research"
        MyDatabaseStore.shared.upsert(record)
        saved += 1
        message = "Saved to Research (\(saved))."
    }
}

struct ResearchCaptureButton: View {
    var page: () -> String
    @ObservedObject private var capture = ResearchCapture.shared

    private var clock: String { String(format: "%ld:%02ld", capture.secondsLeft / 60, capture.secondsLeft % 60) }

    var body: some View {
        HStack(spacing: 6) {
            Button { capture.toggle(page: page) } label: {
                HStack(spacing: 5) {
                    Image(systemName: capture.active ? "record.circle.fill" : "photo.badge.arrow.down")
                        .foregroundStyle(capture.active ? Color.red : Color.secondary)
                    Text(capture.active ? "Research \(clock)" : "Research capture").font(.system(size: 11, weight: .semibold))
                    if capture.active { Text("\(capture.saved) saved").font(.system(size: 10)).foregroundStyle(.secondary) }
                }
            }
            .buttonStyle(.borderless)
            .help(capture.active ? "Saving pictures you copy in the browser to the Research collection. Click to stop." : "Turn on for 10 minutes: pictures you copy in the browser are saved to the Research collection in Database Organizer. Videos are never saved.")
            if !capture.message.isEmpty {
                Text(capture.message).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .fixedSize()
    }
}
