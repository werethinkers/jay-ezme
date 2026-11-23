// Font Creator: an AppBuilder app. Upload a picture of one letter, KeyDo reads its weight, corners, lean and colours and
// builds a whole A to Z and 0 to 9 font in that look. The ten built-in fonts are shown too. Saved fonts show in every font list.
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Vision

struct FontCreatorApp: View {
    @State private var tab = 0
    @State private var sample = "Happy Birthday"
    @State private var letter: NSImage?
    @State private var letterName = ""
    @State private var lettersText = ""
    @State private var draft: KeyDoFontStyle?
    @State private var fontName = ""
    @State private var chosenID = "summit-block"
    @State private var saved: [KeyDoFontStyle] = KeyDoFonts.user
    @State private var notice = ""
    @State private var ownGlyphs: [String: KeyDoGlyph] = [:]
    @State private var aiGlyphs: [String: KeyDoGlyph] = [:]
    @State private var showCrop = false
    @State private var aiBusy = false
    @State private var aiCaps = true
    @State private var aiSmall = true

    private var current: KeyDoFontStyle? {
        if tab == 0 { return draft }
        return KeyDoFonts.all.first { $0.id == chosenID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "textformat.abc").font(.system(size: 26, weight: .bold)).foregroundStyle(Butter.coral)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Font Creator").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Butter.cocoa)
                        Text("Upload a picture of a letter, a word or a whole alphabet. Your letters are copied exactly, and the rest of A to Z, a to z and 0 to 9 is drawn in the same look.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Picker("", selection: $tab) {
                    Text("Make from a letter").tag(0)
                    Text("20 KeyDo fonts").tag(1)
                    Text("My fonts (\(saved.count))").tag(2)
                }.labelsHidden().pickerStyle(.segmented)

                wishBar

                if tab == 0 { makeSection }
                if tab == 1 { gallery(KeyDoFonts.builtIn) }
                if tab == 2 {
                    if saved.isEmpty { Text("Nothing saved yet. Make a font from a letter and press Save font.").foregroundStyle(.secondary) }
                    else { gallery(saved) }
                }
                if tab != 0 || draft != nil { previewSection }
                if !notice.isEmpty { Text(notice).font(.caption).foregroundStyle(Butter.cocoa) }
            }
            .padding(18)
        }
    }

    private var makeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("1. Your letter").font(.system(size: 13, weight: .bold, design: .rounded))
            PhotoChooser(app: "Font Creator", title: "Choose a picture of a letter or a logo letter", name: letterName) { image, label in
                letter = image; letterName = label
                draft = KeyDoFontAnalyzer.analyze(image)
                fontName = "My font"
                ownGlyphs = [:]
                aiGlyphs = [:]
                lettersText = KeyDoFontAnalyzer.guessLetters(image)
                notice = lettersText.isEmpty ? "Read the picture. Type which letters it shows below, or crop to one letter."
                    : "Read the picture. I think it shows \u{201C}\(lettersText)\u{201D}. Fix the letters if that is wrong."
                recapture()
            }
            if let letter {
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 4) {
                        Image(nsImage: letter).resizable().scaledToFit().frame(height: 70).background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                        Button { showCrop = true } label: { Label("Crop", systemImage: "crop") }.buttonStyle(.bordered).controlSize(.small)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Which letters are in the picture, left to right? For example HES").font(.caption).foregroundStyle(.secondary)
                        TextField("Letters in the picture", text: $lettersText).textFieldStyle(.roundedBorder).onChange(of: lettersText) { _ in recapture() }
                    }
                }
            }
            if let draft {
                Text("2. Fine tune").font(.system(size: 13, weight: .bold, design: .rounded))
                TextField("Font name", text: $fontName).textFieldStyle(.roundedBorder)
                let binding = Binding<KeyDoFontStyle>(get: { self.draft ?? draft }, set: { self.draft = $0 })
                HStack { Text("Thickness").font(.caption).frame(width: 80, alignment: .leading); Slider(value: binding.weight, in: 0.04...0.3) }
                HStack { Text("Width").font(.caption).frame(width: 80, alignment: .leading); Slider(value: binding.width, in: 0.6...1.5) }
                HStack { Text("Lean").font(.caption).frame(width: 80, alignment: .leading); Slider(value: binding.slant, in: -20...20) }
                HStack { Text("Spacing").font(.caption).frame(width: 80, alignment: .leading); Slider(value: binding.spacing, in: 0...0.2) }
                HStack { Text("Serifs").font(.caption).frame(width: 80, alignment: .leading); Slider(value: Binding(get: { self.draft?.serif ?? 0 }, set: { self.draft?.serif = $0 }), in: 0...0.22) }
                HStack { Text("Thick & thin").font(.caption).frame(width: 80, alignment: .leading); Slider(value: Binding(get: { self.draft?.contrast ?? 0 }, set: { self.draft?.contrast = $0 }), in: 0...0.75) }
                Text("KeyDo reads the stroke thickness, corners, lean, serifs and thick-and-thin from your letter, then draws every other letter the same way. Thick & thin shows in the Solid style.")
                    .font(.caption2).foregroundStyle(.secondary)
                Picker("Corners", selection: binding.cap) { Text("Flat").tag(0); Text("Round").tag(1); Text("Square").tag(2) }.pickerStyle(.segmented)
                Picker("Style", selection: binding.mode) { ForEach(0..<KeyDoFontStyle.modes.count, id: \.self) { Text(KeyDoFontStyle.modes[$0]).tag($0) } }
                if !draft.palette.isEmpty {
                    HStack(spacing: 6) {
                        Text("Colours found").font(.caption)
                        ForEach(draft.palette, id: \.self) { hex in Circle().fill(Color(nsColor: NSColor(templateHex: hex))).frame(width: 18, height: 18) }
                    }
                }
                if !ownGlyphs.isEmpty { compareStrip }
                Text("3. Make the rest with AI").font(.system(size: 13, weight: .bold, design: .rounded))
                Text("AI draws the other letters in the same style from your picture. Your own letters are never replaced. Each sheet uses one AI picture of your credits.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Toggle("Capitals and numbers", isOn: $aiCaps)
                    Toggle("Small letters", isOn: $aiSmall)
                    Button { Task { await generateRest() } } label: { Label(aiBusy ? "Drawing\u{2026}" : "Create with AI", systemImage: "wand.and.stars") }
                        .buttonStyle(.bordered).disabled(aiBusy || letter == nil || (!aiCaps && !aiSmall))
                    if !aiGlyphs.isEmpty { Text("\(aiGlyphs.count) letters drawn by AI").font(.caption).foregroundStyle(.secondary) }
                }
                Button { saveDraft() } label: { Label("Save font", systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent).tint(Butter.coral)
            }
        }
        .sheet(isPresented: $showCrop) {
            if let letter {
                FontCropSheet(image: letter, letters: lettersText,
                              onUse: { cropped in
                                  self.letter = cropped
                                  self.draft = KeyDoFontAnalyzer.analyze(cropped)
                                  self.draft?.name = self.fontName
                                  self.ownGlyphs = [:]
                                  self.aiGlyphs = [:]
                                  self.lettersText = KeyDoFontAnalyzer.guessLetters(cropped)
                                  self.recapture()
                              },
                              onAdd: { cropped, typed in addCropped(cropped, typed) })
            }
        }
        .padding(12).background(Butter.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var compareStrip: some View {
        if let style = draft {
            let keys = Array(ownGlyphs.keys.sorted().prefix(10))
            VStack(alignment: .leading, spacing: 4) {
                Text("Check: your letter on top, KeyDo\u{2019}s drawing of the same letter below. Adjust the sliders until they match.").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(keys, id: \.self) { key in compareCell(key, style) } }
                }
            }
        }
    }

    private func compareCell(_ key: String, _ style: KeyDoFontStyle) -> some View {
        var plain = style
        plain.glyphs = nil
        return VStack(spacing: 2) {
            if let glyph = ownGlyphs[key], let picture = NSImage(data: glyph.png) { Image(nsImage: picture).resizable().scaledToFit().frame(width: 64, height: 64) }
            if let drawn = KeyDoFonts.image(key, style: plain, width: 200, height: 200, color: NSColor(Butter.cocoa), background: nil) { Image(nsImage: drawn).resizable().scaledToFit().frame(width: 64, height: 64) }
            Text(key).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(6).background(Color.white, in: RoundedRectangle(cornerRadius: 8))
    }

    private func gallery(_ styles: [KeyDoFontStyle]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
            ForEach(styles) { style in
                Button { chosenID = style.id } label: {
                    VStack(spacing: 4) {
                        if let image = KeyDoFonts.image("Aa Kd 7", style: style, width: 400, height: 130, color: NSColor(Butter.cocoa), background: nil) {
                            Image(nsImage: image).resizable().scaledToFit().frame(height: 60)
                        }
                        Text(style.name).font(.caption.bold()).foregroundStyle(Butter.cocoa)
                    }
                    .padding(8).frame(maxWidth: .infinity)
                    .background(chosenID == style.id ? Butter.honey.opacity(0.6) : Butter.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Type a name to try", text: $sample).textFieldStyle(.roundedBorder)
            if let style = current {
                if let image = KeyDoFonts.image(sample.isEmpty ? "Name" : sample, style: style, width: 1200, height: 320, color: NSColor(Butter.cocoa), background: NSColor.white) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 190).background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                }
                if let sheet = KeyDoFonts.alphabetSheet(style: style, sample: sample, color: NSColor(Butter.cocoa)) {
                    Image(nsImage: sheet).resizable().scaledToFit().background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    HStack {
                        Button("Save alphabet picture") { savePNG(sheet, style.name) }.buttonStyle(.bordered)
                        if !style.builtIn, tab == 2 { Button("Delete this font", role: .destructive) { KeyDoFonts.deleteUser(style.id); saved = KeyDoFonts.user; chosenID = "summit-block" }.buttonStyle(.bordered) }
                    }
                }
                Text("In Wish Studio, Template Designer and AppDesigner, pick \u{201C}\(style.fontName)\u{201D} in the Font list.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Cuts the typed letters out of the picture so they are drawn exactly as they look there.
    private func recapture() {
        guard let letter, draft != nil else { return }
        let cleaned = lettersText.filter { !$0.isWhitespace }
        if cleaned.isEmpty { ownGlyphs = [:]; rebuildGlyphs(); return }
        let result = KeyDoFontAnalyzer.capture(letter, letters: lettersText)
        ownGlyphs = result.glyphs
        if var fitted = draft, !ownGlyphs.isEmpty { KeyDoFontAnalyzer.calibrate(&fitted, glyphs: ownGlyphs); draft = fitted }
        rebuildGlyphs()
        if !result.palette.isEmpty { draft?.palette = result.palette }
        notice = result.found == result.expected ? "Copied \(result.found) letter\(result.found == 1 ? "" : "s") exactly from your picture. The other letters follow the same look."
            : "Found \(result.found) separate letters but you typed \(result.expected). Check the letters, or use a clearer picture."
    }

    /// Your own cut-out letters first, then the ones AI drew for the rest.
    private func rebuildGlyphs() {
        var all = aiGlyphs
        let colored = ownGlyphs.values.first?.colored
        if let colored { for key in all.keys { all[key]?.colored = colored } }
        for (key, value) in ownGlyphs { all[key] = value }
        draft?.glyphs = all.isEmpty ? nil : all
    }

    /// A crop with its own letters, added to the letters already cut out.
    private func addCropped(_ cropped: NSImage, _ typed: String) {
        let result = KeyDoFontAnalyzer.capture(cropped, letters: typed)
        guard !result.glyphs.isEmpty else { notice = "Could not cut a letter out of that part. Crop closer around it."; return }
        for (key, value) in result.glyphs { ownGlyphs[key] = value }
        rebuildGlyphs()
        if draft?.palette.isEmpty ?? false, !result.palette.isEmpty { draft?.palette = result.palette }
        notice = result.found == result.expected ? "Added \(result.found) letter\(result.found == 1 ? "" : "s") from the crop. You have \(ownGlyphs.count) of your own letters."
            : "Found \(result.found) separate letters in the crop but you typed \(result.expected)."
    }

    /// Asks the AI image model for alphabet sheets in the style of the picture, then cuts the letters out of each sheet.
    @MainActor private func generateRest() async {
        guard let letter, let png = PhotoCanvas.png(letter) else { return }
        let profiles = AIModelProfileStore.load()
        let selectedID = UserDefaults.standard.string(forKey: "ezmeSelectedAIModelProfile") ?? UserDefaults.standard.string(forKey: "ezmeCollectionSelectedProfile") ?? CollectionAIModelProfile.starter.id
        let profile = profiles.first(where: { $0.id == selectedID }) ?? .starter
        let key = KeyStore.load(account: profile.keyAccount) ?? ""
        guard !key.isEmpty else { notice = "Add an API key in API configuration to draw letters with AI."; return }
        let provider = profile.provider.lowercased()
        let google = provider.contains("google") || provider.contains("gemini")
        guard google || provider.contains("openai") else { notice = "Choose an OpenAI or Google Gemini model in API configuration to draw letters with AI."; return }
        let model = google ? "gemini-3.1-flash-image" : "gpt-image-2.5-flare"
        let reference = FileManager.default.temporaryDirectory.appendingPathComponent("keydo-font-" + String(UUID().uuidString.prefix(8)) + ".png")
        do { try png.write(to: reference) } catch { notice = "Could not prepare the picture: \(error.localizedDescription)"; return }
        defer { try? FileManager.default.removeItem(at: reference) }

        var sheets: [(chars: String, rows: [String])] = []
        if aiCaps { sheets.append(("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", ["A B C D E F", "G H I J K L", "M N O P Q R", "S T U V W X", "Y Z 0 1 2 3", "4 5 6 7 8 9"])) }
        if aiSmall { sheets.append(("abcdefghijklmnopqrstuvwxyz", ["a b c d e f", "g h i j k l", "m n o p q r", "s t u v w x", "y z"])) }
        aiBusy = true
        defer { aiBusy = false }
        var added = 0
        for (index, sheet) in sheets.enumerated() {
            notice = "Drawing sheet \(index + 1) of \(sheets.count) with AI\u{2026} this takes a minute."
            let prompt = "The reference picture shows sample letters of a font. Draw a font specimen sheet in EXACTLY the same style as those letters: the same shapes, stroke thickness, corner roundness, colours and finish. "
                + "Use a plain pure white background, no shadows, no frame, no labels and no other text. Put one character per cell in a clean grid, left to right then top to bottom, in this exact order, rows separated by a slash: "
                + sheet.rows.joined(separator: " / ") + ". Make the characters large with generous white space so they never touch each other, and keep the letters in each row on the same baseline."
            do {
                let bytes = try await BuilderMediaGenerator.generateImage(provider: profile.provider, key: key, modelID: model, prompt: prompt, referencePaths: [reference.path], aspectRatio: "1:1", resolution: "2K")
                guard let picture = NSImage(data: bytes) else { notice = "The AI picture could not be read."; continue }
                let result = KeyDoFontAnalyzer.capture(picture, letters: sheet.chars)
                if result.found == result.expected {
                    for (name, value) in result.glyphs { aiGlyphs[name] = value }
                    added += result.found
                } else {
                    notice = "The AI sheet had \(result.found) separate letters instead of \(result.expected), so it was not used. Try again."
                }
            } catch {
                notice = "AI could not draw the letters: \(error.localizedDescription)"
            }
        }
        rebuildGlyphs()
        if added > 0 { notice = "AI drew \(added) letters in your style. Your own letters stay as they are." }
    }

    /// One button to use the font in WishStudio: saves it if needed, copies its name, and opens WishStudio.
    private var wishBar: some View {
        let name = current?.fontName ?? ""
        return HStack(spacing: 10) {
            Image(systemName: "party.popper.fill").foregroundStyle(Butter.coral)
            VStack(alignment: .leading, spacing: 1) {
                Text(name.isEmpty ? "Pick or make a font to use it in WishStudio" : "Use \u{201C}\(name)\u{201D} in WishStudio").font(.system(size: 13, weight: .bold, design: .rounded))
                Text("Saved fonts appear in every WishStudio font list. In WishStudio, choose a text, open Font and pick it (the name starts with KeyDo \u{00B7}).")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { sendToWishStudio() } label: { Label("Send to WishStudio", systemImage: "paperplane.fill") }
                .buttonStyle(.borderedProminent).tint(Butter.coral).disabled(name.isEmpty)
        }
        .padding(12)
        .background(Butter.cream, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Butter.honey, lineWidth: 1))
    }

    private func sendToWishStudio() {
        guard let style = current else { return }
        var fontName = style.fontName
        if tab == 0 {
            saveDraft()
            fontName = draft?.fontName ?? fontName
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fontName, forType: .string)
        UserDefaults.standard.set(fontName, forKey: "keydoWishNewFont")
        NotificationCenter.default.post(name: .keydoOpenSection, object: nil, userInfo: ["section": "WishStudio"])
        notice = "\u{201C}\(fontName)\u{201D} is ready in WishStudio, and its name is copied."
    }

    private func saveDraft() {
        guard var style = draft else { return }
        let clean = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        style.name = clean.isEmpty ? "My font" : clean
        if KeyDoFonts.all.contains(where: { $0.name.lowercased() == style.name.lowercased() && $0.id != style.id }) { style.name += " 2" }
        KeyDoFonts.saveUser(style)
        saved = KeyDoFonts.user
        draft = style
        notice = "Saved. \u{201C}\(style.fontName)\u{201D} is now in every font list."
    }

    private func savePNG(_ image: NSImage, _ name: String) {
        guard let data = PhotoCanvas.png(image) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = name.replacingOccurrences(of: " ", with: "-").lowercased() + "-alphabet.png"
        if panel.runModal() == .OK, let url = panel.url { try? data.write(to: url) }
    }
}

// MARK: - Crop

/// Drag over the part of the picture you want. "Use this part" makes it the picture; "Add these letters" cuts the typed letters
/// out of just this part and adds them to the letters you already have, so you can crop one letter at a time.
struct FontCropSheet: View {
    var image: NSImage
    var letters: String
    var onUse: (NSImage) -> Void
    var onAdd: (NSImage, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start: CGPoint?
    @State private var end: CGPoint?
    @State private var typed = ""
    @State private var shown = CGSize(width: 1, height: 1)
    @State private var dragging = false

    private var selection: CGRect? {
        guard let start, let end else { return nil }
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y))
        return rect.width > 6 && rect.height > 6 ? rect : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Crop the picture").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Butter.cocoa)
            Text("Drag over the letter or letters you want. Crop close around them, then use the buttons below.").font(.callout).foregroundStyle(.secondary)
            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 640, maxHeight: 360)
                .background(Color.white)
                .overlay(
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            Color.clear.contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        shown = geo.size
                                        if !dragging { dragging = true; start = clamped(value.startLocation, geo.size) }
                                        end = clamped(value.location, geo.size)
                                    }
                                    .onEnded { _ in dragging = false })
                            if let rect = selection {
                                Rectangle().stroke(Butter.coral, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                    .background(Butter.coral.opacity(0.12))
                                    .frame(width: rect.width, height: rect.height)
                                    .offset(x: rect.minX, y: rect.minY)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                )
                .border(Butter.coral.opacity(0.25))
            HStack(spacing: 8) {
                TextField("Letters in the selection (for example H)", text: $typed).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Button("Add these letters") { if let part = cropped() { onAdd(part, typed); dismiss() } }
                    .buttonStyle(.borderedProminent).tint(Butter.coral).disabled(selection == nil || typed.filter { !$0.isWhitespace }.isEmpty)
                Button("Use this part as my picture") { if let part = cropped() { onUse(part); dismiss() } }
                    .buttonStyle(.bordered).disabled(selection == nil)
                Spacer()
                Button("Cancel") { dismiss() }
            }
        }
        .padding(18)
        .frame(minWidth: 700)
        .onAppear { typed = "" }
    }

    private func clamped(_ point: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: min(max(0, point.x), size.width), y: min(max(0, point.y), size.height))
    }

    /// The selected part, cut from the picture at its full detail.
    private func cropped() -> NSImage? {
        guard let rect = selection, shown.width > 1, shown.height > 1 else { return nil }
        let points = image.size
        let pixels = PhotoCanvas.pixelSize(image)
        let kx = points.width / shown.width, ky = points.height / shown.height
        let source = NSRect(x: rect.minX * kx, y: points.height - (rect.minY + rect.height) * ky, width: rect.width * kx, height: rect.height * ky)
        let scale = pixels.width / max(1, points.width)
        let width = max(2, Int((source.width * scale).rounded())), height = max(2, Int((source.height * scale).rounded()))
        let rep = PhotoCanvas.bitmap(width: width, height: height) { canvas in
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()
            image.draw(in: NSRect(origin: .zero, size: canvas), from: source, operation: .sourceOver, fraction: 1)
        }
        return PhotoCanvas.image(rep)
    }
}

extension KeyDoFontAnalyzer {
    /// A first guess at which letters a picture shows, read with the Mac's text recognition. Empty when it cannot tell.
    static func guessLetters(_ image: NSImage) -> String {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil else { return "" }
        let found = (request.results as? [VNRecognizedTextObservation]) ?? []
        let text = found.compactMap { $0.topCandidates(1).first?.string }.joined()
        return String(text.filter { $0.isLetter || $0.isNumber }.prefix(60))
    }
}
