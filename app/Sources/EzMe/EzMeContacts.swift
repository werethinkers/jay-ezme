// Contacts to shortcuts, and short endings.
//
// 1. Import a VCF or CSV (Google Contacts, Zoho and others export these) and Collection Builder
//    creates one shortcut per detail, for example yogeshsahu.name, yogeshsahu.mobile, yogeshsahu.email.
// 2. When you type the start of an ending, EzMe finds the full shortcut: yogesh.n runs yogesh.name,
//    yogesh.mo runs yogesh.mobile. A shortcut you made yourself with that exact ending always wins.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Short endings

/// Endings that win when several shortcuts share the typed beginning, most useful first.
private let ezEndingPriority = ["name", "mobile", "phone", "firstname", "lastname", "email", "address", "company", "title"]

/// "/yogesh.n" -> the shortcut "/yogesh.name" when there is no exact "/yogesh.n".
/// Only the part after the last dot may be shortened, and the exact shortcut is always checked first by the caller.
func resolveShortSuffixShortcut(_ wanted: String, in clips: [Clip]) -> Clip? {
    let typed = wanted.lowercased()
    guard let dot = typed.lastIndex(of: "."), dot != typed.startIndex else { return nil }
    let partial = String(typed[typed.index(after: dot)...])
    guard !partial.isEmpty, partial.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
    let stem = String(typed[...dot])
    var best: (rank: Int, length: Int, clip: Clip)?
    for clip in clips {
        let key = clip.key.lowercased()
        guard key.hasPrefix(stem), key.count > typed.count else { continue }
        let ending = String(key.dropFirst(stem.count))
        guard ending.hasPrefix(partial), !ending.contains(".") else { continue }
        let rank = ezEndingPriority.firstIndex(of: ending) ?? ezEndingPriority.count
        if let current = best {
            if rank < current.rank || (rank == current.rank && ending.count < current.length) {
                best = (rank, ending.count, clip)
            }
        } else {
            best = (rank, ending.count, clip)
        }
    }
    return best?.clip
}

// MARK: - Contacts

struct EzContact: Identifiable {
    var id = UUID()
    var first = ""
    var last = ""
    var full = ""
    var mobile = ""
    var phones: [String] = []
    var email = ""
    var address = ""
    var company = ""
    var title = ""

    var displayName: String {
        if !full.isEmpty { return full }
        return [first, last].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum EzContactField: String, CaseIterable, Identifiable {
    case name, firstname, lastname, mobile, phone, email, address, company, title
    var id: String { rawValue }
    var label: String {
        switch self {
        case .name: return "Name"
        case .firstname: return "First name"
        case .lastname: return "Last name"
        case .mobile: return "Mobile"
        case .phone: return "Phone"
        case .email: return "Email"
        case .address: return "Address"
        case .company: return "Company"
        case .title: return "Job title"
        }
    }

    func value(of contact: EzContact) -> String {
        switch self {
        case .name: return contact.displayName
        case .firstname: return contact.first
        case .lastname: return contact.last
        case .mobile: return contact.mobile
        case .phone: return contact.phones.first ?? contact.mobile
        case .email: return contact.email
        case .address: return contact.address
        case .company: return contact.company
        case .title: return contact.title
        }
    }
}

/// How the first part of each shortcut is built from the person's name.
enum EzContactCodeStyle: String, CaseIterable, Identifiable {
    case fullFirstFullLast, first3Last3, initialFullLast, first3FullLast, firstOnly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullFirstFullLast: return "Full first name + full last name"
        case .first3Last3: return "First 3 letters + last 3 letters"
        case .initialFullLast: return "First letter + full last name"
        case .first3FullLast: return "First 3 letters + full last name"
        case .firstOnly: return "Full first name only"
        }
    }

    func stem(first: String, last: String, full: String) -> String {
        func clean(_ value: String) -> String {
            String(String.UnicodeScalarView(value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }))
        }
        let f = clean(first), l = clean(last)
        if f.isEmpty && l.isEmpty {
            let fallback = clean(full)
            return fallback.isEmpty ? "contact" : String(fallback.prefix(14))
        }
        if l.isEmpty { return String(f.prefix(14)) }
        if f.isEmpty { return String(l.prefix(14)) }
        switch self {
        case .fullFirstFullLast: return f + l
        case .first3Last3: return String(f.prefix(3)) + String(l.prefix(3))
        case .initialFullLast: return String(f.prefix(1)) + l
        case .first3FullLast: return String(f.prefix(3)) + l
        case .firstOnly: return f
        }
    }

    func example(first: String, last: String) -> String { stem(first: first, last: last, full: first + " " + last) }
}

