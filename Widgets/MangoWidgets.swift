import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

private let mango = Color(red: 1, green: 0.62, blue: 0.1)
private let bg = Color(red: 0.08, green: 0.05, blue: 0.1)

struct MangoEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
}

struct MangoProvider: TimelineProvider {
    func placeholder(in context: Context) -> MangoEntry {
        MangoEntry(date: Date(), snap: WidgetSnapshot(certName: "My Certificate", certExpires: Date().addingTimeInterval(86400 * 120), lastSigned: "YouTube", lastSignedAt: Date(), updates: 2, signedCount: 8))
    }
    func getSnapshot(in context: Context, completion: @escaping (MangoEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : MangoEntry(date: Date(), snap: WidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MangoEntry>) -> Void) {
        // Days left change once a day; the app also refreshes the widget whenever something changes.
        let entry = MangoEntry(date: Date(), snap: WidgetSnapshot.load())
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date().addingTimeInterval(21600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

func daysLeft(_ d: Date?) -> Int? { d.map { Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0 } }

struct MangoWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: MangoEntry

    var body: some View {
        content
            .widgetURL(URL(string: "mangosigner://open"))
            .modifier(WidgetBackground())
    }

    @ViewBuilder var content: some View {
        if let s = entry.snap {
            let left = daysLeft(s.certExpires)
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Text(left.map { "\($0)" } ?? "–").font(.system(size: 20, weight: .bold))
                        Text("days").font(.system(size: 9))
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("🥭 Mango Signer").font(.headline)
                    Text(left.map { $0 < 0 ? "Certificate expired" : "Certificate: \($0) days left" } ?? "No certificate")
                    if s.updates > 0 { Text("\(s.updates) update\(s.updates == 1 ? "" : "s") waiting") }
                }
            case .systemSmall:
                VStack(alignment: .leading, spacing: 4) {
                    Text("🥭").font(.title2)
                    Spacer(minLength: 0)
                    Text(left.map { "\(max(0, $0))" } ?? "–").font(.system(size: 34, weight: .bold)).foregroundStyle(left.map { $0 < 7 } == true ? .red : mango)
                    Text(left.map { $0 < 0 ? "certificate expired" : "days left on your certificate" } ?? "add a certificate").font(.caption2).foregroundStyle(.secondary)
                    if s.updates > 0 { Text("⬆️ \(s.updates) update\(s.updates == 1 ? "" : "s")").font(.caption2.bold()).foregroundStyle(mango) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            default:
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🥭 Mango Signer").font(.headline).foregroundStyle(.white)
                        Text(s.certName ?? "No certificate").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(left.map { "\(max(0, $0))" } ?? "–").font(.system(size: 34, weight: .bold)).foregroundStyle(left.map { $0 < 7 } == true ? .red : mango)
                        Text(left.map { $0 < 0 ? "certificate expired" : "days left" } ?? "add a certificate").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 8) {
                        stat("Last signed", s.lastSigned ?? "Nothing yet")
                        stat("Updates waiting", "\(s.updates)")
                        stat("Signed apps", "\(s.signedCount)")
                    }
                }
            }
        } else {
            VStack(spacing: 6) {
                Text("🥭").font(.title)
                Text("Open Mango Signer once to set up this widget").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
        }
    }

    func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.caption.bold()).foregroundStyle(.white).lineLimit(1)
        }
    }
}

struct WidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { bg }
        } else {
            content.padding().background(bg)
        }
    }
}

struct MangoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MangoWidget", provider: MangoProvider()) { MangoWidgetView(entry: $0) }
            .configurationDisplayName("Mango Signer")
            .description("Days left on your certificate, your last signed app and updates waiting.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

#if canImport(ActivityKit)
struct MangoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MangoActivityAttributes.self) { ctx in
            HStack(spacing: 12) {
                Text(ctx.state.done ? "✅" : ctx.state.failed ? "⚠️" : "🥭").font(.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ctx.state.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text(ctx.state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let p = ctx.state.progress, !ctx.state.done { ProgressView(value: p).tint(mango) }
                }
            }
            .padding(16)
            .activityBackgroundTint(bg)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("🥭").font(.title2) }
                DynamicIslandExpandedRegion(.trailing) {
                    if let p = ctx.state.progress, !ctx.state.done { Text("\(Int(p * 100))%").font(.headline).foregroundStyle(mango) }
                    else if ctx.state.done { Text("✅") }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ctx.state.title).font(.headline).lineLimit(1)
                        Text(ctx.state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if let p = ctx.state.progress, !ctx.state.done { ProgressView(value: p).tint(mango) }
                    }
                }
            } compactLeading: {
                Text("🥭")
            } compactTrailing: {
                if ctx.state.done { Text("✅") }
                else if let p = ctx.state.progress { Text("\(Int(p * 100))%").font(.caption2.bold()).foregroundStyle(mango) }
                else { ProgressView().tint(mango) }
            } minimal: {
                Text(ctx.state.done ? "✅" : "🥭")
            }
        }
    }
}
#endif

@main
struct MangoWidgetBundle: WidgetBundle {
    var body: some Widget {
        MangoWidget()
        MangoLiveActivity()
    }
}
