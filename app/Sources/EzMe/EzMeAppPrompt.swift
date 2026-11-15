// One prompt for every app. Type or say what you want ("Send Diwali greetings to Rohit", "write an invoice reminder")
// and KeyDo finds the app: one you built, a Wish Studio app, or an Ezyourlife app. Several fit: your own apps first
// (they cost no credits), then the cheapest Ezyourlife app, then the first match. The other matches stay one tap away.
import SwiftUI

struct AppPromptChoice: Identifiable, Hashable {
    enum Kind: Hashable { case builder(String), ezy(String) }
    var kind: Kind
    var title: String
    var detail: String
    /// 0 for your own apps. Ezyourlife apps show their credits.
    var credits: Int
    var id: String {
        switch kind {
        case .builder(let name): return "b:" + name
        case .ezy(let id): return "e:" + id
        }
    }
}

struct AppPromptPlan {
    var choices: [AppPromptChoice] = []
    /// The sentence turned into an app command such as `diwali-Rohit`, when one of your apps matched.
    var command: String? = nil
    var complete = false
    var primary: AppPromptChoice? { choices.first }
}

@MainActor
enum AppPromptResolver {
    private static let builtIns: [(name: String, words: [String])] = [
        ("Collection Builder", ["collection builder", "build a collection", "new collection"]),
        ("MyDatabase", ["mydatabase", "my database", "database"]),
        ("Prompt Builder", ["prompt builder"]),
    ]

    /// `=date` and `=time` in the sentence become today's date and the time, the same as in Prompt Builder.
    static func expandFunctions(_ text: String) -> String {
        var out = text
        for info in LiveValues.catalog {
            let name = info.token.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
            guard !name.isEmpty, out.localizedCaseInsensitiveContains("=" + name) else { continue }
            out = out.replacingOccurrences(of: "=" + name, with: LiveValues.expand(info.token), options: .caseInsensitive)
        }
        return out
    }

    static func resolve(_ raw: String, apps: [String], clips: [Clip], records: [CollectionRecord]) -> AppPromptPlan {
        let sentence = expandFunctions(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return AppPromptPlan() }
        let lower = sentence.lowercased()
        var plan = AppPromptPlan()

        // 1. An app you built or a Wish Studio app, by its phrases and prefix.
        let rewritten = keydoSpokenAppCommand(sentence, clips: clips, records: records)
        if let command = customBuilderCommand(rewritten, clips: clips, records: records) {
            plan.command = rewritten
            plan.complete = command.isComplete
            plan.choices.append(AppPromptChoice(kind: .builder(command.app), title: command.app, detail: command.isComplete ? "Your app · free" : "Your app · needs a detail", credits: 0))
        }

        // 2. The built-in apps, when named.
        if plan.choices.isEmpty {
            for builtIn in builtIns where builtIn.words.contains(where: { lower.contains($0) }) {
                plan.choices.append(AppPromptChoice(kind: .builder(builtIn.name), title: builtIn.name, detail: "Built-in · free", credits: 0))
            }
        }

        // 3. Other apps of yours that share words with the sentence.
        let sentenceWords = Set(lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        for app in apps where !plan.choices.contains(where: { $0.id == "b:" + app }) {
            let keys = BuilderPhrases.keywords(for: app)
            if !keys.isDisjoint(with: sentenceWords) {
                plan.choices.append(AppPromptChoice(kind: .builder(app), title: app, detail: "Your app · free", credits: 0))
            }
            if plan.choices.count >= 3 { break }
        }

        // 4. Ezyourlife apps. Within the best matches the cheapest in credits comes first; ties keep the original order.
        let ezy = Ezyourlife.shared.rank(sentence, limit: 3)
        let ranked = ezy.enumerated().sorted { a, b in
            let ca = a.element.credits ?? 99, cb = b.element.credits ?? 99
            return ca != cb ? ca < cb : a.offset < b.offset
        }.map { $0.element }
        for app in ranked {
            plan.choices.append(AppPromptChoice(kind: .ezy(app.id), title: app.name, detail: "Ezyourlife · \(ezyCredits(app.credits))", credits: app.credits ?? 99))
        }
        return plan
    }
}

struct AppPromptBar: View {
    var apps: [String]
    var clips: [Clip]
    var records: [CollectionRecord]
    var openApp: (String) -> Void