enum EzContactImport {
    static let maxContacts = 5000

    static func parse(url: URL) throws -> [EzContact] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: "EzMeContacts", code: 1, userInfo: [NSLocalizedDescriptionKey: "That file could not be read as text."])
        }
        let ext = url.pathExtension.lowercased()
        let contacts = (ext == "csv" || (ext != "vcf" && !text.contains("BEGIN:VCARD"))) ? parseCSV(text) : parseVCF(text)
        return Array(contacts.filter { !$0.displayName.isEmpty }.prefix(maxContacts))
    }

    // MARK: VCF

    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseVCF(_ text: String) -> [EzContact] {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n") {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += String(raw.dropFirst())
            } else {
                lines.append(raw)
            }
        }
        var result: [EzContact] = []
        var current: EzContact?
        for line in lines {
            let upper = line.uppercased()
            if upper.hasPrefix("BEGIN:VCARD") { current = EzContact(); continue }
            if upper.hasPrefix("END:VCARD") {
                if var contact = current {
                    if contact.first.isEmpty && contact.last.isEmpty && !contact.full.isEmpty {
                        let parts = contact.full.split(separator: " ").map(String.init)
                        if parts.count > 1 { contact.last = parts.last ?? ""; contact.first = parts.dropLast().joined(separator: " ") }
                        else { contact.first = contact.full }
                    }
                    if contact.full.isEmpty { contact.full = [contact.first, contact.last].filter { !$0.isEmpty }.joined(separator: " ") }
                    result.append(contact)
                }
                current = nil
                continue
            }
            guard current != nil, let colon = line.firstIndex(of: ":") else { continue }
            let head = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            let pieces = head.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            var property = (pieces.first ?? "").uppercased()
            if let dot = property.lastIndex(of: ".") { property = String(property[property.index(after: dot)...]) }
            let params = pieces.dropFirst().joined(separator: ";").uppercased()
            let parts = value.components(separatedBy: ";")
            switch property {
            case "N":
                current?.last = unescape(parts.count > 0 ? parts[0] : "")
                current?.first = unescape(parts.count > 1 ? parts[1] : "")
            case "FN":
                current?.full = unescape(value)
            case "TEL":
                let number = unescape(value).replacingOccurrences(of: "tel:", with: "")
                guard !number.isEmpty else { break }
                let isMobile = params.contains("CELL") || params.contains("MOBILE") || params.contains("IPHONE")
                if isMobile && (current?.mobile.isEmpty ?? false) { current?.mobile = number }
                else { current?.phones.append(number) }
            case "EMAIL":
                if current?.email.isEmpty ?? false { current?.email = unescape(value) }
            case "ADR":
                let joined = parts.dropFirst(2).map(unescape).filter { !$0.isEmpty }.joined(separator: ", ")
                if current?.address.isEmpty ?? false { current?.address = joined }
            case "ORG":
                if current?.company.isEmpty ?? false { current?.company = unescape(parts.first ?? "") }
            case "TITLE":
                if current?.title.isEmpty ?? false { current?.title = unescape(value) }
            default:
                break
            }
        }
        // A number with no type is still a number: use the first one as the mobile if no mobile was marked.
        return result.map { contact in
            var c = contact
            if c.mobile.isEmpty, let first = c.phones.first { c.mobile = first; c.phones.removeFirst() }
            return c
        }
    }

    // MARK: CSV (Google Contacts and Zoho exports)

    static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\n" || c == "\r" { row.append(field); field = ""; if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }; row = [] }
            else { field.append(c) }
            i += 1
        }
        row.append(field)
        if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }
        return rows
    }

    static func parseCSV(_ text: String) -> [EzContact] {
        let rows = csvRows(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        guard let header = rows.first else { return [] }
        let names = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func index(_ options: [String]) -> Int? { options.compactMap { names.firstIndex(of: $0) }.first }
        func value(_ row: [String], _ i: Int?) -> String {
            guard let i, i < row.count else { return "" }
            return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let firstI = index(["first name", "given name"])
        let lastI = index(["last name", "family name", "surname"])
        let fullI = index(["name", "full name", "display name", "file as"])
        let emailI = index(["e-mail 1 - value", "email", "email address", "e-mail address", "e-mail", "secondary email"])
        let companyI = index(["organization name", "organization 1 - name", "company", "account name", "organization"])
        let titleI = index(["job title", "organization title", "organization 1 - title", "title"])
        let mobileI = index(["mobile", "mobile phone", "cell", "cell phone"])
        let phoneI = index(["phone", "home phone", "work phone", "business phone", "other phone"])
        let formattedAddressI = index(["address 1 - formatted", "address", "mailing address"])
        let streetI = index(["mailing street", "address 1 - street", "street"])
        let cityI = index(["mailing city", "address 1 - city", "city"])
        let stateI = index(["mailing state", "address 1 - region", "state"])
        let zipI = index(["mailing zip", "address 1 - postal code", "zip code", "zip"])
        let countryI = index(["mailing country", "address 1 - country", "country"])
        // Google exports "Phone 1 - Type" and "Phone 1 - Value" pairs.
        let googlePairs: [(Int?, Int?)] = (1...5).map { n in (names.firstIndex(of: "phone \(n) - type"), names.firstIndex(of: "phone \(n) - value")) }

        var result: [EzContact] = []
        for row in rows.dropFirst() {
            var contact = EzContact()
            contact.first = value(row, firstI)
            contact.last = value(row, lastI)
            contact.full = value(row, fullI)
            contact.email = value(row, emailI).components(separatedBy: " ::: ").first ?? ""
            contact.company = value(row, companyI)
            contact.title = value(row, titleI)
            contact.mobile = value(row, mobileI)
            let phone = value(row, phoneI)
            if !phone.isEmpty { contact.phones.append(phone) }
            for (typeI, valueI) in googlePairs {
                for number in value(row, valueI).components(separatedBy: " ::: ") where !number.isEmpty {
                    let type = value(row, typeI).lowercased()
                    if (type.contains("mobile") || type.contains("cell")) && contact.mobile.isEmpty { contact.mobile = number }
                    else { contact.phones.append(number) }
                }
            }
            if contact.mobile.isEmpty, let first = contact.phones.first { contact.mobile = first; contact.phones.removeFirst() }
            let formatted = value(row, formattedAddressI).replacingOccurrences(of: "\n", with: ", ")
            if !formatted.isEmpty { contact.address = formatted }
            else {
                contact.address = [streetI, cityI, stateI, zipI, countryI].map { value(row, $0) }.filter { !$0.isEmpty }.joined(separator: ", ")
            }
            if contact.first.isEmpty && contact.last.isEmpty && !contact.full.isEmpty {
                let parts = contact.full.split(separator: " ").map(String.init)
                if parts.count > 1 { contact.last = parts.last ?? ""; contact.first = parts.dropLast().joined(separator: " ") }
                else { contact.first = contact.full }
            }
            if contact.full.isEmpty { contact.full = [contact.first, contact.last].filter { !$0.isEmpty }.joined(separator: " ") }
            if !contact.displayName.isEmpty { result.append(contact) }
        }
        return result
    }

    // MARK: Any other list (products, items, vendors...)

    static func readTable(url: URL) throws -> (headers: [String], rows: [[String]]) {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: "EzMeContacts", code: 1, userInfo: [NSLocalizedDescriptionKey: "That file could not be read as text."])
        }
        let rows = csvRows(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        guard let header = rows.first else { return ([], []) }
        return (header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }, Array(rows.dropFirst().prefix(maxContacts)))
    }

    private static func cleanWord(_ value: String) -> String {
        String(String.UnicodeScalarView(value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }))
    }

    static func tableShortcuts(headers: [String], rows: [[String]], nameColumn: Int, columns: Set<Int>, shortWords: Bool, group: String, note: String) -> [Clip] {
        var stems = Set<String>()
        var clips: [Clip] = []
        for row in rows {
            guard nameColumn < row.count else { continue }
            let name = row[nameColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { cleanWord(String($0)) }.filter { !$0.isEmpty }
            var stem = shortWords ? String(words.map { String($0.prefix(3)) }.joined().prefix(14)) : String(words.joined().prefix(14))
            if stem.isEmpty { stem = "item" }
            let base = stem
            var number = 2
            while stems.contains(stem) { stem = base + String(number); number += 1 }
            stems.insert(stem)
            var endings = Set<String>()
            for column in columns.sorted() {
                let isName = column == nameColumn
                guard column < row.count, column < headers.count else { continue }
                let text = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                var ending = isName ? "name" : cleanWord(headers[column])
                if ending.isEmpty { ending = "col\(column + 1)" }
                guard endings.insert(ending).inserted else { continue }
                clips.append(Clip(key: "/" + stem + "." + ending,
                                  name: name + " · " + (isName ? "Name" : headers[column]),
                                  text: text,
                                  group: group,
                                  keywords: [name, note].filter { !$0.isEmpty }.joined(separator: " ")))
            }
        }
        return clips
    }

    // MARK: Shortcuts

    static func shortcuts(for contacts: [EzContact], style: EzContactCodeStyle, fields: Set<EzContactField>, group: String) -> [Clip] {
        var stems = Set<String>()
        var clips: [Clip] = []
        for contact in contacts {
            var stem = style.stem(first: contact.first, last: contact.last, full: contact.full)
            var number = 2
            let base = stem
            while stems.contains(stem) { stem = base + String(number); number += 1 }
            stems.insert(stem)
            let searchWords = [contact.displayName, contact.company, contact.email, contact.mobile].filter { !$0.isEmpty }.joined(separator: " ")
            for field in EzContactField.allCases where fields.contains(field) {
                let text = field.value(of: contact)
                guard !text.isEmpty else { continue }
                clips.append(Clip(key: "/" + stem + "." + field.rawValue,
                                  name: contact.displayName + " · " + field.label,
                                  text: text,
                                  group: group,
                                  keywords: searchWords))
            }
        }
        return clips
    }
}

