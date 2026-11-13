// Library > Collections: the Grid view and the content-type filter.
//
// The grid is a glimpse of what each shortcut holds: pictures are shown, GIFs play, videos loop for the first
// 10 seconds, documents and sheets show their first page (Quick Look), links show the page's own preview image,
// apps show their icon and text shortcuts show their words.
import AppKit
import AVFoundation
import LinkPresentation
import QuickLookThumbnailing
import SwiftUI

// MARK: - Content types

enum LibraryContentType: String, CaseIterable, Identifiable {
    case all, text, image, gif, video, music, document, link, app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .image: return "Images"
        case .gif: return "GIFs"
        case .video: return "Videos"
        case .music: return "Music"
        case .document: return "Docs & sheets"
        case .link: return "Links"
        case .app: return "Apps"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.quote"
        case .image: return "photo"
        case .gif: return "photo.on.rectangle.angled"
        case .video: return "film"
        case .music: return "waveform"
        case .document: return "doc.text"
        case .link: return "link"
        case .app: return "app.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .all: return .gray
        case .text: return .teal
        case .image: return .green
        case .gif: return .pink
        case .video: return .blue
        case .music: return .purple
        case .document: return .orange
        case .link: return .indigo
        case .app: return .brown
        }
    }

    private static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "webp", "tif", "tiff", "bmp", "heic", "heif", "svg"]
    private static let videoTypes: Set<String> = ["mp4", "mov", "m4v", "avi", "webm", "mpeg", "mpg", "mkv"]
    private static let musicTypes: Set<String> = ["mp3", "wav", "m4a", "aac", "flac", "aiff", "ogg"]

    static func fileType(_ path: String) -> LibraryContentType {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if ext == "gif" { return .gif }
        if imageTypes.contains(ext) { return .image }
        if videoTypes.contains(ext) { return .video }
        if musicTypes.contains(ext) { return .music }
        return .document
    }

    static func of(_ clip: Clip) -> LibraryContentType {
        if let path = clip.files.first { return fileType(path) }
        if let link = clip.webURL, !link.isEmpty { return .link }
        if clip.appBundleIdentifier != nil || clip.appPath != nil { return .app }
        return .text
    }

    static func counts(_ clips: [Clip]) -> [LibraryContentType: Int] {
        var result: [LibraryContentType: Int] = [:]
        for clip in clips { result[of(clip), default: 0] += 1 }
        return result
    }
}

struct LibraryTypeFilterBar: View {
    @Binding var selection: LibraryContentType
    let counts: [LibraryContentType: Int]

    private func count(_ type: LibraryContentType) -> Int {
        type == .all ? counts.values.reduce(0, +) : (counts[type] ?? 0)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LibraryContentType.allCases) { type in
                    if type == .all || count(type) > 0 || selection == type {
                        Button { selection = type } label: {
                            HStack(spacing: 5) {
                                Image(systemName: type.symbol).font(.caption)
                                Text(type.title).font(.caption.weight(.semibold)).lineLimit(1)
                                Text("\(count(type))").font(.caption2).foregroundStyle(selection == type ? Color.white.opacity(0.85) : Color.secondary)
                            }
                            .fixedSize()
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .foregroundStyle(selection == type ? Color.white : Color.primary)
                            .background(selection == type ? type.tint : type.tint.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - The grid

struct LibraryGridView: View {
    let clips: [Clip]
    var selecting: Bool
    @Binding var selectedIDs: Set<UUID>
    var onEdit: (Clip) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14, alignment: .top)], spacing: 14) {
                ForEach(clips) { clip in
                    LibraryGridCard(
                        clip: clip,
                        selecting: selecting,
                        isSelected: selectedIDs.contains(clip.id),
                        onToggle: {
                            if selectedIDs.contains(clip.id) { selectedIDs.remove(clip.id) } else { selectedIDs.insert(clip.id) }
                        },
                        onEdit: { onEdit(clip) }
                    )
                }
            }
            .padding(2)
        }
    }
}

