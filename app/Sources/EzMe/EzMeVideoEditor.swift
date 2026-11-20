// Video Editor: cut a clip (the old Video Cutter), join clips into one, and put a filter on a picture or a video.
import SwiftUI
import AVFoundation
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import AppKit

// MARK: - Small helpers

private func editorIsVideo(_ url: URL) -> Bool {
    ["mp4", "mov", "m4v", "avi", "webm", "mpeg", "mpg"].contains(url.pathExtension.lowercased())
}

private func editorClock(_ seconds: Double) -> String {
    let whole = max(0, Int(seconds.isFinite ? seconds : 0))
    return String(format: "%d:%02d", whole / 60, whole % 60)
}

/// A shortcut key that nothing else uses yet.
private func editorFreeKey(_ raw: String, fallback: String, in clips: [Clip]) -> String {
    let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ ")).lowercased()
        .replacingOccurrences(of: "[^a-z0-9_-]+", with: "-", options: .regularExpression)
    let base = cleaned.isEmpty ? fallback : cleaned
    var key = normalizedTrigger("/" + base)
    var serial = 2
    while clips.contains(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
        key = normalizedTrigger("/" + base + "-\(serial)")
        serial += 1
    }
    return key
}

private struct EditorError: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

private func editorExport(_ session: AVAssetExportSession, to url: URL) async throws {
    session.outputURL = url
    session.outputFileType = .mp4
    session.shouldOptimizeForNetworkUse = true
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        session.exportAsynchronously {
            if session.status == .completed { continuation.resume() }
            else { continuation.resume(throwing: session.error ?? EditorError(text: "The video could not be exported.")) }
        }
    }
}

// MARK: - The editor with its three modes

@MainActor struct VideoEditorView: View {
    var clips: [Clip]
    var attachmentDirectory: URL
    var onSave: (Clip) -> Void
    var onExport: (Clip) -> Void
    var initialPath: String? = nil
    @State private var mode = "Cut"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Text("Video Editor").font(.system(size: 22, weight: .bold, design: .rounded))
                Picker("", selection: $mode) {
                    Text("Cut").tag("Cut")
                    Text("Join clips").tag("Join clips")
                    Text("Filters").tag("Filters")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 320)
                Spacer()
            }
            switch mode {
            case "Join clips":
                VideoJoinView(clips: clips, attachmentDirectory: attachmentDirectory, onSave: onSave, onExport: onExport)
            case "Filters":
                VideoFilterView(clips: clips, attachmentDirectory: attachmentDirectory, onSave: onSave, onExport: onExport)
            default:
                VideoCutterView(clips: clips, attachmentDirectory: attachmentDirectory, onSave: onSave, onExport: onExport, initialPath: initialPath)
            }
        }
    }
}

// MARK: - Join clips

@MainActor struct VideoJoinView: View {
    var clips: [Clip]
    var attachmentDirectory: URL
    var onSave: (Clip) -> Void
    var onExport: (Clip) -> Void

    @State private var items: [URL] = []
    @State private var lengths: [String: Double] = [:]
    @State private var name = "Joined video"
    @State private var code = "joined"
    @State private var saveTo = "Save as shortcut"
    @State private var busy = false
    @State private var message = ""

    private var videoShortcuts: [Clip] {
        clips.filter { clip in clip.files.contains { editorIsVideo(URL(fileURLWithPath: $0)) && FileManager.default.fileExists(atPath: $0) } }
    }

