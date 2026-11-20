// Library > Collections: the Grid view and the content-type filter.
//
// The grid is a glimpse of what each shortcut holds: pictures are shown, GIFs play, videos loop for the first
// 10 seconds, documents and sheets show their first page (Quick Look), links show the page's own preview image,
// apps show their icon and text shortcuts show their words.
import AppKit
import ImageIO
import AVFoundation
import AVKit
import LinkPresentation
import QuickLookThumbnailing
import SwiftUI

// MARK: - Content types

enum LibraryContentType: String, CaseIterable, Identifiable {
    case all, text, image, gif, video, music, pdf, sheet, word, slides, document, link, app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .image: return "Images"
        case .gif: return "GIFs"
        case .video: return "Videos"
        case .music: return "Music"
        case .pdf: return "PDF"
        case .sheet: return "Excel & sheets"
        case .word: return "Word & docs"
        case .slides: return "Slides"
        case .document: return "Other files"
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
        case .pdf: return "doc.richtext"
        case .sheet: return "tablecells"
        case .word: return "doc.text"
        case .slides: return "rectangle.on.rectangle.angled"
        case .document: return "doc"
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
        case .pdf: return .red
        case .sheet: return Color(red: 0.13, green: 0.6, blue: 0.35)
        case .word: return Color(red: 0.2, green: 0.4, blue: 0.85)
        case .slides: return .orange
        case .document: return .gray
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
        return documentKind(ext: ext)
    }

    /// PDF, Excel and Google Sheets, Word and Google Docs, slides, or any other file.
    static func documentKind(ext: String) -> LibraryContentType {
        switch ext.lowercased() {
        case "pdf": return .pdf
        case "xls", "xlsx", "xlsm", "xlsb", "csv", "tsv", "numbers", "ods", "gsheet": return .sheet
        case "doc", "docx", "dot", "dotx", "pages", "rtf", "odt", "txt", "md", "gdoc": return .word
        case "ppt", "pptx", "pps", "ppsx", "key", "odp", "gslides": return .slides
        default: return .document
        }
    }

    static func linkKind(_ url: String) -> LibraryContentType {
        let lower = url.lowercased()
        if lower.contains("docs.google.com/spreadsheets") { return .sheet }
        if lower.contains("docs.google.com/document") { return .word }
        if lower.contains("docs.google.com/presentation") { return .slides }
        return .link
    }

    static func of(_ clip: Clip) -> LibraryContentType {
        if let path = clip.files.first { return fileType(path) }
        if let link = clip.webURL, !link.isEmpty { return linkKind(link) }
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
    /// Every shortcut in the current filter, so the large viewer can step through all the media, not just this page.
    var galleryClips: [Clip]? = nil
    /// Called after a file was renamed on disk, so the shortcut points at the new path.
    var collectionNames: [String] = []
    var onViewerEdits: (([ViewerEdit]) -> Void)? = nil
    @State private var viewer: LibraryGalleryStart?
    /// About four or five rows first. More tiles are added only when the person scrolls near the end.
    @State private var shown = LibraryGridView.firstBatch
    static let firstBatch = 24
    private static let nextBatch = 24

    private func openViewer(_ clip: Clip, path: String?) {
        let items = LibraryGalleryItem.items(from: galleryClips ?? clips)
        guard !items.isEmpty else { return }
        let start = items.firstIndex { $0.clipID == clip.id && (path == nil || $0.path == path) } ?? items.firstIndex { $0.clipID == clip.id } ?? 0
        viewer = LibraryGalleryStart(items: items, index: start)
    }

    var body: some View {
        ScrollView {
          LazyVStack(spacing: 0) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14, alignment: .top)], spacing: 14) {
                ForEach(clips.prefix(shown)) { clip in
                    LibraryGridCard(
                        clip: clip,
                        selecting: selecting,
                        isSelected: selectedIDs.contains(clip.id),
                        onToggle: {
                            if selectedIDs.contains(clip.id) { selectedIDs.remove(clip.id) } else { selectedIDs.insert(clip.id) }
                        },
                        onEdit: { onEdit(clip) },
                        onEnlarge: { openViewer(clip, path: clip.files.first { FileManager.default.fileExists(atPath: $0) }) }
                    )
                }
            }
            .padding(2)
            if shown < clips.count {
                ProgressView().controlSize(.small).padding(14)
                    .onAppear { shown = min(clips.count, shown + LibraryGridView.nextBatch) }
                    .id(shown)
            }
          }
        }
        .onChange(of: clips.first?.id) { _ in shown = LibraryGridView.firstBatch; LibraryThumbs.removeAll() }
        .onChange(of: clips.count) { count in if count < shown { shown = max(LibraryGridView.firstBatch, count) } }
        .onDisappear { LibraryThumbs.removeAll() }
        .sheet(item: $viewer) { start in LibraryMediaViewer(items: start.items, startIndex: start.index, collectionNames: collectionNames, onFinished: { edits in onViewerEdits?(edits); LibraryThumbs.removeAll() }) }
    }
}

