import SwiftUI

// MARK: - Filtering (same rules as the website)

@MainActor
enum Lib {
    static func matches(_ a: SApp, _ key: String, _ server: Server) -> Bool {
        switch key {
        case "all": return true
        case "installed": return a.installed != nil
        case "favorites": return server.isFavorite(a)
        case "updates": return a.hasUpdate
        case "new": return a.isNew || a.isUpdatedRecently
        case "featured": return a.featured == true
        case "none": return server.category(a.categoryId) == nil
        case "hidden": return a.published == false
        case "missing": return a.missing == true
        case "cloud:github": return a.cloud == "github"
        case "cloud:link": return a.cloud == "link"
        default:
            if key.hasPrefix("src:") { return a.isSourceApp && a.sourceName == String(key.dropFirst(4)) }
            if key.hasPrefix("tag:") { return (a.tags ?? []).contains(String(key.dropFirst(4))) }
            return a.categoryId == key
        }
    }

    static func count(_ key: String, _ server: Server) -> Int {
        if let n = server.countCache[key] { return n }
        let n = (server.state?.apps ?? []).filter { matches($0, key, server) }.count
        server.countCache[key] = n
        return n
    }

    struct Group { let title: String; let items: [(String, String)] }

    static func groups(_ server: Server) -> [Group] {
        let apps = server.state?.apps ?? []
        let tags = Array(Set(apps.flatMap { $0.tags ?? [] })).sorted()
        let srcs = Array(Set(apps.filter { $0.isSourceApp }.compactMap { $0.sourceName })).sorted()
        var g: [Group] = [
            Group(title: "Show", items: [("all", "📱 All"), ("favorites", "♥ Favorites"), ("installed", "✓ Installed"), ("updates", "⬆ Updates"), ("new", "🆕 New"), ("featured", "★ Featured")]),
            Group(title: "Categories", items: (server.state?.categories ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }.map { ($0.id, "\($0.emoji ?? "") \($0.name)") }),
            Group(title: "Sources", items: srcs.map { n in ("src:\(n)", "\(apps.contains { $0.cloud == "telegram" && $0.sourceName == n } ? "✈️" : "☁") \(n)") }),
            Group(title: "Tags", items: tags.map { ("tag:\($0)", "# \($0)") }),
        ]
        if server.isOwner {
            g.append(Group(title: "Owner", items: [("cloud:github", "☁ On GitHub"), ("cloud:link", "🔗 Links"), ("none", "Uncategorized"), ("hidden", "Hidden"), ("missing", "⚠ Removed")]))
        }
        return g.map { x in Group(title: x.title, items: x.items.filter { $0.0 == "all" || count($0.0, server) > 0 || (x.title == "Categories" && server.isOwner) }) }
            .filter { !$0.items.isEmpty }
    }

    static func label(_ key: String, _ server: Server) -> String {
        groups(server).flatMap { $0.items }.first { $0.0 == key }?.1 ?? key
    }

    static func filtered(_ server: Server, cat: String, query: String, sort: String) -> [SApp] {
        let cacheKey = "\(cat)|\(sort)|\(query)"
        if let hit = server.libCache[cacheKey] { return hit }
        if server.libCache.count > 40 { server.libCache.removeAll() }
        let result = filteredFresh(server, cat: cat, query: query, sort: sort)
        server.libCache[cacheKey] = result
        return result
    }

