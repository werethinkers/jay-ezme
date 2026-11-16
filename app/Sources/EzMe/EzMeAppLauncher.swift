// Finds and opens published apps and contacts from one sentence, typed or spoken.
//   $greeting   looks at apps only        @rahul   looks at people only        no symbol   looks at everything
// A sentence with an action word (create, generate, send, design, make...) opens the app it names, and the rest of
// the sentence becomes what goes into the form.
import SwiftUI
import AppKit

struct LaunchSuggestion: Identifiable {
    enum Kind { case app, contact, shortcut }
    var id: String
    var kind: Kind
    var title: String
    var subtitle: String
    var symbol: String
    var designID: String? = nil
    var recordID: String? = nil
    var clipKey: String? = nil
}

enum LaunchScope { case apps, contacts, everything }

@MainActor final class AppLauncher: NSObject, NSWindowDelegate {
    static let shared = AppLauncher()
    private var windows: [NSWindow] = []

    static let verbs: Set<String> = ["create", "generate", "send", "design", "make", "build", "write", "prepare", "draft", "issue", "print", "produce", "compose", "fill", "run", "open", "launch", "start"]
    private static let filler: Set<String> = ["a", "an", "the", "me", "my", "please", "app", "using", "use", "with", "new", "one", "now"]
    private static let peopleWords = ["contact", "people", "person", "customer", "client", "friend", "family", "team", "employee", "member", "student", "lead", "vendor", "supplier", "staff", "relative", "colleague"]

    // MARK: Reading the sentence

