import SwiftUI
import LocalAuthentication
import UserNotifications

// MARK: - Import from a link (Apps tab)

/// Downloads an .ipa from a link straight onto this iPhone (into the Apps tab), ready to sign.
struct ImportLinkSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var router: Router
    @State private var link = ""
    @State private var progress: Double?
    @State private var status: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        SheetScroll {
            SheetTitle(text: "Import from a link")
            Hint(text: "Paste a direct link to an .ipa. It downloads to this iPhone and shows up in your Apps tab, ready to sign. You can also share a link to Mango Signer from Safari.").padding(.bottom, 12)
            Field(label: "Link") {
                HStack {
                    TextField("https://…/app.ipa", text: $link).plainInput().keyboardType(.URL)
                    Button { link = UIPasteboard.general.string ?? link } label: { Image(systemName: "doc.on.clipboard") }.foregroundStyle(Theme.mango)
                }
                .inputStyle()
            }
            if let status {
                VStack(spacing: 8) {
                    if let progress { ProgressView(value: progress).tint(Theme.mango) } else { ProgressView().tint(Theme.mango) }
                    Text(status).font(.footnote).foregroundStyle(Theme.muted)
                    LinkButton(title: "Cancel") { task?.cancel(); task = nil; self.status = nil }
                }
                .padding(.vertical, 10)
            } else {
                WebButton(title: "Download", kind: .primary, big: true, disabled: link.trimmingCharacters(in: .whitespaces).isEmpty) { start() }
            }
        }
        .onAppear {
            if let l = router.pendingLink { router.pendingLink = nil; link = l; start() }
            else if link.isEmpty, let clip = UIPasteboard.general.string, clip.lowercased().hasPrefix("http"), clip.lowercased().contains(".ipa") { link = clip }
        }
        .onDisappear { task?.cancel() }
        .interactiveDismissDisabled(status != nil)
    }

    func start() {
        var s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let u = URL(string: s), u.scheme == "https" || u.scheme == "http" else { router.say("That doesn't look like a link"); return }
        status = "Downloading…"; progress = 0
        task = Task {
            do {
                let tmp = try await server.downloadFile(u) { p in progress = p; status = "Downloading \(Int(p * 100))%" }
                defer { try? FileManager.default.removeItem(at: tmp) }
                try Task.checkCancellation()
                status = "Reading app info…"; progress = nil
                // Give it a proper name so it shows up nicely.
                let name = u.lastPathComponent.lowercased().hasSuffix(".ipa") ? u.lastPathComponent : "download.ipa"
                let named = Paths.work.appendingPathComponent(String(UUID().uuidString.prefix(6)) + "-" + name)
                try FileManager.default.moveItem(at: tmp, to: named)
                defer { try? FileManager.default.removeItem(at: named) }
                let a = try await local.importIPA(named)
                status = nil
                Haptics.success()
                router.tab = .apps
                router.open(.signLocal(a.id))
            } catch is CancellationError {
                status = nil
            } catch {
                status = nil
                router.say((error as? URLError)?.code == .cancelled ? "Cancelled" : "Couldn't import it: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Re-sign all

/// Signs every app you've signed before again with one certificate (for when yours is expiring or you got a new one).
struct ResignAllSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    enum Phase: Equatable { case waiting, signing, done(String), failed(String) }
    @State private var certId = ""
    @State private var chosen: Set<String> = []
    @State private var phases: [String: Phase] = [:]
    @State private var running = false
    @State private var loaded = false

    /// One row per app: your newest signed copy of each app that's still in the library or your Apps tab.
    var items: [(signed: SSigned, app: SApp)] {
        var seen = Set<String>()
        var out: [(signed: SSigned, app: SApp)] = []
        for s in server.state?.signed ?? [] {
            guard let aid = s.appId, !seen.contains(aid), let a = server.app(aid) else { continue }
            seen.insert(aid)
            out.append((signed: s, app: a))
        }
        return out.sorted { (parseDate($0.signed.expires) ?? .distantFuture) < (parseDate($1.signed.expires) ?? .distantFuture) }
    }

    var body: some View {
        let list = items
        let certs = server.certs
        SheetScroll {
            SheetTitle(text: "Re-sign all")
            Hint(text: "Signs your apps again with the certificate you pick, keeping each app's bundle ID so it installs over the one on your iPhone. Your apps' default settings and tweaks are used.").padding(.bottom, 12)
            if certs.isEmpty {
                WebEmpty(icon: "checkmark.shield", title: "No certificates", text: "Add a certificate first.", button: "Add Certificate") { router.open(.addCert) }
            } else if list.isEmpty {
                WebEmpty(icon: "arrow.triangle.2.circlepath", title: "Nothing to re-sign", text: "Apps you sign show up here.")
            } else {
                Field(label: "Certificate") {
                    SelectBox(selection: $certId, options: certs.map { c in (c.id, "\(c.label)\(c.daysLeft.map { $0 < 0 ? " · expired" : " · \($0)d left" } ?? "")") })
                }
                .disabled(running)
                ListBox(fill: Theme.bg2) {
                    ForEach(Array(list.enumerated()), id: \.element.signed.id) { i, it in
                        if i > 0 { RowLine() }
                        row(it.signed, it.app)
                    }
                }
                let n = list.filter { chosen.contains($0.app.id) }.count
                if let limit = server.state?.settings?.signsPerDay, limit > 0 {
                    let left = max(0, limit - (server.state?.settings?.signsToday ?? 0))
                    Hint(text: "You have \(left) sign\(left == 1 ? "" : "s") left today.\(n > left ? " Only the first \(left) will be signed." : "")").padding(.top, 8)
                }
                if running || phases.values.contains(where: { if case .done = $0 { return true } else { return false } }) {
                    Hint(text: "Signing runs on the server, so it keeps going if you close this. Tap Install on each app when it's ready.").padding(.top, 8)
                }
                WebButton(title: running ? "Re-signing…" : "Re-sign \(n) app\(n == 1 ? "" : "s")", kind: .primary, big: true, disabled: running || n == 0 || certId.isEmpty) { go(list) }
                    .padding(.top, 12)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            certId = server.defaultCert?.id ?? certs.first?.id ?? ""
            chosen = Set(list.map { $0.app.id })
        }
    }

    func row(_ s: SSigned, _ a: SApp) -> some View {
        let left = parseDate(s.expires).map { Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0 }
        return HStack(spacing: 10) {
            Image(systemName: chosen.contains(a.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(chosen.contains(a.id) ? Theme.mango : Theme.muted)
                .onTapGesture { if !running { if chosen.contains(a.id) { chosen.remove(a.id) } else { chosen.insert(a.id) } } }
            AppIconImage(app: a, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Group {
                    switch phases[a.id] {
                    case .signing: Text("Signing…").foregroundStyle(Theme.mango)
                    case .waiting: Text("Waiting…").foregroundStyle(Theme.muted)
                    case .failed(let e): Text("✕ \(e)").foregroundStyle(Theme.red).lineLimit(2)
                    case .done: Text("✓ Ready to install").foregroundStyle(Theme.leaf)
                    case nil: Text("\(s.certLabel ?? "") · \(left.map { $0 < 0 ? "expired" : "\($0)d left" } ?? "")").foregroundStyle(left.map { $0 < 7 } == true ? Theme.red : Theme.muted)
                    }
                }
                .font(.caption)
            }
            Spacer()
            if case .done(let sid) = phases[a.id] {
                PillButton(title: "Install") { if let ss = router.signed(sid, server) { router.startInstall(ss, server: server) } }
            } else if phases[a.id] == .signing {
                ProgressView().tint(Theme.mango)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    func go(_ list: [(signed: SSigned, app: SApp)]) {
        running = true
        let todo = list.filter { chosen.contains($0.app.id) }
        for it in todo { phases[it.app.id] = .waiting }
        Task {
            defer { running = false }
            for it in todo {
                phases[it.app.id] = .signing
                var body = server.signBodyFromDefaults(it.app, versionIndex: it.signed.options?.versionIndex ?? 0)
                body["certId"] = certId
                if let b = it.signed.bundleId, !b.isEmpty { body["bundleId"] = b } // installs over the copy on your iPhone
                do {
                    let r = try await server.post("/api/sign", body)
                    guard let job = r["jobId"] as? String else { throw MangoError("The server didn't start signing.") }
                    let res = try await server.waitJob(job) { _, _ in }
                    var sid = (res["signed"] as? [String: Any])?["id"] as? String
                    if sid == nil { sid = (try? await server.get("/api/jobs/\(job)", as: JobStatus.self))?.result?.signed?.id }
                    await server.refresh()
                    phases[it.app.id] = sid.map { .done($0) } ?? .failed("Signed, but it didn't come back. Check the Signed tab.")
                } catch {
                    phases[it.app.id] = .failed(error.localizedDescription)
                    if error.localizedDescription.contains("signs for today") { for rest in todo where phases[rest.app.id] == .waiting { phases[rest.app.id] = .failed("Daily limit reached") }; break }
                }
            }
            Haptics.success()
        }
    }
}

// MARK: - Certificate reminders

enum CertReminders {
    static var on: Bool {
        get { UserDefaults.standard.bool(forKey: "certReminders") }
        set { UserDefaults.standard.set(newValue, forKey: "certReminders") }
    }

    /// Asks once for permission to show notifications.
    static func enable() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Reminders 7 days and 1 day before each certificate expires, at 10 am. Run again whenever certificates change.
    @MainActor
    static func schedule(server: Server, local: LocalStore) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            center.removePendingNotificationRequests(withIdentifiers: reqs.map { $0.identifier }.filter { $0.hasPrefix("cert-") })
        }
        guard on else { return }
        var certs: [(id: String, label: String, expires: Date)] = server.certs.compactMap { c in c.expires.map { (c.id, c.label, $0) } }
        for c in local.ownCerts { if let e = c.expires { certs.append((c.id.uuidString, c.label + " (on this iPhone)", e)) } }
        for c in certs {
            for days in [7, 1] {
                guard var when = Calendar.current.date(byAdding: .day, value: -days, to: c.expires) else { continue }
                when = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: when) ?? when
                guard when > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = days == 1 ? "🔐 \(c.label) expires tomorrow" : "🔐 \(c.label) expires in a week"
                content.body = "Apps signed with it stop opening when it expires. Get a new certificate, then use Re-sign all in the Signed tab."
                content.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
                center.add(UNNotificationRequest(identifier: "cert-\(c.id)-\(days)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
        }
    }
}

// MARK: - Face ID lock

final class AppLock: ObservableObject {
    static let shared = AppLock()
    @Published var locked = false
    private var leftAt: Date?
    private var unlocking = false

    static var on: Bool {
        get { UserDefaults.standard.bool(forKey: "faceIDLock") }
        set { UserDefaults.standard.set(newValue, forKey: "faceIDLock") }
    }

    /// What this iPhone uses: "Face ID", "Touch ID" or "passcode".
    static var methodName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "your passcode"
        }
    }

    init() { locked = AppLock.on }

    func wentAway() { if AppLock.on { leftAt = Date() } }
    /// Locks again after 30 seconds away (a quick trip to Settings or the share sheet doesn't count).
    func cameBack() {
        guard AppLock.on, let t = leftAt else { return }
        leftAt = nil
        if Date().timeIntervalSince(t) > 30 { locked = true }
        if locked { unlock() }
    }

    func unlock() {
        guard locked, !unlocking else { return }
        unlocking = true
        let ctx = LAContext()
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Mango Signer") { ok, _ in
            Task { @MainActor in
                self.unlocking = false
                if ok { self.locked = false }
            }
        }
    }

    /// Checks it works before turning it on.
    func turnOn() async -> Bool {
        await withCheckedContinuation { cont in
            LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Turn on the lock for Mango Signer") { ok, _ in cont.resume(returning: ok) }
        }
    }
}

struct LockOverlay: ViewModifier {
    @ObservedObject var lock = AppLock.shared
    func body(content: Content) -> some View {
        content.overlay {
            if lock.locked {
                VStack(spacing: 18) {
                    Image("Logo").resizable().frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    Text("Mango Signer is locked").font(.title3.bold()).foregroundStyle(Theme.text)
                    Button { lock.unlock() } label: {
                        Label("Unlock with \(AppLock.methodName)", systemImage: "lock.open.fill").font(.headline).foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 22).padding(.vertical, 13).background(Theme.gradient).clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg.ignoresSafeArea())
                .onAppear { lock.unlock() }
            }
        }
    }
}

extension View {
    func lockOverlay() -> some View { modifier(LockOverlay()) }
}

// MARK: - App icon

struct AppIconChoice: Identifiable {
    let id: String     // alternate icon name (nil-able: "" = the main icon)
    let title: String
    static let all: [AppIconChoice] = [
        .init(id: "", title: "Classic"),
        .init(id: "AppIcon-Midnight", title: "Midnight"),
        .init(id: "AppIcon-Sunset", title: "Sunset"),
        .init(id: "AppIcon-Leaf", title: "Leaf"),
        .init(id: "AppIcon-Cream", title: "Cream"),
        .init(id: "AppIcon-Ocean", title: "Ocean"),
    ]
}

struct AppIconPicker: View {
    @EnvironmentObject var router: Router
    @State private var current = UIApplication.shared.alternateIconName ?? ""
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
            ForEach(AppIconChoice.all) { c in
                Button { pick(c) } label: {
                    VStack(spacing: 6) {
                        Image(c.id.isEmpty ? "IconPreview-Classic" : c.id.replacingOccurrences(of: "AppIcon-", with: "IconPreview-"))
                            .resizable().frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(current == c.id ? Theme.mango : Color.clear, lineWidth: 3))
                        Text(c.title).font(.caption.weight(current == c.id ? .bold : .regular)).foregroundStyle(current == c.id ? Theme.mango : Theme.muted)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    func pick(_ c: AppIconChoice) {
        guard UIApplication.shared.supportsAlternateIcons else { router.say("This iPhone can't change app icons"); return }
        UIApplication.shared.setAlternateIconName(c.id.isEmpty ? nil : c.id) { err in
            Task { @MainActor in
                if let err { router.say("Couldn't change the icon: \(err.localizedDescription)") } else { current = c.id; Haptics.tap() }
            }
        }
    }
}