    private static func filteredFresh(_ server: Server, cat: String, query: String, sort: String) -> [SApp] {
        var apps = server.state?.apps ?? []
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            apps = apps.filter { a in
                ([a.name, a.bundleId, a.description, a.developer, a.notes, a.sourceName, a.shownVersion, server.categoryLabel(a.categoryId)] + (a.tags ?? []).map { Optional($0) })
                    .contains { ($0 ?? "").lowercased().contains(q) }
            }
        }
        apps = apps.filter { matches($0, cat, server) }
        func date(_ a: SApp) -> String { a.updatedAt ?? a.addedAt ?? "" }
        switch sort {
        case "name": apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case "newest": apps.sort { date($0) > date($1) }
        case "popular": apps.sort { ($0.installCount ?? 0, $0.score) > ($1.installCount ?? 0, $1.score) }
        case "rating": apps.sort { ($0.score, $0.installCount ?? 0) > ($1.score, $1.installCount ?? 0) }
        case "size": apps.sort { ($0.size ?? 0) > ($1.size ?? 0) }
        default: apps.sort { ($0.featured == true ? 1 : 0, $1.name) > ($1.featured == true ? 1 : 0, $0.name) }
        }
        return apps
    }

    static func badges(_ a: SApp, _ server: Server, compact: Bool = false) -> [Badge] {
        var b: [Badge] = []
        if a.hasUpdate { b.append(Badge(text: "⬆ Update", style: .mango, small: true)) }
        else if a.isStopped { b.append(Badge(text: "⚠ Won't open", style: .bad, small: true)) }
        else if a.installed != nil { b.append(Badge(text: "✓ Installed", style: .good, small: true)) }
        if a.isNew { b.append(Badge(text: "NEW", style: .new, small: true)) } else if a.isUpdatedRecently { b.append(Badge(text: "UPDATED", style: .new, small: true)) }
        if !compact {
            if server.isOwner && a.published == false { b.append(Badge(text: "Hidden", small: true)) }
            if a.missing == true { b.append(Badge(text: "Removed from source", style: .bad, small: true)) }
            if let c = cloudBadge(a, server) { b.append(Badge(text: c, style: .cloud, small: true)) }
        }
        return b
    }

    static func cloudBadge(_ a: SApp, _ server: Server) -> String? {
        switch a.cloud {
        case "source": return "☁ \(a.sourceName ?? "Source")"
        case "telegram": return "✈️ \(a.sourceName ?? "Telegram")"
        case "github": return server.isOwner ? "☁ GitHub" : nil
        case "link": return server.isOwner ? "🔗 Link" : nil
        default: return nil
        }
    }
}

// MARK: - The Library tab

