// Three small AppBuilder apps that work on pictures on this Mac, with no AI key:
//   Photo Collage (up to four views of one thing on one sheet), Logo on Background (logo to transparent PNG,
//   placed on any picture), Bollywood 80s (a retro film look). Each picture made costs credits.
import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

enum PhotoApps {
    static let names = ["Photo Collage", "Logo on Background", "Bollywood 80s"]
    static func isPhotoApp(_ name: String) -> Bool { names.contains(name) }
}

// MARK: - Drawing helpers

enum PhotoCanvas {
    static func bitmap(width: Int, height: Int, draw: (NSSize) -> Void) -> NSBitmapImageRep? {
        guard width > 0, height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        draw(NSSize(width: width, height: height))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func image(_ rep: NSBitmapImageRep?) -> NSImage? {
        guard let rep else { return nil }
        let result = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        result.addRepresentation(rep)
        return result
    }

    static func png(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static func pixelSize(_ image: NSImage) -> NSSize {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 { return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh) }
        return image.size
    }

    /// The same shape, no longer than `maxSide` on its long side.
    static func scaled(_ size: NSSize, maxSide: CGFloat) -> NSSize {
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else { return NSSize(width: max(1, size.width.rounded()), height: max(1, size.height.rounded())) }
        let k = maxSide / longest
        return NSSize(width: max(1, (size.width * k).rounded()), height: max(1, (size.height * k).rounded()))
    }

    static func fit(_ size: NSSize, in rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let k = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * k, h = size.height * k
        return NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    /// A picture copied anywhere (a screenshot, an image from a web page or a file in Finder), if there is one on the clipboard.
    static func pasted() -> NSImage? {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL],
           let first = urls.first, let loaded = NSImage(contentsOf: first) { return loaded }
        return (board.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first
    }

    static func choose(_ prompt: String) -> (image: NSImage, name: String)? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = prompt
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url, let loaded = NSImage(contentsOf: url) else { return nil }
        return (loaded, url.lastPathComponent)
    }
}

// MARK: - Collage

enum CollageMaker {
    static let layouts = ["2 × 2 grid", "One row", "One big and three small"]
    static let labels = ["Front", "Back", "Top", "Bottom", "Left", "Right", "Side", "Detail"]

    private static func cells(count: Int, layout: Int, size: NSSize, gap: CGFloat) -> [NSRect] {
        let width = size.width, height = size.height
        var result: [NSRect] = []
        guard count > 0 else { return result }
        if layout == 1 {
            let each = (width - gap * CGFloat(count + 1)) / CGFloat(count)
            for index in 0..<count { result.append(NSRect(x: gap + CGFloat(index) * (each + gap), y: gap, width: each, height: height - gap * 2)) }
        } else if layout == 2, count >= 2 {
            let bigWidth = (width - gap * 3) * 0.6
            result.append(NSRect(x: gap, y: gap, width: bigWidth, height: height - gap * 2))
            let small = count - 1
            let smallHeight = (height - gap * CGFloat(small + 1)) / CGFloat(small)
            let smallWidth = width - gap * 3 - bigWidth
            for index in 0..<small {
                let y = height - gap - CGFloat(index + 1) * smallHeight - CGFloat(index) * gap
                result.append(NSRect(x: gap * 2 + bigWidth, y: y, width: smallWidth, height: smallHeight))
            }
        } else {
            let cellWidth = (width - gap * 3) / 2, cellHeight = (height - gap * 3) / 2
            for index in 0..<min(count, 4) {
                let column = CGFloat(index % 2), row = CGFloat(index / 2)
                result.append(NSRect(x: gap + column * (cellWidth + gap), y: height - gap - (row + 1) * cellHeight - row * gap, width: cellWidth, height: cellHeight))
            }
        }
        return result
    }

