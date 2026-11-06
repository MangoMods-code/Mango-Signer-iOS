import SwiftUI

// Cloud Library settings, like the website: sources (pinned ones in Settings, the rest under All sources),
// Telegram channels, GitHub storage and the Telegram bot.

let suggestedSources: [(name: String, url: String)] = [
    ("ryP0 Repository", "https://github.com/Sami-Wali/ryP0-repository/blob/main/repo.json"),
    ("MikeBuilds", "https://github.com/mikevillarroel/mikebuilds-source/blob/main/source.json"),
]

/// Where a background check / import goes back to when it's done.
func routeAfterJob(_ then: String) -> Route? {
    if then.hasPrefix("source:") { return .source(String(then.dropFirst(7))) }
    if then.hasPrefix("tgch:") { return .tgChannel(String(then.dropFirst(5))) }
    if then == "tg" { return .telegram(nil) }
    if then == "all" { return .allSources }
    return nil
}

// MARK: - The section in Settings

struct CloudSection: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router

    var body: some View {
        let srcs = (server.state?.sources ?? []).filter { !$0.isTelegram }
        let channels = (server.state?.sources ?? []).filter { $0.isTelegram }
        let shown = srcs.filter { $0.isPinned || $0.lastError != nil }
        let tg = server.state?.telegram
        let gh = server.state?.github
        SectionTitle(text: "Cloud Library")
        ListBox {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                if i > 0 { RowLine() }
                SourceRow(source: s) { router.open(.source(s.id)) }
            }
            if !srcs.isEmpty {
                if !shown.isEmpty { RowLine() }
                Button { router.open(.allSources) } label: {
                    HStack(spacing: 12) {
                        Text("☁").font(.system(size: 24)).frame(width: 46, height: 46).background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All sources").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                            Text("\(srcs.count) source\(srcs.count == 1 ? "" : "s") · \(srcs.reduce(0) { $0 + $1.apps }) apps\(srcs.count > shown.count && !shown.isEmpty ? " · \(srcs.count - shown.count) more" : "")")
                                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            RowLine()
            LinkRow(title: "＋ Add a source", value: "AltStore / ESign repos") { router.open(.addSource) }
            RowLine()
            LinkRow(title: "↻ Check all now", value: "Sources & channels") {
                Task {
                    do { try await server.post("/api/checks/run-all"); router.say("Checking everything for new apps and updates"); router.open(.activity) }
                    catch { router.say(error.localizedDescription) }
                }
            }
            if server.isOwner || tg?.connected == true {
                RowLine()
                LinkRow(title: "✈️ Telegram channels",
                        value: tg?.connected == true ? "\(channels.count) · \(channels.reduce(0) { $0 + $1.apps }) apps" : "Off") { router.open(.telegram(nil)) }
            }
            if server.isOwner {
                RowLine()
                LinkRow(title: "GitHub storage", value: gh?.connected == true ? "\(gh?.owner ?? "")/\(gh?.repo ?? "")" : "Off") { router.open(.github(false)) }
                RowLine()
                LinkRow(title: "🤖 Telegram bot", value: "") { router.open(.tgBot) }
                RowLine()
                LinkRow(title: "🌐 Translate descriptions", value: server.state?.settings?.translateOn == true ? "On" : "Off") { router.open(.translate) }
            }
        }
        Hint(text: "Cloud apps only keep their info and icon here. The file is downloaded while signing and deleted right after, so your Railway volume stays empty.").padding(.top, 6)
    }
}

struct SourceRow: View {
    let source: SSource
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                WebIcon(url: source.iconURL.flatMap { URL(string: $0) }, name: source.name, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(source.isPinned ? "📌 " : "")\(source.name)").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    if let e = source.lastError {
                        Text("⚠ \(e)").font(.system(size: 13)).foregroundStyle(Theme.red).lineLimit(1)
                    } else {
                        Text("\(source.apps) app\(source.apps == 1 ? "" : "s") · synced \(ago(source.lastSync))\(source.showInLibrary ? "" : " · hidden")")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - All sources

struct AllSourcesSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    @State private var query = ""
    var body: some View {
        let srcs = (server.state?.sources ?? []).filter { !$0.isTelegram }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = srcs.filter { q.isEmpty || [$0.name, $0.url, $0.subtitle ?? ""].contains { $0.lowercased().contains(q) } }
            .sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned }
                if (a.lastError != nil) != (b.lastError != nil) { return a.lastError != nil }
                if a.apps != b.apps { return a.apps > b.apps }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        SheetScroll {
            SheetTitle(text: "All sources")
            Hint(text: "\(srcs.count) sources · 📌 pinned ones show in Settings. Open a source to pin or unpin it.").padding(.bottom, 10)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search sources", text: $query).plainInput().foregroundStyle(Theme.text)
            }
            .inputStyle().padding(.bottom, 10)
            if list.isEmpty {
                Hint(text: "No sources match.", center: true).padding(.vertical, 20)
            } else {
                ListBox(fill: Theme.bg2) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                        if i > 0 { RowLine() }
                        SourceRow(source: s) { router.open(.source(s.id)) }
                    }
                }
            }
            WebButton(title: "＋ Add a source") { router.open(.addSource) }.padding(.top, 12)
        }
    }
}

// MARK: - Add a source

