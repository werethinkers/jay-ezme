// Ez Tools (was Ez Studio): every tool is its own tab, in a clean row like the apps in WishStudio.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct EzToolDef: Identifiable {
    let id: String
    let title: String
    let hint: String
    let symbol: String
    let colors: [Color]
}

enum EzTools {
    static let all: [EzToolDef] = [
        EzToolDef(id: "Image Studio", title: "Image Studio", hint: "Draw pictures with AI", symbol: "paintbrush.pointed.fill",
                  colors: [Color(red: 0.93, green: 0.35, blue: 0.62), Color(red: 0.55, green: 0.36, blue: 0.96)]),
        EzToolDef(id: "ChatGPT Image Edit", title: "Image Edit", hint: "Fix or change a picture", symbol: "wand.and.stars",
                  colors: [Color(red: 0.98, green: 0.55, blue: 0.25), Color(red: 0.90, green: 0.33, blue: 0.31)]),
        EzToolDef(id: "Media Resizer", title: "Resize and Crop", hint: "Any size, any shape", symbol: "crop",
                  colors: [Color(red: 0.30, green: 0.65, blue: 0.98), Color(red: 0.20, green: 0.45, blue: 0.90)]),
        EzToolDef(id: "Video Editor", title: "Video Editor", hint: "Cut, join and trim", symbol: "film.fill",
                  colors: [Color(red: 0.55, green: 0.85, blue: 0.35), Color(red: 0.12, green: 0.70, blue: 0.62)]),
        EzToolDef(id: "Photo Collage", title: "Photo Collage", hint: "Many photos, one picture", symbol: "square.grid.3x3.fill",
                  colors: [Color(red: 0.99, green: 0.78, blue: 0.25), Color(red: 0.96, green: 0.40, blue: 0.55)]),
        EzToolDef(id: "Logo on Background", title: "Logo on Background", hint: "Put your logo on a scene", symbol: "photo.on.rectangle.angled",
                  colors: [Color(red: 0.40, green: 0.75, blue: 0.90), Color(red: 0.35, green: 0.40, blue: 0.85)]),
        EzToolDef(id: "Bollywood 80s", title: "Bollywood 80s", hint: "Retro film poster look", symbol: "star.fill",
                  colors: [Color(red: 0.95, green: 0.40, blue: 0.35), Color(red: 0.70, green: 0.25, blue: 0.55)]),
        EzToolDef(id: "Font Creator", title: "Font Creator", hint: "Make your own letters", symbol: "textformat",
                  colors: [Color(red: 0.55, green: 0.50, blue: 0.95), Color(red: 0.30, green: 0.30, blue: 0.75)])
    ]
}

/// The row of tool tabs. The chosen tab is filled with its colour; the others are quiet cards.
struct EzToolTabs: View {
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(EzTools.all) { tool in tab(tool) }
            }
            .padding(.vertical, 4).padding(.horizontal, 2)
        }
    }

    @State private var pictureRevision = 0

    @ViewBuilder private func toolIcon(_ tool: EzToolDef) -> some View {
        let _ = pictureRevision
        if let picture = EzToolPictures.image(EzToolPictures.tabKey(tool.id)) {
            Color.clear.frame(width: 34, height: 34)
                .overlay { Image(nsImage: picture).resizable().scaledToFill() }
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Image(systemName: tool.symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(LinearGradient(colors: tool.colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func tab(_ tool: EzToolDef) -> some View {
        let on = selected == tool.id
        return Button { withAnimation(.easeInOut(duration: 0.15)) { selected = tool.id } } label: {
            HStack(spacing: 10) {
                toolIcon(tool)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.title).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                    Text(tool.hint).font(.system(size: 10, weight: .medium)).lineLimit(1).opacity(0.7)
                }
            }
            .foregroundStyle(Butter.cocoa)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14).fill(on ? Butter.honey.opacity(0.35) : Color.white))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Butter.coral : Butter.honey.opacity(0.7), lineWidth: on ? 2 : 1))
            .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Change picture…") { if EzToolPictures.choose(EzToolPictures.tabKey(tool.id)) { pictureRevision += 1 } }
            if EzToolPictures.image(EzToolPictures.tabKey(tool.id)) != nil {
                Button("Reset picture") { EzToolPictures.clear(EzToolPictures.tabKey(tool.id)); pictureRevision += 1 }
            }
        }
    }
}

