import SwiftUI

struct SettingsTab: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var router: Router
    @State private var confirmLogout = false
    @AppStorage("keepSignedCopies") private var keepCopies = true

    var settings: SSettings? { server.state?.settings }
    var info: SServerInfo? { server.state?.server }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if server.isOwner { ownerSections }
            accountSection
            phoneSection
            Text("🥭 Mango Signer \(info?.version ?? "")\(server.isOwner ? " · signing powered by zsign (MIT)" : "")\n© 2026 MangoMods · All rights reserved")
                .font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 26)
        }
        .confirmationDialog("Log out?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) { Task { await server.logout() } }
        }
    }

    func save(_ body: [String: Any], _ msg: String = "Saved") {
        Task {
            do { try await server.post("/api/settings", body, method: "PATCH"); await server.refresh(); router.say(msg) } catch { router.say(error.localizedDescription) }
        }
    }

    func website(_ what: String) {
        if let u = server.baseURL { UIApplication.shared.open(u) }
        router.say("\(what) opens on the website for now")
    }

    // MARK: owner

    @ViewBuilder
    var ownerSections: some View {
        if info?.https == false { WarningBox(text: "Your server isn't on HTTPS, so iOS will refuse to install apps. On Railway, generate a public domain for the service.", bad: true) }
        if info?.passwordSet == false { WarningBox(text: "No APP_PASSWORD is set, so anyone with your link has owner access. Add an APP_PASSWORD variable on Railway.") }

        SectionTitle(text: "Server")
        ListBox {
            ValueRow(title: "Address", value: info?.baseUrl ?? server.baseURL?.absoluteString ?? "")
            RowLine()
            ValueRow(title: "Signing engine", value: info?.zsign.map { "zsign \($0)" } ?? "Not installed")
            RowLine()
            ValueRow(title: "Version", value: info?.version ?? "")
        }

        SectionTitle(text: "Storage")
        storageCard

        SectionTitle(text: "Cloud Library")
        ListBox {
            LinkRow(title: "☁ Sources, GitHub & Telegram", value: "Website") { website("Cloud Library") }
        }

        SectionTitle(text: "Signing")
        ListBox {
            PickerRow(title: "IPA compression", selection: Binding(get: { settings?.zipLevel ?? 1 }, set: { save(["zipLevel": $0]) }),
                      options: [(0, "None (fastest)"), (1, "Level 1 (fast, default)"), (3, "Level 3"), (6, "Level 6"), (9, "Max (smallest)")])
            RowLine()
            ToggleRow(title: "Remove signed file after it installs", sub: "Frees the space right away. Re-sign any time.",
                      isOn: Binding(get: { settings?.deleteAfterInstall != false }, set: { save(["deleteAfterInstall": $0]) }))
            RowLine()
            PickerRow(title: "Delete signed files after", selection: Binding(get: { settings?.signedRetentionDays ?? 7 }, set: { save(["signedRetentionDays": $0]) }),
                      options: [(1, "1 day"), (3, "3 days"), (7, "7 days"), (30, "30 days"), (0, "Never")])
        }
        Hint(text: "Signed files are only needed to install. Removing old ones keeps big games from filling your Railway volume.").padding(.top, 8)

        SectionTitle(text: "Users")
        let failsToday = (server.state?.securityLog ?? []).filter { !$0.ok && Date().timeIntervalSince(parseDate($0.at) ?? .distantPast) < 86400 }.count
        ListBox {
            PickerRow(title: "Signed apps kept per user", selection: Binding(get: { settings?.maxSignedPerUser ?? 10 }, set: { save(["maxSignedPerUser": $0]) }),
                      options: [3, 5, 10, 20, 50].map { ($0, "\($0)") })
            RowLine()
            PickerRow(title: "Signs per user per day", sub: "You can change it per person on their page", selection: Binding(get: { settings?.signsPerDay ?? 0 }, set: { save(["signsPerDay": $0]) }),
                      options: [(0, "No limit"), (3, "3"), (5, "5"), (10, "10"), (20, "20"), (50, "50")])
            RowLine()
            LinkRow(title: "🛡 Security log", value: failsToday > 0 ? "\(failsToday) failed today" : "", valueColor: failsToday > 0 ? Theme.red : Theme.muted) { router.open(.securityLog) }
            RowLine()
            ToggleRow(title: "Sign in with iPhone (UDID)", isOn: Binding(get: { settings?.udidLogin == true }, set: { save(["udidLogin": $0]) }))
        }

        SectionTitle(text: "Library")
        let apps = server.state?.apps ?? []
        ListBox {
            ValueRow(title: "Apps", value: "\(apps.count) (\(apps.filter { $0.published != false }.count) shown)")
            RowLine()
            LinkRow(title: "Categories & collections", value: "\(server.state?.categories?.count ?? 0)") { website("Categories") }
            RowLine()
            LinkRow(title: "🧩 Tweaks", value: "\(server.state?.tweaks.count ?? 0)") { website("Tweaks") }
            RowLine()
            LinkRow(title: "📣 Announcement", value: (server.state?.announcement?.text ?? "").isEmpty ? "Off" : "On") { website("Announcements") }
            RowLine()
            ValueRow(title: "Your signed apps", value: "\(server.state?.signed?.count ?? 0)")
            RowLine()
            ValueRow(title: "Users", value: "\(server.state?.users.count ?? 0)")
        }

        SectionTitle(text: "Owner tools")
        ListBox {
            LinkRow(title: "📊 Stats & activity") { website("Stats") }
            RowLine()
            LinkRow(title: "📣 Message everyone") { website("Messages") }
            RowLine()
            LinkRow(title: "💾 Backup & restore", value: settings?.lastBackup.map { ago($0) } ?? "never") { website("Backups") }
        }
    }

    @ViewBuilder
    var storageCard: some View {
        let b = info?.storageBreakdown
        let total = max(1, info?.disk?.total ?? info?.storage ?? 1)
        VStack(alignment: .leading, spacing: 10) {
            if let d = info?.disk, let t = d.total, let f = d.free {
                HStack {
                    (Text(formatBytes(t - f)).bold() + Text(" of \(formatBytes(t)) used")).foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(formatBytes(f)) free").foregroundStyle(f < 1_073_741_824 ? Theme.red : Theme.muted)
                }
                .font(.subheadline)
                if f < 1_073_741_824 { WarningBox(text: "Storage is almost full. Big apps need about twice their size free to sign. Clean up below or delete apps you don't need.", bad: true) }
            }
            GeometryReader { g in
                HStack(spacing: 0) {
                    bar(b?.library, total, g.size.width, Theme.mango)
                    bar(b?.signed, total, g.size.width, Theme.blue)
                    bar(b?.certs, total, g.size.width, Theme.leaf)
                    bar(b?.temp, total, g.size.width, Theme.muted)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 10).background(Theme.bg2).clipShape(Capsule())
            FlowLayout(spacing: 12) {
                legend("Library", b?.library, Theme.mango)
                legend("Signed", b?.signed, Theme.blue)
                legend("Certs", b?.certs, Theme.leaf)
                legend("Temp", b?.temp, Theme.muted)
            }
            let cloud = (server.state?.apps ?? []).filter { $0.cloud != nil }
            if !cloud.isEmpty {
                Hint(text: "☁ \(cloud.count) app\(cloud.count == 1 ? "" : "s") (\(formatBytes(cloud.reduce(0) { $0 + ($1.size ?? 0) }))) live in the cloud and use no space here.")
            }
            HStack(spacing: 8) {
                WebButton(title: "Clean signed files") { maintenance("purge-signed") }
                WebButton(title: "Clear temp") { maintenance("clear-temp") }
            }
        }
        .padding(16).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func bar(_ n: Double?, _ total: Double, _ width: CGFloat, _ color: Color) -> some View {
        color.frame(width: max(width * 0.005, width * CGFloat((n ?? 0) / total)))
    }

    func legend(_ t: String, _ n: Double?, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(t) \(formatBytes(n).isEmpty ? "0 KB" : formatBytes(n))").font(.caption).foregroundStyle(Theme.muted)
        }
    }

    func maintenance(_ action: String) {
        Task {
            do {
                let r = try await server.post("/api/maintenance", ["action": action])
                router.say((r["message"] as? String) ?? "Done")
                await server.refresh()
            } catch { router.say(error.localizedDescription) }
        }
    }

    // MARK: account

    @ViewBuilder
    var accountSection: some View {
        let a = server.account
        let going = server.tasks.filter { ["running", "queued"].contains($0.status) }.count
        SectionTitle(text: "Account")
        ListBox {
            LinkRow(title: "⏳ Activity", value: going > 0 ? "\(going) going" : "", valueColor: Theme.mango) { router.open(.activity) }
            RowLine()
            LinkRow(title: "✨ What's New", value: "V\(info?.version ?? "")") { router.open(.whatsNew) }
            RowLine()
            ValueRow(title: "Username", value: a?.username ?? "")
            RowLine()
            ValueRow(title: "iPhone", value: a?.udid != nil ? "\(a?.deviceName ?? "iPhone")\n\(shortUdid(a?.udid ?? ""))" : "Not linked")
            if let udid = a?.udid {
                RowLine()
                LinkRow(title: "Copy my UDID", chevron: false) { UIPasteboard.general.string = udid; router.say("UDID copied") }
                RowLine()
                LinkRow(title: "Unlink iPhone", color: Theme.red, chevron: false) {
                    Task { do { try await server.post("/api/account", ["unlinkDevice": true], method: "PATCH"); router.say("iPhone unlinked"); await server.refresh() } catch { router.say(error.localizedDescription) } }
                }
            } else {
                RowLine()
                LinkRow(title: "Link this iPhone", color: Theme.mango, chevron: false) {
                    if let u = server.url("/udid/profile.mobileconfig?intent=link") { UIApplication.shared.open(u) }
                }
            }
            if !server.isOwner {
                RowLine()
                LinkRow(title: "Change Password") { router.open(.changePassword) }
            }
            RowLine()
            LinkRow(title: "🛡 Sign-ins & security", value: (server.state?.mySignins.first).map { ago($0.at) } ?? "") { router.open(.mySecurity) }
            if !server.isOwner, let limit = settings?.signsPerDay, limit > 0 {
                RowLine()
                ValueRow(title: "Signs today", value: "\(settings?.signsToday ?? 0) of \(limit)")
            }
            RowLine()
            LinkRow(title: "Log Out", color: Theme.red, chevron: false) { confirmLogout = true }
        }
        Hint(text: a?.udid != nil ? "Your iPhone can sign in without a password, and Mango checks whether it's in your profiles." : "Linking downloads a quick profile: open Settings › Profile Downloaded › Install, then come back.").padding(.top, 8)

        if !server.isOwner {
            SectionTitle(text: "My app requests")
            let reqs = server.state?.requests ?? []
            if !reqs.isEmpty {
                ListBox {
                    ForEach(Array(reqs.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { RowLine() }
                        RequestRow(r: r)
                    }
                }
                .padding(.bottom, 10)
            }
            WebButton(title: "+ Request an App") { router.open(.requestApp) }
        }
    }

    @ViewBuilder
    var phoneSection: some View {
        SectionTitle(text: "This app")
        ListBox {
            ToggleRow(title: "Save signed apps on this iPhone", sub: "Like ESign: everything you sign is kept here too, so it can always be installed again or shared",
                      isOn: Binding(get: { keepCopies }, set: { v in
                          keepCopies = v
                          if v { Task { await local.saveMissingCopies(server: server) } }
                      }))
            RowLine()
            ValueRow(title: "What's installed", value: DeviceApps.statusText,
                     sub: DeviceApps.seesOtherApps ? "" : "Mango goes by what you installed through it. Mark apps you deleted with \"Not on my phone anymore\" (touch and hold them in Signed).")
            RowLine()
            LinkRow(title: "📦 Apps on this iPhone", value: "\(local.apps.count)") { router.open(.localApps) }
            RowLine()
            LinkRow(title: "📱 Certificates on this iPhone", value: "\(local.certs.count)") { router.open(.localCerts) }
            RowLine()
            ValueRow(title: "App version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            RowLine()
            LinkRow(title: "Use a different server", value: server.baseURL?.host ?? "") {
                Task { await server.logout(); server.setServer(nil) }
            }
        }
    }
}

// MARK: - Alerts, Activity, What's New, security

struct AlertsSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let icons = ["broadcast": "📣", "update": "⬆️", "request": "🙋", "cert": "🔐", "security": "🔒", "user": "👋", "storage": "💾"]

    var body: some View {
        let list = server.state?.alerts ?? []
        SheetScroll {
            SheetTitle(text: "🔔 Alerts")
            if list.isEmpty {
                WebEmpty(icon: "bell.slash", title: "No alerts", text: "Updates to apps you installed, answers to your requests and certificate warnings show up here.")
            } else {
                ListBox(fill: Theme.bg2) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                        if i > 0 { RowLine() }
                        Button { open(a) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Text(icons[a.kind ?? ""] ?? "🔔").font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stripEmoji(a.title ?? "")).font(.system(size: 15, weight: a.read == true ? .regular : .semibold)).foregroundStyle(Theme.text)
                                    if let b = a.body, !b.isEmpty { Text(b).font(.system(size: 13)).foregroundStyle(Theme.muted) }
                                    Text(ago(a.at)).font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                if a.read != true { Circle().fill(Theme.mango).frame(width: 8, height: 8).padding(.top, 6) }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                WebButton(title: "Clear all") {
                    Task { do { _ = try await server.data("DELETE", "/api/alerts"); router.close(); router.say("Cleared"); await server.refresh() } catch { router.say(error.localizedDescription) } }
                }
                .padding(.top, 12)
            }
        }
        .task {
            let unread = list.filter { $0.read != true }.map { $0.id }
            if !unread.isEmpty {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                _ = try? await server.post("/api/alerts/read", ["ids": unread])
                await server.refresh()
            }
        }
    }

    func stripEmoji(_ s: String) -> String {
        guard let first = s.unicodeScalars.first, first.properties.isEmojiPresentation || first.properties.isEmoji && first.value > 0x2000 else { return s }
        return String(s.drop { !$0.isLetter && !$0.isNumber })
    }

    func open(_ a: SAlert) {
        let apps = server.state?.apps ?? []
        switch a.kind {
        case "update", "request":
            if let id = a.appId, apps.contains(where: { $0.id == id }) { router.open(.app(id)); return }
            if let rid = a.requestId, (server.state?.requests ?? []).contains(where: { $0.id == rid }) { router.open(.request(rid)) }
        case "cert": router.go(.certs)
        case "user": if let uid = a.userId, (server.state?.users ?? []).contains(where: { $0.id == uid }) { router.open(.user(uid)) }
        case "security": if server.isOwner { router.open(.securityLog) }
        case "storage": router.go(.settings)
        default: break
        }
    }
}

struct ActivitySheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router

    var body: some View {
        SheetScroll {
            SheetTitle(text: "⏳ Activity")
            if server.tasks.isEmpty {
                WebEmpty(icon: "checkmark.circle", title: "Nothing going on", text: "Signing, checks and other tasks from the last half hour show up here.")
            } else {
                ListBox(fill: Theme.bg2) {
                    ForEach(Array(server.tasks.enumerated()), id: \.element.id) { i, t in
                        if i > 0 { RowLine() }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(t.title ?? "Task").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                                Spacer()
                                badge(t)
                            }
                            if t.status == "running" {
                                if let p = t.progress { ProgressView(value: p).tint(Theme.mango) } else { ProgressView().tint(Theme.mango).frame(maxWidth: .infinity, alignment: .leading) }
                            }
                            if t.status == "queued", let w = t.waitingFor, !w.isEmpty {
                                Text("Waiting for \(w)\(t.position.map { " · #\($0) in line" } ?? "")").font(.caption).foregroundStyle(Theme.muted)
                            }
                            if let e = t.error, !e.isEmpty, t.status != "done" {
                                Text(e).font(.caption).foregroundStyle(Theme.red)
                            } else if let l = t.last, !l.isEmpty {
                                Text(l).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                            }
                            if t.cancellable == true {
                                Button("Stop") {
                                    Task { do { try await server.post("/api/jobs/\(t.id)/cancel"); await server.refreshTasks(); router.say("Stopping…") } catch { router.say(error.localizedDescription) } }
                                }
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.red)
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await server.refreshTasks()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func badge(_ t: TaskInfo) -> Badge {
        switch t.status {
        case "running": return Badge(text: "Running", style: .mango, small: true)
        case "queued": return Badge(text: "Waiting", style: .blue, small: true)
        case "done": return Badge(text: "Done", style: .good, small: true)
        case "cancelled": return Badge(text: "Stopped", small: true)
        default: return Badge(text: "Failed", style: .bad, small: true)
        }
    }
}

struct WhatsNewSheet: View {
    @EnvironmentObject var server: Server
    @State private var entries: [WhatsNewEntry] = []
    @State private var error: String?
    @State private var open: Set<String> = []

    var body: some View {
        SheetScroll {
            SheetTitle(text: "✨ What's New")
            if let error { WarningBox(text: error, bad: true) }
            if entries.isEmpty && error == nil { ProgressView().tint(Theme.mango).frame(maxWidth: .infinity).padding(40) }
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                VStack(alignment: .leading, spacing: 8) {
                    Button { withAnimation { if open.contains(e.id) { open.remove(e.id) } else { open.insert(e.id) } } } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(e.title ?? "Version \(e.version)").font(.headline).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                                Text("V\(e.version)\(e.date.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: (i == 0 || open.contains(e.id)) ? "chevron.up" : "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                    if let s = e.summary, !s.isEmpty { Text(s).font(.subheadline).foregroundStyle(Theme.soft) }
                    if i == 0 || open.contains(e.id) {
                        ForEach(Array((e.sections ?? []).enumerated()), id: \.offset) { _, sec in
                            Text(sec.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mango).padding(.top, 4)
                            ForEach(Array(sec.items.enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•").foregroundStyle(Theme.muted)
                                    Text(item).font(.subheadline).foregroundStyle(Theme.soft)
                                }
                            }
                        }
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.bottom, 10)
            }
        }
        .task {
            struct R: Decodable { var versions: [WhatsNewEntry] }
            do { let r: R = try await server.get("/api/whats-new"); entries = r.versions } catch { self.error = error.localizedDescription }
        }
    }
}

struct ChangePasswordSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    @State private var old = ""
    @State private var new = ""
    var body: some View {
        SheetScroll {
            SheetTitle(text: "Change Password")
            Field(label: "Current password") { SecureField("", text: $old).inputStyle() }
            Field(label: "New password") { SecureField("6+ characters", text: $new).inputStyle() }
            WebButton(title: "Save", kind: .primary, big: true) {
                Task {
                    do { try await server.post("/api/account", ["currentPassword": old, "newPassword": new], method: "PATCH"); server.rememberNewPassword(new); router.close(); router.say("Password changed") } catch { router.say(error.localizedDescription) }
                }
            }
        }
    }
}

struct MySecuritySheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    @State private var confirm = false
    var body: some View {
        let list = server.state?.mySignins ?? []
        SheetScroll {
            SheetTitle(text: "🛡 Sign-ins & security")
            Hint(text: "Recent sign-ins to your account. If you see one that wasn't you, sign out everywhere and \(server.isOwner ? "change APP_PASSWORD on Railway" : "change your password").").padding(.bottom, 12)
            if list.isEmpty {
                Hint(text: "No sign-ins recorded yet.")
            } else {
                ListBox(fill: Theme.bg2) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { RowLine() }
                        SigninRow(e: e)
                    }
                }
            }
            VStack(spacing: 10) {
                WebButton(title: "Sign out everywhere else") { confirm = true }
                if !server.isOwner { WebButton(title: "Change Password") { router.open(.changePassword) } }
            }
            .padding(.top, 12)
            Hint(text: "Signing out everywhere else keeps you signed in here. Accounts lock for 15 minutes after 8 wrong passwords in a row.").padding(.top, 8)
        }
        .confirmationDialog("Sign out every other phone and browser?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Sign out others", role: .destructive) {
                Task { do { try await server.post("/api/account/signout-others"); router.say("Signed out everywhere else"); await server.refresh() } catch { router.say(error.localizedDescription) } }
            }
        }
    }
}

struct SecurityLogSheet: View {
    @EnvironmentObject var server: Server
    var body: some View {
        let log = server.state?.securityLog ?? []
        let fails = log.filter { !$0.ok && Date().timeIntervalSince(parseDate($0.at) ?? .distantPast) < 86400 }.count
        SheetScroll {
            SheetTitle(text: "🛡 Security log")
            Hint(text: fails > 0 ? "\(fails) failed sign-in\(fails == 1 ? "" : "s") in the last day." : "No failed sign-ins in the last day.").padding(.bottom, 12)
            if log.isEmpty {
                Hint(text: "Nothing yet.")
            } else {
                ListBox(fill: Theme.bg2) {
                    ForEach(Array(log.prefix(200).enumerated()), id: \.element.id) { i, e in
                        if i > 0 { RowLine() }
                        SigninRow(e: e)
                    }
                }
            }
        }
    }
}
