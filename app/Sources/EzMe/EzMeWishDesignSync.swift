// Wish Studio and the designer on one page: every variable, collection and text box of the design becomes a field of
// the Wish app, so typing in Details changes the card at once (as the Try it side did in App Designer).
import SwiftUI
import AppKit
import Combine

private struct DesignEmbeddedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True when the designer sits inside Wish Studio, which then owns Launch, closing and the app name.
    var designEmbedded: Bool {
        get { self[DesignEmbeddedKey.self] }
        set { self[DesignEmbeddedKey.self] = newValue }
    }
}

@MainActor enum WishDesignSync {
    private static func label(_ key: String) -> String {
        let spaced = key.replacingOccurrences(of: "[_\\-]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    /// Adds a Wish field for every variable and text box of the design that has none yet. Returns how many were added.
    @discardableResult static func sync(_ model: WishStudioModel) -> Int {
        guard let id = WishAppLink.designID(model), let design = AppDesignStore.shared.design(id: id) else { return 0 }
        var app = model.app
        var added = 0
        func add(_ key: String, type: WishFieldType, value: String, placeholder: String) {
            let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, app.field(clean) == nil else { return }
            var field = WishField(key: clean, label: label(clean), type: type)
            field.value = value
            field.placeholder = placeholder
            app.fields.append(field)
            added += 1
        }
        for name in DesignDataType.names(design.variables) {
            let kind = DesignDataType.of(name, in: design.variables)
            let type: WishFieldType = kind == .long ? .longText : kind == .date ? .date : (kind == .number || kind == .whole || kind == .currency) ? .number : .text
            add(name, type: type, value: design.variables[name] ?? "", placeholder: kind.example)
        }
        for page in design.pages {
            guard let template = TemplateStore.shared.template(id: page) else { continue }
            for slot in template.slots where slot.kind == .text { add(slot.key, type: .text, value: "", placeholder: slot.sample) }
        }
        guard added > 0 else { return 0 }
        model.store.updateApp(app)
        model.objectWillChange.send()
        return added
    }

    static func launch(_ model: WishStudioModel) -> String {
        guard let id = WishAppLink.designID(model) else { return "Choose a background first." }
        let message = AppDesignStore.shared.release(id)
        sync(model)
        model.status = "Launched. Colours and looks can still be changed by voice."
        return message
    }
}

// MARK: - The one bar at the top of Wish Studio

struct WishModeBar: View {
    @ObservedObject var model: WishStudioModel
    @ObservedObject private var designs = AppDesignStore.shared
    @State private var message = ""

    private var selection: Binding<Int> {
        Binding(
            get: { model.designAll ? 2 : (model.designMode ? 0 : 1) },
            set: { value in
                model.designAll = value == 2
                model.designMode = value != 1
                if value == 1 { DispatchQueue.main.async { WishDesignSync.sync(model) } }
            }
        )
    }

    private var hasDesign: Bool { designs.design(id: WishAppLink.designID(model)) != nil }

    var body: some View {
        HStack(spacing: 12) {
            Picker("", selection: selection) {
                Label("Design", systemImage: "paintbrush.pointed").tag(0)
                Label("Card", systemImage: "rectangle.portrait").tag(1)
                Label("All designs", systemImage: "rectangle.stack").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 330)
            Text(model.designAll ? "Every design and template. Open one to edit it here."
                 : model.designMode ? "Background, boxes, positions and the app name. Press Card to try your words."
                 : "Type in Details and the card changes as you type. Colours and sizes work by voice.")
                .font(.system(size: 11)).foregroundStyle(WishTheme.muted).lineLimit(1)
            Spacer()
            if !message.isEmpty { Text(message).font(.system(size: 11)).foregroundStyle(WishTheme.muted).lineLimit(1) }
            if hasDesign {
                Button { message = WishDesignSync.launch(model) } label: { Label("Launch", systemImage: "paperplane.fill") }
                    .buttonStyle(.borderedProminent).tint(WishTheme.accent)
                    .help("Publishes this design as the app. Cards, shortcuts and credits then use it.")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(WishTheme.accentSoft.opacity(0.6))
    }
}