    @State private var text = ""
    @State private var plan = AppPromptPlan()
    @State private var picked: String? = nil
    @State private var status = ""
    @State private var working = false
    @FocusState private var focused: Bool

    private var ordered: [AppPromptChoice] {
        guard let picked, let choice = plan.choices.first(where: { $0.id == picked }) else { return plan.choices }
        return [choice] + plan.choices.filter { $0.id != picked }
    }

    private func analyse() {
        plan = AppPromptResolver.resolve(text, apps: apps, clips: clips, records: records)
        picked = nil
    }

    private func go(autoVoice: Bool = false) {
        analyse()
        guard let choice = ordered.first else {
            status = "No app matched. Try “Send Diwali greetings to Rohit”, or browse the apps below."
            return
        }
        switch choice.kind {
        case .builder(let name):
            if plan.complete, let command = plan.command, choice.id == plan.primary?.id {
                let trigger = command.hasPrefix("\\") ? command : "\\" + command
                working = true
                status = "Making it with \(name)… the result is saved as a shortcut and ready in the popup."
                NotificationCenter.default.post(name: .ezmeBuilderGenerateShortcut, object: nil, userInfo: ["trigger": trigger])
            } else {
                if autoVoice { status = "Opened \(name). Add the missing detail and run it."; }
                else { status = "Opened \(name). Fill in the details and run it." }
                openApp(name)
            }
        case .ezy(let id):
            let clip = ezyClip(id: id, name: choice.title)
            EzyRunPanel.shared.open(clip: clip, removeCount: 0, returnApp: nil)
            status = "Opened \(choice.title) from Ezyourlife."
        }
    }

    private func ezyClip(id: String, name: String) -> Clip {
        var clip = Clip(key: "/ezy-" + id, name: name, text: "", group: EzyConfig.collection)
        clip.webURL = "ezyourlife://app/\(id)"
        return clip
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Butter.coral)
                TextField("Say or type what you want, for example “Send Diwali greetings to Rohit”", text: $text, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 15)).lineLimit(1...3)
                    .focused($focused)
                    .onSubmit { go() }
                    .onChange(of: text) { _ in analyse(); if !working { status = "" } }
                VoiceDictationButton(onTranscript: { spoken in
                    text = spoken
                    analyse()
                    if let first = plan.primary, case .builder(let name) = first.kind, plan.complete, BuilderPhrases.runsByItself(name) { go(autoVoice: true) }
                }, onPartial: { text = $0 })
                Button { go() } label: { Label("Go", systemImage: "arrow.right.circle.fill") }
                    .buttonStyle(.borderedProminent).tint(Butter.coral)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(focused ? Butter.coral : Butter.coral.opacity(0.25), lineWidth: focused ? 2 : 1))
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if ordered.isEmpty {
                    Label("No app found for this yet. Keep typing, or browse below.", systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        Text("WILL USE").font(.system(size: 10, weight: .heavy)).foregroundStyle(.tertiary)
                        ForEach(Array(ordered.prefix(4).enumerated()), id: \.element.id) { index, choice in
                            Button { picked = choice.id } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: index == 0 ? "checkmark.circle.fill" : "circle").font(.system(size: 11))
                                    Text(choice.title).font(.system(size: 12, weight: .semibold))
                                    Text(choice.detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(index == 0 ? Butter.coral.opacity(0.14) : Color.white.opacity(0.85), in: Capsule())
                                .overlay(Capsule().stroke(Butter.coral.opacity(index == 0 ? 0.5 : 0.18)))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            if !status.isEmpty { Label(status, systemImage: "info.circle.fill").font(.caption).foregroundStyle(Butter.cocoa) }
            else if text.isEmpty { Text("Works with your apps, Wish Studio apps and Ezyourlife apps. Use =date for today's date.").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(14)
        .background(Butter.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Butter.coral.opacity(0.16)))
        .task { await Ezyourlife.shared.refreshCatalogue() }
        .onReceive(NotificationCenter.default.publisher(for: .ezmeBuilderGenerationFinished)) { note in
            working = false
            if let message = note.userInfo?["status"] as? String, !message.isEmpty { status = message }
        }
    }
}
