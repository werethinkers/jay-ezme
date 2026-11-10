import SwiftUI
import AppKit

extension Notification.Name {
    static let miniJMoveSelection = Notification.Name("MiniJMoveSelection")
    static let miniJRunSelected = Notification.Name("MiniJRunSelected")
    static let miniJPhraseMode = Notification.Name("MiniJPhraseMode")
}

/// One thing the popup search can show: a shortcut, an AppBuilder card, a website, an Ezyourlife app or a Mac app.
struct SpotlightEntry: Identifiable {
    let id: String
    let group: String
    let title: String
    let hint: String
    let detail: String
    let badge: String
    let symbol: String
    var iconPath: String? = nil
    var keyLabel: String? = nil
    var clip: Clip? = nil
    var score: Int = 0
    let run: () -> Void
}

/// Spotlight-style results: grouped accordions on the left, a preview of the highlighted result on the right.
/// Arrow keys move, Return runs, and the mouse works the same way.
struct SpotlightResults: View {
    @ObservedObject var search: PickerSearch
    let entries: [SpotlightEntry]
    var onEdit: (Clip) -> Void
    var onCopyKey: (Clip) -> Void
    var onManage: () -> Void
    var loadMore: () -> Void

    @State private var selected: String?
    @State private var closed: Set<String> = []
    @State private var lastKeyMove = Date.distantPast

    private static let groups: [(title: String, icon: String)] = [
        ("Best matches", "star.fill"),
        ("Shortcuts", "text.cursor"),
        ("AppBuilder cards", "wand.and.stars"),
        ("Websites", "globe"),
        ("Ezyourlife apps", "sparkles"),
        ("Mac apps", "app.dashed"),
        ("Ask Merlin", "sparkles"),
    ]

