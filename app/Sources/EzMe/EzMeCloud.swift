import SwiftUI
import AppKit
import Foundation
import CryptoKit

// Cloud accounts and sync.
// People sign in with email and password (Supabase Auth in the Lovable Cloud project). Their workspace lives in the cloud:
//  - text files in the profile folder (clips.json, collections.json, ...) and the app's settings go to the
//    workspace_files table, one row per file, readable only by that user (row level security);
//  - attachments and other files go to the private ezme-media storage bucket under <user id>/.
// While someone is signed in, EzMe keeps a working copy in its profile folder so shortcuts expand instantly.
// Signing out uploads anything pending, then deletes that copy and the synced settings from this Mac.

extension Notification.Name {
    static let ezmeCloudDataChanged = Notification.Name("EzMeCloudDataChanged")
}

struct EzMeCloudSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Double
    var userID: String
    var email: String
    var name: String?
}

enum EzMeCloudError: Error {
    case message(String)
}

@MainActor
final class EzMeCloud: ObservableObject {
    static let shared = EzMeCloud()

    nonisolated static let supabaseURL = EzMeUpdater.supabaseURL
    nonisolated static let supabaseKey = EzMeUpdater.supabaseKey
    nonisolated static let bucket = "ezme-media"
    private static let sessionAccount = "ezme.cloud.session"
    private static let settingsPath = "settings.plist"
    private static let secretsPath = "keys.plist"
    private static let manifestName = ".ezme-sync-manifest.json"
    private static let profileToken = "{{EZME_PROFILE}}"

    @Published private(set) var session: EzMeCloudSession?
    @Published var status = ""
    @Published private(set) var isWorking = false
    @Published private(set) var lastSynced: Date?
    @Published private(set) var lastError: String?

    private var profile: URL?
    private var manifest: [String: ManifestEntry] = [:]
    private var timer: Timer?
    private var tick = 0
    private var syncing = false
    private var pullRequested = false
    private var activationObserver: NSObjectProtocol?

    struct ManifestEntry: Codable {
        var sha: String?
        var size: Int64?
        var mtime: Double?
        var remote: String?
    }

    init() {
        if let raw = KeyStore.load(account: Self.sessionAccount), let data = raw.data(using: .utf8),
           let saved = try? JSONDecoder().decode(EzMeCloudSession.self, from: data) {
            session = saved
        }
    }

    var isSignedIn: Bool { session != nil }
    var email: String { session?.email ?? "" }

    static func profileDirectory(identity: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiniJ", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(ezmeProfileSlug(identity), isDirectory: true)
    }

    // MARK: - Email sign-in

