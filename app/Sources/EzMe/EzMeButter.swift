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
    var onToggleBrowser: () -> Void
    var onOpen: (String) -> Void

    var body: some View {
        let current = ButterNav.area(containing: section)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("EzMe")
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
                Button(action: onToggleBrowser) {
                    HStack(spacing: 6) {
                        Image(systemName: "sidebar.right")
                        Text(browserPanelVisible ? "Hide browser" : "Browser panel")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .foregroundStyle(Butter.cocoa)
                    .overlay(Capsule().stroke(Butter.honey, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
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
            Text("Merlin")
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .foregroundStyle(Butter.cream)
                .background(Butter.coral, in: Capsule())
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
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