    /// `scale` 1 is the full sheet; the live preview uses a small scale.
    static func make(items: [(label: String, image: NSImage)], layout: Int, background: NSColor, showLabels: Bool, scale: CGFloat) -> NSImage? {
        let size = layout == 1 ? NSSize(width: (4000 * scale).rounded(), height: (1200 * scale).rounded()) : NSSize(width: (2400 * scale).rounded(), height: (2400 * scale).rounded())
        let gap = 30 * scale
        let frames = cells(count: items.count, layout: layout, size: size, gap: gap)
        let brightness = background.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 1
        let textColor: NSColor = brightness < 0.5 ? .white : NSColor(white: 0.15, alpha: 1)
        let rep = PhotoCanvas.bitmap(width: Int(size.width), height: Int(size.height)) { canvas in
            background.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()
            for (index, frame) in frames.enumerated() where index < items.count {
                let strip: CGFloat = showLabels ? 70 * scale : 0
                let area = NSRect(x: frame.minX, y: frame.minY + strip, width: frame.width, height: max(1, frame.height - strip))
                let target = PhotoCanvas.fit(items[index].image.size, in: area)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: target, xRadius: 18 * scale, yRadius: 18 * scale).addClip()
                items[index].image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
                if showLabels {
                    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 44 * scale, weight: .semibold), .foregroundColor: textColor]
                    let text = NSAttributedString(string: items[index].label, attributes: attributes)
                    let textSize = text.size()
                    text.draw(at: NSPoint(x: frame.midX - textSize.width / 2, y: frame.minY + (strip - textSize.height) / 2))
                }
            }
        }
        return PhotoCanvas.image(rep)
    }
}

// MARK: - Logo on background

enum LogoMaker {
    /// Makes the plain background around a logo transparent. The background is the colour at the corners, found from the edges inwards,
    /// so the same colour inside the logo stays.
    static func cutOut(_ source: NSImage, tolerance: Double) -> NSImage? {
        let size = PhotoCanvas.scaled(PhotoCanvas.pixelSize(source), maxSide: 1600)
        guard let rep = PhotoCanvas.bitmap(width: Int(size.width), height: Int(size.height), draw: { canvas in
            source.draw(in: NSRect(origin: .zero, size: canvas), from: .zero, operation: .copy, fraction: 1)
        }), let data = rep.bitmapData else { return nil }
        let width = rep.pixelsWide, height = rep.pixelsHigh, stride = rep.bytesPerRow
        func offset(_ x: Int, _ y: Int) -> Int { y * stride + x * 4 }
        if data[offset(0, 0) + 3] < 10 { return PhotoCanvas.image(rep) }

        let corners = [offset(0, 0), offset(width - 1, 0), offset(0, height - 1), offset(width - 1, height - 1)]
        var sumR = 0, sumG = 0, sumB = 0
        for corner in corners { sumR += Int(data[corner]); sumG += Int(data[corner + 1]); sumB += Int(data[corner + 2]) }
        let baseR = sumR / 4, baseG = sumG / 4, baseB = sumB / 4
        let limit = Int(tolerance * 441)
        let limitSquared = limit * limit

        func matches(_ x: Int, _ y: Int) -> Bool {
            let o = offset(x, y)
            let dr = Int(data[o]) - baseR, dg = Int(data[o + 1]) - baseG, db = Int(data[o + 2]) - baseB
            return dr * dr + dg * dg + db * db <= limitSquared
        }

        var removed = [Bool](repeating: false, count: width * height)
        var stack: [Int] = []
        func seed(_ x: Int, _ y: Int) {
            let index = y * width + x
            if !removed[index], matches(x, y) { removed[index] = true; stack.append(index) }
        }
        for x in 0..<width { seed(x, 0); seed(x, height - 1) }
        for y in 0..<height { seed(0, y); seed(width - 1, y) }
        while let index = stack.popLast() {
            let x = index % width, y = index / width
            if x > 0 { seed(x - 1, y) }
            if x < width - 1 { seed(x + 1, y) }
            if y > 0 { seed(x, y - 1) }
            if y < height - 1 { seed(x, y + 1) }
        }

        // A softer one-pixel edge so the logo does not look cut with scissors.
        var edge = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width where !removed[y * width + x] {
                let touches = (x > 0 && removed[y * width + x - 1]) || (x < width - 1 && removed[y * width + x + 1])
                    || (y > 0 && removed[(y - 1) * width + x]) || (y < height - 1 && removed[(y + 1) * width + x])
                if touches { edge[y * width + x] = true }
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                let o = offset(x, y)
                if removed[y * width + x] {
                    data[o] = 0; data[o + 1] = 0; data[o + 2] = 0; data[o + 3] = 0
                } else if edge[y * width + x] {
                    data[o] = UInt8(Double(data[o]) * 0.6); data[o + 1] = UInt8(Double(data[o + 1]) * 0.6)
                    data[o + 2] = UInt8(Double(data[o + 2]) * 0.6); data[o + 3] = UInt8(Double(data[o + 3]) * 0.6)
                }
            }
        }
        return PhotoCanvas.image(rep)
    }

    private static func place(_ index: Int, total: CGFloat, length: CGFloat, margin: CGFloat) -> CGFloat {
        switch index {
        case 0: return margin
        case 1: return (total - length) / 2
        default: return total - length - margin
        }
    }

    /// `anchor` 0 to 8: top-left to bottom-right, row by row.
    static func compose(background: NSImage, logo: NSImage, anchor: Int, size: Double, opacity: Double, margin: Double, maxSide: CGFloat) -> NSImage? {
        let canvas = PhotoCanvas.scaled(PhotoCanvas.pixelSize(background), maxSide: maxSide)
        let logoShape = PhotoCanvas.pixelSize(logo)
        let width: CGFloat = canvas.width * CGFloat(size)
        let height: CGFloat = width * logoShape.height / max(1, logoShape.width)
        let edge: CGFloat = canvas.width * CGFloat(margin)
        let x: CGFloat = place(anchor % 3, total: canvas.width, length: width, margin: edge)
        let top: CGFloat = place(anchor / 3, total: canvas.height, length: height, margin: edge)
        let y: CGFloat = canvas.height - top - height
        let rep = PhotoCanvas.bitmap(width: Int(canvas.width), height: Int(canvas.height)) { whole in
            background.draw(in: NSRect(origin: .zero, size: whole), from: .zero, operation: .copy, fraction: 1)
            logo.draw(in: NSRect(x: x, y: y, width: width, height: height), from: .zero, operation: .sourceOver, fraction: CGFloat(opacity))
        }
        return PhotoCanvas.image(rep)
    }
}

