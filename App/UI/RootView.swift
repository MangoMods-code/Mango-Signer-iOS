import SwiftUI
import UIKit

@main
struct MangoSignerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var server = Server()
    @StateObject private var local = LocalStore()
    @StateObject private var router = Router()

    init() { Theme.applyAppearance(); CopyPicker.clearOldCopies() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(server)
                .environmentObject(local)
                .environmentObject(router)
                .tint(Theme.mango)
                .preferredColorScheme(.dark)
                .lockOverlay()
        }
    }
}

struct RootView: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var router: Router
    @Environment(\.scenePhase) private var phase

    /// Changes whenever the signed-in account or its certificates change.
    var certSyncKey: String {
        guard server.authed, let st = server.state else { return "signed-out" }
        let certs: [String] = (st.certs ?? []).map { c in c.id + "|" + c.label }
        return st.account.id + ":" + certs.joined(separator: ",")
    }

    var body: some View {
        // A ZStack (not a Group) so the tasks below belong to this screen as a whole. On a Group they'd run
        // again every time it switches between loading and sign-in, and the session check would loop forever.
        ZStack {
            if server.checking && server.state == nil && server.baseURL != nil {
                VStack(spacing: 16) {
                    Image("Logo").resizable().frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    ProgressView().tint(Theme.mango)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg.ignoresSafeArea())
            } else if !server.authed || server.state == nil {
                LoginScreen()
            } else {
                MainShell()
            }
        }
        .task { await server.checkSession() }
        // Keeps this iPhone's copies of your account's certificates in step (added, renamed, deleted, or another account).
        .task(id: certSyncKey) {
            guard server.state != nil || !server.authed else { return }
            await local.syncAccountCerts(server: server)
        }
        .onChange(of: phase) { p in
            if p == .background { AppLock.shared.wentAway() }
            if p == .active {
                AppLock.shared.cameBack()
                // A link shared from Safari while Mango Signer couldn't be opened.
                if let l = SharedLink.take(), server.authed, router.route != .importLink {
                    router.pendingLink = l
                    router.tab = .apps
                    router.open(.importLink)
                }
            }
            if p == .active && server.authed {
                Task {
                    await server.refresh()
                    await server.syncWithDevice()
                    await local.saveMissingCopies(server: server)
                }
            }
        }
        // "Open in Mango Signer": .ipa files go to the Apps tab, ready to sign.
        // mangosigner://import?url=… (from the share sheet or Shortcuts) downloads a link the same way.
        .onOpenURL { url in
            if url.scheme == "mangosigner" {
                let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "url" }?.value
                if url.host == "import", let link, !link.isEmpty, router.route != .importLink {
                    _ = SharedLink.take()
                    router.pendingLink = link
                    router.tab = .apps
                    router.open(.importLink)
                }
                return
            }
            guard url.pathExtension.lowercased() == "ipa" else { return }
            Task {
                do {
                    let a = try await local.importIPA(url)
                    router.tab = .apps
                    router.open(.signLocal(a.id))
                } catch { router.say(error.localizedDescription) }
            }
        }
    }
}

/// The tab bar and the one sheet at a time, like the website.
struct MainShell: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var router: Router

    var owner: Bool { server.isStaff }
    /// Changes when what the Home Screen widget shows changes.
    var widgetKey: String {
        let signed = server.state?.signed ?? []
        return "\(server.defaultCert?.id ?? "")|\(server.defaultCert?.daysLeft ?? 0)|\(signed.count)|\(signed.first?.id ?? "")|\(updates)"
    }
    /// Changes when certificates are added, removed or renewed, so reminders are set up again.
    var reminderKey: String {
        let ids: [String] = server.certs.map { c in c.id + String(c.daysLeft ?? 0) }
        return ids.joined(separator: ",") + "|" + String(local.ownCerts.count)
    }
    var updates: Int { (server.state?.apps ?? []).filter { $0.hasUpdate }.count }
    var certWarn: Bool { server.certs.contains { $0.check?.status == "revoked" || ($0.daysLeft ?? 99) < 7 } }
    var pending: Int { (server.state?.requests ?? []).filter { $0.status == "pending" }.count + (server.state?.bugs ?? []).filter { $0.status == "open" }.count }

    var body: some View {
        TabView(selection: $router.tab) {
            TabPage(title: "Your Apps", plus: { router.importTick += 1 }) { AppsTab() }
                .tabItem { Label("Apps", systemImage: "square.and.arrow.down.fill") }
                .tag(AppTab.apps)
            TabPage(title: owner ? "Library" : "App Library", plus: owner ? { router.open(.addApp) } : nil) { LibraryTab() }
                .tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }
                .badge(updates)
                .tag(AppTab.library)
            TabPage(title: "Signed") { SignedTab() }
                .tabItem { Label("Signed", systemImage: "arrow.down.circle.fill") }
                .tag(AppTab.signed)
            if !owner {
                TabPage(title: "Certificates", plus: { router.open(.addCert) }) { CertsTab() }
                    .tabItem { Label("Certificates", systemImage: "checkmark.shield.fill") }
                    .badge(certWarn ? Text("!") : nil)
                    .tag(AppTab.certs)
            }
            if owner {
                TabPage(title: "Users", plus: { router.open(.newInvite) }) { UsersTab() }
                    .tabItem { Label("Users", systemImage: "person.2.fill") }
                    .badge(pending)
                    .tag(AppTab.users)
            }
            TabPage(title: server.isOwner ? "Settings" : "Account") { SettingsTab() }
                .tabItem { Label(server.isOwner ? "Settings" : "Account", systemImage: server.isOwner ? "gearshape.fill" : "person.crop.circle.fill") }
                .badge(owner && certWarn ? Text("!") : nil)
                .tag(AppTab.settings)
        }
        .toast($router.toast)
        .onAppear { router.certsInSettings = owner }
        .onChange(of: owner) { v in router.certsInSettings = v; if v && router.tab == .certs { router.tab = .settings } }
        .task(id: reminderKey) {
            CertReminders.schedule(server: server, local: local)
        }
        .task(id: widgetKey) { WidgetSync.save(server: server) }
        .task {
            await server.syncWithDevice(force: true)
            await local.saveMissingCopies(server: server)
        }
        .sheet(isPresented: Binding(get: { router.route != nil }, set: { if !$0 { router.close() } })) {
            SheetHost()
                .environmentObject(server)
                .environmentObject(local)
                .environmentObject(router)
        }
    }

    func openWebsite() {
        if let u = server.baseURL { UIApplication.shared.open(u) }
        router.say("Adding apps opens the website for now")
    }
}

