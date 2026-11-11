import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MyDatabase: a built-in app (like Collection Builder) where people keep their own data in one place:
// contacts, URLs and links, direct links to local files, tables from CSV files, and a view of their shortcuts.
// File Renamer lives here too, so renamed files keep their saved links.

// MARK: - Model

struct DBRecord: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    /// "contact", "link" or "file"
    var kind: String
    var title: String
    /// Mobile number for a contact, web address for a link, full path for a file.
    var value: String
    var email = ""
    var company = ""
    var address = ""
    var tags = ""
    var collection = "General"
    var notes = ""
    var created = Date()
}

struct DBTable: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var name: String
    var headers: [String]
    var rows: [[String]]
    var collection = "General"
}

@MainActor final class MyDatabaseStore: ObservableObject {
    static let shared = MyDatabaseStore()
    @Published var records: [DBRecord] = []
    @Published var tables: [DBTable] = []
    @Published var message = ""

    private struct Payload: Codable { var records: [DBRecord]; var tables: [DBTable] }

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiniJ", isDirectory: true).appendingPathComponent("MyDatabase", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("mydatabase.json")
    }

    init() {
        load()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL), let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        records = payload.records
        tables = payload.tables
    }

    func save() {
        guard let data = try? JSONEncoder().encode(Payload(records: records, tables: tables)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    var collections: [String] {
        var names = Set(records.map { $0.collection })
        for table in tables { names.insert(table.collection) }
        names.insert("General")
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func upsert(_ record: DBRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record } else { records.insert(record, at: 0) }
        save()
    }

    func remove(ids: Set<String>) {
        records.removeAll { ids.contains($0.id) }
        save()
    }

    func move(ids: Set<String>, to collection: String) {
        for index in records.indices where ids.contains(records[index].id) { records[index].collection = collection }
        save()
    }

    /// Adds contacts, skipping ones already saved (same mobile or email).
    @discardableResult func addContacts(_ contacts: [EzContact], collection: String) -> Int {
        var added = 0
        for contact in contacts {
            let name = contact.displayName
            guard !name.isEmpty else { continue }
            let mobile = contact.mobile.isEmpty ? (contact.phones.first ?? "") : contact.mobile
            let duplicate = records.contains { $0.kind == "contact" && ((!mobile.isEmpty && $0.value == mobile) || (!contact.email.isEmpty && $0.email.caseInsensitiveCompare(contact.email) == .orderedSame)) }
            if duplicate { continue }
            records.insert(DBRecord(kind: "contact", title: name, value: mobile, email: contact.email, company: contact.company, address: contact.address, collection: collection), at: 0)
            added += 1
        }
        save()
        return added
    }

    @discardableResult func addLinks(_ items: [(title: String, url: String)], collection: String) -> Int {
        var added = 0
        for item in items {
            var url = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { continue }
            if !url.contains("://") { url = "https://" + url }
            if records.contains(where: { $0.kind == "link" && $0.value.caseInsensitiveCompare(url) == .orderedSame }) { continue }
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            records.insert(DBRecord(kind: "link", title: title.isEmpty ? (URL(string: url)?.host ?? url) : title, value: url, collection: collection), at: 0)
            added += 1
        }
        save()
        return added
    }

    @discardableResult func addFiles(_ urls: [URL], collection: String) -> Int {
        var added = 0
        for url in urls {
            let path = url.standardizedFileURL.path
            if records.contains(where: { $0.kind == "file" && $0.value == path }) { continue }
            records.insert(DBRecord(kind: "file", title: url.lastPathComponent, value: path, collection: collection), at: 0)
            added += 1
        }
        save()
        return added
    }

    /// File Renamer calls this so saved links follow the new names.
    func filesRenamed(_ pairs: [(from: URL, to: URL)]) {
        var changed = false
        for pair in pairs {
            let old = pair.from.standardizedFileURL.path
            for index in records.indices where records[index].kind == "file" && records[index].value == old {
                records[index].value = pair.to.standardizedFileURL.path
                records[index].title = pair.to.lastPathComponent
                changed = true
            }
        }
        if changed { save() }
    }

    func addTable(_ table: DBTable) { tables.insert(table, at: 0); save() }

    func removeTable(_ id: String) { tables.removeAll { $0.id == id }; save() }

    func renameTable(_ id: String, to name: String) {
        if let index = tables.firstIndex(where: { $0.id == id }) { tables[index].name = name; save() }
    }

    func setCell(table id: String, row: Int, column: Int, value: String) {
        guard let t = tables.firstIndex(where: { $0.id == id }), row < tables[t].rows.count else { return }
        while tables[t].rows[row].count <= column { tables[t].rows[row].append("") }
        tables[t].rows[row][column] = value
    }

    func addRow(table id: String) {
        if let t = tables.firstIndex(where: { $0.id == id }) { tables[t].rows.append(Array(repeating: "", count: tables[t].headers.count)); save() }
    }

    func removeRow(table id: String, row: Int) {
        if let t = tables.firstIndex(where: { $0.id == id }), row < tables[t].rows.count { tables[t].rows.remove(at: row); save() }
    }

    func addColumn(table id: String, name: String) {
        guard let t = tables.firstIndex(where: { $0.id == id }) else { return }
        tables[t].headers.append(name)
        for row in tables[t].rows.indices { tables[t].rows[row].append("") }
        save()
    }

    func csv(for table: DBTable) -> String {
        func cell(_ value: String) -> String {
            value.contains(",") || value.contains("\"") || value.contains("\n") ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
        }
        let lines = [table.headers.map(cell).joined(separator: ",")] + table.rows.map { row in
            (0..<table.headers.count).map { cell($0 < row.count ? row[$0] : "") }.joined(separator: ",")
        }
        return lines.joined(separator: "\n")
    }

    func csv(for kind: String, records list: [DBRecord]) -> String {
        let headers = ["Name", kind == "contact" ? "Mobile" : kind == "link" ? "URL" : "Path", "Email", "Company", "Address", "Tags", "Collection", "Notes"]
        let table = DBTable(name: kind, headers: headers, rows: list.map { [$0.title, $0.value, $0.email, $0.company, $0.address, $0.tags, $0.collection, $0.notes] })
        return csv(for: table)
    }
}

// MARK: - Main view

struct MyDatabaseView: View {
    var clips: [Clip]
    var onOpenShortcuts: (String) -> Void = { _ in }
    @ObservedObject private var store = MyDatabaseStore.shared
    @State private var tab = "Contacts"
    @State private var search = ""
    @State private var collectionFilter = "All collections"
    @State private var selection = Set<String>()
    @State private var editing: DBRecord?
    @State private var showPasteLinks = false
    @State private var pasteText = ""
    @State private var openTableID: String?
    @State private var newColumnName = ""
    @State private var page = 0
    @State private var shortcutSearch = ""
    @State private var newCollectionName = ""
    @State private var showNewCollection = false

    private let tabs: [(String, String)] = [
        ("Contacts", "person.crop.circle"), ("Links", "link"), ("Files", "doc.on.doc"),
        ("Tables", "tablecells"), ("Shortcuts", "bolt.fill"), ("File Renamer", "doc.badge.gearshape")
    ]

    private var kind: String { tab == "Contacts" ? "contact" : tab == "Links" ? "link" : "file" }
    private var isRecordTab: Bool { ["Contacts", "Links", "Files"].contains(tab) }

    private var visible: [DBRecord] {
        store.records.filter { record in
            record.kind == kind
                && (collectionFilter == "All collections" || record.collection == collectionFilter)
                && (search.trimmingCharacters(in: .whitespaces).isEmpty
                    || [record.title, record.value, record.email, record.company, record.address, record.tags, record.notes, record.collection]
                        .contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    tabBar
                    if isRecordTab { toolbar; recordList }
                    else if tab == "Tables" { tablesView }
                    else if tab == "Shortcuts" { shortcutsView }
                    else { fileRenamerView }
                    if !store.message.isEmpty {
                        Text(store.message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: 1400, alignment: .leading)
            }
        }
        .sheet(item: $editing) { record in
            DBRecordEditor(record: record, collections: store.collections) { saved in store.upsert(saved); editing = nil } onCancel: { editing = nil }
        }
        .sheet(isPresented: $showPasteLinks) { pasteLinksSheet }
        .alert("New collection", isPresented: $showNewCollection) {
            TextField("Collection name", text: $newCollectionName)
            Button("Cancel", role: .cancel) {}
            Button("Create and move") {
                let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { store.move(ids: selection, to: name); selection = [] }
            }
        } message: { Text("Selected items move into this collection.") }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard tab == "Files" else { return false }
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { _ = store.addFiles([url], collection: currentCollection) } }
                }
            }
            return true
        }
    }

    private var currentCollection: String { collectionFilter == "All collections" ? "General" : collectionFilter }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "externaldrive.fill.badge.person.crop")
                .font(.system(size: 24)).foregroundStyle(.white).frame(width: 48, height: 48)
                .background(LinearGradient(colors: [Butter.cocoa, Butter.coral], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text("MyDatabase").font(.system(size: 23, weight: .bold, design: .rounded))
                Text("Your contacts, links, files, tables and shortcuts in one place. Organize, edit and search them.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(store.records.count) saved · \(store.tables.count) tables").font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.0) { item in
                    Button {
                        tab = item.0; selection = []; search = ""; openTableID = nil; page = 0
                    } label: {
                        Label(item.0, systemImage: item.1)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundStyle(tab == item.0 ? Butter.cream : Butter.cocoa)
                            .background(tab == item.0 ? Butter.cocoa : Butter.cream, in: Capsule())
                            .overlay(Capsule().stroke(Butter.honey, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Contacts, links, files

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                MerlinBar(text: $search, placeholder: "Search \(tab.lowercased())…", showsBadge: false)
                Picker("", selection: $collectionFilter) {
                    Text("All collections").tag("All collections")
                    ForEach(store.collections, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 190)
            }
            HStack(spacing: 8) {
                Button { editing = DBRecord(kind: kind, title: "", value: "", collection: currentCollection) } label: { Label("Add", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(Butter.coral)
                if tab == "Contacts" { Button { importContacts() } label: { Label("Import VCF or CSV", systemImage: "square.and.arrow.down") }.buttonStyle(.bordered) }
                if tab == "Links" {
                    Button { pasteText = ""; showPasteLinks = true } label: { Label("Paste links", systemImage: "doc.on.clipboard") }.buttonStyle(.bordered)
                    Button { importLinksCSV() } label: { Label("Import CSV", systemImage: "square.and.arrow.down") }.buttonStyle(.bordered)
                }
                if tab == "Files" {
                    Button { chooseFiles() } label: { Label("Add files", systemImage: "doc.badge.plus") }.buttonStyle(.bordered)
                    Button { checkFiles() } label: { Label("Check links", systemImage: "checkmark.seal") }.buttonStyle(.bordered)
                }
                Button { exportCSV() } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered).disabled(visible.isEmpty)
                Spacer()
                if !selection.isEmpty {
                    Text("\(selection.count) selected").font(.caption).foregroundStyle(.secondary)
                    Menu {
                        ForEach(store.collections, id: \.self) { name in Button(name) { store.move(ids: selection, to: name); selection = [] } }
                        Divider()
                        Button("New collection…") { newCollectionName = ""; showNewCollection = true }
                    } label: { Label("Move to", systemImage: "folder") }
                    Button(role: .destructive) { store.remove(ids: selection); selection = [] } label: { Label("Delete", systemImage: "trash") }
                }
            }
            if tab == "Files" { Text("Drop files here to save a direct link to them. The file stays where it is.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var recordList: some View {
        VStack(spacing: 0) {
            if visible.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: tabs.first { $0.0 == tab }?.1 ?? "tray", description: Text(emptyHint))
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                HStack {
                    Toggle("", isOn: Binding(get: { !visible.isEmpty && visible.allSatisfy { selection.contains($0.id) } },
                                             set: { on in if on { selection.formUnion(visible.map { $0.id }) } else { selection.subtract(visible.map { $0.id }) } }))
                        .toggleStyle(.checkbox).labelsHidden()
                    Text("\(visible.count) \(tab.lowercased())").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                Divider()
                LazyVStack(spacing: 0) {
                    ForEach(visible.prefix(400)) { record in
                        recordRow(record)
                        Divider()
                    }
                }
                if visible.count > 400 { Text("Showing the first 400. Use search to narrow the list.").font(.caption).foregroundStyle(.secondary).padding(8) }
            }
        }
        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Butter.honey, lineWidth: 1))
    }

    private var emptyTitle: String { "No \(tab.lowercased()) yet" }
    private var emptyHint: String {
        switch tab {
        case "Contacts": return "Add a contact or import a VCF or CSV file from Google Contacts, Zoho or your phone."
        case "Links": return "Add a link, paste a list of links, or import a CSV."
        default: return "Add files or drop them here to keep direct links to them."
        }
    }

    private func recordRow(_ record: DBRecord) -> some View {
        let missing = record.kind == "file" && !FileManager.default.fileExists(atPath: record.value)
        return HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(get: { selection.contains(record.id) }, set: { on in if on { selection.insert(record.id) } else { selection.remove(record.id) } }))
                .toggleStyle(.checkbox).labelsHidden().padding(.top, 2)
            Image(systemName: record.kind == "contact" ? "person.crop.circle" : record.kind == "link" ? "link" : (missing ? "exclamationmark.triangle.fill" : "doc"))
                .foregroundStyle(missing ? Color.orange : Butter.coral).frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title.isEmpty ? "Untitled" : record.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(record.value).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if record.kind == "contact" {
                    let extra = [record.email, record.company, record.address].filter { !$0.isEmpty }.joined(separator: "  ·  ")
                    if !extra.isEmpty { Text(extra).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                }
                if missing { Text("File not found at this path. It may have been moved or renamed.").font(.system(size: 11)).foregroundStyle(.orange) }
                HStack(spacing: 6) {
                    Text(record.collection).font(.system(size: 10, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Butter.butter, in: Capsule())
                    if !record.tags.isEmpty { Text(record.tags).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                if record.kind == "link", let url = URL(string: record.value) {
                    iconButton("safari", "Open link") { NSWorkspace.shared.open(url) }
                    iconButton("doc.on.doc", "Copy link") { copy(record.value) }
                }
                if record.kind == "file" {
                    iconButton("arrow.up.forward.app", "Open file") { NSWorkspace.shared.open(URL(fileURLWithPath: record.value)) }.disabled(missing)
                    iconButton("folder", "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.value)]) }.disabled(missing)
                    iconButton("doc.on.doc", "Copy path") { copy(record.value) }
                }
                if record.kind == "contact" {
                    iconButton("doc.on.doc", "Copy mobile number") { copy(record.value) }.disabled(record.value.isEmpty)
                    if !record.email.isEmpty { iconButton("envelope", "Copy email") { copy(record.email) } }
                }
                iconButton("pencil", "Edit") { editing = record }
                iconButton("trash", "Delete") { store.remove(ids: [record.id]); selection.remove(record.id) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 24, height: 24) }
            .buttonStyle(.bordered).controlSize(.small).help(help)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        store.message = "Copied."
    }

    // MARK: Actions

    private func importContacts() {
        let panel = NSOpenPanel()
        panel.title = "Choose a VCF or CSV contacts file"
        panel.allowedContentTypes = [UTType(filenameExtension: "vcf") ?? .data, .commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var total = 0, found = 0
        for url in panel.urls {
            do {
                let contacts = try EzContactImport.parse(url: url)
                found += contacts.count
                total += store.addContacts(contacts, collection: currentCollection)
            } catch { store.message = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"; return }
        }
        store.message = "Added \(total) contact(s). \(found - total) already saved or without a name."
    }

    private func importLinksCSV() {
        let panel = NSOpenPanel()
        panel.title = "Choose a CSV of links"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let table = try EzContactImport.readTable(url: url)
            let lower = table.headers.map { $0.lowercased() }
            let urlColumn = lower.firstIndex { $0.contains("url") || $0.contains("link") || $0.contains("website") } ?? 0
            let titleColumn = lower.firstIndex { $0.contains("title") || $0.contains("name") }
            let items = table.rows.map { row -> (title: String, url: String) in
                (title: titleColumn.flatMap { $0 < row.count ? row[$0] : nil } ?? "", url: urlColumn < row.count ? row[urlColumn] : "")
            }
            store.message = "Added \(store.addLinks(items, collection: currentCollection)) link(s)."
        } catch { store.message = "Could not read that file: \(error.localizedDescription)" }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Choose files or folders to link"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        store.message = "Added \(store.addFiles(panel.urls, collection: currentCollection)) file link(s)."
    }

    private func checkFiles() {
        let files = store.records.filter { $0.kind == "file" }
        let missing = files.filter { !FileManager.default.fileExists(atPath: $0.value) }
        store.message = missing.isEmpty ? "All \(files.count) file links work." : "\(missing.count) of \(files.count) file links point to a missing file (marked with a warning)."
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MyDatabase-\(tab).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = store.csv(for: kind, records: visible)
        do { try text.write(to: url, atomically: true, encoding: .utf8); store.message = "Exported \(visible.count) rows." }
        catch { store.message = "Could not save: \(error.localizedDescription)" }
    }

    private var pasteLinksSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste links").font(.title3.bold())
            Text("One link per line. To name a link, write the name, then a | sign, then the link. Example: Our site | ezyourlife.com")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $pasteText).font(.system(size: 13)).frame(minWidth: 460, minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            HStack {
                Spacer()
                Button("Cancel") { showPasteLinks = false }
                Button("Add links") {
                    let items = pasteText.split(whereSeparator: \.isNewline).map { line -> (title: String, url: String) in
                        let parts = line.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                        return parts.count == 2 ? (title: parts[0], url: parts[1]) : (title: "", url: parts.first ?? "")
                    }
                    store.message = "Added \(store.addLinks(items, collection: currentCollection)) link(s)."
                    showPasteLinks = false
                }.buttonStyle(.borderedProminent).tint(Butter.coral)
            }
        }
        .padding(20)
    }

    // MARK: Tables

    private var tablesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let id = openTableID, let table = store.tables.first(where: { $0.id == id }) {
                tableEditor(table)
            } else {
                HStack(spacing: 8) {
                    Button { importTable() } label: { Label("Upload CSV", systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent).tint(Butter.coral)
                    Button {
                        store.addTable(DBTable(name: "New table", headers: ["Name", "Details"], rows: [["", ""]]))
                        openTableID = store.tables.first?.id
                    } label: { Label("New table", systemImage: "plus") }.buttonStyle(.bordered)
                    Spacer()
                }
                if store.tables.isEmpty {
                    ContentUnavailableView("No tables yet", systemImage: "tablecells", description: Text("Upload a CSV file of your data, products or customers. You can edit it here and export it again."))
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ForEach(store.tables) { table in
                        HStack(spacing: 12) {
                            Image(systemName: "tablecells").foregroundStyle(Butter.coral)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(table.name).font(.system(size: 14, weight: .semibold))
                                Text("\(table.rows.count) rows · \(table.headers.count) columns · \(table.headers.prefix(4).joined(separator: ", "))")
                                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("Open") { openTableID = table.id; page = 0 }.buttonStyle(.bordered)
                            Button(role: .destructive) { store.removeTable(table.id) } label: { Image(systemName: "trash") }.buttonStyle(.bordered)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Butter.honey, lineWidth: 1))
                    }
                }
            }
        }
    }

    private func tableEditor(_ table: DBTable) -> some View {
        let pageSize = 50
        let start = min(page * pageSize, max(0, table.rows.count - 1))
        let end = min(start + pageSize, table.rows.count)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { store.save(); openTableID = nil } label: { Label("All tables", systemImage: "chevron.left") }.buttonStyle(.bordered)
                TextField("Table name", text: Binding(get: { table.name }, set: { store.renameTable(table.id, to: $0) })).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Button { store.addRow(table: table.id); page = max(0, (table.rows.count) / pageSize) } label: { Label("Add row", systemImage: "plus") }.buttonStyle(.bordered)
                TextField("New column", text: $newColumnName).textFieldStyle(.roundedBorder).frame(width: 130)
                Button {
                    let name = newColumnName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { store.addColumn(table: table.id, name: name); newColumnName = "" }
                } label: { Label("Add column", systemImage: "plus.rectangle.on.rectangle") }.buttonStyle(.bordered)
                Button { exportTable(table) } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                Spacer()
            }
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("").frame(width: 30)
                        ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                            Text(header).font(.system(size: 12, weight: .bold)).lineLimit(1).frame(width: 170, alignment: .leading).padding(.horizontal, 6)
                        }
                    }
                    ForEach(start..<end, id: \.self) { row in
                        HStack(spacing: 4) {
                            Button { store.removeRow(table: table.id, row: row) } label: { Image(systemName: "minus.circle").foregroundStyle(.red.opacity(0.7)) }
                                .buttonStyle(.plain).frame(width: 30).help("Delete this row")
                            ForEach(0..<table.headers.count, id: \.self) { column in
                                TextField("", text: Binding(
                                    get: { row < table.rows.count && column < table.rows[row].count ? table.rows[row][column] : "" },
                                    set: { store.setCell(table: table.id, row: row, column: column, value: $0) }))
                                    .textFieldStyle(.roundedBorder).frame(width: 170)
                            }
                        }
                    }
                }
                .padding(4)
            }
            .frame(minHeight: 260, maxHeight: 520)
            HStack {
                Text(table.rows.isEmpty ? "No rows" : "Rows \(start + 1)–\(end) of \(table.rows.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left") }.disabled(page == 0)
                Button { page += 1 } label: { Image(systemName: "chevron.right") }.disabled(end >= table.rows.count)
            }
        }
        .onDisappear { store.save() }
    }

    private func importTable() {
        let panel = NSOpenPanel()
        panel.title = "Choose a CSV file"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            store.message = "That file could not be read as text."; return
        }
        let rows = EzContactImport.csvRows(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        guard let header = rows.first, !header.isEmpty else { store.message = "That file is empty."; return }
        let headers = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let body = rows.dropFirst().map { row in (0..<headers.count).map { $0 < row.count ? row[$0] : "" } }
        let table = DBTable(name: url.deletingPathExtension().lastPathComponent, headers: headers, rows: Array(body), collection: currentCollection)
        store.addTable(table)
        store.message = "Uploaded \(body.count) rows into \"\(table.name)\"."
    }

    private func exportTable(_ table: DBTable) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = table.name + ".csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.csv(for: table).write(to: url, atomically: true, encoding: .utf8); store.message = "Exported \(table.rows.count) rows." }
        catch { store.message = "Could not save: \(error.localizedDescription)" }
    }

    // MARK: Shortcuts

    private var shortcutsView: some View {
        let matches = clips.filter { clip in
            shortcutSearch.trimmingCharacters(in: .whitespaces).isEmpty
                || [clip.key, clip.name, clip.group, clip.text, clip.keywords ?? ""].contains { $0.localizedCaseInsensitiveContains(shortcutSearch) }
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                MerlinBar(text: $shortcutSearch, placeholder: "Search your shortcuts…", showsBadge: false)
                Button { copyShortcutsToTable(clips) } label: { Label("Copy all to a table", systemImage: "tablecells.badge.ellipsis") }.buttonStyle(.bordered)
                    .help("Makes an editable table with code, collection, text and search words")
                Button { onOpenShortcuts("") } label: { Label("Open My shortcuts", systemImage: "arrow.up.forward.app") }.buttonStyle(.bordered)
            }
            Text("\(matches.count) of \(clips.count) shortcuts. Edit opens the shortcut where you rename, change text or move it. Nothing is changed from this list.")
                .font(.caption).foregroundStyle(.secondary)
            LazyVStack(spacing: 0) {
                ForEach(matches.prefix(300)) { clip in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(displayTrigger(clip.key)).font(.system(size: 13, weight: .semibold, design: .monospaced))
                            Text(clip.text.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                            Text(clip.allGroups.joined(separator: ", ")).font(.system(size: 10, weight: .bold)).foregroundStyle(Butter.coral)
                        }
                        Spacer()
                        Button { onOpenShortcuts(clip.key) } label: { Image(systemName: "pencil").frame(width: 24, height: 24) }
                            .buttonStyle(.bordered).controlSize(.small).help("Edit this shortcut")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    Divider()
                }
            }
            .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Butter.honey, lineWidth: 1))
            if matches.count > 300 { Text("Showing the first 300. Use search to narrow the list.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func copyShortcutsToTable(_ list: [Clip]) {
        let rows = list.map { [displayTrigger($0.key), $0.allGroups.joined(separator: "; "), $0.text, $0.keywords ?? ""] }
        store.addTable(DBTable(name: "Shortcuts copy", headers: ["Code", "Collections", "Text", "Search words"], rows: rows))
        tab = "Tables"
        openTableID = store.tables.first?.id
        store.message = "Copied \(rows.count) shortcuts into a table. This is a copy for organizing and export."
    }

    // MARK: File Renamer

    private var fileRenamerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files you rename here keep their saved links in the Files tab.").font(.caption).foregroundStyle(.secondary)
            FileRenamerView(onRenamed: { pairs in store.filesRenamed(pairs) })
        }
    }
}

