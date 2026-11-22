// Home page "Your apps": every app and link in one place. AppDesigner apps, AppBuilder apps, WishStudio apps,
// Ezyourlife apps and your saved links, with chips to narrow the list. One tap opens the app.
import SwiftUI
import AppKit

enum HomeAppKind: String, CaseIterable, Identifiable {
    case designer = "AppDesigner"
    case builder = "AppBuilder"
    case wish = "WishStudio"
    case ezy = "Ezyourlife"
    case link = "Links"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .designer: return "paintpalette.fill"
        case .builder: return "wand.and.stars"
        case .wish: return "party.popper.fill"
        case .ezy: return "sparkles"
        case .link: return "link"
        }
    }

    var colors: [Color] {
        switch self {
        case .designer: return [Color(red: 0.93, green: 0.35, blue: 0.62), Color(red: 0.55, green: 0.36, blue: 0.96)]
        case .builder: return [Color(red: 0.98, green: 0.55, blue: 0.25), Color(red: 0.90, green: 0.33, blue: 0.31)]
        case .wish: return [Color(red: 0.99, green: 0.78, blue: 0.25), Color(red: 0.96, green: 0.40, blue: 0.55)]
        case .ezy: return [Color(red: 0.55, green: 0.85, blue: 0.35), Color(red: 0.12, green: 0.70, blue: 0.62)]
        case .link: return [Color(red: 0.30, green: 0.65, blue: 0.98), Color(red: 0.20, green: 0.45, blue: 0.90)]
        }
    }
}

struct HomeAppTile: Identifiable {
    let id: String
    let kind: HomeAppKind
    let title: String
    let subtitle: String
    let symbol: String
}

struct HomeAppsStrip: View {
    var clips: [Clip]
    var records: [CollectionRecord]
    var links: [EzMeAppLink]
    var onOpenDesigner: () -> Void
    var onOpenBuilder: (String) -> Void
    var onOpenWish: (String) -> Void
    var onOpenEzy: () -> Void
    var onOpenLink: (String) -> Void

    @ObservedObject private var designs = AppDesignStore.shared
    @ObservedObject private var ezy = Ezyourlife.shared
    @AppStorage("ezmeCustomBuilderAppsJSON") private var customJSON = "[]"
    @State private var filter = "All"
    @State private var showAll = false
    @State private var running: String?
    @State private var wishApps: [WishAppIndex.Entry] = []

    private static let builtInBuilders = ["Collection Builder", "MyDatabase", "Prompt Builder", "Template Designer", "Font Creator"]

    private var tiles: [HomeAppTile] {
        var out: [HomeAppTile] = []
        for design in designs.designs where design.version > 0 {
            let format = DesignDynamic.format(design)
            out.append(HomeAppTile(id: "d-" + design.id, kind: .designer, title: design.appTitle ?? design.name, subtitle: format.title, symbol: format.symbol))
        }
        let custom = ((try? JSONDecoder().decode([String].self, from: Data(customJSON.utf8))) ?? []).filter { !AppDeletion.isDeleted($0) }
        var seen = Set<String>()
        for name in HomeAppsStrip.builtInBuilders + PhotoApps.names + custom where seen.insert(name).inserted {
            let shown = name == "MyDatabase" ? "My Files" : name
            out.append(HomeAppTile(id: "b-" + name, kind: .builder, title: shown, subtitle: "AppBuilder", symbol: name == "MyDatabase" ? "folder.fill" : "wand.and.stars"))
        }
        for app in wishApps {
            out.append(HomeAppTile(id: "w-" + app.id, kind: .wish, title: app.name, subtitle: "WishStudio", symbol: "party.popper.fill"))
        }
        for app in ezy.catalogue.filter({ $0.runnable }).prefix(60) {
            out.append(HomeAppTile(id: "e-" + app.id, kind: .ezy, title: app.name, subtitle: app.category, symbol: "sparkles"))
        }
        for link in links {
            out.append(HomeAppTile(id: "l-" + link.id, kind: .link, title: link.name, subtitle: link.category, symbol: "link"))
        }
        return out
    }

    private func counts(_ all: [HomeAppTile]) -> [HomeAppKind: Int] {
        var out: [HomeAppKind: Int] = [:]
        for t in all { out[t.kind, default: 0] += 1 }
        return out
    }

