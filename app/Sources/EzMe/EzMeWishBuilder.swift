// WishBuilder: defines what kinds of wish apps WishStudio can make, in five steps.
//   1 Application   2 Information   3 Collection   4 Function   5 Live Changes
import SwiftUI

enum WishStep: Int, CaseIterable {
    case application, information, collection, function, live

    var title: String {
        switch self {
        case .application: return "Application"
        case .information: return "Information"
        case .collection: return "Collection"
        case .function: return "Function"
        case .live: return "Live Changes"
        }
    }

    var hint: String {
        switch self {
        case .application: return "What kind of app do you want to build?"
        case .information: return "The fields, based on your prompt."
        case .collection: return "Which of your collections show up, and can be used by voice."
        case .function: return "Global functions like =Date and =Date+1, plus the Google Sheets set."
        case .live: return "How voice commands change the card while you speak."
        }
    }

    var symbol: String {
        switch self {
        case .application: return "square.grid.2x2"
        case .information: return "list.bullet.rectangle"
        case .collection: return "tray.full"
        case .function: return "function"
        case .live: return "waveform"
        }
    }
}

struct WishBuilderView: View {
    @ObservedObject var model: WishStudioModel
    @ObservedObject var store: WishStore
    @ObservedObject var builder: WishBuilderState

    private var current: WishApp? {
        return store.app(id: builder.editingID) ?? store.apps.first
    }

    private var appBinding: Binding<WishApp> {
        return Binding(
            get: { current ?? WishApp(name: "New app") },
            set: { value in
                store.updateApp(value)
                if value.id == model.appID { model.appDefinitionChanged() }
            }
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            modeBar
            if builder.mode == .create {
                WishCreateView(model: model, builder: builder)
            } else {
                editor
            }
        }
        .padding(22)
        .onAppear {
            if builder.editingID.isEmpty { builder.editingID = model.appID.isEmpty ? (store.apps.first?.id ?? "") : model.appID }
        }
    }

