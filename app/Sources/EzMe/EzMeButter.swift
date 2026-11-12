import SwiftUI
import AppKit

/// "Butter Desk" look: butter and cocoa, coral accents, top tabs instead of a sidebar.
enum Butter {
    static let butter = Color(red: 0.941, green: 0.894, blue: 0.776)
    static let cream = Color(red: 0.973, green: 0.941, blue: 0.855)
    static let cocoa = Color(red: 0.227, green: 0.165, blue: 0.122)
    static let coral = Color(red: 0.851, green: 0.412, blue: 0.310)
    static let honey = Color(red: 0.886, green: 0.812, blue: 0.624)
    static let dustyBlue = Color(red: 0.553, green: 0.702, blue: 0.769)
    static let sage = Color(red: 0.718, green: 0.804, blue: 0.671)
    static let blush = Color(red: 0.922, green: 0.714, blue: 0.639)
}

/// The five top-level tabs, built from the same list the old sidebar used so nothing goes missing.
struct ButterArea: Identifiable {
    var id: String
    var title: String
    var icon: String
    var items: [EzMeNavigation.Item]
}

enum ButterNav {
    static let areas: [ButterArea] = {
        let src = EzMeNavigation.areas
        func items(_ i: Int) -> [EzMeNavigation.Item] { i < src.count ? src[i].items : [] }
        return [
            ButterArea(id: "Home", title: "Home", icon: "house", items: items(0)),
            ButterArea(id: "Library", title: "Library", icon: "books.vertical", items: items(1)),
            ButterArea(id: "Create", title: "Create", icon: "wand.and.stars", items: items(2)),
            ButterArea(id: "Apps", title: "Apps & web", icon: "globe", items: items(3)),
            ButterArea(id: "Setup", title: "Setup", icon: "gearshape", items: items(4)),
        ]
    }()

    static func item(for section: String) -> EzMeNavigation.Item? {
        for a in areas { if let i = a.items.first(where: { $0.id == section }) { return i } }
        return nil
    }

    static func area(containing section: String) -> ButterArea {
        areas.first(where: { $0.items.contains(where: { $0.id == section }) }) ?? areas[0]
    }
}

/// Top tabs, with a row of sub-tab pills for the open tab. Replaces the purple sidebar and header.
struct ButterTopBar: View {
    @Binding var section: String
    var browserPanelVisible: Bool
    var browserWidth: CGFloat
    var onPanelSize: (CGFloat) -> Void
    var onFullScreen: () -> Void
    var onToggleBrowser: () -> Void
    var onOpen: (String) -> Void

