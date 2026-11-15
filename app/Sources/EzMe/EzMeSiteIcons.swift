// Site icons for browser tabs: remembered per site, shown straight away, kept until the tab is closed.
import SwiftUI
import AppKit

@MainActor
enum SiteIconCache {
    private static var memory: [String: NSImage] = [:]
    private static var missing = Set<String>()

    private static var directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MiniJ/SiteIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func host(_ urlString: String) -> String? {
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func file(_ host: String) -> URL {
        directory.appendingPathComponent(host.replacingOccurrences(of: "/", with: "_") + ".png")
    }

    /// The remembered icon for this page's site: memory first, then the saved file (read once).
    static func lookup(_ urlString: String) -> NSImage? {
        guard let host = host(urlString) else { return nil }
        if let image = memory[host] { return image }
        if missing.contains(host) { return nil }
        if let image = NSImage(contentsOf: file(host)) { memory[host] = image; return image }
        missing.insert(host)
        return nil
    }

    /// Remembers the icon. Incognito and Private Mode keep it in memory only.
    static func store(_ image: NSImage, urlString: String, persist: Bool) {
        guard let host = host(urlString) else { return }
        memory[host] = image
        missing.remove(host)
        guard persist, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: file(host), options: .atomic)
    }
}

/// The icon, or while there is none the first letter of the site's name, so a tab never looks empty or jumps.
struct SiteIconView: View {
    var icon: NSImage?
    var title: String
    var selected = false
    var size: CGFloat = 14

    var body: some View {
        if let icon {
            Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            Text(String(title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                .font(.system(size: size * 0.62, weight: .heavy, design: .rounded))
                .foregroundStyle(selected ? .white : Butter.coral)
                .frame(width: size, height: size)
                .background(selected ? Butter.coral : Butter.coral.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.26))
        }
    }
}
