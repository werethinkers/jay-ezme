// Ezyourlife inside EzMe: the 300 apps, PromptMaster, cards, shortcuts and credits of ezyourlife.com,
// through its public API (ezmylife02: supabase/functions/api, docs/public-api.md).
//
//  1. Backslash picker: matching Ezyourlife apps appear under your own shortcuts. Picking one opens
//     the run panel, and the result is pasted where you were typing.
//  2. Apps tab: browse every app by goal, run it, save it as a shortcut.
//  3. Ask bar (Option-Space): say what you need; EzMe ranks the apps, or brainstorms / improves your words.
//  4. Smart shortcuts: a shortcut can hold an app step ("ezyourlife://app/<id>?Box=value") and your own
//     text around it ("[[result]]" marks where the result goes). Credits and top-ups in their own screen.
//
// One ezyourlife.com account pays for everything, with the same credits and prices as the website.
import SwiftUI
import AppKit
import Carbon
import AuthenticationServices

// MARK: - Config and look

enum EzyConfig {
    static let api = "https://vrsadzjyugbusfazdgyi.supabase.co/functions/v1/api/v1"
    static let site = "https://ezyourlife.com"
    static let keyAccount = "ezyourlife.apiKey"
    static let connectURL = "\(site)/developers/keys?app=ezme&redirect=ezme://ezyourlife-connected"
    static let appScheme = "ezyourlife"
    static let resultMarker = "[[result]]"
    static let collection = "Ezyourlife apps"
}

/// Ezyourlife's sticker-sheet palette (Ezyourlife Design System tokens).
enum EzyColor {
    static let cream = Color(red: 1.0, green: 0.973, blue: 0.922)
    static let ink = Color(red: 0.071, green: 0.071, blue: 0.071)
    static let sand = Color(red: 0.957, green: 0.922, blue: 0.863)
    static let pink = Color(red: 1.0, green: 0.561, blue: 0.914)
    static let sun = Color(red: 1.0, green: 0.784, blue: 0.0)
    static let teal = Color(red: 0.133, green: 0.765, blue: 0.651)
    static let sky = Color(red: 0.561, green: 0.706, blue: 1.0)
    static let lime = Color(red: 0.745, green: 0.957, blue: 0.204)
    static let coral = Color(red: 1.0, green: 0.506, blue: 0.341)
    static let muted = Color(red: 0.29, green: 0.29, blue: 0.29)
    static func goal(_ name: String?) -> Color {
        switch name { case "pink": pink; case "sun": sun; case "teal": teal; case "sky": sky; case "lime": lime; default: coral }
    }
}

struct EzyBlock: ViewModifier {
    var fill: Color = .white
    var radius: CGFloat = 14
    var shadow: CGFloat = 3
    func body(content: Content) -> some View {
        // Later .background layers sit behind earlier ones, so the card fill goes first and the hard shadow last.
        content
            .foregroundStyle(EzyColor.ink)
            .environment(\.colorScheme, .light)
            .background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(EzyColor.ink, lineWidth: 2))
            .background(RoundedRectangle(cornerRadius: radius).fill(EzyColor.ink).offset(x: shadow, y: shadow))
    }
}
extension View {
    /// Ezyourlife screens always use the light sticker-sheet look, whatever the Mac's appearance is.
    func ezyLight() -> some View {
        self.environment(\.colorScheme, .light).foregroundStyle(EzyColor.ink).tint(EzyColor.ink)
    }
    func ezyBlock(_ fill: Color = .white, radius: CGFloat = 14, shadow: CGFloat = 3) -> some View { modifier(EzyBlock(fill: fill, radius: radius, shadow: shadow)) }
}

struct EzyButtonStyle: ButtonStyle {
    var fill: Color = EzyColor.pink
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(EzyColor.ink)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .ezyBlock(fill, radius: 12, shadow: configuration.isPressed ? 0 : 3)
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
    }
}

struct EzyBadge: View {
    var text: String
    var fill: Color = .white
    var body: some View {
        Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(EzyColor.ink)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(fill)).overlay(Capsule().stroke(EzyColor.ink, lineWidth: 2))
    }
}

func ezyCredits(_ n: Int?) -> String {
    guard let n else { return "price on site" }
    return n == 1 ? "1 credit" : "\(n) credits"
}

// MARK: - Models

struct EzyApp: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var description: String
    var category: String
    var goal_color: String?
    var credits: Int?
    var runnable: Bool
    var mode: String
    var url: String
}

struct EzyField: Identifiable, Codable, Hashable {
    var id: String { key }
    var key: String
    var label: String
    var type: String
    var required: Bool?
    var placeholder: String?
    var options: [String]?
    var `default`: String?
    var help: String?
    var profile: String?
}

struct EzyAppDetail: Codable {
    var id: String
    var name: String
    var description: String
    var category: String
    var goal_color: String?
    var credits: Int?
    var runnable: Bool
    var mode: String
    var url: String
    var intro: String?
    var cta: String?
    var fields: [EzyField]?
    var prompt_label: String?
    var styles: [String]?
    var aspects: [String]?
    var suggestions: [String]?
    var variants: [String]?
}

struct EzyCategory: Codable, Hashable { var name: String; var goal_color: String? }

struct EzyPack: Identifiable, Codable, Hashable { var id: String; var inr: Int; var credits: Int }

struct EzyLedgerRow: Codable, Hashable { var delta: Int; var reason: String?; var tool_id: String?; var created_at: String }

struct EzyWallet: Codable {
    var balance: Int
    var free: Int
    var paid: Int
    var promo: Int?
    var recent: [EzyLedgerRow]
    var packs: [EzyPack]
}

struct EzyRunResult {
    var text: String
    var imageDataURL: String?
    var credits: Int
    var balance: Int?
}

enum EzyError: LocalizedError {
    case notConnected
    case server(code: String, message: String, topup: String?)
    var errorDescription: String? {
        switch self {
        case .notConnected: return "Connect your Ezyourlife account first."
        case .server(_, let message, _): return message
        }
    }
}

/// Turns an app's answer (text, JSON object or list) into readable text to paste.
func ezyRender(_ value: Any?, depth: Int = 0) -> String {
    guard let value else { return "" }
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    let pad = String(repeating: "  ", count: depth)
    if let list = value as? [Any] {
        return list.map { item -> String in
            if let d = item as? [String: Any], let title = d["title"] as? String, let body = d["prompt"] ?? d["text"] ?? d["content"] {
                return "\(pad)\(title)\n\(pad)\(ezyRender(body, depth: depth + 1))"
            }
            let inner = ezyRender(item, depth: depth + 1)
            return item is [String: Any] ? inner : "\(pad)- \(inner)"
        }.joined(separator: "\n\n")
    }
    if let dict = value as? [String: Any] {
        return dict.keys.sorted().map { key -> String in
            let inner = ezyRender(dict[key], depth: depth + 1)
            let label = key.replacingOccurrences(of: "_", with: " ").capitalized
            return inner.contains("\n") ? "\(pad)\(label):\n\(inner)" : "\(pad)\(label): \(inner)"
        }.joined(separator: "\n")
    }
    return "\(value)"
}

