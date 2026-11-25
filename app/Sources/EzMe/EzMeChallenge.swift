import SwiftUI
import AppKit

// 7-day KeyDo Challenge.
// Each day has one task. Completing all 7 earns the "KeyDo Pro" badge (social-shareable card).
// Progress is stored locally (UserDefaults) and synced to Supabase when signed in.
// Streak is visible on the Home screen once the user starts.

// MARK: - Challenge definition

struct ChallengeDay: Identifiable {
    let id: Int // 1–7
    let taskKey: String
    let title: String
    let detail: String
    let symbol: String
    let cta: String
    let ctaAction: String // internal action name
}

enum Challenge {
    static let days: [ChallengeDay] = [
        ChallengeDay(id: 1, taskKey: "save_signature",
            title: "Save your signature",
            detail: "Type \\sig and save your full email signature — name, title, company, phone. Use it in your next email.",
            symbol: "signature",
            cta: "Open Library", ctaAction: "open_library"),
        ChallengeDay(id: 2, taskKey: "save_reply_template",
            title: "Save a reply template",
            detail: "What do you type in emails every day? Save it as \\thanks, \\follow, or \\sorry. Try it in Gmail right now.",
            symbol: "envelope.fill",
            cta: "Open Library", ctaAction: "open_library"),
        ChallengeDay(id: 3, taskKey: "try_live_value",
            title: "Use a live value",
            detail: "Start a shortcut with {=TODAY()} — it always pastes today's date. Try {=Date+30} for a date 30 days from now.",
            symbol: "calendar",
            cta: "Open Library", ctaAction: "open_library"),
        ChallengeDay(id: 4, taskKey: "try_calculator",
            title: "Calculate in a shortcut",
            detail: "Make a shortcut that starts with {=} and a formula. Try {=12*4500} for a quick calculation without opening Calculator.",
            symbol: "function",
            cta: "Open Library", ctaAction: "open_library"),
        ChallengeDay(id: 5, taskKey: "try_wish_studio",
            title: "Send a wish card",
            detail: "Type hbd- and a name in any app. KeyDo will offer you a birthday card ready to share on WhatsApp in one tap.",
            symbol: "sparkles",
            cta: "Open Wish Studio", ctaAction: "open_wish_studio"),
        ChallengeDay(id: 6, taskKey: "share_collection",
            title: "Share a collection",
            detail: "Export one of your collections and share it with a colleague or friend — or install a pack from the Marketplace.",
            symbol: "square.and.arrow.up",
            cta: "Open Marketplace", ctaAction: "open_marketplace"),
        ChallengeDay(id: 7, taskKey: "try_app_builder",
            title: "Build something with AppBuilder",
            detail: "Open AppBuilder and try one of the starter packs — an invoice, a quotation, or a greeting card. Build it in under 2 minutes.",
            symbol: "doc.richtext.fill",
            cta: "Open AppBuilder", ctaAction: "open_app_builder"),
    ]
}

// MARK: - Manager

@MainActor final class ChallengeManager: ObservableObject {
    static let shared = ChallengeManager()

    @Published private(set) var completedDays: Set<Int> = []
    @Published private(set) var badgeEarned = false
    @Published var showBadgeSheet = false

    private static let completedKey = "keydoChallengeCompleted"
    private static let badgeKey = "keydoBadgeEarned"
    private static let startedKey = "keydoChallengeStarted"

    var hasStarted: Bool { UserDefaults.standard.bool(forKey: Self.startedKey) }
    var nextDay: ChallengeDay? { Challenge.days.first { !completedDays.contains($0.id) } }
    var streak: Int { completedDays.count }
    var isComplete: Bool { completedDays.count == 7 }

    private init() {
        let saved = UserDefaults.standard.array(forKey: Self.completedKey) as? [Int] ?? []
        completedDays = Set(saved)
        badgeEarned = UserDefaults.standard.bool(forKey: Self.badgeKey)
    }

    func start() {
        UserDefaults.standard.set(true, forKey: Self.startedKey)
        objectWillChange.send()
    }

    func markComplete(day: Int) {
        guard day >= 1, day <= 7 else { return }
        completedDays.insert(day)
        UserDefaults.standard.set(Array(completedDays), forKey: Self.completedKey)
        syncDayToServer(day: day)
        if isComplete && !badgeEarned {
            badgeEarned = true
            UserDefaults.standard.set(true, forKey: Self.badgeKey)
            showBadgeSheet = true
            Task { await syncCompletionToServer() }
        }
    }

