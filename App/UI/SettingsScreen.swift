import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @State private var confirmSignOut = false

    var unread: Int { (server.state?.alerts ?? []).filter { $0.read != true }.count }
    var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Theme.gradient)
                            Text(String((server.account?.username ?? "?").prefix(1)).uppercased())
                                .font(.title2.bold()).foregroundStyle(Theme.onAccent)
                        }
                        .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(server.account?.username ?? "").font(.headline).foregroundStyle(Theme.text)
                            Text(server.isOwner ? "Owner" : "Member").font(.caption).foregroundStyle(Theme.muted)
                            if let d = server.account?.deviceName, !d.isEmpty { Text(d).font(.caption2).foregroundStyle(Theme.muted) }
                        }
                    }
                    .padding(.vertical, 4)
                    if let s = server.state?.settings, let limit = s.signsPerDay, limit > 0 {
                        row("Signs left today", "\(max(0, limit - (s.signsToday ?? 0))) of \(limit)")
                    }
                }

                Section {
                    NavigationLink { AlertsScreen() } label: {
                        HStack {
                            Label("Alerts", systemImage: "bell.fill")
                            Spacer()
                            if unread > 0 { Badge(text: "\(unread)", style: .new) }
                        }
                    }
                    NavigationLink { ActivityScreen() } label: { Label("Activity", systemImage: "list.bullet.rectangle") }
                    NavigationLink { WhatsNewScreen() } label: { Label("What's New", systemImage: "sparkles") }
                }

                Section {
                    NavigationLink { LocalAppsScreen() } label: {
                        HStack { Label("Apps", systemImage: "square.stack.3d.up.fill"); Spacer(); Text("\(local.apps.count)").foregroundStyle(Theme.muted) }
                    }
                    NavigationLink { LocalCertsScreen() } label: {
                        HStack { Label("Certificates", systemImage: "checkmark.shield"); Spacer(); Text("\(local.certs.count)").foregroundStyle(Theme.muted) }
                    }
                } header: { Text("On this iPhone") } footer: {
                    Text("Your own .ipa files and certificates kept only on this iPhone, for signing without the server.")
                }

                if server.isOwner {
                    Section {
                        if let base = server.baseURL {
                            Link(destination: base) {
                                Label("Open the owner tools in Safari", systemImage: "safari")
                            }
                        }
                    } header: { Text("Owner") } footer: {
                        Text("Managing users, sources, Telegram and the rest is coming to the app. Until then it's in the website.")
                    }
                }

                Section {
                    row("Server", server.baseURL?.host ?? "")
                    if let v = server.state?.server?.version { row("Server version", v) }
                    row("App version", appVersion)
                    Button("Use a different server") { Task { await server.logout(); server.setServer(nil) } }
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .listRowBackground(Theme.card)
            .navigationTitle("Settings")
            .refreshable { await server.refresh() }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await server.logout() } }
            }
        }
    }

    func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(Theme.text); Spacer(); Text(v).foregroundStyle(Theme.muted) }
    }
}

struct AlertsScreen: View {
    @EnvironmentObject var server: Server
    var alerts: [SAlert] { (server.state?.alerts ?? []).sorted { (parseDate($0.at) ?? .distantPast) > (parseDate($1.at) ?? .distantPast) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if alerts.isEmpty {
                    EmptyState(icon: "bell.slash", title: "No alerts", message: "You'll see app updates and certificate warnings here.")
                } else {
                    Card {
                        ForEach(Array(alerts.enumerated()), id: \.element.id) { i, a in
                            if i > 0 { Divider().overlay(Theme.line) }
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(a.read == true ? Color.clear : Theme.mango).frame(width: 8, height: 8).padding(.top, 6)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(a.title ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                    if let b = a.body, !b.isEmpty { Text(b).font(.caption).foregroundStyle(Theme.muted) }
                                    Text(ago(a.at)).font(.caption2).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                            }
                            .padding(14)
                        }
                    }
                }
            }
            .padding(16)
        }
        .mangoScreen()
        .navigationTitle("Alerts")
        .task {
            if alerts.contains(where: { $0.read != true }) {
                _ = try? await server.post("/api/alerts/read")
                await server.refresh()
            }
        }
    }
}

struct ActivityScreen: View {
    @EnvironmentObject var server: Server
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if server.tasks.isEmpty {
                    EmptyState(icon: "checkmark.circle", title: "Nothing going on", message: "Signing and other tasks from the last half hour show up here.")
                } else {
                    Card {
                        ForEach(Array(server.tasks.enumerated()), id: \.element.id) { i, t in
                            if i > 0 { Divider().overlay(Theme.line) }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(t.title ?? "Task").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                    Spacer()
                                    statusBadge(t)
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
                                    Button("Stop") { cancel(t) }.font(.caption.weight(.semibold)).foregroundStyle(Theme.red)
                                }
                            }
                            .padding(14)
                        }
                    }
                }
            }
            .padding(16)
        }
        .mangoScreen()
        .navigationTitle("Activity")
        .toast($toast)
        .refreshable { await server.refreshTasks() }
        .task {
            while !Task.isCancelled {
                await server.refreshTasks()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func statusBadge(_ t: TaskInfo) -> Badge {
        switch t.status {
        case "running": return Badge(text: "Running", style: .mango)
        case "queued": return Badge(text: "Waiting", style: .blue)
        case "done": return Badge(text: "Done", style: .good)
        case "cancelled": return Badge(text: "Stopped")
        default: return Badge(text: "Failed", style: .bad)
        }
    }

    func cancel(_ t: TaskInfo) {
        Task {
            do { try await server.post("/api/jobs/\(t.id)/cancel"); await server.refreshTasks(); toast = "Stopping…" } catch { toast = error.localizedDescription }
        }
    }
}

struct WhatsNewScreen: View {
    @EnvironmentObject var server: Server
    @State private var entries: [WhatsNewEntry] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error { Text(error).foregroundStyle(Theme.red) }
                if entries.isEmpty && error == nil { ProgressView().tint(Theme.mango).frame(maxWidth: .infinity).padding(40) }
                ForEach(entries) { e in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(e.title ?? "Version \(e.version)").font(.headline).foregroundStyle(Theme.text)
                            Spacer()
                            Badge(text: "v\(e.version)", style: .mango)
                        }
                        if let d = e.date { Text(d).font(.caption).foregroundStyle(Theme.muted) }
                        if let s = e.summary, !s.isEmpty { Text(s).font(.subheadline).foregroundStyle(Theme.text.opacity(0.9)) }
                        ForEach(Array((e.sections ?? []).enumerated()), id: \.offset) { _, sec in
                            Text(sec.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mango).padding(.top, 4)
                            ForEach(Array(sec.items.enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•").foregroundStyle(Theme.muted)
                                    Text(item).font(.subheadline).foregroundStyle(Theme.text.opacity(0.9))
                                }
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(16)
        }
        .mangoScreen()
        .navigationTitle("What's New")
        .task {
            struct R: Decodable { var versions: [WhatsNewEntry] }
            do { let r: R = try await server.get("/api/whats-new"); entries = r.versions } catch { self.error = error.localizedDescription }
        }
    }
}
