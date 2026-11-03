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

enum BadgeStyle { case plain, mango, good, bad, new, blue }

struct Badge: View {
    let text: String
    var style: BadgeStyle = .plain
    var body: some View {
        let (fg, bg): (Color, Color) = {
            switch style {
            case .plain: return (Theme.muted, Theme.card2)
            case .mango: return (Theme.mango, Theme.mango.opacity(0.16))
            case .good: return (Theme.leaf, Theme.leaf.opacity(0.16))
            case .bad: return (Theme.red, Theme.red.opacity(0.16))
            case .new: return (Theme.onAccent, Theme.mango)
            case .blue: return (Theme.blue, Theme.blue.opacity(0.16))
            }
        }()
        Text(text).font(.caption2.weight(.bold)).foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 3).background(bg).clipShape(Capsule())
    }
}

struct PillButton: View {
    let title: String
    var danger = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.bold))
                .foregroundStyle(danger ? Theme.red : Theme.mango)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background((danger ? Theme.red : Theme.mango).opacity(0.16))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
