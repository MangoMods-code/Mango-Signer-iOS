import SwiftUI

/// An app's page, like the website's app sheet.
struct AppSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let appId: String
    @State private var shot: Int?
    @State private var openNotes: Set<Int> = []
    @State private var confirmDelete = false
    @State private var confirmMove = false

    var app: SApp? { server.app(appId) }

    /// One fact in the strip under the app's name.
    func fact(_ label: String, _ value: String, _ note: String?) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.round(18, .heavy)).foregroundStyle(Theme.soft).lineLimit(1)
            if let note { Text(note).font(.system(size: 10.5)).foregroundStyle(Theme.muted) }
        }
        .frame(minWidth: 62).padding(.horizontal, 14)
    }
    var factLine: some View { Rectangle().fill(Theme.line).frame(width: 1, height: 36) }

    @State private var original: String?
    @State private var favNow: Bool?
    @State private var voteNow: Int?
    func toggleOriginal(_ a: SApp) {
        if original != nil { original = nil; return }
        Task {
            if let d = try? await server.data("GET", "/api/apps/\(a.id)/original"),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let o = j["description"] as? String { original = o }
            else { router.say("Couldn't load the original") }
        }
    }

    var body: some View {
        if let a = app {
            content(a)
                .fullScreenCover(item: Binding(get: { shot.map { ShotPick(index: $0) } }, set: { shot = $0?.index })) { p in
                    ShotViewer(urls: server.screenshotURLs(a), start: p.index)
                }
                .confirmationDialog("Move \(a.name) to your GitHub storage?", isPresented: $confirmMove, titleVisibility: .visible) {
                    Button("Move to GitHub") { router.open(.moveToGithub(a.id)) }
                } message: { Text("It frees \(formatBytes(a.size)) on your server. Signing works the same.") }
                .confirmationDialog("Delete \(a.name) from the library?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { delete(a) }
                } message: {
                    Text("People who already installed it keep it.\(a.isSourceApp ? " \(a.sourceName ?? "Its source") won't add it back when it refreshes." : "")")
                }
        } else {
            SheetScroll { WebEmpty(icon: "questionmark.app", title: "Not in the library", text: "That app is no longer in the library.") }
        }
    }

    struct ShotPick: Identifiable { let index: Int; var id: Int { index } }

    @ViewBuilder
    func content(_ a: SApp) -> some View {
        let owner = server.isStaff
        let defaults = defaultsSummary(a.signDefaults ?? SignDefaults(), server)
        let pct: Int? = a.votes > 0 ? Int((Double(a.likes ?? 0) * 100 / Double(a.votes)).rounded()) : nil
        let versions = a.versions ?? []
        let shots = server.screenshotURLs(a)
        SheetScroll {
            HStack(alignment: .center, spacing: 16) {
                AppIconImage(app: a, size: 104).shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.name).font(Theme.round(23, .heavy)).tracking(-0.3).foregroundStyle(Theme.text).lineLimit(2).minimumScaleFactor(0.8)
                    Text(a.developer?.isEmpty == false ? a.developer! : (a.bundleId ?? "")).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
                    HStack(spacing: 8) {
                        Button { router.quickGet(a, server: server) } label: {
                            Text(a.hasUpdate ? "Update" : a.isStopped ? "Fix" : a.installed != nil ? "Get Again" : "Get")
                                .font(Theme.round(15)).foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 26).padding(.vertical, 8).frame(minWidth: 96)
                                .background(Theme.buttonFill).clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                                .shadow(color: Theme.accent2.opacity(0.3), radius: 10, y: 6)
                        }
                        .buttonStyle(PressStyle())
                        Button { router.open(.sign(a.id, presetId: nil)) } label: {
                            Text("Options").font(Theme.round(15, .semibold)).foregroundStyle(Theme.text)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(Theme.card2).clipShape(Capsule()).overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(PressStyle())
                    }
                    .padding(.top, 9)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 14)
            if !headBadges(a).isEmpty { BadgeFlow(badges: headBadges(a)).padding(.bottom, 10) }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    fact("Installs", "\(a.installCount ?? 0)", nil)
                    factLine
                    fact("Liked", pct.map { "\($0)%" } ?? "—", a.votes > 0 ? "\(a.votes) vote\(a.votes == 1 ? "" : "s")" : "no votes")
                    factLine
                    fact("Version", a.shownVersion.isEmpty ? "—" : a.shownVersion, nil)
                    factLine
                    fact("Size", formatBytes(a.size).isEmpty ? "—" : formatBytes(a.size), nil)
                    factLine
                    fact("Needs iOS", a.minOS?.isEmpty == false ? a.minOS! : "—", nil)
                }
                .padding(.vertical, 12)
            }
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            .padding(.bottom, 12)

            if a.missing == true {
                WarningBox(text: owner ? "This app was removed from \(a.sourceName ?? "its source"), so it's hidden from everyone. You can still try signing it if the link works, or delete it." : "This app is no longer available.", bad: true)
            }

            if a.hasUpdate { Hint(text: "Updates you to \(a.shownVersion).", center: true) }
            else if a.isStopped { Hint(text: "Signs it again so it opens.", center: true) }
            if let inst = a.installed { installedNote(a, inst) }
            if !defaults.isEmpty { Hint(text: "Comes set up with: \(defaults.joined(separator: " · "))", center: true).padding(.top, 8) }
            if server.seesTesterApps && !server.isOwner {
                LinkButton(title: "🐞 Report a bug in this app") { router.open(.reportBug(a.id)) }
            }

            if !shots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(shots.enumerated()), id: \.offset) { i, u in
                            Button { shot = i } label: { RemoteShot(url: u).frame(height: 360) }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            let fav = favNow ?? server.isFavorite(a)
            let was = a.myVote ?? 0
            let mine = voteNow ?? was
            let likes = (a.likes ?? 0) - (was == 1 ? 1 : 0) + (mine == 1 ? 1 : 0)
            let dislikes = (a.dislikes ?? 0) - (was == -1 ? 1 : 0) + (mine == -1 ? 1 : 0)
            HStack(spacing: 8) {
                // Changes show straight away; the server catches up in the background.
                vote(fav ? "♥" : "♡", count: nil, on: fav, color: Color(hex: 0xff5c8a)) {
                    let on = !fav
                    favNow = on
                    Haptics.tap()
                    do { try await server.post("/api/apps/\(a.id)/favorite", ["on": on]) } catch { favNow = !on; throw error }
                    return on ? "♥ Added to Favorites" : "Removed from Favorites"
                }
                Text("Do you like it?").font(.footnote).foregroundStyle(Theme.muted)
                Spacer()
                vote("👍", count: max(0, likes), on: mine > 0, color: Theme.leaf) {
                    let v = mine == 1 ? 0 : 1
                    voteNow = v; Haptics.tap()
                    do { try await server.post("/api/apps/\(a.id)/vote", ["value": v]) } catch { voteNow = mine; throw error }
                    return nil
                }
                vote("👎", count: max(0, dislikes), on: mine < 0, color: Theme.red) {
                    let v = mine == -1 ? 0 : -1
                    voteNow = v; Haptics.tap()
                    do { try await server.post("/api/apps/\(a.id)/vote", ["value": v]) } catch { voteNow = mine; throw error }
                    return nil
                }
            }
            .padding(.top, 16).padding(.bottom, 4)

            if let tags = a.tags, !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { t in
                        Button { router.libCat = "tag:\(t)"; router.libQuery = ""; router.go(.library) } label: {
                            Text("# \(t)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.soft)
                                .padding(.horizontal, 10).padding(.vertical, 5).background(Theme.bg2).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }
            if let d = a.description, !d.isEmpty {
                SectionTitle(text: "About")
                Text(original ?? d).font(.system(size: 15)).foregroundStyle(Theme.soft).textSelection(.enabled)
                if let lang = a.translatedFrom {
                    HStack(spacing: 4) {
                        Text("🌐 Translated from \(lang) ·").font(.caption).foregroundStyle(Theme.muted)
                        Button(original == nil ? "Show original" : "Show translation") { toggleOriginal(a) }
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.mango)
                    }
                    .padding(.top, 4)
                }
            }
            if let n = a.notes, !n.isEmpty {
                SectionTitle(text: "What's changed / notes")
                Text(cleanNotes(n)).font(.system(size: 15)).foregroundStyle(Theme.soft).textSelection(.enabled)
            } else if let first = versions.first, let n = first.notes, !n.isEmpty {
                SectionTitle(text: "What's new in \(first.version ?? "this version")")
                Text(cleanNotes(n)).font(.system(size: 15)).foregroundStyle(Theme.soft).textSelection(.enabled)
            }
            if versions.count > 1 {
                SectionTitle(text: "Other versions", count: versions.count - 1)
                ListBox(fill: Theme.bg2) {
                    ForEach(1..<versions.count, id: \.self) { i in
                        if i > 1 { RowLine() }
                        versionRow(a, versions[i], index: i)
                    }
                }
                Hint(text: "Older versions are handy if the newest one has a bug or needs a newer iOS.").padding(.top, 6)
            }

            SectionTitle(text: "Info")
            VStack(spacing: 0) {
                KVList(items: info(a, owner))
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if owner { ownerSection(a) }
        }
    }

    func headBadges(_ a: SApp) -> [Badge] {
        var b = Lib.badges(a, server)
        b.append(Badge(text: server.categoryLabel(a.categoryId), style: .mango))
        if a.featured == true { b.append(Badge(text: "★ Featured", style: .warn)) }
        if a.madeByMango { b.append(Badge(text: "🥭 Made by Mango", style: .warn)) }
        b.append(Badge(text: "v" + (a.shownVersion.isEmpty ? "?" : a.shownVersion)))
        let size = formatBytes(a.size)
        b.append(Badge(text: size.isEmpty ? "—" : size))
        return b
    }

    func info(_ a: SApp, _ owner: Bool) -> [(String, String)] {
        var v = a.shownVersion.isEmpty ? "—" : a.shownVersion
        if a.versionOverride == nil, let b = a.build, !b.isEmpty, b != a.version { v += " (\(b))" }
        if let p = a.previousVersion, p != a.shownVersion { v += "\nwas \(p)" }
        var items: [(String, String)] = [
            ("Version", v),
            ("Bundle ID", a.bundleId ?? "—"),
            ("Minimum iOS", a.minOS?.isEmpty == false ? a.minOS! : "—"),
            ("Size", formatBytes(a.size).isEmpty ? "—" : formatBytes(a.size)),
            ("Extensions", "\(a.extensions ?? 0)\(a.hasWatch == true ? " + Watch app" : "")"),
            (a.updatedAt != nil && a.updatedAt != a.addedAt ? "Updated" : "Added", ago(a.updatedAt ?? a.addedAt)),
        ]
        if a.isSourceApp { items.append((a.cloud == "telegram" ? "Telegram" : "Source", "\(a.cloud == "telegram" ? "✈️" : "☁") \(a.sourceName ?? "—")")) }
        if owner {
            let stored: String
            switch a.cloud {
            case "telegram": stored = "Telegram: \(a.sourceName ?? "a channel") (not stored here)"
            case "source": stored = "Linked from \(a.sourceName ?? "a source") (not stored here)"
            case "github": stored = "Your GitHub repo (not stored here)"
            case "link": stored = "Download link (not stored here)"
            default: stored = "This server"
            }
            items.append(("Stored on", stored))
            if let u = a.remoteUrl, !u.isEmpty { items.append(("Link", u)) }
        }
        return items
    }

    func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 18, weight: .bold)).monospacedDigit().foregroundStyle(Theme.text)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 4)
    }

    func vote(_ icon: String, count: Int?, on: Bool, color: Color, action: @escaping () async throws -> String?) -> some View {
        Button {
            Task {
                do { let m = try await action(); if let m { router.say(m) }; _ = await server.refresh() } catch { router.say(error.localizedDescription) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(icon).font(.system(size: count == nil ? 18 : 15)).foregroundStyle(on && count == nil ? color : Theme.text)
                if let count { Text("\(count)").font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(Theme.text) }
            }
            .padding(.horizontal, 13).padding(.vertical, 7).frame(minWidth: 44)
            .background(on ? color.opacity(0.15) : Theme.bg2).clipShape(Capsule())
            .overlay(Capsule().stroke(on ? color.opacity(0.5) : Theme.line))
        }
        .buttonStyle(PressStyle())
    }

    @ViewBuilder
    func installedNote(_ a: SApp, _ i: SInstalled) -> some View {
        VStack(spacing: 6) {
            if let st = i.stopped {
                WarningBox(text: "You installed \(i.version ?? "") \(ago(i.at)), but \(st == "revoked" ? "the certificate it was signed with was revoked" : "the certificate it was signed with has expired"), so it won't open anymore. Sign it again with a working certificate to fix it.", bad: true)
            } else {
                Hint(text: "You installed \(i.version ?? "") \(ago(i.at))\(a.hasUpdate ? " · \(a.shownVersion) is out" : "")", center: true)
            }
            HStack(spacing: 18) {
                if a.hasUpdate { Button("I already updated it") { myApp(a, "latest", "Marked as up to date") } }
                Button("Not on my phone anymore") { myApp(a, "remove", "Removed from your installed apps") }
            }
            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.mango)
        }
        .frame(maxWidth: .infinity).padding(.top, 8)
    }

    func myApp(_ a: SApp, _ action: String, _ msg: String) {
        Task {
            do { try await server.post("/api/my-apps/\(a.id)", ["action": action]); await server.refresh(); router.say(msg) } catch { router.say(error.localizedDescription) }
        }
    }

    func versionRow(_ a: SApp, _ v: SVersion, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(v.version ?? "Version \(index + 1)").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                    if let c = v.channel, !c.isEmpty, c != "stable" { Badge(text: c, style: c.lowercased().hasPrefix("beta") ? .blue : .plain, small: true) }
                }
                let sub = [v.date.map { String($0.prefix(10)) } ?? "", formatBytes(v.size)].filter { !$0.isEmpty }.joined(separator: " · ")
                if !sub.isEmpty { Text(sub).font(.system(size: 13)).foregroundStyle(Theme.muted) }
                if let n = v.notes, !n.isEmpty {
                    Text(cleanNotes(n)).font(.system(size: 13)).foregroundStyle(Theme.muted)
                        .lineLimit(openNotes.contains(index) ? nil : 3)
                        .onTapGesture { withAnimation { if openNotes.contains(index) { openNotes.remove(index) } else { openNotes.insert(index) } } }
                }
            }
            Spacer(minLength: 4)
            if server.isStaff, let mid = v.manualId {
                PillButton(title: "✕", danger: true) { removeVersion(a, mid) }
            }
            PillButton(title: "Get") { router.quickGet(a, server: server, versionIndex: v.vi ?? index) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    func removeVersion(_ a: SApp, _ mid: String) {
        Task {
            do { _ = try await server.data("DELETE", "/api/apps/\(a.id)/versions/\(mid)"); await server.refresh(); router.say("Version removed") } catch { router.say(error.localizedDescription) }
        }
    }

    @ViewBuilder
    func ownerSection(_ a: SApp) -> some View {
        ListBox(fill: Theme.bg2) {
            ToggleRow(title: "Show in App Library", sub: "Everyone you invite can sign and install it", isOn: Binding(get: { a.published != false }, set: { v in patch(a, ["published": v], v ? "Shown in App Library" : "Hidden from App Library") }))
            RowLine()
            ToggleRow(title: "Featured", sub: "Pinned to the top of the library", isOn: Binding(get: { a.featured == true }, set: { v in patch(a, ["featured": v], v ? "Featured ★" : "No longer featured") }))
            RowLine()
            ToggleRow(title: "Made by Mango", sub: "Shows in the 🥭 Made by Mango row at the top of everyone's library", isOn: Binding(get: { a.madeByMango }, set: { v in patch(a, ["madeByMango": v], v ? "Added to Made by Mango 🥭" : "Removed from Made by Mango") }))
            RowLine()
            ToggleRow(title: "Testers only", sub: "Only testers (and admins) can see it — a 🧪 For testers list shows at the top of their library",
                      isOn: Binding(get: { a.testersOnly }, set: { v in patch(a, ["testersOnly": v], v ? "Only testers can see it now 🧪" : "Not just for testers anymore") }))
        }
        .padding(.top, 14)
        VStack(spacing: 10) {
            WebButton(title: "Edit details, tags & sign settings") { router.open(.editApp(a.id)) }
            WebButton(title: "Screenshots (\((a.screenshots ?? []).count))") { router.open(.appShots(a.id)) }
            WebButton(title: "Add to collection") { router.open(.appCollections(a.id)) }
            if a.cloud == "source" {
                WebButton(title: "⬆ Add a newer version") { router.open(.appFile(a.id, newVersion: true)) }
                Hint(text: "For when you have a newer build than \(a.sourceName ?? "the source"). Its older versions stay available.", center: true).padding(.top, -6)
            }
            if a.isSourceApp {
                Hint(text: "Updates come in by themselves when \(a.sourceName ?? "the source") \(a.cloud == "telegram" ? "posts" : "adds") a new version.", center: true)
            } else {
                WebButton(title: "Update IPA (new version)") { router.open(.appFile(a.id, newVersion: false)) }
            }
            if a.cloud == nil && server.isOwner && server.state?.github?.connected == true {
                WebButton(title: "☁ Move to GitHub (frees \(formatBytes(a.size)))") { confirmMove = true }
            }
            WebButton(title: "Delete", kind: .danger) { confirmDelete = true }
        }
        .padding(.top, 14)
    }

    func patch(_ a: SApp, _ body: [String: Any], _ msg: String) {
        Task {
            do { try await server.post("/api/apps/\(a.id)", body, method: "PATCH"); await server.refresh(); router.say(msg) } catch { router.say(error.localizedDescription) }
        }
    }

    func delete(_ a: SApp) {
        Task {
            do { _ = try await server.data("DELETE", "/api/apps/\(a.id)"); router.close(); router.say("Deleted"); await server.refresh() } catch { router.say(error.localizedDescription) }
        }
    }
}

