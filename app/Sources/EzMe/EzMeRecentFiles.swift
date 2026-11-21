import SwiftUI
import AppKit

/// Files you opened, on this Mac and in the KeyDo browser (Google Sheets, Docs, Slides, Drive, Word and Excel online),
/// kept in one list so each can be tagged with what it is for, and found again by searching.
struct RecentFile: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var kind: String            // "mac" or "web"
    var location: String        // file path or page address
    var title: String
    var source: String          // "PDF", "Google Sheet", ...
    var firstSeen = Date()
    var lastOpened = Date()
    var tags: [String] = []
    var purpose = ""
}

@MainActor final class RecentFileStore: ObservableObject {
    static let shared = RecentFileStore()
    @Published private(set) var items: [RecentFile] = []
    @Published var message = ""
    @Published var scanning = false

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("KeyDo", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("RecentFiles.json")
    }

    init() {
        if let data = try? Data(contentsOf: fileURL), let list = try? JSONDecoder().decode([RecentFile].self, from: data) { items = list }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: fileURL, options: .atomic) }
    }

    // MARK: Pages opened in the KeyDo browser

    /// Google Sheets, Docs, Slides, Drive files and Word, Excel and PowerPoint online.
    static func classify(_ url: URL) -> (source: String, key: String)? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path
        let key = (url.scheme ?? "https") + "://" + host + path
        if host == "docs.google.com" {
            if path.hasPrefix("/spreadsheets/d/") { return ("Google Sheet", key) }
            if path.hasPrefix("/document/d/") { return ("Google Doc", key) }
            if path.hasPrefix("/presentation/d/") { return ("Google Slides", key) }
            if path.hasPrefix("/forms/d/") { return ("Google Form", key) }
        }
        if host == "drive.google.com", path.contains("/file/d/") { return ("Drive file", key) }
        let lower = url.absoluteString.lowercased()
        if host.hasSuffix("sharepoint.com") || host == "onedrive.live.com" || host.hasSuffix("office.com") || host.hasSuffix("officeapps.live.com") {
            if lower.contains(".xlsx") || lower.contains("/:x:/") { return ("Excel online", key + "?" + (url.query ?? "")) }
            if lower.contains(".docx") || lower.contains("/:w:/") { return ("Word online", key + "?" + (url.query ?? "")) }
            if lower.contains(".pptx") || lower.contains("/:p:/") { return ("PowerPoint online", key + "?" + (url.query ?? "")) }
        }
        return nil
    }

    func noteWeb(title: String, address: String) {
        guard let url = URL(string: address), let found = Self.classify(url) else { return }
        let cleaned = title.replacingOccurrences(of: " - Google Sheets", with: "").replacingOccurrences(of: " - Google Docs", with: "")
            .replacingOccurrences(of: " - Google Slides", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleaned.isEmpty ? found.source : cleaned
        if let index = items.firstIndex(where: { $0.kind == "web" && $0.location.hasPrefix(found.key) }) {
            items[index].lastOpened = Date()
            if !cleaned.isEmpty { items[index].title = name }
        } else {
            var item = RecentFile(kind: "web", location: address, title: name, source: found.source)
            item.tags = [found.source]
            items.append(item)
        }
        save()
    }

    // MARK: Files opened on this Mac

    private static let documentTypes: Set<String> = ["pdf", "doc", "docx", "xls", "xlsx", "csv", "ppt", "pptx", "txt", "md", "rtf", "pages", "numbers", "key",
                                                    "png", "jpg", "jpeg", "heic", "mov", "mp4", "m4a", "mp3", "zip"]

    private static func sourceName(_ ext: String) -> String {
        switch ext {
        case "pdf": return "PDF"
        case "doc", "docx", "pages", "rtf", "txt", "md": return "Document"
        case "xls", "xlsx", "csv", "numbers": return "Spreadsheet"
        case "ppt", "pptx", "key": return "Presentation"
        case "png", "jpg", "jpeg", "heic": return "Image"
        case "mov", "mp4": return "Video"
        case "m4a", "mp3": return "Audio"
        default: return "File"
        }
    }

    /// Looks for files you used in the last few days, using Spotlight's own "last used" record.
    func scanMac(days: Int) {
        guard !scanning else { return }
        scanning = true
        message = "Looking for files you opened in the last \(days) day\(days == 1 ? "" : "s")\u{2026}"
        let home = NSHomeDirectory()
        Task.detached(priority: .utility) {
            var found: [(String, Date)] = []
            // Files opened lately anywhere in the home folder, and files that arrived in Downloads (even if never opened).
            let searches: [[String]] = [
                ["-onlyin", home, "kMDItemLastUsedDate >= $time.today(-\(days))"],
                ["-onlyin", home + "/Downloads", "kMDItemDateAdded >= $time.today(-\(days))"]
            ]
            for arguments in searches {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
                for path in lines where !path.contains("/Library/") && !path.contains("/.") && !path.contains(".app/") {
                    let url = URL(fileURLWithPath: path)
                    guard Self.documentTypes.contains(url.pathExtension.lowercased()) else { continue }
                    let values = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey, .isDirectoryKey])
                    if values?.isDirectory == true { continue }
                    found.append((path, values?.contentAccessDate ?? values?.contentModificationDate ?? Date()))
                    if found.count >= 400 { break }
                }
            }
            }
            let result = found
            await MainActor.run { RecentFileStore.shared.merge(result) }
        }
    }

    private func merge(_ found: [(String, Date)]) {
        var added = 0
        for (path, date) in found {
            if let index = items.firstIndex(where: { $0.kind == "mac" && $0.location == path }) {
                if date > items[index].lastOpened { items[index].lastOpened = date }
            } else {
                let url = URL(fileURLWithPath: path)
                var item = RecentFile(kind: "mac", location: path, title: url.lastPathComponent, source: Self.sourceName(url.pathExtension.lowercased()))
                item.lastOpened = date
                item.firstSeen = date
                items.append(item)
                added += 1
            }
        }
        save()
        scanning = false
        message = added == 0 ? "No new files found." : "Added \(added) file\(added == 1 ? "" : "s") you opened on this Mac."
    }

    // MARK: Tags

    func setTags(_ id: String, _ tags: [String]) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].tags = tags
        save()
    }

    func setPurpose(_ id: String, _ text: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].purpose = text
        save()
    }

    func remove(_ id: String) { items.removeAll { $0.id == id }; save() }

    private static let keywordTags: [(String, [String])] = [
        ("Finance", ["invoice", "bill", "gst", "tax", "receipt", "payment", "bank", "statement", "budget", "salary"]),
        ("Legal", ["contract", "agreement", "nda", "terms", "policy", "legal"]),
        ("Sales", ["proposal", "quote", "quotation", "pitch", "lead", "client", "order"]),
        ("HR", ["resume", "cv", "offer", "leave", "attendance", "payroll", "interview"]),
        ("Marketing", ["campaign", "brand", "logo", "social", "poster", "design"]),
        ("Operations", ["inventory", "stock", "dispatch", "plan", "report", "tracker", "schedule"]),
        ("Personal", ["ticket", "passport", "family", "trip", "travel"])
    ]

    /// Adds a first guess to files that have no tag yet, from the kind of file and words in its name.
    func autoTag() {
        var changed = 0
        for index in items.indices {
            var tags = items[index].tags
            let name = items[index].title.lowercased()
            if !tags.contains(items[index].source) { tags.append(items[index].source) }
            for (tag, words) in Self.keywordTags where words.contains(where: { name.contains($0) }) && !tags.contains(tag) { tags.append(tag) }
            if items[index].kind == "mac" {
                let folder = URL(fileURLWithPath: items[index].location).deletingLastPathComponent().lastPathComponent
                if !["Downloads", "Desktop", "Documents", NSUserName()].contains(folder), !folder.isEmpty, !tags.contains(folder) { tags.append(folder) }
            }
            if tags != items[index].tags { items[index].tags = tags; changed += 1 }
        }
        save()
        message = changed == 0 ? "Every file already has its tags." : "Added tags to \(changed) file\(changed == 1 ? "" : "s"). Change them as you like."
    }

    var allTags: [String] {
        Array(Set(items.flatMap { $0.tags })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

struct RecentFilesView: View {
    @ObservedObject private var store = RecentFileStore.shared
    @AppStorage("recentFilesPurposeReviewDay") private var reviewedDay = ""
    @State private var search = ""
    @State private var tagFilter = "All"
    @State private var days = 7
    @State private var editing: String?
    @State private var newTag = ""

    private static let dayKey: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
    private static let dayTitle: DateFormatter = { let f = DateFormatter(); f.dateStyle = .full; return f }()
    private static let suggested = ["Work", "Client", "Finance", "Personal", "Project", "Reference", "To do", "Done"]

    private var today: [RecentFile] { store.items.filter { Calendar.current.isDateInToday($0.lastOpened) } }
    private var needsPurpose: [RecentFile] { today.filter { $0.purpose.trimmingCharacters(in: .whitespaces).isEmpty } }

    private var shown: [RecentFile] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.items.filter { item in
            if tagFilter == "Untagged" && !item.tags.isEmpty { return false }
            if tagFilter != "All" && tagFilter != "Untagged" && !item.tags.contains(tagFilter) { return false }
            if q.isEmpty { return true }
            return item.title.localizedCaseInsensitiveContains(q) || item.location.localizedCaseInsensitiveContains(q)
                || item.purpose.localizedCaseInsensitiveContains(q) || item.tags.contains { $0.localizedCaseInsensitiveContains(q) }
        }.sorted { $0.lastOpened > $1.lastOpened }
    }

    private var grouped: [(String, [RecentFile])] {
        var order: [String] = []
        var map: [String: [RecentFile]] = [:]
        for item in shown {
            let key = Self.dayKey.string(from: item.lastOpened)
            if map[key] == nil { order.append(key); map[key] = [] }
            map[key]?.append(item)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            dailyTask
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search by name, tag, purpose or place", text: $search).textFieldStyle(.roundedBorder)
                Picker("", selection: $days) { Text("1 day").tag(1); Text("3 days").tag(3); Text("7 days").tag(7); Text("30 days").tag(30) }.frame(width: 100).labelsHidden()
                Button { store.scanMac(days: days) } label: { Label(store.scanning ? "Looking\u{2026}" : "Find files from this Mac", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent).tint(Butter.coral).disabled(store.scanning)
                Button { store.autoTag() } label: { Label("Auto-tag", systemImage: "tag") }.buttonStyle(.bordered)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["All", "Untagged"] + store.allTags, id: \.self) { tag in
                        Button { tagFilter = tag } label: {
                            Text(tag).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                                .background(tagFilter == tag ? Butter.coral.opacity(0.25) : Color.secondary.opacity(0.12), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            if !store.message.isEmpty { Text(store.message).font(.caption).foregroundStyle(.secondary) }
            if grouped.isEmpty {
                ContentUnavailableView("No files yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Press \u{201C}Find files from this Mac\u{201D}. Google Sheets, Docs, Slides and Word or Excel online that you open in the KeyDo browser appear here by themselves."))
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                ForEach(grouped, id: \.0) { day, files in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Self.dayKey.date(from: day).map { Self.dayTitle.string(from: $0) } ?? day).font(.headline)
                        ForEach(files) { file in row(file) }
                    }
                }
            }
        }
    }

    private var dailyTask: some View {
        let done = reviewedDay == Self.dayKey.string(from: Date())
        let left = needsPurpose.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: left == 0 && !today.isEmpty ? "checkmark.circle.fill" : "checklist").foregroundStyle(Butter.coral)
                Text("Today's task: organize your files").font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                if done { Text("Marked done for today").font(.caption).foregroundStyle(.secondary) }
                else { Button("Mark today done") { reviewedDay = Self.dayKey.string(from: Date()) }.buttonStyle(.bordered) }
            }
            if today.isEmpty {
                Text("No files opened today yet. Find files from this Mac, or open a Google Sheet or Doc in the browser.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text(left == 0 ? "All \(today.count) files opened today have a purpose. Nice." : "\(left) of \(today.count) files opened today still need a purpose. Say what each is for, so it is easy to find later.")
                    .font(.callout).foregroundStyle(.secondary)
                ProgressView(value: Double(today.count - left), total: Double(max(1, today.count))).tint(Butter.coral)
            }
        }
        .padding(14).background(Butter.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ file: RecentFile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: file.kind == "web" ? "globe" : "doc").foregroundStyle(Butter.coral)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text(file.kind == "web" ? file.source : (file.location as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Open") { open(file) }.buttonStyle(.bordered).controlSize(.small)
                Button { editing = editing == file.id ? nil : file.id } label: { Image(systemName: "tag") }.buttonStyle(.bordered).controlSize(.small)
                Button { store.remove(file.id) } label: { Image(systemName: "xmark") }.buttonStyle(.bordered).controlSize(.small).help("Remove from this list")
            }
            if !file.tags.isEmpty || !file.purpose.isEmpty {
                HStack(spacing: 5) {
                    ForEach(file.tags, id: \.self) { tag in Text(tag).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3).background(Butter.coral.opacity(0.15), in: Capsule()) }
                    if !file.purpose.isEmpty { Text("For: \(file.purpose)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if editing == file.id {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("What is this file for? (for example: GST filing for Izzhaar)", text: Binding(get: { file.purpose }, set: { store.setPurpose(file.id, $0) })).textFieldStyle(.roundedBorder)
                    HStack(spacing: 5) {
                        ForEach(Self.suggested, id: \.self) { tag in
                            let on = file.tags.contains(tag)
                            Button { store.setTags(file.id, on ? file.tags.filter { $0 != tag } : file.tags + [tag]) } label: {
                                Text(tag).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(on ? Butter.coral.opacity(0.3) : Color.secondary.opacity(0.12), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                        TextField("New tag", text: $newTag).textFieldStyle(.roundedBorder).frame(width: 110)
                            .onSubmit {
                                let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !tag.isEmpty, !file.tags.contains(tag) { store.setTags(file.id, file.tags + [tag]) }
                                newTag = ""
                            }
                    }
                }
            }
        }
        .padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
    }

    private func open(_ file: RecentFile) {
        if file.kind == "web" {
            NotificationCenter.default.post(name: .ezmeOpenSite, object: nil, userInfo: ["url": file.location])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: file.location))
        }
    }
}
