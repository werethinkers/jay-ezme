// The same "Add a box" experience as the New App wizard, inside the designer: say what you need or tap a kind, fill in
// its card (data type, subcategory, fixed or mandatory), and press Add to page.
import SwiftUI

struct DesignerAddPanel: View {
    /// Names already used by boxes and variables, so new ones never clash.
    var taken: () -> [String]
    var onAdd: ([WizardElement]) -> String
    @State private var draft: WizardElement?
    @State private var spoken = ""
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Say or type: two variables string and date, one picture", text: $spoken)
                    .textFieldStyle(.roundedBorder).onSubmit { addSpoken(spoken) }
                Button("Add") { addSpoken(spoken) }.buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.small)
                VoiceDictationButton(onTranscript: { said in addSpoken(said) })
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                ForEach(WizardElementKind.allCases) { kind in
                    Button { start(kind) } label: {
                        Label(kind.title, systemImage: kind.symbol).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .tint(draft?.kind == kind ? Butter.coral : nil)
                }
            }
            if draft != nil {
                ElementEditor(element: Binding(get: { draft ?? WizardElement(kind: .variable, name: "") }, set: { draft = $0 }),
                              selected: true, onChange: {}, onSelect: {}, onDelete: { draft = nil })
                if let current = draft, current.kind != .function, current.kind != .text, !current.fixed {
                    Toggle("Mandatory: the app cannot run until this is filled", isOn: Binding(get: { draft?.required ?? false }, set: { draft?.required = $0 }))
                        .toggleStyle(.checkbox).font(.system(size: 11))
                }
                HStack {
                    Button { place() } label: { Label("Add to page", systemImage: "plus.circle.fill") }
                        .buttonStyle(.borderedProminent).tint(Butter.coral).controlSize(.small)
                        .disabled(draft.map { $0.needsChoice } ?? true)
                    Button("Cancel") { draft = nil }.buttonStyle(.bordered).controlSize(.small)
                }
                if draft?.needsChoice == true {
                    Text("Choose the collection subcategory or the function first.").font(.system(size: 10)).foregroundStyle(Color(red: 0.74, green: 0.18, blue: 0.1))
                }
            }
            if !message.isEmpty { Text(message).font(.system(size: 11)).foregroundStyle(Butter.cocoa.opacity(0.8)) }
            Text("Variables are optional: an app runs with whatever is filled in. Tick Mandatory on a box only when it must be filled.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func start(_ kind: WizardElementKind) {
        var e = WizardElement(kind: kind, name: "")
        let base = kind == .variable ? "variable" : kind == .collection ? "collection" : kind == .function ? "function" : kind == .picture ? "photo" : "label"
        let used = Set(taken().map { TemplateFill.normal($0) })
        var name = base, n = 1
        while used.contains(TemplateFill.normal(name)) { n += 1; name = base + String(n) }
        e.name = name
        if kind == .function { e.formula = "{=TODAY()}" }
        if kind == .text { e.text = "Your text" }
        draft = e
        message = ""
    }

    private func place() {
        guard let e = draft else { return }
        message = onAdd([e])
        draft = nil
    }

    private func addSpoken(_ text: String) {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else { return }
        let existing = taken().map { WizardElement(kind: .text, name: $0) }
        let made = WizardSpec.parse(said, existing: existing)
        spoken = ""
        if made.isEmpty { message = "I did not hear what to add. Try \u{201C}two variables string and date, one collection\u{201D}."; return }
        message = onAdd(made)
    }
}