// MARK: - Links stored in shortcuts

enum EzyLink {
    /// "ezyourlife://app/<id>?Box=value&…"
    static func url(appID: String, values: [String: String]) -> String {
        var c = URLComponents()
        c.scheme = EzyConfig.appScheme
        c.host = "app"
        c.path = "/" + appID
        let items = values.filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        if !items.isEmpty { c.queryItems = items }
        return c.string ?? "\(EzyConfig.appScheme)://app/\(appID)"
    }
    static func parse(_ raw: String?) -> (appID: String, values: [String: String])? {
        guard let raw, let c = URLComponents(string: raw), c.scheme == EzyConfig.appScheme, c.host == "app" else { return nil }
        let id = c.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !id.isEmpty else { return nil }
        var values = [String: String]()
        for item in c.queryItems ?? [] { values[item.name] = item.value ?? "" }
        return (id, values)
    }
    static func isApp(_ clip: Clip) -> Bool { parse(clip.webURL) != nil }
}

// MARK: - Client

@MainActor final class Ezyourlife: ObservableObject {
    static let shared = Ezyourlife()

    @Published private(set) var apiKey: String?
    @Published private(set) var catalogue: [EzyApp] = []
    @Published private(set) var categories: [EzyCategory] = []
    @Published var wallet: EzyWallet?
    @Published var status = ""
    @Published var isConnecting = false
    private var authSession: ASWebAuthenticationSession?
    private let presenter = EzyAuthPresenter()
    private var loadingCatalogue = false

    var isConnected: Bool { !(apiKey ?? "").isEmpty }

    init() {
        apiKey = KeyStore.load(account: EzyConfig.keyAccount)
        loadCachedCatalogue()
    }

    // Connection