struct LibraryGridCard: View {
    let clip: Clip
    let selecting: Bool
    let isSelected: Bool
    var onToggle: () -> Void
    var onEdit: () -> Void
    var onEnlarge: () -> Void = {}
    @State private var hovering = false
    @State private var visible = false

    private var type: LibraryContentType { LibraryContentType.of(clip) }
    private var canEnlarge: Bool { [.image, .gif, .video, .music].contains(type) && clip.files.contains { FileManager.default.fileExists(atPath: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibraryPreview(clip: clip, type: type, isVisible: visible)
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topLeading) { badge.padding(8) }
                .overlay(alignment: .topTrailing) { corner.padding(8) }
                .overlay(alignment: .bottomTrailing) { if canEnlarge && !selecting { enlargeButton.padding(8) } }
                .overlay(alignment: .bottomLeading) { if clip.favorite == true { Image(systemName: "heart.fill").foregroundStyle(.red).padding(6).background(.ultraThinMaterial, in: Circle()).padding(8) } }
            VStack(alignment: .leading, spacing: 3) {
                Text(displayTrigger(clip.key))
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Butter.coral).lineLimit(1)
                Text(clip.name.isEmpty ? "Untitled" : clip.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
                TagStrip(tags: clip.tags ?? [])
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
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onTapGesture { if selecting { onToggle() } else { onEdit() } }
    }

    private var enlargeButton: some View {
        Button { onEnlarge() } label: {
            Image(systemName: type == .video || type == .music ? "play.fill" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.black.opacity(0.62)))
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(type == .video ? "Play this video large" : (type == .music ? "Play this audio" : "Show this larger"))
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
    /// False once the tile has scrolled away: videos and GIFs stop and free their memory.
    var isVisible: Bool = true

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
            if let path = path { LibraryPosterTile(path: path, isVideo: false) } else { missing("photo") }
        case .gif:
            if let path = path {
                ZStack {
                    LibraryPosterTile(path: path, isVideo: false)
                    if isVisible { AnimatedGIFView(path: path) }
                }
            } else { missing("photo.on.rectangle.angled") }
        case .video:
            if let path = path {
                ZStack {
                    LibraryPosterTile(path: path, isVideo: true)
                    if isVisible { LoopingVideoView(url: URL(fileURLWithPath: path), limit: 10) }
                }
            } else { missing("film") }
        case .music:
            ZStack {
                LinearGradient(colors: [Color.purple.opacity(0.35), Color.blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 8) {
                    Image(systemName: "waveform").font(.system(size: 40, weight: .medium)).foregroundStyle(.purple)
                    Text(URL(fileURLWithPath: clip.files.first ?? "").lastPathComponent)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal, 12)
                }
            }
        case .document, .pdf, .sheet, .word, .slides:
            if let path = path { QuickLookThumbnailView(path: path) }
            else if let link = clip.webURL, !link.isEmpty { LinkPreviewTile(urlString: link) }
            else { missing("doc.text") }
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
    var path: String

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
        player.replaceCurrentItem(with: nil)
        if let observer = timeObserver { player.removeTimeObserver(observer); timeObserver = nil }
        if let observer = endObserver { NotificationCenter.default.removeObserver(observer); endObserver = nil }
    }
}

// MARK: Small pictures, kept in a bounded cache

/// Small copies of pictures and video first frames. The cache is limited in size and is emptied when the grid goes away,
/// so a big library never holds full-size pictures in memory.
enum LibraryThumbs {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 140
        cache.totalCostLimit = 40 * 1024 * 1024
        return cache
    }()

    static func removeAll() { cache.removeAllObjects() }

    private static func store(_ image: NSImage, key: String) {
        cache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4))
    }

    static func picture(_ path: String, maxPixel: CGFloat = 520) async -> NSImage? {
        let key = "p:" + path
        if let hit = cache.object(forKey: key as NSString) { return hit }
        let image: NSImage? = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                           kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceShouldCacheImmediately: true]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
        if let image { store(image, key: key) }
        return image
    }

    static func videoFrame(_ path: String, maxPixel: CGFloat = 520) async -> NSImage? {
        let key = "v:" + path
        if let hit = cache.object(forKey: key as NSString) { return hit }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        guard let result = try? await generator.image(at: CMTime(seconds: 0.4, preferredTimescale: 600)) else { return nil }
        let image = NSImage(cgImage: result.image, size: NSSize(width: result.image.width, height: result.image.height))
        store(image, key: key)
        return image
    }
}

