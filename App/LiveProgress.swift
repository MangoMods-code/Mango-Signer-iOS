import Foundation
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Shows signing or uploading progress on the Lock Screen and in the Dynamic Island.
@MainActor
final class LiveProgress {
    private var activity: Any?
    private var lastSent = Date.distantPast
    private var lastState: (String, String, Double?)?

    func start(app: String, title: String) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *), ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = MangoActivityAttributes.ContentState(title: title, detail: app, progress: nil)
        activity = try? Activity.request(attributes: MangoActivityAttributes(appName: app), contentState: state, pushType: nil)
        #endif
    }

    /// Sends at most one update a second (iOS limits how often the Lock Screen can change).
    func update(title: String, detail: String, progress: Double?) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *), let a = activity as? Activity<MangoActivityAttributes> else { return }
        if let l = lastState, l.0 == title, l.1 == detail, l.2 == progress { return }
        let titleChanged = lastState?.0 != title
        guard titleChanged || Date().timeIntervalSince(lastSent) > 1 else { return }
        lastSent = Date(); lastState = (title, detail, progress)
        let s = MangoActivityAttributes.ContentState(title: title, detail: detail, progress: progress)
        Task { await a.update(using: s) }
        #endif
    }

    func end(title: String, detail: String, failed: Bool = false) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *), let a = activity as? Activity<MangoActivityAttributes> else { return }
        let s = MangoActivityAttributes.ContentState(title: title, detail: detail, progress: nil, done: !failed, failed: failed)
        Task { await a.end(using: s, dismissalPolicy: .after(Date().addingTimeInterval(failed ? 60 : 20))) }
        activity = nil
        #endif
    }
}

/// Keeps the Home Screen widget up to date.
enum WidgetSync {
    @MainActor
    static func save(server: Server) {
        guard let st = server.state else { return }
        let cert = server.defaultCert
        let last = (st.signed ?? []).max { (parseDate($0.signedAt) ?? .distantPast) < (parseDate($1.signedAt) ?? .distantPast) }
        let snap = WidgetSnapshot(certName: cert?.label, certExpires: cert?.expires, lastSigned: last?.name, lastSignedAt: parseDate(last?.signedAt),
                                  updates: st.apps.filter { $0.hasUpdate }.count, signedCount: (st.signed ?? []).count, server: server.baseURL?.host)
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