    private var totalLength: Double { items.reduce(0) { $0 + (lengths[$1.path] ?? 0) } }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button { addFiles() } label: { Label("Add videos\u{2026}", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(Butter.coral)
                    Menu {
                        ForEach(videoShortcuts) { clip in
                            Button("\(displayTrigger(clip.key)) \u{00B7} \(clip.name)") { add(clip.files.map { URL(fileURLWithPath: $0) }.filter { editorIsVideo($0) }) }
                        }
                    } label: { Label("From shortcut", systemImage: "command") }
                    .disabled(videoShortcuts.isEmpty)
                    Spacer()
                    if !items.isEmpty { Text("\(items.count) clips \u{00B7} \(editorClock(totalLength))").font(.caption).foregroundStyle(.secondary) }
                }
                if items.isEmpty {
                    ContentUnavailableView("Add the clips to join", systemImage: "film.stack",
                                           description: Text("They play one after another in the order shown. Move a clip up or down to change the order."))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(items.enumerated()), id: \.element.path) { index, url in row(index, url) }
                        }
                    }
                    .frame(minHeight: 300, maxHeight: 520)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 10) {
                Text("Name your joined video").font(.headline)
                Text("Shortcut code").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("joined", text: $code).textFieldStyle(.roundedBorder).font(.system(size: 14, weight: .semibold, design: .monospaced))
                Text("Displayed name").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                Picker("Save as", selection: $saveTo) {
                    Text("Shortcut").tag("Save as shortcut")
                    Text("Desktop file").tag("Save to Desktop")
                }.pickerStyle(.segmented)
                Button { Task { await join() } } label: { Label(busy ? "Joining\u{2026}" : "Join and save", systemImage: "link") }
                    .buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.large).disabled(busy || items.count < 2)
                if busy { ProgressView().controlSize(.small) }
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
                Text("Clips of different sizes are fitted to the first clip's size, with black bars where needed.").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(14).frame(width: 300, alignment: .topLeading)
            .background(Butter.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ index: Int, _ url: URL) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)").font(.system(size: 12, weight: .bold, design: .rounded)).frame(width: 24, height: 24)
                .background(Butter.coral.opacity(0.18), in: Circle())
            Image(systemName: "play.rectangle.fill").foregroundStyle(Butter.coral)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(editorClock(lengths[url.path] ?? 0)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }.buttonStyle(.bordered).controlSize(.small).disabled(index == 0)
            Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }.buttonStyle(.bordered).controlSize(.small).disabled(index == items.count - 1)
            Button { items.remove(at: index) } label: { Image(systemName: "trash") }.buttonStyle(.bordered).controlSize(.small)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard items.indices.contains(index), items.indices.contains(target) else { return }
        items.swapAt(index, target)
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.title = "Choose the videos to join"
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    private func add(_ urls: [URL]) {
        for url in urls where !items.contains(url) {
            items.append(url)
            Task {
                let seconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
                lengths[url.path] = seconds.isFinite ? seconds : 0
            }
        }
    }

    private func join() async {
        guard items.count >= 2 else { message = "Add at least two clips to join."; return }
        busy = true
        message = "Joining \(items.count) clips\u{2026}"
        defer { busy = false }
        do {
            try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
            let composition = AVMutableComposition()
            guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw EditorError(text: "This Mac could not start the joined video.")
            }
            let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

            struct Piece { var start: CMTime; var length: CMTime; var natural: CGSize; var turn: CGAffineTransform }
            var pieces: [Piece] = []
            var cursor = CMTime.zero
            for url in items {
                let asset = AVURLAsset(url: url)
                let length = try await asset.load(.duration)
                guard let source = try await asset.loadTracks(withMediaType: .video).first else { continue }
                let natural = try await source.load(.naturalSize)
                let turn = try await source.load(.preferredTransform)
                let range = CMTimeRange(start: .zero, duration: length)
                try videoTrack.insertTimeRange(range, of: source, at: cursor)
                if let sound = try await asset.loadTracks(withMediaType: .audio).first, let audioTrack {
                    try? audioTrack.insertTimeRange(range, of: sound, at: cursor)
                }
                pieces.append(Piece(start: cursor, length: length, natural: natural, turn: turn))
                cursor = CMTimeAdd(cursor, length)
            }
            guard let first = pieces.first else { throw EditorError(text: "None of these files has a video track.") }
            let firstShown = CGRect(origin: .zero, size: first.natural).applying(first.turn)
            let canvas = CGSize(width: max(2, abs(firstShown.width).rounded()), height: max(2, abs(firstShown.height).rounded()))

            var instructions: [AVMutableVideoCompositionInstruction] = []
            for piece in pieces {
                let shown = CGRect(origin: .zero, size: piece.natural).applying(piece.turn)
                let width = max(1, abs(shown.width))
                let height = max(1, abs(shown.height))
                let scale = min(canvas.width / width, canvas.height / height)
                var fit = piece.turn
                fit = fit.concatenating(CGAffineTransform(translationX: -shown.minX, y: -shown.minY))
                fit = fit.concatenating(CGAffineTransform(scaleX: scale, y: scale))
                fit = fit.concatenating(CGAffineTransform(translationX: (canvas.width - width * scale) / 2, y: (canvas.height - height * scale) / 2))
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                layer.setTransform(fit, at: piece.start)
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: piece.start, duration: piece.length)
                instruction.layerInstructions = [layer]
                instructions.append(instruction)
            }
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = canvas
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            videoComposition.instructions = instructions

            guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                throw EditorError(text: "These clips cannot be joined on this Mac.")
            }
            session.videoComposition = videoComposition
            let stem = name.lowercased().replacingOccurrences(of: "[^a-z0-9_-]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let output = attachmentDirectory.appendingPathComponent("\(stem.isEmpty ? "joined-video" : stem)-\(UUID().uuidString.prefix(6)).mp4")
            try await editorExport(session, to: output)

            let key = editorFreeKey(code, fallback: "joined", in: clips)
            let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let made = Clip(key: key, name: title.isEmpty ? output.deletingPathExtension().lastPathComponent : title,
                            text: "\(pieces.count) clips joined", group: "Sound & media", files: [output.path], directMediaPaste: true)
            if saveTo == "Save to Desktop" { onExport(made); message = "Joined and saved to the Desktop as \(output.lastPathComponent)." }
            else { onSave(made); message = "Joined and saved as \(displayTrigger(made.key))." }
        } catch {
            message = "Could not join: \(error.localizedDescription)"
        }
    }
}

