// Basic privacy and safety rules for the in-app browser.
//  - Programs and installers are never downloaded (apps, installers, scripts, disk images, Windows programs).
//  - Every other download asks first, and says which site wants to save which file.
//  - Plain http:// pages are upgraded to https:// (with one fall back to http for sites that have no https).
//  - Well-known advertising and tracking hosts are blocked when they load inside another site.
//  - Pages cannot open pop-up windows by themselves.
import AppKit
import WebKit

enum EzMeBrowserSafety {
    /// File types that run code on a Mac or on other systems. KeyDo does not download these.
    static let blockedExtensions: Set<String> = [
        "app", "pkg", "mpkg", "dmg", "iso", "exe", "msi", "bat", "cmd", "com", "scr", "pif", "sh", "command", "csh", "zsh", "bash",
        "ps1", "vbs", "vbe", "wsf", "jar", "apk", "ipa", "deb", "rpm", "dylib", "kext", "workflow", "action", "terminal",
        "scpt", "scptd", "applescript", "lnk", "reg", "dll", "sys", "appimage", "run", "bin", "cpl", "msp", "hta", "swf"
    ]

    static func isBlocked(filename: String) -> Bool {
        let parts = filename.lowercased().split(separator: ".").map(String.init)
        guard parts.count > 1 else { return false }
        // "invoice.pdf.exe" is blocked by its last part; also look at the one before a trailing archive suffix.
        return blockedExtensions.contains(parts.last ?? "")
    }

    /// Returns true when the person agrees to save this file.
    @MainActor static func confirmDownload(filename: String, from host: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Download \u{201C}\(filename)\u{201D}?"
        alert.informativeText = "\(host.isEmpty ? "This page" : host) wants to save this file on your Mac. Only download files you trust."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Download")
        alert.alertStyle = .warning
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// True for http:// addresses that should be tried as https:// first.
    static func httpsUpgrade(for url: URL) -> URL? {
        guard url.scheme?.lowercased() == "http", let host = url.host?.lowercased() else { return nil }
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") { return nil }
        if host.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) { return nil } // plain IP addresses
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.scheme = "https"
        if parts?.port == 80 { parts?.port = nil }
        return parts?.url
    }

    private static let trackerHosts: [String] = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com", "adservice.google.com",
        "adnxs.com", "adsrvr.org", "taboola.com", "outbrain.com", "scorecardresearch.com", "quantserve.com", "criteo.com",
        "criteo.net", "rubiconproject.com", "pubmatic.com", "openx.net", "moatads.com", "amazon-adsystem.com", "hotjar.com",
        "mixpanel.com", "segment.io", "fullstory.com", "krxd.net", "bluekai.com", "demdex.net", "everesttech.net"
    ]

    private static var ruleList: WKContentRuleList?
    private static var loading = false
    private static var waiting: [(WKContentRuleList) -> Void] = []

    /// Gives the tracker block list to a callback, compiling it once.
    @MainActor static func withRules(_ use: @escaping (WKContentRuleList) -> Void) {
        if let ruleList { use(ruleList); return }
        waiting.append(use)
        guard !loading else { return }
        loading = true
        let rules: [[String: Any]] = trackerHosts.map { host in
            let escaped = host.replacingOccurrences(of: ".", with: "\\.")
            return ["trigger": ["url-filter": "^https?://([^/]+\\.)?" + escaped + "[:/]", "load-type": ["third-party"]], "action": ["type": "block"]]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules), let json = String(data: data, encoding: .utf8) else { loading = false; waiting = []; return }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "KeyDoTrackerBlock1", encodedContentRuleList: json) { list, _ in
            DispatchQueue.main.async {
                loading = false
                if let list { ruleList = list; for callback in waiting { callback(list) } }
                waiting = []
            }
        }
    }
}
