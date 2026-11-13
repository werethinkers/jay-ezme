// Image Resizer: a shortcut code and a display name for a picture, worked out from what the picture tells us.
//
// In order: its file name, the shortcut it came from, the title or caption stored inside the picture, and the web
// address it was downloaded from. The first one that reads like a real name wins. A name that is too long, mostly
// digits or letters-and-numbers codes, or only a camera or screenshot label ("IMG_4021", "Screen Shot 2024-05-01 at
// 10.22.11 AM") is not a real name, so the picture is called Screenshot-<date>-<time>, which is always unique.
import CoreGraphics
import Foundation
import ImageIO

enum ImageNaming {
    /// Longest shortcut code this app makes (it fits "screenshot-20261113-125530").
    static let codeLimit = 32
    private static let nameLimit = 40

    /// A shortcut key without its leading slash, in lower case, for comparing.
    static func slug(_ key: String) -> String {
        key.trimmingCharacters(in: CharacterSet(charactersIn: "/\\")).lowercased()
    }

    static func names(for path: String, fallbackTitle: String?, existingKeys: Set<String>, now: Date = Date()) -> (code: String, name: String) {
        var candidates: [String] = [URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent]
        if let title = fallbackTitle { candidates.append(title) }
        candidates.append(contentsOf: embeddedTitles(path))
        if let origin = sourceName(path) { candidates.append(origin) }

        for raw in candidates {
            let words = cleanWords(raw)
            guard isRelevant(words) else { continue }
            let name = displayName(words)
            let code = codeText(words)
            if code.count >= 2 { return (unique(code, existingKeys), name) }
        }
        let stamp = screenshotName(now)
        return (unique(stamp.lowercased(), existingKeys), stamp)
    }

    static func screenshotName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Screenshot-" + formatter.string(from: date)
    }

    // MARK: Cleaning

    private static func cleanWords(_ raw: String) -> [String] {
        var text = raw
        // names this app gave to its own copies: resizer-<uuid>-photo, studio-<uuid>-photo, resized-<uuid>
        text = text.replacingOccurrences(of: "^(resizer|studio|resized|crop|local)[-_][0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}[-_]?", with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "(?i)\\s*[·•]\\s*resized$", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)\\s+cut$", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
        return text.split(separator: " ").map(String.init)
    }

    private static let generic = try? NSRegularExpression(
        pattern: "^(img|image|images|dsc|dscn|dscf|pxl|mvimg|photo|photos|picture|pic|screenshot|screen shot|screen recording|untitled|download|unnamed|whatsapp image|whatsapp video|capture|snap|scan|file|copy|new image|resized image)\\s*[\\d\\s]*(at\\s*[\\d\\s]*(am|pm)?)?$",
        options: [.caseInsensitive])

    private static func isRelevant(_ words: [String]) -> Bool {
        guard !words.isEmpty, words.count <= 8 else { return false }
        let text = words.joined(separator: " ")
        guard text.count >= 3, text.count <= 48 else { return false }
        let letters = text.filter { $0.isLetter }.count
        guard letters >= 3, Double(letters) / Double(text.count) >= 0.5 else { return false }
        if text.range(of: "[0-9a-fA-F]{8,}", options: .regularExpression) != nil { return false }
        if let regex = generic, regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil { return false }
        return true
    }

    private static func displayName(_ words: [String]) -> String {
        var result = ""
        for word in words {
            let shown = word == word.lowercased() ? word.prefix(1).uppercased() + word.dropFirst() : word
            let next = result.isEmpty ? shown : result + " " + shown
            if next.count > nameLimit { break }
            result = next
        }
        return result
    }

    private static func codeText(_ words: [String]) -> String {
        var result = ""
        for word in words {
            let piece = word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
            if piece.isEmpty { continue }
            let next = result.isEmpty ? piece : result + "-" + piece
            if next.count > codeLimit {
                if result.isEmpty { result = String(piece.prefix(codeLimit)) }
                break
            }
            result = next
        }
        return result
    }

    private static func unique(_ code: String, _ existing: Set<String>) -> String {
        if !existing.contains(code) { return code }
        var number = 2
        while true {
            let suffix = "-\(number)"
            let candidate = String(code.prefix(codeLimit - suffix.count)) + suffix
            if !existing.contains(candidate) { return candidate }
            number += 1
        }
    }

    // MARK: What the picture says about itself

    /// The title or caption stored inside the picture (IPTC, TIFF or PNG text), when there is one.
    private static func embeddedTitles(_ path: String) -> [String] {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return [] }
        var found: [String] = []
        if let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            if let value = iptc[kCGImagePropertyIPTCObjectName] as? String { found.append(value) }
            if let value = iptc[kCGImagePropertyIPTCCaptionAbstract] as? String { found.append(value) }
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let value = tiff[kCGImagePropertyTIFFImageDescription] as? String { found.append(value) }
        if let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any],
           let value = png[kCGImagePropertyPNGDescription] as? String { found.append(value) }
        return found
    }

    /// The name at the end of the web address the picture was downloaded from (Finder remembers it).
    private static func sourceName(_ path: String) -> String? {
        let attribute = "com.apple.metadata:kMDItemWhereFroms"
        let size = getxattr(path, attribute, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { buffer in
            getxattr(path, attribute, buffer.baseAddress, size, 0, 0)
        }
        guard read > 0,
              let list = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String],
              let first = list.first, let url = URL(string: first) else { return nil }
        let last = url.deletingPathExtension().lastPathComponent
        return last.isEmpty ? nil : last
    }
}