// MARK: - Bollywood 80s

enum RetroMaker {
    static let looks = ["Classic 80s film", "Faded poster", "Disco neon"]

    private static func recipe(_ look: Int) -> (saturation: Float, contrast: Float, red: CGFloat, green: CGFloat, blue: CGFloat, biasRed: CGFloat, biasGreen: CGFloat, biasBlue: CGFloat) {
        switch look {
        case 1: return (0.85, 1.05, 1.08, 1.0, 0.88, 0.07, 0.05, 0.03)
        case 2: return (1.35, 1.15, 1.08, 0.95, 1.18, 0.03, 0.0, 0.05)
        default: return (1.25, 1.12, 1.12, 1.0, 0.84, 0.04, 0.02, 0.0)
        }
    }

    static func make(_ source: NSImage, look: Int, title: String, frame: Bool, maxSide: CGFloat) -> NSImage? {
        let size = PhotoCanvas.scaled(PhotoCanvas.pixelSize(source), maxSide: maxSide)
        guard let base = PhotoCanvas.bitmap(width: Int(size.width), height: Int(size.height), draw: { canvas in
            source.draw(in: NSRect(origin: .zero, size: canvas), from: .zero, operation: .copy, fraction: 1)
        }), let cg = base.cgImage else { return nil }
        let r = recipe(look)
        var image = CIImage(cgImage: cg)
        let extent = image.extent

        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.saturation = r.saturation
        controls.contrast = r.contrast
        controls.brightness = 0.02
        image = controls.outputImage ?? image

        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: r.red, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: r.green, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: r.blue, w: 0)
        matrix.biasVector = CIVector(x: r.biasRed, y: r.biasGreen, z: r.biasBlue, w: 0)
        image = matrix.outputImage ?? image

        let bloom = CIFilter.bloom()
        bloom.inputImage = image
        bloom.radius = Float(extent.width / 120)
        bloom.intensity = 0.55
        image = (bloom.outputImage ?? image).cropped(to: extent)

