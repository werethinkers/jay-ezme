import SwiftUI
import AppKit

// KeyDo subscription tiers, feature gates and upgrade UI.
//
// Tiers: free → pro → teams
// Gate pattern: SubscriptionManager.shared.require(.feature) { /* allowed */ }
// Upgrade flow: SubscriptionUpgradeView shown as a sheet when a gate fires.
// Payment: Stripe checkout via website (server-side); app verifies via get_my_subscription() RPC.

// MARK: - Tier

enum SubscriptionTier: String, Codable, Comparable {
    case free, pro, teams

    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        [SubscriptionTier.free, .pro, .teams].firstIndex(of: lhs)! < [SubscriptionTier.free, .pro, .teams].firstIndex(of: rhs)!
    }

    var displayName: String {
        switch self { case .free: return "Free"; case .pro: return "KeyDo Pro"; case .teams: return "KeyDo Teams" }
    }

    var badgeColor: Color {
        switch self { case .free: return .secondary; case .pro: return Butter.coral; case .teams: return Color.indigo }
    }

    var monthlyUSD: Double { switch self { case .free: return 0; case .pro: return 4.99; case .teams: return 7.99 } }
    var yearlyUSD: Double  { switch self { case .free: return 0; case .pro: return 39;   case .teams: return 79.99 } }
    var monthlyINR: Double { switch self { case .free: return 0; case .pro: return 399;  case .teams: return 649 } }
    var yearlyINR: Double  { switch self { case .free: return 0; case .pro: return 3199; case .teams: return 6399 } }
    var monthlyAICredits: Int { switch self { case .free: return 50; case .pro: return 200; case .teams: return 500 } }
    var maxCollections: Int? { switch self { case .free: return 3; case .pro, .teams: return nil } }
}

// MARK: - Feature gates

enum SubscriptionFeature: String, CaseIterable {
    // Always free
    case textShortcuts, liveValues, calculator, basicWishStudio

    // Pro+
    case cloudSync, unlimitedCollections, mediaShortcuts, fullWishStudio
    case appBuilder, ezTools, aiRewrite, aiImage, aiVideo
    case marketplace, advancedLiveData, starterPacksIntl

    // Teams+
    case teamCollections, adminDashboard, templateLocking, usageAnalytics, onboardingKit

    var requiredTier: SubscriptionTier {
        switch self {
        case .textShortcuts, .liveValues, .calculator, .basicWishStudio:
            return .free
        case .cloudSync, .unlimitedCollections, .mediaShortcuts, .fullWishStudio,
             .appBuilder, .ezTools, .aiRewrite, .aiImage, .aiVideo,
             .marketplace, .advancedLiveData, .starterPacksIntl:
            return .pro
        case .teamCollections, .adminDashboard, .templateLocking, .usageAnalytics, .onboardingKit:
            return .teams
        }
    }

    var displayName: String {
        switch self {
        case .textShortcuts: return "Text shortcuts"
        case .liveValues: return "Live values"
        case .calculator: return "Inline calculator"
        case .basicWishStudio: return "Wish Studio (5 templates)"
        case .cloudSync: return "Cloud sync"
        case .unlimitedCollections: return "Unlimited collections"
        case .mediaShortcuts: return "Media shortcuts"
        case .fullWishStudio: return "Full Wish Studio"
        case .appBuilder: return "AppBuilder"
        case .ezTools: return "EzTools"
        case .aiRewrite: return "AI rewrite"
        case .aiImage: return "AI image"
        case .aiVideo: return "AI video"
        case .marketplace: return "Template Marketplace"
        case .advancedLiveData: return "Advanced live data"
        case .starterPacksIntl: return "International starter packs"
        case .teamCollections: return "Shared team collections"
        case .adminDashboard: return "Admin dashboard"
        case .templateLocking: return "Template locking"
        case .usageAnalytics: return "Usage analytics"
        case .onboardingKit: return "Onboarding kit"
        }
    }

    var symbol: String {
        switch self {
        case .textShortcuts: return "text.cursor"
        case .liveValues: return "clock"
        case .calculator: return "function"
        case .basicWishStudio: return "sparkles"
        case .cloudSync: return "icloud.fill"
        case .unlimitedCollections: return "folder.fill.badge.plus"
        case .mediaShortcuts: return "photo.fill"
        case .fullWishStudio: return "wand.and.stars"
        case .appBuilder: return "doc.richtext.fill"
        case .ezTools: return "paintbrush.fill"
        case .aiRewrite: return "text.quote"
        case .aiImage: return "photo.badge.plus"
        case .aiVideo: return "video.badge.plus"
        case .marketplace: return "storefront.fill"
        case .advancedLiveData: return "chart.line.uptrend.xyaxis"
        case .starterPacksIntl: return "globe"
        case .teamCollections: return "person.3.fill"
        case .adminDashboard: return "gauge.medium"
        case .templateLocking: return "lock.fill"
        case .usageAnalytics: return "chart.bar.fill"
        case .onboardingKit: return "person.badge.plus"
        }
    }
}

