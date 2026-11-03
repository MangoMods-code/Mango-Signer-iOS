import SwiftUI

struct SignedTab: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var router: Router

    var signed: [SSigned] { server.state?.signed ?? [] }
    var installs: [SInstallLog] { server.state?.installs ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if signed.isEmpty && installs.isEmpty && local.signed.isEmpty {
                WebEmpty(icon: "arrow.down.circle", title: "Nothing signed yet", text: "Signed apps show up here, ready to install.",
                         button: "Go to \(server.isOwner ? "Library" : "App Library")") { router.tab = .library }
            } else {
                let notes = notesText
                if !notes.isEmpty { Hint(text: notes).padding(.bottom, 10) }
                let ready = signed.filter { $0.fileAvailable == true }
                let old = signed.filter { $0.fileAvailable != true }
                if !ready.isEmpty {
                    SectionTitle(text: "Ready to install", count: ready.count)
                    ListBox { rows(ready) }
                }
                if !old.isEmpty {
                    SectionTitle(text: "File removed", count: old.count)
                    ListBox { rows(old) }
                }
                if !local.signed.isEmpty {
                    SectionTitle(text: "Signed on this iPhone", count: local.signed.count)
                    ListBox {
                        ForEach(Array(local.signed.enumerated()), id: \.element.id) { i, s in
                            if i > 0 { RowLine() }
                            HStack(spacing: 12) {
                                LocalIcon(id: s.id, name: s.name, size: 54)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                                    Text("\(s.version) · \(s.certLabel)").font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                                    Text("Signed \(s.signedAt.formatted(.relative(presentation: .named))) · \(formatSize(s.size))").font(.system(size: 13)).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 4)
                                ShareLink(item: s.url) {
                                    Text("Share").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.mango)
                                        .padding(.horizontal, 15).padding(.vertical, 6).background(Theme.mango.opacity(0.16)).clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .contextMenu { Button(role: .destructive) { local.delete(s) } label: { Label("Delete", systemImage: "trash") } }
                        }
                    }
                    Hint(text: "Touch and hold one to delete it.").padding(.top, 6)
                }
                history
            }
        }
    }

    var notesText: String {
        var n: [String] = []
        let s = server.state?.settings
        if !server.isOwner { n.append("Your newest \(s?.maxSignedPerUser ?? 10) signed apps are kept.") }
        if s?.signedOnGithub == true || server.state?.github?.signedToGithub == true {
            n.append("Signed apps stay here until you delete them, or until their certificate expires.")
        } else if let keep = s?.signedRetentionDays, keep > 0 {
            n.append("Signed files are removed after \(keep) day\(keep == 1 ? "" : "s") to save space — tap Sign again any time.")
        }
        return n.joined(separator: " ")
    }

    @ViewBuilder
    func rows(_ list: [SSigned]) -> some View {
        ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
            if i > 0 { RowLine() }
            SignedRow(s: s)
        }
    }

    @ViewBuilder
    var history: some View {
        if !installs.isEmpty {
            SectionTitle(text: "Install history", count: installs.count)
            let mine = (server.state?.apps ?? []).filter { $0.installed != nil }.count
            if mine > 0 {
                HStack(spacing: 10) {
                    Text("\(mine) app\(mine == 1 ? "" : "s") on your phone, as far as Mango knows").font(.system(size: 14)).foregroundStyle(Theme.soft).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Review") { router.open(.myApps) }.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 12).padding(.vertical, 7).background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal, 12).padding(.vertical, 10).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12)).padding(.bottom, 12)
            }
            ListBox {
                ForEach(Array(installs.prefix(20).enumerated()), id: \.offset) { i, l in
                    if i > 0 { RowLine() }
                    let app = (server.state?.apps ?? []).first { $0.id == l.appId }
                    HStack(spacing: 12) {
                        if let app { AppIconImage(app: app) } else { WebIcon(url: nil, name: l.name) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            Text("\(l.shownVersion ?? l.version ?? "") · \(l.certLabel ?? "")\(l.via == "link" ? " · from a shared link" : "")").font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                            Text(parseDate(l.at)?.formatted(.dateTime.month(.abbreviated).day().hour().minute()) ?? "").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Badge(text: "✓", style: .good)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { if let app { router.open(.app(app.id)) } }
                }
            }
        }
    }
}

struct SignedRow: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let s: SSigned
    var body: some View {
        HStack(spacing: 12) {
            WebIcon(url: server.iconURL(s), name: s.name)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(s.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    if s.onPhone == true { Badge(text: "On your phone", style: .good, small: true) }
                    if let left = s.daysLeft {
                        if left < 0 { Badge(text: "Cert expired", style: .bad, small: true) }
                        else { Badge(text: "\(left)d left", style: left < 7 ? .warn : .plain, small: true) }
                    }
                }
                Text("\(s.version ?? "—") · \(s.certLabel ?? "")").font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                Text("Signed \(ago(s.signedAt)) · \(formatBytes(s.size))\(s.savedOnGithub == true ? " · ☁ saved" : "")").font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if s.fileAvailable == true {
                PillButton(title: "Get") { router.startInstall(s, server: server) }
            } else {
                PillButton(title: "Re-sign", dim: true) { resign() }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { router.open(.signed(s.id)) }
    }
    func resign() {
        guard let appId = s.appId, (server.state?.apps ?? []).contains(where: { $0.id == appId }) else { router.say("That app is no longer in the library"); return }
        router.open(.sign(appId, presetId: nil))
    }
}

/// One signed app's details, like the website.
struct SignedSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let signedId: String
    @State private var confirmDelete = false
    @State private var confirmRelink = false

    var body: some View {
        SheetScroll {
            if let s = router.signed(signedId, server) {
                SheetHead(title: s.name, sub: s.bundleId ?? "") { WebIcon(url: server.iconURL(s), name: s.name, size: 76) }
                if s.fileAvailable != true { WarningBox(text: "The signed file was cleaned up to save space. Tap Sign again to make a fresh one.") }
                KVList(items: kv(s))
                VStack(spacing: 10) {
                    if s.fileAvailable == true {
                        WebButton(title: "Install", kind: .primary, big: true) { router.startInstall(s, server: server) }
                        if let share = s.shareUrl {
                            WebButton(title: "Copy install link") { UIPasteboard.general.string = share; router.say("Install link copied") }
                            WebButton(title: "Show QR code") { router.open(.qr(title: "Install \(s.name)", url: share)) }
                        }
                        if let d = s.downloadUrl, let u = URL(string: d) {
                            ShareLink(item: u) {
                                Text("Share signed .ipa link").font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .foregroundStyle(Theme.text).background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                        }
                    }
                    WebButton(title: "Sign again", kind: s.fileAvailable == true ? .normal : .primary, big: s.fileAvailable != true) {
                        guard let appId = s.appId, (server.state?.apps ?? []).contains(where: { $0.id == appId }) else { router.say("That app is no longer in the library"); return }
                        router.open(.sign(appId, presetId: nil))
                    }
                    if s.fileAvailable == true { WebButton(title: "Reset install link") { confirmRelink = true } }
                    WebButton(title: "Delete", kind: .danger) { confirmDelete = true }
                }
                .padding(.top, 10)
                .confirmationDialog("Delete signed \(s.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        Task {
                            do { _ = try await server.data("DELETE", "/api/signed/\(s.id)"); router.close(); router.say("Deleted"); await server.refresh() } catch { router.say(error.localizedDescription) }
                        }
                    }
                }
                .confirmationDialog("Old install links will stop working. Continue?", isPresented: $confirmRelink, titleVisibility: .visible) {
                    Button("Reset link") {
                        Task {
                            do { try await server.post("/api/signed/\(s.id)/relink"); router.close(); router.say("New link created"); await server.refresh() } catch { router.say(error.localizedDescription) }
                        }
                    }
                }
            } else {
                WebEmpty(icon: "questionmark.circle", title: "Not found", text: "This signed app was removed.")
            }
        }
    }

    func kv(_ s: SSigned) -> [(String, String)] {
        let left = s.daysLeft
        var items: [(String, String)] = [
            ("Version", s.version ?? "—"),
            ("Certificate", s.certLabel ?? "—"),
            ("Signed", ago(s.signedAt)),
            ("Works until", "\(shortDate(s.expires))\(left.map { $0 < 0 ? " (expired)" : " (\($0) days)" } ?? "")"),
            ("Size", formatBytes(s.size)),
        ]
        let o = s.options
        let tw = (o?.dylibs ?? []) + (o?.tweaks ?? [])
        if !tw.isEmpty { items.append(("Tweaks", tw.joined(separator: ", "))) }
        var extras: [String] = []
        for k in o?.entitlements ?? [] {
            if let p = SignPresets.ent.first(where: { $0.key == k }) { extras.append(p.short) }
            else { extras.append(k.components(separatedBy: ".").last ?? k) }
        }
        for k in o?.plist ?? [] {
            if let p = SignPresets.plist.first(where: { $0.key == k }) { extras.append(p.short) } else { extras.append(k) }
        }
        if !extras.isEmpty { items.append(("Changes", extras.joined(separator: ", "))) }
        return items
    }
}