    /// Signs in, or creates the account first when `create` is true.
    func signIn(email rawEmail: String, password: String, create: Bool, onSignedIn: @escaping (String) -> Void) {
        guard !isWorking else { return }
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), email.contains("."), email.count >= 5 else { lastError = "Enter a valid email address."; return }
        guard password.count >= 8 else { lastError = "Use a password of at least 8 characters."; return }
        lastError = nil
        isWorking = true
        status = create ? "Creating your account..." : "Signing in..."
        Task {
            do {
                let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
                if create {
                    let data = try await Self.authRequest(path: "/auth/v1/signup", body: body)
                    if let newSession = try? Self.decodeSession(data) {
                        await finishSignIn(newSession, onSignedIn: onSignedIn)
                    } else {
                        fail("Account created. Open the confirmation email we sent to \(email), then come back and sign in.")
                    }
                } else {
                    let data = try await Self.authRequest(path: "/auth/v1/token?grant_type=password", body: body)
                    await finishSignIn(try Self.decodeSession(data), onSignedIn: onSignedIn)
                }
            } catch {
                fail(Self.describe(error))
            }
        }
    }

    func sendPasswordReset(email rawEmail: String) {
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@") else { lastError = "Type your email address first."; return }
        lastError = nil
        Task {
            do {
                let body = try JSONSerialization.data(withJSONObject: ["email": email])
                _ = try await Self.authRequest(path: "/auth/v1/recover", body: body)
                status = "If \(email) has an account, a reset link is on its way."
            } catch { fail(Self.describe(error)) }
        }
    }

    private func finishSignIn(_ newSession: EzMeCloudSession, onSignedIn: @escaping (String) -> Void) async {
        do {
            store(newSession)
            status = "Loading your workspace..."
            let folder = Self.profileDirectory(identity: newSession.email)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            profile = folder
            manifest = loadManifest(folder)
            let remoteFiles = try await listRemoteFiles()
            let remoteMedia = try await listRemoteMedia()
            if remoteFiles.isEmpty && remoteMedia.isEmpty {
                let imported = importLocalAccount(into: folder, email: newSession.email)
                try await push()
                if let imported { finishImport(imported) }
            } else {
                _ = try await pull(files: remoteFiles, media: remoteMedia)
            }
            saveManifest()
            lastSynced = Date()
            status = "Signed in as \(newSession.email)"
            isWorking = false
            onSignedIn(newSession.email)
        } catch {
            fail(Self.describe(error))
        }
    }

    private func fail(_ message: String) {
        isWorking = false
        status = ""
        lastError = message
    }

    // MARK: - Sign out

    /// Uploads pending changes, then removes this person's working copy and synced settings from the Mac.
    /// If the upload fails, nothing is deleted unless `force` is true.
    func signOut(force: Bool = false) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        stopSync()
        if session != nil, profile != nil, !force {
            do { try await push(); saveManifest() } catch {
                lastError = "Couldn't upload your latest changes (\(Self.describe(error))). Connect to the internet and try again, or sign out anyway."
                startSync(profile: profile!)
                return false
            }
        }
        if let session {
            var request = URLRequest(url: URL(string: Self.supabaseURL + "/auth/v1/logout")!)
            request.httpMethod = "POST"
            request.setValue(Self.supabaseKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer " + session.accessToken, forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
            try? FileManager.default.removeItem(at: Self.profileDirectory(identity: session.email))
        }
        for key in Self.syncedDefaultsKeys() { UserDefaults.standard.removeObject(forKey: key) }
        for account in Self.syncedKeychainAccounts() { _ = KeyStore.save("", account: account) }
        _ = KeyStore.save("", account: Self.sessionAccount)
        session = nil
        profile = nil
        manifest = [:]
        lastSynced = nil
        lastError = nil
        status = "Signed out. Nothing from your account is left on this Mac."
        return true
    }

    // MARK: - Sync loop

    func startSync(profile folder: URL) {
        guard session != nil else { return }
        if profile?.standardizedFileURL != folder.standardizedFileURL || manifest.isEmpty {
            profile = folder
            manifest = loadManifest(folder)
        }
        guard timer == nil else { return }
        pullRequested = true
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.timerFired() }
        }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pullRequested = true }
        }
        timerFired()
    }

    func stopSync() {
        timer?.invalidate()
        timer = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
    }

    func syncNow() {
        pullRequested = true
        timerFired()
    }

    private func timerFired() {
        guard !syncing, session != nil, profile != nil else { return }
        tick += 1
        let doPull = pullRequested || tick % 12 == 0
        pullRequested = false
        syncing = true
        Task {
            defer { syncing = false }
            do {
                try await push()
                if doPull {
                    let changed = try await pull(files: listRemoteFiles(), media: listRemoteMedia())
                    if changed { NotificationCenter.default.post(name: .ezmeCloudDataChanged, object: nil) }
                }
                saveManifest()
                lastSynced = Date()
                lastError = nil
            } catch {
                lastError = Self.describe(error)
            }
        }
    }

    // MARK: - Push (this Mac -> cloud)

    private func push() async throws {
        guard let folder = profile, let session = try await freshSession() else { return }
        let fm = FileManager.default

        // Text files at the top of the profile folder, with this Mac's folder path replaced by a token.
        var seenText = Set<String>()
        for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        where url.pathExtension.lowercased() == "json" && url.lastPathComponent != Self.manifestName {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let path = url.lastPathComponent
            seenText.insert(path)
            let content = tokenize(raw, folder: folder)
            let sha = Self.sha256(content)
            if manifest[path]?.sha != sha {
                try await upsertFile(path: path, content: content, sha: sha, session: session)
                manifest[path] = ManifestEntry(sha: sha, remote: sha)
            }
        }
        // Settings.
        let settings = tokenize(Self.settingsSnapshot(), folder: folder)
        let settingsSHA = Self.sha256(settings)
        seenText.insert(Self.settingsPath)
        if manifest[Self.settingsPath]?.sha != settingsSHA {
            try await upsertFile(path: Self.settingsPath, content: settings, sha: settingsSHA, session: session)
            manifest[Self.settingsPath] = ManifestEntry(sha: settingsSHA, remote: settingsSHA)
        }

        // AI provider keys and other EzMe Keychain items, so they follow the account too.
        let secrets = Self.secretsSnapshot()
        let secretsSHA = Self.sha256(secrets)
        seenText.insert(Self.secretsPath)
        if manifest[Self.secretsPath]?.sha != secretsSHA {
            try await upsertFile(path: Self.secretsPath, content: secrets, sha: secretsSHA, session: session)
            manifest[Self.secretsPath] = ManifestEntry(sha: secretsSHA, remote: secretsSHA)
        }

        // Everything in subfolders (attachments, media) goes to storage.
        var seenMedia = Set<String>()
        for (path, url) in mediaFiles(in: folder) {
            seenMedia.insert(path)
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let known = manifest["media:" + path]
            if known?.size != size || known?.mtime != mtime {
                try await uploadMedia(path: path, file: url, session: session)
                manifest["media:" + path] = ManifestEntry(size: size, mtime: mtime, remote: nil)
            }
        }

        // Files deleted on this Mac since the last sync.
        for key in manifest.keys {
            if key.hasPrefix("media:") {
                let path = String(key.dropFirst(6))
                if !seenMedia.contains(path) { try await deleteMedia(path: path, session: session); manifest[key] = nil }
            } else if !seenText.contains(key) {
                try await deleteFile(path: key, session: session)
                manifest[key] = nil
            }
        }
    }

    // MARK: - Pull (cloud -> this Mac)

    struct RemoteFile: Decodable { var path: String; var sha256: String?; var updated_at: String? }
    struct RemoteMedia { var path: String; var key: String; var stamp: String }

    /// Returns true when something on this Mac changed.
    private func pull(files: [RemoteFile], media: [RemoteMedia]) async throws -> Bool {
        guard let folder = profile, let session = try await freshSession() else { return false }
        let fm = FileManager.default
        var changed = false

        let remotePaths = Set(files.map(\.path))
        for file in files where file.sha256 == nil || manifest[file.path]?.remote != file.sha256 {
            guard let content = try await downloadFile(path: file.path, session: session) else { continue }
            let sha = Self.sha256(content)
            let local = detokenize(content, folder: folder, json: file.path.hasSuffix(".json"))
            if file.path == Self.settingsPath {
                Self.applySettings(local)
            } else if file.path == Self.secretsPath {
                Self.applySecrets(content)
            } else if Self.isSafeRelativePath(file.path) {
                try local.write(to: folder.appendingPathComponent(file.path), atomically: true, encoding: .utf8)
            }
            manifest[file.path] = ManifestEntry(sha: sha, remote: sha)
            changed = true
        }
        for key in manifest.keys where !key.hasPrefix("media:") && !remotePaths.contains(key) && manifest[key]?.remote != nil {
            if key != Self.settingsPath && key != Self.secretsPath { try? fm.removeItem(at: folder.appendingPathComponent(key)) }
            manifest[key] = nil
            changed = true
        }

        let remoteMediaPaths = Set(media.map(\.path))
        for item in media where Self.isSafeRelativePath(item.path) {
            let key = "media:" + item.path
            let target = folder.appendingPathComponent(item.path)
            if let known = manifest[key] {
                if known.remote == nil { manifest[key]?.remote = item.stamp; continue } // our own upload
                if known.remote == item.stamp { continue }
            } else if fm.fileExists(atPath: target.path) {
                // Same file already here (for example after an import): just remember it.
                let values = try? target.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                manifest[key] = ManifestEntry(size: Int64(values?.fileSize ?? 0), mtime: values?.contentModificationDate?.timeIntervalSince1970, remote: item.stamp)
                continue
            }
            try await downloadMedia(key: item.key, to: target, session: session)
            let values = try? target.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            manifest[key] = ManifestEntry(size: Int64(values?.fileSize ?? 0), mtime: values?.contentModificationDate?.timeIntervalSince1970, remote: item.stamp)
            changed = true
        }
        for key in manifest.keys where key.hasPrefix("media:") && manifest[key]?.remote != nil && !remoteMediaPaths.contains(String(key.dropFirst(6))) {
            try? fm.removeItem(at: folder.appendingPathComponent(String(key.dropFirst(6))))
            manifest[key] = nil
            changed = true
        }
        return changed
    }

    // MARK: - Importing a local account from an earlier version

    struct ImportedAccount { var folder: URL; var username: String }

    /// First sign-in with an empty cloud workspace: copies the local EzMe account last used on this Mac into
    /// the cloud workspace so nothing is lost.
    private func importLocalAccount(into folder: URL, email: String) -> ImportedAccount? {
        let fm = FileManager.default
        guard let username = UserDefaults.standard.string(forKey: "ezmeLocalUsername"), !username.isEmpty else { return nil }
        let old = Self.profileDirectory(identity: username)
        guard old.standardizedFileURL != folder.standardizedFileURL,
              let items = try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil), !items.isEmpty else { return nil }
        for item in items where item.lastPathComponent != ".DS_Store" {
            let dest = folder.appendingPathComponent(item.lastPathComponent)
            try? fm.removeItem(at: dest)
            try? fm.copyItem(at: item, to: dest)
        }
        // Point attachment paths at the new folder.
        for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "json" {
            guard var text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            text = text.replacingOccurrences(of: Self.jsonEscaped(old.path), with: Self.jsonEscaped(folder.path))
                .replacingOccurrences(of: old.path, with: folder.path)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        // Per-account settings keys.
        let defaults = UserDefaults.standard
        let oldSlug = ezmeProfileSlug(username), newSlug = ezmeProfileSlug(email)
        for (key, value) in defaults.dictionaryRepresentation() {
            var newKey: String?
            if key.hasSuffix("." + oldSlug) { newKey = String(key.dropLast(oldSlug.count)) + newSlug }
            if key.hasPrefix("ezme.stats.\(username).") { newKey = "ezme.stats.\(email)." + key.dropFirst("ezme.stats.\(username).".count) }
            if let newKey, defaults.object(forKey: newKey) == nil { defaults.set(value, forKey: newKey) }
        }
        status = "Moved your shortcuts from the local account \(username) to the cloud."
        return ImportedAccount(folder: old, username: username)
    }

    /// After the imported data is safely in the cloud, the old local copy goes to the Trash.
    private func finishImport(_ imported: ImportedAccount) {
        try? FileManager.default.trashItem(at: imported.folder, resultingItemURL: nil)
        UserDefaults.standard.set(false, forKey: "ezmeLocalSignedIn")
        UserDefaults.standard.removeObject(forKey: "ezmeLocalUsername")
    }

    // MARK: - Settings snapshot

    private static let localOnlyKeys: Set<String> = [
        "ezmePickerOriginX", "ezmePickerOriginY", "ezmeCurrentEmail", "ezmeLocalSignedIn", "ezmeLocalUsername",
        "ezmeLegacyDataClaimed", "ezmeLocalLegacyProfileMoved", "ezmeBrowserPrivateWorkspace",
        "ezmeUpdateLastCheck", "ezmeUpdateSkippedBuild", "EzMeUpdateFeed", "EzMeAutoInstallUpdate",
    ]

    static func syncedDefaultsKeys() -> [String] {
        UserDefaults.standard.dictionaryRepresentation().keys.filter { key in
            (key.hasPrefix("ezme") || key.hasPrefix("miniJ")) && !localOnlyKeys.contains(key)
        }.sorted()
    }

    static func settingsSnapshot() -> String {
        var values: [String: Any] = [:]
        let defaults = UserDefaults.standard
        for key in syncedDefaultsKeys() { if let value = defaults.object(forKey: key) { values[key] = value } }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func applySettings(_ text: String) {
        guard let data = text.data(using: .utf8),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
        let defaults = UserDefaults.standard
        for (key, value) in values where !localOnlyKeys.contains(key) { defaults.set(value, forKey: key) }
    }

    // MARK: - Keychain items (AI keys and similar)

    /// Keychain items that travel with the account. The sign-in session and old local passwords stay out.
    static func syncedKeychainAccounts() -> [String] {
        KeyStore.allAccounts().filter { $0 != sessionAccount && !$0.hasPrefix("ezme.local.user.") }
    }

    static func secretsSnapshot() -> String {
        var values: [String: String] = [:]
        for account in syncedKeychainAccounts() { if let value = KeyStore.load(account: account), !value.isEmpty { values[account] = value } }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func applySecrets(_ text: String) {
        guard let data = text.data(using: .utf8),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else { return }
        for (account, value) in values where account != sessionAccount && !account.hasPrefix("ezme.local.user.") {
            if KeyStore.load(account: account) != value { _ = KeyStore.save(value, account: account) }
        }
    }

    // MARK: - Paths

    private func tokenize(_ text: String, folder: URL) -> String {
        text.replacingOccurrences(of: Self.jsonEscaped(folder.path), with: Self.profileToken)
            .replacingOccurrences(of: folder.path, with: Self.profileToken)
    }

    private func detokenize(_ text: String, folder: URL, json: Bool) -> String {
        text.replacingOccurrences(of: Self.profileToken, with: json ? Self.jsonEscaped(folder.path) : folder.path)
    }

    private static func jsonEscaped(_ path: String) -> String { path.replacingOccurrences(of: "/", with: "\\/") }

    static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    private func mediaFiles(in folder: URL) -> [(String, URL)] {
        var result: [(String, URL)] = []
        let fm = FileManager.default
        for top in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
            guard (try? top.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let walker = fm.enumerator(at: top, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            for case let url as URL in walker {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true, url.lastPathComponent != ".DS_Store" else { continue }
                let relative = String(url.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count + 1))
                result.append((relative, url))
            }
        }
        return result
    }

    private func loadManifest(_ folder: URL) -> [String: ManifestEntry] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.manifestName)),
              let decoded = try? JSONDecoder().decode([String: ManifestEntry].self, from: data) else { return [:] }
        return decoded
    }

    private func saveManifest() {
        guard let folder = profile, let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: folder.appendingPathComponent(Self.manifestName), options: .atomic)
    }

    // MARK: - Session

    private func store(_ newSession: EzMeCloudSession) {
        session = newSession
        if let data = try? JSONEncoder().encode(newSession), let text = String(data: data, encoding: .utf8) {
            _ = KeyStore.save(text, account: Self.sessionAccount)
        }
    }

    private func freshSession() async throws -> EzMeCloudSession? {
        guard var current = session else { return nil }
        if current.expiresAt - Date().timeIntervalSince1970 > 120 { return current }
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": current.refreshToken])
        let data = try await Self.authRequest(path: "/auth/v1/token?grant_type=refresh_token", body: body)
        let refreshed = try Self.decodeSession(data)
        current = refreshed
        store(current)
        return current
    }

    nonisolated private static func authRequest(path: String, body: Data) async throws -> Data {
        var request = URLRequest(url: URL(string: supabaseURL + path)!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap { $0["error_description"] as? String ?? $0["msg"] as? String ?? $0["message"] as? String }
            throw EzMeCloudError.message(detail ?? "The sign-in server refused the request.")
        }
        return data
    }

    nonisolated private static func decodeSession(_ data: Data) throws -> EzMeCloudSession {
        struct Meta: Decodable { var full_name: String?; var name: String? }
        struct User: Decodable { var id: String; var email: String?; var user_metadata: Meta? }
        struct Token: Decodable { var access_token: String; var refresh_token: String; var expires_in: Double?; var expires_at: Double?; var user: User }
        let token = try JSONDecoder().decode(Token.self, from: data)
        let expires = token.expires_at ?? (Date().timeIntervalSince1970 + (token.expires_in ?? 3600))
        guard let email = token.user.email, !email.isEmpty else { throw EzMeCloudError.message("The account has no email address.") }
        return EzMeCloudSession(accessToken: token.access_token, refreshToken: token.refresh_token, expiresAt: expires,
                                userID: token.user.id, email: email.lowercased(), name: token.user.user_metadata?.full_name ?? token.user.user_metadata?.name)
    }

    // MARK: - REST: workspace_files

    private func restRequest(_ path: String, method: String = "GET", session: EzMeCloudSession) -> URLRequest {
        var request = URLRequest(url: URL(string: Self.supabaseURL + path)!, timeoutInterval: 60)
        request.httpMethod = method
        request.setValue(Self.supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer " + session.accessToken, forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest, accept: Set<Int> = [200, 201, 204]) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard accept.contains(code) else {
            let text = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw EzMeCloudError.message("Cloud request failed (\(code)). \(text)")
        }
        return data
    }

    private static func queryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? value
    }

    private func listRemoteFiles() async throws -> [RemoteFile] {
        guard let session = try await freshSession() else { return [] }
        let data = try await send(restRequest("/rest/v1/workspace_files?select=path,sha256,updated_at", session: session))
        return try JSONDecoder().decode([RemoteFile].self, from: data)
    }

    private func downloadFile(path: String, session: EzMeCloudSession) async throws -> String? {
        let data = try await send(restRequest("/rest/v1/workspace_files?select=content&path=eq." + Self.queryValue(path), session: session))
        struct Row: Decodable { var content: String }
        return try JSONDecoder().decode([Row].self, from: data).first?.content
    }

    private func upsertFile(path: String, content: String, sha: String, session: EzMeCloudSession) async throws {
        var request = restRequest("/rest/v1/workspace_files", method: "POST", session: session)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let row: [String: Any] = [
            "user_id": session.userID, "path": path, "content": content, "sha256": sha,
            "device": String((Host.current().localizedName ?? "Mac").prefix(120)),
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: [row])
        _ = try await send(request)
    }

    private func deleteFile(path: String, session: EzMeCloudSession) async throws {
        _ = try await send(restRequest("/rest/v1/workspace_files?path=eq." + Self.queryValue(path), method: "DELETE", session: session))
    }

    // MARK: - REST: storage (object names are base64url of the relative path, so any file name works)

    private func objectKey(_ path: String, session: EzMeCloudSession) -> String {
        session.userID + "/f/" + Self.base64URL(Data(path.utf8))
    }

    private func listRemoteMedia() async throws -> [RemoteMedia] {
        guard let session = try await freshSession() else { return [] }
        var result: [RemoteMedia] = []
        var offset = 0
        struct Object: Decodable { var name: String; var id: String?; var updated_at: String? }
        while true {
            var request = restRequest("/storage/v1/object/list/" + Self.bucket, method: "POST", session: session)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "prefix": session.userID + "/f/", "limit": 1000, "offset": offset,
                "sortBy": ["column": "name", "order": "asc"],
            ] as [String: Any])
            let objects = try JSONDecoder().decode([Object].self, from: try await send(request))
            for object in objects where object.id != nil {
                guard let decoded = Self.fromBase64URL(object.name), let path = String(data: decoded, encoding: .utf8) else { continue }
                result.append(RemoteMedia(path: path, key: session.userID + "/f/" + object.name, stamp: object.updated_at ?? ""))
            }
            if objects.count < 1000 { break }
            offset += objects.count
        }
        return result
    }

    private func uploadMedia(path: String, file: URL, session: EzMeCloudSession) async throws {
        var request = restRequest("/storage/v1/object/" + Self.bucket + "/" + objectKey(path, session: session), method: "POST", session: session)
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: file)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 || code == 201 else {
            throw EzMeCloudError.message("Upload of \(file.lastPathComponent) failed (\(code)). \(String(data: data.prefix(200), encoding: .utf8) ?? "")")
        }
    }

    private func downloadMedia(key: String, to target: URL, session: EzMeCloudSession) async throws {
        var request = restRequest("/storage/v1/object/authenticated/" + Self.bucket + "/" + key, session: session)
        request.timeoutInterval = 600
        let (temp, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw EzMeCloudError.message("Download failed for \(target.lastPathComponent).") }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temp, to: target)
    }

    private func deleteMedia(path: String, session: EzMeCloudSession) async throws {
        var request = restRequest("/storage/v1/object/" + Self.bucket, method: "DELETE", session: session)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["prefixes": [objectKey(path, session: session)]])
        _ = try await send(request)
    }

    // MARK: - Helpers

    nonisolated static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    nonisolated static func fromBase64URL(_ text: String) -> Data? {
        var value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value += "=" }
        return Data(base64Encoded: value)
    }

    nonisolated static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    nonisolated static func describe(_ error: Error) -> String {
        if let error = error as? EzMeCloudError, case .message(let text) = error { return text }
        return error.localizedDescription
    }
}

