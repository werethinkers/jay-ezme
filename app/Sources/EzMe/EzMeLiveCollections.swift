// Live collections: a collection that refreshes itself from a feed (RSS or Atom) daily, weekly or in a season.
// Each refresh replaces the collection's live shortcuts, so \news1 is always the newest item.
import SwiftUI
import Foundation

enum LiveFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, seasonal, manual
    var id: String { rawValue }
    var title: String { switch self { case .daily: return "Daily"; case .weekly: return "Weekly"; case .seasonal: return "Seasonal (daily, between two dates)"; case .manual: return "Only when I press Update" } }
    var short: String { switch self { case .daily: return "daily"; case .weekly: return "weekly"; case .seasonal: return "seasonal"; case .manual: return "manual" } }
}

struct LiveCollectionSource: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var collection: String
    var url: String
    var frequency: LiveFrequency = .daily
    var maxItems: Int = 10
    var seasonStart: Date? = nil
    var seasonEnd: Date? = nil
    var lastRun: Date? = nil
    var lastStatus: String = ""
}

struct LiveFeedItem { var title = ""; var link = ""; var date = ""; var summary = "" }

/// Reads the items of an RSS or Atom feed.
final class LiveFeedParser: NSObject, XMLParserDelegate {
    private(set) var items = [LiveFeedItem]()
    private var current: LiveFeedItem?
    private var element = ""
    private var text = ""

    static func parse(_ data: Data) -> [LiveFeedItem] {
        let parser = XMLParser(data: data)
        let delegate = LiveFeedParser()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.parse()
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        let lower = name.lowercased()
        if lower == "item" || lower == "entry" { current = LiveFeedItem() }
        element = lower
        text = ""
        if current != nil, lower == "link", let href = attributes["href"], current?.link.isEmpty == true { current?.link = href }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(data: CDATABlock, encoding: .utf8) ?? "" }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let lower = name.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if current != nil {
            switch lower {
            case "title": if current?.title.isEmpty == true { current?.title = value }
            case "link": if current?.link.isEmpty == true, !value.isEmpty { current?.link = value }
            case "pubdate", "updated", "published", "dc:date": if current?.date.isEmpty == true { current?.date = value }
            case "description", "summary", "content": if current?.summary.isEmpty == true { current?.summary = Self.plain(value) }
            default: break
            }
        }
        if lower == "item" || lower == "entry", let done = current { if !done.title.isEmpty { items.append(done) }; current = nil }
        text = ""
    }

    private static func plain(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(stripped.prefix(280))
    }
}

@MainActor final class LiveCollections: ObservableObject {
    static let shared = LiveCollections()
    private static let key = "keydoLiveCollectionsJSON"
    weak var db: DB?
    @Published var sources: [LiveCollectionSource] = []
    @Published var busy = Set<String>()
    private var timer: Timer?

    private init() {
        if let data = UserDefaults.standard.string(forKey: Self.key)?.data(using: .utf8), let saved = try? JSONDecoder().decode([LiveCollectionSource].self, from: data) { sources = saved }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(sources), let text = String(data: data, encoding: .utf8) { UserDefaults.standard.set(text, forKey: Self.key) }
    }