    func connect() {
        guard let url = URL(string: EzyConfig.connectURL) else { return }
        isConnecting = true
        status = "Opening ezyourlife.com..."
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "ezme") { [weak self] callback, error in
            Task { @MainActor in
                guard let self else { return }
                self.authSession = nil
                self.isConnecting = false
                if let error {
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    self.status = cancelled ? "" : "Could not connect: \(error.localizedDescription)"
                    return
                }
                guard let callback, let key = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "key" })?.value,
                      key.hasPrefix("ezy_live_") else {
                    self.status = "Ezyourlife did not send a key back. Try again."
                    return
                }
                self.useKey(key)
            }
        }
        session.presentationContextProvider = presenter
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        if !session.start() { isConnecting = false; status = "Could not open the sign-in window." }
    }

    /// For people who made a key on ezyourlife.com themselves.
    func useKey(_ key: String) {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.hasPrefix("ezy_live_") else { status = "That is not an Ezyourlife key (it starts with ezy_live_)."; return }
        _ = KeyStore.save(clean, account: EzyConfig.keyAccount)
        apiKey = clean
        status = "Connected to Ezyourlife."
        Task { await refreshWallet() }
    }

    func disconnect() {
        _ = KeyStore.save("", account: EzyConfig.keyAccount)
        apiKey = nil
        wallet = nil
        status = "Disconnected. Remove the key on ezyourlife.com too if you no longer need it."
    }

    // HTTP

    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, auth: Bool = true) async throws -> [String: Any] {
        guard let url = URL(string: EzyConfig.api + path) else { throw EzyError.server(code: "bad_url", message: "Bad address.", topup: nil) }
        var req = URLRequest(url: url, timeoutInterval: 150)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("EzMe-Mac", forHTTPHeaderField: "X-Client-Info")
        if auth {
            guard let key = apiKey, !key.isEmpty else { throw EzyError.notConnected }
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if code >= 400 || object["ok"] as? Bool == false {
            if code == 401 && auth { status = "Your Ezyourlife connection has expired. Connect again." }
            throw EzyError.server(code: object["error"] as? String ?? "http_\(code)",
                                  message: object["message"] as? String ?? "Ezyourlife answered \(code).",
                                  topup: object["topup_url"] as? String)
        }
        return object
    }

    private func decode<T: Decodable>(_ type: T.Type, _ value: Any?) -> T? {
        guard let value, JSONSerialization.isValidJSONObject(value) || value is [Any] else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // Catalogue (public, cached on disk so the picker can rank it without waiting)

    private var cacheURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("KeyDo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("ezyourlife-apps.json")
    }

    private func loadCachedCatalogue() {
        guard let data = try? Data(contentsOf: cacheURL), let apps = try? JSONDecoder().decode([EzyApp].self, from: data) else { return }
        catalogue = apps
        categories = Array(Set(apps.map { EzyCategory(name: $0.category, goal_color: $0.goal_color) })).sorted { $0.name < $1.name }
    }

    func refreshCatalogue(force: Bool = false) async {
        guard !loadingCatalogue else { return }
        if !force, let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < 6 * 3600, !catalogue.isEmpty { return }
        loadingCatalogue = true
        defer { loadingCatalogue = false }
        var all = [EzyApp]()
        var offset = 0
        var cats = [EzyCategory]()
        while offset < 2000 {
            guard let page = try? await request("/apps?limit=200&offset=\(offset)", auth: false) else { break }
            let apps = decode([EzyApp].self, page["apps"]) ?? []
            if cats.isEmpty { cats = decode([EzyCategory].self, page["categories"]) ?? [] }
            all += apps
            let total = page["total"] as? Int ?? 0
            offset += 200
            if apps.isEmpty || offset >= total { break }
        }
        guard !all.isEmpty else { return }
        catalogue = all
        categories = cats.isEmpty ? Array(Set(all.map { EzyCategory(name: $0.category, goal_color: $0.goal_color) })).sorted { $0.name < $1.name } : cats
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: cacheURL, options: .atomic) }
    }

    /// Word-overlap ranking of the cached catalogue (same idea as the server's).
    func rank(_ query: String, limit: Int = 8, runnableOnly: Bool = true) -> [EzyApp] {
        let words = query.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init).filter { $0.count > 1 }
        guard !words.isEmpty else { return [] }
        let scored: [(EzyApp, Double)] = catalogue.compactMap { app in
            if runnableOnly && !app.runnable { return nil }
            let name = app.name.lowercased(), desc = app.description.lowercased(), cat = app.category.lowercased()
            var s = 0.0
            for w in words {
                if name.hasPrefix(w) { s += 6 } else if name.contains(w) { s += 4 }
                if cat.contains(w) { s += 1.5 }
                if desc.contains(w) { s += 1 }
            }
            return s >= 4 || (s > 0 && words.count == 1) ? (app, s) : nil
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    /// Apps shown at the end of the backslash picker's results.
    func pickerClips(query: String, limit: Int = 5) -> [Clip] {
        guard UserDefaults.standard.object(forKey: "ezyShowInPicker") as? Bool ?? true else { return [] }
        if catalogue.isEmpty { Task { await refreshCatalogue() } }
        return rank(query, limit: limit).map { app in
            Clip(key: "/ezy-" + app.id, name: "\(app.name) · \(ezyCredits(app.credits))", text: app.description,
                 group: EzyConfig.collection, webURL: EzyLink.url(appID: app.id, values: [:]))
        }
    }

    /// The person's saved business details on ezyourlife.com (business name, city, GSTIN…), used to fill app boxes.
    @Published var profile: [String: String] = [:]
    private var profileLoaded: Date?

    func refreshProfile(force: Bool = false) async {
        guard isConnected else { return }
        if !force, let t = profileLoaded, Date().timeIntervalSince(t) < 600 { return }
        guard let r = try? await request("/profile"), let p = r["profile"] as? [String: Any] else { return } // older API: no profile, nothing to fill
        profile = p.compactMapValues { ($0 as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } }
        profileLoaded = Date()
    }

    /// Answers typed last time for this app (not kept for apps that hold personal text).
    func lastValues(_ appID: String) -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: "ezyLast." + appID) as? [String: String]) ?? [:]
    }
    func rememberValues(_ appID: String, _ values: [String: String], fields: [EzyField]) {
        var keep = [String: String]()
        for f in fields where f.type != "textarea" && f.type != "rows" { if let v = values[f.key], !v.isEmpty, v.count < 200 { keep[f.key] = v } }
        UserDefaults.standard.set(keep, forKey: "ezyLast." + appID)
    }

    func search(_ q: String) async -> [EzyApp] {
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let r = try? await request("/apps?runnable=true&limit=8&q=\(encoded)", auth: false) else { return rank(q) }
        return decode([EzyApp].self, r["apps"]) ?? []
    }

    func detail(_ id: String) async throws -> EzyAppDetail {
        let r = try await request("/apps/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)", auth: false)
        guard let d = decode(EzyAppDetail.self, r["app"]) else { throw EzyError.server(code: "bad_reply", message: "Could not read this app.", topup: nil) }
        return d
    }

    // Running

    private func result(_ r: [String: Any]) -> EzyRunResult {
        let credits = r["credits_charged"] as? Int ?? 0
        let balance = r["balance"] as? Int
        if let balance, var w = wallet { w.balance = balance; wallet = w }
        return EzyRunResult(text: ezyRender(r["output"]), imageDataURL: r["image"] as? String, credits: credits, balance: balance)
    }

    func run(_ id: String, inputs: [String: String], messages: [[String: String]]? = nil, prompt: String? = nil,
             style: String? = nil, aspect: String? = nil, variant: String? = nil, previous: String? = nil, instruction: String? = nil) async throws -> EzyRunResult {
        var body: [String: Any] = ["inputs": inputs.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }]
        if let messages { body["messages"] = messages }
        if let prompt { body["prompt"] = prompt }
        if let style { body["style"] = style }
        if let aspect { body["aspect"] = aspect }
        if let variant { body["variant"] = variant }
        if let previous, let instruction { body["action"] = "refine"; body["previous"] = previous; body["instruction"] = instruction }
        let path = "/apps/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)/run"
        return result(try await request(path, method: "POST", body: body))
    }

    func improve(_ text: String, goal: String? = nil) async throws -> EzyRunResult {
        var body: [String: Any] = ["prompt": text]
        if let goal { body["goal"] = goal }
        return result(try await request("/prompt/improve", method: "POST", body: body))
    }

    func brainstorm(_ topic: String) async throws -> EzyRunResult {
        result(try await request("/prompt/brainstorm", method: "POST", body: ["topic": topic]))
    }

    // Wallet

    func refreshWallet() async {
        guard isConnected, let r = try? await request("/wallet") else { return }
        wallet = decode(EzyWallet.self, r)
    }

    func topUp(_ pack: String) async {
        let fallback = "\(EzyConfig.site)/credits?pack=\(pack)"
        let link = (try? await request("/wallet/topup", method: "POST", body: ["pack_id": pack]))?["checkout_url"] as? String ?? fallback
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    // Shortcuts shared with ezyourlife.com (browser extension, Speedy Notebook)

    func pullShortcuts() async throws -> [(key: String, value: String, category: String?)] {
        let r = try await request("/shortcuts")
        let list = r["shortcuts"] as? [[String: Any]] ?? []
        return list.compactMap { s in
            guard let k = s["key"] as? String, let v = s["value"] as? String else { return nil }
            return (k, v, s["category"] as? String)
        }
    }

    func pushShortcuts(_ items: [(key: String, value: String, category: String)]) async throws -> Int {
        let payload = items.map { ["key": $0.key, "value": $0.value, "category": $0.category] }
        let r = try await request("/shortcuts", method: "PUT", body: ["shortcuts": payload])
        return r["total"] as? Int ?? items.count
    }
}

// MARK: - Pasting into the app you were using

@MainActor enum EzyPaste {
    static func paste(_ text: String, into app: NSRunningApplication?, removeCount: Int) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        guard let app, AXIsProcessTrusted() else { return }
        app.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            let source = CGEventSource(stateID: .hidSystemState)
            for _ in 0..<min(max(0, removeCount), 80) {
                CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Delete), keyDown: true)?.post(tap: .cghidEventTap)
                CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Delete), keyDown: false)?.post(tap: .cghidEventTap)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let down = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true)
                down?.flags = .maskCommand
                down?.post(tap: .cghidEventTap)
                let up = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
                up?.flags = .maskCommand
                up?.post(tap: .cghidEventTap)
            }
        }
    }
}

// MARK: - Run model (shared by the picker panel, the Ask bar and the Apps tab)

