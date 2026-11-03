import SwiftUI

struct LibraryScreen: View {
    @EnvironmentObject var server: Server
    @State private var search = ""
    @State private var filter = "all"
    @State private var getting: SApp?
    @State private var limit = 60

    var apps: [SApp] { server.state?.apps ?? [] }

    var filtered: [SApp] {
        var list = apps
        if !search.isEmpty {
            list = list.filter { a in
                [a.name, a.bundleId ?? "", a.developer ?? "", a.sourceName ?? "", a.description ?? ""]
                    .contains { $0.localizedCaseInsensitiveContains(search) }
            }
        }
        switch filter {
        case "all": break
        case "favorites": list = list.filter { server.isFavorite($0) }
        case "installed": list = list.filter { $0.installed != nil }
        case "updates": list = list.filter { $0.hasUpdate }
        case "featured": list = list.filter { $0.featured == true }
        case "new": list = list.filter { $0.isNew || $0.isUpdatedRecently }
        default: list = list.filter { $0.categoryId == filter }
        }
        return list.sorted { $0.sortDate > $1.sortDate }
    }

    struct Chip: Identifiable { let id: String; let label: String; let count: Int }

    var chips: [Chip] {
        var c: [Chip] = [Chip(id: "all", label: "All", count: apps.count)]
        let fav = apps.filter { server.isFavorite($0) }.count
        let inst = apps.filter { $0.installed != nil }.count
        let upd = apps.filter { $0.hasUpdate }.count
        let feat = apps.filter { $0.featured == true }.count
        let new = apps.filter { $0.isNew || $0.isUpdatedRecently }.count
        if fav > 0 { c.append(Chip(id: "favorites", label: "♥", count: fav)) }
        if upd > 0 { c.append(Chip(id: "updates", label: "⬆ Updates", count: upd)) }
        if inst > 0 { c.append(Chip(id: "installed", label: "✓ Installed", count: inst)) }
        if new > 0 { c.append(Chip(id: "new", label: "✨ New", count: new)) }
        if feat > 0 { c.append(Chip(id: "featured", label: "★ Featured", count: feat)) }
        for cat in (server.state?.categories ?? []).sorted(by: { ($0.order ?? 0) < ($1.order ?? 0) }) {
            let n = apps.filter { $0.categoryId == cat.id }.count
            if n > 0 { c.append(Chip(id: cat.id, label: "\(cat.emoji ?? "") \(cat.name)", count: n)) }
        }
        return c
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    if let a = server.state?.announcement?.text, !a.isEmpty {
                        Text(a).font(.subheadline).foregroundStyle(Theme.text).padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.mango.opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.bottom, 10)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chips) { c in
                                Button { withAnimation(.easeOut(duration: 0.15)) { filter = c.id; limit = 60 } } label: {
                                    HStack(spacing: 5) {
                                        Text(c.label).fontWeight(.semibold)
                                        if c.id != "all" { Text("\(c.count)").opacity(0.7) }
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(filter == c.id ? Theme.onAccent : Theme.text)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(filter == c.id ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.card))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .padding(.bottom, 6)

                    let list = filtered
                    if list.isEmpty {
                        EmptyState(icon: "magnifyingglass", title: search.isEmpty ? "Nothing here" : "No matches",
                                   message: search.isEmpty ? "No apps in this group yet." : "Try a different search.")
                    } else {
                        SectionTitle(text: filter == "all" ? "Recently updated" : chips.first { $0.id == filter }?.label ?? "Apps", count: list.count)
                        Card {
                            ForEach(Array(list.prefix(limit).enumerated()), id: \.element.id) { i, app in
                                if i > 0 { Divider().overlay(Theme.line).padding(.leading, 84) }
                                NavigationLink(value: app.id) { AppRow(app: app) { getting = app } }
                                    .buttonStyle(.plain)
                            }
                        }
                        if list.count > limit {
                            Button("Show more (\(list.count - limit) left)") { limit += 60 }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mango).padding(.vertical, 16)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await server.refresh() }
            .searchable(text: $search, prompt: "Search \(apps.count) apps")
            .navigationTitle("Library")
            .navigationDestination(for: String.self) { id in AppScreen(appId: id) }
            .mangoScreen()
            .sheet(item: $getting) { app in GetSheet(app: app, versionIndex: 0) }
        }
    }
}

struct AppRow: View {
    @EnvironmentObject var server: Server
    let app: SApp
    let onGet: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            RemoteIcon(url: server.iconURL(app), name: app.name, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                Text([app.shownVersion, app.developer ?? "", formatBytes(app.size)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                HStack(spacing: 5) {
                    if app.hasUpdate { Badge(text: "⬆ Update", style: .mango) }
                    else if app.isStopped { Badge(text: "⚠ Won't open", style: .bad) }
                    else if app.installed != nil { Badge(text: "✓ Installed", style: .good) }
                    if app.isNew { Badge(text: "NEW", style: .new) } else if app.isUpdatedRecently { Badge(text: "UPDATED", style: .new) }
                    if let s = app.sourceName, app.cloud == "telegram" || app.cloud == "source" {
                        Badge(text: "\(app.cloud == "telegram" ? "✈️" : "☁") \(s)", style: .blue).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 6)
            PillButton(title: app.hasUpdate ? "Update" : app.isStopped ? "Fix" : "Get", action: onGet)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