struct AddSourceSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    @State private var link = ""
    @State private var show = true
    @State private var busy = false
    var body: some View {
        let have = Set((server.state?.sources ?? []).map { $0.url })
        let sugg = suggestedSources.filter { s in !have.contains(rawGithub(s.url)) }
        SheetScroll {
            SheetTitle(text: "Add a Source")
            Hint(text: "A source is a list of apps someone keeps up to date (the same kind AltStore, SideStore, ESign and Feather use). Its apps show up in your library as links — nothing is downloaded to your server until someone signs one.").padding(.bottom, 12)
            Field(label: "Source link", hint: "Works with AltStore-style sources, GitHub repos (github.com/owner/repo — every release with an .ipa becomes a version) and a website's downloads page.") {
                TextField("https://…/source.json or github.com/owner/repo", text: $link).plainInput().keyboardType(.URL).inputStyle()
            }
            ListBox(fill: Theme.bg2) {
                ToggleRow(title: "Show its apps to everyone", sub: "Turn off to keep them just for you until you check them out", isOn: $show)
            }
            WebButton(title: busy ? "Reading source…" : "Add Source", kind: .primary, disabled: busy || link.trimmingCharacters(in: .whitespaces).isEmpty) { add(link) }
                .padding(.top, 12)
            if !sugg.isEmpty {
                SectionTitle(text: "Suggested")
                ListBox(fill: Theme.bg2) {
                    ForEach(Array(sugg.enumerated()), id: \.offset) { i, s in
                        if i > 0 { RowLine() }
                        HStack(spacing: 12) {
                            WebIcon(url: nil, name: s.name, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                                Text(s.url.replacingOccurrences(of: "https://github.com/", with: "")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                            PillButton(title: "Add") { add(s.url) }.disabled(busy)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                }
            }
        }
    }

    func rawGithub(_ u: String) -> String {
        u.replacingOccurrences(of: #"^https://github\.com/([^/]+)/([^/]+)/(?:blob|raw)/"#, with: "https://raw.githubusercontent.com/$1/$2/", options: .regularExpression)
    }

    func add(_ url: String) {
        let u = url.trimmingCharacters(in: .whitespaces)
        guard !u.isEmpty else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let r = try await server.post("/api/sources", ["url": u, "showInLibrary": show])
                await server.refresh()
                let src = r["source"] as? [String: Any]
                let id = src?["id"] as? String ?? ""
                if let job = r["jobId"] as? String {
                    router.say("Added \(src?["name"] as? String ?? "it"). Its apps come in after the current check.")
                    router.open(.jobRun("Checking \(src?["name"] as? String ?? "source")…", job, "source:\(id)"))
                    return
                }
                let added = ((r["result"] as? [String: Any])?["added"] as? NSNumber)?.intValue ?? 0
                router.say("Added \(src?["name"] as? String ?? "source"): \(added) app\(added == 1 ? "" : "s")")
                router.open(.source(id))
            } catch { router.say(error.localizedDescription) }
        }
    }
}

// MARK: - One source

struct SourceSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let sourceId: String
    @State private var name = ""
    @State private var loaded = false
    @State private var confirmRemove = false
    @State private var confirmDeleteMissing = false

    var source: SSource? { server.state?.sources.first { $0.id == sourceId } }

    var body: some View {
        if let s = source {
            let apps = (server.state?.apps ?? []).filter { $0.isSourceApp && $0.sourceName == s.name }
            let missing = apps.filter { $0.missing == true }.count
            SheetScroll {
                SheetHead(title: s.name, sub: subLine(s)) {
                    WebIcon(url: s.iconURL.flatMap { URL(string: $0) }, name: s.name, size: 76)
                }
                if let e = s.lastError { WarningBox(text: "Last refresh failed: \(e)", bad: true).padding(.bottom, 10) }
                VStack(spacing: 0) {
                    KVList(items: [
                        ("Apps", "\(s.apps)\(missing > 0 ? " (+\(missing) removed upstream)" : "")"),
                        ("Last refresh", s.lastSync != nil ? ago(s.lastSync) : "never"),
                        ("Link", s.url),
                    ])
                }
                .padding(.horizontal, 16).padding(.vertical, 6).background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Hint(text: "Refreshes by itself every hour. New versions show as UPDATED in the library. Anything you edit on an app (name, category, description…) is kept when it refreshes.").padding(.top, 8)

                ListBox(fill: Theme.bg2) {
                    ToggleRow(title: "Show its apps to everyone", sub: "Off = only you can see them",
                              isOn: Binding(get: { s.showInLibrary }, set: { v in patch(["showInLibrary": v], v ? "Shown to everyone" : "Only you can see these apps now") }))
                    RowLine()
                    ToggleRow(title: "Skip apps I already have", sub: "Don't add an app that's already in your library from somewhere else",
                              isOn: Binding(get: { s.skipHave ?? (s.kind != "ghrepo") }, set: { v in patch(["skipHave": v], v ? "Apps you already have are skipped" : "It adds every app, even ones you have") }))
                    RowLine()
                    ToggleRow(title: "📌 Pin to Settings", sub: "Always shown in Settings instead of only under All sources",
                              isOn: Binding(get: { s.isPinned }, set: { v in patch(["pinned": v], v ? "📌 Pinned to Settings" : "Moved to All sources") }))
                }
                .padding(.top, 12)

                Field(label: "Name in your library") { TextField(s.name, text: $name).inputStyle() }.padding(.top, 12)
                VStack(spacing: 10) {
                    WebButton(title: "Refresh now", kind: .primary) { sync(s) }
                    if !apps.isEmpty {
                        WebButton(title: "See its \(apps.count) app\(apps.count == 1 ? "" : "s") in the library") {
                            router.libCat = "src:\(s.name)"; router.libQuery = ""; router.go(.library)
                        }
                    }
                    if missing > 0 { WebButton(title: "🗑 Delete \(missing) removed app\(missing == 1 ? "" : "s")", kind: .danger) { confirmDeleteMissing = true } }
                    WebButton(title: "Save name", disabled: name.trimmingCharacters(in: .whitespaces).isEmpty || name == s.name) { patch(["name": name], "Renamed") }
                    WebButton(title: "Remove source", kind: .danger) { confirmRemove = true }
                }
                ExcludedList(source: s)
            }
            .onAppear { if !loaded { name = s.name; loaded = true } }
            .confirmationDialog("Remove \(s.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { remove(s) }
            } message: { Text("Its \(apps.count) app\(apps.count == 1 ? "" : "s") leave the library. People who installed them keep them.") }
            .confirmationDialog("Delete \(missing) removed app\(missing == 1 ? "" : "s")?", isPresented: $confirmDeleteMissing, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteMissing(s) }
            } message: { Text("These were removed from the source. This can't be undone.") }
        } else {
            SheetScroll { WebEmpty(icon: "questionmark.circle", title: "Source not found", text: "It may have been removed.") }
        }
    }

    func subLine(_ s: SSource) -> String {
        if let o = s.repoOwner { return "GitHub · \(o)/\(s.repoName ?? "")" }
        if let t = s.subtitle, !t.isEmpty { return t }
        return "App source"
    }
    func patch(_ body: [String: Any], _ msg: String) {
        Task {
            do { try await server.post("/api/sources/\(sourceId)", body, method: "PATCH"); await server.refresh(); router.say(msg) } catch { router.say(error.localizedDescription) }
        }
    }
    func sync(_ s: SSource) {
        Task {
            do {
                let r = try await server.post("/api/sources/\(s.id)/sync")
                if let w = r["waitingFor"] as? [String], let first = w.first { router.say("Waiting for \(first) to finish first — it starts right after") }
                if let job = r["jobId"] as? String { router.open(.jobRun("Checking \(s.name)…", job, "source:\(s.id)")) }
            } catch { router.say(error.localizedDescription) }
        }
    }
    func remove(_ s: SSource) {
        Task {
            do { _ = try await server.data("DELETE", "/api/sources/\(s.id)"); await server.refresh(); router.say("Source removed"); router.open(.allSources) } catch { router.say(error.localizedDescription) }
        }
    }
    func deleteMissing(_ s: SSource) {
        Task {
            do {
                let r = try await server.post("/api/apps/delete-removed", ["sourceId": s.id])
                await server.refresh()
                let n = (r["count"] as? NSNumber)?.intValue ?? 0
                router.say(n > 0 ? "Deleted \(n) removed app\(n == 1 ? "" : "s")" : "Nothing to delete — those apps are still there")
            } catch { router.say(error.localizedDescription) }
        }
    }
}

