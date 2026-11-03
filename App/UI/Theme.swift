import SwiftUI
import UIKit

// The same colors as the Mango Signer website.
extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

enum Theme {
    static let bg = Color(hex: 0x140c1a)
    static let bg2 = Color(hex: 0x1d1326)
    static let card = Color(hex: 0x241830)
    static let card2 = Color(hex: 0x2e2139)
    static let line = Color.white.opacity(0.08)
    static let text = Color(hex: 0xf6eefc)
    static let muted = Color(hex: 0xa898b5)
    static let mango = Color(hex: 0xff9f1c)
    static let mango2 = Color(hex: 0xffcf4a)
    static let accent2 = Color(hex: 0xff7a1a)
    static let leaf = Color(hex: 0x5cc45c)
    static let red = Color(hex: 0xff5c6c)
    static let blue = Color(hex: 0x6aa8ff)
    static let onAccent = Color(hex: 0x1a0d05)
    static let gradient = LinearGradient(colors: [mango, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func applyAppearance() {
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundColor = UIColor(Color(hex: 0x180f1f, alpha: 0.92))
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundColor = UIColor(bg)
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(text)]
        nav.titleTextAttributes = [.foregroundColor: UIColor(text)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SectionTitle: View {
    let text: String
    var count: Int?
    var body: some View {
        HStack(spacing: 8) {
            Text(text.uppercased()).font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Theme.muted)
            if let count {
                Text("\(count)").font(.caption2.weight(.bold)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.card2).clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 4).padding(.top, 18).padding(.bottom, 8)
    }
}

enum BadgeStyle { case plain, mango, good, bad, new, blue, warn, cloud }

struct Badge: View {
    let text: String
    var style: BadgeStyle = .plain
    var small = false
    var body: some View {
        let (fg, bg): (Color, Color) = {
            switch style {
            case .plain: return (Theme.muted, Theme.card2)
            case .mango: return (Theme.mango, Theme.mango.opacity(0.16))
            case .good: return (Theme.leaf, Theme.leaf.opacity(0.16))
            case .bad: return (Theme.red, Theme.red.opacity(0.16))
            case .new: return (Theme.onAccent, Theme.mango)
            case .blue: return (Theme.blue, Theme.blue.opacity(0.16))
            case .warn: return (Color(hex: 0xffcf4a), Color(hex: 0xffcf4a).opacity(0.14))
            case .cloud: return (Color(hex: 0x5aa0ff), Color(hex: 0x5aa0ff).opacity(0.15))
            }
        }()
        Text(text).font(.system(size: small ? 11 : 12, weight: style == .new ? .heavy : .semibold)).foregroundStyle(fg)
            .padding(.horizontal, small ? 8 : 9).padding(.vertical, small ? 2 : 3)
            .background(style == .new ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(bg)).clipShape(Capsule())
            .lineLimit(1)
    }
}

struct PillButton: View {
    let title: String
    var danger = false
    var dim = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .bold))
                .foregroundStyle(dim ? Theme.muted : danger ? Theme.red : Theme.mango)
                .padding(.horizontal, 15).padding(.vertical, 6)
                .background(dim ? AnyShapeStyle(Theme.card2) : AnyShapeStyle((danger ? Theme.red : Theme.mango).opacity(0.16)))
                .clipShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

struct BigButton: View {
    let title: String
    var icon: String?
    var primary = true
    var danger = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(primary ? Theme.onAccent : danger ? Theme.red : Theme.text)
            .background(primary ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.card2))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct RemoteIcon: View {
    let url: URL?
    let name: String
    var size: CGFloat = 56
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.card2
                Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(Theme.mango)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).stroke(Theme.line))
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await ImageCache.shared.image(url)
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(Theme.mango)
            Text(title).font(.title3.bold()).foregroundStyle(Theme.text)
            Text(message).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

struct Toast: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message {
                Text(message).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.card2).clipShape(Capsule())
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task { try? await Task.sleep(nanoseconds: 2_400_000_000); withAnimation { self.message = nil } }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View { modifier(Toast(message: message)) }
    func mangoScreen() -> some View { background(Theme.bg.ignoresSafeArea()).scrollContentBackground(.hidden) }
}

/// Release notes often use Markdown; show them as tidy text.
func cleanNotes(_ text: String) -> String {
    var lines: [String] = []
    for raw in text.replacingOccurrences(of: "\r", with: "").split(separator: "\n", omittingEmptySubsequences: false) {
        var l = String(raw)
        l = l.replacingOccurrences(of: "^\\s*#{1,6}\\s*", with: "", options: .regularExpression)
        l = l.replacingOccurrences(of: "^\\s*[-*+]\\s+", with: "• ", options: .regularExpression)
        l = l.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
        l = l.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        l = l.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        lines.append(l)
    }
    return lines.joined(separator: "\n").replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
}

func formatBytes(_ n: Double?) -> String {
    guard let n, n > 0 else { return "" }
    return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
}

// MARK: - Pieces that copy the website's look

extension Theme {
    static let icon = Color(hex: 0x3a2a48)
    static let soft = Color(hex: 0xd9cde3)
    static let warn = Color(hex: 0xffcf4a)
    static let cloud = Color(hex: 0x5aa0ff)
}

/// A sheet's big heading.
struct SheetTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
    }
}

