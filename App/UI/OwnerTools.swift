import SwiftUI
import Charts
import UniformTypeIdentifiers

// Owner and admin tools that used to open the website: categories & collections, tweaks, stats,
// duplicates, adding apps, the announcement, messages and backups.

// MARK: - Categories & collections

struct CategoriesSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    @State private var newName = ""
    @State private var newEmoji = "📁"
    @State private var editing: SCategory?
    @State private var editName = ""
    @State private var editEmoji = ""
    @State private var deleting: SCategory?
    @State private var rules: [SCatRule] = []
    @State private var rulesLoaded = false

    var cats: [SCategory] { (server.state?.categories ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) } }

    func count(_ c: SCategory) -> Int { (server.state?.apps ?? []).filter { $0.categoryId == c.id }.count }

    var body: some View {
        let list = cats
        let collections = server.state?.collections ?? []
        SheetScroll {
            SheetTitle(text: "Categories & collections")
            SectionTitle(text: "Categories", count: list.count)
            ListBox(fill: Theme.bg2) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { RowLine() }
                    HStack(spacing: 10) {
                        Text(c.emoji ?? "📁").font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                            Text("\(count(c)) app\(count(c) == 1 ? "" : "s")").font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button { move(i, -1) } label: { Image(systemName: "chevron.up") }.disabled(i == 0).foregroundStyle(i == 0 ? Theme.muted.opacity(0.4) : Theme.muted)
                        Button { move(i, 1) } label: { Image(systemName: "chevron.down") }.disabled(i == list.count - 1).foregroundStyle(i == list.count - 1 ? Theme.muted.opacity(0.4) : Theme.muted)
                        Menu {
                            Button { editing = c; editName = c.name; editEmoji = c.emoji ?? "" } label: { Label("Rename", systemImage: "pencil") }
                            Button { router.libCat = c.id; router.libQuery = ""; router.go(.library) } label: { Label("See its apps", systemImage: "square.grid.2x2") }
                            Button(role: .destructive) { deleting = c } label: { Label("Delete", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Theme.mango) }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
            HStack(spacing: 8) {
                TextField("📁", text: $newEmoji).frame(width: 44).multilineTextAlignment(.center).inputStyle()
                TextField("New category", text: $newName).inputStyle()
                PillButton(title: "Add") { add() }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 10)

            if server.isOwner {
                SectionTitle(text: "Sorting rules")
                Hint(text: "Apps whose name has one of these words go in that category when they're added, and when you run Auto-sort. Separate words with commas.").padding(.bottom, 8)
                ForEach(rules.indices, id: \.self) { i in
                    VStack(spacing: 8) {
                        TextField("e.g. emulator, gba, nes", text: $rules[i].words).plainInput().inputStyle()
                        HStack {
                            SelectBox(selection: Binding(get: { rules[i].categoryId ?? "" }, set: { rules[i].categoryId = $0 }),
                                      options: [("", "Pick a category")] + list.map { ($0.id, "\($0.emoji ?? "") \($0.name)") })
                            Button { rules.remove(at: i) } label: { Image(systemName: "trash").foregroundStyle(Theme.red) }.buttonStyle(.plain).padding(.leading, 6)
                        }
                    }
                    .padding(12).background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)).padding(.bottom, 8)
                }
                HStack(spacing: 10) {
                    WebButton(title: "＋ Add a rule") { rules.append(SCatRule(words: "", categoryId: list.first?.id)) }
                    WebButton(title: "Save rules", kind: .primary) { saveRules() }
                }
            }

            SectionTitle(text: "Collections", count: collections.count)
            Hint(text: "Hand-picked lists shown at the top of the library, like \"Best emulators\".").padding(.bottom, 8)
            ListBox(fill: Theme.bg2) {
                ForEach(Array(collections.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { RowLine() }
                    LinkRow(title: "\(c.emoji ?? "📦") \(c.name)", value: "\(c.appIds.count) app\(c.appIds.count == 1 ? "" : "s")") { router.open(.editCollection(c.id)) }
                }
                if !collections.isEmpty { RowLine() }
                LinkRow(title: "＋ New collection") { router.open(.editCollection(nil)) }
            }
        }
        .onAppear { if !rulesLoaded { rules = server.state?.settings?.catRules ?? []; rulesLoaded = true } }
        .alert("Rename category", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Emoji", text: $editEmoji)
            TextField("Name", text: $editName)
            Button("Save") { if let c = editing { rename(c) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let c = deleting { remove(c) } }
        } message: { Text("Its apps become uncategorized. They aren't deleted.") }
    }

    func act(_ msg: String?, _ work: @escaping () async throws -> Void) {
        Task {
            do { try await work(); await server.refresh(); if let msg { router.say(msg) } } catch { router.say(error.localizedDescription) }
        }
    }
    func add() {
        let n = newName.trimmingCharacters(in: .whitespaces), e = newEmoji
        act("Added \(n)") { _ = try await server.post("/api/categories", ["name": n, "emoji": e]); newName = "" }
    }
    func rename(_ c: SCategory) {
        let n = editName, e = editEmoji
        act("Saved") { _ = try await server.post("/api/categories/\(c.id)", ["name": n, "emoji": e], method: "PATCH") }
    }
    func remove(_ c: SCategory) { act("Deleted \(c.name)") { _ = try await server.data("DELETE", "/api/categories/\(c.id)") } }
    func move(_ i: Int, _ d: Int) {
        var ids = cats.map { $0.id }
        let j = i + d
        guard ids.indices.contains(j) else { return }
        ids.swapAt(i, j)
        act(nil) { _ = try await server.post("/api/categories/order", ["ids": ids]) }
    }
    func saveRules() {
        let body = rules.filter { !$0.words.trimmingCharacters(in: .whitespaces).isEmpty && $0.categoryId != nil }.map { ["words": $0.words, "categoryId": $0.categoryId ?? ""] }
        act("Rules saved") { _ = try await server.post("/api/settings", ["catRules": body], method: "PATCH") }
    }
}

/// Make or change a collection (nil = new).
struct CollectionEditSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let collectionId: String?
    @State private var name = ""
    @State private var emoji = "📦"
    @State private var about = ""
    @State private var picked: [String] = []
    @State private var query = ""
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        let apps = server.state?.apps ?? []
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let results = q.isEmpty ? [] : apps.filter { $0.name.lowercased().contains(q) && !picked.contains($0.id) }.prefix(20)
        SheetScroll {
            SheetTitle(text: collectionId == nil ? "New collection" : "Edit collection")
            HStack(spacing: 8) {
                TextField("📦", text: $emoji).frame(width: 44).multilineTextAlignment(.center).inputStyle()
                TextField("Name, e.g. Best emulators", text: $name).inputStyle()
            }
            .padding(.bottom, 10)
            Field(label: "Description (optional)") { TextField("What's in it", text: $about, axis: .vertical).lineLimit(1...4).inputStyle() }
            SectionTitle(text: "Apps", count: picked.count)
            if !picked.isEmpty {
                ListBox(fill: Theme.bg2) {
                    ForEach(Array(picked.enumerated()), id: \.element) { i, aid in
                        if i > 0 { RowLine() }
                        HStack(spacing: 10) {
                            if let a = server.app(aid) { AppIconImage(app: a, size: 36) }
                            Text(server.app(aid)?.name ?? "Deleted app").foregroundStyle(Theme.text).lineLimit(1)
                            Spacer()
                            Button { if i > 0 { picked.swapAt(i, i - 1) } } label: { Image(systemName: "chevron.up") }.foregroundStyle(Theme.muted).disabled(i == 0)
                            Button { picked.remove(at: i) } label: { Image(systemName: "minus.circle.fill") }.foregroundStyle(Theme.red)
                        }
                        .buttonStyle(.plain).padding(.horizontal, 14).padding(.vertical, 8)
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField(picked.count >= 30 ? "30 apps is the most" : "Search the library to add apps", text: $query).plainInput()
            }
            .inputStyle().padding(.top, 10).disabled(picked.count >= 30)
            if !results.isEmpty {
                ListBox(fill: Theme.bg2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, a in
                        if i > 0 { RowLine() }
                        Button { picked.append(a.id); query = "" } label: {
                            HStack(spacing: 10) {
                                AppIconImage(app: a, size: 36)
                                Text(a.name).foregroundStyle(Theme.text).lineLimit(1)
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.mango)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
            }
            VStack(spacing: 10) {
                WebButton(title: "Save", kind: .primary, big: true, disabled: name.trimmingCharacters(in: .whitespaces).isEmpty) { save() }
                if collectionId != nil { WebButton(title: "Delete collection", kind: .danger) { confirmDelete = true } }
                WebButton(title: "Back") { router.open(.categories) }
            }
            .padding(.top, 14)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let c = server.state?.collections.first(where: { $0.id == collectionId }) {
                name = c.name; emoji = c.emoji ?? "📦"; about = c.description ?? ""; picked = c.appIds
            }
        }
        .confirmationDialog("Delete \(name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    do { _ = try await server.data("DELETE", "/api/collections/\(collectionId ?? "")"); await server.refresh(); router.say("Deleted"); router.open(.categories) } catch { router.say(error.localizedDescription) }
                }
            }
        } message: { Text("The apps in it stay in the library.") }
    }

    func save() {
        let body: [String: Any] = ["name": name, "emoji": emoji, "description": about, "appIds": picked]
        Task {
            do {
                if let cid = collectionId { _ = try await server.post("/api/collections/\(cid)", body, method: "PATCH") } else { _ = try await server.post("/api/collections", body) }
                await server.refresh(); router.say("Saved"); router.open(.categories)
            } catch { router.say(error.localizedDescription) }
        }
    }
}

// MARK: - Tweaks

struct TweaksSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    @State private var picking = false
    @State private var uploading: String?
    @State private var progress: Double = 0
    @State private var deleting: STweak?

    var body: some View {
        let tweaks = server.state?.tweaks ?? []
        SheetScroll {
            SheetTitle(text: "🧩 Tweaks")
            Hint(text: "Tweaks here can be picked when signing (and set as an app's default). Jailbreak .deb files work: Mango pulls the tweak out and adds CydiaSubstrate when it needs it.").padding(.bottom, 10)
            Button { picking = true } label: {
                FilePickButtonLabel(icon: "plus", title: uploading == nil ? "Add a .deb or .dylib" : "Adding \(uploading!)…", sub: uploading == nil ? "From Files" : "\(Int(progress * 100))%")
            }
            .buttonStyle(.plain).disabled(uploading != nil)
            if !tweaks.isEmpty {
                SectionTitle(text: "Library", count: tweaks.count)
                ListBox(fill: Theme.bg2) {
                    ForEach(Array(tweaks.enumerated()), id: \.element.id) { i, t in
                        if i > 0 { RowLine() }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(t.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                                if let v = t.version, !v.isEmpty { Text(v).font(.caption).foregroundStyle(Theme.muted) }
                                if !t.published { Badge(text: "Hidden", small: true) }
                                Spacer()
                                Menu {
                                    Button { toggle(t) } label: { Label(t.published ? "Hide from everyone" : "Show to everyone", systemImage: t.published ? "eye.slash" : "eye") }
                                    Button(role: .destructive) { deleting = t } label: { Label("Delete", systemImage: "trash") }
                                } label: { Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Theme.mango) }
                            }
                            if let a = t.author, !a.isEmpty { Text("by \(a)").font(.caption).foregroundStyle(Theme.muted) }
                            if let d = t.description, !d.isEmpty { Text(d).font(.caption).foregroundStyle(Theme.soft).lineLimit(3) }
                            Text(t.files.map { $0.name + ($0.needsSubstrate ? " · needs Substrate" : "") }.joined(separator: ", ")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                            ForEach(t.warnings, id: \.self) { w in Text("⚠️ \(w)").font(.caption).foregroundStyle(Color(hex: 0xffcf4a)) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data], allowsMultipleSelection: false) { r in
            guard case .success(let urls) = r, let u = urls.first else { return }
            guard ["deb", "dylib"].contains(u.pathExtension.lowercased()) else { router.say("Pick a .deb or .dylib file"); return }
            upload(u)
        }
        .confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let t = deleting { Task { do { _ = try await server.data("DELETE", "/api/tweaks/\(t.id)"); await server.refresh(); router.say("Deleted") } catch { router.say(error.localizedDescription) } } }
            }
        } message: { Text("It's also taken off any app or preset that uses it by default.") }
    }

    func upload(_ u: URL) {
        uploading = u.lastPathComponent; progress = 0
        Task {
            defer { uploading = nil }
            do {
                let uid = try await server.uploadLarge(u) { p, _ in progress = p }
                let r = try await server.post("/api/tweaks", ["uploadId": uid, "fileName": u.lastPathComponent])
                await server.refresh()
                router.say("Added \(((r["tweak"] as? [String: Any])?["name"] as? String) ?? "tweak")")
            } catch { router.say(error.localizedDescription) }
        }
    }
    func toggle(_ t: STweak) {
        Task {
            do { _ = try await server.post("/api/tweaks/\(t.id)", ["published": !t.published], method: "PATCH"); await server.refresh(); router.say(t.published ? "Hidden" : "Shown to everyone") } catch { router.say(error.localizedDescription) }
        }
    }
}

// MARK: - Stats

struct StatsSheet: View {
    @EnvironmentObject var server: Server
    struct DayPoint: Identifiable { var id: String { "\(kind)-\(day)" }; let day: Date; let kind: String; let n: Int }
    struct Top: Identifiable { var id: String { name }; let name: String; let count: Int }
    struct Line: Identifiable { let id = UUID(); let at: String; let kind: String; let text: String }
    @State private var totals: [String: Int] = [:]
    @State private var points: [DayPoint] = []
    @State private var top: [Top] = []
    @State private var activity: [Line] = []
    @State private var loaded = false
    @State private var failed: String?

    var body: some View {
        SheetScroll {
            SheetTitle(text: "📊 Stats & activity")
            if let failed { WarningBox(text: failed, bad: true) }
            if !loaded && failed == nil { ProgressView().tint(Theme.mango).frame(maxWidth: .infinity).padding(.top, 30) }
            if loaded {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    tile("Users", totals["users"], "\(totals["activeUsers7d"] ?? 0) active this week")
                    tile("Installs", totals["installs30d"], "last 30 days")
                    tile("Signs", totals["signs30d"], "last 30 days")
                    tile("Apps", totals["apps"], "\(totals["cloudApps"] ?? 0) in the cloud")
                    tile("Certificates", totals["certs"], "all accounts")
                    tile("Tweaks", totals["tweaks"], "in the library")
                }
                SectionTitle(text: "Last 30 days")
                Chart(points) { p in
                    LineMark(x: .value("Day", p.day), y: .value("Count", p.n))
                        .foregroundStyle(by: .value("What", p.kind))
                        .interpolationMethod(.monotone)
                }
                .chartForegroundStyleScale(["Installs": Theme.mango, "Signs": Theme.blue, "New users": Theme.leaf])
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .frame(height: 200)
                .padding(14).background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                if !top.isEmpty {
                    SectionTitle(text: "Most installed (30 days)")
                    ListBox(fill: Theme.bg2) {
                        ForEach(Array(top.enumerated()), id: \.element.id) { i, t in
                            if i > 0 { RowLine() }
                            ValueRow(title: "\(i + 1). \(t.name)", value: "\(t.count)")
                        }
                    }
                }
                if !activity.isEmpty {
                    SectionTitle(text: "Recent activity")
                    ListBox(fill: Theme.bg2) {
                        ForEach(Array(activity.prefix(40).enumerated()), id: \.element.id) { i, l in
                            if i > 0 { RowLine() }
                            HStack(alignment: .top, spacing: 10) {
                                Text(["install": "📲", "sign": "✍️", "user": "👋", "request": "🙋"][l.kind] ?? "•")
                                Text(l.text).font(.subheadline).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
                                Text(ago(l.at)).font(.caption).foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    func tile(_ title: String, _ n: Int?, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n ?? 0)").font(.title2.bold()).foregroundStyle(Theme.text)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.soft)
            Text(sub).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    func load() async {
        do {
            let d = try await server.data("GET", "/api/stats")
            guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw MangoError("Couldn't read the stats") }
            totals = ((j["totals"] as? [String: Any]) ?? [:]).compactMapValues { ($0 as? NSNumber)?.intValue }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")
            let days = ((j["days"] as? [String]) ?? []).map { f.date(from: $0) ?? Date() }
            var pts: [DayPoint] = []
            for (key, label) in [("installs", "Installs"), ("signs", "Signs"), ("signups", "New users")] {
                let vals = ((j[key] as? [NSNumber]) ?? []).map { $0.intValue }
                for (i, v) in vals.enumerated() where i < days.count { pts.append(DayPoint(day: days[i], kind: label, n: v)) }
            }
            points = pts
            top = ((j["topApps"] as? [[String: Any]]) ?? []).map { Top(name: $0["name"] as? String ?? "App", count: ($0["count"] as? NSNumber)?.intValue ?? 0) }
            activity = ((j["activity"] as? [[String: Any]]) ?? []).map { Line(at: $0["at"] as? String ?? "", kind: $0["kind"] as? String ?? "", text: $0["text"] as? String ?? "") }
            loaded = true
        } catch { failed = error.localizedDescription }
    }
}

// MARK: - Duplicates

struct DuplicatesSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    @State private var prefer = "newest"
    @State private var picks: [String: String] = [:]
    @State private var busy = false

    var groups: [[SApp]] {
        var by: [String: [SApp]] = [:]
        for a in server.state?.apps ?? [] {
            guard let b = a.bundleId?.lowercased(), !b.isEmpty, a.missing != true else { continue }
            by[b, default: []].append(a)
        }
        return by.values.filter { $0.count > 1 }.sorted { $0[0].name.localizedCaseInsensitiveCompare($1[0].name) == .orderedAscending }
    }

    func keeper(_ g: [SApp]) -> SApp {
        if let p = picks[g[0].bundleId?.lowercased() ?? ""], let a = g.first(where: { $0.id == p }) { return a }
        let pref: [SApp] = prefer == "mine" ? g.filter { !$0.isSourceApp } : prefer == "newest" ? [] : g.filter { $0.isSourceApp && $0.sourceName == prefer }
        let pool = pref.isEmpty ? g : pref
        return pool.sorted { x, y in
            let c = versionCompare(x.version ?? "", y.version ?? "")
            if c != 0 { return c > 0 }
            if (x.installCount ?? 0) != (y.installCount ?? 0) { return (x.installCount ?? 0) > (y.installCount ?? 0) }
            return (x.addedAt ?? "") < (y.addedAt ?? "")
        }[0]
    }

    var body: some View {
        let gs = groups
        let extra = gs.reduce(0) { $0 + $1.count - 1 }
        let places = Array(Set(gs.flatMap { $0 }.compactMap { $0.isSourceApp ? $0.sourceName : nil })).sorted()
        SheetScroll {
            SheetTitle(text: "🔁 Duplicates")
            Hint(text: "Apps that share a bundle ID — usually the same app added twice, or once from a source and once by you.").padding(.bottom, 10)
            if gs.isEmpty {
                WebEmpty(icon: "checkmark.seal", title: "No duplicates", text: "Every app in the library is only there once.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(gs.count) app\(gs.count == 1 ? " has" : "s have") copies · \(extra) extra cop\(extra == 1 ? "y" : "ies")").foregroundStyle(Theme.text)
                    Field(label: "For apps you haven't picked, keep", hint: "Tap Keep on any copy below to choose it yourself. Deleted copies won't come back when their channel or source refreshes.") {
                        SelectBox(selection: $prefer, options: [("newest", "The newest version"), ("mine", "The one I added myself")] + places.map { ($0, "The one from \($0)") })
                    }
                    WebButton(title: busy ? "Cleaning up…" : "Clean up all — delete \(extra) extra cop\(extra == 1 ? "y" : "ies")", kind: .primary, disabled: busy) { clean(nil) }
                }
                .padding(14).background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                ForEach(gs, id: \.first!.id) { g in
                    let keep = keeper(g)
                    SectionTitle(text: g[0].name, count: g.count)
                    ListBox(fill: Theme.bg2) {
                        ForEach(Array(g.enumerated()), id: \.element.id) { i, a in
                            if i > 0 { RowLine() }
                            HStack(spacing: 10) {
                                AppIconImage(app: a, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(a.version ?? "—") · \(a.isSourceApp ? (a.sourceName ?? "Source") : a.cloud == "github" ? "Your GitHub" : "Added by you")")
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                                    Text("\(a.installCount ?? 0) installs · added \(ago(a.addedAt))").font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                if a.id == keep.id { Badge(text: "Keeping", style: .good, small: true) } else {
                                    PillButton(title: "Keep") { picks[a.bundleId?.lowercased() ?? ""] = a.id }
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                        }
                    }
                    LinkButton(title: "Clean up just this app") { clean(g[0].bundleId) }
                }
            }
        }
    }

    func clean(_ only: String?) {
        busy = true
        var body: [String: Any] = ["prefer": prefer, "picks": picks]
        if let only { body["only"] = only }
        Task {
            defer { busy = false }
            do {
                let r = try await server.post("/api/apps/dedupe", body)
                await server.refresh()
                let n = (r["deleted"] as? NSNumber)?.intValue ?? 0
                router.say(n > 0 ? "Deleted \(n) extra cop\(n == 1 ? "y" : "ies")" : "Nothing to clean up")
            } catch { router.say(error.localizedDescription) }
        }
    }
}

/// Compares version numbers like 1.10.2 vs 1.9 (bigger number wins).
func versionCompare(_ a: String, _ b: String) -> Int {
    let pa = a.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    let pb = b.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    for i in 0..<max(pa.count, pb.count) {
        let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
        if x != y { return x < y ? -1 : 1 }
    }
    return 0
}

// MARK: - Add an app to the library

struct AddAppSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    @State private var picking = false
    @State private var link = ""
    @State private var linkOnly = true
    @State private var status: String?
    @State private var progress: Double?

    var busy: Bool { status != nil }

    var body: some View {
        SheetScroll {
            SheetTitle(text: "Add an app")
            Button { picking = true } label: {
                FilePickButtonLabel(icon: "doc.badge.plus", title: "Upload an .ipa", sub: server.state?.github?.connected == true ? "From Files. It's saved to your GitHub storage." : "From Files")
            }
            .buttonStyle(.plain).disabled(busy)
            SectionTitle(text: "Or from a link")
            Field(label: "Download link", hint: "A direct .ipa link. GitHub release links work too.") {
                HStack {
                    TextField("https://…/app.ipa", text: $link).plainInput().keyboardType(.URL)
                    Button { link = UIPasteboard.general.string ?? link } label: { Image(systemName: "doc.on.clipboard") }.foregroundStyle(Theme.mango)
                }
                .inputStyle()
            }
            ListBox(fill: Theme.bg2) {
                ToggleRow(title: "Link only", sub: "Keep just the link: nothing is stored, and the app downloads while signing. Off = download it now", isOn: $linkOnly)
            }
            WebButton(title: "Add from link", kind: .primary, disabled: busy || link.trimmingCharacters(in: .whitespaces).isEmpty) { addLink() }.padding(.top, 10)
            if let status {
                VStack(spacing: 8) {
                    if let progress { ProgressView(value: progress).tint(Theme.mango) } else { ProgressView().tint(Theme.mango) }
                    Text(status).font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(.top, 14)
            }
            SectionTitle(text: "Keep apps coming in by themselves")
            ListBox(fill: Theme.bg2) {
                LinkRow(title: "＋ Add a source", value: "AltStore, GitHub repos") { router.open(.addSource) }
                if server.isOwner {
                    RowLine()
                    LinkRow(title: "✈️ Telegram channels") { router.open(.telegram(nil)) }
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [FileTypes.ipa], allowsMultipleSelection: false) { r in
            guard case .success(let urls) = r, let u = urls.first else { return }
            upload(u)
        }
        .interactiveDismissDisabled(busy)
    }

    func finish(_ result: [String: Any]) async {
        await server.refresh()
        status = nil
        if let a = result["app"] as? [String: Any], let id = a["id"] as? String {
            router.say("Added \(a["name"] as? String ?? "it")")
            router.open(.editApp(id))
        } else { router.close() }
    }

    func upload(_ u: URL) {
        status = "Uploading…"; progress = 0
        Task {
            do {
                let uid = try await server.uploadLarge(u) { p, line in progress = p; status = line }
                status = "Reading app info…"; progress = nil
                var r = try await server.post("/api/apps", ["uploadId": uid, "fileName": u.lastPathComponent])
                if let job = r["jobId"] as? String { r = try await server.waitJob(job) { p, l in progress = p; status = p != nil ? "Saving to GitHub \(Int((p ?? 0) * 100))%" : l } }
                await finish(r)
            } catch { status = nil; router.say(error.localizedDescription) }
        }
    }

    func addLink() {
        var u = link.trimmingCharacters(in: .whitespaces)
        if !u.contains("://") { u = "https://" + u }
        status = linkOnly ? "Reading the app…" : "Downloading…"; progress = nil
        let path = linkOnly ? "/api/apps/link" : "/api/apps/import"
        Task {
            do {
                let r = try await server.post(path, ["url": u])
                guard let job = r["jobId"] as? String else { await finish(r); return }
                let res = try await server.waitJob(job) { p, l in progress = p; status = p != nil ? "\(linkOnly ? "Reading" : "Downloading") \(Int((p ?? 0) * 100))%" : l }
                await finish(res)
            } catch { status = nil; router.say(error.localizedDescription) }
        }
    }
}

// MARK: - Announcement, messages, backups

struct AnnouncementSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    @State private var text = ""
    @State private var style = "info"
    @State private var loaded = false
    var body: some View {
        SheetScroll {
            SheetTitle(text: "📣 Announcement")
            Hint(text: "Shown at the top of everyone's app and website until you turn it off.").padding(.bottom, 10)
            Field(label: "Message") { TextField("e.g. New apps added every day 🥭", text: $text, axis: .vertical).lineLimit(2...6).inputStyle() }
            Field(label: "Style") { SelectBox(selection: $style, options: [("info", "ℹ️ Info"), ("success", "✅ Good news"), ("warning", "⚠️ Heads up"), ("party", "🎉 Party")]) }
            VStack(spacing: 10) {
                WebButton(title: "Post it", kind: .primary, disabled: text.trimmingCharacters(in: .whitespaces).isEmpty) { put(text) }
                if !(server.state?.announcement?.text ?? "").isEmpty { WebButton(title: "Turn it off", kind: .danger) { put("") } }
            }
        }
        .onAppear { if !loaded { loaded = true; text = server.state?.announcement?.text ?? ""; style = server.state?.announcement?.style ?? "info" } }
    }
    func put(_ t: String) {
        Task {
            do { _ = try await server.post("/api/announcement", ["text": t, "style": style], method: "PUT"); await server.refresh(); router.say(t.isEmpty ? "Announcement off" : "Posted"); router.close() } catch { router.say(error.localizedDescription) }
        }
    }
}

struct BroadcastSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    @State private var title = ""
    @State private var message = ""
    @State private var busy = false
    var body: some View {
        SheetScroll {
            SheetTitle(text: "📣 Message everyone")
            Hint(text: "Goes to everyone's 🔔 alerts.").padding(.bottom, 10)
            Field(label: "Title") { TextField("e.g. Server update tonight", text: $title).inputStyle() }
            Field(label: "Message (optional)") { TextField("More details", text: $message, axis: .vertical).lineLimit(2...8).inputStyle() }
            WebButton(title: busy ? "Sending…" : "Send", kind: .primary, disabled: busy || title.trimmingCharacters(in: .whitespaces).isEmpty) {
                busy = true
                Task {
                    defer { busy = false }
                    do {
                        let r = try await server.post("/api/broadcast", ["title": title, "body": message])
                        let n = (r["sent"] as? NSNumber)?.intValue ?? 0
                        router.say("Sent to \(n) \(n == 1 ? "person" : "people")"); router.close()
                    } catch { router.say(error.localizedDescription) }
                }
            }
        }
    }
}

struct BackupSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    @State private var file: URL?
    @State private var busy: String?
    @State private var picking = false
    @State private var confirmRestore: URL?
    var body: some View {
        SheetScroll {
            SheetTitle(text: "💾 Backup & restore")
            Hint(text: "A backup has your settings, users, library info, certificates, tweaks and icons. App files and signed copies aren't in it, to keep it small. Last backup: \(server.state?.settings?.lastBackup.map { ago($0) } ?? "never").").padding(.bottom, 12)
            VStack(spacing: 10) {
                if let file {
                    ShareLink(item: file) {
                        Label("Save or share the backup", systemImage: "square.and.arrow.up").font(.headline).foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity).padding(.vertical, 14).background(Theme.gradient).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                } else {
                    WebButton(title: busy == "backup" ? "Making the backup…" : "Make a backup", kind: .primary, big: true, disabled: busy != nil) { backup() }
                }
                WebButton(title: busy == "restore" ? "Restoring…" : "Restore from a backup", kind: .danger, disabled: busy != nil) { picking = true }
            }
            Hint(text: "Restoring replaces everything on this server with what's in the backup, then the server restarts.").padding(.top, 8)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.zip], allowsMultipleSelection: false) { r in
            if case .success(let urls) = r, let u = urls.first { confirmRestore = u }
        }
        .confirmationDialog("Restore this backup?", isPresented: Binding(get: { confirmRestore != nil }, set: { if !$0 { confirmRestore = nil } }), titleVisibility: .visible) {
            Button("Replace everything", role: .destructive) { if let u = confirmRestore { restore(u) } }
        } message: { Text("Everything on the server now is replaced. This can't be undone.") }
    }
    func backup() {
        busy = "backup"
        Task {
            defer { busy = nil }
            do {
                guard let u = server.url("/api/backup") else { return }
                let tmp = try await server.downloadFile(u) { _ in }
                let stamp = ISO8601DateFormatter().string(from: Date()).prefix(16).replacingOccurrences(of: ":", with: "-")
                let dest = Paths.work.appendingPathComponent("mango-backup-\(stamp).zip")
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                file = dest
                _ = try? await server.post("/api/settings", ["lastBackup": true], method: "PATCH")
                await server.refresh()
            } catch { router.say(error.localizedDescription) }
        }
    }
    func restore(_ u: URL) {
        busy = "restore"
        Task {
            defer { busy = nil }
            do {
                let uid = try await server.uploadLarge(u) { _, _ in }
                let r = try await server.post("/api/restore", ["uploadId": uid])
                let apps = (r["apps"] as? NSNumber)?.intValue ?? 0, users = (r["users"] as? NSNumber)?.intValue ?? 0
                router.say("Restored \(apps) apps and \(users) users. The server is restarting…")
                router.close()
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await server.refresh()
            } catch { router.say(error.localizedDescription) }
        }
    }
}