/// Apps you deleted from a source or channel, which it won't add back (tap Restore to let it).
struct ExcludedList: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let source: SSource
    var body: some View {
        if !source.excluded.isEmpty {
            SectionTitle(text: "Deleted from this \(source.isTelegram ? "channel" : "source")", count: source.excluded.count)
            Hint(text: "These won't come back when it refreshes.").padding(.bottom, 8)
            ListBox(fill: Theme.bg2) {
                ForEach(Array(source.excluded.enumerated()), id: \.offset) { i, e in
                    if i > 0 { RowLine() }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name ?? e.bundleId ?? "App").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                            if let b = e.bundleId { Text(b).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted) }
                        }
                        Spacer()
                        PillButton(title: "Restore") { restore(i) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
        }
    }
    func restore(_ i: Int) {
        Task {
            do {
                let r = try await server.post("/api/sources/\(source.id)/restore", ["index": i])
                await server.refresh()
                let name = r["restored"] as? String ?? "It"
                router.say((r["note"] as? String).map { "\(name) restored. \($0)" } ?? "\(name) is back")
            } catch { router.say(error.localizedDescription) }
        }
    }
}

// MARK: - Background checks (refresh, import, scan)

struct JobRunSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let title: String
    let jobId: String
    let then: String
    @State private var progress: Double?
    @State private var lines: [String] = []
    @State private var failure: String?
    @State private var started = false
    var body: some View {
        SheetScroll {
            VStack(spacing: 10) {
                Text(title).font(.title3.bold()).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                if let failure {
                    WarningBox(text: failure, bad: true)
                } else {
                    if let progress { ProgressView(value: progress).tint(Theme.mango) } else { ProgressView().tint(Theme.mango) }
                }
                if !lines.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(lines.joined(separator: "\n")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            Color.clear.frame(height: 1).id("end")
                        }
                        .frame(maxHeight: 240).background(Theme.bg).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onChange(of: lines.count) { _ in proxy.scrollTo("end") }
                    }
                }
                if failure == nil { Hint(text: "It runs on your server, so you can close this.", center: true) }
                if failure == nil && server.isOwner {
                    LinkButton(title: "Stop") { Task { _ = try? await server.post("/api/jobs/\(jobId)/cancel") } }
                }
                WebButton(title: failure == nil ? "Keep going in the background" : "Back") {
                    if let r = routeAfterJob(then) { router.open(r) } else { router.close() }
                }
            }
        }
        .task {
            guard !started else { return }
            started = true
            do {
                _ = try await server.waitJob(jobId) { p, l in
                    progress = p
                    if lines.last != l { lines.append(l); if lines.count > 300 { lines.removeFirst(lines.count - 300) } }
                }
                await server.refresh()
                router.say("Done ✓")
                if let r = routeAfterJob(then) { router.open(r) } else { router.close() }
            } catch is CancellationError {
            } catch {
                await server.refresh()
                failure = error.localizedDescription
            }
        }
    }
}

// MARK: - Telegram channels