@MainActor final class EzyRunModel: ObservableObject {
    enum Phase { case ask, app }
    @Published var phase: Phase = .ask
    @Published var question = ""
    @Published var matches: [EzyApp] = []
    @Published var detail: EzyAppDetail?
    @Published var values: [String: String] = [:]
    @Published var fixed: Set<String> = []
    @Published var chatText = ""
    @Published var output = ""
    @Published var imageDataURL: String?
    @Published var busy = false
    @Published var message = ""
    @Published var topupURL: String?
    @Published var refineText = ""
    @Published var filledNote = ""
    @Published var variant = ""
    @Published var style = ""
    @Published var aspect = ""
    var template = ""
    var request = ""
    let api = Ezyourlife.shared

    func reset() {
        phase = .ask; question = ""; matches = []; detail = nil; values = [:]; fixed = []; output = ""; imageDataURL = nil
        message = ""; topupURL = nil; refineText = ""; template = ""; request = ""; chatText = ""; variant = ""; style = ""; aspect = ""; filledNote = ""
    }

    func findApps() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { matches = []; return }
        let local = api.rank(q, limit: 6)
        if !local.isEmpty { matches = local }
        let remote = await api.search(q)
        if !remote.isEmpty { matches = Array(remote.prefix(6)) }
        if matches.isEmpty { message = "No app matched. Try other words, or Brainstorm." } else { message = "" }
    }

    func open(_ appID: String, values preset: [String: String] = [:], template: String = "", request: String = "") async {
        busy = true; message = ""; output = ""; imageDataURL = nil
        defer { busy = false }
        do {
            let d = try await api.detail(appID)
            detail = d
            await api.refreshProfile()
            let last = api.lastValues(appID)
            var v = [String: String]()
            var fromProfile = [String]()
            for f in d.fields ?? [] {
                if let def = f.default { v[f.key] = def }
                if let saved = last[f.key], !saved.isEmpty { v[f.key] = saved }
                if let pk = f.profile, let known = api.profile[pk], !known.isEmpty { v[f.key] = known; fromProfile.append(f.label) }
            }
            for (k, val) in preset { v[k] = val }
            filledNote = fromProfile.isEmpty ? "" : "Filled from your Ezyourlife profile: " + fromProfile.joined(separator: ", ")
            values = v
            fixed = Set(preset.filter { !$0.value.isEmpty }.map { $0.key })
            self.template = template
            self.request = request
            variant = d.variants?.first ?? ""
            style = d.styles?.first ?? ""
            aspect = d.aspects?.first ?? ""
            phase = .app
        } catch {
            message = error.localizedDescription
        }
    }

    var missingRequired: [String] {
        (detail?.fields ?? []).filter { ($0.required ?? false) && (values[$0.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.map { $0.label }
    }

    func runApp() async {
        guard let d = detail else { return }
        guard api.isConnected else { message = EzyError.notConnected.localizedDescription; return }
        busy = true; message = ""; topupURL = nil
        defer { busy = false }
        do {
            var inputs = values
            if !request.isEmpty { inputs["What I need"] = request }
            let r: EzyRunResult
            switch d.mode {
            case "chat":
                r = try await api.run(d.id, inputs: [:], messages: [["role": "user", "content": chatText.isEmpty ? request : chatText]])
            case "image":
                r = try await api.run(d.id, inputs: [:], prompt: chatText.isEmpty ? request : chatText, style: style.isEmpty ? nil : style, aspect: aspect.isEmpty ? nil : aspect)
            case "studio":
                r = try await api.run(d.id, inputs: inputs, variant: variant.isEmpty ? nil : variant)
            default:
                r = try await api.run(d.id, inputs: inputs)
            }
            output = r.text
            imageDataURL = r.imageDataURL
            api.rememberValues(d.id, values, fields: d.fields ?? [])
            message = "\(ezyCredits(r.credits)) used" + (r.balance.map { " · \($0) left" } ?? "")
        } catch let EzyError.server(_, msg, topup) {
            message = msg; topupURL = topup
        } catch {
            message = error.localizedDescription
        }
    }

    func refine() async {
        guard let d = detail, !output.isEmpty, !refineText.isEmpty else { return }
        busy = true; defer { busy = false }
        do {
            let r = try await api.run(d.id, inputs: values, previous: output, instruction: refineText)
            output = r.text; refineText = ""
            message = "\(ezyCredits(r.credits)) used" + (r.balance.map { " · \($0) left" } ?? "")
        } catch { message = error.localizedDescription }
    }

    func prompt(brainstorm: Bool) async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { message = "Write something first."; return }
        guard api.isConnected else { message = EzyError.notConnected.localizedDescription; return }
        busy = true; message = ""; defer { busy = false }
        do {
            let r = brainstorm ? try await api.brainstorm(text) : try await api.improve(text)
            output = r.text
            message = "PromptMaster · \(ezyCredits(r.credits)) used" + (r.balance.map { " · \($0) left" } ?? "")
        } catch let EzyError.server(_, msg, topup) { message = msg; topupURL = topup } catch { message = error.localizedDescription }
    }

    /// The text to paste: the shortcut's own words around the result.
    var finalText: String {
        guard !template.isEmpty else { return output }
        if template.contains(EzyConfig.resultMarker) { return template.replacingOccurrences(of: EzyConfig.resultMarker, with: output) }
        return template + "\n\n" + output
    }

    /// A shortcut that reruns this app: boxes you filled stay fixed, empty ones are asked each time.
    func shortcutClip() -> Clip? {
        guard let d = detail else { return nil }
        let slug = d.name.lowercased().split { !($0.isLetter || $0.isNumber) }.prefix(3).map { String($0.prefix(5)) }.joined()
        let keep = values.filter { fixed.contains($0.key) && !$0.value.isEmpty }
        return Clip(key: "/" + (slug.isEmpty ? "ezyapp" : slug), name: d.name, text: template.isEmpty ? EzyConfig.resultMarker : template,
                    group: EzyConfig.collection, webURL: EzyLink.url(appID: d.id, values: keep))
    }
}

// MARK: - Shared views

struct EzyFieldsForm: View {
    @ObservedObject var model: EzyRunModel
    var allowFixing = true
    @StateObject private var guide = EzyVoiceGuide()
    @FocusState private var focusedKey: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.detail != nil { EzyVoiceBar(guide: guide, voice: guide.voice) }
            if let d = model.detail {
                switch d.mode {
                case "chat", "image":
                    Text(d.mode == "image" ? (d.prompt_label ?? "Describe the picture") : "Your question").font(.system(size: 12, weight: .bold)).foregroundStyle(EzyColor.muted)
                    TextEditor(text: $model.chatText).font(.system(size: 14)).frame(minHeight: 70).padding(6).ezyBlock(.white, radius: 10, shadow: 0)
                    if d.mode == "image" {
                        HStack {
                            if let styles = d.styles, !styles.isEmpty { Picker("Style", selection: $model.style) { ForEach(styles, id: \.self) { Text($0).tag($0) } } }
                            if let aspects = d.aspects, !aspects.isEmpty { Picker("Shape", selection: $model.aspect) { ForEach(aspects, id: \.self) { Text($0).tag($0) } } }
                        }
                    }
                default:
                    if d.mode == "studio", let variants = d.variants, !variants.isEmpty {
                        Picker("Picture", selection: $model.variant) { ForEach(variants, id: \.self) { Text($0).tag($0) } }
                    }
                    if d.mode == "document" {
                        Text("Paste the text of your document in the first box, or describe it.").font(.caption).foregroundStyle(EzyColor.muted)
                    }
                    ForEach(d.fields ?? []) { f in fieldRow(f) }
                    if (d.fields ?? []).isEmpty {
                        Text("Tell the app what you need").font(.system(size: 12, weight: .bold)).foregroundStyle(EzyColor.muted)
                        TextEditor(text: Binding(get: { model.values["What I need"] ?? model.request }, set: { model.values["What I need"] = $0 }))
                            .font(.system(size: 14)).frame(minHeight: 70).padding(6).ezyBlock(.white, radius: 10, shadow: 0)
                    }
                }
            }
        }
        .onAppear { guide.model = model }
        .onDisappear { guide.stop() }
        .onChange(of: model.detail?.name) { _ in guide.stop() }
        // Where you click or press Tab, voice follows; where voice moves, the cursor follows.
        .onChange(of: focusedKey) { key in if let key { guide.select(key) } }
        .onChange(of: guide.index) { _ in
            if guide.active, let key = guide.current?.key, focusedKey != key { focusedKey = key }
        }
    }

    @ViewBuilder func fieldRow(_ f: EzyField) -> some View {
        let binding = Binding(get: { model.values[f.key] ?? "" }, set: { model.values[f.key] = $0 })
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(f.label + ((f.required ?? false) ? " *" : "")).font(.system(size: 12, weight: .bold)).foregroundStyle(EzyColor.muted)
                Spacer()
                if allowFixing {
                    HStack(spacing: 4) {
                        Image(systemName: model.fixed.contains(f.key) ? "pin.fill" : "pin").font(.system(size: 10)).foregroundStyle(EzyColor.muted)
                        Toggle("", isOn: Binding(get: { model.fixed.contains(f.key) }, set: { on in if on { model.fixed.insert(f.key) } else { model.fixed.remove(f.key) } }))
                            .toggleStyle(.checkbox).labelsHidden().fixedSize()
                    }
                    .help("Keep in KeyDo shortcut: when you save this as a shortcut, this box keeps its value. Other boxes are asked each time.")
                }
            }
            if let options = f.options, !options.isEmpty, f.type == "select" {
                Picker("", selection: binding) { Text("Choose…").tag(""); ForEach(options, id: \.self) { Text($0).tag($0) } }.labelsHidden()
            } else if f.type == "textarea" || f.type == "rows" {
                TextEditor(text: binding).font(.system(size: 13)).frame(minHeight: 54).padding(4).ezyBlock(.white, radius: 10, shadow: 0)
                    .focused($focusedKey, equals: f.key)
            } else {
                TextField(f.placeholder ?? "", text: binding).textFieldStyle(.roundedBorder)
                    .focused($focusedKey, equals: f.key)
            }
            if let help = f.help { Text(help).font(.system(size: 11)).foregroundStyle(EzyColor.muted) }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { guide.select(f.key) })
        .padding(guide.active && guide.current?.key == f.key ? 6 : 0)
        .background(RoundedRectangle(cornerRadius: 10).fill(guide.active && guide.current?.key == f.key ? EzyColor.sun.opacity(0.28) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(guide.active && guide.current?.key == f.key ? EzyColor.ink : Color.clear, lineWidth: 2))
    }
}