struct LibraryGridCard: View {
    let clip: Clip
    let selecting: Bool
    let isSelected: Bool
    var onToggle: () -> Void
    var onEdit: () -> Void
    @State private var hovering = false

    private var type: LibraryContentType { LibraryContentType.of(clip) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibraryPreview(clip: clip, type: type)
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topLeading) { badge.padding(8) }
                .overlay(alignment: .topTrailing) { corner.padding(8) }
            VStack(alignment: .leading, spacing: 3) {
                Text(displayTrigger(clip.key))
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Butter.coral).lineLimit(1)
                Text(clip.name.isEmpty ? "Untitled" : clip.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Butter.coral : Color.secondary.opacity(0.22), lineWidth: isSelected ? 2 : 1))
        .shadow(color: .black.opacity(hovering ? 0.14 : 0.05), radius: hovering ? 8 : 3, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onHover { hovering = $0 }
        .onTapGesture { if selecting { onToggle() } else { onEdit() } }
    }

    private var badge: some View {
        HStack(spacing: 4) {
            Image(systemName: type.symbol)
            Text(type.title)
            if clip.files.count > 1 { Text("· \(clip.files.count)") }
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
    }

    @ViewBuilder private var corner: some View {
        if selecting {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3).foregroundStyle(isSelected ? Butter.coral : Color.secondary)
                .background(Circle().fill(.ultraThinMaterial))
        } else if hovering {
            Label("Edit", systemImage: "pencil")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

// MARK: - What each tile shows

struct LibraryPreview: View {
    let clip: Clip
    let type: LibraryContentType

    private var path: String? {
        clip.files.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    var body: some View {
        ZStack {
            Color.black.opacity(type == .video || type == .gif || type == .image ? 0.06 : 0)
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch type {
        case .image:
            if let path = path, let image = EzMeImageCache.load(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                missing("photo")
            }
        case .gif:
            if let path = path { AnimatedGIFView(path: path) } else { missing("photo.on.rectangle.angled") }
        case .video:
            if let path = path { LoopingVideoView(url: URL(fileURLWithPath: path), limit: 10) } else { missing("film") }
        case .music:
            ZStack {
                LinearGradient(colors: [Color.purple.opacity(0.35), Color.blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 8) {
                    Image(systemName: "waveform").font(.system(size: 40, weight: .medium)).foregroundStyle(.purple)
                    Text(URL(fileURLWithPath: clip.files.first ?? "").lastPathComponent)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal, 12)
                }
            }
        case .document:
            if let path = path { QuickLookThumbnailView(path: path) } else { missing("doc.text") }
        case .link:
            LinkPreviewTile(urlString: clip.webURL ?? "")
        case .app:
            AppIconTile(clip: clip)
        case .text, .all:
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color.teal.opacity(0.16), Color.blue.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(clip.text.isEmpty ? "No text yet" : clip.text)
                    .font(.system(size: 13)).foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(6).multilineTextAlignment(.leading)
                    .padding(.top, 36).padding(.horizontal, 12)
            }
        }
    }

    private func missing(_ symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(.secondary)
            Text("File not found").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AnimatedGIFView: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.image = NSImage(contentsOfFile: path)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {}
}

/// Plays muted from the start and goes back to the start after `limit` seconds (or at the end of a shorter video).
struct LoopingVideoView: NSViewRepresentable {
    let url: URL
    var limit: Double = 10

    func makeNSView(context: Context) -> LoopingVideoNSView { LoopingVideoNSView(url: url, limit: limit) }
    func updateNSView(_ view: LoopingVideoNSView, context: Context) {}
    static func dismantleNSView(_ view: LoopingVideoNSView, coordinator: ()) { view.stop() }
}

final class LoopingVideoNSView: NSView {
    private let player: AVPlayer
    private let playerLayer = AVPlayerLayer()
    private let limit: Double
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init(url: URL, limit: Double) {
        self.player = AVPlayer(url: url)
        self.limit = limit
        super.init(frame: .zero)
        wantsLayer = true
        player.isMuted = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            if time.seconds >= self.limit { self.restart() }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            self?.restart()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { player.pause() } else { player.play() }
    }

    private func restart() {
        player.seek(to: .zero)
        player.play()
    }

    func stop() {
        player.pause()
        if let observer = timeObserver { player.removeTimeObserver(observer); timeObserver = nil }
        if let observer = endObserver { NotificationCenter.default.removeObserver(observer); endObserver = nil }
    }
}

// MARK: Documents and sheets

enum LibraryThumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func thumbnail(for path: String, size: CGSize) async -> NSImage? {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: size, scale: scale, representationTypes: .all)
        let image: NSImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                if let representation = representation {
                    continuation.resume(returning: NSImage(cgImage: representation.cgImage, size: size))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
        if let image = image { cache.setObject(image, forKey: path as NSString) }
        return image
    }
}

struct QuickLookThumbnailView: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            if let image = image {
                Image(nsImage: image).resizable().scaledToFit().padding(10)
            } else {
                VStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().scaledToFit().frame(width: 54, height: 54)
                    Text(URL(fileURLWithPath: path).lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(2).padding(.horizontal, 12)
                }
            }
        }
        .task(id: path) {
            image = await LibraryThumbnails.thumbnail(for: path, size: CGSize(width: 320, height: 240))
        }
    }
}

