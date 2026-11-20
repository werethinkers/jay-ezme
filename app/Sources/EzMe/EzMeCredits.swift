import SwiftUI
import AppKit

// KeyDo credits.
//
// Every service that does real work (making a card or an invoice, a picture or video with AI, an AI rewrite)
// uses credits. This file holds the whole system so that buying and selling credits can be added later
// without touching the services:
//   - CreditService:  what can be charged, and its starting price (5 to 30 credits, in steps of 5)
//   - CreditsBackend: where the ledger lives. Today a file on this Mac (LocalCreditsBackend); a server
//                     can replace it later by implementing the same four functions.
//   - CreditsCenter:  the one place that prices, asks for approval, charges, refunds and keeps the history
//   - CreditsView:    balance, usage history, prices and the approval limit (Settings)

// MARK: - Services and prices

enum CreditService: String, CaseIterable, Codable, Identifiable {
    case designSimple = "design.simple"
    case designBusiness = "design.business"
    case designLarge = "design.large"
    case aiRewrite = "ai.rewrite"
    case aiImage = "ai.image"
    case aiVideo = "ai.video"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .designSimple: return "Cards and wishes"
        case .designBusiness: return "Invoices and business papers"
        case .designLarge: return "Posters and multi-page designs"
        case .aiRewrite: return "AI rewrite and reply"
        case .aiImage: return "Picture with AI"
        case .aiVideo: return "Video with AI"
        }
    }

    var detail: String {
        switch self {
        case .designSimple: return "One-page designs such as greeting cards and invitations."
        case .designBusiness: return "Invoices, quotations, certificates and similar."
        case .designLarge: return "Posters, brochures and designs with several pages."
        case .aiRewrite: return "Rewriting text in a tone, or writing a reply."
        case .aiImage: return "A new picture made by an AI model."
        case .aiVideo: return "A short video made by an AI model."
        }
    }

    var symbol: String {
        switch self {
        case .designSimple: return "greetingcard"
        case .designBusiness: return "doc.text"
        case .designLarge: return "rectangle.stack"
        case .aiRewrite: return "text.quote"
        case .aiImage: return "photo.badge.plus"
        case .aiVideo: return "video.badge.plus"
        }
    }

    /// The starting price. Prices stay between 5 and 30 unless the owner changes them.
    var defaultCost: Int {
        switch self {
        case .designSimple: return 10
        case .designBusiness: return 15
        case .designLarge: return 20
        case .aiRewrite: return 5
        case .aiImage: return 25
        case .aiVideo: return 30
        }
    }
}

// MARK: - The ledger

enum CreditKind: String, Codable {
    case grant, spend, refund, purchase, adjustment

    var title: String {
        switch self {
        case .grant: return "Welcome credits"
        case .spend: return "Used"
        case .refund: return "Returned"
        case .purchase: return "Bought"
        case .adjustment: return "Adjusted"
        }
    }
}

struct CreditEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date = Date()
    var kind: CreditKind
    /// Positive adds credits, negative uses them.
    var amount: Int
    var balanceAfter: Int
    var serviceID: String?
    var title: String
    var detail: String = ""
    /// For a refund: the use it returned.
    var refundOf: UUID? = nil
}

struct CreditLedgerFile: Codable {
    var balance: Int
    var entries: [CreditEntry]
}

/// Where the ledger is kept. A server can implement this later (buy, sell and share credits across Macs).
protocol CreditsBackend {
    func load(identity: String) -> CreditLedgerFile?
    func save(_ ledger: CreditLedgerFile, identity: String)
}

struct LocalCreditsBackend: CreditsBackend {
    private func url(_ identity: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyDo", isDirectory: true).appendingPathComponent("Credits", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(ezmeProfileSlug(identity) + ".json")
    }
    func load(identity: String) -> CreditLedgerFile? {
        guard let data = try? Data(contentsOf: url(identity)) else { return nil }
        return try? JSONDecoder().decode(CreditLedgerFile.self, from: data)
    }
    func save(_ ledger: CreditLedgerFile, identity: String) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        try? data.write(to: url(identity), options: .atomic)
    }
}

