// Collection Builder, Prompt Builder and MyDatabase on the home page, and by voice.
import SwiftUI

enum HomeBuilders {
    static let all: [(name: String, symbol: String, line: String, phrases: [String])] = [
        ("Collection Builder", "square.stack.3d.up.fill", "Build a collection of shortcuts with AI", ["collection builder", "build a collection", "make a collection", "create a collection"]),
        ("Prompt Builder", "text.bubble.fill", "Write a prompt, attach media, send it to any AI site", ["prompt builder", "prompt maker", "prompt writer", "write a prompt"]),
        ("MyDatabase", "cylinder.split.1x2.fill", "Contacts, links and tables in one place", ["my database", "mydatabase", "my data base", "database"])
    ]

    /// The builder named in a spoken or typed command, if any.
    static func match(_ normalized: String) -> String? {
        let text = normalized.lowercased()
        // A collection name with "database" in it should still open that collection, so a bare "database" needs "open" or "my".
        for item in all {
            for phrase in item.phrases where text.contains(phrase) {
                if phrase == "database" && !(text.hasPrefix("open database") || text == "database") { continue }
                return item.name
            }
        }
        return nil
    }
}

struct HomeBuildersStrip: View {
    var open: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Builders").font(.headline)
            HStack(spacing: 12) {
                ForEach(HomeBuilders.all, id: \.name) { item in
                    Button { open(item.name) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol).font(.title2).foregroundStyle(Butter.coral).frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.system(size: 14, weight: .semibold))
                                Text(item.line).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Butter.coral.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Open \(item.name). You can also say “open \(item.name.lowercased())”.")
                }
            }
        }
    }
}