        if let noise = CIFilter.randomGenerator().outputImage {
            let grey = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0, kCIInputContrastKey: 0.3]).cropped(to: extent)
            let blend = CIFilter.softLightBlendMode()
            blend.inputImage = grey
            blend.backgroundImage = image
            image = (blend.outputImage ?? image).cropped(to: extent)
        }

        let vignette = CIFilter.vignette()
        vignette.inputImage = image
        vignette.intensity = 0.9
        vignette.radius = 2
        image = (vignette.outputImage ?? image).cropped(to: extent)

        guard let graded = CIContext().createCGImage(image, from: extent) else { return nil }
        let gradedImage = NSImage(cgImage: graded, size: size)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rep = PhotoCanvas.bitmap(width: Int(size.width), height: Int(size.height)) { canvas in
            gradedImage.draw(in: NSRect(origin: .zero, size: canvas), from: .zero, operation: .copy, fraction: 1)
            if frame {
                let inset = canvas.width * 0.025
                let path = NSBezierPath(rect: NSRect(x: inset, y: inset, width: canvas.width - inset * 2, height: canvas.height - inset * 2))
                path.lineWidth = canvas.width * 0.008
                NSColor(white: 0.97, alpha: 0.95).setStroke()
                path.stroke()
            }
            if !cleanTitle.isEmpty {
                let fontSize = min(canvas.width * 0.09, canvas.width * 0.9 / (CGFloat(cleanTitle.count) * 0.62))
                let shadow = NSShadow()
                shadow.shadowOffset = NSSize(width: 4, height: -4)
                shadow.shadowBlurRadius = 6
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
                let font: NSFont = NSFont(name: "Impact", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .black)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1),
                    .strokeColor: NSColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1),
                    .strokeWidth: -3.0,
                    .shadow: shadow
                ]
                let text = NSAttributedString(string: cleanTitle.uppercased(), attributes: attributes)
                let textSize = text.size()
                text.draw(at: NSPoint(x: (canvas.width - textSize.width) / 2, y: canvas.height * 0.07))
            }
        }
        return PhotoCanvas.image(rep)
    }
}

// MARK: - Shared screen

/// Controls on the left, a live preview on the right. The preview is free; making the PNG uses credits.
struct PhotoAppShell<Controls: View>: View {
    var symbol: String
    var title: String
    var subtitle: String
    var preview: NSImage?
    var ready: Bool
    var suggestedName: String
    var make: () -> NSImage?
    var controls: () -> Controls

    @ObservedObject private var credits = CreditsCenter.shared
    @State private var result: NSImage?
    @State private var message = ""

    init(symbol: String, title: String, subtitle: String, preview: NSImage?, ready: Bool, suggestedName: String,
         make: @escaping () -> NSImage?, @ViewBuilder controls: @escaping () -> Controls) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.preview = preview
        self.ready = ready
        self.suggestedName = suggestedName
        self.make = make
        self.controls = controls
    }

    private var price: Int { credits.cost(.photoApp) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BuilderHeader(symbol: symbol, title: title, subtitle: subtitle) { CreditChip(cost: price) }
                .padding(16)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) { controls() }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 370)
                Divider()
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(Butter.cream)
                        if let shown = result ?? preview {
                            Image(nsImage: shown).resizable().scaledToFit().padding(10)
                        } else {
                            Text("Choose your picture to see it here.").foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text(result != nil ? "Your finished picture" : "Preview. It is free until you make the picture.").font(.caption).foregroundStyle(.secondary)
                    if !message.isEmpty { Text(message).font(.callout).foregroundStyle(Butter.cocoa).multilineTextAlignment(.center) }
                    HStack(spacing: 10) {
                        Button { makeIt() } label: { Label("Make picture · \(price) credits", systemImage: "wand.and.stars") }
                            .buttonStyle(.borderedProminent).tint(Butter.coral).disabled(!ready)
                        if let result {
                            Button { save(result) } label: { Label("Save PNG", systemImage: "square.and.arrow.down") }.buttonStyle(.bordered)
                            Button { copy(result) } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(.bordered)
                            Menu {
                                ForEach(PhotoApps.names, id: \.self) { app in Button(app) { send(result, to: app) } }
                                Button("Wish Studio backgrounds (library)") { send(result, to: "Wish Studio") }
                                Divider()
                                ForEach(WishAppIndex.read(), id: \.id) { entry in Button("Wish app: " + entry.name) { sendToWish(result, entry) } }
                            } label: { Label("Send to app as template", systemImage: "square.and.arrow.up.on.square") }
                                .menuStyle(.borderlessButton).fixedSize()
                            Button { self.result = nil; message = "" } label: { Text("Back to preview") }.buttonStyle(.borderless)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func makeIt() {
        guard let id = credits.charge(.photoApp, detail: title) else { message = credits.lastMessage; return }
        if let image = make() {
            result = image
            message = "Made. \(price) credits used."
        } else {
            credits.refund(id, reason: "The picture could not be made")
            message = "The picture could not be made, so your credits were returned."
        }
    }

    private func save(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedName + ".png"
        guard panel.runModal() == .OK, let url = panel.url, let data = PhotoCanvas.png(image) else { return }
        do { try data.write(to: url, options: .atomic); message = "Saved to \(url.lastPathComponent)." } catch { message = "Could not save the file." }
    }

    private func send(_ image: NSImage, to app: String) {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmm"
        let ok = CommonLibrary.send(image, name: title + " " + stamp.string(from: Date()), toApp: app)
        message = ok ? "Sent. It is now in \(app)'s templates and in the common library." : "Could not send it."
    }

    private func sendToWish(_ image: NSImage, _ entry: WishAppIndex.Entry) {
        if WishLookStore.add(image, appID: entry.id) != nil {
            message = "Added to the Wish app \(entry.name) as a template. Open it in Wish Studio to use it."
        } else { message = "Could not send it." }
    }

    private func copy(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        message = "Copied. Paste it into any app."
    }
}

/// Every picture slot in every photo app uses this, so each one can pick from the Mac or from the common library.
private struct PhotoChooser: View {
    var app: String
    var title: String
    var name: String
    var pick: (NSImage, String) -> Void
    @State private var showLibrary = false
    @State private var notice = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button { if let picked = PhotoCanvas.choose(title) { pick(picked.image, picked.name) } } label: {
                    Label(name.isEmpty ? "From this Mac" : "Change", systemImage: "photo.badge.plus")
                }.buttonStyle(.bordered)
                Button { showLibrary = true } label: { Label("Library", systemImage: "photo.stack") }.buttonStyle(.bordered)
                Button { if let image = PhotoCanvas.pasted() { pick(image, "Pasted picture") } else { notice = "There is no picture on the clipboard. Copy one first." } } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }.buttonStyle(.bordered).help("Use the picture you copied")
            }
            if !notice.isEmpty { Text(notice).font(.caption).foregroundStyle(.orange) }
            Text(name.isEmpty ? "No picture yet" : name).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .sheet(isPresented: $showLibrary) { CommonLibrarySheet(app: app) { image, label in pick(image, label) } }
    }
}