struct CreditError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

// MARK: - The center

@MainActor final class CreditsCenter: ObservableObject {
    static let shared = CreditsCenter()
    static let welcomeCredits = 10_000
    static let defaultApprovalLimit = 20
    private static let costsKey = "keydoCreditCosts"
    private static let limitKey = "keydoCreditApprovalLimit"

    @Published private(set) var balance = 0
    @Published private(set) var entries: [CreditEntry] = []
    @Published private(set) var costs: [String: Int] = [:]
    @Published private(set) var approvalLimit = CreditsCenter.defaultApprovalLimit
    /// Why the last charge did not go through, ready to show.
    var lastMessage = ""

    var backend: CreditsBackend = LocalCreditsBackend()
    private var identity = ""

    private init() {
        costs = (UserDefaults.standard.dictionary(forKey: Self.costsKey) as? [String: Int]) ?? [:]
        let saved = UserDefaults.standard.integer(forKey: Self.limitKey)
        approvalLimit = saved > 0 ? saved : Self.defaultApprovalLimit
        reload()
    }

    private var currentIdentity: String {
        let email = EzMeCloud.shared.email
        return email.isEmpty ? "this-mac" : email
    }

    /// Loads the ledger of whoever is signed in. A new account gets the welcome credits once.
    func reload() {
        let who = currentIdentity
        identity = who
        if let file = backend.load(identity: who) {
            balance = file.balance
            entries = file.entries
        } else {
            let grant = CreditEntry(kind: .grant, amount: Self.welcomeCredits, balanceAfter: Self.welcomeCredits,
                                    serviceID: nil, title: "Welcome credits", detail: "Free credits for your account")
            balance = Self.welcomeCredits
            entries = [grant]
            persist()
        }
    }

    private func refreshIdentity() { if identity != currentIdentity { reload() } }

    private func persist() {
        if entries.count > 5000 { entries = Array(entries.prefix(5000)) }
        backend.save(CreditLedgerFile(balance: balance, entries: entries), identity: identity)
    }

    // MARK: Prices

    func cost(_ service: CreditService) -> Int { costs[service.rawValue] ?? service.defaultCost }

    func setCost(_ service: CreditService, _ value: Int) {
        costs[service.rawValue] = min(100, max(1, value))
        UserDefaults.standard.set(costs, forKey: Self.costsKey)
    }

    func resetCosts() { costs = [:]; UserDefaults.standard.removeObject(forKey: Self.costsKey) }

    func setApprovalLimit(_ value: Int) {
        approvalLimit = min(100, max(5, value))
        UserDefaults.standard.set(approvalLimit, forKey: Self.limitKey)
    }

    /// Which price applies to a design, by what it is and how many pages it has (deeper work costs more).
    func designPricing(name: String, pages: Int) -> (service: CreditService, cost: Int) {
        let lower = name.lowercased()
        let business = ["invoice", "bill", "quotation", "quote", "receipt", "certificate", "letterhead", "proposal", "agreement"]
        let large = ["poster", "brochure", "flyer", "catalogue", "catalog", "menu", "magazine", "deck"]
        let service: CreditService
        if pages > 1 || large.contains(where: { lower.contains($0) }) { service = .designLarge }
        else if business.contains(where: { lower.contains($0) }) { service = .designBusiness }
        else { service = .designSimple }
        return (service, cost(service))
    }

    // MARK: Charging

    /// Charges for one piece of work. Returns the ledger entry to refund if the work fails, or nil when the
    /// work should not go ahead (not enough credits, or the person did not approve a larger charge).
    @discardableResult
    func charge(_ service: CreditService, cost override: Int? = nil, detail: String) -> UUID? {
        refreshIdentity()
        let price = override ?? cost(service)
        guard balance >= price else {
            lastMessage = "Not enough credits: this needs \(price) and you have \(balance)."
            return nil
        }
        if price > approvalLimit && !askApproval(service: service, price: price, detail: detail) {
            lastMessage = "Cancelled. \(price) credits were not used."
            return nil
        }
        balance -= price
        let entry = CreditEntry(kind: .spend, amount: -price, balanceAfter: balance, serviceID: service.rawValue,
                                title: service.title, detail: detail)
        entries.insert(entry, at: 0)
        persist()
        lastMessage = ""
        return entry.id
    }