    /// Starts the half-hourly check that refreshes whatever is due. Safe to call more than once.
    func start(db: DB) {
        self.db = db
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in Task { @MainActor in LiveCollections.shared.refreshDue() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { LiveCollections.shared.refreshDue() }
    }

    func add(_ source: LiveCollectionSource) { sources.append(source); persist() }
    func remove(_ id: String) { sources.removeAll { $0.id == id }; persist() }
    func update(_ source: LiveCollectionSource) { if let index = sources.firstIndex(where: { $0.id == source.id }) { sources[index] = source; persist() } }

    func isDue(_ source: LiveCollectionSource, now: Date = Date()) -> Bool {
        let age = source.lastRun.map { now.timeIntervalSince($0) } ?? .infinity
        switch source.frequency {
        case .manual: return false
        case .daily: return age > 20 * 3600
        case .weekly: return age > 6.5 * 86400
        case .seasonal:
            guard let start = source.seasonStart, let end = source.seasonEnd, now >= start, now <= end.addingTimeInterval(86400) else { return false }
            return age > 20 * 3600
        }
    }

    func refreshDue() { for source in sources where isDue(source) && !busy.contains(source.id) { Task { await refresh(source.id) } } }

    func refresh(_ id: String) async {
        guard let source = sources.first(where: { $0.id == id }), !busy.contains(id) else { return }
        busy.insert(id)
        defer { busy.remove(id) }
        var result = source
        do {
            guard let url = URL(string: source.url.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.hasPrefix("http") == true else { throw NSError(domain: "KeyDoLive", code: 1, userInfo: [NSLocalizedDescriptionKey: "The feed address is not a web link."]) }
            var request = URLRequest(url: url, timeoutInterval: 25)
            request.setValue("Mozilla/5.0 KeyDo", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 { throw NSError(domain: "KeyDoLive", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "The site answered \(http.statusCode)."]) }
            let items = Array(LiveFeedParser.parse(data).prefix(max(1, min(source.maxItems, 30))))
            guard !items.isEmpty else { throw NSError(domain: "KeyDoLive", code: 2, userInfo: [NSLocalizedDescriptionKey: "No items found. This needs an RSS or Atom feed address."]) }
            apply(items, to: source)
            result.lastStatus = "Updated with \(items.count) item\(items.count == 1 ? "" : "s")."
        } catch {
            result.lastStatus = "Not updated: \(error.localizedDescription)"
        }
        result.lastRun = Date()
        update(result)
    }

    /// Replaces the collection's live shortcuts (marked with the keyword live-feed). The person's own shortcuts are never touched.
    private func apply(_ items: [LiveFeedItem], to source: LiveCollectionSource) {
        guard let db else { return }
        let name = source.collection
        let letters = String(name.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(10))
        let stem = letters.isEmpty ? "live" : letters
        db.clips.removeAll { $0.group.caseInsensitiveCompare(name) == .orderedSame && ($0.keywords ?? "").contains("live-feed") }
        let taken = Set(db.clips.map { $0.key.lowercased() })
        var made = [Clip]()
        for (index, item) in items.enumerated() {
            var key = "/\(stem)\(index + 1)"
            if taken.contains(key.lowercased()) { key = "/\(stem)live\(index + 1)" }
            let lines = [item.title, item.date, item.summary, item.link].filter { !$0.isEmpty }
            var clip = Clip(key: key, name: item.title, text: lines.joined(separator: "\n"), group: name)
            clip.keywords = "live-feed"
            made.append(clip)
        }
        if !db.collections.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { db.collections.append(name) }
        db.clips.insert(contentsOf: made, at: 0)
    }
}

/// Where each preset points. Google News search feeds give headlines and links about a topic; they are not price or score tables.
struct LivePreset: Identifiable {
    let name: String; let query: String; let frequency: LiveFrequency; let note: String
    var id: String { name }
    var url: String { "https://news.google.com/rss/search?q=" + (query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query) + "&hl=en-IN&gl=IN&ceid=IN:en" }
    static let all: [LivePreset] = [
        LivePreset(name: "News Updates", query: "top news India when:1d", frequency: .daily, note: "Headlines, every day"),
        LivePreset(name: "Stock Updates", query: "stock market Sensex Nifty when:1d", frequency: .daily, note: "Market headlines, every day"),
        LivePreset(name: "Movie Trailers", query: "new movie trailer released", frequency: .weekly, note: "Trailer news, every week"),
        LivePreset(name: "Cricket Score", query: "cricket match score", frequency: .seasonal, note: "Match news in a season you set"),
        LivePreset(name: "Hindi Dance Songs", query: "latest Hindi dance songs", frequency: .weekly, note: "New songs, every week"),
        LivePreset(name: "Music Label Hindi Songs", query: "T-Series Zee Music Sony Music new Hindi song", frequency: .weekly, note: "New label releases, every week")
    ]
}

/// The Live updates card in Collection Builder.
struct CollectionLiveUpdatesBox: View {
    @ObservedObject private var live = LiveCollections.shared
    @State private var open = false
    @State private var name = ""
    @State private var url = ""
    @State private var frequency = LiveFrequency.daily
    @State private var seasonStart = Date()
    @State private var seasonEnd = Calendar.current.date(byAdding: .month, value: 2, to: Date()) ?? Date()
    @State private var error = ""

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 10) {
                Text("A live collection fills itself from a feed address (RSS or Atom) and refreshes on its own while KeyDo is open. Its shortcuts are numbered, so \\news1 is always the newest. Your own shortcuts in the same collection are never changed.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(live.sources) { source in row(source) }
                Divider()
                HStack(spacing: 6) {
                    Menu {
                        ForEach(LivePreset.all) { preset in
                            Button(preset.name + " · " + preset.note) { name = preset.name; url = preset.url; frequency = preset.frequency }
                        }
                    } label: { Label("Ready-made", systemImage: "sparkles") }.menuStyle(.borderlessButton).fixedSize()
                    TextField("Collection name", text: $name).textFieldStyle(.roundedBorder).controlSize(.small).frame(maxWidth: 180)
                    TextField("Feed address (RSS or Atom)", text: $url).textFieldStyle(.roundedBorder).controlSize(.small)
                }
                HStack(spacing: 8) {
                    Picker("", selection: $frequency) { ForEach(LiveFrequency.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 250)
                    if frequency == .seasonal {
                        DatePicker("From", selection: $seasonStart, displayedComponents: .date).labelsHidden().controlSize(.small)
                        DatePicker("To", selection: $seasonEnd, displayedComponents: .date).labelsHidden().controlSize(.small)
                    }
                    Spacer()
                    Button { addSource() } label: { Label("Add live collection", systemImage: "plus.circle.fill") }.buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.small)
                }
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
                Text("Ready-made ones use Google News search feeds: they bring headlines and links about the topic, not price or score tables. Check the address in a browser if a collection stays empty, or paste any other RSS or Atom address.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Live updates: daily, weekly or seasonal").font(.system(size: 13, weight: .semibold))
                Text("News, stocks, trailers, cricket and new Hindi songs that refresh on their own.").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ source: LiveCollectionSource) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(source.collection).font(.system(size: 13, weight: .semibold)).foregroundStyle(Butter.cocoa)
                    Text(source.frequency.short.uppercased()).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 1).background(Butter.coral, in: Capsule())
                }
                Text(source.lastStatus.isEmpty ? "Not updated yet" : source.lastStatus + (source.lastRun.map { " " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if live.busy.contains(source.id) { ProgressView().controlSize(.small) }
            Button("Update now") { Task { await live.refresh(source.id) } }.controlSize(.small).disabled(live.busy.contains(source.id))
            Button { live.remove(source.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.red.opacity(0.8)).help("Stop updating this collection (its shortcuts stay)")
        }
        .padding(8).background(Butter.cream, in: RoundedRectangle(cornerRadius: 10))
    }

    private func addSource() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !address.isEmpty else { error = "Give the collection a name and a feed address, or pick a Ready-made one."; return }
        guard URL(string: address)?.scheme?.hasPrefix("http") == true else { error = "The feed address must start with http or https."; return }
        error = ""
        var source = LiveCollectionSource(collection: clean, url: address, frequency: frequency)
        if frequency == .seasonal { source.seasonStart = Calendar.current.startOfDay(for: seasonStart); source.seasonEnd = Calendar.current.startOfDay(for: seasonEnd) }
        live.add(source)
        name = ""; url = ""
        Task { await live.refresh(source.id) }
    }
}