private struct PhotoStep<Content: View>: View {
    var number: Int
    var title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(number). \(title)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Butter.cocoa)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Butter.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - The three apps

struct PhotoCollageApp: View {
    private struct Slot: Identifiable {
        let id = UUID()
        var label: String
        var name = ""
        var image: NSImage?
    }

    @State private var slots: [Slot] = [Slot(label: "Front"), Slot(label: "Back"), Slot(label: "Left"), Slot(label: "Right")]
    @State private var layout = 0
    @State private var background = Color.white
    @State private var showLabels = true

    private var items: [(label: String, image: NSImage)] {
        slots.compactMap { slot in slot.image.map { (label: slot.label, image: $0) } }
    }

    var body: some View {
        PhotoAppShell(symbol: "square.grid.2x2.fill", title: "Photo Collage", subtitle: "Put the front, back, top, left or right views of one thing on one sheet.",
                      preview: CollageMaker.make(items: items, layout: layout, background: NSColor(background), showLabels: showLabels, scale: 0.3),
                      ready: !items.isEmpty, suggestedName: "collage",
                      make: { CollageMaker.make(items: items, layout: layout, background: NSColor(background), showLabels: showLabels, scale: 1) }) {
            PhotoStep(number: 1, title: "Add your views (up to four)") {
                ForEach($slots) { $slot in
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $slot.label) { ForEach(CollageMaker.labels, id: \.self) { Text($0).tag($0) } }
                            .labelsHidden().frame(width: 130)
                        PhotoChooser(app: "Photo Collage", title: "Choose the \(slot.label.lowercased()) view", name: slot.name) { image, label in
                            slot.image = image; slot.name = label
                        }
                    }
                }
            }
            PhotoStep(number: 2, title: "Choose the sheet") {
                Picker("", selection: $layout) { ForEach(0..<CollageMaker.layouts.count, id: \.self) { Text(CollageMaker.layouts[$0]).tag($0) } }
                    .labelsHidden()
                ColorPicker("Background colour", selection: $background)
                Toggle("Show the names under each view", isOn: $showLabels)
            }
        }
    }
}

struct LogoOnBackgroundApp: View {
    @State private var logo: NSImage?
    @State private var logoName = ""
    @State private var cutLogo: NSImage?
    @State private var background: NSImage?
    @State private var backgroundName = ""
    @State private var removeBackground = true
    @State private var tolerance = 0.18
    @State private var anchor = 8
    @State private var size = 0.22
    @State private var opacity = 1.0
    @State private var margin = 0.04