// MARK: - Filters

private enum PrismMath {
    static func controls(_ image: CIImage, saturation: Double = 1, contrast: Double = 1, brightness: Double = 0) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.saturation = Float(saturation)
        filter.contrast = Float(contrast)
        filter.brightness = Float(brightness)
        return filter.outputImage ?? image
    }

    /// 0 keeps the picture, 1 gives the changed one.
    static func mix(_ original: CIImage, _ changed: CIImage, _ amount: Double) -> CIImage {
        let filter = CIFilter.dissolveTransition()
        filter.inputImage = original
        filter.targetImage = changed
        filter.time = Float(max(0, min(1, amount)))
        return (filter.outputImage ?? changed).cropped(to: original.extent)
    }

    static func tint(_ image: CIImage, red: Double, green: Double, blue: Double) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: CGFloat(red), y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: CGFloat(green), z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: CGFloat(blue), w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filter.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return filter.outputImage ?? image
    }

    static func blur(_ image: CIImage, radius: Double) -> CIImage {
        guard radius > 0.05 else { return image }
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = image.clampedToExtent()
        filter.radius = Float(radius)
        return (filter.outputImage ?? image).cropped(to: image.extent)
    }
}

struct PrismFilter: Identifiable {
    let id: String
    let name: String
    let category: String
    let tagline: String
    /// What the slider changes, for example "Desaturation".
    let parameter: String
    let unit: String
    let range: ClosedRange<Double>
    let start: Double
    let apply: (CIImage, Double) -> CIImage
    let css: (Double) -> String

    func readout(_ value: Double) -> String { "\(Int(value.rounded()))\(unit)" }

