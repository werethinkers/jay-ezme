import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A shared shelf of transparent PNG backgrounds. Import PNGs, folders or a library zip; export the whole shelf as a zip to publish or share.
@MainActor enum WishBackgroundLibrary {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("KeyDo/BackgroundLibrary", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func files() -> [URL] {
        let list = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return list.filter { $0.pathExtension.lowercased() == "png" }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    @discardableResult static func add(_ image: NSImage, name: String) -> URL? {
        guard let data = TemplateImages.png(image) else { return nil }
        let stem = name.replacingOccurrences(of: "[^A-Za-z0-9 _-]+", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        var url = folder.appendingPathComponent((stem.isEmpty ? "background" : stem) + ".png")
        var count = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(stem.isEmpty ? "background" : stem) \(count).png")
            count += 1
        }
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    /// The older designs: the Birthday and Anniversary cards and the 12 greeting colour designs, drawn as PNGs. Only missing ones are added.
    @discardableResult static func addBuiltIns() -> Int {
        var added = 0
        func put(_ name: String, _ data: Data?) {
            let url = folder.appendingPathComponent(name + ".png")
            guard !FileManager.default.fileExists(atPath: url.path), let data else { return }
            if (try? data.write(to: url, options: .atomic)) != nil { added += 1 }
        }
        put("Birthday card", CelebrationCard.pngData(kind: .birthday, name: "", sender: "", photo: nil))
        put("Anniversary card", CelebrationCard.pngData(kind: .anniversary, name: "", sender: "", photo: nil))
        for design in WishDesigns.greeting { put(design.name, drawDesign(design)) }
        return added
    }

    private static func drawDesign(_ design: WishDesign) -> Data? {
        let side = 1600
        guard let rep = TemplateImages.bitmap(width: side, height: side), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let s = CGFloat(side)
        NSColor(templateHex: design.background).setFill()
        NSRect(x: 0, y: 0, width: s, height: s).fill()
        let accent = NSColor(templateHex: design.accent)
        switch design.layout {
        case "arch":
            accent.withAlphaComponent(0.18).setFill()
            let arch = NSBezierPath(roundedRect: NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8), xRadius: s * 0.4, yRadius: s * 0.4)
            arch.fill()
            accent.setStroke(); arch.lineWidth = 8; arch.stroke()
        case "band":
            accent.withAlphaComponent(0.2).setFill()
            NSRect(x: 0, y: s * 0.38, width: s, height: s * 0.24).fill()
            accent.setFill()
            NSRect(x: 0, y: s * 0.38, width: s, height: 8).fill()
            NSRect(x: 0, y: s * 0.62 - 8, width: s, height: 8).fill()
        default:
            let frame = NSBezierPath(roundedRect: NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88), xRadius: 40, yRadius: 40)
            accent.setStroke(); frame.lineWidth = 12; frame.stroke()
            let inner = NSBezierPath(roundedRect: NSRect(x: s * 0.09, y: s * 0.09, width: s * 0.82, height: s * 0.82), xRadius: 28, yRadius: 28)
            accent.withAlphaComponent(0.5).setStroke(); inner.lineWidth = 4; inner.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// PNG files, folders of PNGs and library zips. Returns how many backgrounds were added.
    static func importItems(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls {
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
            if isFolder.boolValue {
                added += importItems(((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []).filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" })
            } else if url.pathExtension.lowercased() == "zip" {
                let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("keydo-lib-" + String(UUID().uuidString.prefix(6)))
                try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                if run("/usr/bin/ditto", ["-x", "-k", url.path, scratch.path]) { added += importItems([scratch]) }
                try? FileManager.default.removeItem(at: scratch)
            } else if url.pathExtension.lowercased() == "png", let image = NSImage(contentsOf: url), add(image, name: url.deletingPathExtension().lastPathComponent) != nil {
                added += 1
            }
        }
        return added
    }

    static func exportZip(to destination: URL) -> Bool {
        try? FileManager.default.removeItem(at: destination)
        return run("/usr/bin/ditto", ["-c", "-k", folder.path, destination.path])
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 } catch { return false }
    }
}

struct WishLibrarySheet: View {
    var appID: String
    var onUse: ([NSImage]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var files: [URL] = WishBackgroundLibrary.files()
    @State private var chosen: Set<URL> = []
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Background library").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(.bordered)
            }
            Text("Keep your transparent PNG backgrounds here. Import a library someone shared, or download yours as a zip to publish or send.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button { importFromDisk() } label: { Label("Import PNGs, folder or zip", systemImage: "square.and.arrow.down") }
                Button { addFromApp() } label: { Label("Add this app's backgrounds", systemImage: "plus.square.on.square") }
                Button { let added = WishBackgroundLibrary.addBuiltIns(); message = added == 0 ? "The older designs are already in the library." : "Added \(added) older designs (Birthday, Anniversary and colour designs)."; reload() } label: { Label("Add older designs", systemImage: "clock.arrow.circlepath") }
                Button { download() } label: { Label("Download library (zip)", systemImage: "arrow.down.to.line") }.disabled(files.isEmpty)
            }
            if files.isEmpty {
                ContentUnavailableView("The library is empty", systemImage: "photo.stack", description: Text("Import PNG files or a library zip to fill it."))
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                        ForEach(files, id: \.self) { url in
                            Button { if chosen.contains(url) { chosen.remove(url) } else { chosen.insert(url) } } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.93))
                                        if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFit().padding(4) }
                                    }
                                    .frame(height: 110)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(chosen.contains(url) ? Butter.coral : Color.secondary.opacity(0.3), lineWidth: chosen.contains(url) ? 3 : 1))
                                    Text(url.deletingPathExtension().lastPathComponent).font(.caption).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu { Button("Remove from library", role: .destructive) { remove(url) } }
                        }
                    }
                    .padding(2)
                }
                .frame(height: 300)
            }
            HStack {
                Text(message).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !chosen.isEmpty { Button("Remove selected", role: .destructive) { chosen.forEach { remove($0) } }.buttonStyle(.bordered) }
                Button { useChosen() } label: { Label("Use \(chosen.count) in this app", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent).tint(Butter.coral).disabled(chosen.isEmpty)
            }
        }
        .padding(22).frame(width: 680)
        .onAppear {
            if !UserDefaults.standard.bool(forKey: "wishLibraryBuiltInsAdded") {
                UserDefaults.standard.set(true, forKey: "wishLibraryBuiltInsAdded")
                let added = WishBackgroundLibrary.addBuiltIns()
                if added > 0 { message = "Your older designs (Birthday, Anniversary and colour designs) are now in the library."; reload() }
            }
        }
    }

    private func reload() { files = WishBackgroundLibrary.files(); chosen = chosen.filter { files.contains($0) } }

    private func remove(_ url: URL) { try? FileManager.default.removeItem(at: url); chosen.remove(url); reload() }

    private func importFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .zip, .folder]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose PNG backgrounds, a folder of them, or a library zip"
        guard panel.runModal() == .OK else { return }
        let added = WishBackgroundLibrary.importItems(panel.urls)
        message = added == 0 ? "No PNG backgrounds were found." : "Added \(added) to the library."
        reload()
    }

    private func addFromApp() {
        var added = 0
        for file in WishLookStore.files(appID) {
            if let image = WishLookStore.image(file), WishBackgroundLibrary.add(image, name: "Background") != nil { added += 1 }
        }
        message = added == 0 ? "This app has no backgrounds yet." : "Added \(added) from this app."
        reload()
    }

    private func download() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "KeyDo Background Library.zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        message = WishBackgroundLibrary.exportZip(to: url) ? "Saved \(url.lastPathComponent). Share it, and others can import it here." : "Could not save the zip."
    }

    private func useChosen() {
        let images = files.filter { chosen.contains($0) }.compactMap { NSImage(contentsOf: $0) }
        onUse(images)
        dismiss()
    }
}
