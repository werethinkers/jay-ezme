// Collections of media work like collections of wishes: attach a picture or video by its name, or find it by words
// from its description. Typing or saying "birthday cake" lists the matching media with a small picture to tap.
import SwiftUI
import AppKit

@MainActor enum MediaFinder {
    private static let pictureTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff", "bmp"]
    private static var thumbnails: [String: NSImage] = [:]

    static func firstPicture(_ clip: Clip) -> String? {
        clip.files.first { path in FileManager.default.fileExists(atPath: path) && pictureTypes.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) }
    }

    /// A small copy of the picture, kept so lists stay quick.
    static func thumbnail(_ clip: Clip) -> NSImage? {
        guard let path = firstPicture(clip) else { return nil }
        if let cached = thumbnails[path] { return cached }
        guard let image = NSImage(contentsOfFile: path), image.size.width > 0, image.size.height > 0 else { return nil }
        let side: CGFloat = 96
        let scale = max(side / image.size.width, side / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let small = NSImage(size: size)
        small.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        small.unlockFocus()
        thumbnails[path] = small
        return small
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 }
    }

    /// True when most of the shortcuts in a collection are pictures or videos.
    static func isMediaCollection(_ name: String) -> Bool {
        let clips = WishPick.clips(in: name)
        guard !clips.isEmpty else { return false }
        return clips.filter { SourceMedia.hasMedia($0) }.count * 2 > clips.count
    }

    /// The media collection a picture box is named after, if there is one.
    static func collectionNamed(_ key: String) -> String? {
        AppDesignContext.shared.collections.first { $0.caseInsensitiveCompare(key) == .orderedSame && isMediaCollection($0) }
    }

    /// Media that matches what was typed or said: its key, its name, its keywords, or words from its description.
    /// Every word said has to be found. Best matches first.
    static func search(_ query: String, in collection: String? = nil, limit: Int = 8) -> [Clip] {
        let pool = AppDesignContext.shared.clips.filter { clip in
            guard SourceMedia.hasMedia(clip) else { return false }
            guard let collection else { return true }
            return clip.allGroups.contains { $0.caseInsensitiveCompare(collection) == .orderedSame }
        }
        let tokens = words(query)
        guard !tokens.isEmpty else { return Array(pool.prefix(limit)) }
        let compact = WishPick.plain(query)
        let lowered = query.trimmingCharacters(in: .whitespaces).lowercased()
        var scored: [(clip: Clip, score: Int)] = []
        for clip in pool {
            let key = WishPick.plain(clip.key)
            let haystack = [clip.key, clip.name, clip.keywords ?? "", String(clip.text.prefix(400))].joined(separator: " ").lowercased()
            var score = 0
            if !compact.isEmpty, key == compact { score += 100 } else if !compact.isEmpty, key.contains(compact) { score += 60 }
            if clip.name.lowercased() == lowered { score += 90 }
            let hits = tokens.filter { haystack.contains($0) }.count
            if hits == tokens.count { score += 30 + hits * 5 }
            if score > 0 { scored.append((clip, score)) }
        }
        return scored.sorted { $0.score > $1.score }.prefix(limit).map { $0.clip }
    }

    static func best(_ query: String, in collection: String? = nil) -> Clip? { search(query, in: collection, limit: 1).first }
}

/// A small picture, or a film icon for a video.
struct MediaThumb: View {
    var clip: Clip
    var body: some View {
        Group {
            if let image = MediaFinder.thumbnail(clip) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack { Color(white: 0.92); Image(systemName: "film").foregroundStyle(.secondary) }
            }
        }
        .frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private func mediaDescription(_ clip: Clip) -> String {
    let text = clip.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    return text.isEmpty ? (clip.keywords ?? "") : String(text.prefix(90))
}

/// Matches shown under a picture box while someone types or says words for it.
struct MediaSuggestions: View {
    var query: String
    var collection: String?
    var onPick: (Clip) -> Void

    var body: some View {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact = celebrationMedia(text, clips: AppDesignContext.shared.clips) != nil || FileManager.default.fileExists(atPath: text)
        let hits: [Clip] = (text.isEmpty || exact) ? [] : MediaFinder.search(text, in: collection, limit: 5)
        if !hits.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Matching media. Tap one to use it.").font(.system(size: 10)).foregroundStyle(.secondary)
                ForEach(hits, id: \.id) { clip in
                    Button { onPick(clip) } label: {
                        HStack(spacing: 8) {
                            MediaThumb(clip: clip)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(clip.name.isEmpty ? clip.key : clip.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text(clip.key + (mediaDescription(clip).isEmpty ? "" : "  \u{00B7}  " + mediaDescription(clip))).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Butter.cream))
        }
    }
}

/// All the media of one collection (or of the whole library), searchable by name or description.
struct MediaChooserList: View {
    var collection: String?
    var onPick: (Clip) -> Void
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search by name or description", text: $query).textFieldStyle(.plain)
            }
            .padding(10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    let clips = MediaFinder.search(query, in: collection, limit: 120)
                    if clips.isEmpty { Text("No media found.").font(.system(size: 12)).foregroundStyle(.secondary).padding(8) }
                    ForEach(clips, id: \.id) { clip in
                        Button { onPick(clip) } label: {
                            HStack(spacing: 8) {
                                MediaThumb(clip: clip)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(clip.name.isEmpty ? clip.key : clip.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Text(clip.key).font(.system(size: 10, weight: .bold)).foregroundStyle(Butter.coral)
                                    if !mediaDescription(clip).isEmpty { Text(mediaDescription(clip)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
                                }
                                Spacer()
                            }
                            .padding(4).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
    }
}
