import Foundation
import UIKit

/// What's actually installed on this iPhone. iOS keeps changing which of its (unofficial) ways of asking still
/// answer, so this tries each one and uses the first that passes a self-test: it must see Mango Signer itself as
/// installed and a made-up app as not installed. If none pass, everything here returns nil and the app falls
/// back to what the server remembers (and the "Not on my phone anymore" buttons).
enum DeviceApps {
    typealias Check = (String) -> Bool?

    private static let workspace: NSObject? = {
        guard let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else { return nil }
        let sel = NSSelectorFromString("defaultWorkspace")
        guard cls.responds(to: sel) else { return nil }
        return cls.perform(sel)?.takeUnretainedValue() as? NSObject
    }()

    // 1. LSApplicationWorkspace -applicationIsInstalled:
    private static func viaWorkspace(_ id: String) -> Bool? {
        let sel = NSSelectorFromString("applicationIsInstalled:")
        guard let ws = workspace, ws.responds(to: sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, NSString) -> Bool
        return unsafeBitCast(ws.method(for: sel), to: Fn.self)(ws, sel, id as NSString)
    }

    // 2. LSApplicationProxy +applicationProxyForIdentifier: then its install state
    private static func proxy(_ id: String) -> NSObject? {
        guard let cls = NSClassFromString("LSApplicationProxy") as? NSObject.Type else { return nil }
        let sel = NSSelectorFromString("applicationProxyForIdentifier:")
        guard cls.responds(to: sel) else { return nil }
        return cls.perform(sel, with: id)?.takeUnretainedValue() as? NSObject
    }
    private static func viaProxy(_ id: String) -> Bool? {
        guard let p = proxy(id) else { return nil }
        if p.responds(to: NSSelectorFromString("appState")), let st = p.value(forKey: "appState") as? NSObject,
           st.responds(to: NSSelectorFromString("isInstalled")), let v = st.value(forKey: "isInstalled") as? Bool { return v }
        if p.responds(to: NSSelectorFromString("isInstalled")), let v = p.value(forKey: "isInstalled") as? Bool { return v }
        return nil
    }

    private static let methods: [(String, Check)] = [("workspace", viaWorkspace), ("proxy", viaProxy)]

    /// The way of asking that works on this iPhone (nil if none does).
    static let method: (name: String, check: Check)? = {
        guard let me = Bundle.main.bundleIdentifier else { return nil }
        let fake = "com.mango.not-installed.\(UUID().uuidString.prefix(8).lowercased())"
        for (name, check) in methods where check(me) == true && check(fake) == false {
            return (name, check)
        }
        return nil
    }()

    static var available: Bool { method != nil }

    /// Newer iOS lets an app see itself but answers "not installed" for every other app. Only when it can also
    /// see a built-in app is a "not installed" answer believable.
    static let seesOtherApps: Bool = {
        guard let m = method else { return false }
        return ["com.apple.mobilesafari", "com.apple.Preferences", "com.apple.camera", "com.apple.mobileslideshow"].contains { m.check($0) == true }
    }()

    /// true = installed (always believable), false = not installed (only when iOS really answers about other
    /// apps), nil = can't tell (then the app goes by what the server recorded when you installed through Mango).
    static func isInstalled(_ bundleId: String?) -> Bool? {
        guard let m = method, let id = bundleId, !id.isEmpty else { return nil }
        if m.check(id) == true || userApps.contains(where: { $0.id == id }) { return true }
        return seesOtherApps ? false : nil
    }

    static var statusText: String {
        guard let m = method else { return "iOS won't say" }
        return seesOtherApps ? "Checked on this iPhone (\(m.name))" : "iOS only shows Mango itself"
    }

    struct Seen: Identifiable, Hashable {
        var id: String          // bundle ID
        var name: String
        var version: String
        var user: Bool          // installed by you (not one of Apple's)
    }