/// Your own pictures for Ez Tools: the page cover and a picture for each tool tab. Copies are kept inside KeyDo.
enum EzToolPictures {
    static let coverKey = "keydoEzToolsCoverPath"
    static func tabKey(_ id: String) -> String { "keydoEzToolPic." + id }

    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyDo", isDirectory: true).appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func image(_ key: String) -> NSImage? {
        guard let path = UserDefaults.standard.string(forKey: key), !path.isEmpty else { return nil }
        return NSImage(contentsOfFile: path)
    }

    /// Asks for a picture, keeps a copy, and remembers it. Returns true when something was chosen.
    @MainActor @discardableResult static func choose(_ key: String) -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use picture"
        guard panel.runModal() == .OK, let source = panel.url else { return false }
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let name = key.replacingOccurrences(of: ".", with: "-") + "-" + String(Int(Date().timeIntervalSince1970)) + "." + ext
        let target = folder.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: source, to: target)
        } catch { return false }
        if let old = UserDefaults.standard.string(forKey: key), old != target.path { try? FileManager.default.removeItem(atPath: old) }
        UserDefaults.standard.set(target.path, forKey: key)
        return true
    }

    static func clear(_ key: String) {
        if let old = UserDefaults.standard.string(forKey: key) { try? FileManager.default.removeItem(atPath: old) }
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// The wide cover at the top of Ez Tools. Change it to any picture, or go back to the colour cover.
struct EzToolsBanner: View {
    @AppStorage(EzToolPictures.coverKey) private var coverPath = ""
    @State private var hover = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cover
            LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 14) {
                Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ez Tools").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    Text("Pick a tool below. Draw, fix, resize, edit video and make fonts.").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                HStack(spacing: 8) {
                    Button { if EzToolPictures.choose(EzToolPictures.coverKey) { coverPath = UserDefaults.standard.string(forKey: EzToolPictures.coverKey) ?? "" } } label: {
                        Label("Change cover", systemImage: "photo.badge.plus")
                    }
                    if !coverPath.isEmpty {
                        Button { EzToolPictures.clear(EzToolPictures.coverKey); coverPath = "" } label: { Label("Reset", systemImage: "arrow.uturn.backward") }
                    }
                }
                .buttonStyle(.borderedProminent).tint(Color.black.opacity(0.45)).controlSize(.small)
                .opacity(hover || coverPath.isEmpty ? 1 : 0.0)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(height: 124)
        .frame(maxWidth: .infinity)
        .clipped()
        .onHover { hover = $0 }
        .contextMenu {
            Button("Change cover…") { if EzToolPictures.choose(EzToolPictures.coverKey) { coverPath = UserDefaults.standard.string(forKey: EzToolPictures.coverKey) ?? "" } }
            if !coverPath.isEmpty { Button("Reset cover") { EzToolPictures.clear(EzToolPictures.coverKey); coverPath = "" } }
        }
    }

    @ViewBuilder private var cover: some View {
        if !coverPath.isEmpty, let image = NSImage(contentsOfFile: coverPath) {
            Color.clear.overlay { Image(nsImage: image).resizable().scaledToFill() }.clipped()
        } else {
            LinearGradient(colors: [Color(red: 0.98, green: 0.50, blue: 0.35), Color(red: 0.92, green: 0.30, blue: 0.55), Color(red: 0.50, green: 0.36, blue: 0.92)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
