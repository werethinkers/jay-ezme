import SwiftUI
import AppKit

// KeyDo Wall — community experiences, tips and showcases.
// Users share how they use KeyDo. The team posts official tips and answers.
// Posts go through simple approval (is_approved flag) so the wall stays clean.

// MARK: - Model

struct WallPost: Identifiable, Codable {
    var id: UUID
    var authorId: UUID?
    var displayName: String
    var postType: String // experience | tip | showcase | official
    var content: String
    var shortcutKey: String?
    var imageUrl: String?
    var likes: Int
    var isApproved: Bool
    var isFeatured: Bool
    var isKeydoOfficial: Bool
    var language: String
    var createdAt: Date?

    var typeLabel: String {
        switch postType {
        case "tip": return "Tip"
        case "showcase": return "Showcase"
        case "official": return "KeyDo Team"
        default: return "Experience"
        }
    }

    var typeSymbol: String {
        switch postType {
        case "tip": return "lightbulb.fill"
        case "showcase": return "sparkles"
        case "official": return "checkmark.seal.fill"
        default: return "bubble.left.fill"
        }
    }

    var typeColor: Color {
        switch postType {
        case "tip": return .orange
        case "showcase": return .purple
        case "official": return Color.blue
        default: return Butter.coral
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, authorId = "author_id", displayName = "display_name"
        case postType = "post_type", content, shortcutKey = "shortcut_key"
        case imageUrl = "image_url", likes, isApproved = "is_approved"
        case isFeatured = "is_featured", isKeydoOfficial = "is_keydo_official"
        case language, createdAt = "created_at"
    }
}

// MARK: - Manager

@MainActor final class WallManager: ObservableObject {
    static let shared = WallManager()

    @Published private(set) var posts: [WallPost] = []
    @Published private(set) var likedIDs: Set<UUID> = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    @Published var filterType = "all"
    @Published var showCompose = false

    var filtered: [WallPost] {
        filterType == "all" ? posts : posts.filter { $0.postType == filterType }
    }

    var featured: [WallPost] { posts.filter { $0.isFeatured || $0.isKeydoOfficial } }

    private init() { Task { await load() } }

