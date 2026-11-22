// Ez Tools (was Ez Studio): every tool is its own tab, in a clean row like the apps in WishStudio.
import SwiftUI

struct EzToolDef: Identifiable {
    let id: String
    let title: String
    let hint: String
    let symbol: String
    let colors: [Color]
}

enum EzTools {
    static let all: [EzToolDef] = [
        EzToolDef(id: "Image Studio", title: "Image Studio", hint: "Draw pictures with AI", symbol: "paintbrush.pointed.fill",
                  colors: [Color(red: 0.93, green: 0.35, blue: 0.62), Color(red: 0.55, green: 0.36, blue: 0.96)]),
        EzToolDef(id: "ChatGPT Image Edit", title: "Image Edit", hint: "Fix or change a picture", symbol: "wand.and.stars",
                  colors: [Color(red: 0.98, green: 0.55, blue: 0.25), Color(red: 0.90, green: 0.33, blue: 0.31)]),
        EzToolDef(id: "Media Resizer", title: "Resize and Crop", hint: "Any size, any shape", symbol: "crop",
                  colors: [Color(red: 0.30, green: 0.65, blue: 0.98), Color(red: 0.20, green: 0.45, blue: 0.90)]),
        EzToolDef(id: "Video Editor", title: "Video Editor", hint: "Cut, join and trim", symbol: "film.fill",
                  colors: [Color(red: 0.55, green: 0.85, blue: 0.35), Color(red: 0.12, green: 0.70, blue: 0.62)]),
        EzToolDef(id: "Photo Collage", title: "Photo Collage", hint: "Many photos, one picture", symbol: "square.grid.3x3.fill",
                  colors: [Color(red: 0.99, green: 0.78, blue: 0.25), Color(red: 0.96, green: 0.40, blue: 0.55)]),
        EzToolDef(id: "Logo on Background", title: "Logo on Background", hint: "Put your logo on a scene", symbol: "photo.on.rectangle.angled",
                  colors: [Color(red: 0.40, green: 0.75, blue: 0.90), Color(red: 0.35, green: 0.40, blue: 0.85)]),
        EzToolDef(id: "Bollywood 80s", title: "Bollywood 80s", hint: "Retro film poster look", symbol: "star.fill",
                  colors: [Color(red: 0.95, green: 0.40, blue: 0.35), Color(red: 0.70, green: 0.25, blue: 0.55)]),
        EzToolDef(id: "Font Creator", title: "Font Creator", hint: "Make your own letters", symbol: "textformat",
                  colors: [Color(red: 0.55, green: 0.50, blue: 0.95), Color(red: 0.30, green: 0.30, blue: 0.75)])
    ]
}

/// The row of tool tabs. The chosen tab is filled with its colour; the others are quiet cards.
struct EzToolTabs: View {
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(EzTools.all) { tool in tab(tool) }
            }
            .padding(.vertical, 4).padding(.horizontal, 2)
        }
    }

    private func tab(_ tool: EzToolDef) -> some View {
        let on = selected == tool.id
        return Button { withAnimation(.easeInOut(duration: 0.15)) { selected = tool.id } } label: {
            HStack(spacing: 10) {
                Image(systemName: tool.symbol).font(.system(size: 15, weight: .bold))
                    .foregroundStyle(on ? Color.white : Color.white)
                    .frame(width: 34, height: 34)
                    .background(LinearGradient(colors: tool.colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.title).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                    Text(tool.hint).font(.system(size: 10, weight: .medium)).lineLimit(1).opacity(0.7)
                }
            }
            .foregroundStyle(Butter.cocoa)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14).fill(on ? Butter.honey.opacity(0.35) : Color.white))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Butter.coral : Butter.honey.opacity(0.7), lineWidth: on ? 2 : 1))
            .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }
}