// MARK: Links

struct LibraryLinkInfo {
    var title: String?
    var image: NSImage?
}

@MainActor enum LibraryLinkPreviews {
    private static var cache: [String: LibraryLinkInfo] = [:]

    private static func loadImage(_ provider: NSItemProvider?) async -> NSImage? {
        guard let provider = provider, provider.canLoadObject(ofClass: NSImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                continuation.resume(returning: object as? NSImage)
            }
        }
    }

    static func load(_ urlString: String) async -> LibraryLinkInfo {
        if let hit = cache[urlString] { return hit }
        var text = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        var info = LibraryLinkInfo()
        if let url = URL(string: text) {
            let provider = LPMetadataProvider()
            provider.timeout = 8
            if let metadata = try? await provider.startFetchingMetadata(for: url) {
                info.title = metadata.title
                info.image = await loadImage(metadata.imageProvider)
                if info.image == nil { info.image = await loadImage(metadata.iconProvider) }
            }
        }
        cache[urlString] = info
        return info
    }
}

struct LinkPreviewTile: View {
    let urlString: String
    @State private var info: LibraryLinkInfo?

    private var host: String {
        let text = urlString.lowercased().hasPrefix("http") ? urlString : "https://" + urlString
        return URL(string: text)?.host?.replacingOccurrences(of: "www.", with: "") ?? urlString
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = info?.image {
                Color(nsColor: .textBackgroundColor)
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color.indigo.opacity(0.28), Color.blue.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 8) {
                    Image(systemName: "globe").font(.system(size: 34)).foregroundStyle(.indigo)
                    Text(info?.title ?? host).font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center).padding(.horizontal, 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(host)
                .font(.caption2.weight(.semibold)).lineLimit(1)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
        }
        .task(id: urlString) { info = await LibraryLinkPreviews.load(urlString) }
    }
}

// MARK: Apps

struct AppIconTile: View {
    let clip: Clip

    private var icon: NSImage? {
        if let path = clip.appPath, FileManager.default.fileExists(atPath: path) { return NSWorkspace.shared.icon(forFile: path) }
        if let bundle = clip.appBundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.brown.opacity(0.18), Color.orange.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let icon = icon {
                Image(nsImage: icon).resizable().scaledToFit().frame(width: 84, height: 84)
            } else {
                Image(systemName: "app.dashed").font(.system(size: 44)).foregroundStyle(.brown)
            }
        }
    }
}
