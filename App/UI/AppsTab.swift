import SwiftUI

/// The main tab: import your own .ipa files and sign them (like ESign's Apps tab).
/// Apps imported here are saved on this iPhone. Apps imported on the website show up under "From your account".
struct AppsTab: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var router: Router
    @State private var picking = false
    @State private var importing = 0
    @State private var deleting: SApp?

    /// Website imports that aren't already saved here as the same app and version.
    var accountApps: [SApp] {
        (server.state?.imports ?? []).filter { a in !local.apps.contains { $0.bundleId == (a.bundleId ?? "") && $0.version == (a.version ?? "") } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { picking = true } label: {
                FilePickButtonLabel(icon: "plus", title: "Import an .ipa", sub: "From Files, iCloud Drive or Downloads. Only you can see apps you import.")
            }
            .buttonStyle(.plain)
            if importing > 0 {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.mango)
                    Text("Importing \(importing) app\(importing == 1 ? "" : "s")…").font(.subheadline).foregroundStyle(Theme.muted)
                }
                .padding(.top, 12)
            }

            if local.apps.isEmpty && accountApps.isEmpty && importing == 0 {
                WebEmpty(icon: "square.and.arrow.down", title: "Sign your own apps",
                         text: "Import an .ipa, then sign and install it with your certificate. You can also use \"Open in Mango Signer\" from another app.",
                         button: "Or browse the App Library") { router.tab = .library }
                    .padding(.top, 20)
            }

            if !local.apps.isEmpty {
                SectionTitle(text: "On this iPhone", count: local.apps.count)
                ListBox {
                    ForEach(Array(local.apps.enumerated()), id: \.element.id) { i, app in
                        if i > 0 { RowLine() }
                        localRow(app)
                    }
                }
                Hint(text: LocalStore.keepImports
                     ? "Saved on this iPhone until you delete them. Touch and hold an app to share or delete it."
                     : "Removed from this iPhone after you sign them (change this in \(server.isOwner ? "Settings" : "Account")).")
                    .padding(.top, 8)
            }

            if !accountApps.isEmpty {
                SectionTitle(text: "From your account", count: accountApps.count)
                ListBox {
                    ForEach(Array(accountApps.enumerated()), id: \.element.id) { i, app in
                        if i > 0 { RowLine() }
                        accountRow(app)
                    }
                }
                Hint(text: server.state?.importsOnGithub == true
                     ? "Imported on the website. They stay in your account until you delete them."
                     : "Imported on the website. They're kept for 3 days, so sign them before then.")
                    .padding(.top, 8)
            }
        }
        .onChange(of: router.importTick) { _ in picking = true }
        .fileImporter(isPresented: $picking, allowedContentTypes: [FileTypes.ipa], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            importing += urls.count
            Task {
                var last: LibraryApp?
                for url in urls {
                    do { last = try await local.importIPA(url) } catch { router.say("\(url.lastPathComponent): \(error.localizedDescription)") }
                    importing -= 1
                }
                if urls.count == 1, let a = last {
                    Haptics.success()
                    router.open(.signLocal(a.id)) // straight to signing, like the website
                } else if let a = last {
                    router.say("Imported \(urls.count) apps (last: \(a.name))")
                }
            }
        }
        .confirmationDialog("Delete \(deleting?.name ?? "app")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let d = deleting { deleteAccountApp(d) } }
        } message: { Text("It's removed from your account. Your signed copy stays in the Signed tab.") }
    }

    func localRow(_ app: LibraryApp) -> some View {
        let signed = local.signed.contains { $0.bundleId == app.bundleId && $0.version == app.version }
        return Button { router.open(.signLocal(app.id)) } label: {
            HStack(spacing: 12) {
                LocalIcon(id: app.id, name: app.name, size: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    HStack(spacing: 6) {
                        Badge(text: "📱 On this iPhone", small: true)
                        if signed { Badge(text: "Signed", style: .good, small: true) }
                    }
                    Text("\(app.version.isEmpty ? "—" : app.version) · \(formatSize(app.size))").font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                PillButton(title: "Sign") { router.open(.signLocal(app.id)) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            ShareLink(item: app.url) { Label("Share .ipa", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) { local.delete(app) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    func accountRow(_ app: SApp) -> some View {
        let signed = (server.state?.signed ?? []).contains { $0.appId == app.id }
        let daysLeft: Int? = parseDate(app.expires).map { max(0, Int(ceil($0.timeIntervalSinceNow / 86400))) }
        return Button { if app.available { router.open(.sign(app.id, presetId: nil)) } else { deleting = app } } label: {
            HStack(spacing: 12) {
                AppIconImage(app: app, size: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    HStack(spacing: 6) {
                        if app.onGithub { Badge(text: "☁ Saved", small: true) } else if app.savingToGithub { Badge(text: "☁ Saving…", small: true) }
                        if let d = daysLeft { Badge(text: d > 0 ? "Kept \(d)d" : "Removed soon", style: d <= 1 ? .warn : .plain, small: true) }
                        if signed { Badge(text: "Signed", style: .good, small: true) }
                        if !app.available { Badge(text: "File gone", style: .bad, small: true) }
                    }
                    Text("\(app.version ?? "—") · \(formatBytes(app.size))").font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                PillButton(title: "Sign", dim: !app.available) { if app.available { router.open(.sign(app.id, presetId: nil)) } else { deleting = app } }
            }
            .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { deleting = app } label: { Label("Delete", systemImage: "trash") }
        }
    }

    func deleteAccountApp(_ app: SApp) {
        guard let iid = app.importId else { return }
        Task {
            do { _ = try await server.data("DELETE", "/api/imports/\(iid)"); await server.refresh(); router.say("Deleted") } catch { router.say(error.localizedDescription) }
        }
    }
}

/// Certificates, for you and admins (the tab bar only fits five tabs, so it lives in Settings).
struct CertsListSheet: View {
    @EnvironmentObject var router: Router
    var body: some View {
        SheetScroll {
            HStack {
                SheetTitle(text: "Certificates")
                Button { router.open(.addCert) } label: {
                    Image(systemName: "plus").font(.headline).foregroundStyle(Theme.mango)
                        .frame(width: 36, height: 36).background(Theme.card2).clipShape(Circle())
                }
            }
            CertsTab()
        }
    }
}