/// A resized picture, or a video's first frame. Cleared when the tile scrolls away.
struct LibraryPosterTile: View {
    var path: String
    let isVideo: Bool
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: path) {
            image = isVideo ? await LibraryThumbs.videoFrame(path) : await LibraryThumbs.picture(path)
        }
        .onDisappear { image = nil }
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
    var path: String
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
                    WebsiteIcon(url: "https://" + host, title: host, size: 44)
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


// MARK: - Large viewer

struct LibraryGalleryItem: Identifiable {
    let id: String
    let clipID: UUID
    var title: String
    var path: String
    var favorite: Bool = false
    var key: String = ""
    var group: String = ""
    var tags: [String] = []

    /// Every picture, GIF, video and audio file of these shortcuts, in order.
    static func items(from clips: [Clip]) -> [LibraryGalleryItem] {
        var result: [LibraryGalleryItem] = []
        for clip in clips {
            for path in clip.files where [.image, .gif, .video, .music].contains(LibraryContentType.fileType(path)) {
                result.append(LibraryGalleryItem(id: clip.id.uuidString + path, clipID: clip.id, title: clip.name.isEmpty ? displayTrigger(clip.key) : clip.name, path: path, favorite: clip.favorite == true, key: clip.key, group: clip.group, tags: clip.tags ?? []))
            }
        }
        return result
    }
}

enum ViewerEdit {
    case rename(UUID, String, String)
    case favourite(UUID, Bool)
    case move(UUID, String)
    case shortcut(UUID, String)
    case tags(UUID, [String])
}

struct LibraryGalleryStart: Identifiable {
    let id = UUID()
    let items: [LibraryGalleryItem]
    let index: Int
}

/// A big view of pictures, GIFs, videos and audio with Previous and Next, like a browser's image viewer.
/// Left and right arrow keys move too. A video plays with its own controls.
struct LibraryMediaViewer: View {
    @State private var items: [LibraryGalleryItem]
    var collectionNames: [String] = []
    /// Everything done here is applied once the viewer closes, so the grid behind it is not rebuilt while you work.
    var onFinished: (([ViewerEdit]) -> Void)? = nil
    @State private var edits: [ViewerEdit] = []
    @StateObject private var voice = WishVoiceController()
    @State private var heard = ""
    @State private var voiceWanted = false
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var renaming = false
    @State private var newName = ""
    @State private var renameError = ""
    @State private var showInfo = false
    @State private var showShortcutRow = true
    @State private var shortcutText = ""

    init(items: [LibraryGalleryItem], startIndex: Int, collectionNames: [String] = [], onFinished: (([ViewerEdit]) -> Void)? = nil) {
        _items = State(initialValue: items)
        self.collectionNames = collectionNames
        self.onFinished = onFinished
        _index = State(initialValue: min(max(0, startIndex), max(0, items.count - 1)))
    }