    /// Every app iOS lists for Mango (when it lists them at all). Newer iOS may hide the apps you installed.
    static func everything() -> [Seen] {
        let sels = ["allInstalledApplications", "allApplications"]
        guard let ws = workspace else { return [] }
        for name in sels {
            let sel = NSSelectorFromString(name)
            guard ws.responds(to: sel), let list = ws.perform(sel)?.takeUnretainedValue() as? [NSObject], !list.isEmpty else { continue }
            return list.compactMap { p in
                func str(_ k: String) -> String? { p.responds(to: NSSelectorFromString(k)) ? p.value(forKey: k) as? String : nil }
                guard let id = str("bundleIdentifier") ?? str("applicationIdentifier") else { return nil }
                let type = str("applicationType") ?? ""
                return Seen(id: id, name: str("localizedName") ?? str("itemName") ?? id, version: str("shortVersionString") ?? str("bundleVersion") ?? "",
                            user: type == "User" || (!id.hasPrefix("com.apple.") && type != "System"))
            }
        }
        return []
    }

    /// Your own apps iOS lists, refreshed whenever the app checks (cheap enough to redo each time).
    static var userApps: [Seen] = []
    static func rescan() { userApps = everything().filter { $0.user && !isSelf($0.id) } }

    /// Is an app with this name on the phone (for apps installed under a different app ID)?
    static func installedByName(_ name: String?) -> Seen? {
        guard let n = name?.trimmingCharacters(in: .whitespaces).lowercased(), !n.isEmpty else { return nil }
        return userApps.first { $0.name.lowercased() == n }
    }

    /// The installed copy's version ("1.2.3"), if iOS says.
    static func version(_ bundleId: String?) -> String? {
        guard let id = bundleId, isInstalled(id) == true, let p = proxy(id) else { return nil }
        for key in ["shortVersionString", "bundleVersion"] {
            if p.responds(to: NSSelectorFromString(key)), let v = p.value(forKey: key) as? String, !v.isEmpty { return v }
        }
        return nil
    }

    /// True for Mango Signer itself (no point offering to open the app you're in).
    static func isSelf(_ bundleId: String?) -> Bool { bundleId != nil && bundleId == Bundle.main.bundleIdentifier }

    private static func openDirect(_ bundleId: String) -> Bool {
        let sel = NSSelectorFromString("openApplicationWithBundleID:")
        guard let ws = workspace, ws.responds(to: sel) else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector, NSString) -> Bool
        return unsafeBitCast(ws.method(for: sel), to: Fn.self)(ws, sel, bundleId as NSString)
    }

    /// The link schemes an app answers to ("whatsapp", "fb123…"), read from its saved .ipa or from iOS.
    static func schemes(_ bundleId: String, ipa: URL?) -> [String] {
        var out: [String] = []
        if let p = proxy(bundleId), p.responds(to: NSSelectorFromString("claimedURLSchemes")),
           let list = p.value(forKey: "claimedURLSchemes") as? [String] { out += list }
        if let ipa, let names = try? IPAReader.names(in: ipa),
           let path = names.first(where: { $0.hasPrefix("Payload/") && $0.hasSuffix(".app/Info.plist") && $0.split(separator: "/").count == 3 }),
           let data = try? IPAReader.entry(path, in: ipa),
           let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let types = info["CFBundleURLTypes"] as? [[String: Any]] {
            for t in types { out += (t["CFBundleURLSchemes"] as? [String]) ?? [] }
        }
        var seen = Set<String>()
        return out.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Opens an installed app: directly if iOS allows it, otherwise through one of its own links.
    @MainActor
    static func open(_ bundleId: String, ipa: URL? = nil) async -> Bool {
        if isSelf(bundleId) { return true }
        if openDirect(bundleId) { return true }
        for scheme in schemes(bundleId, ipa: ipa) {
            guard let u = URL(string: "\(scheme)://") else { continue }
            if await UIApplication.shared.open(u) { return true }
        }
        return false
    }
}

/// Compares version strings by their numbers ("1.10" > "1.9").
func versionCompare(_ a: String?, _ b: String?) -> Int {
    let pa = (a ?? "").split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    let pb = (b ?? "").split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    for i in 0..<max(pa.count, pb.count) {
        let d = (i < pa.count ? pa[i] : 0) - (i < pb.count ? pb[i] : 0)
        if d != 0 { return d }
    }
    return 0
}