    private var visibleGroups: [(title: String, icon: String)] {
        Self.groups.filter { g in entries.contains(where: { $0.group == g.title }) || (g.title == "Shortcuts" && (search.isLoading || !search.isExhausted)) }
    }
    private func items(_ group: String) -> [SpotlightEntry] { entries.filter { $0.group == group } }
    private var navigable: [SpotlightEntry] { Self.groups.flatMap { g in closed.contains(g.title) ? [] : items(g.title) } }
    private var current: SpotlightEntry? { navigable.first(where: { $0.id == selected }) ?? navigable.first }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    list
                    if geo.size.width >= 540, let entry = current { preview(entry) }
                }
            }
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor).overlay(Butter.cream.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Butter.honey, lineWidth: 1.2))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { search.hasSpotlight = true }
        .onDisappear { search.hasSpotlight = false }
        .onReceive(NotificationCenter.default.publisher(for: .miniJRunSelected)) { _ in current?.run() }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleGroups, id: \.title) { g in group(g) }
                    if visibleGroups.isEmpty {
                        Text("Nothing found yet. Try other words, or describe what you want.")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Butter.cocoa.opacity(0.7))
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(NotificationCenter.default.publisher(for: .miniJMoveSelection)) { note in
                let delta = note.userInfo?["delta"] as? Int ?? 0
                let list = navigable
                guard !list.isEmpty else { return }
                let index = list.firstIndex(where: { $0.id == current?.id }) ?? 0
                let next = list[min(list.count - 1, max(0, index + delta))]
                lastKeyMove = Date()
                selected = next.id
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(next.id, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func group(_ g: (title: String, icon: String)) -> some View {
        let rows = items(g.title)
        let isClosed = closed.contains(g.title)
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if isClosed { closed.remove(g.title) } else { closed.insert(g.title) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isClosed ? 0 : 90))
                    Image(systemName: g.icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(Butter.coral)
                    Text(g.title.uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(0.8)
                    Spacer()
                    Text("\(rows.count)").font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 1).background(Butter.honey.opacity(0.7), in: Capsule())
                }
                .foregroundStyle(Butter.cocoa.opacity(0.8))
                .padding(.horizontal, 8).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !isClosed {
                ForEach(rows) { entry in row(entry) }
                if g.title == "Shortcuts" {
                    if search.isLoading { ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(8) }
                    if !search.isLoading && !search.isExhausted {
                        Color.clear.frame(height: 3).id("more-\(search.results.count)").onAppear { loadMore() }
                    }
                }
            }
        }
    }

    private func tile(_ entry: SpotlightEntry, size: CGFloat) -> some View {
        Group {
            if let path = entry.iconPath, let image = EzMeImageCache.load(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: entry.symbol).font(.system(size: size * 0.46, weight: .medium)).foregroundStyle(Butter.coral)
            }
        }
        .frame(width: size, height: size)
        .background(Butter.butter)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28))
    }

    private func row(_ entry: SpotlightEntry) -> some View {
        let isCurrent = entry.id == current?.id
        return HStack(spacing: 6) {
            Button { entry.run() } label: {
                HStack(spacing: 10) {
                    tile(entry, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Butter.cocoa).lineLimit(1)
                        if !entry.hint.isEmpty {
                            Text(entry.hint).font(.system(size: 11.5)).foregroundStyle(Butter.cocoa.opacity(0.6)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    if let key = entry.keyLabel {
                        Text(key).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Butter.cocoa.opacity(0.75)).lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Butter.honey.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let clip = entry.clip {
                Button { onCopyKey(clip) } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 11, weight: .semibold)).foregroundStyle(Butter.coral)
                        .frame(width: 26, height: 26).background(Butter.honey.opacity(0.6), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Copy shortcode")
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(isCurrent ? Butter.honey.opacity(0.75) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .id(entry.id)
        .onHover { inside in
            if inside && Date().timeIntervalSince(lastKeyMove) > 0.4 { selected = entry.id }
        }
    }

    private func preview(_ entry: SpotlightEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            tile(entry, size: 46)
            Text(entry.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Butter.cocoa).lineLimit(2).padding(.top, 12)
            Text(entry.detail).font(.system(size: 12.5)).foregroundStyle(Butter.cocoa.opacity(0.7)).lineLimit(9).padding(.top, 4)
            Spacer(minLength: 8)
            HStack {
                Text(entry.badge).font(.system(size: 10, weight: .heavy)).foregroundStyle(Butter.cocoa.opacity(0.7)).lineLimit(1)
                Spacer(minLength: 8)
                if let key = entry.keyLabel {
                    Text(key).font(.system(size: 10.5, design: .monospaced)).lineLimit(1).truncationMode(.middle).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Butter.cream, in: RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(Butter.honey))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button(entry.clip == nil ? "Open" : "Paste") { entry.run() }
                        .buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.small)
                    if let clip = entry.clip {
                        Button("Edit") { onEdit(clip) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                if let clip = entry.clip {
                    Button { onCopyKey(clip) } label: { Label("Copy shortcode", systemImage: "doc.on.doc") }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            .padding(.top, 10)
        }
        .padding(16)
        .frame(width: 236)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Butter.honey.opacity(0.35))
        .overlay(alignment: .leading) { Rectangle().fill(Butter.honey).frame(width: 1) }
    }

    private var footer: some View {
        // Three layouts, widest first: the first one that fits the width is used, so text never overlaps.
        ViewThatFits(in: .horizontal) {
            footerRow(keys: ["\u{2191}\u{2193} to move", "\u{21B5} to run", "esc to close"], tip: search.phraseMode ? nil : "\\ + space = plain words", showManage: true)
            footerRow(keys: ["\u{2191}\u{2193} move", "\u{21B5} run", "esc close"], tip: nil, showManage: true)
            footerRow(keys: [], tip: nil, showManage: true)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Butter.cocoa.opacity(0.65))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).overlay(Butter.cream))
        .overlay(alignment: .top) { Rectangle().fill(Butter.honey).frame(height: 1) }
    }

    private func footerRow(keys: [String], tip: String?, showManage: Bool) -> some View {
        HStack(spacing: 14) {
            ForEach(keys, id: \.self) { Text($0).lineLimit(1).fixedSize() }
            if let tip = tip { Text(tip).lineLimit(1).fixedSize() }
            Spacer(minLength: 12)
            Text(search.isLoading ? "\(entries.count) results \u{00B7} searching\u{2026}" : "\(entries.count) results").lineLimit(1).fixedSize()
            if showManage {
                Button("Manage all", action: onManage).buttonStyle(.plain).foregroundStyle(Butter.coral).fontWeight(.semibold).lineLimit(1).fixedSize()
            }
        }
    }
}