struct TelegramSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let step: String?
    @State private var apiId = ""
    @State private var apiHash = ""
    @State private var phone = ""
    @State private var value = ""
    @State private var busy = false
    @State private var confirmOff = false

    var body: some View {
        let t = server.state?.telegram
        SheetScroll {
            if t?.connected != true {
                let pending = step ?? t?.pending
                if pending == "code" || pending == "password" { codeStep(pending == "password") } else { startStep }
            } else {
                connectedView(t!)
            }
        }
        .confirmationDialog("Disconnect Telegram?", isPresented: $confirmOff, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                Task { do { _ = try await server.data("DELETE", "/api/telegram"); await server.refresh(); router.say("Disconnected"); router.close() } catch { router.say(error.localizedDescription) } }
            }
        } message: { Text("Mango signs out of your account. Apps from channels stay listed but can't be signed until you connect again (unless they were copied to GitHub).") }
    }

    @ViewBuilder var startStep: some View {
        SheetTitle(text: "✈️ Telegram channels")
        Hint(text: "Mango signs in to Telegram as you and watches channels you pick. When a channel posts an .ipa, it's added to your library (or updates the app that's already there). Only you sign in — everyone else just sees the apps.").padding(.bottom, 12)
        VStack(alignment: .leading, spacing: 8) {
            Text("1. On your iPhone, open my.telegram.org in Safari and log in with your Telegram phone number (the code arrives in Telegram).")
            Text("2. Tap API development tools. Fill in any app title and short name (e.g. Mango / mangosigner), pick any platform, and tap Create application.")
            Text("3. Copy the App api_id (a number) and App api_hash (32 letters and numbers) into the boxes below.")
        }
        .font(.subheadline).foregroundStyle(Theme.soft).padding(.bottom, 12)
        Field(label: "API ID") { TextField("1234567", text: $apiId).keyboardType(.numberPad).inputStyle() }
        Field(label: "API hash") { TextField("0123456789abcdef…", text: $apiHash).plainInput().inputStyle() }
        Field(label: "Your Telegram phone number", hint: "With the country code. A spare Telegram account works too, and keeps your main one safer.") {
            TextField("+1 555 123 4567", text: $phone).keyboardType(.phonePad).inputStyle()
        }
        WebButton(title: busy ? "Sending…" : "Send login code", kind: .primary, big: true, disabled: busy) {
            run { _ = try await server.post("/api/telegram/login", ["apiId": apiId, "apiHash": apiHash, "phone": phone]); await server.refresh(); router.open(.telegram("code")) }
        }
        Hint(text: "Your login is stored encrypted on your server. Telegram will show \"Mango Signer\" under Settings › Devices, and you can end it there any time.").padding(.top, 10)
    }

    @ViewBuilder func codeStep(_ pw: Bool) -> some View {
        SheetTitle(text: pw ? "✈️ Two-step password" : "✈️ Enter the code")
        Hint(text: pw ? "Your Telegram account has a two-step verification password. Enter it to finish." : "Telegram just sent a login code to your Telegram app (check the chat named \"Telegram\"), or by text.").padding(.bottom, 12)
        Group {
            if pw { SecureField("Password", text: $value) } else { TextField("12345", text: $value).keyboardType(.numberPad).textContentType(.oneTimeCode) }
        }
        .inputStyle().padding(.bottom, 12)
        WebButton(title: busy ? "Checking…" : pw ? "Finish" : "Sign in", kind: .primary, big: true, disabled: busy || value.isEmpty) {
            run {
                let r = try await server.post(pw ? "/api/telegram/password" : "/api/telegram/code", pw ? ["password": value] : ["code": value])
                await server.refresh()
                if (r["needPassword"] as? Bool) == true { value = ""; router.open(.telegram("password")); return }
                router.say("Telegram connected ✈️")
                router.open(.telegram(nil))
            }
        }
        LinkButton(title: "Start over") {
            Task { _ = try? await server.data("DELETE", "/api/telegram"); await server.refresh(); router.open(.telegram("start")) }
        }
    }

    @ViewBuilder func connectedView(_ t: STelegramInfo) -> some View {
        let chans = (server.state?.sources ?? []).filter { $0.isTelegram }
        SheetTitle(text: "✈️ Telegram channels")
        if let e = t.error { WarningBox(text: e, bad: true).padding(.bottom, 10) }
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Signed in as \(t.meName ?? "you")").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    Badge(text: "Connected", style: .good, small: true)
                }
                let sub = [t.meUsername.map { "@\($0)" }, t.mePhone].compactMap { $0 }.joined(separator: " · ")
                if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(Theme.muted) }
            }
            Spacer()
        }
        .padding(14).background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)).padding(.bottom, 12)
        if !chans.isEmpty {
            ListBox(fill: Theme.bg2) {
                ForEach(Array(chans.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { RowLine() }
                    Button { router.open(.tgChannel(c.id)) } label: {
                        HStack(spacing: 12) {
                            Text("✈️").font(.system(size: 22)).frame(width: 46, height: 46).background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                                if let e = c.lastError { Text("⚠ \(e)").font(.system(size: 13)).foregroundStyle(Theme.red).lineLimit(1) } else {
                                    Text("\(c.apps) app\(c.apps == 1 ? "" : "s") · \(c.lastSync != nil ? "checked \(ago(c.lastSync))" : "not checked yet")\(c.options.storage == "github" ? " · GitHub copies" : "")")
                                        .font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        Button { router.open(.tgChannel(nil)) } label: {
            FilePickButtonLabel(icon: "plus", title: "Add a channel", sub: "Its @username or t.me link")
        }
        .buttonStyle(.plain).padding(.top, 12)
        Hint(text: "Channels, GitHub repos and sources are checked every hour, one at a time. Only posts with an .ipa file are looked at.").padding(.top, 10)
        if server.isOwner { WebButton(title: "Disconnect Telegram", kind: .danger) { confirmOff = true }.padding(.top, 12) }
    }

    func run(_ work: @escaping () async throws -> Void) {
        busy = true
        Task { defer { busy = false }; do { try await work() } catch { router.say(error.localizedDescription) } }
    }
}

/// Add a channel (channelId nil) or change one.
struct TgChannelSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let channelId: String?
    @State private var ref = ""
    @State private var backfill = 10
    @State private var storage = "telegram"
    @State private var skipHave = true
    @State private var updateMine = false
    @State private var matchName = false
    @State private var captionNotes = true
    @State private var autoSync = true
    @State private var show = true
    @State private var keywords = ""
    @State private var categoryId = "__auto"
    @State private var name = ""
    @State private var loaded = false
    @State private var busy = false
    @State private var confirmRemove = false
    @State private var confirmDeleteMissing = false

    var channel: SSource? { channelId.flatMap { id in server.state?.sources.first { $0.id == id } } }
    var gh: Bool { server.state?.github?.connected == true }

    var body: some View {
        SheetScroll {
            if let c = channel { edit(c) } else { add }
        }
        .confirmationDialog("Remove \(channel?.name ?? "channel")?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { if let c = channel { removeChannel(c) } }
        } message: { Text("Its \(channelApps.count) app\(channelApps.count == 1 ? "" : "s") leave the library. People who installed them keep them.") }
        .confirmationDialog("Delete \(channelApps.filter { $0.missing == true }.count) removed apps?", isPresented: $confirmDeleteMissing, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let c = channel { deleteMissing(c) } }
        } message: { Text("Mango double-checks the channel first, so only apps that are really gone get deleted. This can't be undone.") }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let c = channel {
                let o = c.options
                storage = o.storage == "github" ? "github" : "telegram"; skipHave = o.skipHave != false; updateMine = o.updateMine == true
                matchName = o.matchName == true; captionNotes = o.captionNotes != false; autoSync = o.autoSync != false
                show = c.showInLibrary; keywords = o.keywords ?? ""; categoryId = c.categoryId ?? "__auto"; name = c.name
            }
        }
    }

    var channelApps: [SApp] {
        guard let c = channel else { return [] }
        return (server.state?.apps ?? []).filter { $0.cloud == "telegram" && $0.sourceName == c.name }
    }

    func removeChannel(_ c: SSource) {
        Task {
            do { _ = try await server.data("DELETE", "/api/sources/\(c.id)"); await server.refresh(); router.say("Channel removed"); router.open(.telegram(nil)) } catch { router.say(error.localizedDescription) }
        }
    }

    func deleteMissing(_ c: SSource) {
        Task {
            do {
                let r = try await server.post("/api/apps/delete-removed", ["sourceId": c.id]); await server.refresh()
                let n = (r["count"] as? NSNumber)?.intValue ?? 0
                router.say(n > 0 ? "Deleted \(n) removed app\(n == 1 ? "" : "s")" : "Nothing to delete — those apps are still there")
            } catch { router.say(error.localizedDescription) }
        }
    }

    var options: [String: Any] {
        ["storage": storage, "skipHave": skipHave, "updateMine": updateMine, "matchName": matchName, "captionNotes": captionNotes, "autoSync": autoSync, "keywords": keywords]
    }

    @ViewBuilder var settingsForm: some View {
        Field(label: "Where the files live", hint: "Link only is fastest to set up. A GitHub copy keeps working even if the channel deletes the post.") {
            SelectBox(selection: $storage, options: [("telegram", "On Telegram (link only, uses no storage)"), ("github", gh ? "Copy to my GitHub storage" : "Copy to GitHub (connect GitHub first)")])
        }
        ListBox(fill: Theme.bg2) {
            ToggleRow(title: "Skip apps I already have", sub: "Don't add an app that's already in your library from another channel, repo or upload", isOn: $skipHave)
            RowLine()
            ToggleRow(title: "Update apps I added myself", sub: "If the channel posts a newer version of an app you uploaded, replace yours with it", isOn: $updateMine)
            RowLine()
            ToggleRow(title: "Also match by app name", sub: "For channels that change the bundle ID between builds", isOn: $matchName)
            RowLine()
            ToggleRow(title: "Use the post's text as “What's new”", sub: "Promo lines (Tap Here, links, @mentions) are left out", isOn: $captionNotes)
            RowLine()
            ToggleRow(title: "Check automatically", sub: "Every hour", isOn: $autoSync)
            RowLine()
            ToggleRow(title: "Show its apps to everyone", sub: "Off = only you can see them until you turn it on", isOn: $show)
        }
        Field(label: "Only import posts that mention", hint: "Comma-separated. Leave empty to import every .ipa.") {
            TextField("Optional, e.g. mortal kombat, youtube", text: $keywords).plainInput().inputStyle()
        }
        .padding(.top, 12)
        Field(label: "Category for new apps") {
            SelectBox(selection: $categoryId, options: [("__auto", "✨ Automatic (your rules, then the App Store)"), ("__none", "Uncategorized")]
                      + (server.state?.categories ?? []).map { ($0.id, [$0.emoji ?? "", $0.name].filter { !$0.isEmpty }.joined(separator: " ")) })
        }
    }

    @ViewBuilder var add: some View {
        SheetTitle(text: "Add a Telegram channel")
        Field(label: "Channel", hint: "Public channels work right away. For a private one, join it in Telegram first and use its @username.") {
            TextField("@channelname or https://t.me/channelname", text: $ref).plainInput().inputStyle()
        }
        Field(label: "Import recent posts", hint: "If the same app was posted several times, only its newest version is kept.") {
            SelectBox(selection: $backfill, options: [(0, "None — only new posts from now on"), (5, "Last 5 .ipa posts"), (10, "Last 10"), (25, "Last 25"), (50, "Last 50")])
        }
        settingsForm
        WebButton(title: busy ? "Finding the channel…" : "Add channel", kind: .primary, big: true, disabled: busy || ref.trimmingCharacters(in: .whitespaces).isEmpty) {
            busy = true
            Task {
                defer { busy = false }
                do {
                    var o = options; o["backfill"] = backfill
                    let r = try await server.post("/api/telegram/channels", ["ref": ref, "showInLibrary": show, "categoryId": categoryId, "options": o])
                    await server.refresh()
                    if let job = r["jobId"] as? String { router.open(.jobRun("Importing…", job, "tg")) } else { router.open(.telegram(nil)) }
                } catch { router.say(error.localizedDescription) }
            }
        }
        .padding(.top, 12)
    }

    func channelFacts(_ c: SSource) -> [(String, String)] {
        var items: [(String, String)] = [("Apps", "\(c.apps)"), ("Last check", c.lastSync != nil ? ago(c.lastSync) : "never")]
        if let r = c.lastResult {
            var bits: [String] = ["\(r.added) new", "\(r.updated) updated"]
            if r.same > 0 { bits.append("\(r.same) already had") }
            if r.failed > 0 { bits.append("\(r.failed) failed") }
            items.append(("Last result", bits.joined(separator: " · ")))
        }
        return items
    }

    @ViewBuilder func edit(_ c: SSource) -> some View {
        let apps = (server.state?.apps ?? []).filter { $0.cloud == "telegram" && $0.sourceName == c.name }
        let missing = apps.filter { $0.missing == true }.count
        SheetHead(title: c.name, sub: c.username.map { "@\($0)" } ?? "Telegram channel") {
            Text("✈️").font(.system(size: 36)).frame(width: 76, height: 76).background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        if let e = c.lastError { WarningBox(text: "Last check failed: \(e)", bad: true).padding(.bottom, 10) }
        VStack(spacing: 0) {
            KVList(items: channelFacts(c))
        }
        .padding(.horizontal, 16).padding(.vertical, 6).background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        VStack(spacing: 10) {
            WebButton(title: "Check for new posts now", kind: .primary) {
                Task {
                    do {
                        let r = try await server.post("/api/sources/\(c.id)/sync")
                        if let w = r["waitingFor"] as? [String], let first = w.first { router.say("Waiting for \(first) to finish first — it starts right after") }
                        if let job = r["jobId"] as? String { router.open(.jobRun("Checking \(c.name)…", job, "tgch:\(c.id)")) }
                    } catch { router.say(error.localizedDescription) }
                }
            }
            if !apps.isEmpty { WebButton(title: "See its \(apps.count) app\(apps.count == 1 ? "" : "s")") { router.libCat = "src:\(c.name)"; router.libQuery = ""; router.go(.library) } }
            if missing > 0 { WebButton(title: "🗑 Delete \(missing) removed app\(missing == 1 ? "" : "s")", kind: .danger) { confirmDeleteMissing = true } }
        }
        .padding(.top, 12)
        SectionTitle(text: "Settings")
        settingsForm
        Field(label: "Name in your library") { TextField(c.name, text: $name).inputStyle() }
        VStack(spacing: 10) {
            WebButton(title: busy ? "Saving…" : "Save settings", kind: .primary, disabled: busy) {
                busy = true
                Task {
                    defer { busy = false }
                    do {
                        try await server.post("/api/sources/\(c.id)", ["name": name, "showInLibrary": show, "categoryId": categoryId, "options": options], method: "PATCH")
                        await server.refresh(); router.say("Saved")
                    } catch { router.say(error.localizedDescription) }
                }
            }
            WebButton(title: "🔍 Scan older posts") { router.open(.tgScan(c.id)) }
            WebButton(title: "Back") { router.open(.telegram(nil)) }
            WebButton(title: "Remove channel", kind: .danger) { confirmRemove = true }
        }
        ExcludedList(source: c)
    }
}

struct TgScanSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let channelId: String
    @State private var count = 100
    @State private var quick = true
    @State private var recheck = false
    var body: some View {
        let c = server.state?.sources.first { $0.id == channelId }
        SheetScroll {
            SheetTitle(text: "🔍 Scan older posts")
            Hint(text: "Looks back through \(c?.name ?? "the channel")'s history for .ipa files and adds any apps you don't have yet. Apps already in your library stay exactly as they are, and an older post never replaces a newer version.").padding(.bottom, 12)
            Field(label: "How far back", hint: "\(c?.deepest.map { "Last deep scan went back \($0) posts. " } ?? "")Bigger scans take longer, and you can stop any time. Apps found so far are kept.") {
                SelectBox(selection: $count, options: [(25, "Last 25 .ipa posts"), (50, "Last 50"), (100, "Last 100"), (250, "Last 250"), (500, "Last 500"), (1000, "Last 1,000"), (0, "Everything (the whole channel)")])
            }
            ListBox(fill: Theme.bg2) {
                ToggleRow(title: "Quick mode", sub: "Skips older reposts of the same app by file name, without opening them. Much faster on big channels.", isOn: $quick)
                RowLine()
                ToggleRow(title: "Re-check posts already checked", sub: "Off = posts looked at in an earlier scan are skipped instantly", isOn: $recheck)
            }
            if let k = c?.options.keywords, !k.isEmpty { Hint(text: "Only posts that mention: \(k) (change this in the channel's settings).").padding(.top, 8) }
            if c?.options.storage == "github" { WarningBox(text: "This channel copies files to GitHub, so a big scan can take a long time. Switch it to \"On Telegram\" in the channel settings first if you want it fast.").padding(.top, 8) }
            WebButton(title: "Start scanning", kind: .primary, big: true) {
                Task {
                    do {
                        let r = try await server.post("/api/sources/\(channelId)/scan", ["count": count, "quick": quick, "recheck": recheck])
                        if let w = r["waitingFor"] as? [String], let first = w.first { router.say("Waiting for \(first) to finish first — it starts right after") }
                        if let job = r["jobId"] as? String { router.open(.jobRun("Scanning \(c?.name ?? "channel")…", job, "tgch:\(channelId)")) }
                    } catch { router.say(error.localizedDescription) }
                }
            }
            .padding(.top, 12)
            LinkButton(title: "Back") { router.open(.tgChannel(channelId)) }
        }
    }
}

// MARK: - GitHub storage

struct GithubSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let editing: Bool
    @State private var repo = ""
    @State private var token = ""
    @State private var busy = false
    @State private var loaded = false
    @State private var confirmOff = false

    var body: some View {
        let g = server.state?.github
        SheetScroll {
            if g?.connected != true || editing { setup(g) } else { connected(g!) }
        }
        .onAppear { if !loaded { loaded = true; if let o = g?.owner, let r = g?.repo { repo = "\(o)/\(r)" } } }
        .confirmationDialog("Disconnect GitHub?", isPresented: $confirmOff, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                Task { do { _ = try await server.data("DELETE", "/api/github"); await server.refresh(); router.say("Disconnected"); router.close() } catch { router.say(error.localizedDescription) } }
            }
        } message: { Text("Your \(g?.apps ?? 0) GitHub app\(g?.apps == 1 ? "" : "s") stay listed but can't be signed until you connect again. Nothing is deleted from GitHub.") }
    }

    @ViewBuilder func setup(_ g: SGithubInfo?) -> some View {
        SheetTitle(text: "GitHub storage")
        Hint(text: "Keep your own IPAs in a GitHub repo (private works) instead of on Railway. Files up to 2 GB each, and it's free.").padding(.bottom, 12)
        if !editing {
            VStack(alignment: .leading, spacing: 8) {
                Text("1. On github.com make a new repository (e.g. mango-ipas). Set it to Private and tick Add a README.")
                Text("2. Go to Settings › Developer settings › Personal access tokens › Fine-grained tokens and tap Generate new token.")
                Text("3. Under Repository access pick Only select repositories and choose that repo. Under Permissions › Repository permissions set Contents to Read and write.")
                Text("4. Copy the token and paste it below.")
            }
            .font(.subheadline).foregroundStyle(Theme.soft).padding(.bottom, 12)
        }
        Field(label: "Repository", hint: "owner/name, or paste the repo's link") { TextField("your-name/mango-ipas", text: $repo).plainInput().inputStyle() }
        Field(label: "Token", hint: "Stored encrypted on your server and never shown again.") {
            SecureField(g?.connected == true ? "Leave blank to keep the current token" : "github_pat_…", text: $token).plainInput().inputStyle()
        }
        WebButton(title: busy ? "Checking…" : g?.connected == true ? "Save" : "Connect", kind: .primary, disabled: busy) {
            let clean = repo.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"^https?://github\.com/"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: ".git", with: "").split(separator: "/").map(String.init)
            guard clean.count >= 2 else { router.say("Enter the repo as owner/name"); return }
            busy = true
            Task {
                defer { busy = false }
                do {
                    let r = try await server.post("/api/github", ["owner": clean[0], "repo": clean[1], "token": token.trimmingCharacters(in: .whitespaces)], method: "PUT")
                    await server.refresh()
                    let added = ((r["result"] as? [String: Any])?["added"] as? NSNumber)?.intValue ?? 0
                    router.say(added > 0 ? "Connected · found \(added) app\(added == 1 ? "" : "s")" : "GitHub connected")
                    router.open(.github(false))
                } catch { router.say(error.localizedDescription) }
            }
        }
        if editing { WebButton(title: "Back") { router.open(.github(false)) }.padding(.top, 8) }
    }

    @ViewBuilder func connected(_ g: SGithubInfo) -> some View {
        SheetTitle(text: "GitHub storage")
        if let e = g.lastError { WarningBox(text: e, bad: true).padding(.bottom, 10) }
        VStack(spacing: 0) {
            KVList(items: [("Repo", "\(g.owner ?? "")/\(g.repo ?? "") · \(g.isPrivate ? "Private" : "Public")"), ("Apps there", "\(g.apps)"), ("Last sync", g.lastSync != nil ? ago(g.lastSync) : "never")])
        }
        .padding(.horizontal, 16).padding(.vertical, 6).background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        ListBox(fill: Theme.bg2) {
            ToggleRow(title: "Save new uploads to GitHub", sub: "Apps you upload go straight to your repo, then get removed from this server",
                      isOn: Binding(get: { g.storeUploads }, set: { v in patch(["storeUploads": v], v ? "New uploads go to GitHub" : "New uploads stay on this server") }))
            RowLine()
            ToggleRow(title: "Keep signed apps on GitHub",
                      sub: g.isPrivate ? "Signed apps stay in everyone's Signed tab until they delete them, without using space here\(g.signedSaved > 0 ? " · \(g.signedSaved) saved" : "")" : "Needs a private repo — anyone could download signed apps from a public one",
                      isOn: Binding(get: { g.signedToGithub }, set: { v in patch(["signedToGithub": v], v ? "Signed apps are saved to GitHub" : "Signed apps stay on this server only") }))
        }
        .padding(.top, 12)
        VStack(spacing: 10) {
            WebButton(title: busy ? "Syncing…" : "Sync with GitHub", kind: .primary, disabled: busy) {
                busy = true
                Task {
                    defer { busy = false }
                    do {
                        let r = (try await server.post("/api/github/sync"))["result"] as? [String: Any] ?? [:]
                        await server.refresh()
                        let n = { (k: String) in (r[k] as? NSNumber)?.intValue ?? 0 }
                        let bits = [n("added") > 0 ? "\(n("added")) added" : "", n("removed") > 0 ? "\(n("removed")) removed" : ""].filter { !$0.isEmpty }
                        router.say(bits.isEmpty ? "Already in sync" : bits.joined(separator: " · "))
                    } catch { await server.refresh(); router.say(error.localizedDescription) }
                }
            }
            if let o = g.owner, let r = g.repo, let u = URL(string: "https://github.com/\(o)/\(r)/releases/tag/\(g.tag ?? "mango-library")") {
                WebButton(title: "Open the release on GitHub ↗") { UIApplication.shared.open(u) }
            }
            WebButton(title: "Change repo or token") { router.open(.github(true)) }
            WebButton(title: "Disconnect", kind: .danger) { confirmOff = true }
        }
        .padding(.top, 12)
    }

    func patch(_ body: [String: Any], _ msg: String) {
        Task {
            do { try await server.post("/api/github", body, method: "PATCH"); await server.refresh(); router.say(msg) } catch { await server.refresh(); router.say(error.localizedDescription) }
        }
    }
}