/// "JIT · More RAM · 120Hz" — what an app's default settings turn on.
@MainActor
func defaultsSummary(_ d: SignDefaults, _ server: Server) -> [String] {
    var bits: [String] = []
    for p in SignPresets.ent where d.entitlements.contains(where: { $0.key == p.key }) { bits.append(p.short) }
    for p in SignPresets.plist where d.plist.contains(where: { $0.key == p.key }) { bits.append(p.short) }
    let extraEnt = d.entitlements.filter { e in !SignPresets.ent.contains { $0.key == e.key } }.count
    let extraPlist = d.plist.filter { e in !SignPresets.plist.contains { $0.key == e.key } }.count
    if extraEnt > 0 { bits.append("\(extraEnt) custom entitlement\(extraEnt == 1 ? "" : "s")") }
    if extraPlist > 0 { bits.append("\(extraPlist) Info.plist change\(extraPlist == 1 ? "" : "s")") }
    if d.removeExtensions { bits.append("No extensions") }
    if d.removeWatch == true { bits.append("No Watch app") }
    if d.removeUISD { bits.append("No device limits") }
    if d.enableDocs { bits.append("Files app") }
    let tw = d.tweakIds.compactMap { id in server.state?.tweaks.first { $0.id == id }?.name }
    if !tw.isEmpty { bits.append("🧩 \(tw.joined(separator: ", "))") }
    return bits
}

struct RemoteShot: View {
    let url: URL
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if !failed {
                RoundedRectangle(cornerRadius: 14).fill(Theme.bg2).frame(width: 170).overlay(ProgressView().tint(Theme.muted))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: url) {
            image = await ImageCache.shared.image(url)
            failed = image == nil
        }
    }
}

/// Full-screen screenshots you can swipe through.
struct ShotViewer: View {
    @Environment(\.dismiss) private var dismiss
    let urls: [URL]
    let start: Int
    @State private var page = 0
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(Array(urls.enumerated()), id: \.offset) { i, u in
                    RemoteShot(url: u).padding(.vertical, 40).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(.white.opacity(0.15)).clipShape(Circle())
            }
            .padding(16)
        }
        .onAppear { page = start }
    }
}
