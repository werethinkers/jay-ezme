// The common library: one shelf of pictures every AppBuilder app can pick from, with search and categories.
// It is the same folder as the Wish Studio background library, so a picture added in one place is there in the other.
// Categories are kept in a small categories.json beside the pictures. A picture sent to an app as a template is
// saved here under "Templates · <app>" and shows first in that app's library.
import SwiftUI
import AppKit

@MainActor enum CommonLibrary {
    static let defaultCategories = ["Backgrounds", "Logos", "Birthday", "Anniversary", "Festival", "Templates", "Other"]

    private static var mapURL: URL { WishBackgroundLibrary.folder.appendingPathComponent("categories.json") }

    static func loadMap() -> [String: String] {
        guard let data = try? Data(contentsOf: mapURL), let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    private static func saveMap(_ map: [String: String]) {
        if let data = try? JSONEncoder().encode(map) { try? data.write(to: mapURL, options: .atomic) }
    }

    /// The saved category, or a guess from the file name for pictures added before categories existed.
    static func category(of url: URL, map: [String: String]) -> String {
        if let saved = map[url.lastPathComponent] { return saved }
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        if name.contains("birthday") || name.contains("hbd") { return "Birthday" }
        if name.contains("anniversary") || name.contains("hwa") { return "Anniversary" }
        if name.contains("logo") { return "Logos" }
        if name.contains("festival") || name.contains("diwali") || name.contains("holi") || name.contains("eid") { return "Festival" }
        return "Backgrounds"
    }

    static func setCategory(_ url: URL, _ category: String) {
        var map = loadMap()
        map[url.lastPathComponent] = category
        saveMap(map)
    }

    @discardableResult static func add(_ image: NSImage, name: String, category: String) -> URL? {
        guard let url = WishBackgroundLibrary.add(image, name: name) else { return nil }
        setCategory(url, category)
        return url
    }

    /// Sends a finished picture to an app as a template. Wish Studio uses the library as its background shelf.
    @discardableResult static func send(_ image: NSImage, name: String, toApp app: String) -> Bool {
        let category = app == "Wish Studio" ? "Backgrounds" : "Templates \u{00B7} " + app
        return add(image, name: name, category: category) != nil
    }
}

/// A short list of the Wish Studio apps (id and name) kept in UserDefaults, so other apps can offer them as places to send a picture.
enum WishAppIndex {
    private static let key = "wishAppIndex.v1"
    struct Entry: Codable, Hashable { var id: String; var name: String }
    static func write(_ apps: [WishApp]) {
        let list = apps.map { Entry(id: $0.id, name: $0.name) }
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }
    static func read() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key), let list = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return list
    }
}

struct CommonLibrarySheet: View {
    var app: String
    var onPick: (NSImage, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var files: [URL] = []
    @State private var map: [String: String] = [:]
    @State private var query = ""
    @State private var category = "All"
    @State private var message = ""

    private var thisApp: String { "This app's templates" }

    private var chips: [String] {
        var list = ["All", thisApp] + CommonLibrary.defaultCategories
        for value in Set(map.values).sorted() where !value.hasPrefix("Templates") && !list.contains(value) { list.append(value) }
        return list
    }

    private func matches(_ url: URL) -> Bool {
        let value = CommonLibrary.category(of: url, map: map)
        switch category {
        case "All": break
        case thisApp: if value != "Templates \u{00B7} " + app { return false }
        case "Templates": if !value.hasPrefix("Templates") { return false }
        default: if value != category { return false }
        }
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || url.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains(text) || value.localizedCaseInsensitiveContains(text)
    }

    private var shown: [URL] {
        let list = files.filter { matches($0) }
        // Templates made for this app come first.
        let mine = "Templates \u{00B7} " + app
        return list.filter { CommonLibrary.category(of: $0, map: map) == mine } + list.filter { CommonLibrary.category(of: $0, map: map) != mine }
    }

    private func reload() {
        files = WishBackgroundLibrary.files()
        map = CommonLibrary.loadMap()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Library").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(.bordered)
            }
            MerlinBar(text: $query, placeholder: "Search the library\u{2026}", showsBadge: false)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        Button { category = chip } label: {
                            Text(chip).font(.caption.weight(.semibold)).lineLimit(1).fixedSize()
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .foregroundStyle(category == chip ? Color.white : Butter.cocoa)
                                .background(category == chip ? Butter.coral : Butter.cream, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            if shown.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "photo.stack", description: Text("Add pictures, or finish something and use Send to app as template."))
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        ForEach(shown, id: \.self) { url in
                            Button {
                                if let image = NSImage(contentsOf: url) { onPick(image, url.lastPathComponent); dismiss() }
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.93))
                                        if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFit().padding(4) }
                                    }
                                    .frame(height: 100)
                                    Text(url.deletingPathExtension().lastPathComponent).font(.caption).lineLimit(1)
                                    Text(CommonLibrary.category(of: url, map: map)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Menu("Move to category") {
                                    ForEach(CommonLibrary.defaultCategories, id: \.self) { name in
                                        Button(name) { CommonLibrary.setCategory(url, name); reload() }
                                    }
                                }
                                Button("Remove from library", role: .destructive) { try? FileManager.default.removeItem(at: url); reload() }
                            }
                        }
                    }
                    .padding(2)
                }
                .frame(height: 300)
            }
            HStack {
                Text(message).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { addPictures() } label: { Label("Add pictures", systemImage: "plus") }.buttonStyle(.bordered)
            }
        }
        .padding(22).frame(width: 640)
        .onAppear { reload() }
    }

    private func addPictures() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        let target = (category == "All" || category == thisApp) ? "Backgrounds" : category
        var added = 0
        for url in panel.urls {
            if let image = NSImage(contentsOf: url), CommonLibrary.add(image, name: url.deletingPathExtension().lastPathComponent, category: target) != nil { added += 1 }
        }
        message = added == 0 ? "Nothing was added." : "Added \(added) to \(target)."
        reload()
    }
}
