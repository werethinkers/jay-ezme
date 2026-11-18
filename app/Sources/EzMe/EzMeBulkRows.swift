// Smarter bulk shortcut paste, app-made collections, and contacts from the Mac's Contacts app (which holds Google contacts too).
import Foundation
import Contacts

enum BulkRows {
    private static let separators = CharacterSet(charactersIn: ":=>-\u{2013}\u{2014}\u{2192}").union(.whitespaces)

    /// A short display name made from the expanded text: its first few words.
    static func nameFrom(_ text: String, fallback: String) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return fallback }
        var words = clean.split(separator: " ").prefix(6).map(String.init)
        var result = words.joined(separator: " ")
        while result.count > 40, words.count > 1 { words.removeLast(); result = words.joined(separator: " ") }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?-\u{2013}\u{2014}\"'"))
        return result.isEmpty ? fallback : result
    }

    /// One row per line, as [shortcut, expanded text, display name, collection, media...].
    /// A line with commas or tabs whose first part is a single word keeps its columns. Any other line is read as
    /// "shortcut" then the text: the first word is the shortcut, the rest is the expanded text, and the name is made from it.
    static func smart(_ text: String, split: (String) -> [String]) -> [[String]] {
        var rows: [[String]] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            var columns: [String]
            let delimited = trimmed.contains("\t") ? trimmed.components(separatedBy: "\t") : (trimmed.contains(",") ? split(trimmed) : [trimmed])
            let first = delimited.first?.trimmingCharacters(in: .whitespaces) ?? ""
            let structured = delimited.count > 1 && !first.isEmpty && !first.contains(" ")
            if structured {
                columns = delimited.map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                // First word is the shortcut; separators like ":" or "=" right after it are dropped.
                let pieces = trimmed.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
                let key = String(pieces.first ?? "").trimmingCharacters(in: CharacterSet(charactersIn: ":=,"))
                var rest = pieces.count > 1 ? String(pieces[1]) : ""
                rest = rest.trimmingCharacters(in: separators)
                columns = [key, rest]
            }
            while columns.count < 3 { columns.append("") }
            let key = columns[0]
            guard !key.isEmpty else { continue }
            var phrase = columns[1], name = columns[2]
            if phrase.isEmpty, !name.isEmpty { phrase = name }
            if name.isEmpty { name = nameFrom(phrase, fallback: key) }
            columns[1] = phrase
            columns[2] = name
            rows.append(columns)
        }
        return rows
    }
}

/// Collections that apps make on their own, so they can sit together under "Apps" instead of filling the list.
enum AppCollections {
    private static let lock = NSLock()
    private static var cacheKey = ""
    private static var cache = Set<String>()

    static func names() -> Set<String> {
        let defaults = UserDefaults.standard
        let json = defaults.string(forKey: "ezmeCustomBuilderAppsJSON") ?? "[]"
        let apps = (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
        let outputs = apps.map { defaults.string(forKey: "ezmeBuilderOutputCollections." + $0) ?? "" }
        let key = json + "|" + outputs.joined(separator: "|")
        lock.lock(); defer { lock.unlock() }
        if key == cacheKey { return cache }
        var set = Set<String>()
        for (index, app) in apps.enumerated() {
            let pieces = outputs[index].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
            if pieces.isEmpty { set.insert(app.lowercased()) } else { pieces.forEach { set.insert($0) } }
        }
        cacheKey = key
        cache = set
        return set
    }
}

/// The Mac's Contacts app. Google contacts show up here once the Google account is added in System Settings, Internet Accounts, with Contacts on.
enum MacContacts {
    static func fetch() async throws -> [EzContact] {
        let store = CNContactStore()
        let granted = try await store.requestAccess(for: .contacts)
        guard granted else {
            throw NSError(domain: "KeyDo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Contacts access was not allowed. Allow KeyDo in System Settings, Privacy and Security, Contacts."])
        }
        return try await Task.detached { () -> [EzContact] in
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor, CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactJobTitleKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactPostalAddressesKey as CNKeyDescriptor, CNContactUrlAddressesKey as CNKeyDescriptor,
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
            ]
            var found: [EzContact] = []
            let request = CNContactFetchRequest(keysToFetch: keys)
            try store.enumerateContacts(with: request) { contact, _ in
                var item = EzContact()
                item.first = contact.givenName
                item.last = contact.familyName
                item.full = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
                item.company = contact.organizationName
                item.title = contact.jobTitle
                item.phones = contact.phoneNumbers.map { $0.value.stringValue }
                let mobile = contact.phoneNumbers.first { ($0.label ?? "").lowercased().contains("mobile") } ?? contact.phoneNumbers.first
                item.mobile = mobile?.value.stringValue ?? ""
                item.email = contact.emailAddresses.first.map { String($0.value) } ?? ""
                if let postal = contact.postalAddresses.first { item.address = CNPostalAddressFormatter.string(from: postal.value, style: .mailingAddress).replacingOccurrences(of: "\n", with: ", ") }
                item.url = contact.urlAddresses.first.map { String($0.value) } ?? ""
                item.source = "Mac Contacts"
                if !item.displayName.isEmpty { found.append(item) }
            }
            return found
        }.value
    }
}