    private var modeBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $builder.mode) {
                ForEach(WishBuilderMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 360)
            Text(builder.mode == .create ? "Describe an app in your own words. WishBuilder asks for what is missing." : "Change what an app asks for, which collections it uses, its functions and its voice commands.")
                .font(.system(size: 12))
                .foregroundStyle(WishTheme.muted)
                .lineLimit(1)
            Spacer()
        }
    }

    private var editor: some View {
        HStack(alignment: .top, spacing: 16) {
            appList.frame(width: 240)
            VStack(spacing: 12) {
                stepRail
                ScrollView {
                    if current != nil {
                        stepBody
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WishTheme.line, lineWidth: 1))
            }
        }
    }

    // MARK: App list

    private var appList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your wish apps").font(.system(size: 15, weight: .semibold))
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.apps) { item in
                        let active = item.id == current?.id
                        Button {
                            builder.editingID = item.id
                        } label: {
                            HStack(spacing: 8) {
                                WishCover(app: item, store: store, emojiSize: 16)
                                    .frame(width: 34, height: 34)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text("\(item.kind.title) \u{00B7} \(item.fields.count) fields").font(.system(size: 10)).foregroundStyle(WishTheme.muted)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(active ? WishTheme.accentSoft : Color.clear))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? WishTheme.accent : WishTheme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Button {
                    builder.restart()
                    builder.mode = .create
                } label: {
                    Label("New app", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                if let item = current, !item.builtIn {
                    Button(role: .destructive) {
                        store.apps.removeAll { $0.id == item.id }
                        store.cards[item.id] = nil
                        builder.editingID = store.apps.first?.id ?? ""
                        if model.appID == item.id, let first = store.apps.first { model.loadApp(first.id, saveCurrent: false) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete this app")
                }
            }
            Button("Restore starter apps") { store.resetStarterApps() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(WishTheme.muted)
            Spacer(minLength: 0)
            if let item = current {
                Button {
                    model.openApp(item.id)
                } label: {
                    Label("Open in Studio", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WishTheme.line, lineWidth: 1))
    }

    // MARK: Step rail

    private var stepRail: some View {
        HStack(spacing: 8) {
            ForEach(WishStep.allCases, id: \.self) { item in
                let active = item == builder.step
                Button {
                    builder.step = item
                } label: {
                    HStack(spacing: 8) {
                        Text("\(item.rawValue + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(active ? WishTheme.accent : WishTheme.accentSoft))
                            .foregroundStyle(active ? Color.white : WishTheme.accent)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                            Text(item.hint).font(.system(size: 9)).foregroundStyle(WishTheme.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(active ? WishTheme.accentSoft : Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(active ? WishTheme.accent : WishTheme.line, lineWidth: active ? 1.4 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch builder.step {
        case .application:
            WishApplicationStep(app: appBinding)
        case .information:
            WishInformationStep(app: appBinding)
        case .collection:
            WishCollectionStep(app: appBinding, collections: model.collections, records: model.records, clips: model.clips)
        case .function:
            WishFunctionStep(store: store, app: current)
        case .live:
            WishLiveStep(app: appBinding, store: store, model: model)
        }
    }
}

// MARK: - Shared helpers

enum WishBuilderTools {
    /// Keyword-based. There is no AI behind this: it looks for words in the prompt and offers matching fields.
    static func suggestFields(from prompt: String, kind: WishKind) -> [WishField] {
        let text = prompt.lowercased()
        func has(_ words: [String]) -> Bool { return words.contains { text.contains($0) } }
        func make(_ key: String, _ label: String, _ labelHi: String, _ type: WishFieldType, _ value: String, universal: Bool = false) -> WishField {
            return WishField(key: key, label: label, labelHi: labelHi, type: type, value: value, valueHi: value, universal: universal)
        }
        var fields: [WishField] = [
            make("eyebrow", "Top line", "\u{090A}\u{092A}\u{0930} \u{0915}\u{0940} \u{092A}\u{0902}\u{0915}\u{094D}\u{0924}\u{093F}", .text, "A LITTLE NOTE"),
            make("title", "Title", "\u{0936}\u{0940}\u{0930}\u{094D}\u{0937}\u{0915}", .text, "Your title here"),
        ]
        if kind == .infographic || has(["chart", "data", "list", "steps", "numbers", "table", "graph", "infographic"]) {
            fields.append(make("data", "Data", "\u{0921}\u{0947}\u{091F}\u{093E}", .list, "One, 30\nTwo, 20\nThree, 50"))
        }
        if kind == .greeting {
            if has(["name", "dear", "friend", "person", "family", "couple", "colleague", "teacher", "mother", "father", "mom", "dad", "sister", "brother"]) || prompt.isEmpty {
                fields.append(make("name", "Name", "\u{0928}\u{093E}\u{092E}", .text, "Dear friend"))
            }
            fields.append(make("message", "Message", "\u{0938}\u{0902}\u{0926}\u{0947}\u{0936}", .longText, "Write something warm here."))
            fields.append(make("from", "From", "\u{0915}\u{0940} \u{0913}\u{0930} \u{0938}\u{0947}", .text, "With love"))
        }
        if has(["venue", "place", "location", "where", "address"]) {
            fields.append(make("venue", "Venue", "\u{0938}\u{094D}\u{0925}\u{093E}\u{0928}", .text, "At our place"))
        }
        if has(["date", "when", "day", "today", "tomorrow", "event", "party", "wedding", "birthday", "anniversary"]) || prompt.isEmpty {
            fields.append(make("date", "Date", "\u{0924}\u{093E}\u{0930}\u{0940}\u{0916}", .date, "=Date", universal: true))
        }
        if has(["time", "clock", "hour", "o'clock"]) {
            fields.append(make("time", "Time", "\u{0938}\u{092E}\u{092F}", .text, "=Time", universal: true))
        }
        if has(["phone", "call", "contact", "number"]) {
            fields.append(make("phone", "Phone", "\u{092B}\u{093C}\u{094B}\u{0928}", .text, "", universal: true))
        }
        return fields
    }

    static func makeKey(_ label: String, existing: [WishField]) -> String {
        let letters = label.lowercased().filter { $0.isLetter || $0.isNumber }
        var base = letters.isEmpty ? "field" : String(letters.prefix(18))
        if base.first?.isNumber == true { base = "f" + base }
        var key = base
        var count = 2
        while existing.contains(where: { $0.key == key }) {
            key = base + String(count)
            count += 1
        }
        return key
    }

    static func section(_ title: String, _ detail: String = "") -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 17, weight: .semibold))
            if !detail.isEmpty {
                Text(detail).font(.system(size: 12)).foregroundStyle(WishTheme.muted)
            }
        }
    }
}

// MARK: - 1 Application

struct WishApplicationStep: View {
    @Binding var app: WishApp

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WishBuilderTools.section("1 \u{00B7} Application", "Define what kind of app you want to build.")
            HStack(spacing: 12) {
                labelled("Name") { TextField("Birthday", text: $app.name).textFieldStyle(.roundedBorder) }
                labelled("Name in Hindi") { TextField("\u{091C}\u{0928}\u{094D}\u{092E}\u{0926}\u{093F}\u{0928}", text: $app.nameHi).textFieldStyle(.roundedBorder) }
            }
            labelled("Tagline") { TextField("Make a wish", text: $app.tagline).textFieldStyle(.roundedBorder) }
            HStack(spacing: 12) {
                labelled("Kind of app") {
                    Picker("", selection: $app.kind) {
                        ForEach(WishKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                labelled("Starts in") {
                    Picker("", selection: $app.defaultLanguage) {
                        ForEach(WishLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
            labelled("Prompt: describe the app in your own words") {
                TextEditor(text: $app.prompt)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WishTheme.line, lineWidth: 1))
            }
            Text("The prompt is kept with the app. Step 2 can suggest fields from the words in it.")
                .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
            labelled("Menu icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 12), spacing: 6) {
                    ForEach(WishArtwork.choices, id: \.symbol) { choice in
                        let active = app.symbol == choice.symbol
                        Button {
                            app.symbol = choice.symbol
                            if app.kind == .greeting { app.artwork = choice.symbol }
                        } label: {
                            Image(systemName: choice.symbol)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 8).fill(active ? WishTheme.accentSoft : Color.clear))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(active ? WishTheme.accent : WishTheme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help(choice.name)
                    }
                }
            }
        }
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 2 Information

struct WishInformationStep: View {
    @Binding var app: WishApp
    @State private var confirmReplace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WishBuilderTools.section("2 \u{00B7} Information", "The fields a card of this app asks for. Use a field in any function by its key, like =name.")
            HStack {
                Button {
                    if app.fields.isEmpty {
                        app.fields = WishBuilderTools.suggestFields(from: app.prompt, kind: app.kind)
                    } else {
                        confirmReplace = true
                    }
                } label: {
                    Label("Suggest from prompt", systemImage: "text.badge.plus")
                }
                .buttonStyle(.bordered)
                .confirmationDialog("Replace the current fields?", isPresented: $confirmReplace) {
                    Button("Replace with suggestions", role: .destructive) {
                        app.fields = WishBuilderTools.suggestFields(from: app.prompt, kind: app.kind)
                    }
                    Button("Cancel", role: .cancel) {}
                }
                Button {
                    let label = "Field \(app.fields.count + 1)"
                    app.fields.append(WishField(key: WishBuilderTools.makeKey(label, existing: app.fields), label: label))
                } label: {
                    Label("Add field", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            Text("Tip: drag a function chip from the Function step onto a starting text box to make it a formula like =Date+1.")
                .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
            Text("Suggestions come from keywords in your prompt (name, date, venue, chart...). There is no AI behind them, so check the list.")
                .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
            if app.fields.isEmpty {
                Text("No fields yet.").foregroundStyle(WishTheme.muted)
            }
            ForEach($app.fields) { $field in
                fieldRow($field)
            }
        }
    }

    private func fieldRow(_ field: Binding<WishField>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Label", text: field.label).textFieldStyle(.roundedBorder)
                TextField("\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940} \u{0932}\u{0947}\u{092C}\u{0932}", text: field.labelHi).textFieldStyle(.roundedBorder)
                Picker("", selection: field.type) {
                    ForEach(WishFieldType.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
                Button(role: .destructive) {
                    app.fields.removeAll { $0.id == field.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                Text("Key").font(.system(size: 11)).foregroundStyle(WishTheme.muted)
                TextField("key", text: field.key)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onChange(of: field.wrappedValue.key) { value in
                        let cleaned = String(value.lowercased().filter { $0.isLetter || $0.isNumber })
                        if cleaned != value { field.wrappedValue.key = cleaned }
                    }
                TextField("Starting text (English)", text: field.value)
                    .textFieldStyle(.roundedBorder)
                    .dropDestination(for: String.self) { items, _ in
                        guard let first = items.first else { return false }
                        field.wrappedValue.value = first
                        field.wrappedValue.valueHi = first
                        return true
                    }
                TextField("\u{0936}\u{0941}\u{0930}\u{0942}\u{0906}\u{0924}\u{0940} \u{092A}\u{093E}\u{0920}", text: field.valueHi).textFieldStyle(.roundedBorder)
                Toggle("Same in both", isOn: field.universal).toggleStyle(.checkbox).font(.system(size: 11))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(WishTheme.page))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WishTheme.line, lineWidth: 1))
    }
}

// MARK: - 3 Collection

struct WishCollectionStep: View {
    @Binding var app: WishApp
    let collections: [String]
    let records: [CollectionRecord]
    let clips: [Clip]

    private func link(for name: String) -> WishCollectionLink? {
        return app.links.first { $0.collection == name }
    }

    private func count(_ name: String) -> (records: Int, shortcuts: Int) {
        let r = records.filter { $0.collection.caseInsensitiveCompare(name) == .orderedSame }.count
        let s = clips.filter { $0.allGroups.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }.count
        return (r, s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WishBuilderTools.section("3 \u{00B7} Collection", "Choose which of your collections are shown while you use voice. Their values become tap-to-fill chips, and you can say \u{201C}use <name>\u{201D}.")
            if collections.isEmpty {
                Text("You have no collections yet. Create one in EzMe and it will appear here.").foregroundStyle(WishTheme.muted)
            }
            if app.fields.isEmpty {
                Text("Add fields in step 2 first, so a collection has somewhere to go.").foregroundStyle(WishTheme.muted)
            }
            ForEach(collections, id: \.self) { name in
                row(name)
            }
        }
    }

    private func row(_ name: String) -> some View {
        let existing = link(for: name)
        let counts = count(name)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: Binding(
                    get: { existing != nil },
                    set: { on in
                        if on {
                            guard let first = app.fields.first(where: { $0.type == .text || $0.type == .longText }) ?? app.fields.first else { return }
                            let preferred = app.fields.first(where: { $0.key == "name" }) ?? first
                            app.links.append(WishCollectionLink(collection: name, fieldKey: preferred.key, useShortcutText: counts.records == 0 && counts.shortcuts > 0))
                        } else {
                            app.links.removeAll { $0.collection == name }
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.system(size: 13, weight: .semibold))
                        Text("\(counts.records) records \u{00B7} \(counts.shortcuts) shortcuts").font(.system(size: 10)).foregroundStyle(WishTheme.muted)
                    }
                }
                Spacer()
            }
            if let existing = existing, let index = app.links.firstIndex(where: { $0.id == existing.id }) {
                HStack(spacing: 12) {
                    Picker("Fills", selection: $app.links[index].fieldKey) {
                        ForEach(app.fields) { Text($0.label).tag($0.key) }
                    }
                    .frame(width: 220)
                    Picker("", selection: $app.links[index].useShortcutText) {
                        Text("Record names").tag(false)
                        Text("Shortcut text").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 230)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(existing == nil ? WishTheme.page : WishTheme.accentSoft.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WishTheme.line, lineWidth: 1))
    }
}

// MARK: - 4 Function

struct WishFunctionStep: View {
    @ObservedObject var store: WishStore
    let app: WishApp?

    @State private var tester = "=Date+1"
    @State private var query = ""
    @State private var newName = ""
    @State private var newExpression = ""

    private var context: WishContext {
        var context = WishContext()
        for function in store.functions {
            var body = function.expression.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.hasPrefix("=") { body.removeFirst() }
            context.functions[function.name.lowercased()] = body
        }
        if let app = app {
            for field in app.fields {
                context.variables[field.key.lowercased()] = WishFormula.render(field.value, context: context)
            }
        }
        return context
    }

    private func result(_ source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let value = WishFormula.evaluate(trimmed, context: context)
        return value.display(context)
    }

    private var nameProblem: String? {
        let name = newName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return nil }
        if name.first?.isNumber == true { return "A name cannot start with a number." }
        if name.contains(where: { !($0.isLetter || $0.isNumber || $0 == "_") }) { return "Use letters, numbers and _ only." }
        if WishFunctionCatalog.reservedNames.contains(name.lowercased()) { return "\(name) is already a built-in function. Pick another name." }
        if store.functions.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return "You already have a function called \(name)." }
        return nil
    }

    private let examples: [(String, String)] = [
        ("=Date", "Today"), ("=Date+1", "Tomorrow"), ("=Date-7", "A week ago"), ("=Time", "Time now"), ("=Time+2", "Two hours from now"),
        ("=Month+1", "Next month"), ("=Year", "This year"), ("=Weekday", "Today's weekday"), ("=TEXT(Date,\"d mmmm yyyy\")", "Long date"),
        ("=COUNTDOWN(DATE(2027,1,1))", "Days to new year"), ("=UPPER(\"hello\")", "Capitals"), ("=INR(125000)", "Indian rupees"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WishBuilderTools.section("4 \u{00B7} Function", "Type = in any box on a card. =Date is today, =Date+1 is tomorrow. Time, Month, Year and Weekday work the same way.")
            tryIt
            VStack(alignment: .leading, spacing: 6) {
                Text("Drag a function").font(.system(size: 12, weight: .semibold))
                Text("Drag a chip onto a box in the Information step, or into any box in the Studio. Click one to try it above.")
                    .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
                WishFunctionShelf(store: store, tap: { tester = $0 }, expanded: true)
            }
            examplesView
            myFunctions
            catalogue
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Try a function").font(.system(size: 12, weight: .semibold))
            HStack {
                TextField("=Date+1", text: $tester).textFieldStyle(.roundedBorder).font(.system(size: 13, design: .monospaced))
                Image(systemName: "arrow.right").foregroundStyle(WishTheme.muted)
                Text(result(tester).isEmpty ? "\u{2014}" : result(tester))
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: 200, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(WishTheme.accentSoft))
    }

    private var examplesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Examples (click to try)").font(.system(size: 12, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(examples, id: \.0) { example in
                    Button {
                        tester = example.0
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(example.0).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                            Text("\(example.1) \u{2192} \(result(example.0))").font(.system(size: 10)).foregroundStyle(WishTheme.muted).lineLimit(1)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(WishTheme.page))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WishTheme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var myFunctions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("My global functions").font(.system(size: 12, weight: .semibold))
            Text("Make your own, then use it anywhere with =Name. For example Tomorrow = Date+1 lets you type =Tomorrow.")
                .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
            ForEach($store.functions) { $function in
                HStack(spacing: 10) {
                    Text("=" + function.name).font(.system(size: 12, weight: .semibold, design: .monospaced)).frame(width: 130, alignment: .leading)
                    TextField("expression", text: $function.expression).textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                    Text(result("=" + function.name)).font(.system(size: 12)).foregroundStyle(WishTheme.accent).frame(width: 190, alignment: .leading).lineLimit(1)
                    Button(role: .destructive) {
                        store.functions.removeAll { $0.id == function.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                TextField("Name, like Tomorrow", text: $newName).textFieldStyle(.roundedBorder).frame(width: 170)
                TextField("Expression, like Date+1", text: $newExpression).textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                Button("Add") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    store.functions.append(WishFunction(name: name, expression: newExpression.trimmingCharacters(in: .whitespaces)))
                    newName = ""
                    newExpression = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newExpression.trimmingCharacters(in: .whitespaces).isEmpty || nameProblem != nil)
            }
            if let problem = nameProblem {
                Text(problem).font(.system(size: 11)).foregroundStyle(Color.red)
            }
        }
    }

    private var catalogue: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Google Sheets functions (\(WishFunctionCatalog.all.count))").font(.system(size: 12, weight: .semibold))
                Spacer()
                TextField("Search", text: $query).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            Text("These work in any box, with brackets, like =TEXT(Date,\"dddd\"). This is a popular subset, not every Sheets function.")
                .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
            let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
            let list = WishFunctionCatalog.words + WishFunctionCatalog.all
            ForEach(WishFunctionCatalog.categories, id: \.self) { category in
                let items = list.filter { $0.category == category && (needle.isEmpty || $0.name.lowercased().contains(needle) || $0.summary.lowercased().contains(needle)) }
                if !items.isEmpty {
                    DisclosureGroup(category + "  (\(items.count))") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(items) { item in
                                Button {
                                    tester = item.syntax.hasPrefix("=") ? item.syntax : "=" + item.syntax
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(item.syntax).font(.system(size: 11, weight: .semibold, design: .monospaced)).frame(width: 250, alignment: .leading)
                                        Text(item.summary).font(.system(size: 11)).foregroundStyle(WishTheme.muted)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            }
        }
    }
}

// MARK: - 5 Live Changes

struct WishLiveStep: View {
    @Binding var app: WishApp
    @ObservedObject var store: WishStore
    @ObservedObject var model: WishStudioModel

    @State private var sentence = "make it pink and bigger"
    @State private var dryRun: [String] = []

    private let cheatSheet: [(String, String)] = [
        ("Fields", "\u{201C}name Yogesh\u{201D} \u{00B7} \u{201C}set message to Have a great year\u{201D} \u{00B7} \u{201C}title Happy Diwali\u{201D}"),
        ("Collections", "\u{201C}use Ravi\u{201D} fills the field linked to a collection"),
        ("Colors", "\u{201C}make it pink\u{201D} \u{00B7} \u{201C}background dark blue\u{201D} \u{00B7} \u{201C}title gold\u{201D}"),
        ("Text", "\u{201C}bigger\u{201D} \u{00B7} \u{201C}smaller title\u{201D} \u{00B7} \u{201C}move the name left\u{201D} \u{00B7} \u{201C}bold\u{201D} \u{00B7} \u{201C}hide the date\u{201D}"),
        ("Design", "\u{201C}next design\u{201D} \u{00B7} \u{201C}design 3\u{201D} \u{00B7} \u{201C}switch to Diwali\u{201D}"),
        ("Language", "\u{201C}Hindi\u{201D} \u{00B7} \u{201C}English\u{201D}"),
        ("Magic", "\u{201C}more magic\u{201D} \u{00B7} \u{201C}less magic\u{201D}"),
        ("Output", "\u{201C}download\u{201D} \u{00B7} \u{201C}copy image\u{201D} \u{00B7} \u{201C}new card\u{201D}"),
        ("Always on", "\u{201C}undo\u{201D} \u{00B7} \u{201C}redo\u{201D} \u{00B7} \u{201C}reset\u{201D}"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WishBuilderTools.section("5 \u{00B7} Live Changes", "How the card changes while you talk. There is one microphone, in the bar at the bottom of the Studio.")

            VStack(alignment: .leading, spacing: 6) {
                Text("Language the mic understands").font(.system(size: 12, weight: .semibold))
                Picker("", selection: $app.live.recognition) {
                    Text("Follow the card").tag("card")
                    Text("English").tag("english")
                    Text("\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}").tag("hindi")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 360)
            }

            slider("Pause before a command is applied", value: $app.live.commitDelay, range: 0.4...2.0, format: "%.1f s",
                   note: "Shorter feels faster. Longer lets you finish a long sentence.")
            slider("How long a tapped element stays selected", value: $app.live.selectionSeconds, range: 2...15, format: "%.0f s",
                   note: "It stays selected while your pointer is over the card.")

            VStack(alignment: .leading, spacing: 6) {
                Text("What voice may change").font(.system(size: 12, weight: .semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 6) {
                    ForEach(WishCommandGroup.allNames, id: \.self) { name in
                        Toggle(name, isOn: Binding(
                            get: { app.live.enabledGroups.contains(name) },
                            set: { on in
                                if on {
                                    if !app.live.enabledGroups.contains(name) { app.live.enabledGroups.append(name) }
                                } else {
                                    app.live.enabledGroups.removeAll { $0 == name }
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Test a sentence (nothing is changed)").font(.system(size: 12, weight: .semibold))
                HStack {
                    TextField("make it pink and bigger", text: $sentence)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { test() }
                    Button("Test") { test() }.buttonStyle(.borderedProminent)
                }
                if dryRun.isEmpty {
                    Text("Press Test to see what the mic would do with that sentence.").font(.system(size: 11)).foregroundStyle(WishTheme.muted)
                } else {
                    ForEach(dryRun, id: \.self) { line in
                        Text(line).font(.system(size: 12))
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(WishTheme.accentSoft))

            VStack(alignment: .leading, spacing: 6) {
                Text("Things you can say").font(.system(size: 12, weight: .semibold))
                ForEach(cheatSheet, id: \.0) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.0).font(.system(size: 11, weight: .semibold)).frame(width: 90, alignment: .leading)
                        Text(row.1).font(.system(size: 11)).foregroundStyle(WishTheme.muted)
                    }
                }
                Text("Hindi works too, like \u{201C}\u{0907}\u{0938}\u{0947} \u{0917}\u{0941}\u{0932}\u{093E}\u{092C}\u{0940} \u{0915}\u{0930}\u{094B}\u{201D}. One sentence can hold several changes, joined with \u{201C}and\u{201D} or \u{201C}\u{0914}\u{0930}\u{201D}.")
                    .font(.system(size: 11)).foregroundStyle(WishTheme.muted)
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(String(format: format, value.wrappedValue)).font(.system(size: 12)).foregroundStyle(WishTheme.accent)
            }
            Slider(value: value, in: range)
            Text(note).font(.system(size: 11)).foregroundStyle(WishTheme.muted)
        }
        .frame(maxWidth: 520)
    }

    private func test() {
        let designs = WishDesigns.designs(for: app.kind)
        let env = WishCommandEnvironment(app: app, apps: store.apps, designs: designs, chips: model.chipGroups.flatMap { $0.chips })
        let commands = WishCommandParser.parse(sentence, env: env)
        if commands.isEmpty {
            dryRun = ["Nothing understood. Try one of the examples below."]
            return
        }
        let enabled = Set(app.live.enabledGroups)
        dryRun = commands.map { command in
            let text = WishCommandParser.summary(of: command, env: env)
            if let group = command.action.group, !enabled.contains(group) {
                return "\u{2715} \(text) (blocked: \(group) is switched off)"
            }
            return "\u{2713} \(text)"
        }
    }
}