struct LibraryTab: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    @FocusState private var searching: Bool

    var apps: [SApp] { server.state?.apps ?? [] }

    var body: some View {
        let cat = router.libCat
        VStack(alignment: .leading, spacing: 0) {
            if !server.isOwner && server.certs.isEmpty {
                Button { router.go(.certs) } label: { WarningBox(text: "Add your certificate in the Certificates tab to start signing →") }.buttonStyle(.plain)
            }
            if let c = server.defaultCert, c.check?.status == "revoked" {
                Button { router.go(.certs) } label: { WarningBox(text: "🚫 \(c.label) was revoked, so apps signed with it won't open. Add a new certificate →", bad: true) }.buttonStyle(.plain)
            }
            if !apps.isEmpty {
                searchBar
                chips(cat)
                tools
            }
            if ["installed", "updates"].contains(cat) && Lib.count("installed", server) > 0 {
                hintCard("Deleted something or updated it elsewhere?", button: "Fix the list") { router.open(.myApps) }
            }
            listBody(cat)
        }
    }

    var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted).font(.system(size: 16, weight: .semibold))
            TextField("Search \(apps.count) app\(apps.count == 1 ? "" : "s")", text: $router.libQuery)
                .plainInput().focused($searching).foregroundStyle(Theme.text).submitLabel(.search)
            if !router.libQuery.isEmpty {
                Button { router.libQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(searching ? Theme.mango.opacity(0.35) : .clear, lineWidth: 2))
        .padding(.bottom, 10)
    }

    func chips(_ cat: String) -> some View {
        let primary = [("all", "All"), ("favorites", "♥"), ("installed", "✓ Installed"), ("updates", "⬆ Updates"), ("featured", "★ Featured")]
            .filter { $0.0 == "all" || $0.0 == cat || Lib.count($0.0, server) > 0 }
        let extraOn = !["all", "favorites", "installed", "updates", "featured"].contains(cat)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(primary, id: \.0) { k, l in
                    chip(l, count: k == "all" ? nil : Lib.count(k, server), on: cat == k) { setCat(k) }
                }
                if extraOn {
                    chip("\(Lib.label(cat, server))", count: Lib.count(cat, server), on: true, suffix: " ✕") { setCat("all") }
                }
                Button { router.open(.filters) } label: {
                    Text("☰ Filters").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.mango)
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .overlay(Capsule().stroke(Theme.line))
                }
                .buttonStyle(PressStyle())
            }
            .padding(.vertical, 2)
        }
        .padding(.bottom, 10)
    }

    func chip(_ label: String, count: Int?, on: Bool, suffix: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(label).fontWeight(.semibold)
                if let count { Text("\(count)").fontWeight(.medium).foregroundStyle(on ? Theme.onAccent.opacity(0.65) : Theme.muted) }
                if !suffix.isEmpty { Text(suffix) }
            }
            .font(.system(size: 14))
            .foregroundStyle(on ? Theme.onAccent : Theme.text)
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(on ? Theme.mango : Theme.card)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(on ? Theme.mango : Theme.line))
            .shadow(color: on ? Theme.mango.opacity(0.25) : .clear, radius: 7, y: 4)
        }
        .buttonStyle(PressStyle())
    }

    func setCat(_ k: String) {
        withAnimation(.easeOut(duration: 0.15)) { router.libCat = k; router.libLimit = 40 }
    }

    var tools: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach([("smart", router.libCat == "all" ? "Recently updated" : "Featured first"), ("popular", "Popular"), ("rating", "Top rated"), ("name", "A–Z"), ("newest", "Newest"), ("size", "Biggest")], id: \.0) { k, l in
                    Button { router.libSort = k } label: { if router.libSort == k { Label(l, systemImage: "checkmark") } else { Text(l) } }
                }
            } label: {
                HStack {
                    Text("Sort: \(sortLabel)").foregroundStyle(Theme.text).font(.system(size: 15))
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
            }
            HStack(spacing: 0) {
                segButton("list.bullet", on: !router.libGrid) { router.libGrid = false }
                segButton("square.grid.3x3.fill", on: router.libGrid) { router.libGrid = true }
            }
            .padding(3).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .padding(.bottom, 4)
    }

    var sortLabel: String {
        switch router.libSort {
        case "popular": return "Popular"
        case "rating": return "Top rated"
        case "name": return "A–Z"
        case "newest": return "Newest"
        case "size": return "Biggest"
        default: return router.libCat == "all" ? "Recently updated" : "Featured first"
        }
    }

    func segButton(_ icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? Theme.onAccent : Theme.muted)
                .frame(width: 38, height: 32)
                .background(on ? Theme.mango : .clear).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    func hintCard(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(text).font(.system(size: 14)).foregroundStyle(Theme.soft).frame(maxWidth: .infinity, alignment: .leading)
            Button(button, action: action).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 12).padding(.vertical, 7).background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.vertical, 6)
    }

    @ViewBuilder
    func listBody(_ cat: String) -> some View {
        let list = Lib.filtered(server, cat: cat, query: router.libQuery, sort: router.libSort)
        if apps.isEmpty {
            WebEmpty(icon: "shippingbox", title: "No apps yet",
                     text: server.isOwner ? "Add an .ipa or a source on the website. Apps you add show up here for everyone you invite." : "The owner hasn't added any apps yet. Want something? Request it!",
                     button: server.isOwner ? nil : "Request an App") { router.open(.requestApp) }
        } else if list.isEmpty {
            WebEmpty(icon: "magnifyingglass", title: "Nothing found",
                     text: router.libQuery.isEmpty ? "Nothing here yet." : "No apps match “\(router.libQuery)”.",
                     button: server.isOwner ? nil : "Request an App") { router.open(.requestApp) }
        } else if cat == "all" && router.libQuery.isEmpty && router.libSort == "smart" {
            let updates = list.filter { $0.hasUpdate }
            if !updates.isEmpty {
                SectionTitle(text: "⬆ Updates for you", count: updates.count)
                MiniShelf(apps: updates, sub: { "→ \($0.shownVersion)" })
            }
            let featured = list.filter { $0.featured == true }
            if !featured.isEmpty {
                SectionTitle(text: "★ Featured")
                MiniShelf(apps: featured, sub: { _ in "" })
            }
            let recent = list.sorted { $0.sortDate > $1.sortDate }
            SectionTitle(text: "🕒 Recently updated", count: list.count)
            AppsBlock(apps: Array(recent.prefix(router.libLimit)), age: true)
            if recent.count > router.libLimit {
                WebButton(title: "Show more (\(recent.count - router.libLimit) left)") { router.libLimit += 40 }.padding(.top, 12)
            }
        } else {
            SectionTitle(text: "\(list.count) app\(list.count == 1 ? "" : "s")")
            AppsBlock(apps: Array(list.prefix(max(router.libLimit, 200))), age: false)
            if list.count > max(router.libLimit, 200) {
                WebButton(title: "Show more") { router.libLimit = max(router.libLimit, 200) + 200 }.padding(.top, 12)
            }
        }
    }
}