    private var infoView: some View {
        let path = items.isEmpty ? "" : items[index].path
        let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
        return VStack(alignment: .leading, spacing: 8) {
            Text("Saved at").font(.headline)
            Text(path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if let size { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(path, forType: .string) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            }.controlSize(.small)
        }.padding(14).frame(width: 380)
    }

    private func startRename() {
        guard !items.isEmpty else { return }
        newName = URL(fileURLWithPath: items[index].path).deletingPathExtension().lastPathComponent
        renameError = ""; renaming = true
    }

    /// Renames the real file next to where it is saved, then points the shortcut at the new name.
    private func commitRename() {
        guard !items.isEmpty else { return }
        let item = items[index]
        let old = URL(fileURLWithPath: item.path)
        let base = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !base.contains("/"), !base.contains(":") else { renameError = "Use a name without / or :"; return }
        let ext = old.pathExtension
        let target = old.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? base : base + "." + ext)
        if target.path == old.path { renaming = false; return }
        if FileManager.default.fileExists(atPath: target.path) { renameError = "A file with that name already exists."; return }
        do { try FileManager.default.moveItem(at: old, to: target) } catch { renameError = "Could not rename: \(error.localizedDescription)"; return }
        edits.append(.rename(item.clipID, old.path, target.path))
        items = items.map { guard $0.path == old.path else { return $0 }; var moved = $0; moved.path = target.path; moved.title = base; return moved }
        showShortcutRow = true
        renaming = false; renameError = ""
    }

    private var hasPrevious: Bool { index > 0 }
    private var hasNext: Bool { index < items.count - 1 }
    private func go(_ delta: Int) { let next = index + delta; if next >= 0, next < items.count { index = next } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if renaming, !items.isEmpty {
                    TextField("File name", text: $newName).textFieldStyle(.roundedBorder).frame(maxWidth: 320).onSubmit { commitRename() }
                    Text("." + URL(fileURLWithPath: items[index].path).pathExtension).font(.caption).foregroundStyle(.secondary)
                    Button("Save") { commitRename() }.buttonStyle(.borderedProminent)
                    Button("Cancel") { renaming = false; renameError = "" }
                } else {
                    Text(items.isEmpty ? "" : URL(fileURLWithPath: items[index].path).lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
                    Button { startRename() } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).help("Rename this file. The saved file is renamed too.").disabled(items.isEmpty)
                    Button { toggleFavourite() } label: { Image(systemName: !items.isEmpty && items[index].favorite ? "heart.fill" : "heart").foregroundStyle(!items.isEmpty && items[index].favorite ? Color.red : Color.secondary) }.buttonStyle(.borderless).help("Favourite").disabled(items.isEmpty)
                    Button { showInfo.toggle() } label: { Image(systemName: "info.circle") }.buttonStyle(.borderless).help("Where this file is saved")
                        .popover(isPresented: $showInfo) { infoView }
                }
                if !renameError.isEmpty { Text(renameError).font(.caption).foregroundStyle(.orange).lineLimit(2) }
                Text("\(items.isEmpty ? 0 : index + 1) of \(items.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                voiceButton
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            if voiceOn || !heard.isEmpty || !voice.errorMessage.isEmpty {
                voiceStrip
            }
            if showShortcutRow, !items.isEmpty { shortcutRow }
            Divider()
            ZStack {
                if items.isEmpty {
                    Text("Nothing to show.").foregroundStyle(.secondary)
                } else {
                    media(items[index].path).id(items[index].id)
                }
                HStack {
                    navButton("chevron.left", enabled: hasPrevious) { go(-1) }
                    Spacer()
                    navButton("chevron.right", enabled: hasNext) { go(1) }
                }
                .padding(.horizontal, 14)
                // Arrow keys
                Button("") { go(-1) }.keyboardShortcut(.leftArrow, modifiers: []).opacity(0).frame(width: 0, height: 0)
                Button("") { go(1) }.keyboardShortcut(.rightArrow, modifiers: []).opacity(0).frame(width: 0, height: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.05))
        }
        .frame(minWidth: 820, idealWidth: 1040, minHeight: 600, idealHeight: 760)
        .onChange(of: voice.errorMessage) { _, message in if !message.isEmpty { stopVoice() } }
        .onReceive(NotificationCenter.default.publisher(for: .keydoVoicePriority)) { _ in stopVoice() }
        .onDisappear { stopVoice(); onFinished?(edits); edits = [] }
    }

