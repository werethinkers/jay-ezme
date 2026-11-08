// WishStudio card canvas: draws greeting cards and infographics, and exports them as PNG.
import SwiftUI
import AppKit

// MARK: - Colour helpers

private func wishRGB(_ hex: String) -> (Double, Double, Double) {
    var text = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    if text.count == 3 {
        text = text.map { String([$0, $0]) }.joined()
    }
    var value: UInt64 = 0
    Scanner(string: text).scanHexInt64(&value)
    let red = Double((value >> 16) & 0xFF) / 255
    let green = Double((value >> 8) & 0xFF) / 255
    let blue = Double(value & 0xFF) / 255
    return (red, green, blue)
}

func wishHexString(_ red: Double, _ green: Double, _ blue: Double) -> String {
    let r = Int((min(1, max(0, red)) * 255).rounded())
    let g = Int((min(1, max(0, green)) * 255).rounded())
    let b = Int((min(1, max(0, blue)) * 255).rounded())
    return String(format: "#%02X%02X%02X", r, g, b)
}

/// Mixes a colour toward another one. amount 0 = the first colour, 1 = the second.
func wishMix(_ hex: String, with other: String, amount: Double) -> String {
    let a = wishRGB(hex)
    let b = wishRGB(other)
    return wishHexString(a.0 + (b.0 - a.0) * amount, a.1 + (b.1 - a.1) * amount, a.2 + (b.2 - a.2) * amount)
}

func wishLuminance(_ hex: String) -> Double {
    let c = wishRGB(hex)
    return 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
}

func wishIsDark(_ hex: String) -> Bool {
    return wishLuminance(hex) < 0.45
}

extension Color {
    init(wishHex: String) {
        let c = wishRGB(wishHex)
        self.init(.sRGB, red: c.0, green: c.1, blue: c.2, opacity: 1)
    }
}

// MARK: - Infographic data

struct WishDatum: Identifiable {
    let id: Int
    let label: String
    let value: Double?
}

enum WishData {
    /// One item per line. "Label", "Label, 40", "Label: 40" and "Label<tab>40" are all understood.
    static func parse(_ text: String) -> [WishDatum] {
        var items: [WishDatum] = []
        let pattern = "^(.*?)[,:\\t]\\s*([-+]?\\d[\\d,]*\\.?\\d*)\\s*%?\\s*$"
        let expression = try? NSRegularExpression(pattern: pattern)
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            var label = line
            var value: Double? = nil
            let ns = line as NSString
            if let expression = expression, let match = expression.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 2 {
                let left = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                let right = ns.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: "")
                if !left.isEmpty, let number = Double(right) {
                    label = left
                    value = number
                }
            }
            items.append(WishDatum(id: items.count, label: label, value: value))
            if items.count >= 24 { break }
        }
        return items
    }

    /// Values for charts: when no numbers were given, every item counts the same.
    static func weights(_ items: [WishDatum]) -> [Double] {
        let given = items.map { max(0, $0.value ?? 0) }
        if given.reduce(0, +) <= 0 { return items.map { _ in 1 } }
        return items.map { $0.value.map { max(0, $0) } ?? 0 }
    }
}

struct WishArc: Shape {
    var start: Double
    var end: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(start * 360 - 90), endAngle: .degrees(end * 360 - 90), clockwise: false)
        return path
    }
}

// MARK: - Magic

private struct WishSparkles: View {
    let count: Int
    let color: Color
    let animated: Bool
    let size: CGSize

    private func seed(_ index: Int, _ salt: Double) -> Double {
        let raw = sin(Double(index) * 12.9898 + salt * 78.233) * 43758.5453
        return raw - raw.rounded(.down)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !animated)) { timeline in
            let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    sparkle(index, time)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }

    private func sparkle(_ index: Int, _ time: Double) -> some View {
        let x = seed(index, 1) * size.width
        let speed = 6 + seed(index, 2) * 14
        let baseY = seed(index, 3) * size.height
        var y = baseY - time * speed
        y = y.truncatingRemainder(dividingBy: size.height)
        if y < 0 { y += size.height }
        let pulse = 0.35 + 0.65 * abs(sin(time * (0.6 + seed(index, 4)) + Double(index)))
        let diameter = 8 + seed(index, 5) * 12
        return Image(systemName: "sparkle")
            .font(.system(size: diameter))
            .foregroundStyle(color.opacity(animated ? pulse * 0.7 : 0.45))
            .position(x: x, y: y)
    }
}

// MARK: - The canvas