// MARK: - Telegram bot

struct TgBotSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    struct Chat: Identifiable { var id: String; var title: String; var type: String; var admin: Bool? }
    @State private var bot: [String: Any]?
    @State private var chats: [Chat] = []
    @State private var token = ""
    @State private var busy = false
    @State private var confirmOff = false
    // settings
    @State private var updatesChat = ""
    @State private var appsChat = ""
    @State private var groupChat = ""
    @State private var aServer = true
    @State private var aIos = true
    @State private var aApps = true
    @State private var rServer = ""
    @State private var rIos = ""
    @State private var captcha = true
    @State private var antispam = true
    @State private var flood = true
    @State private var cleanJoins = true
    @State private var newHours = "24"
    @State private var words = ""
    @State private var welcome = ""
    @State private var rules = ""
    @State private var brand = ""
    @State private var publicUrl = ""
    @State private var contact = ""

    var body: some View {
        SheetScroll {
            if let bot {
                if (bot["connected"] as? Bool) == true { connected(bot) } else { connect }
            } else {
                ProgressView().tint(Theme.mango).frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
        .task { await load() }
        .confirmationDialog("Disconnect the bot?", isPresented: $confirmOff, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                Task { do { _ = try await server.data("DELETE", "/api/tgbot"); router.say("Bot disconnected"); router.close() } catch { router.say(error.localizedDescription) } }
            }
        } message: { Text("It stops posting and moderating until you connect it again.") }
    }

    func load() async {
        guard let d = try? await server.data("GET", "/api/tgbot"),
              let b = (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["bot"] as? [String: Any] else { router.say("Couldn't load the bot's settings"); return }
        chats = ((b["chats"] as? [[String: Any]]) ?? []).map { c in
            Chat(id: (c["id"] as? NSNumber)?.stringValue ?? (c["id"] as? String ?? ""), title: c["title"] as? String ?? "Chat", type: c["type"] as? String ?? "", admin: c["admin"] as? Bool)
        }
        updatesChat = b["updatesChat"] as? String ?? ""; appsChat = b["appsChat"] as? String ?? ""; groupChat = b["groupChat"] as? String ?? ""
        let an = b["announce"] as? [String: Any] ?? [:]
        aServer = an["server"] as? Bool ?? true; aIos = an["ios"] as? Bool ?? true; aApps = an["apps"] as? Bool ?? true
        let rp = b["repos"] as? [String: Any] ?? [:]
        rServer = rp["server"] as? String ?? ""; rIos = rp["ios"] as? String ?? ""
        let m = b["mod"] as? [String: Any] ?? [:]
        captcha = m["captcha"] as? Bool ?? true; antispam = m["antispam"] as? Bool ?? true; flood = m["flood"] as? Bool ?? true; cleanJoins = m["cleanJoins"] as? Bool ?? true
        newHours = "\((m["newHours"] as? NSNumber)?.intValue ?? 24)"; words = ((m["bannedWords"] as? [String]) ?? []).joined(separator: "\n")
        welcome = b["welcome"] as? String ?? ""; rules = b["rules"] as? String ?? ""; brand = b["brand"] as? String ?? ""
        publicUrl = b["publicUrl"] as? String ?? ""; contact = (b["contact"] as? String).map { $0.isEmpty ? "" : "@\($0)" } ?? ""
        bot = b
    }

    @ViewBuilder var connect: some View {
        SheetTitle(text: "🤖 Telegram bot")
        Hint(text: "A bot posts new Mango Signer versions, iPhone app builds and library apps in your channels, and keeps your chat clean. It's a separate bot account, not your own Telegram.").padding(.bottom, 12)
        VStack(alignment: .leading, spacing: 8) {
            Text("1. In Telegram, open @BotFather and send /newbot.")
            Text("2. Pick a name (like Mango Signer) and a username ending in bot (like MangoSignerBot).")
            Text("3. BotFather sends a token like 1234567890:AAH…. Copy it and paste it here.")
        }
        .font(.subheadline).foregroundStyle(Theme.soft).padding(.bottom, 12)
        Field(label: "Bot token", hint: "Saved encrypted on your server and never shown again.") { SecureField("1234567890:AAH…", text: $token).plainInput().inputStyle() }
        WebButton(title: busy ? "Connecting…" : "Connect bot", kind: .primary, big: true, disabled: busy || token.isEmpty) {
            busy = true
            Task {
                defer { busy = false }
                do { try await server.post("/api/tgbot/token", ["token": token]); router.say("Bot connected 🤖"); await load() } catch { router.say(error.localizedDescription) }
            }
        }
    }

    func chatPicker(_ label: String, _ sel: Binding<String>, kinds: [String], none: String, hint: String = "") -> some View {
        var opts: [(String, String)] = [("", none)] + chats.filter { kinds.contains($0.type) }.map { ($0.id, "\($0.type == "channel" ? "📢" : "💬") \($0.title)\($0.admin == false ? " (not admin)" : "")") }
        if !sel.wrappedValue.isEmpty && !opts.contains(where: { $0.0 == sel.wrappedValue }) { opts.append((sel.wrappedValue, sel.wrappedValue)) }
        return Field(label: label, hint: hint) { SelectBox(selection: sel, options: opts) }
    }

    @ViewBuilder func connected(_ b: [String: Any]) -> some View {
        let running = b["running"] as? Bool ?? false
        let queued = (b["queued"] as? NSNumber)?.intValue ?? 0
        SheetTitle(text: "🤖 Telegram bot")
        HStack(spacing: 8) {
            Text("@\(b["username"] as? String ?? "bot")").font(.subheadline).foregroundStyle(Theme.muted)
            Badge(text: running ? "Running" : "Stopped", style: running ? .good : .bad, small: true)
            if queued > 0 { Text("· \(queued) app post\(queued == 1 ? "" : "s") waiting").font(.caption).foregroundStyle(Theme.muted) }
        }
        .padding(.bottom, 10)
        if let e = b["lastError"] as? String { WarningBox(text: "⚠ \(e)", bad: true).padding(.bottom, 10) }
        HStack(spacing: 10) {
            Text("Add @\(b["username"] as? String ?? "your bot") to your channels and chat as an admin (post, delete and ban/restrict rights), then send any message there so it shows up below.")
                .font(.system(size: 14)).foregroundStyle(Theme.soft)
            Button("Refresh") { Task { await load() } }.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 12).padding(.vertical, 7).background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(12).background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        SectionTitle(text: "Where it posts")
        chatPicker("📢 Updates channel: new Mango Signer versions & iPhone builds", $updatesChat, kinds: ["channel", "supergroup", "group"], none: "Off")
        chatPicker("📦 Apps channel: new and updated library apps", $appsChat, kinds: ["channel", "supergroup", "group"], none: "Off",
                   hint: "Only apps everyone can see. Hidden and testers-only apps are never posted. Turning it on starts from now, so it won't post your whole library.")
        chatPicker("💬 Chat it looks after", $groupChat, kinds: ["supergroup", "group"], none: "None")

        SectionTitle(text: "Announce")
        ListBox(fill: Theme.bg2) {
            ToggleRow(title: "New Mango Signer versions", sub: "When you publish a release on \(rServer)", isOn: $aServer)
            RowLine()
            ToggleRow(title: "New iPhone app builds", sub: "When a build is published on \(rIos)", isOn: $aIos)
            RowLine()
            ToggleRow(title: "Library apps", sub: "New apps and updates, a few a minute so Telegram doesn't slow it down", isOn: $aApps)
        }
        VStack(spacing: 10) {
            WebButton(title: "Send a test post to the updates channel") { post("test", "updates") }
            WebButton(title: "Post the newest Mango Signer version now") { post("server", "updates") }
            WebButton(title: "Post the newest iPhone build now") { post("ios", "updates") }
            WebButton(title: "Send a test post to the apps channel") { post("test", "apps") }
        }
        .padding(.top, 10)
        Field(label: "Name at the bottom of app posts") { TextField("🥭 Mango Signer", text: $brand).inputStyle() }.padding(.top, 12)
        Field(label: "Your Telegram username (for \"Need a certificate? DM me\" on posts)", hint: "Leave it empty to leave that line off.") { TextField("@MangoOwnah", text: $contact).plainInput().inputStyle() }
        Field(label: "Your Mango Signer link (for \"Sign with Mango Signer\" buttons)") { TextField("https://…", text: $publicUrl).plainInput().keyboardType(.URL).inputStyle() }

        SectionTitle(text: "Chat moderation")
        ListBox(fill: Theme.bg2) {
            ToggleRow(title: "Human check for newcomers", sub: "New members can't talk until they tap \"I'm human\" (removed after 5 minutes). Stops most spam bots.", isOn: $captcha)
            RowLine()
            ToggleRow(title: "Anti-spam", sub: "Deletes links to other groups from anyone, and links or forwards from new members", isOn: $antispam)
            RowLine()
            ToggleRow(title: "Flood control", sub: "6 messages in 8 seconds = muted for 10 minutes", isOn: $flood)
            RowLine()
            ToggleRow(title: "Hide \"joined\" and \"left\" messages", isOn: $cleanJoins)
        }
        Field(label: "New members can't send links for (hours)") { TextField("24", text: $newHours).keyboardType(.numberPad).inputStyle() }.padding(.top, 12)
        Field(label: "Banned words (one per line)", hint: "Single words only match whole words, so \"scam\" doesn't catch \"scampi\".") {
            TextField("scam", text: $words, axis: .vertical).lineLimit(3...8).plainInput().inputStyle()
        }
        Field(label: "Welcome message ({name} = their name)") { TextField("Welcome…", text: $welcome, axis: .vertical).lineLimit(2...6).inputStyle() }
        Field(label: "Rules (shown with /rules)") { TextField("1. Be nice…", text: $rules, axis: .vertical).lineLimit(3...10).inputStyle() }
        WebButton(title: busy ? "Saving…" : "Save", kind: .primary, big: true, disabled: busy) { Task { await save(quietly: false) } }

        SectionTitle(text: "Admin commands in the chat")
        Hint(text: "Reply to someone's message with: /warn [reason] (3 = muted for a day) · /unwarn · /mute [10m, 2h, 1d] · /unmute · /kick · /ban · /del · /pin. Anywhere: /lock (only admins can talk) · /unlock · /unban [user id] · /rules · /help.\(((b["locked"] as? [Any]) ?? []).isEmpty ? "" : " Your chat is locked right now.")")
        SectionTitle(text: "Advanced")
        Field(label: "Mango Signer repo") { TextField("owner/repo", text: $rServer).plainInput().inputStyle() }
        Field(label: "iPhone app repo") { TextField("owner/repo", text: $rIos).plainInput().inputStyle() }
        WebButton(title: "Disconnect bot", kind: .danger) { confirmOff = true }
    }

    var settingsBody: [String: Any] {
        var b = settingsCore
        if !publicUrl.trimmingCharacters(in: .whitespaces).isEmpty { b["publicUrl"] = publicUrl }
        return b
    }

    var settingsCore: [String: Any] {
        [
            "updatesChat": updatesChat, "appsChat": appsChat, "groupChat": groupChat,
            "announce": ["server": aServer, "ios": aIos, "apps": aApps],
            "repos": ["server": rServer, "ios": rIos],
            "mod": ["captcha": captcha, "antispam": antispam, "flood": flood, "cleanJoins": cleanJoins, "newHours": Int(newHours) ?? 0,
                    "bannedWords": words.split(whereSeparator: { $0 == "\n" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }],
            "welcome": welcome, "rules": rules, "brand": brand, "contact": contact,
        ]
    }

    func save(quietly: Bool) async {
        busy = true
        defer { busy = false }
        do { try await server.post("/api/tgbot", settingsBody, method: "PATCH"); if !quietly { router.say("Saved") } } catch { router.say(error.localizedDescription) }
    }

    func post(_ what: String, _ to: String) {
        Task {
            await save(quietly: true)
            do { try await server.post("/api/tgbot/post", ["what": what, "to": to]); router.say("Posted ✓") } catch { router.say(error.localizedDescription) }
        }
    }
}
