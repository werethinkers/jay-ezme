import SwiftUI
import AppKit
import CryptoKit
import UniformTypeIdentifiers

// Database Organizer: the Organizer tab of the Database Organizer app (formerly MyDatabase).
// It looks at every file saved in the database: what is there, what is missing, what is duplicated, what has no tags,
// and it searches names, paths, tags, notes and the words inside PDF and Word documents.

struct OrganizerType: Identifiable {
    var ext: String
    var count: Int
    var size: Int64
    var id: String { ext }
}

struct OrganizerFile: Identifiable {
    var id: String
    var record: DBRecord
    var exists: Bool
    var size: Int64
    var modified: Date?
    var ext: String
    var digest: String
}

enum OrganizerScan {
    static func scan(_ records: [DBRecord]) -> [OrganizerFile] {
        let manager = FileManager.default
        var result: [OrganizerFile] = []
        for record in records {
            let path = record.value
            var exists = false
            var size: Int64 = 0
            var modified: Date? = nil
            if let attributes = try? manager.attributesOfItem(atPath: path) {
                exists = true
                size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                modified = attributes[.modificationDate] as? Date
            }
            var digest = ""
            if exists, size > 0, let handle = FileHandle(forReadingAtPath: path) {
                let data = handle.readData(ofLength: 262_144)
                try? handle.close()
                let hash = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
                digest = "\(size)-\(hash)"
            }
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            result.append(OrganizerFile(id: record.id, record: record, exists: exists, size: size, modified: modified, ext: ext, digest: digest))
        }
        return result
    }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Words found inside documents, kept while the app runs so repeated searches are quick.
final class OrganizerTextCache: @unchecked Sendable {
    static let shared = OrganizerTextCache()
    private let lock = NSLock()
    private var texts: [String: String] = [:]

    func text(for path: String) -> String {
        lock.lock()
        if let hit = texts[path] { lock.unlock(); return hit }
        lock.unlock()
        let value = String(DocText.plain(URL(fileURLWithPath: path)).prefix(400_000)).lowercased()
        lock.lock()
        texts[path] = value
        lock.unlock()
        return value
    }
}

struct DatabaseOrganizerView: View {
    var records: [DBRecord]
    var onOpenViewer: (URL) -> Void
    var onEdit: (DBRecord) -> Void
    @ObservedObject private var store = MyDatabaseStore.shared

    @State private var files: [OrganizerFile] = []
    @State private var sidecars: [String: DocSidecar] = [:]
    @State private var scanning = false
    @State private var query = ""
    @State private var searchInside = true
    @State private var scope = "All files"
    @State private var typeFilter = "All types"
    @State private var sort = "Name"
    @State private var insideHits: [String: String] = [:]
    @State private var searchingInside = false
    @State private var shown = 150

    private let scopes = ["All files", "Missing", "Duplicates", "Large (over 50 MB)", "Not changed in a year", "No tags", "Has notes or highlights"]
    private let sorts = ["Name", "Newest", "Largest", "Type"]

    private var fileRecords: [DBRecord] { records.filter { $0.isFileLike } }

    // MARK: Analysis

    private var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
    private var missing: [OrganizerFile] { files.filter { !$0.exists } }
    private var duplicateGroups: [[OrganizerFile]] {
        Dictionary(grouping: files.filter { !$0.digest.isEmpty }, by: { $0.digest }).values.filter { $0.count > 1 }.map { $0 }
    }
    private var duplicateIDs: Set<String> { Set(duplicateGroups.flatMap { $0.map { $0.id } }) }
    private var untagged: [OrganizerFile] { files.filter { $0.record.tags.trimmingCharacters(in: .whitespaces).isEmpty && (sidecars[$0.record.value]?.tags.isEmpty ?? true) } }
    private var staleCutoff: Date { Date().addingTimeInterval(-365 * 24 * 3600) }
    private var withNotes: [OrganizerFile] {
        files.filter { file in
            guard let side = sidecars[file.record.value] else { return false }
            return !side.marks.isEmpty || !side.general.isEmpty || !side.tags.isEmpty || !side.media.isEmpty
        }
    }

    private var types: [OrganizerType] {
        let groups = Dictionary(grouping: files, by: { $0.ext.isEmpty ? "no extension" : $0.ext })
        return groups.map { OrganizerType(ext: $0.key, count: $0.value.count, size: $0.value.reduce(0) { $0 + $1.size }) }.sorted { $0.count > $1.count }
    }