// MARK: - Collection Builder: attach a list on the left

enum EzAttachmentKind: String, CaseIterable, Identifiable {
    case contacts, products, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .contacts: return "Contacts or people"
        case .products: return "Products or items"
        case .other: return "Another kind of list"
        }
    }
    var hint: String {
        switch self {
        case .contacts: return "VCF from Google Contacts or Zoho, or a CSV export. Creates name, first name, last name, mobile, phone, email, address and more."
        case .products: return "A CSV with one row per product or item. Each column becomes an ending, for example cottonshirt.price."
        case .other: return "A CSV with one row per entry, such as vendors, places or recipes. Each column becomes an ending."
        }
    }
}

struct EzAttachmentImportCard: View {
    var onCreate: ([Clip], String) -> Void
    @State private var kind: EzAttachmentKind?
    @State private var note = ""
    @State private var fileName = ""
    @State private var contacts: [EzContact] = []
    @State private var headers: [String] = []
    @State private var rows: [[String]] = []
    @State private var style: EzContactCodeStyle = .fullFirstFullLast
    @State private var fields: Set<EzContactField> = [.name, .firstname, .lastname, .mobile, .phone, .email, .address]
    @State private var nameColumn = 0
    @State private var columns = Set<Int>()
    @State private var shortWords = false
    @State private var group = "Contacts"
    @State private var staged: [Clip] = []
    @State private var selected = Set<UUID>()
    @State private var showRename = false
    @State private var status = ""

