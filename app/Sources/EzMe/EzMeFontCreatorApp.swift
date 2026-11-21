// Font Creator: an AppBuilder app. Upload a picture of one letter, KeyDo reads its weight, corners, lean and colours and
// builds a whole A to Z and 0 to 9 font in that look. The ten built-in fonts are shown too. Saved fonts show in every font list.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FontCreatorApp: View {
    @State private var tab = 0
    @State private var sample = "Happy Birthday"
    @State private var letter: NSImage?
    @State private var letterName = ""
    @State private var draft: KeyDoFontStyle?
    @State private var fontName = ""
    @State private var chosenID = "summit-block"
    @State private var saved: [KeyDoFontStyle] = KeyDoFonts.user
    @State private var notice = ""

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
                        Text("Upload a picture of one letter and get a whole alphabet in that look. Use it in Wish Studio and every design.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Picker("", selection: $tab) {
                    Text("Make from a letter").tag(0)
                    Text("10 KeyDo fonts").tag(1)
                    Text("My fonts (\(saved.count))").tag(2)
                }.labelsHidden().pickerStyle(.segmented)

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
                notice = "Read the letter. Adjust the look below, then save."
            }
            if let draft {
                Text("2. Fine tune").font(.system(size: 13, weight: .bold, design: .rounded))
                TextField("Font name", text: $fontName).textFieldStyle(.roundedBorder)
                let binding = Binding<KeyDoFontStyle>(get: { self.draft ?? draft }, set: { self.draft = $0 })
                HStack { Text("Thickness").font(.caption).frame(width: 80, alignment: .leading); Slider(value: binding.weight, in: 0.04...0.3) }
                HStack { Text("Width").font(.caption).frame(width: 80, alignment: .leading); Slider(value: binding.width, in: 0.7...1.3) }
                HStack { Text("Lean").font(.caption).frame(width: 80, alignment: .leading); Slider(value: binding.slant, in: -20...20) }
                HStack { Text("Spacing").font(.caption).frame(width: 80, alignment: .leading); Slider(value: binding.spacing, in: 0...0.2) }
                Picker("Corners", selection: binding.cap) { Text("Flat").tag(0); Text("Round").tag(1); Text("Square").tag(2) }.pickerStyle(.segmented)
                Picker("Style", selection: binding.mode) { ForEach(0..<KeyDoFontStyle.modes.count, id: \.self) { Text(KeyDoFontStyle.modes[$0]).tag($0) } }
                if !draft.palette.isEmpty {
                    HStack(spacing: 6) {
                        Text("Colours found").font(.caption)
                        ForEach(draft.palette, id: \.self) { hex in Circle().fill(Color(nsColor: NSColor(templateHex: hex))).frame(width: 18, height: 18) }
                    }
                }
                Button { saveDraft() } label: { Label("Save font", systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent).tint(Butter.coral)
            }
        }
        .padding(12).background(Butter.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
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