struct EzyConnectCard: View {
    @ObservedObject var api = Ezyourlife.shared
    @State private var manualKey = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect your Ezyourlife account").font(.system(size: 16, weight: .bold))
            Text("Use Ezyourlife apps, PromptMaster and your shortcuts in KeyDo. Runs use the same credits as ezyourlife.com, only when an app gives a result.")
                .font(.system(size: 13)).foregroundStyle(EzyColor.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(api.isConnecting ? "Opening…" : "Connect Ezyourlife") { api.connect() }.buttonStyle(EzyButtonStyle()).disabled(api.isConnecting)
                Text("or paste a key:").font(.caption).foregroundStyle(EzyColor.muted)
                SecureField("ezy_live_…", text: $manualKey).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Button("Use key") { api.useKey(manualKey); manualKey = "" }.disabled(manualKey.isEmpty)
            }
            if !api.status.isEmpty { Text(api.status).font(.caption).foregroundStyle(EzyColor.muted) }
        }
        .padding(16).ezyBlock(EzyColor.sun, radius: 16, shadow: 4)
    }
}

struct EzyResultView: View {
    @ObservedObject var model: EzyRunModel
    var onPaste: (() -> Void)?
    var onSave: ((Clip) -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let img = model.imageDataURL, let data = Data(base64Encoded: String(img.split(separator: ",").last ?? "")), let ns = NSImage(data: data) {
                Image(nsImage: ns).resizable().scaledToFit().frame(maxHeight: 260).ezyBlock(.white, radius: 10, shadow: 0)
            }
            if !model.output.isEmpty {
                Text("Result").font(.system(size: 11, weight: .bold)).foregroundStyle(EzyColor.muted)
                ScrollView { Text(model.output).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10) }
                    .frame(minHeight: 120, maxHeight: 320).ezyBlock(.white, radius: 10, shadow: 0)
                HStack(spacing: 8) {
                    if let onPaste { Button("Paste") { onPaste() }.buttonStyle(EzyButtonStyle()) }
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.finalText, forType: .string) }.buttonStyle(EzyButtonStyle(fill: .white))
                    if let onSave, model.detail != nil {
                        Button("Save as shortcut") { if let c = model.shortcutClip() { onSave(c) } }.buttonStyle(EzyButtonStyle(fill: .white))
                    }
                }
                if model.detail != nil {
                    HStack {
                        TextField("Change something: shorter, in Hindi, add a discount…", text: $model.refineText).textFieldStyle(.roundedBorder)
                        Button("Refine") { Task { await model.refine() } }.disabled(model.refineText.isEmpty || model.busy)
                    }
                }
            }
            if !model.message.isEmpty || model.busy {
                HStack {
                    if model.busy { ProgressView().controlSize(.small) }
                    Text(model.message).font(.system(size: 12)).foregroundStyle(EzyColor.muted)
                    if let t = model.topupURL, let url = URL(string: t) { Button("Top up") { NSWorkspace.shared.open(url) } }
                }
            }
        }
    }
}