// MARK: - Manager

@MainActor final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var tier: SubscriptionTier = .free
    @Published private(set) var status: String = "active"
    @Published private(set) var expiresAt: Date?
    @Published private(set) var trialEndsAt: Date?
    @Published private(set) var monthlyCreditsQuota: Int = 50
    @Published var pendingFeature: SubscriptionFeature?
    @Published var showUpgrade = false

    private static let cacheKey = "keydoSubscriptionCache"
    private static let cacheExpiryKey = "keydoSubscriptionCacheExpiry"
    private var refreshTask: Task<Void, Never>?

    private init() { loadCache(); refreshIfStale() }

    // MARK: Access check

    func canUse(_ feature: SubscriptionFeature) -> Bool {
        guard tier >= feature.requiredTier else { return false }
        if status == "expired" || status == "cancelled" { return feature.requiredTier == .free }
        return true
    }

    /// Call at the start of a Pro/Teams action. If allowed, runs `action`. If not, shows upgrade sheet.
    func require(_ feature: SubscriptionFeature, context: String = "", action: @escaping () -> Void) {
        if canUse(feature) { action(); return }
        pendingFeature = feature
        showUpgrade = true
    }

    /// Returns true if the feature is available, false if gated (and shows upgrade sheet).
    @discardableResult
    func gate(_ feature: SubscriptionFeature) -> Bool {
        if canUse(feature) { return true }
        pendingFeature = feature
        showUpgrade = true
        return false
    }

    var collectionsAllowed: Int? { tier.maxCollections }
    var isTrialActive: Bool { status == "trial" && (trialEndsAt.map { $0 > Date() } ?? false) }

    // MARK: Remote refresh

    func refreshFromServer() async {
        guard EzMeCloud.shared.isSignedIn else { tier = .free; status = "active"; return }
        guard let url = URL(string: EzMeCloud.supabaseURL + "/rest/v1/rpc/get_my_subscription") else { return }
        guard let token = EzMeCloud.shared.session?.accessToken else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(EzMeCloud.supabaseKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data("{}".utf8)
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        apply(json)
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
        UserDefaults.standard.set(Date().addingTimeInterval(3600).timeIntervalSince1970, forKey: Self.cacheExpiryKey)
    }

    private func apply(_ json: [String: Any]) {
        tier = SubscriptionTier(rawValue: json["tier"] as? String ?? "free") ?? .free
        status = json["status"] as? String ?? "active"
        monthlyCreditsQuota = json["monthly_credits_quota"] as? Int ?? tier.monthlyAICredits
        if let exp = json["expires_at"] as? String { expiresAt = ISO8601DateFormatter().date(from: exp) }
        if let trial = json["trial_ends_at"] as? String { trialEndsAt = ISO8601DateFormatter().date(from: trial) }
        // CreditsCenter quota is not synced here — pro quota is tracked server-side
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        apply(json)
    }

    private func refreshIfStale() {
        let expiry = UserDefaults.standard.double(forKey: Self.cacheExpiryKey)
        guard expiry < Date().timeIntervalSince1970 else { return }
        refreshTask = Task { await refreshFromServer() }
    }

    func signedIn() { refreshTask = Task { await refreshFromServer() } }
    func signedOut() { tier = .free; status = "active"; expiresAt = nil; trialEndsAt = nil
        UserDefaults.standard.removeObject(forKey: Self.cacheKey) }

    // MARK: Upgrade URL

    static func upgradeURL(tier: SubscriptionTier, cycle: String = "yearly") -> URL {
        URL(string: "https://ezme.ezyourlife.com/#pricing?tier=\(tier.rawValue)&cycle=\(cycle)")!
    }
}

// MARK: - Upgrade sheet

struct SubscriptionUpgradeView: View {
    @ObservedObject private var sub = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCycle: BillingCycle = .yearly
    @State private var targetTier: SubscriptionTier = .pro

