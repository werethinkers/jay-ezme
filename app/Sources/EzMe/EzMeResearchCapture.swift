// Research capture: a button in the browser that, for 10 minutes, saves every picture you copy in the browser
// (right click, Copy Image) into a real file in Pictures > KeyDo Research, listed in My Files in a collection called Research. Pictures only, never videos.
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
        if let png = Self.imageData(from: board) { save(png, ext: "png"); return }
        // Many sites copy only the picture's web address. Download the real file from it, never keep just a link.
        if let address = Self.imageAddress(from: board) { download(address) }
    }

    /// The web address of a picture on the clipboard (copied address, link, or the picture inside copied page HTML).
    private static func imageAddress(from board: NSPasteboard) -> URL? {
        var candidates: [String] = []
        if let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            candidates.append(contentsOf: urls.filter { !$0.isFileURL }.map { $0.absoluteString })
        }
        if let text = board.string(forType: .URL) { candidates.append(text) }
        if let text = board.string(forType: .string) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.contains(" "), !t.contains("\n") { candidates.append(t) }
        }
        if let html = board.string(forType: .html), let range = html.range(of: #"<img[^>]+src=["']([^"']+)["']"#, options: .regularExpression) {
            let tag = String(html[range])
            if let src = tag.range(of: #"src=["']([^"']+)["']"#, options: .regularExpression) {
                let value = tag[src].dropFirst(5).dropLast()
                candidates.append(String(value))
            }
        }
        for text in candidates {
            if let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                if videoTypes.contains(url.pathExtension.lowercased()) { return nil }
                return url
            }
        }
        return nil
    }

    private func download(_ address: URL) {
        guard !seen.contains(address.absoluteString) else { message = "That picture is already in Research."; return }
        seen.insert(address.absoluteString)
        message = "Downloading the picture…"
        let referer = page().trimmingCharacters(in: .whitespacesAndNewlines)
        Task { [weak self] in
            var request = URLRequest(url: address, timeoutInterval: 30)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            if !referer.isEmpty { request.setValue(referer, forHTTPHeaderField: "Referer") }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let mime = (response.mimeType ?? "").lowercased()
                guard data.count > 0, data.count < 40_000_000, mime.hasPrefix("image/"), NSImage(data: data) != nil else {
                    // Not a picture (a page link, a video, a file): nothing is saved, and the address can be tried again.
                    await MainActor.run { self?.seen.remove(address.absoluteString); self?.message = "That was not a picture, so nothing was saved." }
                    return
                }
                let ext = ResearchCapture.fileExtension(mime: mime, address: address)
                await MainActor.run { self?.save(data, ext: ext, address: address) }
            } catch {
                await MainActor.run { self?.seen.remove(address.absoluteString); self?.message = "Could not download that picture." }
            }
        }
    }

    private static func fileExtension(mime: String, address: URL) -> String {
        switch mime {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        case "image/tiff": return "tiff"
        case "image/bmp": return "bmp"
        default:
            let ext = address.pathExtension.lowercased()
            return imageTypes.contains(ext) ? ext : "png"
        }
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

    private func save(_ png: Data, ext: String, address: URL? = nil) {
        let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        guard !seen.contains(digest) else { message = "That picture is already in Research."; return }
        seen.insert(digest)
        // A real file in Pictures > KeyDo Research, so it can be seen and used like any downloaded picture (also in My Files > Finder).
        let fm = FileManager.default
        var base = fm.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("KeyDo Research", isDirectory: true)
        if (try? fm.createDirectory(at: base, withIntermediateDirectories: true)) == nil {
            base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MiniJ", isDirectory: true).appendingPathComponent("MyDatabase", isDirectory: true)
                .appendingPathComponent(Self.collection, isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let name = "research-\(stamp.string(from: Date()))-\(digest.prefix(6)).\(ext)"
        let url = base.appendingPathComponent(name)
        guard (try? png.write(to: url, options: .atomic)) != nil else { message = "Could not save the picture."; return }
        var record = DBRecord(kind: "media", title: name, value: url.standardizedFileURL.path, collection: Self.collection)
        let source = page().trimmingCharacters(in: .whitespacesAndNewlines)
        record.notes = source.isEmpty ? "Copied from the browser" : "Copied from " + source
        if let address { record.notes += "\nPicture address: " + address.absoluteString }
        record.tags = "research"
        MyDatabaseStore.shared.upsert(record)
        saved += 1
        message = "Downloaded to Pictures > KeyDo Research (\(saved))."
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