    // Server sync (best-effort)
    private func syncDayToServer(day: Int) {
        guard EzMeCloud.shared.isSignedIn,
              let token = EzMeCloud.shared.session?.accessToken,
              let taskKey = Challenge.days.first(where: { $0.id == day })?.taskKey,
              let url = URL(string: EzMeCloud.supabaseURL + "/rest/v1/rpc/complete_challenge_day") else { return }
        Task {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(EzMeCloud.supabaseKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["p_day": day, "p_task_key": taskKey])
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    private func syncCompletionToServer() async {
        // The RPC auto-inserts into challenge_completions after 7 days (server-side check)
    }
}

// MARK: - Home screen streak pill

struct ChallengeStreakPill: View {
    @ObservedObject private var mgr = ChallengeManager.shared

    var body: some View {
        if mgr.hasStarted && !mgr.isComplete {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                Text("\(mgr.streak) / 7 days").font(.system(size: 12, weight: .semibold, design: .rounded))
                if let next = mgr.nextDay {
                    Text("· Day \(next.id): \(next.title)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.orange.opacity(0.12), in: Capsule())
        } else if mgr.isComplete {
            HStack(spacing: 6) {
                Image(systemName: "rosette").foregroundStyle(Butter.coral)
                Text("7-Day Challenge Complete!").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Butter.coral)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Butter.coral.opacity(0.12), in: Capsule())
            .onTapGesture { ChallengeManager.shared.showBadgeSheet = true }
        }
    }
}

// MARK: - Main challenge view

struct ChallengeView: View {
    @ObservedObject private var mgr = ChallengeManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                challengeHeader
                Divider()
                VStack(spacing: 1) {
                    ForEach(Challenge.days) { day in
                        DayCellView(day: day)
                    }
                }
            }
        }
        .sheet(isPresented: $mgr.showBadgeSheet) { BadgeView() }
    }

    private var challengeHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.orange.opacity(0.15)).frame(width: 54, height: 54)
                    Image(systemName: "flame.fill").font(.title2).foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("7-Day KeyDo Challenge").font(.headline)
                    Text("One task a day. Finish all 7 and earn your KeyDo Pro badge.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(mgr.streak)").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(.orange)
                    Text("/ 7 done").font(.caption2).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(mgr.streak), total: 7)
                .tint(.orange)
            if !mgr.hasStarted {
                Button("Start the Challenge") { mgr.start() }
                    .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
            }
        }
        .padding(20)
    }
}

struct DayCellView: View {
    let day: ChallengeDay
    @ObservedObject private var mgr = ChallengeManager.shared

    private var isDone: Bool { mgr.completedDays.contains(day.id) }
    private var isNext: Bool { mgr.nextDay?.id == day.id }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(isDone ? Color.green.opacity(0.15) : (isNext ? Color.orange.opacity(0.1) : Color(.controlBackgroundColor))).frame(width: 42, height: 42)
                if isDone {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                } else {
                    Image(systemName: day.symbol).font(.callout).foregroundStyle(isNext ? .orange : .secondary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Day \(day.id)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if isNext { Text("NEXT").font(.system(size: 9, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2).background(.orange.opacity(0.15), in: Capsule()).foregroundStyle(.orange) }
                }
                Text(day.title).font(.callout.weight(.semibold)).foregroundStyle(isDone ? .secondary : .primary)
                if isNext { Text(day.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            if !isDone {
                Button("Done") { mgr.markComplete(day: day.id) }
                    .buttonStyle(.bordered).controlSize(.small).disabled(!mgr.hasStarted && day.id != 1)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(isNext ? Color.orange.opacity(0.04) : Color.clear)
        .opacity(isDone ? 0.6 : 1)
    }
}

// MARK: - Badge sheet

struct BadgeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().fill(LinearGradient(colors: [Butter.coral, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                VStack(spacing: 4) {
                    Image(systemName: "rosette").font(.system(size: 42)).foregroundStyle(.white)
                    Text("PRO").font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                }
            }
            .shadow(color: Butter.coral.opacity(0.4), radius: 20, x: 0, y: 8)

            VStack(spacing: 8) {
                Text("Challenge Complete! 🎉").font(.title2.weight(.bold))
                Text("You've completed the 7-Day KeyDo Challenge.\nYou are now a KeyDo power user.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button {
                    let card = BadgeCardMaker.makeCard()
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    if let data = card.tiffRepresentation { pasteboard.setData(data, forType: .tiff) }
                } label: {
                    Label("Copy badge card", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Butter.coral)

                Button {
                    let text = "I just completed the 7-Day @KeyDo Challenge on my Mac! 🏆 Save shortcuts, live values, wish cards, AppBuilder — all in 7 days. Try it free: https://ezme.ezyourlife.com #KeyDo #Productivity"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy share text", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
            Button("Done") { dismiss() }.buttonStyle(.borderless)
        }
        .padding(32).frame(width: 380, height: 480)
    }
}

// MARK: - Badge image maker

enum BadgeCardMaker {
    @MainActor static func makeCard() -> NSImage {
        let size = CGSize(width: 1080, height: 1080)
        let image = NSImage(size: size)
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }

        // Background
        let bg = CGColor(red: 0.98, green: 0.95, blue: 0.92, alpha: 1)
        ctx.setFillColor(bg)
        ctx.fill(CGRect(origin: .zero, size: size))

        // Gradient circle
        let centre = CGPoint(x: 540, y: 580)
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: 1, green: 0.3, blue: 0.3, alpha: 1), CGColor(red: 1, green: 0.5, blue: 0.1, alpha: 1)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(grad, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: 320, options: [])

        // Text
        let title = "KeyDo Pro" as NSString
        title.draw(at: CGPoint(x: 300, y: 160),
                   withAttributes: [.font: NSFont.boldSystemFont(ofSize: 72), .foregroundColor: NSColor(red: 0.15, green: 0.1, blue: 0.08, alpha: 1)])
        let sub = "7-Day Challenge Complete" as NSString
        sub.draw(at: CGPoint(x: 220, y: 90),
                 withAttributes: [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.secondaryLabelColor])

        image.unlockFocus()
        return image
    }
}
