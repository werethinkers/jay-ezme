import SwiftUI
import AppKit
import Foundation
import CryptoKit
import Security

// In-app updater.
// The website publishes update/latest.json. The app compares its build number with the feed,
// downloads the new zip, checks its SHA-256 and code signature, swaps the app bundle in place
// and relaunches. User data lives outside the app bundle, so nothing is lost on update.

struct EzMeUpdateManifest: Codable, Equatable {
    var version: String
    var build: Int
    var url: String
    var sha256: String
    var notes: String?
    var published: String?
    var minimumSystemVersion: String?
}

@MainActor
final class EzMeUpdater: ObservableObject {
    static let shared = EzMeUpdater()
    nonisolated static let feedURL = URL(string: "https://ezme.ezyourlife.com/update/latest.json")!
    // Lovable Cloud (Supabase) project "EzMe Marketing Backend". The publishable key is public by design:
    // it can only read app_releases and add rows to app_events (row level security).
    nonisolated static let supabaseURL = "https://vfmuqfbmklupzzqfhdjz.supabase.co"
    nonisolated static let supabaseKey = "sb_publishable_tiCUvyFpz0GgyZJF6Ux4cQ_9LTKN3pq"

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(EzMeUpdateManifest)
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var showSheet = false
    @Published private(set) var latest: EzMeUpdateManifest?

