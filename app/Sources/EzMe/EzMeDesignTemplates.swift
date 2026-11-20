// Every AppDesigner app keeps at least three templates (looks) of the same form.
//   temp1 is the default. temp2, temp3 and so on are the others; tempr picks one at random.
//   Template names have at most 6 letters. Typing \hbd-rahul-temp2 (or a template's own name) makes that look.
// Also here: the last values typed into an app, so an app always has something to fill in and never stops to ask.
import SwiftUI
import AppKit

struct DesignVariant: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var pages: [String] = []
    var releasedPages: [String]? = nil
}

@MainActor enum DesignTemplates {
    static let maxNameLength = 6
    static let minimum = 3

    struct Item: Identifiable, Hashable {
        let id: String      // "main" for the default, otherwise the variant id
        let name: String
        let index: Int
        var isDefault: Bool { index == 0 }
    }

    static func clean(_ raw: String) -> String {
        String(raw.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(maxNameLength))
    }

    static func items(_ design: AppDesign) -> [Item] {
        var result = [Item(id: "main", name: design.mainName ?? "temp1", index: 0)]
        for (offset, variant) in (design.variants ?? []).enumerated() { result.append(Item(id: variant.id, name: variant.name, index: offset + 1)) }
        return result
    }

    /// "temp2", "tempr" or a template's own name. Nil when it is not one.
    static func resolve(_ design: AppDesign, token: String?) -> Item? {
        let all = items(design)
        let said = (token ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !said.isEmpty else { return all.first(where: { $0.id == design.defaultTemplate }) ?? all.first }
        if said == "tempr" || said == "random" || said == "rand" { return all.randomElement() }
        if let named = all.first(where: { $0.name.lowercased() == said }) { return named }
        if said.hasPrefix("temp"), let number = Int(said.dropFirst(4)), number >= 1, number <= all.count { return all[number - 1] }
        // A bare number is the template number (\hbd-Rohit-3 is the third template), unless the app takes numbers as values.
        if let number = Int(said), number >= 1, number <= all.count, !takesNumbers(design) { return all[number - 1] }
        return nil
    }

    /// The number (1, 2, 3 ...) of the template used when none is named.
    static func defaultNumber(_ design: AppDesign) -> Int {
        (items(design).firstIndex { $0.id == design.defaultTemplate } ?? 0) + 1
    }

    private static func takesNumbers(_ design: AppDesign) -> Bool {
        DesignDataType.names(design.variables).contains { [.number, .whole, .currency].contains(DesignDataType.of($0, in: design.variables)) }
    }

    static func isToken(_ text: String, design: AppDesign) -> Bool {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !said.isEmpty else { return false }
        if said == "tempr" || said == "random" { return true }
        return resolve(design, token: said) != nil
    }

    static func pageIDs(_ design: AppDesign, item: Item, released: Bool) -> [String] {
        if item.id == "main" { return released ? (design.releasedPages ?? []) : design.pages }
        guard let variant = design.variants?.first(where: { $0.id == item.id }) else { return [] }
        return released ? (variant.releasedPages ?? []) : variant.pages
    }

    /// The pages an app uses for a template: the published copy when there is one, otherwise the working pages.
    static func activePages(_ design: AppDesign, token: String?) -> [ImageTemplate] {
        guard let item = resolve(design, token: token) ?? items(design).first else { return [] }
        let released = pageIDs(design, item: item, released: true)
        let ids = released.isEmpty ? pageIDs(design, item: item, released: false) : released
        return ids.compactMap { TemplateStore.shared.template(id: $0) }
    }

    /// The link that makes an app render one template: "design:<id>@temp2".
    static func link(_ link: String, token: String) -> String {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, link.hasPrefix("design:"), !link.contains("@") else { return link }
        return link + "@" + clean
    }

    // MARK: Making and changing templates

    private static func uniqueName(_ wanted: String, in design: AppDesign, except id: String? = nil) -> String {
        let taken = Set(items(design).filter { $0.id != id }.map { $0.name.lowercased() })
        var base = clean(wanted)
        if base.isEmpty { base = "temp" }
        if !taken.contains(base) { return base }
        var number = 2
        while true {
            let suffix = String(number)
            let candidate = String(base.prefix(maxNameLength - suffix.count)) + suffix
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }

    private static let looks: [(hue: CGFloat, fonts: [String: String])] = [
        (0.36, ["Helvetica Neue": "Avenir Next", "Didot": "Georgia", "Futura": "Gill Sans"]),
        (0.70, ["Helvetica Neue": "Optima", "Didot": "Palatino", "Futura": "Trebuchet MS"]),
        (0.14, ["Helvetica Neue": "Verdana", "Didot": "Baskerville", "Futura": "Avenir Next"])
    ]

    /// Gives an app at least three templates. The new ones are copies of the default with the colours turned round.
    static func ensure(_ designID: String) {
        let store = AppDesignStore.shared
        guard var design = store.design(id: designID), !design.pages.isEmpty else { return }
        var variants = design.variants ?? []
        guard variants.count + 1 < minimum else { return }
        var step = variants.count
        while variants.count + 1 < minimum {
            let look = looks[step % looks.count]
            step += 1
            var scratch = design
            scratch.variants = variants
            let name = uniqueName("temp\(variants.count + 2)", in: scratch)
            var variant = DesignVariant(name: name)
            variant.pages = copyPages(design.pages, design: design, name: name, look: look)
            if design.version > 0, let released = design.releasedPages, !released.isEmpty {
                variant.releasedPages = copyPages(released, design: design, name: name, look: look)
            }
            guard !variant.pages.isEmpty else { break }
            variants.append(variant)
        }
        design.variants = variants
        store.save(design)
    }

    static func ensureAll() {
        for design in AppDesignStore.shared.designs { ensure(design.id) }
    }

    private static func copyPages(_ ids: [String], design: AppDesign, name: String, look: (hue: CGFloat, fonts: [String: String])?) -> [String] {
        var made: [String] = []
        for id in ids {
            guard var copy = TemplateStore.shared.duplicate(id) else { continue }
            copy.designID = design.id
            copy.name = "\(design.name) \(name) page \(made.count + 1)"
            if let look { restyle(&copy, hue: look.hue, fonts: look.fonts) }
            TemplateStore.shared.save(copy)
            made.append(copy.id)
        }
        return made
    }

    /// A new template that starts as a copy of another one in the same app.
    @discardableResult static func add(to designID: String, copying itemID: String) -> String? {
        let store = AppDesignStore.shared
        guard var design = store.design(id: designID), let source = items(design).first(where: { $0.id == itemID }) ?? items(design).first else { return nil }
        let name = uniqueName("temp\(items(design).count + 1)", in: design)
        var variant = DesignVariant(name: name)
        variant.pages = copyPages(pageIDs(design, item: source, released: false), design: design, name: name, look: nil)
        guard !variant.pages.isEmpty else { return nil }
        var list = design.variants ?? []
        list.append(variant)
        design.variants = list
        store.save(design)
        return variant.id
    }

    static func rename(_ designID: String, itemID: String, to wanted: String) {
        let store = AppDesignStore.shared
        guard var design = store.design(id: designID), !clean(wanted).isEmpty else { return }
        let name = uniqueName(wanted, in: design, except: itemID)
        if itemID == "main" { design.mainName = name }
        else if let index = design.variants?.firstIndex(where: { $0.id == itemID }) { design.variants?[index].name = name }
        store.save(design)
    }

    /// Swaps a template into the default place. temp1 is always the default.
    static func makeDefault(_ designID: String, itemID: String) {
        let store = AppDesignStore.shared
        guard itemID != "main", var design = store.design(id: designID), let index = design.variants?.firstIndex(where: { $0.id == itemID }), var variant = design.variants?[index] else { return }
        let mainName = design.mainName ?? "temp1"
        let pages = design.pages, released = design.releasedPages
        design.pages = variant.pages
        design.releasedPages = variant.releasedPages
        design.mainName = variant.name
        variant.pages = pages
        variant.releasedPages = released
        variant.name = mainName
        design.variants?[index] = variant
        store.save(design)
        if design.version > 0 { DesignCommands.register(design) }
    }

    /// Removes a template, but an app always keeps at least three.
    @discardableResult static func remove(_ designID: String, itemID: String) -> Bool {
        let store = AppDesignStore.shared
        guard itemID != "main", var design = store.design(id: designID), items(design).count > minimum, let variant = design.variants?.first(where: { $0.id == itemID }) else { return false }
        for id in variant.pages + (variant.releasedPages ?? []) { TemplateStore.shared.delete(id) }
        design.variants?.removeAll { $0.id == itemID }
        store.save(design)
        return true
    }

    // MARK: Turning the colours round

    private static func shift(_ hex: String, by hue: CGFloat) -> String {
        guard !hex.isEmpty, let color = NSColor(templateHex: hex).usingColorSpace(.sRGB) else { return hex }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        guard s > 0.08 else { return hex }
        let turned = (h + hue).truncatingRemainder(dividingBy: 1)
        return NSColor(hue: turned, saturation: s, brightness: b, alpha: a).templateHex
    }

    /// The one colour of a picture that is a single flat colour, or nil for a photo.
    private static func flatColor(_ image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard rep.pixelsWide > 4, rep.pixelsHigh > 4 else { return nil }
        var first: NSColor?
        for fx in [0.05, 0.5, 0.95] {
            for fy in [0.05, 0.5, 0.95] {
                guard let color = rep.colorAt(x: Int(Double(rep.pixelsWide - 1) * fx), y: Int(Double(rep.pixelsHigh - 1) * fy))?.usingColorSpace(.sRGB) else { return nil }
                if let first {
                    if abs(first.redComponent - color.redComponent) > 0.02 || abs(first.greenComponent - color.greenComponent) > 0.02 || abs(first.blueComponent - color.blueComponent) > 0.02 { return nil }
                } else { first = color }
            }
        }
        return first
    }

    private static func restyle(_ page: inout ImageTemplate, hue: CGFloat, fonts: [String: String]) {
        let installed = Set(TemplateFonts.all)
        for index in page.slots.indices {
            page.slots[index].colorHex = shift(page.slots[index].colorHex, by: hue)
            page.slots[index].fillHex = shift(page.slots[index].fillHex, by: hue)
            if let swap = fonts[page.slots[index].fontName], installed.contains(swap) { page.slots[index].fontName = swap }
        }
        if let base = TemplateStore.shared.basePicture(for: page), let flat = flatColor(base) {
            let size = NSSize(width: CGFloat(page.pixelWidth), height: CGFloat(page.pixelHeight))
            let painted = NSImage(size: size)
            painted.lockFocus()
            NSColor(templateHex: shift(flat.templateHex, by: hue)).setFill()
            NSRect(origin: .zero, size: size).fill()
            painted.unlockFocus()
            TemplateStore.shared.setPicture(painted, for: page)
        }
    }
}

// MARK: - Last values

/// What was typed into an app last time. It fills the form first and stands in when a command leaves something out.
@MainActor enum DesignMemory {
    private static func key(_ designID: String) -> String { "ezmeLastValues." + designID }

    static func last(_ designID: String) -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key(designID)) as? [String: String] ?? [:]
    }