// MARK: - UI

struct EzMeCloudSignInView: View {
    @ObservedObject var cloud: EzMeCloud
    var onSignedIn: (String) -> Void
    @State private var email = ""
    @State private var password = ""
    @State private var creating = false

    private func submit() { cloud.signIn(email: email, password: password, create: creating, onSignedIn: onSignedIn) }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            if let logo = ezMeBrandImage() {
                Image(nsImage: logo).resizable().scaledToFit().frame(width: 150, height: 100)
            }
            Text("Welcome to KeyDo").font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Sign in to use your shortcuts, collections and media on every Mac.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            Picker("", selection: $creating) {
                Text("Sign in").tag(false)
                Text("Create account").tag(true)
            }
            .pickerStyle(.segmented).frame(width: 280).labelsHidden()
            VStack(spacing: 10) {
                TextField("Email", text: $email).textFieldStyle(.roundedBorder).textContentType(.username).onSubmit(submit)
                SecureField(creating ? "Password (at least 8 characters)" : "Password", text: $password).textFieldStyle(.roundedBorder).onSubmit(submit)
            }
            .frame(width: 320)
            Button(action: submit) {
                Text(creating ? "Create account" : "Sign in").font(.headline).frame(width: 280, height: 26)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(cloud.isWorking || email.isEmpty || password.isEmpty)
            if !creating {
                Button("Forgot password?") { cloud.sendPasswordReset(email: email) }.buttonStyle(.link).font(.caption)
            }
            if cloud.isWorking {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(cloud.status).foregroundStyle(.secondary) }
            } else if !cloud.status.isEmpty {
                Text(cloud.status).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            }
            if let error = cloud.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).frame(maxWidth: 460)
            }
            Spacer()
            Text("Everything you save, including your AI keys, lives in your private KeyDo cloud account. When you sign out, KeyDo removes it from this Mac.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 520).padding(.bottom, 24)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color.blue.opacity(0.04), Color.purple.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

struct EzMeCloudAccountBox: View {
    @ObservedObject var cloud: EzMeCloud
    var onSignedOut: () -> Void
    @State private var offerForce = false

    var body: some View {
        GroupBox("KeyDo cloud account") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(cloud.email, systemImage: "person.crop.circle.fill")
                    Spacer()
                    Button("Sync now") { cloud.syncNow() }.buttonStyle(.bordered).disabled(cloud.isWorking)
                    Button("Sign out") {
                        Task { if await cloud.signOut() { onSignedOut() } else { offerForce = true } }
                    }
                    .buttonStyle(.bordered)
                    .disabled(cloud.isWorking)
                }
                Group {
                    if let error = cloud.lastError {
                        Label(error, systemImage: "exclamationmark.icloud").foregroundStyle(.orange)
                    } else if let date = cloud.lastSynced {
                        Label("Synced \(date.formatted(date: .omitted, time: .shortened)). Changes upload within a few seconds.", systemImage: "checkmark.icloud")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Syncing...", systemImage: "icloud").foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                if offerForce {
                    Button("Sign out anyway (unsynced changes on this Mac will be lost)", role: .destructive) {
                        Task { if await cloud.signOut(force: true) { offerForce = false; onSignedOut() } }
                    }
                    .font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