    private var progressObservation: NSKeyValueObservation?
    private let lastCheckKey = "ezmeUpdateLastCheck"
    private let skippedBuildKey = "ezmeUpdateSkippedBuild"

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    var currentBuild: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0 }
    var updateAvailable: Bool { if let latest { return latest.build > currentBuild } else { return false } }

    /// Quiet check at launch, at most every six hours. Shows the sheet only when a new build exists
    /// and the person has not chosen to skip that build.
    func checkOnLaunch() {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        guard Self.testFeedURL != nil || Date().timeIntervalSince1970 - last > 6 * 3600 else { return }
        Task { await check(userInitiated: false) }
    }

    func checkFromMenu() {
        showSheet = true
        Task { await check(userInitiated: true) }
    }

    func check(userInitiated: Bool) async {
        if case .downloading = phase { return }
        if phase == .installing { return }
        phase = .checking
        do {
            // Ask the database and the website feed together and take the newest build either one knows.
            let candidates: [EzMeUpdateManifest]
            if let testFeed = Self.testFeedURL {
                candidates = [await Self.fetchFromWebsite(testFeed)].compactMap { $0 }
            } else {
                async let fromDatabase = Self.fetchFromDatabase()
                async let fromWebsite = Self.fetchFromWebsite(Self.feedURL)
                candidates = [await fromDatabase, await fromWebsite].compactMap { $0 }
            }
            guard let manifest = candidates.max(by: { $0.build < $1.build }) else {
                throw EzMeUpdateError.message("The update server did not answer. Check your connection and try again.")
            }
            Self.logEvent("update_check", targetBuild: manifest.build)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
            latest = manifest
            if manifest.build > currentBuild && Self.systemSupports(manifest.minimumSystemVersion) {
                phase = .available(manifest)
                let skipped = UserDefaults.standard.integer(forKey: skippedBuildKey)
                if userInitiated || skipped != manifest.build { showSheet = true }
                if Self.testFeedURL != nil && UserDefaults.standard.bool(forKey: "EzMeAutoInstallUpdate") { install() }
            } else {
                phase = .upToDate
            }
        } catch {
            phase = userInitiated ? .failed(Self.describe(error)) : .idle
        }
    }

    /// Test hook used by the Mac smoke test: a feed on this Mac only (http://127.0.0.1 or localhost),
    /// set with `defaults write com.ezme.mac EzMeUpdateFeed <url>`. Ignored for any other host.
    nonisolated static var testFeedURL: URL? {
        guard let value = UserDefaults.standard.string(forKey: "EzMeUpdateFeed"), let url = URL(string: value),
              isLocalTestURL(url) else { return nil }
        return url
    }

    nonisolated static func isLocalTestURL(_ url: URL) -> Bool {
        url.scheme == "http" && (url.host == "127.0.0.1" || url.host == "localhost")
    }

    nonisolated static var userAgent: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "EzMe/\(info["CFBundleShortVersionString"] as? String ?? "0") (\(info["CFBundleVersion"] as? String ?? "0"))"
    }

    /// Newest stable row in app_releases.
    nonisolated static func fetchFromDatabase() async -> EzMeUpdateManifest? {
        struct Row: Decodable {
            var version: String; var build: Int; var url: String; var sha256: String
            var notes: String?; var minimum_system_version: String?; var published_at: String?
        }
        guard let url = URL(string: supabaseURL + "/rest/v1/app_releases?select=version,build,url,sha256,notes,minimum_system_version,published_at&channel=eq.stable&order=build.desc&limit=1") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer " + supabaseKey, forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let row = (try? JSONDecoder().decode([Row].self, from: result.0))?.first else { return nil }
        return EzMeUpdateManifest(version: row.version, build: row.build, url: row.url, sha256: row.sha256,
                                  notes: row.notes, published: row.published_at, minimumSystemVersion: row.minimum_system_version)
    }

    /// update/latest.json on the website (fallback when the database can't be reached).
    nonisolated static func fetchFromWebsite(_ feed: URL) async -> EzMeUpdateManifest? {
        var request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(EzMeUpdateManifest.self, from: result.0)
    }

    /// Anonymous update event (version, build, macOS version). Fire and forget; failures are ignored.
    nonisolated static func logEvent(_ event: String, targetBuild: Int? = nil, detail: String? = nil) {
        guard let url = URL(string: supabaseURL + "/rest/v1/app_events") else { return }
        let info = Bundle.main.infoDictionary ?? [:]
        var row: [String: Any] = [
            "event": event,
            "version": info["CFBundleShortVersionString"] as? String ?? "0",
            "build": Int(info["CFBundleVersion"] as? String ?? "0") ?? 0,
            "os_version": String(ProcessInfo.processInfo.operatingSystemVersionString.prefix(40)),
        ]
        if let targetBuild { row["target_build"] = targetBuild }
        if let detail { row["detail"] = String(detail.prefix(300)) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer " + supabaseKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: row)
        URLSession.shared.dataTask(with: request).resume()
    }

    func skipThisVersion() {
        if let latest { UserDefaults.standard.set(latest.build, forKey: skippedBuildKey) }
        showSheet = false
    }

    func install() {
        guard case .available(let manifest) = phase else { return }
        Task { await performInstall(manifest) }
    }

    // MARK: - Install

    private func performInstall(_ manifest: EzMeUpdateManifest) async {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("EzMeUpdate-\(UUID().uuidString)", isDirectory: true)
        do {
            guard let url = URL(string: manifest.url), url.scheme == "https" || (Self.testFeedURL != nil && Self.isLocalTestURL(url)) else {
                throw EzMeUpdateError.message("The update link is not secure.")
            }
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            Self.logEvent("update_started", targetBuild: manifest.build)
            phase = .downloading(0)
            let zip = work.appendingPathComponent("EzMe.zip")
            try await download(url, to: zip)

            phase = .installing
            let digest = SHA256.hash(data: try Data(contentsOf: zip, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
            guard digest.caseInsensitiveCompare(manifest.sha256.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame else {
                throw EzMeUpdateError.message("The download was damaged (checksum mismatch). Nothing was changed.")
            }

            let extracted = work.appendingPathComponent("extracted", isDirectory: true)
            try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
            try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])
            guard let newApp = try fm.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
                throw EzMeUpdateError.message("The download did not contain the KeyDo app.")
            }
            try verify(newApp: newApp, manifest: manifest)

            let current = Bundle.main.bundleURL
            let parent = current.deletingLastPathComponent()
            guard fm.isWritableFile(atPath: parent.path) else {
                NSWorkspace.shared.activateFileViewerSelecting([newApp])
                throw EzMeUpdateError.message("KeyDo can't write to \(parent.path). The new version is open in Finder: drag it into Applications to finish.")
            }
            // Use a clean "EzMe.app" name when possible, so "EzMe 3.38.app" does not keep an old version in its name.
            var destination = parent.appendingPathComponent("EzMe.app")
            if destination.standardizedFileURL != current.standardizedFileURL && fm.fileExists(atPath: destination.path) {
                destination = current
            }

            let script = work.appendingPathComponent("install.sh")
            try Self.installScript.write(to: script, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, current.path, destination.path, work.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            // Close the sheet, then quit. If AppKit doesn't quit within a few seconds (seen on macOS 15
            // with a sheet open), exit anyway so the installer can swap the bundle and relaunch.
            showSheet = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { exit(0) }
        } catch {
            try? fm.removeItem(at: work)
            Self.logEvent("update_failed", targetBuild: manifest.build, detail: Self.describe(error))
            phase = .failed(Self.describe(error))
        }
    }

    private func download(_ url: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = URLSession.shared.downloadTask(with: url) { location, response, error in
                if let error { continuation.resume(throwing: error); return }
                guard let location, let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    continuation.resume(throwing: EzMeUpdateError.message("The download failed. Try again later."))
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: location, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                let value = progress.fractionCompleted
                Task { @MainActor in
                    if case .downloading = self?.phase { self?.phase = .downloading(value) }
                }
            }
            task.resume()
        }
        progressObservation = nil
    }

    /// Checks the new bundle is EzMe, is newer, has a valid signature, and (when this copy is signed
    /// with a real identity) is signed by the same identity.
    private func verify(newApp: URL, manifest: EzMeUpdateManifest) throws {
        guard let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")),
              let bundleID = info["CFBundleIdentifier"] as? String,
              bundleID == Bundle.main.bundleIdentifier else {
            throw EzMeUpdateError.message("The download is not a KeyDo build.")
        }
        let newBuild = Int(info["CFBundleVersion"] as? String ?? "0") ?? 0
        guard newBuild > currentBuild else {
            throw EzMeUpdateError.message("The download is not newer than this copy.")
        }

        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(newApp as CFURL, [], &newCode) == errSecSuccess, let newCode else {
            throw EzMeUpdateError.message("Could not read the new app's signature.")
        }
        let strict = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures) | UInt32(kSecCSStrictValidate))
        guard SecStaticCodeCheckValidity(newCode, strict, nil) == errSecSuccess else {
            throw EzMeUpdateError.message("The new app's signature is not valid. Nothing was changed.")
        }

        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
              SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic else { return }
        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(selfStatic, SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)), &signingInfo) == errSecSuccess,
              let dict = signingInfo as? [String: Any] else { return }
        let flags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let isAdhoc = flags & SecCodeSignatureFlags.adhoc.rawValue != 0
        if isAdhoc { return } // An ad-hoc copy has no identity to compare against.

        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) == errSecSuccess, let requirement else { return }
        guard SecStaticCodeCheckValidity(newCode, strict, requirement) == errSecSuccess else {
            throw EzMeUpdateError.message("The new app is not signed by the KeyDo publisher. Nothing was changed.")
        }
    }

    // Waits for EzMe to quit, swaps the bundle (restoring the old one if the copy fails), and relaunches.
    // Arguments: pid, new app, current app, destination app, work dir.
    private static let installScript = """
    #!/bin/sh
    PID="$1"; NEW="$2"; CURRENT="$3"; DEST="$4"; WORK="$5"
    i=0
    while kill -0 "$PID" 2>/dev/null && [ $i -lt 75 ]; do sleep 0.2; i=$((i+1)); done
    if kill -0 "$PID" 2>/dev/null; then kill -TERM "$PID" 2>/dev/null; sleep 3; fi
    if kill -0 "$PID" 2>/dev/null; then kill -KILL "$PID" 2>/dev/null; sleep 1; fi
    BACKUP="$WORK/EzMe-previous.app"
    if ! mv "$CURRENT" "$BACKUP"; then open "$CURRENT"; exit 1; fi
    if ditto "$NEW" "$DEST"; then
      xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
      open "$DEST"
      sleep 5
      rm -rf "$WORK"
    else
      rm -rf "$DEST"
      mv "$BACKUP" "$CURRENT"
      open "$CURRENT"
    fi
    """

    // MARK: - Helpers

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw EzMeUpdateError.message("Could not unpack the update.")
        }
    }

    private static func systemSupports(_ minimum: String?) -> Bool {
        guard let minimum, !minimum.isEmpty else { return true }
        let parts = minimum.split(separator: ".").compactMap { Int($0) }
        let required = OperatingSystemVersion(majorVersion: parts.count > 0 ? parts[0] : 0,
                                              minorVersion: parts.count > 1 ? parts[1] : 0,
                                              patchVersion: parts.count > 2 ? parts[2] : 0)
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(required)
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? EzMeUpdateError, case .message(let text) = error { return text }
        return error.localizedDescription
    }
}