    private func visible(_ all: [HomeAppTile]) -> [HomeAppTile] {
        if filter == "All" {
            // A balanced mix, so a long Ezyourlife list does not push everything else out of sight.
            var mix: [HomeAppTile] = []
            for kind in HomeAppKind.allCases {
                let part = all.filter { $0.kind == kind }
                mix.append(contentsOf: part.prefix(kind == .ezy ? 6 : 8))
            }
            return showAll ? all : mix
        }
        return all.filter { $0.kind.rawValue == filter }
    }

    var body: some View {
        let all = tiles
        let count = counts(all)
        let list = visible(all)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Your apps and links", systemImage: "square.grid.2x2.fill").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Butter.cocoa)
                Spacer()
                Button { onOpenDesigner() } label: { Label("AppDesigner", systemImage: "wand.and.stars") }.buttonStyle(.bordered).controlSize(.small)
            }
            LaunchBox()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("All", count: all.count, kind: nil)
                    ForEach(HomeAppKind.allCases) { kind in
                        if let n = count[kind], n > 0 { chip(kind.rawValue, count: n, kind: kind) }
                    }
                }
            }
            if list.isEmpty {
                Text("Design an app in AppDesigner and publish it, or make one in AppBuilder. It appears here to launch in one click.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 178, maximum: 250), spacing: 10, alignment: .top)], spacing: 10) {
                    ForEach(list) { tile in tileView(tile) }
                }
                if filter == "All" && all.count > list.count && !showAll {
                    Button { withAnimation { showAll = true } } label: { Label("Show all \(all.count)", systemImage: "chevron.down") }
                        .buttonStyle(.bordered).controlSize(.small)
                } else if filter == "All" && showAll {
                    Button { withAnimation { showAll = false } } label: { Label("Show fewer", systemImage: "chevron.up") }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Butter.cream))
        .onAppear { sync(); wishApps = WishAppIndex.read() }
        .sheet(item: Binding(get: { running.map { HomeRunID(id: $0) } }, set: { running = $0?.id })) { item in
            AppDesignRunView(designID: item.id, onClose: { running = nil }).frame(minWidth: 940, minHeight: 640)
        }
    }

    private func chip(_ title: String, count: Int, kind: HomeAppKind?) -> some View {
        let on = filter == title
        return Button { withAnimation(.easeInOut(duration: 0.15)) { filter = title } } label: {
            HStack(spacing: 5) {
                if let kind { Image(systemName: kind.symbol).font(.system(size: 10, weight: .bold)) }
                Text(title).font(.system(size: 12, weight: .bold, design: .rounded))
                Text("\(count)").font(.system(size: 10, weight: .bold)).opacity(0.7)
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .foregroundStyle(on ? Color.white : Butter.cocoa)
            .background(chipFill(on: on, kind: kind), in: Capsule())
            .overlay(Capsule().stroke(Butter.honey.opacity(on ? 0 : 0.9), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func chipFill(on: Bool, kind: HomeAppKind?) -> LinearGradient {
        if !on { return LinearGradient(colors: [Color.white, Color.white], startPoint: .leading, endPoint: .trailing) }
        let colors = kind?.colors ?? [Butter.cocoa, Butter.cocoa.opacity(0.85)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func tileView(_ tile: HomeAppTile) -> some View {
        Button { open(tile) } label: {
            HStack(spacing: 10) {
                Image(systemName: tile.symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(LinearGradient(colors: tile.kind.colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text(tile.title).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Butter.cocoa).lineLimit(1)
                    Text(tile.subtitle).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Butter.honey.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Open \(tile.title)")
    }

    private func open(_ tile: HomeAppTile) {
        let raw = String(tile.id.dropFirst(2))
        switch tile.kind {
        case .designer: running = raw
        case .builder: onOpenBuilder(raw)
        case .wish: onOpenWish(raw)
        case .ezy: onOpenEzy()
        case .link:
            if let link = links.first(where: { $0.id == raw }) { onOpenLink(link.url) }
        }
    }

    private func sync() {
        if !clips.isEmpty { AppDesignContext.shared.clips = clips }
        if !records.isEmpty { AppDesignContext.shared.records = records }
    }
}

private struct HomeRunID: Identifiable { let id: String }
