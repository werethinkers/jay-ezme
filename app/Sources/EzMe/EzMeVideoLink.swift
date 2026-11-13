// Video Cutter: open a video from a link.
//
// A direct link to a video file (.mp4, .mov, .m4v, .webm) is downloaded as it is. A page link (YouTube, Vimeo,
// Instagram and most other video sites) is fetched with the free open-source helper yt-dlp. KeyDo downloads that
// helper once into its own folder, keeps it up to date when a site changes, and, for sites that want a sign-in
// (Instagram, private videos), tries again with the sign-in from your browser. The video is saved next to the other
// Ez Studio media, then opens in the cutter.
import AppKit
import SwiftUI

enum VideoLinkError: LocalizedError {
    case invalid
    case helperUnavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalid:
            return "That does not look like a web link. Paste the full address of the video."
        case .helperUnavailable(let reason):
            return "KeyDo could not set up the video helper (\(reason)). Check your internet connection and try again. Direct .mp4 or .mov links work without it."
        case .failed(let message):
            return message
        }
    }
}

private final class DataBox: @unchecked Sendable { var data = Data() }

enum VideoLinkFetcher {
    typealias Status = @Sendable (String) -> Void

    private static let directTypes: Set<String> = ["mp4", "mov", "m4v", "webm"]
    private static let helperDownload = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"

    static func fetch(_ text: String, into directory: URL, status: @escaping Status) async throws -> URL {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.lowercased().hasPrefix("http") { raw = "https://" + raw }
        guard let url = URL(string: raw), let host = url.host, host.contains(".") else { throw VideoLinkError.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if directTypes.contains(url.pathExtension.lowercased()) {
            status("Downloading the video…")
            return try await download(url, into: directory)
        }
        return try await viaHelper(url, into: directory, status: status)
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

    // MARK: The helper

    private static var managedHelper: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KeyDo", isDirectory: true).appendingPathComponent("Helpers", isDirectory: true).appendingPathComponent("yt-dlp")
    }

    /// A yt-dlp the person already has, or the copy KeyDo keeps for itself (downloaded on first use).
    private static func helperPath(status: Status) async throws -> String {
        for path in ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", NSHomeDirectory() + "/.local/bin/yt-dlp"] where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let own = managedHelper
        if FileManager.default.isExecutableFile(atPath: own.path) { return own.path }
        status("Setting up the video helper (one time, about 35 MB)…")
        guard let source = URL(string: helperDownload) else { throw VideoLinkError.helperUnavailable("bad address") }
        do {
            let (temp, response) = try await URLSession.shared.download(from: source)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw VideoLinkError.helperUnavailable("download answered \(http.statusCode)")
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? NSNumber)?.intValue ?? 0
            guard size > 5_000_000 else { throw VideoLinkError.helperUnavailable("the download was incomplete") }
            try FileManager.default.createDirectory(at: own.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: own.path) { try FileManager.default.removeItem(at: own) }
            try FileManager.default.moveItem(at: temp, to: own)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: own.path)
            _ = try? await run(["/usr/bin/xattr", "-c", own.path], timeout: 15)
        } catch let error as VideoLinkError {
            throw error
        } catch {
            throw VideoLinkError.helperUnavailable(error.localizedDescription)
        }
        return own.path
    }

    private struct Output {
        var status: Int32
        var out: String
        var err: String
    }

    private static func run(_ command: [String], timeout: TimeInterval) async throws -> Output {
        try await Task.detached(priority: .userInitiated) { () throws -> Output in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command[0])
            process.arguments = Array(command.dropFirst())
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            process.environment = environment
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
            let errBox = DataBox()
            let errReader = Thread { errBox.data = errors.fileHandleForReading.readDataToEndOfFile() }
            errReader.start()
            let outData = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()
            while !errReader.isFinished { usleep(20_000) }
            return Output(status: process.terminationStatus,
                          out: String(data: outData, encoding: .utf8) ?? "",
                          err: String(data: errBox.data, encoding: .utf8) ?? "")
        }.value
    }

    private static func attempt(_ tool: String, _ url: URL, _ directory: URL, extra: [String]) async throws -> URL {
        let name = "link-\(UUID().uuidString)"
        let template = directory.appendingPathComponent(name + ".%(ext)s").path
        let base = [tool, "--quiet", "--no-warnings", "--no-playlist", "--no-mtime",
                    "-f", "best[ext=mp4][protocol^=http]/best[ext=mp4]/best",
                    "-o", template, "--print", "after_move:filepath"]
        let result = try await run(base + extra + [url.absoluteString], timeout: 900)
        guard result.status == 0 else {
            let lines = result.err.split(whereSeparator: { $0.isNewline }).map(String.init)
            let line = lines.last(where: { $0.contains("ERROR") }) ?? lines.last ?? "The site did not give the video."
            throw VideoLinkError.failed(String(line.prefix(260)))
        }
        if let printed = result.out.split(whereSeparator: { $0.isNewline }).last.map(String.init),
           FileManager.default.fileExists(atPath: printed) {
            return URL(fileURLWithPath: printed)
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        if let found = files.first(where: { $0.hasPrefix(name) }) { return directory.appendingPathComponent(found) }
        throw VideoLinkError.failed("The download finished, but the video file was not found.")
    }

    private static func needsSignIn(_ message: String) -> Bool {
        let lower = message.lowercased()
        return ["login", "log in", "sign in", "cookies", "private", "rate-limit", "rate limit", "not available", "empty media", "confirm you", "bot"].contains(where: { lower.contains($0) })
    }

    private static func viaHelper(_ url: URL, into directory: URL, status: Status) async throws -> URL {
        let tool = try await helperPath(status: status)
        status("Getting the video… long videos take a moment.")
        var failure = "The site did not give the video."
        do { return try await attempt(tool, url, directory, extra: []) } catch let error as VideoLinkError {
            failure = error.localizedDescription
        }

        // Sites change often: update the helper once and try again.
        status("Updating the video helper and trying again…")
        _ = try? await run([tool, "-U"], timeout: 120)
        do { return try await attempt(tool, url, directory, extra: []) } catch let error as VideoLinkError {
            failure = error.localizedDescription
        }

        // Instagram, private and age-limited videos want a sign-in: borrow the one from the browser.
        if needsSignIn(failure) {
            for browser in ["chrome", "safari", "firefox", "edge"] {
                status("This site wants a sign-in. Trying with your \(browser.capitalized) sign-in…")
                do { return try await attempt(tool, url, directory, extra: ["--cookies-from-browser", browser]) } catch let error as VideoLinkError {
                    let message = error.localizedDescription
                    if !message.lowercased().contains("cookie") && !message.lowercased().contains("keyring") && !message.lowercased().contains("could not find") {
                        failure = message
                    }
                }
            }
            throw VideoLinkError.failed("\(failure) Sign in to that site in Chrome or Safari, then try again.")
        }
        throw VideoLinkError.failed(failure)
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
        note = "Starting…"
        let text = link
        let folder = directory
        Task {
            do {
                let url = try await VideoLinkFetcher.fetch(text, into: folder) { message in
                    Task { @MainActor in note = message }
                }
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
