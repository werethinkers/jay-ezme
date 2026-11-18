// A dropdown you can type into: press it, start typing, and the list narrows. Return takes the first match.
import SwiftUI

struct SearchablePick: View {
    var title: String
    var options: [String]
    var symbol: ((String) -> String)? = nil
    @Binding var selection: String
    @State private var open = false
    @State private var query = ""

    private var shown: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return options }
        let starts = options.filter { $0.lowercased().hasPrefix(q) }
        let contains = options.filter { !$0.lowercased().hasPrefix(q) && $0.lowercased().contains(q) }
        return starts + contains
    }

    var body: some View {
        Button { query = ""; open = true } label: {
            HStack(spacing: 6) {
                if let symbol, !selection.isEmpty { Image(systemName: symbol(selection)).font(.system(size: 11)).foregroundStyle(Butter.coral) }
                Text(selection.isEmpty ? title : selection).font(.system(size: 12)).foregroundStyle(Butter.cocoa).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(Butter.cocoa.opacity(0.6))
            }
            .padding(.vertical, 6).padding(.horizontal, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Butter.honey, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Type to find\u{2026}", text: $query).textFieldStyle(.plain).onSubmit { if let first = shown.first { pick(first) } }
                }
                .padding(8)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(shown.prefix(80), id: \.self) { option in
                            Button { pick(option) } label: {
                                HStack(spacing: 6) {
                                    if let symbol { Image(systemName: symbol(option)).font(.system(size: 11)).frame(width: 16).foregroundStyle(Butter.coral) }
                                    Text(option).font(.system(size: 12)).lineLimit(1)
                                    Spacer()
                                    if option == selection { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Butter.coral) }
                                }
                                .padding(.vertical, 5).padding(.horizontal, 10).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if shown.isEmpty { Text("Nothing matches.").font(.system(size: 11)).foregroundStyle(.secondary).padding(10) }
                    }
                }
            }
            .frame(width: 260, height: 300)
        }
    }

    private func pick(_ option: String) { selection = option; open = false }
}

/// All the functions, searchable by name or by what they do. Tap to add, or drag a row onto the page.
struct FunctionPickerList: View {
    var onPick: (String) -> Void
    @State private var query = ""
    @State private var category = ""

    private var shown: [WishFunctionInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = category.isEmpty ? WishFunctionCatalog.all : WishFunctionCatalog.all.filter { $0.category == category }
        guard !q.isEmpty else { return category.isEmpty ? WishFunctionCatalog.live + WishFunctionCatalog.all.filter { $0.category != "Live & place" }.prefix(30) : pool }
        return pool.filter { $0.name.lowercased().contains(q) || $0.summary.lowercased().contains(q) || $0.category.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a function, like days, sum or round", text: $query).textFieldStyle(.roundedBorder)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach([""] + WishFunctionCatalog.categories, id: \.self) { name in
                        Button { category = name } label: {
                            Text(name.isEmpty ? "All" : name).font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(category == name ? Butter.coral : Butter.honey.opacity(0.35)))
                                .foregroundStyle(category == name ? Color.white : Butter.cocoa)
                        }.buttonStyle(.plain)
                    }
                }
            }
            ForEach(shown.prefix(60)) { info in
                Button { onPick("{=\(info.syntax)}") } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.syntax).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Butter.cocoa)
                        Text(info.summary).font(.system(size: 10)).foregroundStyle(Butter.cocoa.opacity(0.7)).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Butter.honey.opacity(0.7), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .onDrag { NSItemProvider(object: "{=\(info.syntax)}" as NSString) }
            }
            Text("You can also just say it, like \u{201C}days to event date\u{201D} or \u{201C}today plus 7\u{201D}. No brackets needed.")
                .font(.system(size: 10)).foregroundStyle(Butter.cocoa.opacity(0.7))
        }
    }
}
