// Video Editor: Watermark and overlays. A logo kept on the whole video with a see-through level, and pictures or
// animated GIFs placed over the video for chosen seconds. They are drawn into the video itself when it is exported,
// with a short fade, so they look like part of the film.
import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import ImageIO
import QuartzCore

private struct OverlayError: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

private struct OverlayItem: Identifiable {
    let id = UUID()
    var name: String
    var frames: [CGImage]
    var delays: [Double]
    var start = 0.0
    var length = 3.0
    var anchor = 4
    var size = 0.3
    var opacity = 1.0
    var animated: Bool { frames.count > 1 }
}

private enum OverlayLoader {
    /// All frames of a picture or GIF with the time each is shown.
    static func load(_ url: URL) -> (frames: [CGImage], delays: [Double])? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var frames: [CGImage] = [], delays: [Double] = []
        for index in 0..<CGImageSourceGetCount(source) {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(frame)
            var delay = 0.1
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
               let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                let value = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
                delay = value < 0.02 ? 0.1 : value
            }
            delays.append(delay)
        }
        return frames.isEmpty ? nil : (frames, delays)
    }

    static func cg(_ image: NSImage) -> CGImage? { image.cgImage(forProposedRect: nil, context: nil, hints: nil) }

    /// Where a picture goes. Origin at the bottom left, as in AppKit drawing and Core Animation.
    static func rect(anchor: Int, canvas: CGSize, image: CGSize, size: Double, gap: Double) -> CGRect {
        var width = canvas.width * CGFloat(size)
        var height = width * image.height / max(1, image.width)
        if height > canvas.height * 0.9 { height = canvas.height * 0.9; width = height * image.width / max(1, image.height) }
        let edge = canvas.width * CGFloat(gap)
        func place(_ index: Int, _ total: CGFloat, _ length: CGFloat) -> CGFloat {
            switch index { case 0: return edge; case 1: return (total - length) / 2; default: return total - length - edge }
        }
        let x = place(anchor % 3, canvas.width, width)
        let top = place(anchor / 3, canvas.height, height)
        return CGRect(x: x, y: canvas.height - top - height, width: width, height: height)
    }
}

@MainActor struct VideoOverlayView: View {
    var clips: [Clip]
    var attachmentDirectory: URL
    var onSave: (Clip) -> Void
    var onExport: (Clip) -> Void

    @State private var sourceURL: URL?
    @State private var duration = 0.0
    @State private var frame: NSImage?
    @State private var time = 0.0

    @State private var logo: NSImage?
    @State private var logoName = ""
    @State private var logoOn = true
    @State private var logoCut = false
    @State private var logoOpacity = 0.6
    @State private var logoSize = 0.18
    @State private var logoAnchor = 8
    @State private var logoGap = 0.03

    @State private var overlays: [OverlayItem] = []
    @State private var name = ""
    @State private var busy = false
    @State private var message = ""