    private var hasFile: Bool { !fileName.isEmpty }
    private var rowCount: Int { kind == .contacts ? contacts.count : rows.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "paperclip").foregroundStyle(Butter.coral)
                Text("Build from an attached list").font(.system(size: 17, weight: .bold, design: .rounded))
                Text("optional").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            if !hasFile {
                Picker("What kind of file is it?", selection: $kind) {
                    Text("Choose the kind of file…").tag(EzAttachmentKind?.none)
                    ForEach(EzAttachmentKind.allCases) { option in Text(option.title).tag(Optional(option)) }
                }
                .pickerStyle(.menu)
                if let kind { Text(kind.hint).font(.caption).foregroundStyle(.secondary) }
                TextField("What is in it? e.g. Clients from Zoho, March price list (optional)", text: $note).textFieldStyle(.roundedBorder)
                Button("Attach VCF or CSV file…", systemImage: "paperclip.badge.ellipsis") { choose() }
                    .buttonStyle(.borderedProminent).tint(Butter.coral).disabled(kind == nil)
                Text("Pick the kind first, so EzMe knows how to read the file. Google Contacts and Zoho: export as VCF or CSV, then attach it here. Live sync is not connected yet.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                attachedRow
                if staged.isEmpty { options } else { review }
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(15).frame(maxWidth: .infinity, alignment: .leading)
        .background(Butter.cream, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Butter.coral.opacity(0.14), lineWidth: 1))
        .sheet(isPresented: $showRename) {
            BulkShortcutRenameSheet(clips: staged.filter { selected.isEmpty || selected.contains($0.id) }, allKeys: [], onApply: { changes in
                for index in staged.indices { if let value = changes[staged[index].id] { staged[index].key = value.key; staged[index].name = value.name } }
            })
        }
    }

