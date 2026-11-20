// Backgrounds: change a background's colour when it can be changed (a flat colour, or a PNG with a transparent
// background), and ask ChatGPT or Gemini for new background pictures. A flat photo cannot change colour.
import SwiftUI
import AppKit

@MainActor enum TemplateBackground {
    struct Info { var transparent: Bool; var flat: Bool }
    private static var cache: [String: Info] = [:]

    static func clearCache() { cache = [:] }

    static func analyse(_ image: NSImage) -> Info {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return Info(transparent: false, flat: false) }
        let n = 48
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let made: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard made else { return Info(transparent: false, flat: false) }
        var clear = 0
        var low = [255, 255, 255], high = [0, 0, 0]
        for index in 0..<(n * n) {
            if pixels[index * 4 + 3] < 235 { clear += 1 }
            for channel in 0..<3 {
                let value = Int(pixels[index * 4 + channel])
                low[channel] = min(low[channel], value); high[channel] = max(high[channel], value)
            }
        }
        let transparent = clear * 100 >= n * n * 2
        let flat = !transparent && (0..<3).allSatisfy { high[$0] - low[$0] <= 6 }
        return Info(transparent: transparent, flat: flat)
    }

    private static func key(_ template: ImageTemplate) -> String { "\(template.file)|\(template.originalFile)|\(template.pixelWidth)x\(template.pixelHeight)" }

    /// True when the background colour can be changed: a flat colour, or a PNG with a transparent background.
    static func canRecolour(_ template: ImageTemplate) -> Bool {
        let id = key(template)
        if let known = cache[id] { return known.transparent || known.flat }
        let store = TemplateStore.shared
        var info = Info(transparent: false, flat: false)
        if let original = store.original(for: template), analyse(original).transparent { info = Info(transparent: true, flat: false) }
        else if let base = store.basePicture(for: template) { info = analyse(base) }
        cache[id] = info
        return info.transparent || info.flat
    }

    private static func render(art: NSImage?, size: CGSize, hex: String) -> NSImage? {
        guard let rep = TemplateImages.bitmap(width: Int(size.width), height: Int(size.height)),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(templateHex: hex).setFill()
        NSRect(x: 0, y: 0, width: size.width, height: size.height).fill()
        art?.draw(in: NSRect(x: 0, y: 0, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: size.width, height: size.height))
        image.addRepresentation(rep)
        return image
    }

    /// A transparent PNG over the colour; any other picture as it is.
    static func composite(_ art: NSImage, hex: String) -> NSImage? {
        guard analyse(art).transparent else { return art }
        return render(art: art, size: TemplateImages.pixelSize(art), hex: hex)
    }

    static let cannot = "This background is a flat picture, so its colour cannot change. Upload a PNG with a transparent background to change colours."

    /// The background in a new colour: the transparent PNG over the colour, or a new flat colour. Otherwise nothing, with the reason.
    static func recoloured(_ template: ImageTemplate, hex: String) -> (image: NSImage?, message: String) {
        let store = TemplateStore.shared
        if let original = store.original(for: template), analyse(original).transparent {
            let image = render(art: original, size: TemplateImages.pixelSize(original), hex: hex)
            return (image, image == nil ? "Could not change the colour." : "")
        }
        if let base = store.basePicture(for: template), analyse(base).flat {
            let image = render(art: nil, size: TemplateImages.pixelSize(base), hex: hex)
            return (image, image == nil ? "Could not change the colour." : "")
        }
        return (nil, cannot)
    }
}

// MARK: - Ask ChatGPT or Gemini for backgrounds

struct BackgroundIdeasSheet: View {
    let appName: String
    var width = 1600
    var height = 1000
    @Environment(\.dismiss) private var dismiss
    @State private var theme = ""
    @State private var count = 3
    @State private var transparent = true
    @State private var prompt = ""
    @State private var status = ""