struct WishCardCanvas: View {
    let app: WishApp
    let card: WishCard
    let design: WishDesign
    let context: WishContext
    var selected: String? = nil
    var animated: Bool = true
    var onSelect: (String?) -> Void = { _ in }

    static let size = CGSize(width: 520, height: 660)

    // MARK: Palette

    private var backgroundHex: String { return card.backgroundHex ?? design.background }
    private var accentHex: String { return card.accentHex ?? design.accent }
    private var inkHex: String {
        if card.backgroundHex == nil { return design.ink }
        if wishIsDark(backgroundHex) { return "#F6F1FF" }
        return wishIsDark(design.ink) ? design.ink : "#2B2B2B"
    }
    private var accent: Color { return Color(wishHex: accentHex) }
    private var ink: Color { return Color(wishHex: inkHex) }

    private func text(_ key: String) -> String {
        return context.variables[key.lowercased()] ?? ""
    }

    private func style(_ key: String) -> WishElementStyle {
        return card.styles[key] ?? WishElementStyle()
    }

    private func font(_ size: CGFloat, weight: Font.Weight, italic: Bool) -> Font {
        var base: Font
        switch card.fontStyle {
        case .classic, .romantic: base = Font.system(size: size, weight: weight, design: .serif)
        case .modern: base = Font.system(size: size, weight: weight, design: .default)
        }
        if italic || card.fontStyle == .romantic { base = base.italic() }
        return base
    }

    private func selectionRing(_ key: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(accent, style: StrokeStyle(lineWidth: 1.6, dash: [5, 3]))
            .padding(-7)
            .opacity(selected == key ? 1 : 0)
    }

    @ViewBuilder
    private func line(_ key: String, size: CGFloat, weight: Font.Weight = .regular, color: Color, tracking: CGFloat = 0, upper: Bool = false, opacity: Double = 1) -> some View {
        let value = text(key)
        let st = style(key)
        if !st.hidden && !value.isEmpty {
            let weightToUse: Font.Weight = st.bold == true ? .bold : (st.bold == false ? .regular : weight)
            let tint = st.colorHex.map { Color(wishHex: $0) } ?? color
            Text(value)
                .font(font(size * CGFloat(card.textScale) * CGFloat(st.scale), weight: weightToUse, italic: st.italic == true))
                .tracking(tracking)
                .textCase(upper ? .uppercase : nil)
                .foregroundStyle(tint.opacity(opacity))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .overlay(selectionRing(key))
                .offset(x: CGFloat(st.dx), y: CGFloat(st.dy))
                .contentShape(Rectangle())
                .onTapGesture { onSelect(key) }
        }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Rectangle().fill(Color(wishHex: backgroundHex))
            decoration
            if app.kind == .greeting {
                greetingBody
            } else {
                infographicBody
            }
            if card.magic > 0 {
                WishSparkles(count: [0, 6, 12, 24][min(3, max(0, card.magic))], color: accent, animated: animated, size: WishCardCanvas.size)
            }
        }
        .frame(width: WishCardCanvas.size.width, height: WishCardCanvas.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .contentShape(Rectangle())
        .onTapGesture { onSelect(nil) }
    }