    /// For work that runs in a throwing function.
    func chargeOrThrow(_ service: CreditService, cost override: Int? = nil, detail: String) throws -> UUID {
        guard let id = charge(service, cost: override, detail: detail) else { throw CreditError(message: lastMessage) }
        return id
    }

    func refund(_ id: UUID, reason: String) {
        guard let spent = entries.first(where: { $0.id == id && $0.kind == .spend }),
              !entries.contains(where: { $0.kind == .refund && $0.refundOf == id }) else { return }
        balance += -spent.amount
        let entry = CreditEntry(kind: .refund, amount: -spent.amount, balanceAfter: balance, serviceID: spent.serviceID,
                                title: "Returned: " + spent.title, detail: reason, refundOf: id)
        entries.insert(entry, at: 0)
        persist()
    }

    /// Adds credits that were bought or given. The place the future purchase module will call.
    func add(_ amount: Int, kind: CreditKind, title: String, detail: String = "") {
        guard amount > 0 else { return }
        refreshIdentity()
        balance += amount
        entries.insert(CreditEntry(kind: kind, amount: amount, balanceAfter: balance, serviceID: nil, title: title, detail: detail), at: 0)
        persist()
    }

    private func askApproval(service: CreditService, price: Int, detail: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Use \(price) credits?"
        alert.informativeText = "\(service.title)" + (detail.isEmpty ? "" : " · \(detail)") + "\n\nThis is above your approval limit of \(approvalLimit) credits. You have \(balance) credits."
        alert.addButton(withTitle: "Approve \(price) credits")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Reports

    var usedThisMonth: Int {
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        return entries.filter { $0.kind == .spend && $0.date >= start }.reduce(0) { $0 - $1.amount } - entries.filter { $0.kind == .refund && $0.date >= start }.reduce(0) { $0 + $1.amount }
    }

    struct UsageRow: Identifiable { var service: CreditService; var total: Int; var id: String { service.rawValue } }

    func usageByService() -> [UsageRow] {
        var totals: [String: Int] = [:]
        for entry in entries where entry.kind == .spend || entry.kind == .refund {
            guard let id = entry.serviceID else { continue }
            totals[id, default: 0] += -entry.amount
        }
        return CreditService.allCases.compactMap { service in
            let total = totals[service.rawValue] ?? 0
            return total > 0 ? UsageRow(service: service, total: total) : nil
        }.sorted { $0.total > $1.total }
    }

    func csv() -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["date,type,credits,balance_after,service,detail"]
        for entry in entries.reversed() {
            let detail = entry.detail.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\(formatter.string(from: entry.date)),\(entry.kind.title),\(entry.amount),\(entry.balanceAfter),\"\(entry.title)\",\"\(detail)\"")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Small chip used in popups

/// "⚡ 10 credits" next to a button, or the balance when no price is given. Always visible where work is paid for.
struct CreditChip: View {
    @ObservedObject private var credits = CreditsCenter.shared
    var cost: Int? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold))
            if let cost {
                Text("\(cost) credits")
            } else {
                Text("\(credits.balance) credits")
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(Butter.coral)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Butter.coral.opacity(0.12), in: Capsule())
        .help(cost.map { "This uses \($0) credits. You have \(credits.balance) left." } ?? "Your credit balance")
    }
}

// MARK: - Settings screen

struct CreditsView: View {
    @ObservedObject private var credits = CreditsCenter.shared
    @State private var filter = "All"
    @State private var showAll = false