enum EzMeUpdateError: Error {
    case message(String)
}

// MARK: - UI

/// Sidebar button: "Check for updates", or "Update available" with a dot when a new build is out.
struct EzMeUpdateSidebarButton: View {
    @ObservedObject var updater: EzMeUpdater
    var collapsed: Bool

    var body: some View {
        Button {
            updater.checkFromMenu()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: updater.updateAvailable ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath")
                if !collapsed {
                    Text(updater.updateAvailable ? "Update available" : "Check for updates")
                    Spacer(minLength: 0)
                }
            }
            .font(.subheadline.bold())
            .padding(10)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .background(updater.updateAvailable ? Color(red: 1, green: 0.80, blue: 0.38).opacity(0.28) : Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .help("Version \(updater.currentVersion) (build \(updater.currentBuild))")
    }
}

struct EzMeUpdateSheet: View {
    @ObservedObject var updater: EzMeUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill").font(.system(size: 34)).foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("KeyDo updates").font(.title2.bold())
                    Text("This Mac has version \(updater.currentVersion) (build \(String(updater.currentBuild))).")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            content
            HStack {
                if case .available = updater.phase {
                    Button("Skip this version") { updater.skipThisVersion() }
                }
                Spacer()
                Button(closeTitle) { updater.showSheet = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(updater.phase == .installing)
                if case .available = updater.phase {
                    Button("Update now") { updater.install() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                } else if case .failed = updater.phase {
                    Button("Try again") { Task { await updater.check(userInitiated: true) } }
                }
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var closeTitle: String {
        if case .available = updater.phase { return "Later" }
        return "Close"
    }

    @ViewBuilder private var content: some View {
        switch updater.phase {
        case .idle, .checking:
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Checking ezme.ezyourlife.com for a new version...") }
        case .upToDate:
            Label("You have the latest version.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        case .available(let manifest):
            VStack(alignment: .leading, spacing: 8) {
                Text("Version \(manifest.version) (build \(String(manifest.build))) is ready.").font(.headline)
                if let notes = manifest.notes, !notes.isEmpty {
                    ScrollView { Text(notes).font(.callout).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                        .frame(maxHeight: 180)
                        .padding(10)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                Text("KeyDo will download the update, replace itself and reopen. Your shortcuts, media and settings stay as they are.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .downloading(let value):
            VStack(alignment: .leading, spacing: 6) {
                Text("Downloading update...")
                ProgressView(value: value)
            }
        case .installing:
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Installing. KeyDo will reopen in a moment.") }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
