// Scans the page open in the browser and proposes a clear name and an easy-to-remember shortcut for its link.
import SwiftUI
import WebKit
import Vision

extension Notification.Name {
    static let keydoSaveWebShortcut = Notification.Name("KeyDoSaveWebShortcut")
}

struct PageScan {
    var title = ""
    var siteName = ""
    var heading = ""
    var summary = ""
    var host = ""
    var path = ""
    /// Words read from pictures on the page (banners, buttons, logos), biggest first.
    var imageText: [String] = []
}

enum PageScanner {
    private static let script = """
    (function(){
      function meta(n){var e=document.querySelector('meta[property="'+n+'"],meta[name="'+n+'"]');return e?(e.content||''):'';}
      var h=document.querySelector('h1');
      return JSON.stringify({title:document.title||'',siteName:meta('og:site_name'),ogTitle:meta('og:title'),heading:h?(h.innerText||'').trim():'',summary:(meta('og:description')||meta('description')||'').slice(0,300),host:location.hostname,path:location.pathname});
    })()
    """

    @MainActor
    static func scan(_ view: WKWebView?, fallbackURL: String, completion: @escaping (PageScan) -> Void) {
        let fallbackHost = URL(string: fallbackURL)?.host ?? ""
        guard let view else { completion(PageScan(host: fallbackHost)); return }
        view.evaluateJavaScript(script) { value, _ in
            var scan = PageScan(host: fallbackHost)
            if let text = value as? String, let data = text.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                scan.title = (object["ogTitle"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (object["title"] as? String ?? "")
                scan.siteName = object["siteName"] as? String ?? ""
                scan.heading = object["heading"] as? String ?? ""
                scan.summary = object["summary"] as? String ?? ""
                scan.host = (object["host"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackHost
                scan.path = object["path"] as? String ?? ""
            }
            let base = scan
            readImages(from: view) { lines in
                var result = base
                result.imageText = lines
                completion(result)
            }
        }
    }

    /// Reads the text that is drawn inside images on the visible part of the page. The biggest text comes first,
    /// because that is usually the name on a banner or a logo.
    @MainActor
    private static func readImages(from view: WKWebView, done: @escaping ([String]) -> Void) {
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        view.takeSnapshot(with: configuration) { image, _ in
            guard let image, let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { done([]); return }
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                try? VNImageRequestHandler(cgImage: picture, options: [:]).perform([request])
                var found: [(String, CGFloat)] = []
                for observation in (request.results as? [VNRecognizedTextObservation]) ?? [] {
                    guard let best = observation.topCandidates(1).first, best.confidence >= 0.5 else { continue }
                    let text = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard text.count >= 3, text.contains(where: { $0.isLetter }) else { continue }
                    found.append((text, observation.boundingBox.height))
                }
                var seen = Set<String>()
                let lines = found.sorted { $0.1 > $1.1 }.map { $0.0 }.filter { seen.insert($0.lowercased()).inserted }
                DispatchQueue.main.async { done(Array(lines.prefix(12))) }
            }
        }
    }
}

enum PageNamer {
    private static let stop: Set<String> = ["the", "a", "an", "of", "and", "for", "to", "in", "on", "with", "your", "how", "is", "at", "by", "best", "free", "online", "official", "home", "page", "welcome"]

    /// "Pricing | GitHub" -> "GitHub Pricing", "Inbox (3) - me@mail.com - Gmail" -> "Gmail Inbox".
    static func suggestName(_ scan: PageScan) -> String {
        let site = siteLabel(scan)
        var title = scan.title.isEmpty ? scan.heading : scan.title
        let generic: Set<String> = ["", "home", "homepage", "welcome", "dashboard", "untitled", "login", "log in", "sign in", "index"]
        if generic.contains(title.lowercased().trimmingCharacters(in: .whitespaces)) || title.lowercased() == site.lowercased(),
           let picture = scan.imageText.first(where: { $0.count <= 40 }) {
            title = picture
        }
        let separators = [" | ", " - ", " – ", " — ", " · ", " • ", " :: "]
        var parts = [title]
        for separator in separators where title.contains(separator) {
            parts = title.components(separatedBy: separator); break
        }
        parts = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let siteLower = site.lowercased()
        let topic = parts.first { $0.lowercased() != siteLower && !$0.lowercased().contains(siteLower) && !$0.contains("@") } ?? parts.first ?? ""
        title = topic
        let words = title.split(separator: " ").map(String.init)
        let short = words.prefix(5).joined(separator: " ")
        if short.isEmpty { return site }
        if short.lowercased().contains(siteLower) || site.isEmpty { return String(short.prefix(48)) }
        return String("\(site) \(short)".prefix(48))
    }

    static func siteLabel(_ scan: PageScan) -> String {
        if !scan.siteName.isEmpty { return scan.siteName }
        return hostCore(scan.host).capitalized
    }

    static func hostCore(_ host: String) -> String {
        var parts = host.lowercased().split(separator: ".").map(String.init)
        if parts.first == "www" { parts.removeFirst() }
        if parts.count >= 3, ["co", "com", "org", "gov", "ac"].contains(parts[parts.count - 2]) { return parts[parts.count - 3] }
        if parts.count >= 2 { return parts[parts.count - 2] }
        return parts.first ?? ""
    }

    private static func clean(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Short, typeable and guessable. Offers the site, the site plus the topic, and initials.
    static func suggestShortcuts(_ scan: PageScan) -> [String] {
        let core = clean(hostCore(scan.host))
        let siteKey = core.count <= 9 ? core : String(core.prefix(6))
        var topicWord = ""
        let source = scan.path.split(separator: "/").last.map(String.init) ?? ""
        let pathWords = source.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { String($0).lowercased() }
        if let word = pathWords.first(where: { $0.count > 2 && !stop.contains($0) && Int($0) == nil }) { topicWord = word }
        else if let word = (scan.title.isEmpty ? (scan.heading.isEmpty ? (scan.imageText.first ?? "") : scan.heading) : scan.title).lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).first(where: { $0.count > 2 && !stop.contains($0) && $0 != core }) { topicWord = word }
        var result: [String] = []
        if !siteKey.isEmpty { result.append(siteKey) }
        if !topicWord.isEmpty, !siteKey.isEmpty { result.append(String("\(siteKey)-\(topicWord)".prefix(16))) }
        let initials = String(core.prefix(2)) + String(topicWord.prefix(2))
        if initials.count >= 3, !result.contains(initials) { result.append(initials) }
        var seen = Set<String>()
        return result.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

@MainActor
enum WebShortcutSaver {
    private static var token: NSObjectProtocol?

    /// The browser posts a note when a link is saved with a shortcut; the shortcut store adds it.
    static func listen(_ db: DB) {
        token = NotificationCenter.default.addObserver(forName: .keydoSaveWebShortcut, object: nil, queue: .main) { [weak db] note in
            Task { @MainActor in if let db { save(note, db: db) } }
        }
    }

    /// Adds the page as a Websites & URLs shortcut with a key that is not already used.
    static func save(_ note: Notification, db: DB) {
        guard let info = note.userInfo, let key = info["key"] as? String, let name = info["name"] as? String, let url = info["url"] as? String else { return }
        let base = collectionTrigger(key, collection: "Websites & URLs")
        let used = Set(db.clips.map { $0.key.lowercased() })
        var candidate = base
        var count = 2
        while used.contains(candidate.lowercased()) {
            candidate = collectionTrigger("\(key)\(count)", collection: "Websites & URLs")
            count += 1
        }
        var clip = Clip(key: candidate, name: name, text: url, group: "Websites & URLs")
        clip.webURL = url
        db.clips.append(clip)
    }
}

/// Sits inside the Save link sheet: scan the page, then pick a name and a shortcut.
struct PageScanPanel: View {
    @ObservedObject var state: EzMeBrowserTabs
    @Binding var title: String
    var url: String
    @Binding var shortcut: String
    @Binding var makeShortcut: Bool
    @State private var scanning = false
    @State private var scan: PageScan? = nil
    @State private var names: [String] = []
    @State private var keys: [String] = []

    private func run() {
        scanning = true
        PageScanner.scan(state.webViews[state.selectedID], fallbackURL: url) { result in
            scan = result
            let name = PageNamer.suggestName(result)
            var options = [name]
            let site = PageNamer.siteLabel(result)
            if !site.isEmpty, site != name { options.append(site) }
            if !result.heading.isEmpty, result.heading.count < 48, !options.contains(result.heading) { options.append(result.heading) }
            for line in result.imageText.prefix(4) where line.count <= 40 && !options.contains(line) {
                options.append(site.isEmpty || line.lowercased().contains(site.lowercased()) ? line : "\(site) \(line)")
            }
            names = options
            keys = PageNamer.suggestShortcuts(result)
            title = name
            if shortcut.isEmpty { shortcut = keys.first ?? "" }
            scanning = false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { run() } label: {
                    Label(scanning ? "Scanning…" : "Scan page for a name and shortcut", systemImage: "sparkle.magnifyingglass")
                }.buttonStyle(.bordered).disabled(scanning)
                if let scan, !scan.summary.isEmpty {
                    Text(scan.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let scan, !scan.imageText.isEmpty {
                    Label("Read \(scan.imageText.count) text lines from pictures", systemImage: "text.viewfinder").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !names.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(names, id: \.self) { item in Button(item) { title = item }.buttonStyle(.bordered).controlSize(.small) } }
                }
            }
            Toggle(isOn: $makeShortcut) {
                Text("Also make a KeyDo shortcut for this link").font(.system(size: 12, weight: .medium))
            }.toggleStyle(.switch).controlSize(.small)
            if makeShortcut {
                HStack(spacing: 8) {
                    Text("\\").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                    TextField("shortcut, e.g. github", text: $shortcut).textFieldStyle(.roundedBorder)
                    Text(".web").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                }
                if !keys.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(keys, id: \.self) { item in Button(item) { shortcut = item }.buttonStyle(.bordered).controlSize(.small) } }
                    }
                }
            }
        }
        .onAppear { if scan == nil { run() } }
    }
}
