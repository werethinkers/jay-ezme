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
    static let home = EzToolDef(id: "Home", title: "Home", hint: "All your tools", symbol: "house.fill",
                                colors: [Color(red: 0.98, green: 0.50, blue: 0.35), Color(red: 0.92, green: 0.30, blue: 0.55)])
    static let details: [String: (category: String, text: String)] = [
        "Image Studio": ("AI pictures", "Describe a picture and draw it with AI, or start from one of yours."),
        "ChatGPT Image Edit": ("AI pictures", "Fix, restyle or change a picture by telling AI what to do."),
        "Media Resizer": ("Resize", "Crop and resize to any size or shape, ready for WhatsApp, Instagram or print."),
        "Video Editor": ("Video", "Cut, join and trim video clips and save them as shortcuts or files."),
        "Photo Collage": ("Photo tool", "Put many photos into one neat picture."),
        "Logo on Background": ("Photo tool", "Place your logo on a scene or a plain colour in one step."),
        "Bollywood 80s": ("Photo tool", "Turn a photo into a retro Bollywood film poster."),
        "Font Creator": ("Fonts", "Make a whole alphabet from one letter and use it in WishStudio.")
    ]
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
                tab(EzTools.home)
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
        panel.allowedContentTypes = [.image, .gif, .movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use as cover"
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

/// The wide cover. On Home it is the Ez Tools cover; on a tool it is that tool's own cover. Image, GIF or video.
struct EzToolsBanner: View {
    var showsTitle = true
    var toolId: String? = nil
    var height: CGFloat = 124
    @AppStorage private var coverPath: String
    @State private var hover = false

    init(showsTitle: Bool = true, toolId: String? = nil, height: CGFloat = 124) {
        self.showsTitle = showsTitle
        self.toolId = toolId
        self.height = height
        _coverPath = AppStorage(wrappedValue: "", toolId == nil ? EzToolPictures.coverKey : EzToolPictures.tabKey(toolId!))
    }

    private var key: String { toolId == nil ? EzToolPictures.coverKey : EzToolPictures.tabKey(toolId!) }
    private var tool: EzToolDef? { EzTools.all.first { $0.id == toolId } }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cover
            LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(showsTitle ? 0.55 : 0.2)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
            HStack(alignment: .bottom, spacing: 14) {
                if showsTitle {
                    Image(systemName: tool?.symbol ?? "wrench.and.screwdriver.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 46, height: 46).background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool?.title ?? "Ez Tools").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        Text(tool.map { EzTools.details[$0.id]?.text ?? $0.hint } ?? "Pick a tool below. Draw, fix, resize, edit video and make fonts.")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Button { if EzToolPictures.choose(key) { coverPath = UserDefaults.standard.string(forKey: key) ?? "" } } label: {
                        Label(coverPath.isEmpty ? "Add cover" : "Change cover", systemImage: "photo.badge.plus")
                    }
                    if !coverPath.isEmpty {
                        Button { EzToolPictures.clear(key); coverPath = "" } label: { Label("Reset", systemImage: "arrow.uturn.backward") }
                    }
                }
                .buttonStyle(.borderedProminent).tint(Color.black.opacity(0.45)).controlSize(.small)
                .opacity(hover || coverPath.isEmpty ? 1 : 0.0)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .onHover { hover = $0 }
        .contextMenu {
            Button("Change cover\u{2026}") { if EzToolPictures.choose(key) { coverPath = UserDefaults.standard.string(forKey: key) ?? "" } }
            if !coverPath.isEmpty { Button("Reset cover") { EzToolPictures.clear(key); coverPath = "" } }
        }
    }

    @ViewBuilder private var cover: some View {
        if !coverPath.isEmpty, FileManager.default.fileExists(atPath: coverPath) {
            EzCoverMedia(path: coverPath).id(coverPath)
        } else {
            LinearGradient(colors: tool?.colors ?? [Color(red: 0.98, green: 0.50, blue: 0.35), Color(red: 0.92, green: 0.30, blue: 0.55), Color(red: 0.50, green: 0.36, blue: 0.92)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Home page (same look as the WishStudio home)

struct EzToolsHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 24)).foregroundStyle(Color.white)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Color(red: 0.98, green: 0.50, blue: 0.35), Color(red: 0.92, green: 0.30, blue: 0.55), Color(red: 0.50, green: 0.36, blue: 0.92)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Ez Tools").font(.system(size: 23, weight: .bold, design: .rounded))
                Text("Draw, fix, resize, edit video and make fonts. Pick a tool to begin.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
    }
}

struct EzToolsHome: View {
    @Binding var selected: String
    @State private var pictureRevision = 0

    var body: some View {
        let _ = pictureRevision
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                EzToolsBanner(showsTitle: false).frame(height: 124).clipShape(RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose a tool to get started").font(.system(size: 25, weight: .bold, design: .rounded))
                    Text("Each tool opens in its own tab. Use the picture button on a card to give it your own picture, GIF or video.")
                        .foregroundStyle(.secondary).frame(maxWidth: 780, alignment: .leading)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 236, maximum: 300), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(EzTools.all) { tool in card(tool) }
                }
            }
            .padding(26)
            .frame(maxWidth: 1260, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 40)
        }
    }

    private func card(_ tool: EzToolDef) -> some View {
        let key = EzToolPictures.tabKey(tool.id)
        let picture = UserDefaults.standard.string(forKey: key) ?? ""
        let detail = EzTools.details[tool.id]
        return AppGalleryCard(title: tool.title, description: detail?.text ?? tool.hint, sample: "", category: detail?.category ?? "Tool",
                              icon: tool.symbol, iconPath: "", coverPath: FileManager.default.fileExists(atPath: picture) ? picture : "", credits: "",
                              colors: tool.colors, action: { withAnimation(.easeInOut(duration: 0.15)) { selected = tool.id } }, showsCredits: false, badge: "TOOL")
            .overlay(alignment: .topTrailing) {
                Button { if EzToolPictures.choose(key) { pictureRevision += 1 } } label: {
                    Image(systemName: "photo.badge.plus").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .padding(7).background(Color.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain).padding(10).help("Change this tool's picture, GIF or video")
            }
            .contextMenu {
                Button("Change picture, GIF or video\u{2026}") { if EzToolPictures.choose(key) { pictureRevision += 1 } }
                if !picture.isEmpty { Button("Reset picture") { EzToolPictures.clear(key); pictureRevision += 1 } }
            }
    }
}
