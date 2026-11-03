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

    static func isInstalled(_ bundleId: String?) -> Bool? {
        guard let m = method, let id = bundleId, !id.isEmpty else { return nil }
        return m.check(id)
    }

    /// The installed copy's version ("1.2.3"), if iOS says.
    static func version(_ bundleId: String?) -> String? {
        guard let id = bundleId, isInstalled(id) == true, let p = proxy(id) else { return nil }
        for key in ["shortVersionString", "bundleVersion"] {
            if p.responds(to: NSSelectorFromString(key)), let v = p.value(forKey: key) as? String, !v.isEmpty { return v }
        }
        return nil
    }

    /// Opens an installed app.
    @discardableResult
    static func open(_ bundleId: String) -> Bool {
        let sel = NSSelectorFromString("openApplicationWithBundleID:")
        guard let ws = workspace, ws.responds(to: sel) else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector, NSString) -> Bool
        return unsafeBitCast(ws.method(for: sel), to: Fn.self)(ws, sel, bundleId as NSString)
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
