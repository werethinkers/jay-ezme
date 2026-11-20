// Template choices inside the popup, numbered like the full form: 1, 2, 3, 4 and Random.
import SwiftUI

extension BuilderShortcutCommandCard {
    /// The design behind this app, when it is a design app.
    private var cardDesign: AppDesign? {
        DesignCommands.designID(forApp: command.app).flatMap { AppDesignStore.shared.design(id: $0) }
    }

    /// Extra popup height the template pictures need.
    var templateExtra: Int {
        guard let design = cardDesign, DesignTemplates.items(design).count > 1 else { return 0 }
        return 96
    }

    /// "2" and "temp2" both mean the second template.
    func normalizedTemplateToken(_ token: String) -> String {
        let clean = token.trimmingCharacters(in: .whitespaces).lowercased()
        return Int(clean) != nil ? "temp" + clean : clean
    }

    private func numberedChoices(_ items: [DesignTemplates.Item]) -> [TemplateChoice] {
        var list: [TemplateChoice] = []
        for (index, item) in items.enumerated() {
            let token = "temp\(index + 1)"
            list.append(TemplateChoice(token: token, name: "\(index + 1)" + (item.isDefault ? " \u{2022}" : ""), image: cardThumbs[token]))
        }
        list.append(TemplateChoice(token: "tempr", name: "Random", image: nil))
        return list
    }

    @ViewBuilder var templateChooser: some View {
        if let design = cardDesign {
            let items = DesignTemplates.items(design)
            if items.count > 1 {
                let defaultToken = "temp\((items.firstIndex { $0.isDefault } ?? 0) + 1)"
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose a template").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TemplateStrip(choices: numberedChoices(items),
                                  selection: Binding(get: { templatePick.isEmpty ? defaultToken : templatePick }, set: { templatePick = $0 }),
                                  size: 56)
                }
                .task(id: command.app) { await loadCardThumbs() }
            }
        }
    }

    /// Small pictures of every template, made one at a time so the popup opens straight away.
    private func loadCardThumbs() async {
        guard let design = cardDesign else { return }
        let items = DesignTemplates.items(design)
        for index in items.indices {
            let token = "temp\(index + 1)"
            if cardThumbs[token] != nil { continue }
            if let first = AppDesignStore.shared.activePages(design, token: token).first, let base = TemplateStore.shared.basePicture(for: first) {
                let merged = DesignFill.merge(design.variables, [:])
                let made = TemplateFill.resolved(first, values: merged, clips: db.clips)
                cardThumbs[token] = TemplateRenderer.render(first, base: base, texts: made.texts, images: made.images, useSamples: true, maxSide: 160)
            }
            await Task.yield()
        }
    }
}
