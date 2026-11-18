// What kind of page is open (song, music, lecture, podcast, movie, video, article) and names, shortcuts, tags and a
// collection that fit it. A YouTube link can be a song or a lecture, so the name is the whole topic, not the site.
import Foundation

enum PageKind: String {
    case song, music, lecture, podcast, movie, video, article, other

    var label: String {
        switch self {
        case .song: return "Song"
        case .music: return "Music"
        case .lecture: return "Lecture"
        case .podcast: return "Podcast"
        case .movie: return "Movie or show"
        case .video: return "Video"
        case .article: return "Article"
        case .other: return "Page"
        }
    }

    /// Short prefix for shortcuts and names.
    var short: String {
        switch self {
        case .song: return "song"
        case .music: return "music"
        case .lecture: return "lec"
        case .podcast: return "pod"
        case .movie: return "movie"
        case .video: return "vid"
        case .article: return "read"
        case .other: return ""
        }
    }

    /// The collection this kind is usually saved under.
    var collection: String? {
        switch self {
        case .song, .music: return "Music"
        case .lecture: return "Lectures"
        case .podcast: return "Podcasts"
        case .movie: return "Movies & Shows"
        case .video: return "Videos"
        case .article: return "Reading"
        case .other: return nil
        }
    }

    private static func has(_ list: [String], in text: String) -> Bool { list.contains { text.contains($0) } }

    static func detect(_ scan: PageScan) -> PageKind {
        let host = scan.host.lowercased()
        let path = scan.path.lowercased()
        let hostPath = host + path
        let genre = scan.genre.lowercased()
        let ogType = scan.ogType.lowercased()

        if has(["spotify.", "music.apple.", "soundcloud.", "gaana.", "jiosaavn.", "saavn.", "wynk", "bandcamp.", "deezer.", "hungama.", "music.youtube.", "tidal.", "audiomack."], in: host) {
            return has(["album", "playlist", "artist"], in: path) ? .music : .song
        }
        if has(["udemy.", "coursera.", "nptel.", "edx.", "khanacademy.", "unacademy.", "swayam", "skillshare.", "ocw.", "pw.live", "physicswallah", "byjus.", "vedantu."], in: host) { return .lecture }
        if has(["podcasts.apple.", "anchor.fm", "podbean.", "castbox.", "podcasts.google."], in: host) { return .podcast }
        if has(["netflix.", "primevideo.", "hotstar.", "jiocinema.", "sonyliv.", "zee5.", "imdb.", "hulu.", "disneyplus."], in: host) { return .movie }
        if ogType.hasPrefix("music.song") { return .song }
        if ogType.hasPrefix("music.") { return .music }
        if ogType.hasPrefix("video.movie") || ogType.hasPrefix("video.tv") { return .movie }

        let videoSite = has(["youtube.", "youtu.be", "vimeo.", "dailymotion.", "facebook.com/watch", "instagram.com/reel"], in: hostPath) || ogType.hasPrefix("video")
        guard videoSite else { return ogType == "article" ? .article : .other }

        // YouTube states its category. It is the most reliable hint.
        if genre.contains("music") { return .song }
        if genre.contains("education") || genre.contains("howto") || genre.contains("science") { return .lecture }
        if genre.contains("film") { return .movie }

        let text = [scan.title, scan.heading, scan.summary, path.replacingOccurrences(of: "-", with: " ")].joined(separator: " ").lowercased()
        if has(["lecture", "tutorial", "lesson", "full course", "crash course", "webinar", "masterclass", "syllabus", "seminar", "nptel", "chapter ", "class "], in: text) { return .lecture }
        if has(["official video", "official audio", "lyrics", "lyrical", " song", "music video", "feat.", " ft.", "remix", "mp3", "bhajan", "aarti", "ghazal", "qawwali", "karaoke", "unplugged", "acoustic", "lofi", "lo-fi", "cover by"], in: text) { return .song }
        if has(["podcast", "episode"], in: text) { return .podcast }
        if has(["trailer", "full movie", "web series", "season "], in: text) { return .movie }
        return .video
    }
}

