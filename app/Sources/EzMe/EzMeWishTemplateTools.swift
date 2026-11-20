// Wish Studio, Templates tab: the same simple tools App Designer has (add variables, collections, functions, text and
// picture boxes; command word; more looks from the browser) applied to the background template already in use,
// laid out as accordions so every part stays readable. Each card made from a Wish app uses credits.
import SwiftUI
import AppKit

// MARK: - Accordion

struct WishAccordion<Content: View>: View {
    let id: String
    let title: String
    let symbol: String
    var summary: String = ""
    @Binding var open: String
    @ViewBuilder var content: () -> Content

    private var isOpen: Bool { open == id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { open = isOpen ? "" : id }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(WishTheme.accent).frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        if !summary.isEmpty && !isOpen {
                            Text(summary).font(.system(size: 10)).foregroundStyle(WishTheme.muted).lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(WishTheme.muted)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            if isOpen {
                Divider().overlay(WishTheme.line)
                VStack(alignment: .leading, spacing: 8) { content() }
                    .padding(12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(isOpen ? WishTheme.accentSoft : Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WishTheme.line, lineWidth: 1))
    }
}

// MARK: - Credits for each use

extension WishStudioModel {
    var useCost: Int { CreditsCenter.shared.cost(.wishCard) }

    /// Charges one use of this Wish app. Returns the entry to refund if the work fails, or nil when it must not go ahead.
    func chargeUse(_ what: String) -> UUID? {
        let id = CreditsCenter.shared.charge(.wishCard, detail: "\(app.name): \(what)")
        if id == nil { status = CreditsCenter.shared.lastMessage }
        return id
    }

    func refundUse(_ id: UUID, reason: String) { CreditsCenter.shared.refund(id, reason: reason) }
}

// MARK: - Which design and which command the app has

@MainActor enum WishAppLink {
    static func link(_ model: WishStudioModel) -> String { TemplateStore.wishTemplateID(appID: model.app.id) }
    static func designID(_ model: WishStudioModel) -> String? { TemplateLinks.designID(link(model)) }

    /// The AppBuilder app that answers to the backslash popup for this Wish app.
    static func builderApp(_ model: WishStudioModel) -> (name: String, fromDesign: Bool)? {
        if let preset = WishOccasions.all.first(where: { $0.appName == model.app.name || $0.reuses == model.app.name })?.presetName {
            return (preset, false)
        }
        if let id = designID(model), let name = DesignCommands.appName(forDesign: id) { return (name, true) }
        return nil
    }

    static func currentWord(_ app: String) -> String {
        let fallback = String(app.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).prefix(12))
        return UserDefaults.standard.string(forKey: "ezmeBuilderPrefix." + app) ?? fallback
    }

    static func wordsUsed(byOthersThan app: String) -> Set<String> {
        var used: Set<String> = ["r", "reply", "rr"]
        let list = (try? JSONDecoder().decode([String].self, from: Data((UserDefaults.standard.string(forKey: "ezmeCustomBuilderAppsJSON") ?? "[]").utf8))) ?? []
        for other in list where other != app { used.insert(currentWord(other).lowercased()) }
        return used
    }
}

// MARK: - Add boxes to the template in use

struct WishAddToTemplateSection: View {
    @ObservedObject var model: WishStudioModel

    var body: some View {
        if let template = model.linkedTemplate {
            Text("Variables, collections, functions, text and picture boxes are added and placed by you on the background \u{201C}\(template.name)\u{201D}. Nothing is put on the card for you.")
                .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
            Button { model.designAll = false; model.designMode = true } label: { Label("Open Design: add boxes and place them", systemImage: "paintbrush.pointed") }.buttonStyle(.borderedProminent).controlSize(.small)
        } else {
            Text("This app has no background template yet. Press New template above the card, pick a background, then come back here to add boxes.")
                .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
        }
    }

    private func takenNames() -> [String] {
        var names = model.linkedTemplate?.slots.map { $0.key } ?? []
        if let id = WishAppLink.designID(model), let design = AppDesignStore.shared.design(id: id) { names += Array(design.variables.keys) }
        return names
    }

