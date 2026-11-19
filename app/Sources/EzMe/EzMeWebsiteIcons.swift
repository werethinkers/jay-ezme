// Website icons for every link in KeyDo: downloaded once, stored on this Mac, and shown from the stored copy afterwards.
// Browser tabs, saved sites, the Favorites home page, links in MyDatabase, shortcuts and search results all use it.
import SwiftUI
import AppKit

/// Downloads and keeps the icons. The files live in the same folder the browser tabs use (SiteIconCache).
@MainActor
final class SiteIconStore: ObservableObject {
    static let shared = SiteIconStore()

    /// Goes up whenever a new icon has been stored, so every icon on screen refreshes.
    @Published private(set) var version = 0
    private var inFlight = Set<String>()
    private var failedAt: [String: Date] = [:]
    private var queue: [String] = []
    private var running = 0

    func image(for urlString: String) -> NSImage? { SiteIconCache.lookup(urlString) }

    /// A small copy for menus.
    func menuImage(for urlString: String) -> NSImage? {
        guard let source = SiteIconCache.lookup(urlString), let copy = source.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    /// Makes sure the site's icon is stored. Cheap to call again and again.
    func ensure(_ urlString: String) {
        guard let host = SiteIconCache.host(urlString), host.contains("."), !inFlight.contains(host) else { return }
        if SiteIconCache.lookup(urlString) != nil { return }
        if let failed = failedAt[host], Date().timeIntervalSince(failed) < 1800 { return }
        inFlight.insert(host)
        queue.append(urlString)
        pump()
    }

    func prefetch(_ urls: [String]) {
        for url in urls.prefix(400) { ensure(url) }
    }

    private func pump() {
        while running < 3, !queue.isEmpty {
            let next = queue.removeFirst()
            running += 1
            Task { [weak self] in
                let image = await SiteIconFetcher.download(next)
                self?.finish(next, image)
            }
        }
    }

    private func finish(_ urlString: String, _ image: NSImage?) {
        running -= 1
        if let host = SiteIconCache.host(urlString) {
            inFlight.remove(host)
            if let image {
                SiteIconCache.store(Self.scaled(image), urlString: urlString, persist: true)
                version += 1
            } else {
                failedAt[host] = Date()
            }
        }
        pump()
    }

    /// Keeps stored icons small.
    private static func scaled(_ image: NSImage, to limit: CGFloat = 128) -> NSImage {
        let size = image.size
        guard size.width > limit || size.height > limit else { return image }
        let ratio = min(limit / size.width, limit / size.height)
        let target = NSSize(width: size.width * ratio, height: size.height * ratio)
        let result = NSImage(size: target)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        result.unlockFocus()
        return result
    }
}

enum SiteIconFetcher {
    private static let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    /// Looks for the icon named in the site's own page, then /favicon.ico, then a public icon service as the last resort.
    static func download(_ urlString: String) async -> NSImage? {
        guard let page = URL(string: urlString), let host = page.host else { return nil }
        let scheme = page.scheme ?? "https"
        guard let root = URL(string: "\(scheme)://\(host)/") else { return nil }
        let session = URLSession(configuration: .ephemeral)
        var candidates: [URL] = []
        if let html = await text(root, session) { candidates.append(contentsOf: iconLinks(in: html, base: root)) }
        if let direct = URL(string: "\(scheme)://\(host)/favicon.ico") { candidates.append(direct) }
        if let service = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128") { candidates.append(service) }
        for candidate in candidates.prefix(6) {
            if let image = await picture(candidate, session) { return image }
        }
        return nil
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func text(_ url: URL, _ session: URLSession) async -> String? {
        var request = request(url)
        request.setValue("bytes=0-250000", forHTTPHeaderField: "Range")
        guard let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return String(decoding: data.prefix(300_000), as: UTF8.self)
    }

    private static func picture(_ url: URL, _ session: URLSession) async -> NSImage? {
        guard let (data, response) = try? await session.data(for: request(url)), let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count > 60, data.count < 1_500_000, let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        return image
    }

    /// Icons named in the page's head. Large touch icons come first, then the other icons in page order.
    private static func iconLinks(in html: String, base: URL) -> [URL] {
        guard let tag = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: [.caseInsensitive]),
              let rel = try? NSRegularExpression(pattern: "rel\\s*=\\s*[\"']([^\"']*)[\"']", options: [.caseInsensitive]),
              let href = try? NSRegularExpression(pattern: "href\\s*=\\s*[\"']([^\"']+)[\"']", options: [.caseInsensitive]) else { return [] }
        let source = html as NSString
        var touch: [URL] = []
        var plain: [URL] = []
        for match in tag.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let element = source.substring(with: match.range) as NSString
            guard let relMatch = rel.firstMatch(in: element as String, range: NSRange(location: 0, length: element.length)),
                  let hrefMatch = href.firstMatch(in: element as String, range: NSRange(location: 0, length: element.length)) else { continue }
            let kind = element.substring(with: relMatch.range(at: 1)).lowercased()
            guard kind.contains("icon") else { continue }
            let link = element.substring(with: hrefMatch.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            guard let resolved = URL(string: link, relativeTo: base)?.absoluteURL else { continue }
            if kind.contains("apple-touch") { touch.append(resolved) } else { plain.append(resolved) }
        }
        return touch + plain
    }
}

/// The site's icon for any link. Shows the stored icon at once, downloads it the first time, and shows the site's first letter until then.
struct WebsiteIcon: View {
    var url: String
    var title: String
    var size: CGFloat = 22
    var selected = false
    @ObservedObject private var store = SiteIconStore.shared

    var body: some View {
        let _ = store.version
        SiteIconView(icon: store.image(for: url), title: title.isEmpty ? (SiteIconCache.host(url) ?? "") : title, selected: selected, size: size)
            .onAppear { store.ensure(url) }
            .onChange(of: url) { _ in store.ensure(url) }
    }
}

/// The real icon of a Mac app, from its bundle identifier.
struct AppBundleIcon: View {
    var bundleID: String
    var size: CGFloat = 34

    var body: some View {
        if let location = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: location.path)).resizable().interpolation(.high).scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed").font(.system(size: size * 0.7)).foregroundStyle(Butter.coral).frame(width: size, height: size)
        }
    }
}