    private var results: [OrganizerFile] {
        var list = files
        switch scope {
        case "Missing": list = list.filter { !$0.exists }
        case "Duplicates": list = list.filter { duplicateIDs.contains($0.id) }
        case "Large (over 50 MB)": list = list.filter { $0.size > 50_000_000 }
        case "Not changed in a year": list = list.filter { ($0.modified ?? .distantFuture) < staleCutoff }
        case "No tags": list = untagged
        case "Has notes or highlights": list = withNotes
        default: break
        }
        if typeFilter != "All types" { list = list.filter { ($0.ext.isEmpty ? "no extension" : $0.ext) == typeFilter } }
        let words = query.lowercased().split(separator: " ").map(String.init)
        if !words.isEmpty {
            list = list.filter { file in matches(file, words) }
        }
        switch sort {
        case "Newest": list.sort { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        case "Largest": list.sort { $0.size > $1.size }
        case "Type": list.sort { ($0.ext, $0.record.title.lowercased()) < ($1.ext, $1.record.title.lowercased()) }
        default: list.sort { $0.record.title.localizedStandardCompare($1.record.title) == .orderedAscending }
        }
        return list
    }

    /// True when every search word is in the file's name, path, tags, notes or saved document notes, or the file was found by its inside words.
    private func matches(_ file: OrganizerFile, _ words: [String]) -> Bool {
        if insideHits[file.id] != nil { return true }
        var parts: [String] = [file.record.title, file.record.value, file.record.tags, file.record.notes, file.record.collection]
        if let side = sidecars[file.record.value] {
            parts.append(side.tags.joined(separator: " "))
            parts.append(side.general)
            for mark in side.marks {
                parts.append(mark.note)
                parts.append(mark.quote)
            }
        }
        let hay: String = parts.joined(separator: " ").lowercased()
        for word in words where !hay.contains(word) { return false }
        return true
    }

    // MARK: Screen

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            actions
            statCards
            if !files.isEmpty { suggestions; typeBreakdown }
            searchArea
            resultList
        }
        .task(id: fileRecords.count) { await rescan() }
        .task(id: query + (searchInside ? "1" : "0") + String(fileRecords.count)) { await searchInsideDocuments() }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { addFiles(folders: false) } label: { Label("Add files", systemImage: "doc.badge.plus") }.buttonStyle(.borderedProminent).tint(Butter.coral)
            Button { addFiles(folders: true) } label: { Label("Add a folder", systemImage: "folder.badge.plus") }.buttonStyle(.bordered)
            Button { openAnyDocument() } label: { Label("Open a PDF or Word file", systemImage: "doc.richtext") }.buttonStyle(.bordered)
            Button { Task { await rescan() } } label: { Label("Check again", systemImage: "arrow.clockwise") }.buttonStyle(.bordered)
            if scanning { ProgressView().controlSize(.small) }
            Spacer()
        }
    }

    private var statCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            card("Files saved", "\(files.count)", "doc.on.doc.fill", Butter.coral) { scope = "All files" }
            card("Total size", OrganizerScan.sizeText(totalSize), "internaldrive.fill", .blue) { sort = "Largest" }
            card("Missing", "\(missing.count)", "exclamationmark.triangle.fill", .orange) { scope = "Missing" }
            card("Duplicates", "\(duplicateIDs.count)", "square.on.square", .purple) { scope = "Duplicates" }
            card("No tags", "\(untagged.count)", "tag.slash", .gray) { scope = "No tags" }
            card("With notes", "\(withNotes.count)", "note.text", .green) { scope = "Has notes or highlights" }
        }
    }

    private func card(_ title: String, _ value: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.title3).foregroundStyle(color).frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Butter.cocoa)
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Butter.cream, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Butter.honey, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What you can do").font(.headline)
            if !missing.isEmpty {
                suggestion("\(missing.count) saved file\(missing.count == 1 ? " is" : "s are") no longer where they were saved. They may have been moved or renamed.",
                           button: "Remove these links") {
                    store.remove(ids: Set(missing.map { $0.id }))
                }
            }
            if !duplicateGroups.isEmpty {
                suggestion("\(duplicateGroups.count) set\(duplicateGroups.count == 1 ? "" : "s") of files look identical (same size and start). Review them and keep one.",
                           button: "Show duplicates") { scope = "Duplicates" }
            }
            if !untagged.isEmpty {
                suggestion("\(untagged.count) file\(untagged.count == 1 ? " has" : "s have") no tags, so they are harder to find.",
                           button: "Tag them by file type") { tagByType() }
            }
            let big = files.filter { $0.size > 50_000_000 }
            if !big.isEmpty {
                suggestion("\(big.count) file\(big.count == 1 ? " is" : "s are") over 50 MB, \(OrganizerScan.sizeText(big.reduce(0) { $0 + $1.size })) in all.", button: "Show large files") { scope = "Large (over 50 MB)" }
            }
            let stale = files.filter { ($0.modified ?? .distantFuture) < staleCutoff }
            if !stale.isEmpty {
                suggestion("\(stale.count) file\(stale.count == 1 ? " has" : "s have") not changed in over a year. Archive what you no longer need.", button: "Show them") { scope = "Not changed in a year" }
            }
            if missing.isEmpty && duplicateGroups.isEmpty && untagged.isEmpty && big.isEmpty && stale.isEmpty {
                Text("Everything is in order: no missing, duplicate, untagged, very large or stale files.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Butter.butter.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func suggestion(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "lightbulb.fill").foregroundStyle(Butter.coral)
            Text(text).font(.callout)
            Spacer(minLength: 8)
            Button(button, action: action).buttonStyle(.bordered).controlSize(.small)
        }
    }

    private var typeBreakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("By file type").font(.headline)
            let top = Array(types.prefix(8))
            let biggest = Double(top.first?.count ?? 1)
            ForEach(top) { item in
                Button { typeFilter = item.ext } label: {
                    HStack(spacing: 10) {
                        Text(item.ext.uppercased()).font(.system(size: 11, weight: .bold)).frame(width: 90, alignment: .leading)
                        ProgressView(value: Double(item.count), total: max(biggest, 1)).tint(Butter.coral)
                        Text("\(item.count) · \(OrganizerScan.sizeText(item.size))").font(.caption).foregroundStyle(.secondary).frame(width: 130, alignment: .trailing)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var searchArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            MerlinBar(text: $query, placeholder: "Search files, tags, notes and the words inside PDF and Word documents…", showsBadge: false)
            HStack(spacing: 10) {
                Toggle("Search inside documents", isOn: $searchInside).toggleStyle(.switch).controlSize(.small)
                if searchingInside { ProgressView().controlSize(.small); Text("Reading documents…").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Picker("", selection: $scope) { ForEach(scopes, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 190)
                Picker("", selection: $typeFilter) {
                    Text("All types").tag("All types")
                    ForEach(types.map { $0.ext }, id: \.self) { Text($0.uppercased()).tag($0) }
                }
                .labelsHidden().frame(width: 130)
                Picker("", selection: $sort) { ForEach(sorts, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 110)
            }
        }
    }

    private var resultList: some View {
        let list = results
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(list.count) file\(list.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            if files.isEmpty && !scanning {
                Text("No files saved yet. Press Add files or Add a folder to start organizing.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
            }
            LazyVStack(spacing: 6) {
                ForEach(list.prefix(shown)) { file in row(file) }
            }
            if list.count > shown {
                Button("Show more (\(list.count - shown) left)") { shown += 150 }.buttonStyle(.bordered)
            }
        }
    }

    private func row(_ file: OrganizerFile) -> some View {
        let side = sidecars[file.record.value]
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(file.ext)).font(.title3).foregroundStyle(file.exists ? Butter.coral : .orange).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.record.title.isEmpty ? URL(fileURLWithPath: file.record.value).lastPathComponent : file.record.title)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(file.record.value).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 8) {
                    if file.exists {
                        Text(OrganizerScan.sizeText(file.size)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        if let date = file.modified { Text(date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10.5)).foregroundStyle(.secondary) }
                    } else {
                        Text("Not found").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.orange)
                    }
                    if duplicateIDs.contains(file.id) { Text("Duplicate").font(.system(size: 10, weight: .bold)).foregroundStyle(.purple) }
                    let tags = [file.record.tags] + (side?.tags ?? [])
                    let tagText = tags.filter { !$0.isEmpty }.joined(separator: ", ")
                    if !tagText.isEmpty { Label(tagText, systemImage: "tag.fill").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1) }
                    if let side, !side.marks.isEmpty { Label("\(side.marks.count)", systemImage: "highlighter").font(.system(size: 10.5)).foregroundStyle(.secondary) }
                }
                if let snippet = insideHits[file.id] {
                    Text("…" + snippet + "…").font(.system(size: 11)).foregroundStyle(Butter.cocoa).lineLimit(2)
                        .padding(6).background(Butter.honey.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                if DocText.isViewable(file.record.value) {
                    iconButton("doc.richtext", "Open in the KeyDo Document Viewer") { onOpenViewer(URL(fileURLWithPath: file.record.value)) }.disabled(!file.exists)
                }
                iconButton("arrow.up.forward.app", "Open with its app") { NSWorkspace.shared.open(URL(fileURLWithPath: file.record.value)) }.disabled(!file.exists)
                iconButton("folder", "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.record.value)]) }.disabled(!file.exists)
                iconButton("pencil", "Edit name, tags, notes, collection") { onEdit(file.record) }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Butter.honey.opacity(0.6), lineWidth: 1))
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 26, height: 24) }.buttonStyle(.bordered).controlSize(.small).help(help)
    }

    private func icon(_ ext: String) -> String {
        switch ext {
        case "pdf": return "doc.richtext.fill"
        case "doc", "docx", "rtf", "txt", "md", "pages": return "doc.text.fill"
        case "xls", "xlsx", "csv", "numbers": return "tablecells.fill"
        case "ppt", "pptx", "key": return "rectangle.on.rectangle.angled.fill"
        case "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff": return "photo.fill"
        case "mp4", "mov", "m4v", "avi", "mkv": return "film.fill"
        case "mp3", "wav", "m4a", "aac": return "waveform"
        case "zip", "rar", "7z": return "archivebox.fill"
        default: return "doc.fill"
        }
    }

    // MARK: Work

    private func rescan() async {
        scanning = true
        let list = fileRecords
        let scanned = await Task.detached(priority: .utility) { OrganizerScan.scan(list) }.value
        let notes = await Task.detached(priority: .utility) { DocStore.all() }.value
        files = scanned
        var byPath: [String: DocSidecar] = [:]
        for item in notes { byPath[item.path] = item }
        sidecars = byPath
        scanning = false
    }

    /// Looks for the search words inside PDF and Word files, and shows the words around the first match.
    private func searchInsideDocuments() async {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard searchInside, !words.isEmpty, query.count >= 2 else { insideHits = [:]; searchingInside = false; return }
        try? await Task.sleep(nanoseconds: 450_000_000)
        if Task.isCancelled { return }
        searchingInside = true
        let candidates = files.filter { $0.exists && DocText.isViewable($0.record.value) }.prefix(400).map { ($0.id, $0.record.value) }
        let found = await Task.detached(priority: .utility) { () -> [String: String] in
            var hits: [String: String] = [:]
            for (id, path) in candidates {
                if Task.isCancelled { break }
                let text = OrganizerTextCache.shared.text(for: path)
                guard words.allSatisfy({ text.contains($0) }), let first = words.first, let range = text.range(of: first) else { continue }
                let start = text.index(range.lowerBound, offsetBy: -50, limitedBy: text.startIndex) ?? text.startIndex
                let end = text.index(range.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
                hits[id] = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
            }
            return hits
        }.value
        if Task.isCancelled { return }
        insideHits = found
        searchingInside = false
    }

    private func tagByType() {
        for file in untagged {
            guard let index = store.records.firstIndex(where: { $0.id == file.id }) else { continue }
            store.records[index].tags = file.ext.isEmpty ? "file" : file.ext
        }
        store.save()
        store.message = "Tagged \(untagged.count) file(s) by their type."
        Task { await rescan() }
    }

    private func addFiles(folders: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = !folders
        panel.canChooseDirectories = folders
        panel.message = folders ? "Choose a folder. Every file inside it is added to your database. The files stay where they are." : "Choose files to add to your database. The files stay where they are."
        guard panel.runModal() == .OK else { return }
        var urls: [URL] = []
        for url in panel.urls {
            if folders {
                let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let next = walker?.nextObject() as? URL {
                    if (try? next.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { urls.append(next) }
                    if urls.count >= 3000 { break }
                }
            } else {
                urls.append(url)
            }
        }
        let known = Set(store.records.map { $0.value })
        let media: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "mp4", "mov", "m4v", "mp3", "wav", "m4a"]
        var added = 0
        for url in urls where !known.contains(url.path) {
            let ext = url.pathExtension.lowercased()
            store.records.insert(DBRecord(kind: media.contains(ext) ? "media" : "file", title: url.deletingPathExtension().lastPathComponent, value: url.path, tags: ext, collection: "General"), at: 0)
            added += 1
        }
        store.save()
        store.message = added == 0 ? "Those files are already in your database." : "Added \(added) file\(added == 1 ? "" : "s"). They stay where they are on your Mac."
        Task { await rescan() }
    }

    private func openAnyDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        var allowed: [UTType] = [UTType.pdf, UTType.rtf]
        if let docx = UTType(filenameExtension: "docx") { allowed.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { allowed.append(doc) }
        panel.allowedContentTypes = allowed
        panel.message = "Choose a PDF or Word document to read in the KeyDo Document Viewer."
        if panel.runModal() == .OK, let url = panel.url { onOpenViewer(url) }
    }
}
