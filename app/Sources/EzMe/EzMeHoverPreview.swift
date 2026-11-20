// Hover to see a pictures, GIF, video or design a little bigger. One floating preview that is never cut off by a
// scroll view and always stays on the screen. Used on collection cards, app covers, design and template cards.
import SwiftUI
import AppKit
import AVFoundation

enum HoverMedia {
    case file(String)
    case image(() -> NSImage?)
}

@MainActor final class HoverPreviewPanel {
    static let shared = HoverPreviewPanel()
    private var panel: NSPanel?

    /// The picture's shape, so the preview matches it.
    private func aspect(of media: HoverMedia) -> (ratio: CGFloat, image: NSImage?) {
        switch media {
        case .image(let make):
            let image = make()
            if let image, image.size.height > 0 { return (image.size.width / image.size.height, image) }
            return (1.3, image)
        case .file(let path):
            switch LibraryContentType.fileType(path) {
            case .image, .gif:
                if let image = NSImage(contentsOfFile: path), image.size.height > 0 { return (image.size.width / image.size.height, image) }
            case .video:
                let asset = AVURLAsset(url: URL(fileURLWithPath: path))
                if let size = asset.tracks(withMediaType: .video).first?.naturalSize, size.height > 0 {
                    return (max(0.4, min(2.5, abs(size.width / size.height))), nil)
                }
                return (16.0 / 9.0, nil)
            default:
                break
            }
            return (0.8, nil)
        }
    }

    func show(_ media: HoverMedia, anchor: NSRect) {
        hide()
        let shape = aspect(of: media)
        let longest = min(560, max(320, max(anchor.width, anchor.height) * 2.0))
        let ratio = max(0.3, min(3.5, shape.ratio))
        var size = ratio >= 1 ? CGSize(width: longest, height: longest / ratio) : CGSize(width: longest * ratio, height: longest)
        let center = NSPoint(x: anchor.midX, y: anchor.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main
        let area = (screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)).insetBy(dx: 12, dy: 12)
        size.width = min(size.width, area.width); size.height = min(size.height, area.height)
        var origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        origin.x = min(max(origin.x, area.minX), area.maxX - size.width)
        origin.y = min(max(origin.y, area.minY), area.maxY - size.height)

        let window = NSPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = true
        window.contentView = NSHostingView(rootView: HoverPreviewContent(media: media, image: shape.image).frame(width: size.width, height: size.height))
        window.orderFront(nil)
        panel = window
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct HoverPreviewContent: View {
    let media: HoverMedia
    let image: NSImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
            switch media {
            case .image:
                if let image { Image(nsImage: image).resizable().scaledToFit() }
            case .file(let path):
                switch LibraryContentType.fileType(path) {
                case .image:
                    if let image { Image(nsImage: image).resizable().scaledToFit() }
                case .gif:
                    AnimatedGIFView(path: path)
                case .video:
                    LoopingVideoView(url: URL(fileURLWithPath: path), limit: 10)
                case .music:
                    Image(systemName: "waveform").font(.system(size: 60)).foregroundStyle(.white.opacity(0.8))
                default:
                    QuickLookThumbnailView(path: path)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Modifier

private final class HoverAnchorBox { weak var view: NSView?; var work: DispatchWorkItem? }

private struct HoverAnchor: NSViewRepresentable {
    let box: HoverAnchorBox
    func makeNSView(context: Context) -> NSView { let view = NSView(); box.view = view; return view }
    func updateNSView(_ view: NSView, context: Context) { box.view = view }
}

private struct HoverEnlargeModifier: ViewModifier {
    let media: HoverMedia?
    @State private var box = HoverAnchorBox()

    func body(content: Content) -> some View {
        content
            .background(HoverAnchor(box: box))
            .onHover { inside in
                box.work?.cancel()
                guard inside, let media else { HoverPreviewPanel.shared.hide(); return }
                let item = DispatchWorkItem {
                    MainActor.assumeIsolated {
                        guard let view = box.view, let window = view.window else { return }
                        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
                        HoverPreviewPanel.shared.show(media, anchor: rect)
                    }
                }
                box.work = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
            }
            .onDisappear { box.work?.cancel(); HoverPreviewPanel.shared.hide() }
    }
}

extension View {
    /// Hover for a moment to see this file a little bigger, placed so it is fully on the screen.
    func hoverEnlarge(path: String?) -> some View {
        modifier(HoverEnlargeModifier(media: path.flatMap { FileManager.default.fileExists(atPath: $0) ? HoverMedia.file($0) : nil }))
    }

    /// The same for a picture made on demand, like a design's first page.
    func hoverEnlarge(image: @escaping () -> NSImage?) -> some View {
        modifier(HoverEnlargeModifier(media: .image(image)))
    }
}