/// Icon + title + subtitle at the top of a sheet.
struct SheetHead<Icon: View>: View {
    let title: String
    let sub: String
    @ViewBuilder var icon: Icon
    var body: some View {
        HStack(spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.text).lineLimit(2)
                if !sub.isEmpty { Text(sub).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 10)
    }
}

/// The website's .list: rows on a rounded card with thin lines between them.
struct ListBox<Content: View>: View {
    var fill: Color = Theme.card
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct RowLine: View {
    var inset: CGFloat = 0
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, inset) }
}

/// A plain tappable row: "Title ............ value ›".
struct LinkRow: View {
    let title: String
    var value: String = ""
    var valueColor: Color = Theme.muted
    var color: Color = Theme.text
    var chevron = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(color)
                Spacer(minLength: 8)
                if !value.isEmpty { Text(value).font(.subheadline).foregroundStyle(valueColor).lineLimit(1) }
                if chevron { Text("›").foregroundStyle(Theme.muted) }
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "Label ........ value" (read only).
struct ValueRow: View {
    let title: String
    let value: String
    var sub: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.text)
                if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(Theme.muted) }
            }
            Spacer(minLength: 8)
            Text(value).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
    }
}

/// The website's switch rows: title, small explanation, switch.
struct ToggleRow: View {
    let title: String
    var sub: String = ""
    @Binding var isOn: Bool
    var warning: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15)).foregroundStyle(Theme.text)
                    if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(Theme.muted) }
                }
            }
            .tint(Theme.mango)
            if let warning, !warning.isEmpty {
                Text(warning).font(.caption).foregroundStyle(Color(hex: 0xff9aa4))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

/// A row with a picker on the right ("Delete signed files after   7 days ⌄").
struct PickerRow<T: Hashable>: View {
    let title: String
    var sub: String = ""
    @Binding var selection: T
    let options: [(T, String)]
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.text)
                if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(Theme.muted) }
            }
            Spacer(minLength: 8)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.menu).tint(Theme.mango).labelsHidden()
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
    }
}

/// Label above an input, like the website's .field.
struct Field<Content: View>: View {
    let label: String
    var hint: String = ""
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.footnote).foregroundStyle(Theme.muted).padding(.leading, 2)
            content
            if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(Theme.muted).padding(.leading, 2) }
        }
        .padding(.bottom, 12)
    }
}

struct InputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
            .foregroundStyle(Theme.text)
    }
}

extension View {
    func inputStyle() -> some View { modifier(InputStyle()) }
    func plainInput() -> some View { textInputAutocapitalization(.never).autocorrectionDisabled() }
}

/// A full-width menu that looks like the website's <select>.
struct SelectBox<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var body: some View {
        Menu {
            ForEach(options, id: \.0) { o in
                Button { selection = o.0 } label: {
                    if o.0 == selection { Label(o.1, systemImage: "checkmark") } else { Text(o.1) }
                }
            }
        } label: {
            HStack {
                Text(options.first { $0.0 == selection }?.1 ?? "").foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
            }
            .inputStyle()
        }
    }
}

