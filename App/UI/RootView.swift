import SwiftUI
import UIKit

@main
struct MangoSignerApp: App {
    @StateObject private var server = Server()
    @StateObject private var local = LocalStore()

    init() { Theme.applyAppearance() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(server)
                .environmentObject(local)
                .tint(Theme.mango)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    @State private var toast: String?

    var body: some View {
        Group {
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
                TabView(selection: $tab) {
                    LibraryScreen().tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }.tag(0)
                    SignedScreen().tabItem { Label("Signed", systemImage: "arrow.down.circle.fill") }.tag(1)
                    CertsScreen().tabItem { Label("Certificates", systemImage: "checkmark.shield.fill") }.tag(2)
                    SettingsScreen().tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(3)
                }
            }
        }
        .toast($toast)
        .task { await server.checkSession() }
        .onChange(of: phase) { p in
            if p == .active && server.authed { Task { await server.refresh() } }
        }
        // "Open in Mango Signer": .ipa files go to the apps on this iPhone.
        .onOpenURL { url in
            guard url.pathExtension.lowercased() == "ipa" else { return }
            Task {
                do { let a = try await local.importIPA(url); toast = "Added \(a.name) to On this iPhone"; tab = 3 } catch { toast = error.localizedDescription }
            }
        }
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
                if let error {
                    Text(error).font(.subheadline).foregroundStyle(Theme.red).multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
        .background(Theme.bg.ignoresSafeArea())
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