// MARK: - Floating run panel (picker apps, smart shortcuts, Ask bar)

struct EzyRunPanelView: View {
    @ObservedObject var model: EzyRunModel
    @ObservedObject var api = Ezyourlife.shared
    var close: () -> Void
    var paste: () -> Void
    var runAndPaste: () -> Void = {}
    var save: (Clip) -> Void
    @FocusState private var askFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack { Circle().fill(EzyColor.sun).frame(width: 26, height: 26); Circle().fill(EzyColor.pink).frame(width: 14, height: 14).overlay(Circle().stroke(EzyColor.ink, lineWidth: 2)) }
                    .overlay(Circle().stroke(EzyColor.ink, lineWidth: 2))
                if model.phase == .ask {
                    TextField("Say what you need: a rent agreement for my shop, a reply to this review…", text: $model.question)
                        .textFieldStyle(.plain).font(.system(size: 17, weight: .semibold)).focused($askFocused)
                        .onSubmit { Task { await model.findApps() } }
                } else if let d = model.detail {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name).font(.system(size: 16, weight: .bold))
                        Text(d.intro ?? d.description).font(.system(size: 12)).foregroundStyle(EzyColor.muted).lineLimit(2)
                    }
                    Spacer()
                    EzyBadge(text: ezyCredits(d.credits))
                }
                Spacer(minLength: 0)
                if model.phase == .app { Button("Back") { model.phase = .ask; model.output = "" }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)) }
                Button { close() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)) }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            if !api.isConnected { EzyConnectCard() }
            if model.phase == .ask {
                askBody
            } else {
                ScrollView { EzyFieldsForm(model: model).padding(2) }.frame(maxHeight: 300)
                if !model.filledNote.isEmpty { Text(model.filledNote).font(.system(size: 11, weight: .semibold)).foregroundStyle(EzyColor.muted) }
                HStack {
                    Button(model.busy ? "Working…" : "Run and paste · \(ezyCredits(model.detail?.credits))") { runAndPaste() }
                        .buttonStyle(EzyButtonStyle()).disabled(model.busy || !api.isConnected || !model.missingRequired.isEmpty).keyboardShortcut(.defaultAction)
                    Button("Preview first") { Task { await model.runApp() } }
                        .buttonStyle(EzyButtonStyle(fill: .white)).disabled(model.busy || !api.isConnected)
                    if !model.missingRequired.isEmpty { Text("Not filled: \(model.missingRequired.joined(separator: ", "))").font(.caption).foregroundStyle(EzyColor.muted).lineLimit(1) }
                    Spacer()
                    if let w = api.wallet { Text("\(w.balance) credits").font(.system(size: 12, weight: .semibold)) }
                }
            }
            EzyResultView(model: model, onPaste: paste, onSave: model.detail == nil ? nil : save)
        }
        .padding(16)
        .frame(width: 640)
        .background(EzyColor.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(EzyColor.ink, lineWidth: 2))
        .onAppear { if model.phase == .ask { askFocused = true }; Task { await api.refreshCatalogue(); await api.refreshWallet() } }
    }

    var askBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.matches.isEmpty {
                Text(model.matches.count == 1 ? "Best match" : "Matching apps").font(.system(size: 11, weight: .bold)).foregroundStyle(EzyColor.muted)
                ForEach(Array(model.matches.enumerated()), id: \.element.id) { index, app in
                    Button {
                        Task { await model.open(app.id, request: model.question) }
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 8).fill(EzyColor.goal(app.goal_color)).frame(width: 24, height: 24).overlay(RoundedRectangle(cornerRadius: 8).stroke(EzyColor.ink, lineWidth: 2))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name).font(.system(size: 14, weight: .semibold))
                                Text(app.description).font(.system(size: 12)).foregroundStyle(EzyColor.muted).lineLimit(1)
                            }
                            Spacer()
                            EzyBadge(text: ezyCredits(app.credits))
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(index == 0 ? Color.white : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(index == 0 ? EzyColor.ink : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Button("Find apps") { Task { await model.findApps() } }.buttonStyle(EzyButtonStyle(fill: .white))
                Button("Brainstorm ideas") { Task { await model.prompt(brainstorm: true) } }.buttonStyle(EzyButtonStyle(fill: EzyColor.lime))
                Button("Improve my words") { Task { await model.prompt(brainstorm: false) } }.buttonStyle(EzyButtonStyle(fill: EzyColor.lime))
                Spacer()
                Text("PromptMaster · 2 credits").font(.caption).foregroundStyle(EzyColor.muted)
            }
        }
    }
}

@MainActor final class EzyRunPanel: NSObject, NSWindowDelegate {
    static let shared = EzyRunPanel()
    let model = EzyRunModel()
    private var panel: NSPanel?
    private var returnApp: NSRunningApplication?
    private var removeCount = 0
    /// Set by MainView so a saved shortcut lands in the library.
    var saveShortcut: ((Clip) -> Void)?

    /// From the backslash picker or a smart shortcut.
    func open(clip: Clip, removeCount: Int, returnApp: NSRunningApplication?) {
        guard let link = EzyLink.parse(clip.webURL) else { return }
        let template = clip.text == EzyConfig.resultMarker ? "" : clip.text
        let isCatalogueHit = clip.group == EzyConfig.collection && clip.key.hasPrefix("/ezy-")
        present(returnApp: returnApp, removeCount: removeCount)
        model.reset()
        Task { await model.open(link.appID, values: link.values, template: isCatalogueHit ? "" : template) }
    }

    /// A plain-words question from the search popup: shows the best Ezyourlife apps for it.
    func ask(_ question: String, removeCount: Int, returnApp: NSRunningApplication?) {
        present(returnApp: returnApp, removeCount: removeCount)
        model.reset()
        model.question = question
        Task { await model.findApps() }
    }

    /// The Ask bar (Option-Space).
    func openAsk() {
        let front = NSWorkspace.shared.frontmostApplication
        present(returnApp: front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front, removeCount: 0)
        model.reset()
    }