    static let all: [PrismFilter] = [
        PrismFilter(id: "grayscale", name: "Grayscale", category: "Tone", tagline: "Pure black and white, from a hint of grey to none of the colour.",
                    parameter: "Desaturation", unit: "%", range: 0...100, start: 100,
                    apply: { image, value in PrismMath.controls(image, saturation: 1 - value / 100) },
                    css: { value in "grayscale(\(Int(value))%)" }),
        PrismFilter(id: "soft", name: "Soft Focus", category: "Glow", tagline: "A dreamy diffusion bloom that softens edges and lifts highlights.",
                    parameter: "Diffusion blur", unit: "px", range: 0...30, start: 8,
                    apply: { image, value in
                        let blurred = PrismMath.controls(PrismMath.blur(image, radius: value), brightness: 0.03)
                        return PrismMath.mix(image, blurred, 0.6)
                    },
                    css: { value in "blur(\(Int(value))px) brightness(1.05)" }),
        PrismFilter(id: "invert", name: "Invert", category: "Colour", tagline: "Flips every colour to its opposite, like a photographic negative.",
                    parameter: "Inversion", unit: "%", range: 0...100, start: 100,
                    apply: { image, value in
                        let negative = CIFilter.colorInvert()
                        negative.inputImage = image
                        return PrismMath.mix(image, negative.outputImage ?? image, value / 100)
                    },
                    css: { value in "invert(\(Int(value))%)" }),
        PrismFilter(id: "hue", name: "Hue Shift", category: "Colour", tagline: "Turns the whole colour wheel, so skies go purple and leaves go gold.",
                    parameter: "Hue angle", unit: "\u{00B0}", range: 0...360, start: 90,
                    apply: { image, value in
                        let filter = CIFilter.hueAdjust()
                        filter.inputImage = image
                        filter.angle = Float(value * Double.pi / 180)
                        return filter.outputImage ?? image
                    },
                    css: { value in "hue-rotate(\(Int(value))deg)" }),
        PrismFilter(id: "sepia", name: "Vintage Sepia", category: "Film", tagline: "Warm brown tones from an old photograph.",
                    parameter: "Sepia intensity", unit: "%", range: 0...100, start: 85,
                    apply: { image, value in
                        let filter = CIFilter.sepiaTone()
                        filter.inputImage = image
                        filter.intensity = Float(value / 100)
                        return filter.outputImage ?? image
                    },
                    css: { value in "sepia(\(Int(value))%)" }),
        PrismFilter(id: "neon", name: "Neon Cyber", category: "Glow", tagline: "Hot, saturated colour with a little electric glow.",
                    parameter: "Saturation", unit: "%", range: 100...300, start: 190,
                    apply: { image, value in
                        let vivid = PrismMath.controls(image, saturation: value / 100, contrast: 1.15)
                        let glow = CIFilter.bloom()
                        glow.inputImage = vivid
                        glow.radius = 8
                        glow.intensity = 0.45
                        return (glow.outputImage ?? vivid).cropped(to: image.extent)
                    },
                    css: { value in "saturate(\(Int(value))%) contrast(115%)" }),
        PrismFilter(id: "contrast", name: "High Contrast", category: "Tone", tagline: "Deeper darks and brighter lights for a punchy, bold look.",
                    parameter: "Contrast", unit: "%", range: 100...250, start: 160,
                    apply: { image, value in PrismMath.controls(image, contrast: value / 100) },
                    css: { value in "contrast(\(Int(value))%)" }),
        PrismFilter(id: "noir", name: "Dark Noir", category: "Film", tagline: "Moody black and white with deep shadows.",
                    parameter: "Noir strength", unit: "%", range: 0...100, start: 100,
                    apply: { image, value in
                        let filter = CIFilter.photoEffectNoir()
                        filter.inputImage = image
                        return PrismMath.mix(image, filter.outputImage ?? image, value / 100)
                    },
                    css: { value in "grayscale(\(Int(value))%) contrast(\(100 + Int(value * 0.3))%) brightness(\(100 - Int(value * 0.2))%)" }),
        PrismFilter(id: "golden", name: "Golden Hour", category: "Warm", tagline: "The soft amber light just before sunset.",
                    parameter: "Warmth", unit: "%", range: 0...100, start: 70,
                    apply: { image, value in
                        let amount = value / 100
                        let warm = PrismMath.tint(image, red: 1 + 0.25 * amount, green: 1 + 0.08 * amount, blue: 1 - 0.25 * amount)
                        return PrismMath.controls(warm, saturation: 1 + 0.15 * amount, brightness: 0.02 * amount)
                    },
                    css: { value in "sepia(\(Int(value * 0.35))%) saturate(\(100 + Int(value * 0.2))%) brightness(\(100 + Int(value * 0.05))%)" }),
        PrismFilter(id: "arctic", name: "Arctic Frost", category: "Cool", tagline: "Crisp, icy blues and a clean winter look.",
                    parameter: "Chill", unit: "%", range: 0...100, start: 70,
                    apply: { image, value in
                        let amount = value / 100
                        let cold = PrismMath.tint(image, red: 1 - 0.2 * amount, green: 1 + 0.02 * amount, blue: 1 + 0.25 * amount)
                        return PrismMath.controls(cold, saturation: 1 - 0.2 * amount, brightness: 0.03 * amount)
                    },
                    css: { value in "hue-rotate(\(Int(value * 0.4))deg) saturate(\(100 - Int(value * 0.2))%) brightness(\(100 + Int(value * 0.05))%)" })
    ]
}

