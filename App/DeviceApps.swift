import Foundation
import UIKit

/// What's actually installed on this iPhone. Uses the same system call sideloading apps (ESign, Feather…) use:
/// iOS's app workspace, looked up at run time. If iOS ever stops answering, everything here returns nil and
/// the app falls back to what the server remembers.
enum DeviceApps {
    private static let workspace: NSObject? = {
        guard let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else { return nil }
        let sel = NSSelectorFromString("defaultWorkspace")
        guard cls.responds(to: sel) else { return nil }
        return cls.perform(sel)?.takeUnretainedValue() as? NSObject
    }()

    private static func ask(_ id: String) -> Bool? {
        let sel = NSSelectorFromString("applicationIsInstalled:")
        guard let ws = workspace, ws.responds(to: sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, NSString) -> Bool
        let fn = unsafeBitCast(ws.method(for: sel), to: Fn.self)
        return fn(ws, sel, id as NSString)
    }

    /// True only if iOS really answers (it must see Mango Signer itself as installed).
    static let available: Bool = {
        guard let me = Bundle.main.bundleIdentifier else { return false }
        return ask(me) == true
    }()

    static func isInstalled(_ bundleId: String?) -> Bool? {
        guard available, let id = bundleId, !id.isEmpty else { return nil }
        return ask(id)
    }

    /// The installed copy's version ("1.2.3"), if iOS says.
    static func version(_ bundleId: String?) -> String? {
        guard available, let id = bundleId, !id.isEmpty, isInstalled(id) == true,
              let cls = NSClassFromString("LSApplicationProxy") as? NSObject.Type else { return nil }
        let sel = NSSelectorFromString("applicationProxyForIdentifier:")
        guard cls.responds(to: sel), let proxy = cls.perform(sel, with: id)?.takeUnretainedValue() as? NSObject else { return nil }
        for key in ["shortVersionString", "bundleVersion"] {
            if proxy.responds(to: NSSelectorFromString(key)), let v = proxy.value(forKey: key) as? String, !v.isEmpty { return v }
        }
        return nil
    }

    /// Opens an installed app.
    @discardableResult
    static func open(_ bundleId: String) -> Bool {
        let sel = NSSelectorFromString("openApplicationWithBundleID:")
        guard let ws = workspace, ws.responds(to: sel) else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector, NSString) -> Bool
        let fn = unsafeBitCast(ws.method(for: sel), to: Fn.self)
        return fn(ws, sel, bundleId as NSString)
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