    private func add(_ elements: [WizardElement]) -> String {
        guard !elements.isEmpty, var template = model.linkedTemplate else { return "" }
        let aspect = CGFloat(template.pixelWidth) / max(1, CGFloat(template.pixelHeight))
        var newVars: [String: String] = [:]
        var placed = 0
        for var e in elements {
            let step = Double(template.slots.count % 8)
            e.cx = 0.5; e.cy = min(0.9, 0.18 + 0.09 * step)
            if e.kind == .picture || e.isMediaCollection { e.w = 0.25; e.h = 0.25 * Double(aspect); e.cy = min(0.8, e.cy + 0.08) }
            var slot = WizardBuilder.slot(for: e)
            var key = slot.key, number = 1
            while template.slots.contains(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) { number += 1; key = slot.key + String(number) }
            slot.key = key
            template.slots.append(slot)
            for (name, value) in WizardBuilder.variables(for: [e]) { newVars[name] = value }
            placed += 1
        }
        TemplateStore.shared.save(template)
        if let id = WishAppLink.designID(model), var design = AppDesignStore.shared.design(id: id) {
            for (name, value) in newVars where design.variables[name] == nil || !value.isEmpty { design.variables[name] = value }
            AppDesignStore.shared.save(design)
            if design.version > 0 { DesignCommands.register(design) }
        }
        model.objectWillChange.send()
        return "Added \(placed) box\(placed == 1 ? "" : "es") to the card. Press Design to drag them into place."
    }
}

// MARK: - Command word after the backslash

struct WishCommandWordSection: View {
    @ObservedObject var model: WishStudioModel
    @State private var word = ""
    @State private var message = ""

    var body: some View {
        if let target = WishAppLink.builderApp(model) {
            VStack(alignment: .leading, spacing: 8) {
                Text("The word you type after the backslash to run this app. It can be different from the app name \u{201C}\(model.app.name)\u{201D}.")
                    .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
                HStack(spacing: 6) {
                    Text("\\").font(.system(size: 15, weight: .bold, design: .monospaced))
                    TextField("hbd", text: $word).textFieldStyle(.roundedBorder).frame(width: 120).onSubmit { apply(target) }
                    Button("Change") { apply(target) }.buttonStyle(.borderedProminent).controlSize(.small)
                }
                Text("Example: \\\(word.isEmpty ? "hbd" : word)-Rahul").font(.system(size: 11, design: .monospaced)).foregroundStyle(WishTheme.muted)
                if !message.isEmpty { Text(message).font(.system(size: 11)).foregroundStyle(WishTheme.ink.opacity(0.8)) }
            }
            .onAppear { word = WishAppLink.currentWord(target.name) }
        } else {
            Text("This app does not run from the backslash popup yet. Apps made from an occasion or a published design do.")
                .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
        }
    }

    private func apply(_ target: (name: String, fromDesign: Bool)) {
        let clean = DesignCommands.sanitize(word)
        guard !clean.isEmpty else { message = "Use one word with letters or numbers only."; return }
        if WishAppLink.wordsUsed(byOthersThan: target.name).contains(clean) {
            message = "\\\(clean) is already used by another app. Choose a different word."
            return
        }
        if target.fromDesign, let id = WishAppLink.designID(model), var design = AppDesignStore.shared.design(id: id) {
            design.command = clean
            AppDesignStore.shared.save(design)
            word = design.version > 0 ? DesignCommands.register(design) : clean
        } else {
            word = clean
        }
        UserDefaults.standard.set(clean, forKey: "ezmeBuilderPrefix." + target.name)
        message = "Done. Type \\\(clean)- and a name in any app to run \(model.app.name)."
        model.objectWillChange.send()
    }
}

// MARK: - More looks from the browser

struct WishMoreLooksSection: View {
    @ObservedObject var model: WishStudioModel
    @State private var showSheet = false

    var body: some View {
        if let id = WishAppLink.designID(model) {
            Text("Send this card to ChatGPT or Gemini in the side browser and ask for more template looks. The same tool as in App Designer.")
                .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
            Button { showSheet = true } label: { Label("Find more looks in the browser", systemImage: "globe") }
                .buttonStyle(.borderedProminent)
                .sheet(isPresented: $showSheet) { DesignMoreLooksSheet(designID: id) }
        } else {
            Text("More looks work on an App Designer design. Press Redesign above the card once to turn this card into a design, then come back.")
                .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
        }
    }
}

// MARK: - Credits

struct WishCreditsSection: View {
    @ObservedObject var model: WishStudioModel
    @ObservedObject private var credits = CreditsCenter.shared

    var body: some View {
        HStack {
            CreditChip(cost: model.useCost)
            Text("each time a card is made").font(.system(size: 11)).foregroundStyle(WishTheme.muted)
        }
        Text("Download, copy, share and open as a web page each count as one use. A failed save returns the credits. You have \(credits.balance) credits. Prices and the approval limit are in Credits settings.")
            .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
    }
}