/// One tab: the website's big title with 🔔 and + on the right, then the content.
struct TabPage<Content: View>: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let title: String
    var plus: (() -> Void)?
    @ViewBuilder var content: Content
    @AppStorage("dismissedAnnouncement") private var dismissed = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let e = server.loadError {
                    WarningBox(text: e, bad: true)
                }
                if let a = server.state?.announcement?.text, !a.isEmpty, a != dismissed {
                    HStack(alignment: .top, spacing: 10) {
                        Text("📣").font(.title3)
                        Text(a).font(.subheadline).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
                        Button { dismissed = a } label: { Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Theme.muted) }
                    }
                    .padding(14)
                    .background(Theme.mango.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.bottom, 12)
                }
                content
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 30)
        }
        .refreshable { await server.refresh() }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(alignment: .bottom) {
                Text(title).font(Theme.round(34, .heavy)).tracking(-0.7).foregroundStyle(Theme.text)
                Spacer()
                HStack(spacing: 10) {
                    if !(server.state?.alerts ?? []).isEmpty {
                        IconCircleButton(systemImage: "bell.fill", dot: server.unreadAlerts) { router.open(.alerts) }
                    }
                    if let plus { IconCircleButton(systemImage: "plus", action: plus) }
                }
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)
            // Frosted, fading out at the bottom, so the page's glow shows through and rows slide under it softly.
            .background(
                Rectangle().fill(.ultraThinMaterial)
                    .mask(LinearGradient(colors: [.black, .black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea()
            )
        }
        .background(ZStack(alignment: .top) { Theme.bg; Theme.glow.frame(height: 380) }.ignoresSafeArea())
    }
}

// MARK: - Picking a server and signing in

struct LoginScreen: View {
    @EnvironmentObject var server: Server
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var invite = ""
    @State private var signingUp = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image("Logo").resizable().frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.top, 50)
                Text("Mango Signer").font(.largeTitle.bold()).foregroundStyle(Theme.text)

                if server.baseURL == nil {
                    Text("Enter your Mango Signer server's address — the same one you open in Safari.")
                        .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    field("your-server.up.railway.app", text: $address, secure: false)
                        .keyboardType(.URL)
                    BigButton(title: busy ? "Checking…" : "Continue") { Task { await connect() } }
                        .disabled(busy)
                } else {
                    Text(server.baseURL?.host ?? "").font(.subheadline).foregroundStyle(Theme.muted)
                    VStack(spacing: 10) {
                        field(signingUp ? "Choose a username" : "Username (owner: leave empty)", text: $username, secure: false)
                        field(signingUp ? "Choose a password" : "Password", text: $password, secure: true)
                        if signingUp { field("Invite code", text: $invite, secure: false) }
                    }
                    BigButton(title: busy ? "One moment…" : signingUp ? "Create account" : "Sign in") { Task { await submit() } }
                        .disabled(busy)
                    Button(signingUp ? "I already have an account" : "I have an invite code") { signingUp.toggle(); error = nil }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mango)
                    Button("Use a different server") { server.setServer(nil); error = nil }
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                if let msg = error ?? (server.authed ? server.loadError : server.autoLoginError) {
                    Text(msg).font(.subheadline).foregroundStyle(Theme.red).multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    if server.authed {
                        BigButton(title: "Try again", primary: false) { Task { await server.refresh() } }
                    }
                }
            }
            .padding(24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .task {
            // Signed out while using the app (the session ran out): sign straight back in if the login is saved.
            if server.baseURL != nil && server.savedLogin != nil && !server.checking && server.mayAutoLogin { await server.checkSession() }
        }
    }

    @ViewBuilder
    func field(_ placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure { SecureField(placeholder, text: text) } else { TextField(placeholder, text: text) }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(Theme.text)
    }

    func connect() async {
        guard let url = Server.normalize(address) else { error = "That doesn't look like an address."; return }
        busy = true
        defer { busy = false }
        server.setServer(url)
        do {
            let _: SessionInfo = try await server.get("/api/session")
            error = nil
            await server.checkSession()
        } catch {
            server.setServer(nil)
            self.error = "Couldn't find a Mango Signer server there. Check the address."
        }
    }

    func submit() async {
        busy = true
        defer { busy = false }
        do {
            if signingUp {
                try await server.signup(username: username.trimmingCharacters(in: .whitespaces), password: password, invite: invite.trimmingCharacters(in: .whitespaces))
            } else {
                try await server.login(username: username.trimmingCharacters(in: .whitespaces), password: password)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
