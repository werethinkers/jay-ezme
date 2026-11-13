// Create an AppBuilder app in one step: say what it should make (an NDA, a thank-you card, an invoice),
// and optionally choose a sample image. The AI reads the sample's layout and which parts change, never its
// text, and fills in the app's name, shortcut prefix, fields and instructions. Without an API key a
// simple app is made from the words alone and can be edited afterwards.
import SwiftUI
import AppKit

struct AppBlueprint {
    var name: String
    var prefix: String
    var variables: [String]
    var format: String
    var prompt: String
}

enum AppBlueprintMaker {
    /// The AI profile and key chosen in API configuration, if any.
    static func profileAndKey() -> (CollectionAIModelProfile, String)? {
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: "ezmeSelectedAIModelProfile") ?? defaults.string(forKey: "ezmeCollectionSelectedProfile") ?? CollectionAIModelProfile.starter.id
        let profiles = AIModelProfileStore.load()
        guard let profile = profiles.first(where: { $0.id == id }) ?? profiles.first,
              let key = KeyStore.load(account: profile.keyAccount), !key.isEmpty else { return nil }
        return (profile, key)
    }

    static func slug(_ text: String, limit: Int) -> String {
        String(text.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression).prefix(limit))
    }

    static func titled(_ text: String) -> String {
        let words = text.replacingOccurrences(of: "[^A-Za-z0-9 ]+", with: " ", options: .regularExpression).split(separator: " ").prefix(4)
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// An app made from the words alone, when there is no AI key or the AI did not answer.
    static func fallback(request: String, imagePath: String?) -> AppBlueprint {
        let base = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let fromImage = imagePath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? ""
        var name = titled(base.isEmpty ? fromImage : base)
        if name.isEmpty { name = "My App" }
        let visual = imagePath != nil
        let variables = ["Name", "Date", "Details"]
        let list = variables.map { "\($0): {{\($0.lowercased())}}" }.joined(separator: "\n")
        let prompt = visual
            ? "Create a new design that follows the layout, colours and style of the reference image, but do not copy any of its text. Write new text from these details.\n\(list)"
            : "\(base.isEmpty ? name : base)\n\n\(list)"
        return AppBlueprint(name: name, prefix: slug(name, limit: 8), variables: variables, format: visual ? "Image" : "PDF", prompt: prompt)
    }

    /// Asks the AI for the blueprint. The image, when given, is only a design reference.
    static func draft(request: String, imagePath: String?) async -> AppBlueprint {
        guard let (profile, key) = profileAndKey() else { return fallback(request: request, imagePath: imagePath) }
        var images: [(Data, String)] = []
        if let imagePath, let data = try? Data(contentsOf: URL(fileURLWithPath: imagePath)) {
            let ext = URL(fileURLWithPath: imagePath).pathExtension.lowercased()
            images = [(data, ext == "png" ? "image/png" : (ext == "webp" ? "image/webp" : (ext == "gif" ? "image/gif" : "image/jpeg")))]
        }
        let wanted = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let sample = images.isEmpty ? "" : "An image is attached: it is a sample of the design they want. Read its layout and which parts change from one copy to the next. Do not copy any of its text or personal details.\n"
        let ask = """
        You design small reusable apps for a shortcut tool. The user wants an app for: "\(wanted.isEmpty ? "the design in the attached image" : wanted)".
        \(sample)Reply with JSON only, no other text:
        {"name": "short app name, 2 to 4 words",
         "prefix": "lowercase letters or digits, up to 8 characters",
         "variables": ["up to 6 short field names someone fills in each time, for example Customer, Date, Amount"],
         "format": "PDF or Image or Text",
         "prompt": "instructions for making one result"}
        Use "Image" for greeting cards, posters, infographics, badges, or when a sample image is a visual design. Use "PDF" for letters, agreements, invoices, bills and forms. Use "Text" for messages and replies.
        In the prompt, write each variable as {{name}} in lowercase with spaces removed. If an image is attached, tell the maker to follow its layout, colours and style, to write new text from the variables, and never to copy the sample's text.
        """
        do {
            let reply = try await SharedAIClient.generate(profile: profile, key: key, prompt: ask, images: images, maxTokens: 900)
            guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
                  let object = try? JSONSerialization.jsonObject(with: Data(reply[start...end].utf8)) as? [String: Any] else {
                return fallback(request: request, imagePath: imagePath)
            }
            let name = titled((object["name"] as? String) ?? "")
            let variables = ((object["variables"] as? [String]) ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(6)
            let format = ["PDF", "Image", "Text"].first { $0.caseInsensitiveCompare((object["format"] as? String) ?? "") == .orderedSame } ?? (imagePath != nil ? "Image" : "PDF")
            let prompt = ((object["prompt"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !prompt.isEmpty else { return fallback(request: request, imagePath: imagePath) }
            let prefix = slug((object["prefix"] as? String) ?? name, limit: 8)
            return AppBlueprint(name: name, prefix: prefix.isEmpty ? slug(name, limit: 8) : prefix, variables: variables.isEmpty ? ["Name", "Date", "Details"] : Array(variables), format: format, prompt: prompt)
        } catch {
            return fallback(request: request, imagePath: imagePath)
        }
    }

    /// Saves the app under the settings the AppBuilder reads, and returns its final name.
    static func install(_ blueprint: AppBlueprint, imagePath: String?) -> String {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: "ezmeCustomBuilderAppsJSON") ?? "[]"
        var apps = (try? JSONDecoder().decode([String].self, from: Data(stored.utf8))) ?? []
        var name = blueprint.name
        var suffix = 2
        while apps.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { name = "\(blueprint.name) \(suffix)"; suffix += 1 }
        var taken = Set<String>()
        for app in apps {
            let fallback = slug(app, limit: 12)
            taken.insert((defaults.string(forKey: "ezmeBuilderPrefix." + app) ?? fallback).lowercased())
        }
        var prefix = blueprint.prefix.isEmpty ? slug(name, limit: 8) : blueprint.prefix
        var digit = 2
        let basePrefix = prefix
        while taken.contains(prefix.lowercased()) { prefix = basePrefix + String(digit); digit += 1 }
        AppDeletion.restore(name)
        apps.append(name)
        defaults.set(String(decoding: (try? JSONEncoder().encode(apps)) ?? Data("[]".utf8), as: UTF8.self), forKey: "ezmeCustomBuilderAppsJSON")
        var created = defaults.stringArray(forKey: "ezmeUserCreatedBuilderApps") ?? []
        created.append(name)
        defaults.set(created, forKey: "ezmeUserCreatedBuilderApps")
        defaults.set(blueprint.prompt, forKey: "ezmeBuilderPrompt." + name)
        defaults.set(blueprint.prompt, forKey: "ezmeBuilderDescription." + name)
        defaults.set(prefix, forKey: "ezmeBuilderPrefix." + name)
        defaults.set(blueprint.variables.joined(separator: ", "), forKey: "ezmeBuilderVariables." + name)
        defaults.set("", forKey: "ezmeBuilderCollections." + name)
        defaults.set("", forKey: "ezmeBuilderOutputCollections." + name)
        defaults.set("Modern", forKey: "ezmeBuilderTemplate." + name)
        defaults.set(blueprint.format, forKey: "ezmeBuilderFormat." + name)
        if let imagePath, let kept = keepCopy(of: imagePath) { defaults.set(kept, forKey: "ezmeBuilderAsset." + name) }
        return name
    }

    /// The sample image is copied next to the app's data so it still works if the original moves.
    private static func keepCopy(of path: String) -> String? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("KeyDo/AppSamples", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = URL(fileURLWithPath: path)
        let target = folder.appendingPathComponent(UUID().uuidString + "." + (source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()))
        do { try FileManager.default.copyItem(at: source, to: target); return target.path } catch { return nil }
    }
}

/// Two steps in one window. First say or type what the app makes (keep talking, it all adds up, then say "create").
/// Then KeyDo asks for each detail the new app needs, one box at a time, by voice or typing, and can make the first result.
struct QuickCreateAppSheet: View {
    let onClose: () -> Void
    let onCreated: (String) -> Void

    @StateObject private var voice = WishVoiceController()
    @State private var request = ""
    @State private var imagePath: String?
    @State private var busy = false
    @State private var note = ""
    // Second step
    @State private var made: AppBlueprint?
    @State private var madeName = ""
    @State private var answers: [String] = []
    @State private var step = 0
    @FocusState private var focused: Int?

    private let examples = ["Send an NDA to a client", "Thank-you card with a name", "Invoice for a customer", "Polite payment reminder"]
    private let finishWords: Set<String> = ["create", "create app", "create it", "create the app", "make it", "make the app", "done", "that is all", "thats all", "that's all", "go"]

    var body: some View {
        Group {
            if let made { fillView(made) } else { describeView }
        }
        .padding(22)
        .frame(width: 580)
        .onDisappear { voice.stop() }
    }

    // MARK: Step 1

    private var describeView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Create an app").font(.system(size: 23, weight: .bold, design: .rounded))
                Spacer()
                Button { voice.stop(); onClose() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
            HStack {
                Text("What should it make?").font(.headline)
                Spacer()
                Button(voice.isListening ? "Stop talking" : "Talk to create", systemImage: voice.isListening ? "stop.circle.fill" : "mic.fill") { toggleDescribeVoice() }
                    .buttonStyle(.bordered)
                    .tint(voice.isListening ? .red : Butter.coral)
            }
            TextField("Example: Send an NDA to a client", text: $request, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            if voice.isListening {
                Text(voice.heard.isEmpty ? "Listening. Keep talking, then say \u{201C}create\u{201D}." : voice.heard).font(.caption).foregroundStyle(Butter.coral)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(examples, id: \.self) { example in
                        Button(example) { request = example }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
            Text("Have a sample? (optional)").font(.headline)
            HStack(spacing: 12) {
                if let imagePath, let image = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: 74, height: 74).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Button(imagePath == nil ? "Choose a sample image" : "Choose another", systemImage: "photo.badge.plus") { chooseImage() }
                    Text("A card, poster, invoice or form you like. KeyDo follows its layout and colours and never copies its text.").font(.caption).foregroundStyle(.secondary)
                    if imagePath != nil { Button("Remove sample") { imagePath = nil }.buttonStyle(.link).font(.caption) }
                }
            }
            if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.orange) }
            HStack {
                Text(AppBlueprintMaker.profileAndKey() == nil ? "No API key yet: a simple app is made from your words. You can edit it afterwards." : "Next, KeyDo asks for the details and can make the first result.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(busy ? "Creating\u{2026}" : "Create app", systemImage: "sparkles") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || (request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imagePath == nil))
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose a sample image"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { imagePath = url.path }
    }

    private func clean(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
    }

    private func toggleDescribeVoice() {
        if voice.isListening { voice.stop(); return }
        voice.start(localeIdentifier: "en-IN", commitDelay: 1.2) { sentence in
            Task { @MainActor in handleDescribe(sentence) }
        }
    }

    private func handleDescribe(_ sentence: String) {
        let spoken = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty, made == nil else { return }
        let lower = clean(spoken)
        if finishWords.contains(lower) { create(); return }
        if ["clear", "start again", "clear all"].contains(lower) { request = ""; return }
        request += (request.isEmpty ? "" : " ") + spoken
    }

    private func create() {
        guard !busy else { return }
        let keepTalking = voice.isListening
        voice.stop()
        busy = true
        note = ""
        let wanted = request
        let sample = imagePath
        Task { @MainActor in
            let blueprint = await AppBlueprintMaker.draft(request: wanted, imagePath: sample)
            let name = AppBlueprintMaker.install(blueprint, imagePath: sample)
            busy = false
            madeName = name
            answers = Array(repeating: "", count: blueprint.variables.count)
            step = 0
            made = blueprint
            focused = 0
            if keepTalking { startFillVoice() }
        }
    }

    // MARK: Step 2

    private func fillView(_ blueprint: AppBlueprint) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Now the details").font(.system(size: 23, weight: .bold, design: .rounded))
                Spacer()
                Button { finish(generate: false) } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
            Text("\u{201C}\(madeName)\u{201D} is ready. Tell KeyDo each detail, one box at a time, by voice or typing. Say next to skip, back to go back, make it when you are done.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blueprint.variables.enumerated()), id: \.offset) { position, label in
                    HStack(spacing: 10) {
                        Text(position == step ? "\u{25B6}" : " ").foregroundStyle(Butter.coral).frame(width: 14)
                        Text(label).font(.system(size: 13, weight: .semibold)).frame(width: 120, alignment: .leading)
                        TextField(position == step ? "Say or type the \(label.lowercased())" : "", text: answerBinding(position))
                            .textFieldStyle(.roundedBorder)
                            .focused($focused, equals: position)
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 9).fill(position == step ? Butter.coral.opacity(0.12) : Color.clear))
                }
            }
            .onChange(of: focused) { newValue in if let newValue { step = newValue } }
            if voice.isListening {
                Text(voice.heard.isEmpty ? "Listening for \(currentLabel(blueprint).lowercased())\u{2026}" : voice.heard).font(.caption).foregroundStyle(Butter.coral)
            }
            HStack {
                Button(voice.isListening ? "Stop talking" : "Answer by voice", systemImage: voice.isListening ? "stop.circle.fill" : "mic.fill") {
                    if voice.isListening { voice.stop() } else { startFillVoice() }
                }
                .buttonStyle(.bordered)
                .tint(voice.isListening ? .red : Butter.coral)
                Spacer()
                Button("Skip for now") { finish(generate: false) }
                Button("Make it", systemImage: "sparkles") { finish(generate: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(answers.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }
        }
    }

    private func currentLabel(_ blueprint: AppBlueprint) -> String {
        step < blueprint.variables.count ? blueprint.variables[step] : "the details"
    }

    private func answerBinding(_ position: Int) -> Binding<String> {
        Binding(get: { position < answers.count ? answers[position] : "" }, set: { if position < answers.count { answers[position] = $0 } })
    }

    private func startFillVoice() {
        voice.stop()
        voice.start(localeIdentifier: "en-IN", commitDelay: 1.1) { sentence in
            Task { @MainActor in handleFill(sentence) }
        }
    }

    private func handleFill(_ sentence: String) {
        guard let blueprint = made else { return }
        let spoken = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        let lower = clean(spoken)
        if finishWords.contains(lower) || lower == "generate" { finish(generate: !answers.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }); return }
        if ["next", "skip", "next one", "next box"].contains(lower) { move(to: step + 1, in: blueprint); return }
        if ["back", "previous", "go back"].contains(lower) { move(to: max(0, step - 1), in: blueprint); return }
        if ["clear", "clear this", "delete"].contains(lower), step < answers.count { answers[step] = ""; return }
        // "<box name> is <answer>"
        for (position, label) in blueprint.variables.enumerated() {
            let key = clean(label)
            for joiner in [" is ", " as ", " to ", ": ", " equals "] where lower.hasPrefix(key + joiner) {
                let answer = String(spoken.dropFirst(key.count + joiner.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if position < answers.count { answers[position] = answer }
                move(to: position + 1, in: blueprint)
                return
            }
        }
        guard step < answers.count else { return }
        answers[step] = spoken.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
        move(to: step + 1, in: blueprint)
    }

    private func move(to next: Int, in blueprint: AppBlueprint) {
        if next >= blueprint.variables.count {
            step = blueprint.variables.count - 1
            note = "That was the last box."
        } else {
            step = next
            focused = next
        }
    }

    /// Closes the window. With generate, KeyDo also makes the first result from the answers.
    private func finish(generate: Bool) {
        voice.stop()
        if generate, !answers.isEmpty, answers.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let prefix = UserDefaults.standard.string(forKey: "ezmeBuilderPrefix." + madeName) ?? ""
            let parts = answers.map { $0.replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            if !prefix.isEmpty {
                NotificationCenter.default.post(name: .ezmeBuilderGenerateShortcut, object: nil, userInfo: ["trigger": "\\" + prefix + "-" + parts.joined(separator: "-")])
            }
        }
        onCreated(madeName)
    }
}