    @ViewBuilder
    private var decoration: some View {
        if app.kind == .greeting {
            switch design.layout {
            case "arch":
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 250, bottomLeading: 18, bottomTrailing: 18, topTrailing: 250))
                    .fill(accent.opacity(0.10))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 26)
            case "band":
                VStack {
                    Rectangle().fill(accent).frame(height: 16)
                    Spacer()
                    Rectangle().fill(accent).frame(height: 16)
                }
            default:
                ZStack {
                    RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.7), lineWidth: 1.4).padding(16)
                    RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.35), lineWidth: 0.7).padding(23)
                }
            }
        } else {
            RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.35), lineWidth: 1).padding(16)
        }
    }

    // MARK: Greeting

    private static let knownKeys: Set<String> = ["eyebrow", "title", "name", "message", "from", "date"]

    private var extraFields: [WishField] {
        return app.fields.filter { !WishCardCanvas.knownKeys.contains($0.key.lowercased()) }
    }

    private var greetingBody: some View {
        VStack(spacing: 16) {
            line("eyebrow", size: 11, weight: .semibold, color: accent, tracking: 3, upper: true)
            artwork
            line("title", size: 40, weight: .semibold, color: ink)
            line("name", size: 22, weight: .medium, color: accent)
            line("message", size: 17, color: ink, opacity: 0.85)
            ForEach(extraFields) { field in
                line(field.key, size: 16, color: ink, opacity: 0.85)
            }
            Spacer(minLength: 0)
            line("from", size: 18, weight: .medium, color: ink)
            line("date", size: 12, weight: .semibold, color: accent, tracking: 2, upper: true)
        }
        .padding(.horizontal, 46)
        .padding(.vertical, 50)
    }

    @ViewBuilder
    private var artwork: some View {
        let st = style("artwork")
        if !st.hidden {
            let tint = st.colorHex.map { Color(wishHex: $0) } ?? accent
            ZStack {
                Circle().fill(tint.opacity(0.14)).frame(width: 150, height: 150)
                Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1).frame(width: 168, height: 168)
                Image(systemName: card.artwork)
                    .font(.system(size: 62 * CGFloat(st.scale), weight: .regular))
                    .foregroundStyle(tint)
            }
            .frame(height: 172)
            .overlay(selectionRing("artwork"))
            .offset(x: CGFloat(st.dx), y: CGFloat(st.dy))
            .contentShape(Rectangle())
            .onTapGesture { onSelect("artwork") }
        }
    }

    // MARK: Infographic

    private var chartAccentHex: String {
        return style("data").colorHex ?? accentHex
    }

    private func chartColor(_ index: Int) -> Color {
        let others = ["#C0507A", "#3E9A9A", "#C99A2E", "#4F7FD1", "#6BA36B", "#9A62C9", "#D9743A"]
        if index == 0 { return Color(wishHex: chartAccentHex) }
        return Color(wishHex: others[(index - 1) % others.count])
    }

    private var infographicBody: some View {
        VStack(spacing: 18) {
            line("eyebrow", size: 11, weight: .semibold, color: accent, tracking: 3, upper: true)
            line("title", size: 32, weight: .semibold, color: ink)
            chart
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(selectionRing("data"))
                .offset(x: CGFloat(style("data").dx), y: CGFloat(style("data").dy))
                .contentShape(Rectangle())
                .onTapGesture { onSelect("data") }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 46)
    }

    @ViewBuilder
    private var chart: some View {
        let items = WishData.parse(text("data"))
        if items.isEmpty {
            Text("Add data on the right")
                .font(.system(size: 15))
                .foregroundStyle(ink.opacity(0.5))
        } else {
            switch design.layout {
            case "table": tableChart(items)
            case "bars": barsChart(items)
            case "donut": donutChart(items)
            case "flow": flowChart(items)
            case "grid": gridChart(items)
            case "timeline": timelineChart(items)
            case "ranked": rankedChart(items)
            default: circlesChart(items)
            }
        }
    }

    private func valueText(_ item: WishDatum) -> String {
        guard let value = item.value else { return "" }
        return WishFormula.formatNumber(value)
    }

    private func circlesChart(_ items: [WishDatum]) -> some View {
        let columns = items.count <= 4 ? 2 : 3
        let rows = Int((Double(items.count) / Double(columns)).rounded(.up))
        return GeometryReader { geo in
            let gap: CGFloat = 14
            let cell = max(40, min((geo.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns), (geo.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)))
            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < items.count {
                                circleCell(items[index], index: index, size: cell)
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func circleCell(_ item: WishDatum, index: Int, size: CGFloat) -> some View {
        let color = chartColor(index)
        return ZStack {
            Circle().fill(color.opacity(0.10))
            Circle().strokeBorder(color, lineWidth: 3)
            VStack(spacing: 4) {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: max(9, size * 0.07), weight: .semibold))
                    .foregroundStyle(ink.opacity(0.6))
                Text(item.label)
                    .font(font(min(28, size * 0.17) * CGFloat(card.textScale), weight: .semibold, italic: false))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                if !valueText(item).isEmpty {
                    Text(valueText(item))
                        .font(.system(size: max(10, size * 0.09), weight: .medium))
                        .foregroundStyle(color)
                }
            }
            .padding(size * 0.12)
        }
        .frame(width: size, height: size)
    }

    private func tableChart(_ items: [WishDatum]) -> some View {
        GeometryReader { geo in
            let rowHeight = min(46, geo.size.height / CGFloat(items.count))
            VStack(spacing: 0) {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", item.id + 1))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(chartColor(0))
                            .frame(width: 26, alignment: .leading)
                        Text(item.label)
                            .font(font(min(18, rowHeight * 0.5) * CGFloat(card.textScale), weight: .medium, italic: false))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 8)
                        Text(valueText(item))
                            .font(.system(size: min(18, rowHeight * 0.5), weight: .semibold))
                            .foregroundStyle(chartColor(0))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: rowHeight)
                    .background(item.id % 2 == 0 ? chartColor(0).opacity(0.10) : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(chartColor(0).opacity(0.35), lineWidth: 1))
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    private func barsChart(_ items: [WishDatum]) -> some View {
        let weights = WishData.weights(items)
        let top = max(weights.max() ?? 1, 0.0001)
        return VStack(spacing: 12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.label)
                            .font(font(15 * CGFloat(card.textScale), weight: .medium, italic: false))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                        Spacer()
                        Text(valueText(item))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(chartColor(item.id))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(chartColor(item.id).opacity(0.14))
                            Capsule().fill(chartColor(item.id)).frame(width: max(8, geo.size.width * CGFloat(weights[item.id] / top)))
                        }
                    }
                    .frame(height: 14)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func donutChart(_ items: [WishDatum]) -> some View {
        let weights = WishData.weights(items)
        let total = max(weights.reduce(0, +), 0.0001)
        var starts: [Double] = []
        var running = 0.0
        for weight in weights {
            starts.append(running / total)
            running += weight
        }
        return VStack(spacing: 18) {
            ZStack {
                ForEach(items) { item in
                    WishArc(start: starts[item.id], end: min(1, starts[item.id] + weights[item.id] / total - 0.004))
                        .stroke(chartColor(item.id), style: StrokeStyle(lineWidth: 40, lineCap: .butt))
                        .padding(20)
                }
                Text(items.count == 1 ? "1" : "\(items.count)")
                    .font(font(34, weight: .semibold, italic: false))
                    .foregroundStyle(ink)
            }
            .frame(width: 220, height: 220)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.prefix(8)) { item in
                    HStack(spacing: 8) {
                        Circle().fill(chartColor(item.id)).frame(width: 10, height: 10)
                        Text(item.label)
                            .font(font(14 * CGFloat(card.textScale), weight: .regular, italic: false))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                        Spacer()
                        Text(valueText(item)).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink.opacity(0.7))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func flowChart(_ items: [WishDatum]) -> some View {
        let compact = items.count > 5
        return VStack(spacing: compact ? 4 : 8) {
            ForEach(items) { item in
                Text(item.label)
                    .font(font((compact ? 15 : 19) * CGFloat(card.textScale), weight: .semibold, italic: false))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 20)
                    .padding(.vertical, compact ? 6 : 11)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(chartColor(item.id)))
                if item.id < items.count - 1 {
                    Image(systemName: "chevron.down")
                        .font(.system(size: compact ? 10 : 13, weight: .bold))
                        .foregroundStyle(ink.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func gridChart(_ items: [WishDatum]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: "%02d", item.id + 1))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(chartColor(item.id))
                    Text(item.label)
                        .font(font(17 * CGFloat(card.textScale), weight: .semibold, italic: false))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    if !valueText(item).isEmpty {
                        Text(valueText(item)).font(.system(size: 13, weight: .medium)).foregroundStyle(ink.opacity(0.65))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(chartColor(item.id).opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(chartColor(item.id).opacity(0.5), lineWidth: 1))
            }
        }
    }

    private func timelineChart(_ items: [WishDatum]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Circle().fill(chartColor(item.id)).frame(width: 14, height: 14)
                        if item.id < items.count - 1 {
                            Rectangle().fill(chartColor(0).opacity(0.3)).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                            .font(font(17 * CGFloat(card.textScale), weight: .semibold, italic: false))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                        if !valueText(item).isEmpty {
                            Text(valueText(item)).font(.system(size: 12, weight: .medium)).foregroundStyle(ink.opacity(0.6))
                        }
                    }
                    .padding(.bottom, 14)
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }

    private func rankedChart(_ items: [WishDatum]) -> some View {
        let ordered = items.sorted { ($0.value ?? -1) > ($1.value ?? -1) }
        return VStack(spacing: 10) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { position, item in
                HStack(spacing: 14) {
                    Text("\(position + 1)")
                        .font(font(30, weight: .semibold, italic: false))
                        .foregroundStyle(chartColor(0))
                        .frame(width: 40)
                    Text(item.label)
                        .font(font(18 * CGFloat(card.textScale), weight: .medium, italic: false))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer()
                    Text(valueText(item)).font(.system(size: 14, weight: .semibold)).foregroundStyle(chartColor(0))
                }
                .padding(.vertical, 6)
                Divider().overlay(ink.opacity(0.15))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Export

enum WishExport {
    @MainActor
    static func image<V: View>(of view: V, scale: CGFloat = 2) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.nsImage
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