    private var attachedRow: some View {
        HStack(spacing: 10) {
            Image(systemName: kind == .contacts ? "person.crop.rectangle.stack" : "tablecells").foregroundStyle(Butter.coral)
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text("\(kind?.title ?? "") · \(rowCount) rows" + (note.isEmpty ? "" : " · " + note)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Remove file", systemImage: "xmark.circle") { reset() }.buttonStyle(.bordered).controlSize(.small)
        }
        .padding(10).background(Butter.coral.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder private var options: some View {
        if kind == .contacts, let first = contacts.first {
            Picker("Shortcut starts with", selection: $style) {
                ForEach(EzContactCodeStyle.allCases) { option in
                    Text("\(option.title) · \(option.example(first: first.first, last: first.last))").tag(option)
                }
            }
            .pickerStyle(.menu)
            Text("Details to create").font(.caption.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(EzContactField.allCases) { field in
                    Toggle(field.label, isOn: Binding(get: { fields.contains(field) }, set: { on in if on { fields.insert(field) } else { fields.remove(field) } }))
                        .toggleStyle(.checkbox).font(.caption)
                }
            }
        } else if kind != .contacts, !headers.isEmpty {
            Picker("Name column", selection: $nameColumn) {
                ForEach(Array(headers.enumerated()), id: \.offset) { index, title in Text(title.isEmpty ? "Column \(index + 1)" : title).tag(index) }
            }
            .pickerStyle(.menu)
            .onChange(of: nameColumn) { value in columns.insert(value) }
            Text("Columns to turn into shortcuts").font(.caption.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(Array(headers.enumerated()), id: \.offset) { index, title in
                    Toggle(title.isEmpty ? "Column \(index + 1)" : title, isOn: Binding(get: { columns.contains(index) }, set: { on in if on { columns.insert(index) } else { columns.remove(index) } }))
                        .toggleStyle(.checkbox).font(.caption)
                }
            }
            Picker("Shortcut starts with", selection: $shortWords) {
                Text("The name as one word").tag(false)
                Text("First 3 letters of each word").tag(true)
            }
            .pickerStyle(.segmented)
        }
        TextField("Collection name", text: $group).textFieldStyle(.roundedBorder)
        Button("Review shortcuts", systemImage: "list.bullet.rectangle") { buildStaged() }
            .buttonStyle(.borderedProminent).tint(Butter.coral)
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(staged.count) shortcuts · edit anything before adding").font(.caption.weight(.semibold))
                Spacer()
                Button(selected.count == staged.count ? "Clear" : "Select all", systemImage: "checkmark.circle") {
                    selected = selected.count == staged.count ? [] : Set(staged.map(\.id))
                }.controlSize(.small)
                Button("Rename…", systemImage: "text.cursor") { showRename = true }.controlSize(.small)
                    .help(selected.isEmpty ? "Rename every shortcut with one rule" : "Rename the selected shortcuts with one rule")
                Button("Delete", systemImage: "trash", role: .destructive) {
                    staged.removeAll { selected.contains($0.id) }; selected.removeAll()
                }.controlSize(.small).disabled(selected.isEmpty)
            }
            .buttonStyle(.bordered)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach($staged) { $clip in
                        HStack(alignment: .top, spacing: 8) {
                            Toggle("", isOn: Binding(get: { selected.contains(clip.id) }, set: { on in if on { selected.insert(clip.id) } else { selected.remove(clip.id) } }))
                                .toggleStyle(.checkbox).labelsHidden()
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text("\\").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(Butter.coral)
                                    TextField("Shortcut", text: codeBinding($clip)).font(.system(size: 13, weight: .semibold, design: .monospaced)).textFieldStyle(.roundedBorder)
                                    TextField("Name", text: $clip.name).textFieldStyle(.roundedBorder)
                                }
                                TextField("Expands to", text: $clip.text).textFieldStyle(.roundedBorder).font(.system(size: 12))
                                TextField("Search words (not pasted)", text: keywordBinding($clip)).textFieldStyle(.roundedBorder).font(.system(size: 11))
                            }
                            Button { staged.removeAll { $0.id == clip.id }; selected.remove(clip.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove this shortcut")
                        }
                        .padding(9).background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .frame(maxHeight: 380)
            HStack {
                Button("Back to options", systemImage: "chevron.left") { staged = []; selected = [] }.buttonStyle(.bordered)
                Spacer()
                Button("Add \(staged.count) shortcuts to My Shortcuts", systemImage: "plus.circle.fill") {
                    let name = group.trimmingCharacters(in: .whitespacesAndNewlines)
                    let count = staged.count
                    onCreate(staged, name.isEmpty ? "Imported" : name)
                    status = "Added \(count) shortcuts to \(name.isEmpty ? "Imported" : name)."
                    staged = []; selected = []
                }
                .buttonStyle(.borderedProminent).tint(Butter.coral).disabled(staged.isEmpty)
            }
            Text("Short endings work too: type the start of an ending, such as .n for .name.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func codeBinding(_ clip: Binding<Clip>) -> Binding<String> {
        Binding(
            get: { clip.wrappedValue.key.trimmingCharacters(in: CharacterSet(charactersIn: "/\\")) },
            set: { value in
                let clean = String(value.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" })
                clip.wrappedValue.key = "/" + clean
            })
    }

    private func keywordBinding(_ clip: Binding<Clip>) -> Binding<String> {
        Binding(get: { clip.wrappedValue.keywords ?? "" }, set: { clip.wrappedValue.keywords = $0.isEmpty ? nil : $0 })
    }

    private func buildStaged() {
        let name = group.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = name.isEmpty ? "Imported" : name
        if kind == .contacts {
            staged = EzContactImport.shortcuts(for: contacts, style: style, fields: fields, group: target)
        } else {
            staged = EzContactImport.tableShortcuts(headers: headers, rows: rows, nameColumn: nameColumn, columns: columns, shortWords: shortWords, group: target, note: note)
        }
        selected = []
        status = staged.isEmpty ? "Nothing to create. Check the details or columns you picked." : ""
    }

    private func reset() {
        fileName = ""; contacts = []; headers = []; rows = []; staged = []; selected = []; columns = []; nameColumn = 0; status = ""
    }

    private func choose() {
        guard let kind else { return }
        let panel = NSOpenPanel()
        panel.title = "Attach a contacts or list file"
        var types: [UTType] = [.commaSeparatedText]
        if let vcf = UTType(filenameExtension: "vcf") { types.append(vcf) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if kind == .contacts {
                let parsed = try EzContactImport.parse(url: url)
                guard !parsed.isEmpty else { status = "No contacts with a name were found in that file."; return }
                contacts = parsed
                if group == "Contacts" || group.isEmpty { group = "Contacts" }
            } else {
                guard url.pathExtension.lowercased() != "vcf" else { status = "A VCF file holds contacts. Choose Contacts or people, or attach a CSV."; return }
                let table = try EzContactImport.readTable(url: url)
                guard !table.headers.isEmpty, !table.rows.isEmpty else { status = "That file has no rows to turn into shortcuts."; return }
                headers = table.headers
                rows = table.rows
                let guess = headers.firstIndex { h in ["name", "product", "item", "title", "company"].contains { h.lowercased().contains($0) } } ?? 0
                nameColumn = guess
                columns = Set(headers.indices.prefix(12)).union([guess])
                if group == "Contacts" || group.isEmpty { group = note.isEmpty ? (kind == .products ? "Products" : "Imported list") : note }
            }
            fileName = url.lastPathComponent
            status = rowCount >= EzContactImport.maxContacts ? "Only the first \(EzContactImport.maxContacts) rows were read." : ""
        } catch {
            status = "Could not read that file: \(error.localizedDescription)"
        }
    }
}
