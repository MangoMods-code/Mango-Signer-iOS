import SwiftUI

struct AppScreen: View {
    @EnvironmentObject var server: Server
    let appId: String
    @State private var getVersion: Int?
    @State private var toast: String?

    var app: SApp? { server.state?.apps.first { $0.id == appId } }

    var body: some View {
        Group {
            if let app { content(app) } else { EmptyState(icon: "questionmark.app", title: "App not found", message: "It may have been removed.") }
        }
        .mangoScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
        .sheet(item: Binding(get: { getVersion.map { VersionPick(index: $0) } }, set: { getVersion = $0?.index })) { pick in
            if let app { GetSheet(app: app, versionIndex: pick.index) }
        }
    }

    struct VersionPick: Identifiable { let index: Int; var id: Int { index } }

    @ViewBuilder
    func content(_ app: SApp) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 16) {
                    RemoteIcon(url: server.iconURL(app), name: app.name, size: 96)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.name).font(.title2.bold()).foregroundStyle(Theme.text)
                        if let d = app.developer, !d.isEmpty { Text(d).font(.subheadline).foregroundStyle(Theme.muted) }
                        Text(app.bundleId ?? "").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.top, 8)

                FlowBadges(app: app).padding(.top, 14)

                HStack(spacing: 0) {
                    stat("\(app.installCount ?? 0)", "installs")
                    Divider().frame(height: 34).overlay(Theme.line)
                    let votes = (app.likes ?? 0) + (app.dislikes ?? 0)
                    stat(votes > 0 ? "\(Int((Double(app.likes ?? 0) / Double(votes) * 100).rounded()))%" : "—", votes > 0 ? "liked" : "no votes yet")
                    Divider().frame(height: 34).overlay(Theme.line)
                    stat(app.minOS?.isEmpty == false ? app.minOS! : "—", "min iOS")
                }
                .padding(.vertical, 12)
                .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16)).padding(.top, 14)

                BigButton(title: app.hasUpdate ? "Update to \(app.shownVersion)" : app.isStopped ? "Sign Again to Fix" : app.installed != nil ? "Get Again" : "Get",
                          icon: "arrow.down.circle.fill") { getVersion = 0 }
                    .padding(.top, 16)

                if let inst = app.installed { installedNote(app, inst) }

                HStack(spacing: 10) {
                    voteButton(app, systemImage: server.isFavorite(app) ? "heart.fill" : "heart", label: nil, on: server.isFavorite(app)) {
                        let on = !server.isFavorite(app)
                        try await server.post("/api/apps/\(app.id)/favorite", ["on": on])
                        return on ? "♥ Added to Favorites" : "Removed from Favorites"
                    }
                    Spacer()
                    voteButton(app, systemImage: "hand.thumbsup.fill", label: "\(app.likes ?? 0)", on: app.myVote == 1) {
                        try await server.post("/api/apps/\(app.id)/vote", ["value": app.myVote == 1 ? 0 : 1]); return nil
                    }
                    voteButton(app, systemImage: "hand.thumbsdown.fill", label: "\(app.dislikes ?? 0)", on: app.myVote == -1) {
                        try await server.post("/api/apps/\(app.id)/vote", ["value": app.myVote == -1 ? 0 : -1]); return nil
                    }
                }
                .padding(.top, 16)

                if let shots = app.remoteScreens, !shots.isEmpty {
                    SectionTitle(text: "Screenshots")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(shots, id: \.self) { s in
                                AsyncImage(url: URL(string: s)) { img in img.resizable().scaledToFit() } placeholder: { Theme.card }
                                    .frame(height: 380).clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }

                if let d = app.description, !d.isEmpty {
                    SectionTitle(text: "About")
                    Text(d).font(.body).foregroundStyle(Theme.text.opacity(0.9))
                }

                let whatsNew = (app.notes?.isEmpty == false ? app.notes : app.versions?.first?.notes) ?? ""
                if !whatsNew.isEmpty {
                    SectionTitle(text: app.notes?.isEmpty == false ? "What's changed" : "What's new in \(app.versions?.first?.version ?? app.shownVersion)")
                    Text(cleanNotes(whatsNew)).font(.body).foregroundStyle(Theme.text.opacity(0.9))
                }

                if let versions = app.versions, versions.count > 1 {
                    SectionTitle(text: "Other versions", count: versions.count - 1)
                    Card {
                        ForEach(Array(versions.enumerated().dropFirst()), id: \.offset) { i, v in
                            if i > 1 { Divider().overlay(Theme.line) }
                            VersionRow(version: v) { getVersion = i }
                        }
                    }
                }

                SectionTitle(text: "Info")
                Card {
                    infoRow("Version", app.build?.isEmpty == false && app.build != app.version ? "\(app.version ?? "") (\(app.build!))" : app.version ?? "")
                    if let p = app.previousVersion { infoRow("Was", p) }
                    infoRow("Size", formatBytes(app.size))
                    if let c = server.category(app.categoryId) { infoRow("Category", "\(c.emoji ?? "") \(c.name)") }
                    if let s = app.sourceName { infoRow(app.cloud == "telegram" ? "Telegram" : "Source", s) }
                    infoRow("Updated", ago(app.updatedAt ?? app.addedAt))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .refreshable { await server.refresh() }
    }

    func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).foregroundStyle(Theme.text)
            Text(label).font(.caption2).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    func infoRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(Theme.muted)
            Spacer()
            Text(v).foregroundStyle(Theme.text).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    func voteButton(_ app: SApp, systemImage: String, label: String?, on: Bool, action: @escaping () async throws -> String?) -> some View {
        Button {
            Task {
                do { let msg = try await action(); await server.refresh(); if let msg { toast = msg } } catch { toast = error.localizedDescription }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                if let label { Text(label).fontWeight(.bold) }
            }
            .foregroundStyle(on ? Theme.mango : Theme.muted)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(on ? Theme.mango.opacity(0.16) : Theme.card)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func installedNote(_ app: SApp, _ inst: SInstalled) -> some View {
        VStack(spacing: 6) {
            if inst.stopped != nil {
                Text("You installed \(inst.version ?? "") \(ago(inst.at)), but its certificate \(inst.stopped == "revoked" ? "was revoked" : "has expired"), so it won't open. Sign it again to fix it.")
                    .font(.footnote).foregroundStyle(Theme.red).multilineTextAlignment(.center)
            } else {
                Text("You installed \(inst.version ?? "") \(ago(inst.at))\(app.hasUpdate ? " · \(app.shownVersion) is out" : "")")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 18) {
                if app.hasUpdate {
                    Button("I already updated it") { myApp(app, "latest", "Marked as up to date") }
                }
                Button("Not on my phone anymore") { myApp(app, "remove", "Removed from your installed apps") }
            }
            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.mango)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    func myApp(_ app: SApp, _ action: String, _ msg: String) {
        Task {
            do { try await server.post("/api/my-apps/\(app.id)", ["action": action]); await server.refresh(); toast = msg } catch { toast = error.localizedDescription }
        }
    }
}

struct FlowBadges: View {
    @EnvironmentObject var server: Server
    let app: SApp
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if app.hasUpdate { Badge(text: "⬆ Update", style: .mango) } else if app.installed != nil { Badge(text: "✓ Installed", style: .good) }
                if app.isNew { Badge(text: "NEW", style: .new) } else if app.isUpdatedRecently { Badge(text: "UPDATED", style: .new) }
                if let c = server.category(app.categoryId) { Badge(text: "\(c.emoji ?? "") \(c.name)", style: .mango) }
                if !app.shownVersion.isEmpty { Badge(text: "v\(app.shownVersion)") }
                if let s = app.size, s > 0 { Badge(text: formatBytes(s)) }
                if app.missing == true { Badge(text: "Removed from source", style: .bad) }
            }
        }
    }
}

struct VersionRow: View {
    let version: SVersion
    let onGet: () -> Void
    @State private var open = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(version.version ?? "?").font(.headline).foregroundStyle(Theme.text)
                    if let c = version.channel, !c.isEmpty, c != "stable" { Badge(text: c) }
                }
                Text([String((version.date ?? "").prefix(10)), formatBytes(version.size)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.muted)
                if let n = version.notes, !n.isEmpty {
                    Text(cleanNotes(n)).font(.caption).foregroundStyle(Theme.muted).lineLimit(open ? nil : 3)
                        .onTapGesture { withAnimation { open.toggle() } }
                }
            }
            Spacer()
            PillButton(title: "Get", action: onGet)
        }
        .padding(14)
    }
}
