import Foundation
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// What the Home Screen widget shows. The app writes it; the widget reads it.
/// Signing certificates from most sellers can't share a storage folder between the app and its widget
/// ("App Groups"), so this goes through a private named pasteboard instead, which apps signed by the same
/// certificate can share without any special permission.
struct WidgetSnapshot: Codable {
    var certName: String?
    var certExpires: Date?
    var lastSigned: String?
    var lastSignedAt: Date?
    var updates: Int = 0
    var signedCount: Int = 0
    var server: String?
    var savedAt = Date()

    static let pasteboardName = UIPasteboard.Name("com.mangomods.mangosigner.shared")
    static let type = "com.mangomods.mangosigner.widget"

    static func load() -> WidgetSnapshot? {
        guard let pb = UIPasteboard(name: pasteboardName, create: false), let d = pb.data(forPasteboardType: type) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: d)
    }

    func save() {
        guard let pb = UIPasteboard(name: WidgetSnapshot.pasteboardName, create: true), let d = try? JSONEncoder().encode(self) else { return }
        var items = pb.items
        if items.isEmpty { items = [[:]] }
        items[0][WidgetSnapshot.type] = d
        pb.items = items
    }
}

/// A link shared to Mango Signer from Safari's share sheet, waiting for the app to pick it up.
enum SharedLink {
    static let type = "com.mangomods.mangosigner.link"
    static func put(_ link: String) {
        guard let pb = UIPasteboard(name: WidgetSnapshot.pasteboardName, create: true) else { return }
        var items = pb.items
        if items.isEmpty { items = [[:]] }
        items[0][type] = Data(link.utf8)
        pb.items = items
    }
    static func take() -> String? {
        guard let pb = UIPasteboard(name: WidgetSnapshot.pasteboardName, create: false) else { return nil }
        var items = pb.items
        guard !items.isEmpty, let d = items[0][type] as? Data, let s = String(data: d, encoding: .utf8) else { return nil }
        items[0].removeValue(forKey: type)
        pb.items = items
        return s
    }
}

#if canImport(ActivityKit)
/// Signing or uploading progress on the Lock Screen and in the Dynamic Island.
struct MangoActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var detail: String
        var progress: Double?
        var done: Bool = false
        var failed: Bool = false
    }
    var appName: String
}
#endif