/// The website's buttons: .btn, .btn.primary, .btn.danger, .btn.big.
struct WebButton: View {
    enum Kind { case normal, primary, danger }
    let title: String
    var kind: Kind = .normal
    var big = false
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(big ? .system(size: 17, weight: .semibold) : .body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, big ? 16 : 12).padding(.horizontal, 16)
                .foregroundStyle(kind == .primary ? Theme.onAccent : kind == .danger ? Theme.red : Theme.text)
                .background(kind == .primary ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.card2))
                .clipShape(RoundedRectangle(cornerRadius: big ? 15 : 13, style: .continuous))
                .shadow(color: kind == .primary ? Color(hex: 0xff8c1a, alpha: 0.22) : .clear, radius: 9, y: 6)
        }
        .buttonStyle(PressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Small text link ("More options ▾").
struct LinkButton: View {
    let title: String
    var color: Color = Theme.mango
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

/// The website's yellow/red notice boxes.
struct WarningBox: View {
    let text: String
    var bad = false
    var body: some View {
        Text(text).font(.subheadline)
            .foregroundStyle(bad ? Color(hex: 0xff9aa4) : Theme.warn)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background((bad ? Theme.red.opacity(0.12) : Theme.warn.opacity(0.1)))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.vertical, 4)
    }
}

struct Hint: View {
    let text: String
    var center = false
    var body: some View {
        Text(text).font(.caption).foregroundStyle(Theme.muted)
            .multilineTextAlignment(center ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
            .padding(.horizontal, 4)
    }
}

/// "Label    value" pairs, like the website's <dl class="kv">.
struct KVList: View {
    let items: [(String, String)]
    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, kv in
                HStack(alignment: .top, spacing: 14) {
                    Text(kv.0).foregroundStyle(Theme.muted)
                    Spacer(minLength: 8)
                    Text(kv.1).foregroundStyle(Theme.text).multilineTextAlignment(.trailing).textSelection(.enabled)
                }
                .font(.system(size: 14))
            }
        }
        .padding(.vertical, 8)
    }
}

/// Wrapping row of badges.
struct BadgeFlow: View {
    let badges: [Badge]
    var body: some View {
        FlowLayout(spacing: 6) { ForEach(Array(badges.enumerated()), id: \.offset) { $0.element } }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); maxX = max(maxX, x)
        }
        return CGSize(width: min(width, maxX), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

/// The website's round header buttons (🔔, +).
struct IconCircleButton: View {
    let systemImage: String
    var dot: Int = 0
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.mango)
                .frame(width: 38, height: 38).background(Theme.card).clipShape(Circle())
                .overlay(alignment: .topTrailing) {
                    if dot > 0 {
                        Text(dot > 9 ? "9+" : "\(dot)").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 4).frame(minWidth: 17, minHeight: 17).background(Theme.red).clipShape(Capsule())
                            .offset(x: 4, y: -3)
                    }
                }
        }
        .buttonStyle(PressStyle())
    }
}

/// Website-style app icon: 54pt (rows) or 76pt (big).
struct AppIconImage: View {
    @EnvironmentObject var server: Server
    let app: SApp
    var size: CGFloat = 54
    var body: some View {
        WebIcon(url: server.iconURL(app), name: app.name, size: size)
    }
}

struct WebIcon: View {
    let url: URL?
    let name: String
    var size: CGFloat = 54
    @State private var image: UIImage?
    var radius: CGFloat { size >= 70 ? size * 0.237 : size * 0.24 }
    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Theme.card2, Theme.icon], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(Theme.mango)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.line))
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await ImageCache.shared.image(url)
        }
    }
}

func shortDate(_ s: String?) -> String {
    guard let d = parseDate(s) else { return "—" }
    return d.formatted(date: .abbreviated, time: .omitted)
}

func shortUdid(_ s: String) -> String { s.count > 16 ? "\(s.prefix(8))…\(s.suffix(6))" : s }