struct WebEmpty: View {
    let icon: String
    let title: String
    let text: String
    var button: String?
    var action: () -> Void = {}
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 46, weight: .light)).foregroundStyle(Theme.mango)
            Text(title).font(.title3.bold()).foregroundStyle(Theme.text)
            Text(text).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if let button { WebButton(title: button, kind: .primary, action: action).frame(maxWidth: 240).padding(.top, 6) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 20)
    }
}

/// A slim row of icons (Updates for you, Featured).
struct MiniShelf: View {
    @EnvironmentObject var router: Router
    let apps: [SApp]
    let sub: (SApp) -> String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(apps) { a in
                    Button { router.open(.app(a.id)) } label: {
                        VStack(spacing: 5) {
                            AppIconImage(app: a, size: 56)
                            Text(a.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            let s = sub(a)
                            if !s.isEmpty { Text(s).font(.system(size: 11)).foregroundStyle(Theme.mango).lineLimit(1) }
                        }
                        .frame(width: 64)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

/// List or grid, whichever the person picked.
struct AppsBlock: View {
    @EnvironmentObject var router: Router
    let apps: [SApp]
    var age = false
    var body: some View {
        if router.libGrid {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 10) {
                ForEach(apps) { AppTile(app: $0) }
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { i, a in
                    if i > 0 { RowLine() }
                    AppRowView(app: a, age: age)
                }
            }
            .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct AppRowView: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let app: SApp
    var age = false

    var body: some View {
        let a = app
        let rating = a.votes > 0 ? "👍 \(Int((Double(a.likes ?? 0) * 100 / Double(a.votes)).rounded()))%" : ""
        let when = age ? "\(a.updatedAt != nil && a.updatedAt != a.addedAt ? "Updated" : "Added") \(ago(a.updatedAt ?? a.addedAt))" : ""
        let sub2 = [when, a.developer ?? "", formatBytes(a.size), (a.installCount ?? 0) > 0 ? "🔥 \(a.installCount!)" : "", rating].filter { !$0.isEmpty }.joined(separator: " · ")
        let desc = (a.description ?? "").split(separator: "\n").first.map(String.init) ?? ""
        let badges = Lib.badges(a, server)
        HStack(spacing: 12) {
            AppIconImage(app: a)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(a.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    if a.featured == true { Text("★").font(.caption).foregroundStyle(Theme.mango2) }
                }
                Text("\(a.shownVersion.isEmpty ? "—" : a.shownVersion) · \(desc.isEmpty ? (a.bundleId ?? "") : desc)")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                if !sub2.isEmpty { Text(sub2).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1) }
                if !badges.isEmpty { BadgeFlow(badges: badges).padding(.top, 4) }
            }
            Spacer(minLength: 4)
            PillButton(title: a.getLabel) { router.quickGet(a, server: server) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { router.open(.app(a.id)) }
    }
}

struct AppTile: View {
    @EnvironmentObject var router: Router
    let app: SApp
    var body: some View {
        Button { router.open(.app(app.id)) } label: {
            VStack(spacing: 4) {
                AppIconImage(app: app, size: 68)
                    .overlay(alignment: .topTrailing) {
                        if app.hasUpdate { dot("⬆", Theme.mango, Theme.onAccent) }
                        else if app.installed != nil { dot("✓", Theme.leaf, Color(hex: 0x0f2a0f)) }
                        else if app.isNew { dot("NEW", Theme.mango, Theme.onAccent) }
                    }
                Text(app.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(app.shownVersion).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .padding(.vertical, 6).padding(.horizontal, 2)
        }
        .buttonStyle(PressStyle())
    }
    func dot(_ t: String, _ bg: Color, _ fg: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(fg)
            .padding(.horizontal, 6).padding(.vertical, 2).background(bg).clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.bg, lineWidth: 2))
            .offset(x: 7, y: -5)
    }
}

// MARK: - Filters, requests, "your installed apps"

struct FilterSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    var body: some View {
        SheetScroll {
            SheetTitle(text: "Filter")
            ForEach(Lib.groups(server), id: \.title) { g in
                SectionTitle(text: g.title)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(g.items, id: \.0) { k, l in
                        let n = Lib.count(k, server)
                        Button {
                            router.libCat = k; router.libLimit = 40; router.close()
                        } label: {
                            HStack {
                                Text(l).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text("\(n)").font(.system(size: 13, weight: .bold)).opacity(0.7)
                            }
                            .foregroundStyle(router.libCat == k ? Theme.onAccent : Theme.text)
                            .padding(.horizontal, 12).padding(.vertical, 11)
                            .background(router.libCat == k ? Theme.mango : Theme.bg2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .opacity(n == 0 ? 0.5 : 1)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            if !server.isOwner {
                WebButton(title: "+ Request an App") { router.open(.requestApp) }.padding(.top, 16)
            }
        }
    }
}

struct RequestAppSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    @State private var name = ""
    @State private var link = ""
    @State private var note = ""
    @State private var busy = false
    var body: some View {
        SheetScroll {
            SheetTitle(text: "Request an App")
            Hint(text: "Ask for an app to be added to the library. You'll see the answer in \(server.isOwner ? "Users" : "Account") › Requests.").padding(.bottom, 12)
            Field(label: "App name") { TextField("e.g. Delta Emulator", text: $name).inputStyle() }
            Field(label: "Link (optional)") { TextField("Where to find it", text: $link).plainInput().keyboardType(.URL).inputStyle() }
            Field(label: "Anything else? (optional)") { TextField("Version, tweaks you want, why…", text: $note, axis: .vertical).lineLimit(3...6).inputStyle() }
            WebButton(title: busy ? "Sending…" : "Send Request", kind: .primary, big: true, disabled: busy) {
                busy = true
                Task {
                    defer { busy = false }
                    do {
                        try await server.post("/api/requests", ["name": name, "link": link, "note": note])
                        await server.refresh(); router.close(); router.say("Request sent 🙌")
                    } catch { router.say(error.localizedDescription) }
                }
            }
        }
    }
}

struct MyAppsSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    var mine: [SApp] {
        (server.state?.apps ?? []).filter { $0.installed != nil }.sorted {
            ($0.hasUpdate ? 1 : 0, $0.isStopped ? 1 : 0, $0.installed?.at ?? "") > ($1.hasUpdate ? 1 : 0, $1.isStopped ? 1 : 0, $1.installed?.at ?? "")
        }
    }
    var body: some View {
        SheetScroll {
            SheetTitle(text: "Your installed apps")
            Hint(text: "iPhones don't let apps see your home screen, so this is every app you installed through Mango. Deleted one, or updated it somewhere else? Fix it here and Mango stops bugging you about it.").padding(.bottom, 12)
            let stopped = mine.filter { $0.isStopped }.count
            if stopped > 0 {
                WebButton(title: "Forget \(stopped) app\(stopped == 1 ? "" : "s") that won't open anymore") {
                    Task {
                        do {
                            let r = try await server.post("/api/my-apps/clean")
                            await server.refresh()
                            let n = (r["removed"] as? Int) ?? stopped
                            router.say("Forgot \(n) app\(n == 1 ? "" : "s")")
                        } catch { router.say(error.localizedDescription) }
                    }
                }
                .padding(.bottom, 10)
            }
            if mine.isEmpty {
                Text("Nothing yet. Apps you install from Mango show up here.").foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(30)
            } else {
                ListBox(fill: Theme.bg2) {
                    ForEach(Array(mine.enumerated()), id: \.element.id) { i, a in
                        if i > 0 { RowLine() }
                        HStack(spacing: 12) {
                            AppIconImage(app: a)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                                Group {
                                    if a.hasUpdate { Text("\(a.installed?.version ?? "?") · \(ago(a.installed?.at)) · ") + Text("\(a.shownVersion) is out").bold().foregroundColor(Theme.mango) }
                                    else if a.isStopped { Text("\(a.installed?.version ?? "?") · \(ago(a.installed?.at)) · ") + Text("won't open").bold().foregroundColor(Theme.red) }
                                    else { Text("\(a.installed?.version ?? "?") · \(ago(a.installed?.at)) · up to date") }
                                }
                                .font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if a.hasUpdate { smallButton("✓") { act(a, "latest") } }
                            smallButton("✕") { act(a, "remove") }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                }
                Hint(text: "✓ = I already have the newest version · ✕ = not on my phone anymore").padding(.top, 8)
            }
        }
    }
    func smallButton(_ t: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                .frame(minWidth: 36, minHeight: 34).background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PressStyle())
    }
    func act(_ a: SApp, _ action: String) {
        Task {
            do { try await server.post("/api/my-apps/\(a.id)", ["action": action]); await server.refresh() } catch { router.say(error.localizedDescription) }
        }
    }
}
