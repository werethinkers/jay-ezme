import SwiftUI
import AppKit

/// What the first character after the backslash means: \$ apps, \@ people, \# collections, \= calculations.
/// Anything else after the backslash is the common search over everything.
enum PopupMode: Equatable {
    case none, apps, people, collections, math

    var sigil: String { switch self { case .none: return ""; case .apps: return "$"; case .people: return "@"; case .collections: return "#"; case .math: return "=" } }
    var title: String { switch self { case .none: return "Everything"; case .apps: return "Apps"; case .people: return "People"; case .collections: return "Collections"; case .math: return "Calculate" } }
    var symbol: String { switch self { case .none: return "sparkle.magnifyingglass"; case .apps: return "square.grid.2x2.fill"; case .people: return "person.crop.circle.fill"; case .collections: return "folder.fill"; case .math: return "function" } }
    var hint: String {
        switch self {
        case .none: return ""
        case .apps: return "Only your apps. Type a name, press Enter. \\$s takes a screenshot of the whole screen."
        case .people: return "Only people and the shortcuts that belong to them."
        case .collections: return "Pick a collection and see only its shortcuts."
        case .math: return "Type a calculation, such as \\=12*8+5."
        }
    }

    /// Splits the typed text (without the backslash) into the mode and the rest.
    static func parse(_ typed: String) -> (mode: PopupMode, rest: String) {
        guard let first = typed.first else { return (.none, typed) }
        let rest = String(typed.dropFirst())
        switch first {
        case "$": return (.apps, rest)
        case "@": return (.people, rest)
        case "#": return (.collections, rest)
        case "=": return (.math, rest)
        default: return (.none, typed)
        }
    }

    /// `\$s` means: take a screenshot of the whole screen.
    static func isScreenshotCommand(_ trigger: String) -> Bool {
        trigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "\\$s"
    }
}

extension Notification.Name {
    static let keydoPopupPickApp = Notification.Name("KeyDoPopupPickApp")
    static let keydoPopupFullScreenshot = Notification.Name("KeyDoPopupFullScreenshot")
}

/// One app as the popup lists it, with how many values it needs.
struct PopupAppItem: Identifiable {
    let name: String
    let prefix: String
    let variableCount: Int
    var id: String { name }
    /// Two or three one-word values are quick to type after the command. More than that is easier to fill in the app form by voice.
    var isQuick: Bool { variableCount <= 3 }
}

enum PopupApps {
    static func all() -> [PopupAppItem] {
        let defaults = UserDefaults.standard
        let names = (try? JSONDecoder().decode([String].self, from: Data((defaults.string(forKey: "ezmeCustomBuilderAppsJSON") ?? "[]").utf8))) ?? []
        return names.map { name in
            let prefix = defaults.string(forKey: "ezmeBuilderPrefix." + name) ?? name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            let variables = (defaults.string(forKey: "ezmeBuilderVariables." + name) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return PopupAppItem(name: name, prefix: prefix.trimmingCharacters(in: CharacterSet(charactersIn: "\\/ ")), variableCount: variables.count)
        }.filter { !$0.prefix.isEmpty }
    }

    static func matching(_ query: String) -> [PopupAppItem] {
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let items = all().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !wanted.isEmpty else { return items }
        return items.filter { $0.name.lowercased().contains(wanted) || $0.prefix.lowercased().hasPrefix(wanted) }
    }
}

/// The whole popup body when the person types \$ : apps only, nothing else to confuse.
struct PopupAppList: View {
    let query: String
    var pick: (PopupAppItem) -> Void
    var body: some View {
        let items = PopupApps.matching(query)
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text("No app matches “\(query)”. Make one in AppBuilder.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 10)
            }
            ForEach(items) { item in
                Button { pick(item) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2.fill").foregroundStyle(Butter.coral).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Butter.cocoa)
                            Text(item.isQuick ? "\\\(item.prefix)-value  ·  \(item.variableCount) value\(item.variableCount == 1 ? "" : "s"), type them after the command"
                                              : "\(item.variableCount) values: opens the form, fill it by voice, then copy and paste")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: item.isQuick ? "bolt.fill" : "mic.fill").foregroundStyle(Butter.coral)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Butter.cream, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
        }
    }
}

/// Small bar under the search field that says which mode the backslash is in.
struct PopupModeBanner: View {
    let mode: PopupMode
    var body: some View {
        if mode != .none {
            HStack(spacing: 8) {
                Image(systemName: mode.symbol).foregroundStyle(Butter.coral)
                Text("\\\(mode.sigil)  \(mode.title)").font(.system(size: 12, weight: .heavy)).foregroundStyle(Butter.cocoa)
                Text(mode.hint).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Butter.coral.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
