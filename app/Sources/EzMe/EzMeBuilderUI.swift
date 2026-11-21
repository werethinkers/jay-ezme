// One look for the builders (Prompt Builder, Collection Builder): warm cream cards, a coral accent,
// numbered steps, one header style and tidy chips. Layout only; no behaviour lives here.
import SwiftUI

struct BuilderHeader<Trailing: View>: View {
    var symbol: String
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(LinearGradient(colors: [Butter.coral, Butter.coral.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Butter.coral.opacity(0.28), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 21, weight: .heavy, design: .rounded)).foregroundStyle(Butter.cocoa)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            trailing()
        }
    }
}

/// A numbered card. The number sits in a coral badge so the page reads top to bottom as steps.
struct BuilderCard<Content: View, Accessory: View>: View {
    var step: Int?
    var title: String
    var symbol: String
    var hint: String = ""
    var collapsible: Bool = false
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content
    @State private var open = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let step {
                    Text("\(step)").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .frame(width: 26, height: 26).background(Butter.coral, in: Circle())
                } else {
                    Image(systemName: symbol).foregroundStyle(Butter.coral).frame(width: 26, height: 26)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Butter.cocoa)
                    if !hint.isEmpty { Text(hint).font(.system(size: 11.5)).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 8)
                if open || !collapsible { accessory() }
                if collapsible {
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Butter.cocoa.opacity(0.6))
                        .rotationEffect(.degrees(open ? 0 : -90))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if collapsible { withAnimation(.easeInOut(duration: 0.18)) { open.toggle() } } }
            if open || !collapsible { content() }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Butter.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Butter.coral.opacity(0.16), lineWidth: 1))
        .shadow(color: Butter.cocoa.opacity(0.05), radius: 10, y: 4)
    }
}

extension BuilderCard where Accessory == EmptyView {
    init(step: Int? = nil, title: String, symbol: String, hint: String = "", collapsible: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.init(step: step, title: title, symbol: symbol, hint: hint, collapsible: collapsible, accessory: { EmptyView() }, content: content)
    }
}

struct BuilderStepPill: View {
    var number: Int
    var title: String
    var done = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: done ? "checkmark" : "\(number).circle.fill")
                .font(.system(size: done ? 10 : 15, weight: .bold))
                .foregroundStyle(done ? .white : Butter.coral)
                .frame(width: 20, height: 20)
                .background(done ? Butter.coral : Color.clear, in: Circle())
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Butter.cocoa)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(.white.opacity(0.8), in: Capsule())
        .overlay(Capsule().stroke(Butter.coral.opacity(0.16)))
    }
}

struct BuilderStatusPill: View {
    var text: String
    var symbol: String
    var tint: Color = Butter.coral

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Small rounded insert button such as "# Collections".
struct BuilderChipLabel: View {
    var text: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Butter.cocoa)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.white.opacity(0.85), in: Capsule())
        .overlay(Capsule().stroke(Butter.coral.opacity(0.22)))
    }
}

/// A site to send a prompt to: coloured initial, name, and a clear sending state.
struct BuilderSiteTile: View {
    var name: String
    var sending: Bool
    var enabled: Bool
    var action: () -> Void
    @State private var hovering = false

    private var tint: Color {
        let palette: [Color] = [Butter.coral, Butter.dustyBlue, Color(red: 0.42, green: 0.62, blue: 0.45), Color(red: 0.62, green: 0.45, blue: 0.70), Color(red: 0.86, green: 0.62, blue: 0.22), Color(red: 0.30, green: 0.55, blue: 0.62)]
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(sending ? Color.green : tint, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Butter.cocoa).lineLimit(1)
                    Text(sending ? "Sending…" : "Send prompt").font(.system(size: 11)).foregroundStyle(sending ? .green : .secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: sending ? "checkmark.circle.fill" : "arrow.up.right").font(.system(size: 12, weight: .bold)).foregroundStyle(sending ? .green : tint)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(.white.opacity(hovering && enabled ? 1 : 0.82), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(hovering && enabled ? tint.opacity(0.7) : Butter.coral.opacity(0.14), lineWidth: hovering && enabled ? 1.5 : 1))
            .scaleEffect(hovering && enabled ? 1.015 : 1)
            .opacity(enabled ? 1 : 0.5)
            .animation(.easeOut(duration: 0.14), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The Desktop File Renamer inside Collection Builder, so files can be tidied before a collection is built from them.
struct CollectionFileRenamerBox: View {
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            FileRenamerView().padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Give a batch of files clear names first").font(.system(size: 13, weight: .semibold))
                Text("The same File Renamer as in the Files area and MyDatabase: pick files, choose a rule, preview, rename.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
    }
}
