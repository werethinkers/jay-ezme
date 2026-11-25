import SwiftUI

/// Overlay sidebar that slides in from the left without pushing content.
/// Triggered by the hamburger button in the top bar or hovering the left edge.
struct KeyDoSidebarPanel: View {
    @Binding var section: String
    @Binding var isVisible: Bool
    var username: String
    var tier: SubscriptionTier
    var onSignOut: () -> Void
    var onNavigate: (String) -> Void

    @State private var accountPopoverShowing = false
    @ObservedObject private var credits = CreditsCenter.shared
    private let panelWidth: CGFloat = 232

    var body: some View {
        HStack(spacing: 0) {
            panelContent
                .frame(width: panelWidth)
                .background(sidebarGradient)
                .shadow(color: .black.opacity(0.45), radius: 22, x: 8, y: 0)

            // Transparent veil — tap outside to dismiss
            Color.black.opacity(0.001)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { isVisible = false }
                }
        }
    }

    // MARK: Panel

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider().background(Color.white.opacity(0.1)).padding(.horizontal, 14)
            navScrollView
            Spacer(minLength: 0)
            Divider().background(Color.white.opacity(0.1)).padding(.horizontal, 14)
            accountChip.padding(12)
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 0) {
            if let logo = keyDoLightLogoImage() {
                Image(nsImage: logo).resizable().scaledToFit()
                    .frame(width: 148, height: 42)
            } else {
                Text("KeyDo").font(.headline).foregroundStyle(.white)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isVisible = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close sidebar")
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14)
    }

    private var navScrollView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(EzMeNavigation.areas) { area in
                    if !area.title.isEmpty {
                        Text(area.title.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.38))
                            .tracking(0.7)
                            .padding(.leading, 16).padding(.top, 12).padding(.bottom, 2)
                    }
                    ForEach(area.items) { item in navRow(item) }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func navRow(_ item: EzMeNavigation.Item) -> some View {
        let active = section == item.id
        return Button {
            onNavigate(item.id)
            withAnimation(.easeInOut(duration: 0.18)) { isVisible = false }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: navIcon(item.id))
                    .font(.system(size: 13, weight: active ? .bold : .regular))
                    .frame(width: 20, alignment: .center)
                Text(item.title)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background(active ? Butter.coral.opacity(0.52) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.white : Color.white.opacity(0.85))
    }

    // MARK: Account chip

    private var accountChip: some View {
        Button { accountPopoverShowing.toggle() } label: {
            HStack(spacing: 10) {
                avatarCircle(username, size: 28, font: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(username)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 8) {
                        tierPill
                        creditsLine(compact: true)
                    }
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $accountPopoverShowing, arrowEdge: .top) {
            accountPopoverContent
        }
    }

    private var tierPill: some View {
        HStack(spacing: 4) {
            Circle().fill(tierAccent).frame(width: 5, height: 5)
            Text(tierLabel)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var accountPopoverContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                avatarCircle(username, size: 42, font: 17)
                VStack(alignment: .leading, spacing: 3) {
                    Text(username)
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(tierAccent).frame(width: 6, height: 6)
                        Text(tierLabel + " plan")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tierAccent)
                    }
                }
            }
            Divider()
            // Credits row
            HStack(spacing: 8) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Butter.honey)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(credits.balance.formatted()) credits")
                        .font(.system(size: 13, weight: .semibold))
                    Text("available this month")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            Button(role: .destructive) {
                accountPopoverShowing = false
                onSignOut()
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(16).frame(width: 220)
    }

    // MARK: Helpers

    @ViewBuilder
    private func creditsLine(compact: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "bolt.fill")
                .font(.system(size: compact ? 8 : 10))
                .foregroundStyle(Butter.honey)
            Text(compact ? "\(credits.balance.formatted())" : "\(credits.balance.formatted()) credits")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private func avatarCircle(_ name: String, size: CGFloat, font: CGFloat) -> some View {
        Text(String((name.first ?? "?").uppercased()))
            .font(.system(size: font, weight: .bold))
            .foregroundStyle(Butter.cocoa)
            .frame(width: size, height: size)
            .background(Butter.cream, in: Circle())
    }

    private var tierLabel: String {
        switch tier { case .free: return "Free"; case .pro: return "Pro"; case .teams: return "Teams" }
    }

    private var tierAccent: Color {
        switch tier { case .free: return Color.secondary; case .pro: return Butter.coral; case .teams: return Color.indigo }
    }

    private var sidebarGradient: some ShapeStyle {
        LinearGradient(
            colors: [Color(red: 0.09, green: 0.04, blue: 0.22),
                     Color(red: 0.15, green: 0.05, blue: 0.33),
                     Color(red: 0.08, green: 0.07, blue: 0.27)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func navIcon(_ id: String) -> String {
        switch id {
        case "Dashboard":        return "house.fill"
        case "My shortcuts":     return "bolt.fill"
        case "Collections":      return "folder.fill"
        case "Marketplace":      return "storefront"
        case "KeyDo Store":      return "storefront.fill"
        case "Wall":             return "sparkles.rectangle.stack.fill"
        case "Challenge":        return "flame.fill"
        case "Settings":         return "gearshape.fill"
        case "AppBuilder":       return "wand.and.stars"
        case "WishStudio":       return "party.popper.fill"
        case "Ez Studio":        return "wrench.and.screwdriver.fill"
        case "Browser":          return "globe"
        case "Live & dynamic":   return "clock.fill"
        case "Sound & media":    return "waveform"
        case "User guide":       return "questionmark.circle"
        case "API configuration": return "key.horizontal"
        case "Shortcut ideas":   return "lightbulb.fill"
        case "AppDesigner":      return "paintpalette.fill"
        case "Ask KeyDo":        return "bubble.left.and.text.bubble.right.fill"
        default:                 return "square.grid.2x2"
        }
    }
}

/// Invisible 10 pt trigger zone on the left edge. Hover to open the sidebar.
struct SidebarEdgeTrigger: View {
    var onHover: () -> Void
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 10)
            .contentShape(Rectangle())
            .onHover { inside in if inside { onHover() } }
    }
}
