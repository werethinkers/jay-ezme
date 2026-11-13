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

/// One window: say what the app makes, optionally add a sample image, press Create.
struct QuickCreateAppSheet: View {
    let onClose: () -> Void
    let onCreated: (String) -> Void

    @State private var request = ""
    @State private var imagePath: String?
    @State private var busy = false
    @State private var note = ""

    private let examples = ["Send an NDA to a client", "Thank-you card with a name", "Invoice for a customer", "Polite payment reminder"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Create an app").font(.system(size: 23, weight: .bold, design: .rounded))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
            Text("What should it make?").font(.headline)
            TextField("Example: Send an NDA to a client", text: $request, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
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
                Text(AppBlueprintMaker.profileAndKey() == nil ? "No API key yet: a simple app is made from your words. You can edit it afterwards." : "The app's name, shortcut, fields and instructions are filled in for you.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(busy ? "Creating…" : "Create app", systemImage: "sparkles") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || (request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imagePath == nil))
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose a sample image"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { imagePath = url.path }
    }

    private func create() {
        busy = true
        note = ""
        let wanted = request
        let sample = imagePath
        Task { @MainActor in
            let blueprint = await AppBlueprintMaker.draft(request: wanted, imagePath: sample)
            let name = AppBlueprintMaker.install(blueprint, imagePath: sample)
            busy = false
            onCreated(name)
        }
    }
}