    private var shown: [CreditEntry] {
        let list: [CreditEntry]
        switch filter {
        case "Used": list = credits.entries.filter { $0.kind == .spend }
        case "Added": list = credits.entries.filter { $0.amount > 0 }
        default: list = credits.entries
        }
        return showAll ? list : Array(list.prefix(30))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            balanceCard
            usageCard
            pricesCard
            historyCard
        }
        .onAppear { credits.reload() }
    }

    private var balanceCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Credit balance").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(credits.balance.formatted()).font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(Butter.coral)
                    Text("credits").foregroundStyle(.secondary)
                }
                Text("\(credits.usedThisMonth.formatted()) used this month").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button { } label: { Label("Buy credits", systemImage: "cart") }.buttonStyle(.bordered).disabled(true)
                Text("Buying credits is coming soon.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16).background(Butter.coral.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private var usageCard: some View {
        let usage = credits.usageByService()
        let top = max(1, usage.first?.total ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Where credits went").font(.headline)
            if usage.isEmpty {
                Text("Nothing used yet. Credits are used when you make a design, a picture or a video, or rewrite text with AI.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(usage) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.service.symbol).frame(width: 22).foregroundStyle(Butter.coral)
                    Text(row.service.title).font(.callout).frame(width: 220, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4).fill(Butter.coral.opacity(0.55)).frame(width: max(4, geo.size.width * CGFloat(row.total) / CGFloat(top)), height: 8)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }.frame(height: 14)
                    Text("\(row.total.formatted())").font(.system(.callout, design: .rounded).weight(.semibold)).frame(width: 70, alignment: .trailing)
                }
            }
        }
        .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.15)))
    }

    private var pricesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Prices").font(.headline)
                Spacer()
                Button("Reset prices") { credits.resetCosts() }.buttonStyle(.borderless).font(.caption)
            }
            Text("Each service has a price between 5 and 30 credits, set by how much work it does. You can change a price here.").font(.caption).foregroundStyle(.secondary)
            ForEach(CreditService.allCases) { service in
                HStack(spacing: 10) {
                    Image(systemName: service.symbol).frame(width: 22).foregroundStyle(Butter.coral)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(service.title).font(.callout.weight(.semibold))
                        Text(service.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Stepper(value: Binding(get: { credits.cost(service) }, set: { credits.setCost(service, $0) }), in: 5...100, step: 5) {
                        Text("\(credits.cost(service)) credits").font(.system(.callout, design: .rounded).weight(.semibold)).frame(width: 90, alignment: .trailing)
                    }
                }
            }
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "hand.raised").frame(width: 22).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask me first above").font(.callout.weight(.semibold))
                    Text("Anything that costs more than this needs your approval each time. Everything else just goes ahead.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Stepper(value: Binding(get: { credits.approvalLimit }, set: { credits.setApprovalLimit($0) }), in: 5...100, step: 5) {
                    Text("\(credits.approvalLimit) credits").font(.system(.callout, design: .rounded).weight(.semibold)).frame(width: 90, alignment: .trailing)
                }
            }
        }
        .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.15)))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("History").font(.headline)
                Spacer()
                Picker("", selection: $filter) { Text("All").tag("All"); Text("Used").tag("Used"); Text("Added").tag("Added") }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                Button("Export CSV") { export() }.buttonStyle(.bordered).controlSize(.small)
            }
            if shown.isEmpty { Text("No entries yet.").font(.callout).foregroundStyle(.secondary) }
            ForEach(shown) { entry in
                HStack(spacing: 10) {
                    Image(systemName: entry.amount >= 0 ? "plus.circle.fill" : "minus.circle.fill")
                        .foregroundStyle(entry.amount >= 0 ? Color.green : Butter.coral).frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title).font(.callout.weight(.semibold)).lineLimit(1)
                        Text((entry.detail.isEmpty ? "" : entry.detail + " · ") + entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text((entry.amount > 0 ? "+" : "") + entry.amount.formatted()).font(.system(.callout, design: .rounded).weight(.bold))
                            .foregroundStyle(entry.amount >= 0 ? Color.green : Color.primary)
                        Text("balance \(entry.balanceAfter.formatted())").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Divider()
            }
            if !showAll && credits.entries.count > 30 {
                Button("Show everything (\(credits.entries.count))") { showAll = true }.buttonStyle(.borderless)
            }
        }
        .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.15)))
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "KeyDo-credit-history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? credits.csv().write(to: url, atomically: true, encoding: .utf8)
    }
}
