// Video Cutter: open a video from a link.
//
// A direct link to a video file (.mp4, .mov, .m4v, .webm) is downloaded as it is. A page link (YouTube, Vimeo,
// Instagram and most other video sites) is fetched with the free helper yt-dlp when it is installed on the Mac
// (brew install yt-dlp). The video is saved next to the other Ez Studio media, then opens in the cutter.
import AppKit
import SwiftUI

enum VideoLinkError: LocalizedError {
    case invalid
    case toolMissing
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalid:
            return "That does not look like a web link. Paste the full address of the video."
        case .toolMissing:
            return "Page links (YouTube, Vimeo, Instagram…) need the free helper yt-dlp. Install it once in Terminal with “brew install yt-dlp”, then try again. Direct .mp4 or .mov links work without it."
        case .failed(let message):
            return message
        }
    }
}

enum VideoLinkFetcher {
    private static let directTypes: Set<String> = ["mp4", "mov", "m4v", "webm"]

    static func fetch(_ text: String, into directory: URL) async throws -> URL {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.lowercased().hasPrefix("http") { raw = "https://" + raw }
        guard let url = URL(string: raw), let host = url.host, host.contains(".") else { throw VideoLinkError.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if directTypes.contains(url.pathExtension.lowercased()) {
            return try await download(url, into: directory)
        }
        return try await viaHelper(url, into: directory)
    }

    private static func download(_ url: URL, into directory: URL) async throws -> URL {
        let (temp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw VideoLinkError.failed("The server answered with code \(http.statusCode), so the video could not be downloaded.")
        }
        let destination = directory.appendingPathComponent("link-\(UUID().uuidString).\(url.pathExtension.lowercased())")
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }

    private static func helperPath() -> String? {
        let candidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", NSHomeDirectory() + "/.local/bin/yt-dlp", "/usr/bin/yt-dlp"]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private static func viaHelper(_ url: URL, into directory: URL) async throws -> URL {
        guard let tool = helperPath() else { throw VideoLinkError.toolMissing }
        let name = "link-\(UUID().uuidString)"
        let template = directory.appendingPathComponent(name + ".%(ext)s").path
        return try await Task.detached(priority: .userInitiated) { () throws -> URL in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = ["--quiet", "--no-warnings", "--no-playlist", "-f", "best[ext=mp4]/best",
                                 "-o", template, "--print", "after_move:filepath", url.absoluteString]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            process.environment = environment
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            let outData = output.fileHandleForReading.readDataToEndOfFile()
            let errData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let text = String(data: errData, encoding: .utf8) ?? ""
                let line = text.split(whereSeparator: { $0.isNewline }).last.map(String.init) ?? "The site did not give the video."
                throw VideoLinkError.failed("Could not get that video. \(String(line.prefix(220)))")
            }
            let printed = String(data: outData, encoding: .utf8)?.split(whereSeparator: { $0.isNewline }).last.map(String.init)
            if let printed = printed, FileManager.default.fileExists(atPath: printed) { return URL(fileURLWithPath: printed) }
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            if let found = files.first(where: { $0.hasPrefix(name) }) { return directory.appendingPathComponent(found) }
            throw VideoLinkError.failed("The download finished, but the video file was not found.")
        }.value
    }
}

/// The "paste a link" row in Video Cutter. `onLoaded` gets the saved video file.
struct VideoLinkBar: View {
    let directory: URL
    var onLoaded: (URL) -> Void
    @State private var link = ""
    @State private var busy = false
    @State private var note = ""

    private var canFetch: Bool { !busy && !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("Paste a video link · YouTube, Vimeo, Instagram or a direct .mp4", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { fetch() }
                if busy { ProgressView().controlSize(.small) }
                Button { fetch() } label: { Text(busy ? "Fetching…" : "Open link") }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canFetch)
                    .help("Only cut videos you own or have permission to use")
            }
            if !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fetch() {
        guard canFetch else { return }
        busy = true
        note = "Getting the video… long videos take a moment."
        let text = link
        let folder = directory
        Task {
            do {
                let url = try await VideoLinkFetcher.fetch(text, into: folder)
                busy = false
                note = ""
                link = ""
                onLoaded(url)
            } catch {
                busy = false
                note = error.localizedDescription
            }
        }
    }
}