    private var shape: String {
        let ratio = Double(width) / Double(max(1, height))
        return ratio > 1.15 ? "wide landscape (about \(width) by \(height) pixels)" : ratio < 0.87 ? "tall portrait (about \(width) by \(height) pixels)" : "square"
    }

    private func build() {
        let about = theme.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = "Create \(count) different background images for a greeting card app called \u{201C}\(appName)\u{201D}"
        if !about.isEmpty { text += ". Theme: \(about)" }
        text += ".\n\nRules for every image:\n- \(shape).\n- No text, no letters, no logos and no people's faces.\n- Keep the middle calm and mostly empty, because names and messages will be placed on top.\n- Make it high resolution.\n"
        if transparent {
            text += "- Save each one as a PNG with a TRANSPARENT background: only the decoration (borders, flowers, patterns, shapes) is drawn and the rest is fully transparent, so I can put any colour behind it.\n"
        } else {
            text += "- Save each one as a PNG.\n"
        }
        text += "\nGive me the \(count) images one by one so I can download them."
        prompt = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "photo.badge.plus").foregroundStyle(Butter.coral).font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Get background pictures with ChatGPT or Gemini").font(.system(size: 16, weight: .bold)).foregroundStyle(Butter.cocoa)
                    Text("Download the one you like, then press Replace background and choose it.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            TextField("What should it look like? Like: Diwali, pink and gold flowers", text: $theme).textFieldStyle(.roundedBorder).onChange(of: theme) { _, _ in build() }
            HStack(spacing: 12) {
                Stepper("Pictures: \(count)", value: $count, in: 1...5).onChange(of: count) { _, _ in build() }.frame(width: 150)
                Toggle("PNG with a transparent background (so the colour can change)", isOn: $transparent).toggleStyle(.checkbox).font(.caption)
                    .onChange(of: transparent) { _, _ in build() }
                Spacer()
            }
            TextEditor(text: $prompt).font(.system(size: 12)).frame(minHeight: 170).padding(6)
                .background(Butter.cream, in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 8) {
                Button { send("ChatGPT") } label: { Label("Send to ChatGPT", systemImage: "paperplane.fill") }.buttonStyle(.borderedProminent).tint(Butter.coral)
                Button { send("Gemini") } label: { Label("Send to Gemini", systemImage: "paperplane.fill") }.buttonStyle(.borderedProminent).tint(Butter.coral)
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(prompt, forType: .string); status = "Prompt copied." } label: { Label("Copy", systemImage: "doc.on.doc") }
                Spacer()
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(Butter.cocoa) }
            Text("Tip: ask for a PNG with a transparent background. A flat photo cannot change colour; a transparent PNG can.").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16).frame(width: 560, height: 470)
        .onAppear { build() }
    }

    private func send(_ site: String) {
        guard let target = PromptTargets.load().first(where: { $0.name == site }) else { status = "\(site) is not in your Prompt Builder sites. Add it there first."; return }
        NotificationCenter.default.post(name: .keydoSendPrompt, object: PromptDispatchRequest(target: target, prompt: prompt, files: []))
        status = "Opening \(site) in the side panel with your request…"
    }
}

// MARK: - Command word ideas

enum DesignNameIdeas {
    /// Short words that could run an app named like this: its first word, its initials, a short start and the usual shortcut.
    @MainActor static func words(for name: String) -> [String] {
        let parts = name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard let first = parts.first else { return [] }
        var result: [String] = []
        func add(_ raw: String) {
            let word = DesignCommands.sanitize(raw)
            if word.count >= 2, !result.contains(word) { result.append(word) }
        }
        add(first)
        if parts.count > 1 { add(parts.compactMap { $0.first.map(String.init) }.joined()) }
        add(String(first.prefix(3)))
        add(String(EzMeWords.suggestedTrigger(for: name).dropFirst()))
        if parts.count > 1 { add(String(first.prefix(3)) + String((parts.last ?? "").prefix(2))) }
        return Array(result.prefix(5))
    }
}