    var body: some View {
        let current = ButterNav.area(containing: section)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("KeyDo")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(Butter.cocoa)
                    .padding(.trailing, 10)
                ForEach(ButterNav.areas) { area in
                    Button {
                        if let first = area.items.first { onOpen(first.id) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: area.icon)
                            Text(area.title)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(area.id == current.id ? Butter.cream : Butter.cocoa)
                        .background(area.id == current.id ? Butter.cocoa : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(area.items.map { $0.title }.joined(separator: ", "))
                }
                Spacer()
                ButterUpdateButton()
                Menu {
                    Button(browserPanelVisible ? "Hide browser panel" : "Show browser panel", action: onToggleBrowser)
                    Divider()
                    Button("Small panel") { onPanelSize(360) }
                    Button("Medium panel") { onPanelSize(560) }
                    Button("Large panel") { onPanelSize(820) }
                    Button("Huge panel") { onPanelSize(1100) }
                    Divider()
                    Button("Full screen browser") { onFullScreen() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sidebar.right")
                        Text(browserPanelVisible ? "Browser panel" : "Browser")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .foregroundStyle(Butter.cocoa)
                    .overlay(Capsule().stroke(Butter.honey, lineWidth: 1.5))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 18).padding(.vertical, 10)

            if current.items.count > 1 {
                HStack(spacing: 6) {
                    ForEach(current.items) { item in
                        Button { onOpen(item.id) } label: {
                            Text(item.title)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 11).padding(.vertical, 5)
                                .foregroundStyle(section == item.id ? Butter.cocoa : Butter.cocoa.opacity(0.7))
                                .background(section == item.id ? Butter.honey : Color.clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(item.hint)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18).padding(.bottom, 9)
            }
            if let item = ButterNav.item(for: section) {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(Butter.coral)
                    Text(item.hint).font(.system(size: 13, weight: .medium)).foregroundStyle(Butter.cocoa)
                    Spacer()
                }
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(Butter.honey.opacity(0.35))
            }
            Rectangle().fill(Butter.honey).frame(height: 1)
        }
        .background(Butter.cream)
    }
}

/// One pill-shaped bar used wherever EzMe asks for a search: it finds things, and takes a plain sentence too.
struct MerlinBar: View {
    @Binding var text: String
    var placeholder: String = "Find a shortcut, or tell Merlin what you need"
    var onSubmit: () -> Void = {}
    /// Extra height for the browser address bar (about 20% taller than the search bars).
    var verticalPadding: CGFloat = 11
    var showsBadge = true
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Butter.coral)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(Butter.cocoa)
                .focused($focused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Butter.cocoa.opacity(0.4)) }
                    .buttonStyle(.plain)
            }
            if showsBadge {
                Text("Merlin")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .foregroundStyle(Butter.cream)
                    .background(Butter.coral, in: Capsule())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, verticalPadding)
        .background(Butter.cream, in: Capsule())
        .overlay(Capsule().stroke(focused ? Butter.coral : Butter.honey, lineWidth: focused ? 2 : 1.5))
    }
}

/// Collapsible section. Use this instead of long open lists.
struct ButterAccordion<Content: View>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    @State private var open: Bool
    private let content: Content

    init(_ title: String, subtitle: String? = nil, icon: String? = nil, open: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self._open = State(initialValue: open)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { open.toggle() }
            } label: {
                HStack(spacing: 12) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .foregroundStyle(Butter.coral)
                            .frame(width: 30, height: 30)
                            .background(Butter.butter, in: RoundedRectangle(cornerRadius: 9))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Butter.cocoa)
                        if let subtitle = subtitle {
                            Text(subtitle).font(.system(size: 12)).foregroundStyle(Butter.cocoa.opacity(0.65))
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Butter.cocoa.opacity(0.6))
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                Rectangle().fill(Butter.honey.opacity(0.7)).frame(height: 1)
                content.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Butter.cream, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Butter.honey, lineWidth: 1.5))
    }
}

/// Reads a picture from disk once and remembers it, so screens stop re-reading files on every redraw.
enum EzMeImageCache {
    private static let cache = NSCache<NSString, NSImage>()
    static func load(contentsOfFile path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        var stamp: TimeInterval = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path), let d = attrs[.modificationDate] as? Date { stamp = d.timeIntervalSince1970 }
        let key = "\(path)|\(stamp)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// "Check for updates" in the top bar. Turns coral with "Update ready" when a new build is out.
struct ButterUpdateButton: View {
    @ObservedObject private var updater = EzMeUpdater.shared

    var body: some View {
        Button { updater.checkFromMenu() } label: {
            HStack(spacing: 6) {
                Image(systemName: updater.updateAvailable ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath")
                Text(updater.updateAvailable ? "Update ready" : "Check for updates")
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .foregroundStyle(updater.updateAvailable ? Butter.cream : Butter.cocoa)
            .background(updater.updateAvailable ? Butter.coral : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(updater.updateAvailable ? Butter.coral : Butter.honey, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help("Version \(updater.currentVersion) (build \(updater.currentBuild))")
    }
}

/// Drag this thin bar to make the browser panel as wide as you like.
struct ButterResizeHandle: View {
    @Binding var width: CGFloat
    @State private var startWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Butter.honey)
            .frame(width: 5)
            .overlay(Capsule().fill(Butter.cocoa.opacity(0.35)).frame(width: 3, height: 36))
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if startWidth == nil { startWidth = width }
                    width = min(1400, max(320, (startWidth ?? width) - value.translation.width))
                }
                .onEnded { _ in startWidth = nil })
            .help("Drag to resize the browser")
    }
}

extension Notification.Name {
    static let ezmeOpenBuilderApp = Notification.Name("EzMeOpenBuilderApp")
    static let ezmeOpenSite = Notification.Name("EzMeOpenSite")
}

struct EzMeBuilderHit: Identifiable {
    var id: String { name }
    let name: String
    let detail: String
    let iconPath: String?
    var score: Int = 0
}

/// Things the search can find besides shortcuts: AppBuilder cards and saved websites. Matching understands plain sentences.
enum EzMeSearchSources {
    static var savedSites: () -> [EzMeSavedSite] = { [] }

