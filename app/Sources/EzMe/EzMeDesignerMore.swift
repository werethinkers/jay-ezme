// "More looks": turns a finished AppDesigner design into a ready prompt plus its pictures, and sends them to ChatGPT or Gemini
// in the browser side panel so 2 to 5 more template options come back.
import SwiftUI
import AppKit

enum DesignMorePrompt {
    /// What the AI is told about the design. The printed text, logo, icons and pictures stay; the named boxes are the variables.
    @MainActor static func text(for design: AppDesign, pages: [ImageTemplate], count: Int) -> String {
        let title = design.appTitle ?? design.name
        var lines = [String]()
        lines.append("I am designing a template called \"\(title)\". The attached picture\(pages.count == 1 ? " is" : "s are") its current page\(pages.count == 1 ? "" : "s").")
        lines.append("Create \(count) more template options for it. Each option must look clearly different (layout, colours, type style) while keeping the same size and the same content.")
        lines.append("")
        lines.append("KEEP exactly as in the pictures: every fixed text, image, logo and icon. The variable boxes are empty in the pictures on purpose; there is no sample text to copy.")
        lines.append("LEAVE as named placeholders, in the same place, written like {{name}}: the boxes below. These are variables, formulas and collection values that my app fills in later, so do not replace them with sample text.")
        for (index, page) in pages.enumerated() {
            lines.append("")
            lines.append("Page \(index + 1): \(page.pixelWidth) x \(page.pixelHeight) px")
            for slot in page.slots {
                let place = "centre \(Int(slot.cx * 100))% across and \(Int(slot.cy * 100))% down, \(Int(slot.w * 100))% wide, \(Int(slot.h * 100))% tall"
                lines.append("- {{\(slot.key)}}: \(slot.kind == .text ? "text" : (slot.kind == .image ? "picture" : "logo")) box, \(place)")
            }
        }
        if !design.variables.isEmpty {
            lines.append("")
            lines.append("Variables that start with a value (keep the names): " + design.variables.keys.sorted().joined(separator: ", "))
        }
        lines.append("")
        lines.append("Give each option a short name, then the finished picture at the same pixel size. If you cannot draw pictures, give clean HTML and CSS for each option with the {{placeholders}} untouched.")
        return lines.joined(separator: "\n")
    }

    /// PNG copies of the design's pages, saved in a temporary folder so the browser can upload them.
    @MainActor static func pictures(for pages: [ImageTemplate]) -> [String] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KeyDoMoreLooks-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var paths = [String]()
        for (index, page) in pages.enumerated() {
            guard let base = TemplateStore.shared.basePicture(for: page),
                  let image = TemplateRenderer.render(page, base: base, texts: [:], images: [:], useSamples: false, maxSide: 1600),
                  let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { continue }
            let file = folder.appendingPathComponent("template-page-\(index + 1).png")
            if (try? png.write(to: file)) != nil { paths.append(file.path) }
        }
        return paths
    }
}

struct DesignMoreLooksSheet: View {
    let designID: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var designs = AppDesignStore.shared
    @State private var count = 3
    @State private var prompt = ""
    @State private var pictures = [String]()
    @State private var status = ""

    private var design: AppDesign? { designs.design(id: designID) }
    private var pages: [ImageTemplate] { design.map { TemplateLinks.pages(for: "design:" + $0.id) } ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles.rectangle.stack.fill").foregroundStyle(Butter.coral).font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("More looks for \(design?.appTitle ?? design?.name ?? "this design")").font(.system(size: 16, weight: .bold)).foregroundStyle(Butter.cocoa)
                    Text("Your fixed text, logos and icons stay. Variables, functions and collections stay as placeholders.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            HStack(spacing: 10) {
                Stepper("Options: \(count)", value: $count, in: 2...5).onChange(of: count) { _, _ in rebuild() }.frame(width: 150)
                Text("\(pictures.count) picture\(pictures.count == 1 ? "" : "s") attached").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { rebuild() } label: { Label("Refresh prompt", systemImage: "arrow.clockwise") }.controlSize(.small)
            }
            TextEditor(text: $prompt).font(.system(size: 12)).frame(minHeight: 190).padding(6)
                .background(Butter.cream, in: RoundedRectangle(cornerRadius: 10))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(pictures, id: \.self) { path in
                        if let image = NSImage(contentsOfFile: path) { Image(nsImage: image).resizable().scaledToFit().frame(height: 64).clipShape(RoundedRectangle(cornerRadius: 6)) }
                    }
                }
            }
            HStack(spacing: 8) {
                Button { send("ChatGPT") } label: { Label("Send to ChatGPT", systemImage: "paperplane.fill") }.buttonStyle(.borderedProminent).tint(Butter.coral)
                Button { send("Gemini") } label: { Label("Send to Gemini", systemImage: "paperplane.fill") }.buttonStyle(.borderedProminent).tint(Butter.coral)
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(prompt, forType: .string); status = "Prompt copied." } label: { Label("Copy", systemImage: "doc.on.doc") }
                Spacer()
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(Butter.cocoa) }
            Text("The browser opens in the side panel, the pictures are added and the prompt is sent. Sign in on the site once if it asks.").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16).frame(width: 560, height: 560)
        .onAppear { rebuild() }
    }

    private func rebuild() {
        guard let design else { return }
        pictures = DesignMorePrompt.pictures(for: pages)
        prompt = DesignMorePrompt.text(for: design, pages: pages, count: count)
    }

    private func send(_ site: String) {
        guard let target = PromptTargets.load().first(where: { $0.name == site }) else { status = "\(site) is not in your Prompt Builder sites. Add it there first."; return }
        NotificationCenter.default.post(name: .keydoSendPrompt, object: PromptDispatchRequest(target: target, prompt: prompt, files: pictures))
        status = "Opening \(site) in the side panel with \(pictures.count) picture\(pictures.count == 1 ? "" : "s") and your prompt…"
    }
}
