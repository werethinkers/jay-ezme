import SwiftUI

// Simple choosers for the app popup: templates as small pictures, colours as swatches.

struct TemplateChoice: Identifiable {
    var token: String       // "" for the default template, the template's name, or "tempr" for a random one
    var name: String
    var image: NSImage?
    var id: String { token.isEmpty ? "default" : token }
}

struct TemplateStrip: View {
    var choices: [TemplateChoice]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(choices) { choice in
                    Button { selection = choice.token } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.94))
                                if let image = choice.image {
                                    Image(nsImage: image).resizable().interpolation(.medium).scaledToFit().padding(3)
                                } else if choice.token == "tempr" {
                                    Image(systemName: "dice.fill").font(.system(size: 22)).foregroundStyle(Butter.coral)
                                } else {
                                    ProgressView().controlSize(.small)
                                }
                            }
                            .frame(width: 74, height: 74)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection == choice.token ? Butter.coral : Color.secondary.opacity(0.25), lineWidth: selection == choice.token ? 2.5 : 1))
                            Text(choice.name).font(.system(size: 10, weight: selection == choice.token ? .bold : .regular)).lineLimit(1).frame(width: 78)
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(.vertical, 2).padding(.horizontal, 2)
        }
    }
}

/// Colour names with swatches. Picking one writes its name into the box, so the design uses it.
struct ColourOptions: View {
    @Binding var text: String
    private let options: [(String, Color)] = [
        ("Red", .red), ("Orange", .orange), ("Gold", Color(red: 0.85, green: 0.65, blue: 0.13)), ("Yellow", .yellow),
        ("Green", .green), ("Teal", .teal), ("Blue", .blue), ("Purple", .purple), ("Pink", .pink),
        ("Brown", .brown), ("Black", .black), ("White", .white)
    ]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(options, id: \.0) { option in
                let chosen = text.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(option.0) == .orderedSame
                Button { text = option.0 } label: {
                    Circle().fill(option.1).frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.45), lineWidth: 1))
                        .overlay(Circle().stroke(Butter.coral, lineWidth: chosen ? 3 : 0).padding(-3))
                }.buttonStyle(.plain).help(option.0)
            }
            Spacer(minLength: 0)
        }.padding(.top, 2)
    }
}
