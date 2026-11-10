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

    private static func csvRows(_ text: String) -> [[String]] {
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

// MARK: - Collection Builder card

struct EzContactImportCard: View {
    var onCreate: ([Clip], String) -> Void
    @State private var contacts: [EzContact] = []
    @State private var fileName = ""
    @State private var style: EzContactCodeStyle = .fullFirstFullLast
    @State private var fields: Set<EzContactField> = [.name, .firstname, .lastname, .mobile, .phone, .email, .address]
    @State private var group = "Contacts"
    @State private var status = ""

    private var preview: [Clip] { EzContactImport.shortcuts(for: Array(contacts.prefix(1)), style: style, fields: fields, group: group) }
    private var exampleStem: String {
        guard let key = preview.first?.key else { return "name" }
        let trimmed = key.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        return trimmed.components(separatedBy: ".").first ?? trimmed
    }
    private var total: Int { EzContactImport.shortcuts(for: contacts, style: style, fields: fields, group: group).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Make shortcuts from a contact list, one for each detail such as name, mobile or email. Export your Google Contacts or Zoho contacts as VCF or CSV and choose the file.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Choose VCF or CSV file…", systemImage: "person.crop.circle.badge.plus") { choose() }
                .buttonStyle(.bordered)
            if !contacts.isEmpty {
                Text("\(contacts.count) contacts from \(fileName)").font(.caption.weight(.semibold))
                Picker("Shortcut starts with", selection: $style) {
                    ForEach(EzContactCodeStyle.allCases) { option in
                        Text("\(option.title) · \(option.example(first: contacts[0].first, last: contacts[0].last))").tag(option)
                    }
                }
                .pickerStyle(.menu)
                Text("Details to create").font(.caption.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(EzContactField.allCases) { field in
                        Toggle(field.label, isOn: Binding(get: { fields.contains(field) }, set: { on in if on { fields.insert(field) } else { fields.remove(field) } }))
                            .toggleStyle(.checkbox).font(.caption)
                    }
                }
                TextField("Collection name", text: $group).textFieldStyle(.roundedBorder)
                ForEach(preview) { clip in
                    HStack(spacing: 6) {
                        Text(displayTrigger(clip.key)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Butter.coral)
                        Text(clip.text).font(.system(size: 11)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                Text("Short endings work too: \\" + exampleStem + ".n runs the .name shortcut.")
                    .font(.caption2).foregroundStyle(.secondary)
                Button("Create \(total) shortcuts", systemImage: "plus.circle.fill") {
                    let name = group.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { status = "Give the collection a name."; return }
                    onCreate(EzContactImport.shortcuts(for: contacts, style: style, fields: fields, group: name), name)
                    status = "Created \(total) shortcuts in \(name)."
                }
                .buttonStyle(.borderedProminent).tint(Butter.coral).disabled(total == 0 || fields.isEmpty)
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose a contacts file"
        var types: [UTType] = [.commaSeparatedText]
        if let vcf = UTType(filenameExtension: "vcf") { types.append(vcf) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let parsed = try EzContactImport.parse(url: url)
            guard !parsed.isEmpty else { status = "No contacts with a name were found in that file."; return }
            contacts = parsed
            fileName = url.lastPathComponent
            status = parsed.count >= EzContactImport.maxContacts ? "Only the first \(EzContactImport.maxContacts) contacts were read." : ""
        } catch {
            status = "Could not read that file: \(error.localizedDescription)"
        }
    }
}