enum MediaNamer {
    private static let noiseBrackets = "\\s*[\\(\\[][^\\)\\]]*(official|lyric|audio|video|hd|4k|full|live|remaster|visuali[sz]er)[^\\)\\]]*[\\)\\]]"
    private static let noiseWords: Set<String> = ["official", "video", "audio", "lyrics", "lyrical", "full", "song", "songs", "hd", "4k", "new", "latest", "hindi", "english",
                                                   "feat", "ft", "music", "the", "an", "of", "and", "for", "to", "in", "on", "with", "your", "how", "is", "at", "by", "from",
                                                   "live", "lecture", "class", "tutorial", "part", "episode", "ep"]

    /// The whole topic of the page, without the site name: "Tum Hi Ho (Official Video) - Arijit Singh - YouTube" gives
    /// "Tum Hi Ho (Official Video) – Arijit Singh".
    static func cleanTitle(_ scan: PageScan, site: String) -> String {
        var raw = scan.title.isEmpty ? scan.heading : scan.title
        raw = raw.replacingOccurrences(of: "^\\(\\d+\\)\\s*", with: "", options: .regularExpression)
        var parts = [raw]
        for separator in [" | ", " - ", " \u{2013} ", " \u{2014} ", " \u{00B7} ", " \u{2022} ", " :: "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        let siteLower = site.lowercased()
        let hostWord = PageNamer.hostCore(scan.host)
        parts = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^(song|album|playlist|single|ep|podcast)( and lyrics)? by\\s+", with: "", options: [.regularExpression, .caseInsensitive]) }
            .filter { part in
                let lower = part.lowercased()
                if lower.isEmpty || lower == siteLower || lower == hostWord { return false }
                return !(lower.count <= siteLower.count + 8 && !siteLower.isEmpty && lower.contains(siteLower))
            }
        let joined = parts.joined(separator: " \u{2013} ")
        return limit(joined.isEmpty ? site : joined, 100)
    }

    private static func limit(_ text: String, _ count: Int) -> String {
        guard text.count > count else { return text }
        let cut = String(text.prefix(count))
        if let space = cut.lastIndex(of: " ") { return String(cut[..<space]) }
        return cut
    }

    /// Names to pick from, best first. The first one is the whole topic.
    static func nameOptions(_ scan: PageScan, kind: PageKind, site: String) -> [String] {
        let full = cleanTitle(scan, site: site)
        var options = [full]
        let trimmed = full.replacingOccurrences(of: noiseBrackets, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != full { options.append(trimmed) }
        let base = trimmed.isEmpty ? full : trimmed
        options.append(limit("\(kind.label): \(base)", 100))
        if !scan.author.isEmpty, !base.lowercased().contains(scan.author.lowercased()) { options.append(limit("\(base) \u{2013} \(scan.author)", 100)) }
        var seen = Set<String>()
        return options.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Short keys made from the topic, not the site: "tumhiho", "song-tum", "tho".
    static func shortcuts(kind: PageKind, title: String) -> [String] {
        let words = title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 && !noiseWords.contains($0) }
        guard let first = words.first else { return [] }
        var result = [String(words.prefix(3).joined().prefix(12))]
        if !kind.short.isEmpty { result.append(String("\(kind.short)-\(first)".prefix(16))) }
        let initials = String(words.prefix(5).compactMap { $0.first })
        if initials.count >= 3 { result.append(initials) }
        var seen = Set<String>()
        return result.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func tags(_ scan: PageScan, kind: PageKind) -> String {
        ([kind.label.lowercased()] + (scan.author.isEmpty ? [] : [scan.author])).joined(separator: ", ")
    }

    static func note(_ scan: PageScan, kind: PageKind) -> String {
        var lines: [String] = []
        if !scan.author.isEmpty { lines.append("\(kind.label) by \(scan.author)") }
        if !scan.summary.isEmpty { lines.append(String(scan.summary.prefix(200))) }
        return lines.joined(separator: "\n")
    }
}