    private var logoImage: NSImage? {
        guard let logo else { return nil }
        return logoCut ? (LogoMaker.cutOut(logo, tolerance: 0.18) ?? logo) : logo
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    step("1. Your video") {
                        Button { openVideo() } label: { Label(sourceURL == nil ? "Choose video" : "Change video", systemImage: "film") }.buttonStyle(.bordered)
                        Text(sourceURL.map { $0.lastPathComponent + " \u{00B7} " + clock(duration) } ?? "No video yet").font(.caption).foregroundStyle(.secondary)
                    }
                    step("2. Watermark on the whole video") {
                        Toggle("Show a logo all through the video", isOn: $logoOn)
                        if logoOn {
                            PhotoChooser(app: "Video Editor", title: "Choose your logo", name: logoName) { image, label in logo = image; logoName = label }
                            Toggle("Make the logo's plain background transparent", isOn: $logoCut)
                            slider("See-through", $logoOpacity, 0.1...1)
                            slider("Size", $logoSize, 0.05...0.6)
                            slider("Gap", $logoGap, 0...0.12)
                            anchorGrid($logoAnchor)
                        }
                    }
                    step("3. Pictures and animations for some seconds") {
                        ForEach($overlays) { $item in overlayRow($item) }
                        HStack {
                            Button { addOverlay() } label: { Label("Add picture or GIF", systemImage: "plus") }.buttonStyle(.bordered)
                            Button { pasteOverlay() } label: { Label("Paste", systemImage: "doc.on.clipboard") }.buttonStyle(.bordered)
                        }
                        Text("Each one fades in and out so it blends into the film. A GIF keeps playing for its seconds.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.trailing, 6)
            }
            .frame(width: 390)
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Butter.cream)
                    if let shown = preview() { Image(nsImage: shown).resizable().scaledToFit().padding(8) }
                    else { Text("Choose a video to see it here.").foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if duration > 0 {
                    HStack { Text(clock(time)).font(.caption.monospacedDigit()); Slider(value: $time, in: 0...max(0.1, duration), onEditingChanged: { editing in if !editing { Task { await grabFrame() } } }); Text(clock(duration)).font(.caption.monospacedDigit()) }
                }
                HStack(spacing: 8) {
                    TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 180)
                    Button { Task { await export(toDesktop: false) } } label: { Label(busy ? "Making\u{2026}" : "Make video and save", systemImage: "wand.and.stars") }
                        .buttonStyle(.borderedProminent).tint(Butter.coral).disabled(busy || sourceURL == nil)
                    Button { Task { await export(toDesktop: true) } } label: { Label("Save to Desktop", systemImage: "desktopcomputer") }
                        .buttonStyle(.bordered).disabled(busy || sourceURL == nil)
                }
                if !message.isEmpty { Text(message).font(.callout).foregroundStyle(Butter.cocoa) }
            }
        }
    }

    // MARK: Pieces of the screen

    private func step<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Butter.cocoa)
            content()
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Butter.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack { Text(title).font(.caption).frame(width: 70, alignment: .leading); Slider(value: value, in: range) }
    }

    private func anchorGrid(_ anchor: Binding<Int>) -> some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        Button { anchor.wrappedValue = index } label: {
                            RoundedRectangle(cornerRadius: 6).fill(anchor.wrappedValue == index ? Butter.coral : Butter.honey.opacity(0.5)).frame(width: 40, height: 24)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func overlayRow(_ item: Binding<OverlayItem>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.wrappedValue.name + (item.wrappedValue.animated ? " \u{00B7} animated" : "")).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                Button { overlays.removeAll { $0.id == item.wrappedValue.id } } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            slider("Starts at", Binding(get: { item.wrappedValue.start }, set: { item.wrappedValue.start = $0 }), 0...max(0.5, duration))
            slider("Seconds", Binding(get: { item.wrappedValue.length }, set: { item.wrappedValue.length = $0 }), 0.5...max(1, duration))
            slider("Size", Binding(get: { item.wrappedValue.size }, set: { item.wrappedValue.size = $0 }), 0.05...0.9)
            slider("See-through", Binding(get: { item.wrappedValue.opacity }, set: { item.wrappedValue.opacity = $0 }), 0.1...1)
            anchorGrid(Binding(get: { item.wrappedValue.anchor }, set: { item.wrappedValue.anchor = $0 }))
        }
        .padding(8).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    // MARK: Choosing things

    private func openVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        sourceURL = url
        time = 0
        Task {
            let asset = AVURLAsset(url: url)
            duration = ((try? await asset.load(.duration)).map { CMTimeGetSeconds($0) }) ?? 0
            await grabFrame()
        }
    }

    private func addOverlay() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .gif]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a picture or an animated GIF"
        guard panel.runModal() == .OK, let url = panel.url, let loaded = OverlayLoader.load(url) else { return }
        overlays.append(OverlayItem(name: url.lastPathComponent, frames: loaded.frames, delays: loaded.delays, length: min(3, max(1, duration))))
    }

    private func pasteOverlay() {
        guard let image = PhotoCanvas.pasted(), let cg = OverlayLoader.cg(image) else { message = "There is no picture on the clipboard. Copy one first."; return }
        overlays.append(OverlayItem(name: "Pasted picture", frames: [cg], delays: [1], length: min(3, max(1, duration))))
    }

    private func grabFrame() async {
        guard let url = sourceURL else { return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1100, height: 1100)
        if let result = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)) {
            frame = NSImage(cgImage: result.image, size: NSSize(width: result.image.width, height: result.image.height))
        }
    }

    // MARK: Preview

    private func preview() -> NSImage? {
        guard let frame else { return nil }
        let size = frame.size
        let logoPicture = logoOn ? logoImage : nil
        let rep = PhotoCanvas.bitmap(width: Int(size.width), height: Int(size.height)) { canvas in
            frame.draw(in: NSRect(origin: .zero, size: canvas), from: .zero, operation: .copy, fraction: 1)
            if let logoPicture {
                let box = OverlayLoader.rect(anchor: logoAnchor, canvas: canvas, image: logoPicture.size, size: logoSize, gap: logoGap)
                logoPicture.draw(in: box, from: .zero, operation: .sourceOver, fraction: CGFloat(logoOpacity))
            }
            for item in overlays where time >= item.start && time <= item.start + item.length {
                guard let first = item.frames.first else { continue }
                let box = OverlayLoader.rect(anchor: item.anchor, canvas: canvas, image: CGSize(width: first.width, height: first.height), size: item.size, gap: 0.03)
                NSImage(cgImage: first, size: NSSize(width: first.width, height: first.height)).draw(in: box, from: .zero, operation: .sourceOver, fraction: CGFloat(item.opacity))
            }
        }
        return PhotoCanvas.image(rep)
    }

    // MARK: Export

    private func number(_ value: Double) -> NSNumber { NSNumber(value: value) }

    private func fade(start: Double, end: Double, total: Double, alpha: Double) -> CAKeyframeAnimation {
        let edge = min(0.3, (end - start) / 2)
        let whole = max(total, 0.1)
        func key(_ seconds: Double) -> NSNumber { number(min(1, max(0, seconds / whole))) }
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [number(0), number(0), number(alpha), number(alpha), number(0), number(0)]
        animation.keyTimes = [number(0), key(start), key(start + edge), key(end - edge), key(end), number(1)]
        animation.calculationMode = .linear
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.duration = whole
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
        return animation
    }

    private func export(toDesktop: Bool) async {
        busy = true
        message = "Making the video\u{2026}"
        defer { busy = false }
        do {
            guard let url = sourceURL else { throw OverlayError(text: "Choose a video first.") }
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw OverlayError(text: "This file has no video.") }
            let length = try await asset.load(.duration)
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let rate = try await track.load(.nominalFrameRate)
            let bounds = CGRect(origin: .zero, size: natural).applying(transform)
            let size = CGSize(width: abs(bounds.width).rounded(), height: abs(bounds.height).rounded())
            let total = CMTimeGetSeconds(length)

            let composition = AVMutableComposition()
            guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw OverlayError(text: "The video could not be prepared.") }
            let range = CMTimeRange(start: .zero, duration: length)
            try videoTrack.insertTimeRange(range, of: track, at: .zero)
            if let sound = try await asset.loadTracks(withMediaType: .audio).first,
               let soundTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try soundTrack.insertTimeRange(range, of: sound, at: .zero)
            }
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layerInstruction.setTransform(transform, at: .zero)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = range
            instruction.layerInstructions = [layerInstruction]
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = size
            videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(24, min(60, Int(rate.rounded())))))
            videoComposition.instructions = [instruction]

            let parent = CALayer()
            parent.frame = CGRect(origin: .zero, size: size)
            let videoLayer = CALayer()
            videoLayer.frame = parent.frame
            parent.addSublayer(videoLayer)

            if logoOn, let picture = logoImage, let cg = OverlayLoader.cg(picture) {
                let layer = CALayer()
                layer.contents = cg
                layer.contentsGravity = .resizeAspect
                layer.frame = OverlayLoader.rect(anchor: logoAnchor, canvas: size, image: CGSize(width: cg.width, height: cg.height), size: logoSize, gap: logoGap)
                layer.opacity = Float(logoOpacity)
                parent.addSublayer(layer)
            }
            for item in overlays {
                guard let first = item.frames.first else { continue }
                let layer = CALayer()
                layer.contents = first
                layer.contentsGravity = .resizeAspect
                layer.frame = OverlayLoader.rect(anchor: item.anchor, canvas: size, image: CGSize(width: first.width, height: first.height), size: item.size, gap: 0.03)
                layer.opacity = 0
                let end = min(total, item.start + item.length)
                layer.add(fade(start: item.start, end: end, total: total, alpha: item.opacity), forKey: "fade")
                if item.animated {
                    let loop = max(0.1, item.delays.reduce(0, +))
                    var times: [NSNumber] = [], passed = 0.0
                    for delay in item.delays { times.append(number(passed / loop)); passed += delay }
                    times.append(number(1))
                    let play = CAKeyframeAnimation(keyPath: "contents")
                    play.values = item.frames.map { $0 as Any }
                    play.keyTimes = times
                    play.calculationMode = .discrete
                    play.beginTime = AVCoreAnimationBeginTimeAtZero + item.start
                    play.duration = loop
                    play.repeatDuration = max(0.1, end - item.start)
                    play.isRemovedOnCompletion = false
                    layer.add(play, forKey: "play")
                }
                parent.addSublayer(layer)
            }
            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)

            try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
            let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let stem = (title.isEmpty ? "watermarked" : title).lowercased().replacingOccurrences(of: "[^a-z0-9_-]+", with: "-", options: .regularExpression)
            let output = attachmentDirectory.appendingPathComponent(stem + "-" + String(UUID().uuidString.prefix(6)) + ".mp4")
            guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw OverlayError(text: "This video cannot be exported on this Mac.") }
            session.videoComposition = videoComposition
            session.outputURL = output
            session.outputFileType = .mp4
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.exportAsynchronously {
                    if session.status == .completed { continuation.resume() }
                    else { continuation.resume(throwing: session.error ?? OverlayError(text: "The video could not be exported.")) }
                }
            }
            let key = normalizedTrigger("/" + stem + "-" + String(UUID().uuidString.prefix(4)).lowercased())
            let made = Clip(key: key, name: title.isEmpty ? output.deletingPathExtension().lastPathComponent : title,
                            text: "Watermark and overlays", group: "Sound & media", files: [output.path], directMediaPaste: true)
            if toDesktop { onExport(made); message = "Saved to the Desktop as \(output.lastPathComponent)." }
            else { onSave(made); message = "Saved as \(displayTrigger(made.key))." }
        } catch {
            message = "Could not make the video: \(error.localizedDescription)"
        }
    }
}