// MARK: - Edit sheet

struct DBRecordEditor: View {
    @State var record: DBRecord
    var collections: [String]
    var onSave: (DBRecord) -> Void
    var onCancel: () -> Void

    private var valueLabel: String { record.kind == "contact" ? "Mobile number" : record.kind == "link" ? "Web address" : "File path" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(record.title.isEmpty ? "New \(record.kind)" : "Edit \(record.kind)").font(.title3.bold())
            field(record.kind == "contact" ? "Name" : "Title", $record.title)
            field(valueLabel, $record.value)
            if record.kind == "contact" {
                field("Email", $record.email)
                field("Company", $record.company)
                field("Address", $record.address)
            }
            HStack {
                Text("Collection").font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                TextField("General", text: $record.collection).textFieldStyle(.roundedBorder)
                Menu {
                    ForEach(collections, id: \.self) { name in Button(name) { record.collection = name } }
                } label: { Image(systemName: "chevron.down.circle") }.menuStyle(.borderlessButton).frame(width: 30)
            }
            field("Tags", $record.tags)
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                TextEditor(text: $record.notes).font(.system(size: 13)).frame(height: 70).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    var saved = record
                    saved.collection = saved.collection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "General" : saved.collection.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(saved)
                }
                .buttonStyle(.borderedProminent).tint(Butter.coral)
                .disabled(record.title.trimmingCharacters(in: .whitespaces).isEmpty && record.value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 460)
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            TextField(label, text: text).textFieldStyle(.roundedBorder)
        }
    }
}
