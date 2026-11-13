// Hover details for cards and tabs.
//
// The details appear in a small popover beside the card or tab, never on top of it, so a picture, GIF or
// video cover stays fully visible. There is no system tooltip as well, so the same words are not shown twice.
import SwiftUI

struct HoverInfoPopover: ViewModifier {
    var title: String
    var detail: String
    var footnote: String
    var symbol: String
    var edge: Edge
    @State private var hovering = false
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hovering = inside
                if inside {
                    // A short wait keeps the popover from flashing while the pointer only passes over.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if hovering { shown = true } }
                } else {
                    shown = false
                }
            }
            .popover(isPresented: $shown, arrowEdge: edge) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.system(size: 15, weight: .bold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                    if !detail.isEmpty {
                        Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if !footnote.isEmpty {
                        Label(footnote, systemImage: symbol).font(.caption.weight(.bold)).foregroundStyle(Butter.coral)
                    }
                }
                .padding(14)
                .frame(width: 260, alignment: .leading)
            }
    }
}

extension View {
    /// Shows the title, a short description and one highlighted line in a popover beside this view.
    func hoverInfo(title: String, detail: String = "", footnote: String = "", symbol: String = "sparkles", edge: Edge = .trailing) -> some View {
        modifier(HoverInfoPopover(title: title, detail: detail, footnote: footnote, symbol: symbol, edge: edge))
    }
}