    private func present(returnApp: NSRunningApplication?, removeCount: Int) {
        self.returnApp = returnApp
        self.removeCount = removeCount
        if panel == nil {
            let p = EzMeKeyablePickerWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.isMovableByWindowBackground = true
            p.delegate = self
            let view = EzyRunPanelView(model: model, close: { [weak self] in self?.hide() }, paste: { [weak self] in self?.pasteResult() },
                                       runAndPaste: { [weak self] in self?.runAndPaste() },
                                       save: { [weak self] clip in self?.saveShortcut?(clip); self?.model.message = "Saved as \(displayTrigger(clip.key))" })
            let host = NSHostingView(rootView: view.ezyLight())
            host.sizingOptions = [.preferredContentSize]
            p.contentView = host
            panel = p
        }
        guard let p = panel else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        p.setFrameOrigin(NSPoint(x: visible.midX - 320, y: visible.maxY - 580))
        p.makeKeyAndOrderFront(nil)
    }

    func pasteResult() {
        let text = model.finalText
        guard !text.isEmpty else { return }
        saveResultToLibrary(text)
        let app = returnApp, count = removeCount
        hide()
        EzyPaste.paste(text, into: app, removeCount: count)
    }

    /// One click: run the app, then paste its answer where the person was typing.
    func runAndPaste() {
        Task {
            await model.runApp()
            if !model.output.isEmpty { pasteResult() }
        }
    }

    /// Every pasted answer is kept as a shortcut in "Ezyourlife results", so it syncs to the cloud with the rest of the library.
    private func saveResultToLibrary(_ text: String) {
        guard let d = model.detail, model.imageDataURL == nil else { return }
        let stamp = DateFormatter(); stamp.dateFormat = "yyMMdd-HHmmss"
        let nice = DateFormatter(); nice.dateFormat = "d MMM, h:mm a"
        let key = "/ezr-" + d.id + "-" + stamp.string(from: Date())
        let clip = Clip(key: key, name: "\(d.name) · \(nice.string(from: Date()))", text: text, group: "Ezyourlife results")
        saveShortcut?(clip)
    }

    func hide() { panel?.orderOut(nil) }
}

// MARK: - Ask bar hot key (Option-Space)

enum EzyHotKey {
    private static var ref: EventHotKeyRef?
    private static var handler: EventHandlerRef?
    static var enabled: Bool { UserDefaults.standard.object(forKey: "ezyAskBarHotKey") as? Bool ?? true }

    @MainActor static func install() {
        guard ref == nil, enabled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { EzyRunPanel.shared.openAsk() }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x455A_5931), id: 1) // "EZY1"
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }

    @MainActor static func uninstall() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}

// MARK: - Apps tab (design 2)

struct EzyAppsView: View {
    @ObservedObject var api = Ezyourlife.shared
    @StateObject private var model = EzyRunModel()
    var onSaveShortcut: (Clip) -> Void
    @State private var query = ""
    @State private var category = ""
    @State private var selected: String?
    @ObservedObject private var look = EzyLook.shared
    @State private var lookSheet: EzyHomeSheet?
    @State private var lookNote = ""

    var shown: [EzyApp] {
        var list = api.catalogue.filter { $0.runnable }
        if !category.isEmpty { list = list.filter { $0.category == category } }
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { list = api.rank(query, limit: 300) .filter { category.isEmpty || $0.category == category } }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ezyourlife apps").font(.system(size: 26, weight: .heavy))
                    Text("\(api.catalogue.filter { $0.runnable }.count) apps you can run from KeyDo. Pick one, fill the boxes, and paste or save the result.")
                        .font(.system(size: 13)).foregroundStyle(EzyColor.muted)
                }
                Spacer()
                if let w = api.wallet { EzyBadge(text: "\(w.balance) credits", fill: EzyColor.lime) }
                Button("Refresh") { Task { await api.refreshCatalogue(force: true); await api.refreshWallet() } }
            }
            if !api.isConnected { EzyConnectCard() }
            TextField("Search apps: letter, invoice, photo, post, rent…", text: $query).textFieldStyle(.roundedBorder).font(.system(size: 14))
            HStack(spacing: 6) {
                Image(systemName: "ellipsis.circle").foregroundStyle(EzyColor.muted)
                Text(lookNote.isEmpty ? "Click an app to open it. Use the ··· on a card to add a cover picture, GIF or video, or change its icon." : lookNote)
                    .font(.system(size: 11)).foregroundStyle(EzyColor.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("All", color: EzyColor.ink, on: category.isEmpty) { category = "" }
                    ForEach(api.categories, id: \.self) { c in chip(c.name, color: EzyColor.goal(c.goal_color), on: category == c.name) { category = c.name } }
                }
            }
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 236, maximum: 300), spacing: 16)], spacing: 16) {
                        ForEach(shown) { app in card(app) }
                    }.padding(4)
                }
                if model.detail != nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let d = model.detail {
                                Text(d.name).font(.system(size: 18, weight: .bold))
                                Text(d.intro ?? d.description).font(.system(size: 13)).foregroundStyle(EzyColor.muted)
                            }
                            EzyFieldsForm(model: model)
                            Button(model.busy ? "Working…" : "\(model.detail?.cta ?? "Make it") · \(ezyCredits(model.detail?.credits))") { Task { await model.runApp() } }
                                .buttonStyle(EzyButtonStyle()).disabled(model.busy || !api.isConnected)
                            EzyResultView(model: model, onPaste: nil, onSave: { clip in onSaveShortcut(clip); model.message = "Saved as \(displayTrigger(clip.key)). Type it anywhere to run this app." })
                        }.padding(14)
                    }
                    .frame(width: 380)
                    .ezyBlock(EzyColor.cream, radius: 16, shadow: 4)
                }
            }
            if api.catalogue.isEmpty { HStack { ProgressView().controlSize(.small); Text("Loading apps from ezyourlife.com…").foregroundStyle(EzyColor.muted) } }
        }
        .task { await api.refreshCatalogue(); await api.refreshWallet() }
        .onReceive(NotificationCenter.default.publisher(for: .ezmeBuilderIconChanged)) { _ in look.revision += 1 }
        .sheet(item: $lookSheet) { sheet in
            switch sheet {
            case .icon(let app):
                AppIconGallerySheet(appName: app.name, selected: look.selectedSymbol(app.id).isEmpty ? automaticAppIcon(app.name) : look.selectedSymbol(app.id)) { symbol in
                    look.setSymbol(app.id, symbol); lookNote = "Icon updated for \(app.name)."
                }
            case .crop(let app):
                EzCoverFramingSheet(app: EzyLook.framingName(app.id), path: look.coverPath(app.id))
            }
        }
    }

    func chip(_ title: String, color: Color, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(on && color == EzyColor.ink ? EzyColor.cream : EzyColor.ink)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(on ? color : color.opacity(color == EzyColor.ink ? 0.0 : 0.35)))
                .overlay(Capsule().stroke(EzyColor.ink, lineWidth: on ? 2 : 1))
        }.buttonStyle(.plain)
    }

    func card(_ app: EzyApp) -> some View {
        let _ = look.revision
        let tint = EzyColor.goal(app.goal_color)
        return AppGalleryCard(
            title: app.name,
            description: app.description,
            sample: "",
            category: app.category,
            icon: look.symbol(app.id, name: app.name),
            iconPath: look.iconPath(app.id),
            coverPath: look.coverPath(app.id),
            credits: String(app.credits ?? 1),
            colors: [tint, tint.opacity(0.62)],
            action: {
                selected = app.id
                Task { await model.open(app.id) }
            },
            coverFraming: EzCoverFraming.load(EzyLook.framingName(app.id)),
            showsCredits: true,
            badge: "EZYOURLIFE"
        )
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected == app.id ? Butter.coral : Color.clear, lineWidth: 3))
        .overlay(alignment: .topTrailing) {
            EzyLookMenu(app: app, look: look, sheet: $lookSheet, note: $lookNote).padding(10)
        }
    }
}