    static func builderApps(matching query: String) -> [EzMeBuilderHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let json = UserDefaults.standard.string(forKey: "ezmeCustomBuilderAppsJSON") ?? "[]"
        let custom = (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
        var names = ["Collection Builder", "MyDatabase"]
        for name in custom where !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { names.append(name) }
        var hits: [EzMeBuilderHit] = []
        for name in names {
            let detail = UserDefaults.standard.string(forKey: "ezmeBuilderDescription." + name)
                ?? UserDefaults.standard.string(forKey: "ezmeBuilderPrompt." + name) ?? "AppBuilder app"
            let score = EzMeWords.looseScore(query: q, title: name, detail: detail)
            if score > 0 || name.localizedCaseInsensitiveContains(q) {
                hits.append(EzMeBuilderHit(name: name, detail: detail, iconPath: UserDefaults.standard.string(forKey: "ezmeBuilderAppIcon." + name), score: max(score, 1)))
            }
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(6))
    }

    static func score(site: EzMeSavedSite, query: String) -> Int {
        EzMeWords.looseScore(query: query, title: site.title, detail: site.url, extra: site.tags + [site.note, site.collection])
    }

    static func sites(matching query: String) -> [EzMeSavedSite] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let scored = savedSites().map { ($0, score(site: $0, query: q)) }
            .filter { $0.1 > 0 || $0.0.title.localizedCaseInsensitiveContains(q) || $0.0.url.localizedCaseInsensitiveContains(q) }
        return Array(scored.sorted { $0.1 > $1.1 }.prefix(6).map { $0.0 })
    }
}

/// A search result card for things that are not plain shortcuts (AppBuilder cards, websites).
struct ButterHitRow: View {
    let title: String
    let subtitle: String
    let badge: String
    let symbol: String
    var iconPath: String? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Group {
                    if let path = iconPath, let image = EzMeImageCache.load(contentsOfFile: path) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: symbol).font(.system(size: 22, weight: .medium)).foregroundStyle(Butter.coral)
                    }
                }
                .frame(width: 56, height: 50)
                .background(Butter.butter)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Butter.cocoa).lineLimit(1)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Butter.cocoa.opacity(0.65)).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                Text(badge).font(.system(size: 10, weight: .heavy)).foregroundStyle(Butter.cocoa)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Butter.honey.opacity(0.7), in: Capsule())
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover ? Butter.honey.opacity(0.45) : Butter.cream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Butter.honey, lineWidth: 1.2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Lets the search popup ask the main window to open an AppBuilder card or a website.
struct EzMeOpenRequests: ViewModifier {
    @Binding var section: String
    var openSite: (String) -> Void
    var sendPrompt: (PromptDispatchRequest) -> Void = { _ in }

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .ezmeOpenBuilderApp)) { _ in
                section = "AppBuilder"
                UserDefaults.standard.set(true, forKey: "ezmeAppBuilderHasSeenHome")
                NSApp.activate(ignoringOtherApps: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .keydoSendPrompt)) { note in
                if let request = note.object as? PromptDispatchRequest { sendPrompt(request) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ezmeOpenSite)) { note in
                if let url = note.userInfo?["url"] as? String {
                    openSite(url)
                    section = "Browser"
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}
