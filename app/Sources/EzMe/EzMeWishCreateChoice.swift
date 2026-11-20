import SwiftUI

/// "Create an app" in Wish Studio: describe it, start blank, or copy an app you already have.
struct WishCreateChoiceSheet: View {
    @ObservedObject var model: WishStudioModel
    @ObservedObject var store: WishStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "prompt"
    @State private var prompt = ""
    @State private var baseID = ""
    @State private var copyID = ""
    @State private var busy = false
    @State private var message = ""

    private var bases: [WishApp] { store.apps }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Create an app").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(.bordered)
            }
            Picker("", selection: $mode) {
                Text("From a prompt").tag("prompt")
                Text("Blank").tag("blank")
                Text("Duplicate an app").tag("copy")
            }.pickerStyle(.segmented).labelsHidden()
            switch mode {
            case "prompt":
                Text("Say what you want, for example \u{201C}anniversary card for my wife, warm and romantic\u{201D}. KeyDo copies the app you choose as the template and changes the name, heading and sign-off to match.")
                    .font(.callout).foregroundStyle(WishTheme.muted)
                TextEditor(text: $prompt).font(.system(size: 13)).frame(height: 90).padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WishTheme.line))
                Picker("Template app", selection: $baseID) {
                    Text("None, start fresh").tag("")
                    ForEach(bases) { item in Text(item.name).tag(item.id) }
                }
                Button { Task { await createFromPrompt() } } label: { Label(busy ? "Building\u{2026}" : "Build the app", systemImage: "wand.and.stars") }
                    .buttonStyle(.borderedProminent).tint(Butter.coral).disabled(busy || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case "copy":
                Text("Make a copy of an app, with its fields, then change it.").font(.callout).foregroundStyle(WishTheme.muted)
                Picker("App to copy", selection: $copyID) {
                    Text("Choose\u{2026}").tag("")
                    ForEach(bases) { item in Text(item.name).tag(item.id) }
                }
                Button { duplicate() } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                    .buttonStyle(.borderedProminent).tint(Butter.coral).disabled(copyID.isEmpty)
            default:
                Text("Open the WishBuilder and set up an app yourself. The four default designs are ready, so you can skip step 1.")
                    .font(.callout).foregroundStyle(WishTheme.muted)
                Button { dismiss(); model.openBuilder() } label: { Label("Open WishBuilder", systemImage: "square.and.pencil") }
                    .buttonStyle(.borderedProminent).tint(Butter.coral)
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(WishTheme.muted) }
        }
        .padding(22).frame(width: 540)
    }

    private func duplicate() {
        guard let id = store.duplicateApp(copyID) else { return }
        carryLooks(from: copyID, to: id)
        model.status = "Made a copy: \(store.app(id: id)?.name ?? "")."
        dismiss()
        model.openApp(id)
    }

    /// The new app starts with the same artwork options, so it is ready for step 2.
    private func carryLooks(from source: String, to target: String) {
        let defaults = UserDefaults.standard
        let files = WishLookStore.files(source)
        if !files.isEmpty { defaults.set(files, forKey: "wishLooks." + target) }
        for key in ["wishHeading.", "wishSender.", "wishExample.", "wishBrief.", "wishBackground."] {
            if let value = defaults.string(forKey: key + source) { defaults.set(value, forKey: key + target) }
        }
    }

    private struct Plan { var name: String; var heading: String; var tagline: String; var sender: String }

    private func fallbackPlan(_ text: String) -> Plan {
        let stop: Set<String> = ["a", "an", "the", "for", "my", "me", "make", "create", "build", "app", "card", "to", "of", "and", "with", "please"]
        let words = text.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty && !stop.contains($0.lowercased()) }
        let title = words.prefix(2).map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
        let name = title.isEmpty ? "New wish" : title
        return Plan(name: name, heading: name, tagline: text, sender: "")
    }

    private func askAI(_ text: String, base: WishApp?) async -> Plan? {
        let profiles = AIModelProfileStore.load()
        let selectedID = UserDefaults.standard.string(forKey: "ezmeSelectedAIModelProfile") ?? UserDefaults.standard.string(forKey: "ezmeCollectionSelectedProfile") ?? CollectionAIModelProfile.starter.id
        let profile = profiles.first(where: { $0.id == selectedID }) ?? .starter
        let key = KeyStore.load(account: profile.keyAccount) ?? ""
        guard !key.isEmpty else { return nil }
        let basis = base.map { "It is based on an existing app called \($0.name)." } ?? "It is a new greeting app."
        let instruction = "Plan a small greeting card app. \(basis) The person asked: \(text)\nAnswer with one JSON object and nothing else, using the keys name (2 or 3 words), heading (the big line on the card, a few words), tagline (one short sentence) and sender (a short sign-off such as With love). No markdown."
        guard let reply = try? await SharedAIClient.generate(profile: profile, key: key, prompt: instruction, maxTokens: 400),
              let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"),
              let data = String(reply[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let name = (object["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return Plan(name: name, heading: (object["heading"] as? String) ?? name, tagline: (object["tagline"] as? String) ?? "", sender: (object["sender"] as? String) ?? "")
    }

    private func createFromPrompt() async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        message = "Asking the AI to plan the app\u{2026}"
        defer { busy = false }
        let base = bases.first { $0.id == baseID }
        let ai = await askAI(text, base: base)
        let plan = ai ?? fallbackPlan(text)
        var newID: String?
        if let base, let copyID = store.duplicateApp(base.id) {
            newID = copyID
            carryLooks(from: base.id, to: copyID)
        } else {
            var fresh = WishApp(name: DesignNames.unique(plan.name, taken: store.apps.map { $0.name }))
            fresh.kind = .greeting
            store.apps.append(fresh)
            newID = fresh.id
        }
        guard let id = newID, var made = store.app(id: id) else { message = "Could not make the app."; return }
        made.name = DesignNames.unique(plan.name, taken: store.apps.filter { $0.id != id }.map { $0.name })
        if !plan.tagline.isEmpty { made.tagline = plan.tagline }
        made.prompt = text
        store.updateApp(made)
        UserDefaults.standard.set(plan.heading, forKey: "wishHeading." + id)
        if !plan.sender.isEmpty { UserDefaults.standard.set("From " + plan.sender, forKey: "wishSender." + id) }
        model.status = ai == nil ? "Built \(made.name). Add an API key in API configuration to let the AI write the words." : "Built \(made.name) from your prompt."
        dismiss()
        model.openApp(id)
    }
}
