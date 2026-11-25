import SwiftUI
import AppKit

// KeyDo Template Marketplace.
// Notion Templates model: free packs anyone installs; paid packs (70/30 split) for creators.
// Packs live in Supabase marketplace_packs. Installing runs install_marketplace_pack() RPC.
// Pack data is JSON with type "shortcuts" or "designs" — installed by converting to local Clips/AppDesigns.

// MARK: - Model

struct MarketplacePack: Identifiable, Codable {
    var id: UUID
    var authorName: String
    var title: String
    var description: String
    var category: String
    var language: String
    var tags: [String]
    var packData: PackData
    var packVersion: String
    var priceUsd: Double
    var installCount: Int
    var ratingSum: Int
    var ratingCount: Int
    var isPublished: Bool
    var isFeatured: Bool
    var isStaffPick: Bool
    var coverUrl: String?
    var createdAt: Date?

    var averageRating: Double { ratingCount > 0 ? Double(ratingSum) / Double(ratingCount) : 0 }
    var isFree: Bool { priceUsd == 0 }

    struct PackData: Codable {
        var type: String // "shortcuts" | "designs"
        var items: [PackItem]
    }

    struct PackItem: Codable, Identifiable {
        var id: String { key }
        var key: String
        var label: String
        var body: String
        var tags: [String]?
    }

    enum CodingKeys: String, CodingKey {
        case id, authorName = "author_name", title, description, category, language, tags
        case packData = "pack_data", packVersion = "pack_version", priceUsd = "price_usd"
        case installCount = "install_count", ratingSum = "rating_sum", ratingCount = "rating_count"
        case isPublished = "is_published", isFeatured = "is_featured", isStaffPick = "is_staff_pick"
        case coverUrl = "cover_url", createdAt = "created_at"
    }
}

struct MarketplaceCategory: Identifiable {
    let id: String
    let label: String
    let symbol: String
}

// MARK: - Manager

@MainActor final class MarketplaceManager: ObservableObject {
    static let shared = MarketplaceManager()

    @Published private(set) var packs: [MarketplacePack] = []
    @Published private(set) var installedIDs: Set<UUID> = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    @Published var selectedCategory = "all"
    @Published var searchText = ""

    static let categories: [MarketplaceCategory] = [
        MarketplaceCategory(id: "all",       label: "All",       symbol: "square.grid.2x2"),
        MarketplaceCategory(id: "sales",     label: "Sales",     symbol: "chart.line.uptrend.xyaxis"),
        MarketplaceCategory(id: "support",   label: "Support",   symbol: "headphones"),
        MarketplaceCategory(id: "hr",        label: "HR",        symbol: "person.2.fill"),
        MarketplaceCategory(id: "developer", label: "Dev",       symbol: "chevron.left.forwardslash.chevron.right"),
        MarketplaceCategory(id: "business",  label: "Business",  symbol: "briefcase.fill"),
        MarketplaceCategory(id: "finance",   label: "Finance",   symbol: "indianrupeesign.circle"),
        MarketplaceCategory(id: "creative",  label: "Creative",  symbol: "paintbrush.fill"),
        MarketplaceCategory(id: "personal",  label: "Personal",  symbol: "person.fill"),
        MarketplaceCategory(id: "student",   label: "Student",   symbol: "graduationcap.fill"),
    ]

    var filtered: [MarketplacePack] {
        packs.filter { p in
            (selectedCategory == "all" || p.category == selectedCategory) &&
            (searchText.isEmpty || p.title.localizedCaseInsensitiveContains(searchText) ||
             p.description.localizedCaseInsensitiveContains(searchText) ||
             p.tags.contains { $0.localizedCaseInsensitiveContains(searchText) })
        }
    }

    var featured: [MarketplacePack] { packs.filter { $0.isFeatured || $0.isStaffPick } }

    private init() { Task { await load() } }