    enum BillingCycle: String, CaseIterable { case monthly, yearly
        var label: String { self == .monthly ? "Monthly" : "Yearly (save 35%)" }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    cycleToggle
                    HStack(alignment: .top, spacing: 12) { proCard; teamsCard }
                    featureGrid
                    ctaButton
                    Text("Cancel any time. Prices in USD. Indian pricing: Pro ₹399/mo or ₹3,199/yr · Teams ₹649/mo or ₹6,399/yr per seat.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding(.bottom, 20)
                }
                .padding(24)
            }
        }
        .frame(width: 620, height: 740)
        .background(.background)
        .onAppear { targetTier = sub.pendingFeature?.requiredTier ?? .pro }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let f = sub.pendingFeature {
                    Text("Upgrade to use \(f.displayName)").font(.headline)
                    Text("\(f.displayName) is available on \(f.requiredTier.displayName) and above.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Upgrade KeyDo").font(.headline)
                    Text("Unlock the full app — AppBuilder, cloud sync, AI tools and more.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain).font(.title3)
        }
        .padding(20)
    }

    private var cycleToggle: some View {
        Picker("Billing", selection: $selectedCycle) {
            ForEach(BillingCycle.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden()
    }

    private var proCard: some View {
        tierCard(tier: .pro, features: [
            "Cloud sync across 3 Macs",
            "Unlimited collections",
            "Media shortcuts (images, GIFs, video)",
            "Full Wish Studio + gifting",
            "AppBuilder (invoices, letters, docs)",
            "EzTools (image, video, font studio)",
            "AI rewrite, image and video",
            "200 AI credits / month",
            "Template Marketplace",
        ])
    }

    private var teamsCard: some View {
        tierCard(tier: .teams, features: [
            "Everything in Pro",
            "Shared team collections",
            "Team admin dashboard",
            "Template locking",
            "Usage analytics",
            "Onboarding kit",
            "500 AI credits / month per seat",
            "Priority support",
        ])
    }

    private func tierCard(tier: SubscriptionTier, features: [String]) -> some View {
        let selected = targetTier == tier
        let price = selectedCycle == .monthly ? tier.monthlyUSD : tier.yearlyUSD / 12
        let label = selectedCycle == .monthly ? "/month" : "/month, billed yearly"
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tier.displayName).font(.headline)
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(tier.badgeColor) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$\(String(format: "%.2f", price))").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(tier.badgeColor)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            ForEach(features, id: \.self) { f in
                Label(f, systemImage: "checkmark").font(.caption).foregroundStyle(.primary).labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(selected ? tier.badgeColor.opacity(0.08) : Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? tier.badgeColor : Color.secondary.opacity(0.2), lineWidth: selected ? 2 : 1))
        .onTapGesture { targetTier = tier }
        .frame(maxWidth: .infinity)
    }

    private var featureGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What's always free").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                Label("Unlimited text shortcuts", systemImage: "text.cursor")
                Label("Live values & calculator", systemImage: "clock")
                Label("3 collections", systemImage: "folder")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ctaButton: some View {
        VStack(spacing: 10) {
            Button {
                NSWorkspace.shared.open(SubscriptionManager.upgradeURL(tier: targetTier, cycle: selectedCycle.rawValue))
                dismiss()
            } label: {
                Text("Upgrade to \(targetTier.displayName)")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent).tint(targetTier.badgeColor)
            Text("Opens our website · secure payment by Stripe").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tier badge (small chip for UI)

struct TierBadge: View {
    let tier: SubscriptionTier
    var body: some View {
        if tier != .free {
            Text(tier.displayName).font(.system(size: 10, weight: .bold)).foregroundStyle(tier.badgeColor)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(tier.badgeColor.opacity(0.12), in: Capsule())
        }
    }
}

// MARK: - Pro lock overlay (use over gated content)

struct ProLockOverlay: View {
    let feature: SubscriptionFeature
    @ObservedObject private var sub = SubscriptionManager.shared

    var body: some View {
        if !sub.canUse(feature) {
            ZStack {
                Color(.windowBackgroundColor).opacity(0.85)
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill").font(.title2).foregroundStyle(Butter.coral)
                    Text(feature.requiredTier.displayName + " feature")
                        .font(.headline)
                    Text(feature.displayName + " is available from " + feature.requiredTier.displayName + ".")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Upgrade") { sub.showUpgrade = true; sub.pendingFeature = feature }
                        .buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.small)
                }
                .padding(24)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Settings row for current plan

struct SubscriptionStatusView: View {
    @ObservedObject private var sub = SubscriptionManager.shared
    @State private var refreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your plan").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(sub.tier.displayName).font(.headline)
                        TierBadge(tier: sub.tier)
                    }
                }
                Spacer()
                if sub.tier == .free {
                    Button("Upgrade to Pro") { sub.showUpgrade = true; sub.pendingFeature = nil }
                        .buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.small)
                } else {
                    Button { Task { refreshing = true; await sub.refreshFromServer(); refreshing = false } }
                    label: { Label(refreshing ? "Checking…" : "Refresh", systemImage: "arrow.clockwise") }
                        .buttonStyle(.bordered).controlSize(.small).disabled(refreshing)
                }
            }
            .padding(16)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15)))

            if sub.tier == .free {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What you're missing on Free").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach([SubscriptionFeature.cloudSync, .unlimitedCollections, .appBuilder, .fullWishStudio,
                                 .aiRewrite, .marketplace], id: \.self) { f in
                            HStack(spacing: 6) {
                                Image(systemName: f.symbol).foregroundStyle(Butter.coral).frame(width: 18)
                                Text(f.displayName).font(.caption)
                                Spacer()
                            }
                        }
                    }
                }
                .padding(14)
                .background(Butter.coral.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Pricing page view (shown in Settings > Subscription)

struct PricingPageView: View {
    var body: some View {
        SubscriptionUpgradeView()
    }
}