    static func remember(_ designID: String, values: [String: String]) {
        var stored = last(designID)
        var changed = false
        for (name, value) in values {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let normal = TemplateFill.normal(name)
            guard !clean.isEmpty, !normal.isEmpty, stored[normal] != clean else { continue }
            stored[normal] = clean
            changed = true
        }
        if changed { UserDefaults.standard.set(stored, forKey: key(designID)) }
    }

    /// What an empty box will use: the last value typed, otherwise the starting value of the app.
    static func fallback(_ designID: String, field: DesignField) -> String {
        last(designID)[TemplateFill.normal(field.key)] ?? field.defaultValue
    }
}

// MARK: - The strip of templates above the designer

struct DesignTemplateBar: View {
    var designID: String
    @Binding var selected: String
    @ObservedObject private var designs = AppDesignStore.shared
    @State private var nameText = ""

    private var design: AppDesign? { designs.design(id: designID) }

    var body: some View {
        if let design {
            let items = DesignTemplates.items(design)
            let current = items.first(where: { $0.id == selected }) ?? items[0]
            HStack(spacing: 8) {
                Text("Templates").font(.system(size: 11, weight: .bold)).foregroundStyle(Butter.cocoa)
                ForEach(items) { item in
                    Button { selected = item.id } label: {
                        Text(item.name + (item.isDefault ? " \u{2605}" : ""))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .foregroundStyle(item.id == current.id ? Color.white : Butter.cocoa)
                            .background(Capsule().fill(item.id == current.id ? Butter.coral : Color.white))
                            .overlay(Capsule().stroke(Butter.honey, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(item.isDefault ? "\(item.name) is the default. Say temp\(item.index + 1) to pick it." : "Say temp\(item.index + 1) or \(item.name) to pick it.")
                }
                Button {
                    if let made = DesignTemplates.add(to: designID, copying: current.id) { selected = made }
                } label: { Label("Save as new", systemImage: "plus") }
                    .buttonStyle(.bordered).controlSize(.small).help("Save a copy of this template to keep the old one as it is")
                Spacer()
                Text("Name").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("6 letters", text: $nameText).textFieldStyle(.roundedBorder).frame(width: 84)
                    .onSubmit { commitName(current) }
                    .onChange(of: nameText) { _, value in if value.count > DesignTemplates.maxNameLength { nameText = String(value.prefix(DesignTemplates.maxNameLength)) } }
                if !current.isDefault {
                    Button("Make default") { DesignTemplates.makeDefault(designID, itemID: current.id); selected = "main" }.buttonStyle(.bordered).controlSize(.small)
                }
                if !current.isDefault && items.count > DesignTemplates.minimum {
                    Button { if DesignTemplates.remove(designID, itemID: current.id) { selected = "main" } } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(.red.opacity(0.8)).help("Delete this template")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Butter.cream)
            .onAppear { nameText = current.name }
            .onChange(of: selected) { _, _ in nameText = (DesignTemplates.items(design).first(where: { $0.id == selected }) ?? items[0]).name }
        }
    }

    private func commitName(_ current: DesignTemplates.Item) {
        DesignTemplates.rename(designID, itemID: current.id, to: nameText)
        if let updated = designs.design(id: designID), let item = DesignTemplates.items(updated).first(where: { $0.id == current.id }) { nameText = item.name }
    }
}