private let prismContext = CIContext()

/// Four pictures to try the filters on before you open your own.
private enum PrismSamples {
    static let names = ["Sunset", "Neon alley", "Portrait", "Shapes"]

    static func make(_ index: Int) -> NSImage {
        let size = NSSize(width: 1200, height: 800)
        let image = NSImage(size: size)
        image.lockFocus()
        let full = NSRect(origin: .zero, size: size)
        switch index {
        case 0:
            NSGradient(colors: [NSColor(red: 0.98, green: 0.62, blue: 0.2, alpha: 1), NSColor(red: 0.86, green: 0.3, blue: 0.35, alpha: 1), NSColor(red: 0.22, green: 0.15, blue: 0.4, alpha: 1)])?.draw(in: full, angle: 90)
            NSColor(red: 1, green: 0.93, blue: 0.6, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 470, y: 300, width: 260, height: 260)).fill()
            NSColor(red: 0.1, green: 0.08, blue: 0.2, alpha: 1).setFill()
            let hills = NSBezierPath()
            hills.move(to: NSPoint(x: 0, y: 0)); hills.line(to: NSPoint(x: 0, y: 220))
            hills.curve(to: NSPoint(x: 500, y: 200), controlPoint1: NSPoint(x: 150, y: 330), controlPoint2: NSPoint(x: 330, y: 120))
            hills.curve(to: NSPoint(x: 1200, y: 250), controlPoint1: NSPoint(x: 760, y: 300), controlPoint2: NSPoint(x: 980, y: 140))
            hills.line(to: NSPoint(x: 1200, y: 0)); hills.close(); hills.fill()
        case 1:
            NSGradient(colors: [NSColor(red: 0.05, green: 0.02, blue: 0.15, alpha: 1), NSColor(red: 0.15, green: 0.05, blue: 0.3, alpha: 1)])?.draw(in: full, angle: 90)
            let glows: [NSColor] = [.systemPink, .cyan, .systemPurple, .systemTeal]
            for step in 0..<7 {
                glows[step % glows.count].withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: NSRect(x: 60 + step * 165, y: 140, width: 70, height: 520 - (step % 3) * 90), xRadius: 8, yRadius: 8).fill()
            }
            NSColor(white: 0.05, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 1200, height: 120).fill()
        case 2:
            NSGradient(colors: [NSColor(red: 0.85, green: 0.78, blue: 0.7, alpha: 1), NSColor(red: 0.6, green: 0.52, blue: 0.48, alpha: 1)])?.draw(in: full, angle: 90)
            NSColor(red: 0.93, green: 0.76, blue: 0.64, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 470, y: 250, width: 260, height: 330)).fill()
            NSColor(red: 0.2, green: 0.25, blue: 0.4, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 380, y: -80, width: 440, height: 400), xRadius: 160, yRadius: 160).fill()
            NSColor(red: 0.25, green: 0.15, blue: 0.1, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 460, y: 460, width: 280, height: 150)).fill()
        default:
            NSColor(white: 0.93, alpha: 1).setFill()
            full.fill()
            let colours: [NSColor] = [.systemRed, .systemBlue, .systemYellow, .systemGreen]
            NSBezierPath(rect: NSRect(x: 120, y: 120, width: 360, height: 360)).addClip()
            colours[1].setFill(); NSRect(x: 120, y: 120, width: 360, height: 360).fill()
            NSGraphicsContext.current?.cgContext.resetClip()
            colours[0].setFill(); NSBezierPath(ovalIn: NSRect(x: 560, y: 240, width: 440, height: 440)).fill()
            colours[2].setFill()
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: 220, y: 700)); triangle.line(to: NSPoint(x: 520, y: 700)); triangle.line(to: NSPoint(x: 370, y: 520)); triangle.close(); triangle.fill()
            colours[3].setFill(); NSRect(x: 760, y: 60, width: 300, height: 120).fill()
        }
        image.unlockFocus()
        return image
    }
}