    func load() async {
        isLoading = true; loadError = nil
        guard let url = URL(string: EzMeCloud.supabaseURL + "/rest/v1/wall_posts?is_approved=eq.true&order=is_featured.desc,created_at.desc&limit=100") else { isLoading = false; return }
        var req = URLRequest(url: url)
        req.setValue(EzMeCloud.supabaseKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else {
            loadError = "Could not load. Check your connection."; isLoading = false; return
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            return formatter.date(from: s) ?? Date()
        }
        if let loaded = try? decoder.decode([WallPost].self, from: data) { posts = loaded }
        isLoading = false
    }

    func like(post: WallPost) async {
        guard !likedIDs.contains(post.id), EzMeCloud.shared.isSignedIn,
              let token = EzMeCloud.shared.session?.accessToken,
              let url = URL(string: EzMeCloud.supabaseURL + "/rest/v1/rpc/like_wall_post") else { return }
        likedIDs.insert(post.id)
        if let idx = posts.firstIndex(where: { $0.id == post.id }) { posts[idx].likes += 1 }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(EzMeCloud.supabaseKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["p_post_id": post.id.uuidString])
        _ = try? await URLSession.shared.data(for: req)
    }

    func submit(displayName: String, content: String, postType: String, shortcutKey: String?) async throws {
        guard EzMeCloud.shared.isSignedIn, let token = EzMeCloud.shared.session?.accessToken,
              let userID = EzMeCloud.shared.session?.userID,
              let url = URL(string: EzMeCloud.supabaseURL + "/rest/v1/wall_posts") else {
            throw NSError(domain: "Wall", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sign in to post to the Wall"])
        }
        var payload: [String: Any] = ["author_id": userID as Any, "display_name": displayName, "post_type": postType, "content": content, "is_approved": false]
        if let key = shortcutKey, !key.isEmpty { payload["shortcut_key"] = key }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(EzMeCloud.supabaseKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 201 else {
            throw NSError(domain: "Wall", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not submit post"])
        }
    }
}

// MARK: - Main view

struct WallView: View {
    @ObservedObject private var mgr = WallManager.shared
    @State private var showCompose = false

    var body: some View {
        VStack(spacing: 0) {
            wallHeader
            filterBar
            Divider()
            if mgr.isLoading {
                Spacer()
                ProgressView("Loading the Wall…").frame(maxWidth: .infinity)
                Spacer()
            } else if let err = mgr.loadError {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash").font(.largeTitle).foregroundStyle(.secondary)
                    Text(err).font(.callout).foregroundStyle(.secondary)
                    Button("Retry") { Task { await mgr.load() } }.buttonStyle(.bordered)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(mgr.filtered) { post in WallPostCard(post: post) }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(isPresented: $showCompose) { ComposeWallPostView() }
    }

    private var wallHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack.fill").font(.title3).foregroundStyle(Butter.coral)
            VStack(alignment: .leading, spacing: 1) {
                Text("KeyDo Wall").font(.headline)
                Text("Real experiences, tips and tricks from the KeyDo community.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showCompose = true } label: { Label("Share your experience", systemImage: "plus") }
                .buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.small)
        }
        .padding(16)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([("all","All","square.grid.2x2"), ("official","From KeyDo","checkmark.seal.fill"), ("tip","Tips","lightbulb.fill"), ("showcase","Showcases","sparkles"), ("experience","Experiences","bubble.left.fill")], id: \.0) { id, label, sym in
                    Button {
                        mgr.filterType = id
                    } label: {
                        Label(label, systemImage: sym).font(.caption.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(mgr.filterType == id ? Butter.coral : Color(.controlBackgroundColor), in: Capsule())
                            .foregroundStyle(mgr.filterType == id ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }
}

// MARK: - Post card

struct WallPostCard: View {
    let post: WallPost
    @ObservedObject private var mgr = WallManager.shared
    @State private var liking = false

    private var isLiked: Bool { mgr.likedIDs.contains(post.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // Type badge
                Label(post.typeLabel, systemImage: post.typeSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(post.typeColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(post.typeColor)
                if post.isKeydoOfficial {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.blue).font(.caption2)
                }
                Spacer()
                Text(post.displayName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let date = post.createdAt {
                    Text("·").foregroundStyle(.secondary)
                    Text(date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(post.content).font(.callout).fixedSize(horizontal: false, vertical: true)
            if let key = post.shortcutKey {
                Text("\\\(key)").font(.system(size: 12, design: .monospaced).weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Butter.coral)
            }
            HStack {
                Spacer()
                Button {
                    liking = true
                    Task { await mgr.like(post: post); liking = false }
                } label: {
                    Label("\(post.likes)", systemImage: isLiked ? "heart.fill" : "heart")
                        .font(.caption.weight(.semibold)).foregroundStyle(isLiked ? .red : .secondary)
                }
                .buttonStyle(.plain).disabled(liking || isLiked)
            }
        }
        .padding(16)
        .background(post.isFeatured ? Butter.coral.opacity(0.04) : Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(post.isFeatured ? Butter.coral.opacity(0.2) : Color.secondary.opacity(0.15)))
    }
}

// MARK: - Compose sheet

struct ComposeWallPostView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = EzMeCloud.shared.session?.name ?? ""
    @State private var postType = "experience"
    @State private var content = ""
    @State private var shortcutKey = ""
    @State private var submitting = false
    @State private var error: String?
    @State private var submitted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Share with the KeyDo community").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if submitted {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                            Text("Thanks! Your post will appear on the Wall once approved.").font(.callout).multilineTextAlignment(.center)
                            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity).padding(40)
                    } else {
                        TextField("Your name or handle", text: $displayName).textFieldStyle(.roundedBorder)
                        Picker("Post type", selection: $postType) {
                            Text("My experience").tag("experience")
                            Text("A tip").tag("tip")
                            Text("Showcase").tag("showcase")
                        }.pickerStyle(.segmented)
                        TextEditor(text: $content)
                            .font(.callout).frame(minHeight: 100)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                        if content.isEmpty { Text("What do you want to share? A shortcut that saves you time, a workflow tip, how KeyDo helps your team…").font(.caption).foregroundStyle(.tertiary).allowsHitTesting(false) }
                        HStack {
                            Text("Shortcut key (optional)").font(.caption).foregroundStyle(.secondary)
                            TextField("e.g. inv, sig, thanks", text: $shortcutKey).textFieldStyle(.roundedBorder).frame(width: 160)
                        }
                        if let err = error { Text(err).font(.caption).foregroundStyle(.red) }
                    }
                }
                .padding(20)
            }
            if !submitted {
                Divider()
                HStack {
                    Text("Posts are reviewed before appearing. No spam or advertising.").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button(submitting ? "Submitting…" : "Submit") {
                        Task { await submit() }
                    }
                    .buttonStyle(.borderedProminent).tint(Butter.coral).disabled(content.isEmpty || displayName.isEmpty || submitting)
                }
                .padding(16)
            }
        }
        .frame(width: 500, height: submitted ? 300 : 480)
    }

    private func submit() async {
        submitting = true; error = nil
        do {
            try await WallManager.shared.submit(displayName: displayName, content: content, postType: postType, shortcutKey: shortcutKey.isEmpty ? nil : shortcutKey)
            submitted = true
        } catch {
            self.error = error.localizedDescription
        }
        submitting = false
    }
}