    private func toggleFavourite() {
        guard !items.isEmpty else { return }
        let clipID = items[index].clipID
        let on = !items[index].favorite
        items = items.map { var item = $0; if item.clipID == clipID { item.favorite = on }; return item }
        edits.append(.favourite(clipID, on))
        heard = on ? "Added to favourites." : "Removed from favourites."
    }

    // MARK: Voice (the Mac's own speech recognition, whole sentences, clear on/off)

    private var voiceOn: Bool { voice.isListening }
    private var hearing: Bool { voice.isListening && !voice.heard.isEmpty }

    /// Off, Listening (waiting for you) or Hearing (you are speaking): the button always says which.
    private var voiceButton: some View {
        Button { toggleVoice() } label: {
            HStack(spacing: 7) {
                ZStack {
                    if voiceOn {
                        Circle().fill(Color.red.opacity(0.25)).frame(width: 12 + CGFloat(voice.level) * 16, height: 12 + CGFloat(voice.level) * 16)
                            .animation(.easeOut(duration: 0.1), value: voice.level)
                    }
                    Image(systemName: voiceOn ? "mic.fill" : "mic.slash").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(voiceOn ? Color.red : Color.secondary)
                }
                .frame(width: 26, height: 22)
                Text(!voiceOn ? "Voice off" : (hearing ? "Hearing you…" : "Listening… speak"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(voiceOn ? Color.red.opacity(0.12) : Color.secondary.opacity(0.12)))
            .overlay(Capsule().stroke(voiceOn ? Color.red.opacity(0.6) : Color.secondary.opacity(0.3), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .help(voiceOn ? "Voice is on. Click to turn it off." : "Click to turn voice on. Say: rename to …, save, use full name as shortcut, favourite, move to …, next, previous, close")
    }

    private var voiceStrip: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !voice.errorMessage.isEmpty {
                Text(voice.errorMessage).foregroundStyle(.orange)
            } else if voiceOn {
                Text(hearing ? "Hearing: \u{201C}\(voice.heard)\u{201D}" : "Listening. Say “rename to …”, then “save”. Or “use full name as shortcut”, “tag work”, “favourite”, “next”, “close”.")
            }
            if !heard.isEmpty { Text(heard).fontWeight(.semibold) }
        }
        .font(.caption).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 6)
    }

    private func toggleVoice() { voiceOn ? stopVoice() : startVoice() }

    private func startVoice() {
        voiceWanted = true
        NotificationCenter.default.post(name: .keydoVoiceTakeover, object: voice)
        KeyDoVoice.shared.suspended = true
        KeyDoVoice.shared.stop(announce: false)
        let saved = UserDefaults.standard.string(forKey: "keydoVoiceLocale") ?? ""
        voice.start(localeIdentifier: saved.isEmpty ? Locale.current.identifier : saved, commitDelay: 1.0) { sentence in
            Task { @MainActor in _ = handleVoice(sentence) }
        }
        heard = ""
    }

    private func stopVoice() {
        guard voiceWanted || voice.isListening else { return }
        voiceWanted = false
        voice.stop()
        KeyDoVoice.shared.suspended = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            KeyDoVoice.shared.startWakeIfNeeded()
        }
    }

    private func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A whole spoken sentence. Understands: rename to …, save, cancel, use full name as shortcut, short shortcut,
    /// set shortcut to …, favourite, move to …, info, next, previous, close.
    private func handleVoice(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,!?")))
        let lower = text.lowercased()
        guard !lower.isEmpty else { return false }
        // "rename to sunset beach and save" renames in one go. "re name", "rename too" and "rename 2" are heard as rename to.
        if !items.isEmpty, var name = firstMatch("^(?:please\\s+)?(?:re[\\s-]?name|name|call)(?:\\s+(?:this|it|the file))?(?:\\s+(?:to|too|2|as))?\\s+(.+)$", in: text), !name.isEmpty {
            var saveNow = false
            for tail in [" and save it", " and save", " then save", " and done", " and confirm", " save it", " save"] where name.lowercased().hasSuffix(tail) {
                name = String(name.dropLast(tail.count)).trimmingCharacters(in: .whitespaces); saveNow = true; break
            }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: ".,!? "))
            guard !name.isEmpty else { return false }
            newName = name; renameError = ""; renaming = true
            if saveNow { commitRename(); heard = renameError.isEmpty ? "Renamed to \(name)." : renameError }
            else { heard = "New name: \(name). Say “save” to rename the file." }
            return true
        }
        if ["save", "save it", "save name", "save the name", "confirm", "done", "yes", "ok save", "okay save"].contains(lower) {
            if renaming { commitRename(); heard = renameError.isEmpty ? "Saved. The file is renamed." : renameError }
            else { heard = "Nothing to save. Say “rename to …” first." }
            return true
        }
        if ["cancel", "cancel rename", "never mind", "nevermind"].contains(lower) { renaming = false; renameError = ""; heard = "Rename cancelled."; return true }
        // Shortcut names
        if !items.isEmpty {
            let options = shortcutOptions()
            if lower.contains("full name") || lower.contains("file name") || lower.contains("same name") {
                if let full = options.first { applyShortcut(full.key); return true }
            }
            if lower.contains("short") && lower.contains("shortcut") || lower.hasPrefix("short name") || lower.contains("short one") {
                if let short = options.last { applyShortcut(short.key); return true }
            }
            if let word = firstMatch("^(?:set\\s+|make\\s+)?(?:the\\s+)?shortcut\\s+(?:to|is|as|name)?\\s*(.+)$", in: text), !word.isEmpty {
                let base = ShortcutNaming.slug(word)
                if !base.isEmpty { applyShortcut(ShortcutNaming.build(base, pattern: shortcutPattern(), taken: shortcutTaken())); return true }
            }
        }
        if !items.isEmpty, let word = firstMatch("^(?:add\\s+)?(?:tag|tags)\\s+(?:this\\s+|it\\s+)?(?:as\\s+|with\\s+)?(.+)$", in: text) ?? firstMatch("^tag\\s+(.+)$", in: text) {
            let clipID = items[index].clipID
            var list = items[index].tags
            for tag in KeyDoTags.parse(word.replacingOccurrences(of: " and ", with: ",")) {
                KeyDoTags.remember(tag)
                if !list.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { list.append(tag) }
            }
            items = items.map { var item = $0; if item.clipID == clipID { item.tags = list }; return item }
            edits.append(.tags(clipID, list)); heard = "Tags: " + KeyDoTags.join(list)
            return true
        }
        if !items.isEmpty, let word = firstMatch("^(?:remove|delete|clear)\\s+(?:the\\s+)?tag\\s+(.+)$", in: text) {
            let clipID = items[index].clipID
            let list = items[index].tags.filter { $0.caseInsensitiveCompare(KeyDoTags.canonical(word)) != .orderedSame }
            items = items.map { var item = $0; if item.clipID == clipID { item.tags = list }; return item }
            edits.append(.tags(clipID, list)); heard = "Removed the tag \(word)."
            return true
        }
        if ["next", "next one", "next file", "forward"].contains(lower) { go(1); heard = ""; return true }
        if ["previous", "previous one", "back", "go back", "previous file"].contains(lower) { go(-1); heard = ""; return true }
        if ["favourite", "favorite", "make favourite", "make favorite", "add to favourites", "add to favorites", "love it", "unfavourite", "unfavorite", "remove favourite", "remove favorite"].contains(lower) { toggleFavourite(); return true }
        if ["info", "show path", "where is it saved", "show info"].contains(lower) { showInfo = true; return true }
        if ["close", "close preview", "exit", "stop"].contains(lower) { dismiss(); return true }
        if let target = firstMatch("^(?:move|organise|organize|put)(?:\\s+(?:it|this))?\\s+(?:to|into|in)\\s+(.+)$", in: text), !target.isEmpty, !items.isEmpty {
            if let match = collectionNames.first(where: { $0.caseInsensitiveCompare(target) == .orderedSame }) ?? collectionNames.first(where: { $0.lowercased().contains(target.lowercased()) }) {
                edits.append(.move(items[index].clipID, match)); heard = "Moved to \(match). It leaves this collection when you close the preview."
            } else { heard = "No collection called “\(target)”." }
            return true
        }
        heard = "Heard “\(text)”, but that is not a command here."
        return false
    }

    // MARK: Shortcut names

    private func shortcutPattern() -> ShortcutNaming.Pattern {
        guard !items.isEmpty else { return ShortcutNaming.Pattern() }
        let group = items[index].group
        let keys = items.filter { group.isEmpty || $0.group == group }.map { $0.key }
        return ShortcutNaming.infer(from: Array(Set(keys)))
    }

    private func shortcutTaken() -> Set<String> {
        guard !items.isEmpty else { return [] }
        return Set(items.filter { $0.clipID != items[index].clipID }.map { $0.key })
    }

    private func shortcutOptions() -> [ShortcutNaming.Suggestion] {
        guard !items.isEmpty else { return [] }
        let name = URL(fileURLWithPath: items[index].path).deletingPathExtension().lastPathComponent
        return ShortcutNaming.suggestions(forFileName: name, pattern: shortcutPattern(), taken: shortcutTaken())
    }

    private func applyShortcut(_ key: String) {
        guard !items.isEmpty else { return }
        let clipID = items[index].clipID
        items = items.map { var item = $0; if item.clipID == clipID { item.key = key }; return item }
        edits.append(.shortcut(clipID, key))
        heard = "Shortcut is now \(displayTrigger(key))."
    }

    private var shortcutRow: some View {
        let current = items[index].key
        let options = shortcutOptions()
        let pattern = shortcutPattern()
        let clipID = items[index].clipID
        let tagBinding = Binding<[String]>(
            get: { items.first(where: { $0.clipID == clipID })?.tags ?? [] },
            set: { list in items = items.map { var item = $0; if item.clipID == clipID { item.tags = list }; return item } }
        )
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Name").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(items[index].title).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text("(the display name follows the file name)").font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 8) {
                Text("Shortcut").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(displayTrigger(current)).font(.system(size: 12, weight: .semibold, design: .monospaced)).lineLimit(1)
                ForEach(options) { option in
                    Button { applyShortcut(option.key) } label: {
                        Text("\(option.label): \(displayTrigger(option.key))").font(.system(size: 11, design: .monospaced)).lineLimit(1)
                    }
                    .buttonStyle(.bordered).controlSize(.small).disabled(option.key.caseInsensitiveCompare(current) == .orderedSame)
                }
                TextField("or type one", text: $shortcutText).textFieldStyle(.roundedBorder).frame(width: 130).font(.caption)
                    .onSubmit { let base = ShortcutNaming.slug(shortcutText); if !base.isEmpty { applyShortcut(ShortcutNaming.build(base, pattern: pattern, taken: shortcutTaken())); shortcutText = "" } }
                Spacer()
            }
            if !pattern.isEmpty { Text(pattern.note).font(.caption2).foregroundStyle(.secondary) }
            TagEditor(tags: tagBinding, onChange: { list in edits.append(.tags(clipID, list)); heard = list.isEmpty ? "Tags removed." : "Tags: " + KeyDoTags.join(list) })
        }
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    private func navButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.black.opacity(enabled ? 0.6 : 0.2)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(symbol == "chevron.left" ? "Previous" : "Next")
    }

    @ViewBuilder private func media(_ path: String) -> some View {
        if !FileManager.default.fileExists(atPath: path) {
            Text("This file is missing.").foregroundStyle(.secondary)
        } else {
            switch LibraryContentType.fileType(path) {
            case .image:
                if let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().scaledToFit().padding(.horizontal, 70).padding(.vertical, 12)
                } else { Text("Could not open this picture.").foregroundStyle(.secondary) }
            case .gif:
                AnimatedGIFView(path: path).padding(.horizontal, 70).padding(.vertical, 12)
            default:
                LargeMediaPlayer(url: URL(fileURLWithPath: path))
            }
        }
    }
}

private struct LargeMediaPlayer: View {
    let url: URL
    @State private var player = AVPlayer()

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                player.play()
            }
            .onDisappear { player.pause() }
    }
}