@MainActor struct VideoFilterView: View {
    var clips: [Clip]
    var attachmentDirectory: URL
    var onSave: (Clip) -> Void
    var onExport: (Clip) -> Void

    @State private var sourceURL: URL?
    @State private var base: CIImage?
    @State private var sourceLabel = "Sample: Sunset"
    @State private var stamp = 0
    @State private var duration = 0.0
    @State private var frameTime = 0.0

    @State private var selected = PrismFilter.all[0].id
    @State private var amounts: [String: Double] = [:]
    @State private var shown: NSImage?
    @State private var thumbs: [String: NSImage] = [:]
    @State private var comparing = false
    @State private var fullScreen = false

    @State private var name = "Filtered"
    @State private var code = "filtered"
    @State private var saveTo = "Save as shortcut"
    @State private var busy = false
    @State private var message = ""

    private var filter: PrismFilter { PrismFilter.all.first { $0.id == selected } ?? PrismFilter.all[0] }
    private var amount: Double { amounts[selected] ?? filter.start }
    private var isVideoSource: Bool { sourceURL.map { editorIsVideo($0) } ?? false }
    private var mediaShortcuts: [Clip] {
        clips.filter { clip in clip.files.contains { FileManager.default.fileExists(atPath: $0) && (editorIsVideo(URL(fileURLWithPath: $0)) || NSImage(contentsOfFile: $0) != nil) } }
    }
    private var original: NSImage? { base.flatMap { image(from: $0) } }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 12) {
                sourceBar
                previewArea
                carousel
            }
            .frame(maxWidth: .infinity)
            inspector.frame(width: 300)
        }
        .padding(14)
        .focusable()
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .task { if base == nil { useSample(0) } }
        .task(id: "\(selected)-\(Int(amount * 10))-\(stamp)") { await refresh() }
        .task(id: stamp) { await makeThumbs() }
        .sheet(isPresented: $fullScreen) { fullView }
    }

    // MARK: Pieces

    private var sourceBar: some View {
        HStack(spacing: 8) {
            Button { openFile() } label: { Label("Upload", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent).tint(Butter.coral)
            Menu {
                ForEach(mediaShortcuts) { clip in
                    Button("\(displayTrigger(clip.key)) \u{00B7} \(clip.name)") {
                        if let path = clip.files.first(where: { FileManager.default.fileExists(atPath: $0) && (editorIsVideo(URL(fileURLWithPath: $0)) || NSImage(contentsOfFile: $0) != nil) }) { load(URL(fileURLWithPath: path)) }
                    }
                }
            } label: { Label("From shortcut", systemImage: "command") }
            .disabled(mediaShortcuts.isEmpty)
            Menu {
                ForEach(PrismSamples.names.indices, id: \.self) { index in Button(PrismSamples.names[index]) { useSample(index) } }
            } label: { Label("Samples", systemImage: "photo.on.rectangle") }
            Spacer()
            Text(sourceLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var previewArea: some View {
        VStack(spacing: 8) {
            ZStack {
                Color.black.opacity(0.9)
                if let picture = (comparing ? original : shown) ?? shown {
                    Image(nsImage: picture).resizable().scaledToFit().padding(6)
                } else {
                    ProgressView()
                }
                if comparing {
                    Text("ORIGINAL").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Color.black.opacity(0.6)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(12)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 430)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 10) {
                Label("Hold to compare", systemImage: "square.split.2x1")
                    .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(comparing ? Butter.coral.opacity(0.25) : Color(nsColor: .controlBackgroundColor), in: Capsule())
                    .overlay(Capsule().stroke(Butter.coral.opacity(0.5)))
                    .onLongPressGesture(minimumDuration: 0, maximumDistance: 60, pressing: { comparing = $0 }, perform: {})
                    .help("Press and hold to see the original")
                Button { fullScreen = true } label: { Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") }.buttonStyle(.bordered)
                Spacer()
                if isVideoSource, duration > 0 {
                    Text("Preview frame").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $frameTime, in: 0...max(0.1, duration), onEditingChanged: { editing in if !editing { reloadFrame() } }).frame(width: 160)
                    Text(editorClock(frameTime)).font(.system(.caption, design: .monospaced))
                }
            }
        }
    }

    private var carousel: some View {
        HStack(spacing: 6) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.bordered)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(PrismFilter.all) { item in
                            Button { selected = item.id } label: {
                                VStack(spacing: 5) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.92))
                                        if let thumb = thumbs[item.id] { Image(nsImage: thumb).resizable().scaledToFill() }
                                    }
                                    .frame(width: 92, height: 68).clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected == item.id ? Butter.coral : Color.secondary.opacity(0.25), lineWidth: selected == item.id ? 3 : 1))
                                    Text(item.name).font(.system(size: 11, weight: selected == item.id ? .bold : .regular)).lineLimit(1).frame(width: 96)
                                }
                            }
                            .buttonStyle(.plain).id(item.id)
                        }
                    }
                    .padding(.vertical, 3).padding(.horizontal, 2)
                }
                .onChange(of: selected) { value in withAnimation { proxy.scrollTo(value, anchor: .center) } }
            }
            Button { step(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.bordered)
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(filter.category.uppercased()).font(.system(size: 10, weight: .heavy)).foregroundStyle(Butter.coral)
            Text(filter.name).font(.system(size: 24, weight: .bold, design: .rounded))
            Text(filter.tagline).font(.callout).foregroundStyle(.secondary)
            Divider()
            HStack {
                Text(filter.parameter).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(filter.readout(amount)).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(Butter.coral)
            }
            Slider(value: Binding(get: { amount }, set: { amounts[selected] = $0 }), in: filter.range).tint(Butter.coral)
            HStack(spacing: 6) {
                ForEach([25, 50, 75, 100], id: \.self) { percent in
                    Button("\(percent)%") {
                        let low = filter.range.lowerBound, high = filter.range.upperBound
                        amounts[selected] = low + (high - low) * Double(percent) / 100
                    }.buttonStyle(.bordered).controlSize(.small)
                }
                Spacer()
                Button("Reset") { amounts[selected] = filter.start }.buttonStyle(.plain).font(.caption).foregroundStyle(Butter.coral)
            }
            Text("CSS filter").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("filter: \(filter.css(amount));").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            Divider()
            Text("Save").font(.headline)
            TextField("Shortcut code", text: $code).textFieldStyle(.roundedBorder).font(.system(size: 13, design: .monospaced))
            TextField("Displayed name", text: $name).textFieldStyle(.roundedBorder)
            Picker("", selection: $saveTo) {
                Text("Shortcut").tag("Save as shortcut")
                Text("Desktop file").tag("Save to Desktop")
            }.pickerStyle(.segmented).labelsHidden()
            Button { Task { await save() } } label: { Label(busy ? "Saving\u{2026}" : (isVideoSource ? "Export filtered video" : "Export picture"), systemImage: "square.and.arrow.down") }
                .buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.large).disabled(busy || base == nil)
            if busy { ProgressView().controlSize(.small) }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(14)
        .background(Butter.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }

    private var fullView: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            if let picture = shown { Image(nsImage: picture).resizable().scaledToFit().padding(20) }
            Button("Close") { fullScreen = false }.buttonStyle(.borderedProminent).tint(Butter.coral).padding(16)
        }
        .frame(minWidth: 900, minHeight: 640)
    }

    // MARK: Picking and showing

    private func step(_ delta: Int) {
        guard let index = PrismFilter.all.firstIndex(where: { $0.id == selected }) else { return }
        let next = (index + delta + PrismFilter.all.count) % PrismFilter.all.count
        selected = PrismFilter.all[next].id
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a picture or a video"
        panel.allowedContentTypes = [.image, .movie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    private func useSample(_ index: Int) {
        let picture = PrismSamples.make(index)
        guard let data = picture.tiffRepresentation, let ci = CIImage(data: data) else { return }
        sourceURL = nil
        duration = 0
        base = ci
        sourceLabel = "Sample: \(PrismSamples.names[index])"
        name = "Filtered"
        stamp += 1
    }

    private func load(_ url: URL) {
        message = ""
        if editorIsVideo(url) {
            sourceURL = url
            sourceLabel = url.lastPathComponent
            frameTime = 0
            Task {
                duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
                await grabFrame()
            }
        } else if let ci = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) {
            sourceURL = url
            duration = 0
            base = ci
            sourceLabel = url.lastPathComponent
            stamp += 1
        } else {
            message = "That file could not be opened."
        }
        name = url.deletingPathExtension().lastPathComponent + " filtered"
    }

    private func reloadFrame() { Task { await grabFrame() } }

    private func grabFrame() async {
        guard let url = sourceURL, editorIsVideo(url) else { return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        do {
            let result = try await generator.image(at: CMTime(seconds: frameTime, preferredTimescale: 600))
            base = CIImage(cgImage: result.image)
            stamp += 1
        } catch {
            message = "Could not read a frame from this video."
        }
    }

    /// A smaller copy of the picture, so every change on the slider feels instant.
    private func previewBase(maxSide: CGFloat) -> CIImage? {
        guard let base else { return nil }
        let longest = max(base.extent.width, base.extent.height)
        guard longest > maxSide else { return base }
        let scale = maxSide / longest
        return base.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private func image(from ci: CIImage) -> NSImage? {
        guard let cg = prismContext.createCGImage(ci, from: ci.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: ci.extent.width, height: ci.extent.height))
    }

    private func refresh() async {
        guard let small = previewBase(maxSide: 1100) else { return }
        let changed = filter.apply(small, amount)
        shown = image(from: changed.cropped(to: small.extent))
    }

    private func makeThumbs() async {
        guard let tiny = previewBase(maxSide: 160) else { return }
        var made: [String: NSImage] = [:]
        for item in PrismFilter.all {
            let changed = item.apply(tiny, item.start).cropped(to: tiny.extent)
            if let picture = image(from: changed) { made[item.id] = picture }
            await Task.yield()
        }
        thumbs = made
    }

    // MARK: Saving

    private func save() async {
        busy = true
        message = isVideoSource ? "Filtering the video\u{2026}" : "Saving the picture\u{2026}"
        defer { busy = false }
        do {
            try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
            let stem = name.lowercased().replacingOccurrences(of: "[^a-z0-9_-]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let fileStem = (stem.isEmpty ? "filtered" : stem) + "-" + String(UUID().uuidString.prefix(6))
            let chosen = filter
            let strength = amount
            let output: URL
            if isVideoSource, let url = sourceURL {
                output = attachmentDirectory.appendingPathComponent(fileStem + ".mp4")
                let asset = AVURLAsset(url: url)
                let composition = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
                    let source = request.sourceImage.clampedToExtent()
                    let changed = chosen.apply(source, strength).cropped(to: request.sourceImage.extent)
                    request.finish(with: changed, context: nil)
                })
                guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                    throw EditorError(text: "This video cannot be filtered on this Mac.")
                }
                session.videoComposition = composition
                try await editorExport(session, to: output)
            } else {
                guard let full = previewBase(maxSide: 4096) else { throw EditorError(text: "Open a picture first.") }
                let changed = chosen.apply(full, strength).cropped(to: full.extent)
                guard let cg = prismContext.createCGImage(changed, from: changed.extent) else { throw EditorError(text: "The picture could not be made.") }
                let rep = NSBitmapImageRep(cgImage: cg)
                guard let png = rep.representation(using: .png, properties: [:]) else { throw EditorError(text: "The picture could not be saved.") }
                output = attachmentDirectory.appendingPathComponent(fileStem + ".png")
                try png.write(to: output, options: .atomic)
            }
            let key = editorFreeKey(code, fallback: "filtered", in: clips)
            let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let made = Clip(key: key, name: title.isEmpty ? output.deletingPathExtension().lastPathComponent : title,
                            text: "\(chosen.name) \(chosen.readout(strength))", group: "Sound & media", files: [output.path], directMediaPaste: true)
            if saveTo == "Save to Desktop" { onExport(made); message = "Saved to the Desktop as \(output.lastPathComponent)." }
            else { onSave(made); message = "Saved as \(displayTrigger(made.key))." }
        } catch {
            message = "Could not save: \(error.localizedDescription)"
        }
    }
}