    private func refreshCut() {
        guard let logo else { cutLogo = nil; return }
        cutLogo = removeBackground ? LogoMaker.cutOut(logo, tolerance: tolerance) : logo
    }

    private func composed(maxSide: CGFloat) -> NSImage? {
        guard let background, let readyLogo = cutLogo ?? logo else { return nil }
        return LogoMaker.compose(background: background, logo: readyLogo, anchor: anchor, size: size, opacity: opacity, margin: margin, maxSide: maxSide)
    }

    var body: some View {
        PhotoAppShell(symbol: "signature", title: "Logo on Background", subtitle: "Turn a logo into a transparent PNG and place it on any picture.",
                      preview: composed(maxSide: 700), ready: background != nil && (cutLogo ?? logo) != nil, suggestedName: "logo-on-picture",
                      make: { composed(maxSide: 3000) }) {
            PhotoStep(number: 1, title: "Your logo") {
                PhotoChooser(app: "Logo on Background", title: "Choose your logo", name: logoName) { image, label in
                    logo = image; logoName = label; refreshCut()
                }
                Toggle("Make the plain background transparent", isOn: $removeBackground).onChange(of: removeBackground) { _ in refreshCut() }
                if removeBackground {
                    HStack { Text("How much to remove").font(.caption); Slider(value: $tolerance, in: 0.04...0.5, onEditingChanged: { editing in if !editing { refreshCut() } }) }
                }
            }
            PhotoStep(number: 2, title: "The picture to put it on") {
                PhotoChooser(app: "Logo on Background", title: "Choose the background picture", name: backgroundName) { image, label in
                    background = image; backgroundName = label
                }
            }
            PhotoStep(number: 3, title: "Where it goes") {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(0..<3, id: \.self) { row in
                        GridRow {
                            ForEach(0..<3, id: \.self) { column in
                                let index = row * 3 + column
                                Button { anchor = index } label: {
                                    RoundedRectangle(cornerRadius: 6).fill(anchor == index ? Butter.coral : Butter.honey.opacity(0.5)).frame(width: 44, height: 28)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                HStack { Text("Size").font(.caption).frame(width: 60, alignment: .leading); Slider(value: $size, in: 0.05...0.8) }
                HStack { Text("See-through").font(.caption).frame(width: 60, alignment: .leading); Slider(value: $opacity, in: 0.2...1) }
                HStack { Text("Gap").font(.caption).frame(width: 60, alignment: .leading); Slider(value: $margin, in: 0...0.15) }
            }
        }
    }
}

struct BollywoodRetroApp: View {
    @State private var photo: NSImage?
    @State private var photoName = ""
    @State private var look = 0
    @State private var title = ""
    @State private var frame = true

    var body: some View {
        PhotoAppShell(symbol: "film.stack.fill", title: "Bollywood 80s", subtitle: "Give any picture the warm, grainy look of an 80s Bollywood film poster.",
                      preview: photo.flatMap { RetroMaker.make($0, look: look, title: title, frame: frame, maxSide: 700) },
                      ready: photo != nil, suggestedName: "bollywood-80s",
                      make: { photo.flatMap { RetroMaker.make($0, look: look, title: title, frame: frame, maxSide: 2400) } }) {
            PhotoStep(number: 1, title: "Your picture") {
                PhotoChooser(app: "Bollywood 80s", title: "Choose a picture", name: photoName) { image, label in
                    photo = image; photoName = label
                }
            }
            PhotoStep(number: 2, title: "Pick the look") {
                Picker("", selection: $look) { ForEach(0..<RetroMaker.looks.count, id: \.self) { Text(RetroMaker.looks[$0]).tag($0) } }
                    .labelsHidden().pickerStyle(.segmented)
                TextField("Film title (optional)", text: $title).textFieldStyle(.roundedBorder)
                Toggle("White film border", isOn: $frame)
            }
        }
    }
}

/// What AppBuilder opens for one of the three names.
struct PhotoAppsView: View {
    var name: String
    var body: some View {
        switch name {
        case "Logo on Background": LogoOnBackgroundApp()
        case "Bollywood 80s": BollywoodRetroApp()
        default: PhotoCollageApp()
        }
    }
}