    func load() async {
        isLoading = true; loadError = nil
        guard let url = URL(string: EzMeCloud.supabaseURL + "/rest/v1/marketplace_packs?is_published=eq.true&order=install_count.desc") else { isLoading = false; return }
        var req = URLRequest(url: url)
        req.setValue(EzMeCloud.supabaseKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else {
            loadError = "Could not load packs. Check your connection."; isLoading = false; return
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let loaded = try? decoder.decode([MarketplacePack].self, from: data) { packs = loaded }
        isLoading = false
        await loadInstalledIDs()
    }

    private func loadInstalledIDs() async {
        guard EzMeCloud.shared.isSignedIn,
              let token = EzMeCloud.shared.session?.accessToken,
              let url = URL(string: EzMeCloud.supabaseURL + "/rest/v1/marketplace_installs?select=pack_id") else { return }
        var req = URLRequest(url: url)
        req.setValue(EzMeCloud.supabaseKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        installedIDs = Set(rows.compactMap { ($0["pack_id"] as? String).flatMap { UUID(uuidString: $0) } })
    }

    @discardableResult
    func install(pack: MarketplacePack) async -> Bool {
        guard let url = URL(string: EzMeCloud.supabaseURL + "/rest/v1/rpc/install_marketplace_pack"),
              let token = EzMeCloud.shared.session?.accessToken else {
            installLocally(pack: pack); return true
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(EzMeCloud.supabaseKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["p_pack_id": pack.id.uuidString])
        _ = try? await URLSession.shared.data(for: req)
        installedIDs.insert(pack.id)
        installLocally(pack: pack)
        return true
    }

    private func installLocally(pack: MarketplacePack) {
        guard pack.packData.type == "shortcuts" else { return }
        let items = pack.packData.items.map { item -> [String: Any] in
            ["key": item.key, "text": item.body, "group": pack.title]
        }
        NotificationCenter.default.post(name: .keydoInstallPackShortcuts, object: nil, userInfo: ["items": items])
    }

    // MARK: Publish a pack (Pro feature)

    func publish(title: String, description: String, category: String, items: [(key: String, label: String, body: String)]) async throws { // swiftlint:disable:this function_parameter_count
        guard EzMeCloud.shared.isSignedIn, let token = EzMeCloud.shared.session?.accessToken else { throw NSError(domain: "Marketplace", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sign in first"]) }
        guard let url = URL(string: EzMeCloud.supabaseURL + "/rest/v1/marketplace_packs") else { return }
        let payload: [String: Any] = [
            "title": title,
            "description": description,
            "category": category,
            "pack_data": ["type": "shortcuts", "items": items.map { ["key": $0.key, "label": $0.label, "body": $0.body] }],
            "is_published": true
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(EzMeCloud.supabaseKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 201 else { throw NSError(domain: "Marketplace", code: 2, userInfo: [NSLocalizedDescriptionKey: "Publish failed"]) }
        await load()
    }
}

// MARK: - Main view

struct KeyDoStoreView: View {
    @ObservedObject private var mgr = MarketplaceManager.shared
    @ObservedObject private var sub = SubscriptionManager.shared
    @State private var showPublish = false

    var body: some View {
        VStack(spacing: 0) {
            header
            categoryBar
            Divider()
            if mgr.isLoading {
                Spacer()
                ProgressView("Loading packs…").frame(maxWidth: .infinity)
                Spacer()
            } else if let err = mgr.loadError {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash").font(.largeTitle).foregroundStyle(.secondary)
                    Text(err).font(.callout).foregroundStyle(.secondary)
                    Button("Retry") { Task { await mgr.load() } }.buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                packList
            }
        }
        .sheet(isPresented: $showPublish) { PublishPackView() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "storefront.fill").font(.title3).foregroundStyle(Butter.coral)
            VStack(alignment: .leading, spacing: 1) {
                Text("Template Marketplace").font(.headline)
                Text("\(mgr.packs.count) packs • Install in one click • Publish your own").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Search packs…", text: $mgr.searchText).textFieldStyle(.roundedBorder).frame(width: 180)
            Button { showPublish = true } label: { Label("Publish a pack", systemImage: "plus") }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(!sub.canUse(.marketplace))
        }
        .padding(16)
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MarketplaceManager.categories) { cat in
                    Button {
                        mgr.selectedCategory = cat.id
                    } label: {
                        Label(cat.label, systemImage: cat.symbol).font(.caption.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(mgr.selectedCategory == cat.id ? Butter.coral : Color(.controlBackgroundColor), in: Capsule())
                            .foregroundStyle(mgr.selectedCategory == cat.id ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    private var packList: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(mgr.filtered) { pack in
                    PackCard(pack: pack)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Pack card

struct PackCard: View {
    let pack: MarketplacePack
    @ObservedObject private var mgr = MarketplaceManager.shared
    @State private var installing = false

    private var isInstalled: Bool { mgr.installedIDs.contains(pack.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(pack.category.capitalized)
                    .font(.system(size: 10, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule()).foregroundStyle(Color.accentColor)
                Spacer()
                if pack.isStaffPick {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange)
                }
                Text(pack.isFree ? "Free" : "$\(String(format: "%.0f", pack.priceUsd))")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(pack.isFree ? Color.green : Butter.coral)
            }
            Text(pack.title).font(.callout.weight(.semibold)).lineLimit(2)
            Text(pack.description).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            Spacer(minLength: 0)
            HStack {
                Label("\(pack.installCount)", systemImage: "arrow.down.circle").font(.caption2).foregroundStyle(.secondary)
                if pack.ratingCount > 0 {
                    Label(String(format: "%.1f", pack.averageRating), systemImage: "star").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if isInstalled {
                    Label("Installed", systemImage: "checkmark").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                } else {
                    Button(installing ? "Installing…" : "Install") {
                        installing = true
                        Task { await mgr.install(pack: pack); installing = false }
                    }
                    .buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.mini).disabled(installing)
                }
            }
        }
        .padding(14)
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15)))
        .frame(height: 180)
    }
}

// MARK: - Publish sheet

struct PublishPackView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sub = SubscriptionManager.shared
    @State private var title = ""
    @State private var description = ""
    @State private var category = "general"
    @State private var shortcutKeys = ""
    @State private var publishing = false
    @State private var error: String?
    @State private var success = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Publish a pack").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
            .padding(20)
            Divider()
            if sub.canUse(.marketplace) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Pack details").font(.subheadline.weight(.semibold))
                        TextField("Pack title (e.g. Sales Starter Kit)", text: $title).textFieldStyle(.roundedBorder)
                        TextField("Description — what does this pack do?", text: $description, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(3...5)
                        Picker("Category", selection: $category) {
                            ForEach(["general","sales","support","hr","developer","business","finance","creative","personal","student"], id: \.self) { Text($0.capitalized).tag($0) }
                        }.pickerStyle(.menu)
                        Text("Shortcut keys to include (from your library)").font(.caption.weight(.semibold))
                        TextField("e.g. sig, inv, thanks, fu1 (comma-separated)", text: $shortcutKeys).textFieldStyle(.roundedBorder)
                        if let err = error { Text(err).font(.caption).foregroundStyle(.red) }
                        if success { Label("Published! It's live in the Marketplace.", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout) }
                    }
                    .padding(20)
                }
                Divider()
                HStack {
                    Spacer()
                    Button("Publish for free") {
                        Task { await publish() }
                    }
                    .buttonStyle(.borderedProminent).tint(Butter.coral).disabled(title.isEmpty || publishing)
                }
                .padding(16)
            } else {
                ProLockOverlay(feature: .marketplace).frame(height: 300).padding(20)
            }
        }
        .frame(width: 500, height: 440)
    }

    private func publish() async {
        publishing = true; error = nil
        let keys = shortcutKeys.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        // Items are sourced by the user typing keys; actual text comes via the notification handler
        let items = keys.map { key -> (key: String, label: String, body: String) in
            (key: key, label: key, body: key)
        }
        do {
            try await MarketplaceManager.shared.publish(title: title, description: description, category: category, items: items)
            success = true
        } catch {
            self.error = error.localizedDescription
        }
        publishing = false
    }
}