    static func split(_ raw: String) -> (scope: LaunchScope, text: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        if text.hasPrefix("$") { return (.apps, String(text.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        if text.hasPrefix("@") { return (.contacts, String(text.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        for spoken in ["dollar sign ", "dollar "] where lower.hasPrefix(spoken) { text = String(text.dropFirst(spoken.count)); return (.apps, text) }
        for spoken in ["at the rate of ", "at the rate "] where lower.hasPrefix(spoken) { text = String(text.dropFirst(spoken.count)); return (.contacts, text) }
        return (.everything, text)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression).split(separator: " ").map(String.init)
    }

    static func hasVerb(_ text: String) -> Bool { words(text).contains { verbs.contains($0) } }

    private static func same(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let n = min(a.count, b.count)
        guard n >= 4 else { return false }
        return a.hasPrefix(String(b.prefix(max(4, n - 1)))) || b.hasPrefix(String(a.prefix(max(4, n - 1))))
    }

    var publishedApps: [AppDesign] { AppDesignStore.shared.designs.filter { $0.version > 0 } }

    /// The published app a sentence is about, and what is left of the sentence for the form.
    func matchApp(in text: String) -> (design: AppDesign, rest: String)? {
        let spoken = Self.words(text)
        guard !spoken.isEmpty else { return nil }
        var best: (design: AppDesign, score: Double, used: Set<String>)?
        for design in publishedApps {
            let nameWords = Self.words(design.appTitle ?? design.name).filter { !Self.filler.contains($0) && $0.count >= 2 }
            guard !nameWords.isEmpty else { continue }
            var used = Set<String>()
            var hit = 0
            for word in nameWords {
                if let found = spoken.first(where: { Self.same($0, word) }) { hit += 1; used.insert(found) }
            }
            let score = Double(hit) / Double(nameWords.count)
            if hit > 0, score >= 0.5, score > (best?.score ?? 0) { best = (design, score, used) }
        }
        guard let best else { return nil }
        var left: [String] = []
        for word in text.split(separator: " ").map(String.init) {
            let clean = word.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if Self.verbs.contains(clean) || best.used.contains(clean) || Self.filler.contains(clean) { continue }
            left.append(word)
        }
        return (best.design, left.joined(separator: " "))
    }

    // MARK: People

    func people() -> [CollectionRecord] {
        let records = AppDesignContext.shared.records
        let likely = records.filter { record in
            let name = record.collection.lowercased()
            return Self.peopleWords.contains { name.contains($0) }
        }
        return likely.isEmpty ? records : likely
    }

    // MARK: Suggestions for the box

    func suggestions(for raw: String) -> [LaunchSuggestion] {
        let (scope, text) = Self.split(raw)
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        var result: [LaunchSuggestion] = []
        let tokens = Self.words(text).filter { !Self.verbs.contains($0) && !Self.filler.contains($0) }
        func hits(_ title: String) -> Bool {
            if query.isEmpty { return true }
            let lower = title.lowercased()
            return lower.contains(query) || (!tokens.isEmpty && tokens.contains { token in Self.words(lower).contains { Self.same($0, token) } })
        }
        if scope != .contacts {
            for design in publishedApps where hits(design.appTitle ?? design.name) {
                let format = DesignFormat.from(design.outputFormat) ?? (design.pages.count > 1 ? .pdf : .png)
                result.append(LaunchSuggestion(id: "app:" + design.id, kind: .app, title: design.appTitle ?? design.name, subtitle: "App \u{00B7} makes \(format.title)", symbol: "paintpalette.fill", designID: design.id))
            }
        }
        if scope != .apps {
            let pool = scope == .contacts ? people() : AppDesignContext.shared.records
            let matching = pool.filter { hits($0.name) || (!$0.alias.isEmpty && hits($0.alias)) }
            for record in matching.prefix(scope == .contacts ? 12 : 5) {
                result.append(LaunchSuggestion(id: "rec:" + record.id, kind: .contact, title: record.name, subtitle: record.collection, symbol: "person.crop.circle", recordID: record.id))
            }
        }
        if scope == .everything && !query.isEmpty {
            for clip in AppDesignContext.shared.clips where hits(clip.key) || hits(clip.name) {
                result.append(LaunchSuggestion(id: "clip:" + clip.id.uuidString, kind: .shortcut, title: clip.key, subtitle: clip.name, symbol: "bolt", clipKey: clip.key))
                if result.filter({ $0.kind == .shortcut }).count >= 4 { break }
            }
        }
        return Array(result.prefix(14))
    }

    // MARK: Doing it

    /// A typed or spoken line. Returns true when it was handled here.
    @discardableResult func handle(_ raw: String, spoken: Bool = false) -> Bool {
        let (scope, text) = Self.split(raw)
        guard !text.isEmpty else { return false }
        switch scope {
        case .apps:
            if let found = matchApp(in: text) { open(design: found.design, prompt: found.rest); return true }
            return false
        case .contacts:
            let query = text.lowercased()
            if let record = people().first(where: { $0.name.lowercased() == query || $0.alias.lowercased() == query }) ?? people().first(where: { $0.name.lowercased().contains(query) }) {
                show(contact: record)
                return true
            }
            return false
        case .everything:
            if Self.hasVerb(text), let found = matchApp(in: text) { open(design: found.design, prompt: found.rest); return true }
            if !spoken, let first = suggestions(for: raw).first { return act(first) }
            return false
        }
    }

    @discardableResult func act(_ item: LaunchSuggestion) -> Bool {
        switch item.kind {
        case .app:
            guard let id = item.designID, let design = AppDesignStore.shared.design(id: id) else { return false }
            open(design: design, prompt: "")
        case .contact:
            guard let id = item.recordID, let record = AppDesignContext.shared.records.first(where: { $0.id == id }) else { return false }
            show(contact: record)
        case .shortcut:
            guard let key = item.clipKey, let clip = AppDesignContext.shared.clips.first(where: { $0.key == key }) else { return false }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(clip.text, forType: .string)
        }
        return true
    }

    func open(design: AppDesign, prompt: String) {
        let id = design.id
        present(title: design.appTitle ?? design.name, size: NSSize(width: 980, height: 680)) { close in
            AnyView(AppDesignRunView(designID: id, onClose: { close() }, startPrompt: prompt.isEmpty ? nil : prompt))
        }
    }

    func show(contact: CollectionRecord) {
        present(title: contact.name, size: NSSize(width: 420, height: 460)) { close in
            AnyView(ContactCardView(record: contact, onClose: close))
        }
    }

    private func present(title: String, size: NSSize, content: (@escaping () -> Void) -> AnyView) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.delegate = self
        let close: () -> Void = { [weak window] in window?.close() }
        window.contentView = NSHostingView(rootView: content(close))
        window.center()
        windows.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === window }
    }
}

struct ContactCardView: View {
    var record: CollectionRecord
    var onClose: () -> Void
    @State private var copied = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 34)).foregroundStyle(Butter.coral)
                VStack(alignment: .leading) {
                    Text(record.name).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Butter.cocoa)
                    Text(record.collection).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { onClose() }.buttonStyle(.bordered)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(record.values.keys.sorted(), id: \.self) { field in
                        HStack(alignment: .top) {
                            Text(field).font(.system(size: 12, weight: .semibold)).frame(width: 110, alignment: .leading)
                            Text(record.values[field] ?? "").font(.system(size: 13)).textSelection(.enabled)
                            Spacer()
                            Button { copy(record.values[field] ?? "", field) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if !copied.isEmpty { Text("Copied \(copied).").font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        .padding(18).background(Butter.butter)
    }

    private func copy(_ value: String, _ field: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = field
    }
}