// MARK: - Credits, connection and shared shortcuts (design 4)

struct EzyCreditsView: View {
    @ObservedObject var api = Ezyourlife.shared
    var exportShortcuts: () -> [(key: String, value: String, category: String)]
    var importShortcuts: ([(key: String, value: String, category: String?)]) -> Int
    @State private var syncStatus = ""
    @AppStorage("ezyAskBarHotKey") private var hotKey = true
    @AppStorage("ezyShowInPicker") private var showInPicker = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ezyourlife credits").font(.system(size: 26, weight: .heavy))
            if !api.isConnected {
                EzyConnectCard()
            } else {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let w = api.wallet {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(w.balance)").font(.system(size: 40, weight: .heavy))
                                Text("credits, the same as on ezyourlife.com").foregroundStyle(EzyColor.muted)
                            }
                            HStack { EzyBadge(text: "Free \(w.free)", fill: EzyColor.lime); EzyBadge(text: "Bought \(w.paid)", fill: EzyColor.sand) }
                            Text("Used only when an app gives a result. Failed runs are never charged.").font(.system(size: 12)).foregroundStyle(EzyColor.muted)
                            Text("Top up").font(.system(size: 11, weight: .bold)).foregroundStyle(EzyColor.muted).padding(.top, 6)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                                ForEach(w.packs) { p in
                                    Button { Task { await api.topUp(p.id) } } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("₹\(p.inr)").font(.system(size: 16, weight: .bold))
                                            Text("\(p.credits) credits").font(.system(size: 12))
                                        }.foregroundStyle(EzyColor.ink).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                        .ezyBlock(p.id == "p250" ? EzyColor.sun : .white, radius: 12, shadow: 3)
                                    }.buttonStyle(.plain)
                                }
                            }
                            Text("Pays with Razorpay on ezyourlife.com in your browser. Credits show here when you come back.").font(.caption).foregroundStyle(EzyColor.muted)
                        } else {
                            HStack { ProgressView().controlSize(.small); Text("Loading your credits…") }
                        }
                    }
                    .padding(16).frame(maxWidth: 420, alignment: .leading).ezyBlock(.white, radius: 16, shadow: 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent charges").font(.system(size: 14, weight: .bold))
                        if let rows = api.wallet?.recent, !rows.isEmpty {
                            ForEach(Array(rows.prefix(12).enumerated()), id: \.offset) { _, r in
                                HStack {
                                    Text(r.tool_id ?? r.reason ?? "Credits").font(.system(size: 12)).lineLimit(1)
                                    Spacer()
                                    Text(r.delta > 0 ? "+\(r.delta)" : "\(r.delta)").font(.system(size: 12, weight: .semibold)).foregroundStyle(r.delta > 0 ? .green : EzyColor.ink)
                                }
                            }
                        } else { Text("Nothing yet.").font(.caption).foregroundStyle(EzyColor.muted) }
                    }
                    .padding(16).frame(maxWidth: 320, alignment: .leading).ezyBlock(EzyColor.cream, radius: 16, shadow: 4)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Shortcuts on ezyourlife.com").font(.system(size: 16, weight: .bold))
                Text("Your ezyourlife.com shortcuts (browser extension and Speedy Notebook) and your KeyDo text shortcuts can be one list.")
                    .font(.system(size: 13)).foregroundStyle(EzyColor.muted)
                HStack {
                    Button("Bring them into KeyDo") {
                        Task {
                            do { let n = importShortcuts(try await api.pullShortcuts()); syncStatus = "Added or updated \(n) shortcuts in the \"Ezyourlife\" collection." }
                            catch { syncStatus = error.localizedDescription }
                        }
                    }.buttonStyle(EzyButtonStyle(fill: .white))
                    Button("Send my KeyDo shortcuts there") {
                        Task {
                            do { let n = try await api.pushShortcuts(exportShortcuts()); syncStatus = "Ezyourlife now has \(n) shortcuts." }
                            catch { syncStatus = error.localizedDescription }
                        }
                    }.buttonStyle(EzyButtonStyle(fill: .white))
                }.disabled(!api.isConnected)
                if !syncStatus.isEmpty { Text(syncStatus).font(.caption).foregroundStyle(EzyColor.muted) }
            }
            .padding(16).ezyBlock(.white, radius: 16, shadow: 3)

            VStack(alignment: .leading, spacing: 8) {
                Text("How KeyDo uses Ezyourlife").font(.system(size: 16, weight: .bold))
                Toggle("Show matching Ezyourlife apps in the \\ picker", isOn: $showInPicker)
                Toggle("Option-Space opens the Ask bar", isOn: $hotKey)
                    .onChange(of: hotKey) { on in if on { EzyHotKey.install() } else { EzyHotKey.uninstall() } }
                Text("Smart shortcuts: save any app as a shortcut. Boxes you tick \"Keep in shortcut\" stay filled; the rest are asked each time. Put [[result]] in the shortcut's text to add your own words before or after the result.")
                    .font(.system(size: 12)).foregroundStyle(EzyColor.muted).fixedSize(horizontal: false, vertical: true)
                HStack {
                    if api.isConnected { Button("Disconnect") { api.disconnect() } }
                    Button("Manage keys on ezyourlife.com") { if let u = URL(string: "\(EzyConfig.site)/developers/keys") { NSWorkspace.shared.open(u) } }
                }
                if !api.status.isEmpty { Text(api.status).font(.caption).foregroundStyle(EzyColor.muted) }
            }
            .padding(16).ezyBlock(EzyColor.cream, radius: 16, shadow: 3)
        }
        .task { await api.refreshWallet() }
    }
}

final class EzyAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}
