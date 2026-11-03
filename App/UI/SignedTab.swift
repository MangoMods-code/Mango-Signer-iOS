import SwiftUI

/// Where a signed app stands on this iPhone right now.
struct PhoneStatus {
    var installed: Bool?        // nil = iOS can't tell
    var version: String?
    var bundleId: String?

    static func of(bundleId: String?) -> PhoneStatus {
        let here = DeviceApps.isInstalled(bundleId)
        return PhoneStatus(installed: here, version: here == true ? DeviceApps.version(bundleId) : nil, bundleId: bundleId)
    }
    /// Installed and it's this exact signed copy (same version), so "Open" makes more sense than "Get".
    func isSame(as version: String?) -> Bool {
        installed == true && (self.version == nil || versionCompare(self.version, version) == 0)
    }
}

struct SignedTab: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var router: Router

    var signed: [SSigned] { server.state?.signed ?? [] }
    var installs: [SInstallLog] { server.state?.installs ?? [] }
    /// Copies on this iPhone that aren't tied to something still in the list above (signed here, or deleted on the server).
    var phoneOnly: [SignedApp] { local.signed.filter { c in c.serverId == nil || !signed.contains { $0.id == c.serverId } } }

    var body: some View {
        let _ = server.deviceCheck
        VStack(alignment: .leading, spacing: 0) {
            if signed.isEmpty && installs.isEmpty && local.signed.isEmpty {
                WebEmpty(icon: "arrow.down.circle", title: "Nothing signed yet", text: "Signed apps show up here, ready to install.",
                         button: "Go to \(server.isOwner ? "Library" : "App Library")") { router.tab = .library }
            } else {
                phoneCard
                let notes = notesText
                if !notes.isEmpty { Hint(text: notes).padding(.bottom, 4) }
                let ready = signed.filter { $0.fileAvailable == true || local.copy(of: $0.id) != nil }
                let old = signed.filter { $0.fileAvailable != true && local.copy(of: $0.id) == nil }
                if !ready.isEmpty {
                    SectionTitle(text: "Ready to install", count: ready.count)
                    ListBox { rows(ready) }
                }
                if !old.isEmpty {
                    SectionTitle(text: "File removed", count: old.count)
                    ListBox { rows(old) }
                }
                if !phoneOnly.isEmpty {
                    SectionTitle(text: "Saved on this iPhone", count: phoneOnly.count)
                    ListBox {
                        ForEach(Array(phoneOnly.enumerated()), id: \.element.id) { i, c in
                            if i > 0 { RowLine() }
                            LocalSignedRow(copy: c)
                        }
                    }
                    Hint(text: "Signed on this iPhone, or deleted from the server. Share one to an installer, or touch and hold to delete it.").padding(.top, 6)
                }
                history
            }
        }
        .refreshable {
            await server.refresh()
            await server.syncWithDevice(force: true)
        }
    }

    /// "What's on this iPhone" summary, like ESign's app list.
    @ViewBuilder
    var phoneCard: some View {
        if DeviceApps.available {
            let here = signed.filter { DeviceApps.isInstalled($0.bundleId) == true }
            let saving = local.saving.count
            HStack(spacing: 12) {
                Image(systemName: "iphone").font(.title2).foregroundStyle(Theme.mango)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(here.count) of these \(here.count == 1 ? "is" : "are") on this iPhone").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(saving > 0 ? "Saving \(saving) signed app\(saving == 1 ? "" : "s") to this iPhone…"
                         : "\(local.signed.count) signed app\(local.signed.count == 1 ? "" : "s") saved here · checked just now")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(14).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.bottom, 10)
        }
    }

    var notesText: String {
        var n: [String] = []
        let s = server.state?.settings
        if !server.isOwner { n.append("Your newest \(s?.maxSignedPerUser ?? 10) signed apps are kept on the server.") }
        if s?.signedOnGithub == true || server.state?.github?.signedToGithub == true {
            n.append("Signed apps stay here until you delete them, or until their certificate expires.")
        } else if let keep = s?.signedRetentionDays, keep > 0 {
            n.append("The server removes signed files after \(keep) day\(keep == 1 ? "" : "s").")
        }
        if LocalStore.keepCopies { n.append("Every app you sign is also saved on this iPhone, so it can always be installed again.") }
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
                    let app = server.app(l.appId)
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
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var router: Router
    let s: SSigned
    @State private var busy = false

    var body: some View {
        let phone = PhoneStatus.of(bundleId: s.bundleId)
        let copy = local.copy(of: s.id)
        let saving = local.saving[s.id]
        HStack(spacing: 12) {
            WebIcon(url: server.iconURL(s), name: s.name)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(s.version ?? "—") · \(s.certLabel ?? "")").font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                Text("Signed \(ago(s.signedAt)) · \(formatBytes(s.size))").font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                BadgeFlow(badges: badges(phone, copy: copy, saving: saving)).padding(.top, 4)
            }
            Spacer(minLength: 4)
            if busy {
                ProgressView().tint(Theme.mango).frame(width: 60)
            } else if phone.isSame(as: s.version), let id = s.bundleId {
                PillButton(title: "Open") { if !DeviceApps.open(id) { router.say("Couldn't open it") } }
            } else if s.fileAvailable == true {
                PillButton(title: "Get") { router.startInstall(s, server: server) }
            } else if let copy {
                PillButton(title: "Get") { restoreAndInstall(copy) }
            } else {
                PillButton(title: "Re-sign", dim: true) { resign() }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { router.open(.signed(s.id)) }
    }

    func badges(_ phone: PhoneStatus, copy: SignedApp?, saving: Double?) -> [Badge] {
        var b: [Badge] = []
        if phone.installed == true {
            b.append(Badge(text: phone.isSame(as: s.version) ? "✓ On this iPhone" : "On this iPhone · v\(phone.version ?? "?")", style: .good, small: true))
        } else if phone.installed == nil && s.onPhone == true {
            b.append(Badge(text: "On your phone", style: .good, small: true))
        }
        if let left = s.daysLeft {
            if left < 0 { b.append(Badge(text: "Cert expired", style: .bad, small: true)) }
            else { b.append(Badge(text: "\(left)d left", style: left < 7 ? .warn : .plain, small: true)) }
        }
        if let saving { b.append(Badge(text: "Saving \(Int(saving * 100))%", style: .mango, small: true)) }
        else if copy != nil { b.append(Badge(text: "📱 Saved", style: .mango, small: true)) }
        if s.savedOnGithub == true { b.append(Badge(text: "☁ Saved", style: .cloud, small: true)) }
        return b
    }

    func restoreAndInstall(_ copy: SignedApp) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let fresh = try await server.restoreSigned(s, from: copy) ?? s
                router.startInstall(fresh, server: server)
            } catch { router.say(error.localizedDescription) }
        }
    }

    func resign() {
        guard let appId = s.appId, server.app(appId) != nil else { router.say("That app is no longer in the library"); return }
        router.open(.sign(appId, presetId: nil))
    }
}

/// A signed app kept only on this iPhone.
struct LocalSignedRow: View {
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var router: Router
    let copy: SignedApp
    var body: some View {
        let _ = 0
        let phone = PhoneStatus.of(bundleId: copy.bundleId)
        HStack(spacing: 12) {
            LocalIcon(id: copy.id, name: copy.name, size: 54)
            VStack(alignment: .leading, spacing: 1) {
                Text(copy.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(copy.version) · \(copy.certLabel)").font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                Text("Signed \(copy.signedAt.formatted(.relative(presentation: .named))) · \(formatSize(copy.size))").font(.system(size: 13)).foregroundStyle(Theme.muted)
                if phone.installed == true { BadgeFlow(badges: [Badge(text: "✓ On this iPhone", style: .good, small: true)]).padding(.top, 4) }
            }
            Spacer(minLength: 4)
            if phone.installed == true {
                PillButton(title: "Open") { if !DeviceApps.open(copy.bundleId) { router.say("Couldn't open it") } }
            }
            ShareLink(item: copy.url) {
                Text("Share").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.mango)
                    .padding(.horizontal, 15).padding(.vertical, 6).background(Theme.mango.opacity(0.16)).clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contextMenu { Button(role: .destructive) { local.delete(copy) } label: { Label("Delete from this iPhone", systemImage: "trash") } }
    }
}

/// One signed app's details, like the website, plus what's on this iPhone.
struct SignedSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var router: Router
    let signedId: String
    @State private var confirmDelete = false
    @State private var confirmRelink = false
    @State private var busy = false

    var body: some View {
        SheetScroll {
            if let s = router.signed(signedId, server) {
                let phone = PhoneStatus.of(bundleId: s.bundleId)
                let copy = local.copy(of: s.id)
                SheetHead(title: s.name, sub: s.bundleId ?? "") { WebIcon(url: server.iconURL(s), name: s.name, size: 76) }
                if s.fileAvailable != true {
                    WarningBox(text: copy != nil
                               ? "The server cleaned up its copy, but it's saved on this iPhone. Tap Install and Mango puts it back first."
                               : "The signed file was cleaned up to save space. Tap Sign again to make a fresh one.")
                }
                KVList(items: kv(s, phone: phone, copy: copy))
                VStack(spacing: 10) {
                    if phone.isSame(as: s.version), let id = s.bundleId {
                        WebButton(title: "Open", kind: .primary, big: true) { if !DeviceApps.open(id) { router.say("Couldn't open it") } }
                    }
                    if s.fileAvailable == true {
                        WebButton(title: phone.installed == true ? "Install again" : "Install", kind: phone.isSame(as: s.version) ? .normal : .primary, big: !phone.isSame(as: s.version)) {
                            router.startInstall(s, server: server)
                        }
                    } else if let copy {
                        WebButton(title: busy ? "Putting it back on the server…" : "Install", kind: .primary, big: true, disabled: busy) { restore(s, copy) }
                    }
                    if let copy {
                        ShareLink(item: copy.url) {
                            Text("Share .ipa").font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .foregroundStyle(Theme.text).background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                    } else if let p = local.saving[s.id] {
                        WebButton(title: "Saving to this iPhone… \(Int(p * 100))%", disabled: true) {}
                    } else if s.fileAvailable == true {
                        WebButton(title: "Save to this iPhone") {
                            Task { do { try await local.saveCopy(s, server: server); router.say("Saved on this iPhone") } catch { router.say(error.localizedDescription) } }
                        }
                    }
                    if s.fileAvailable == true, let share = s.shareUrl {
                        WebButton(title: "Copy install link") { UIPasteboard.general.string = share; router.say("Install link copied") }
                        WebButton(title: "Show QR code") { router.open(.qr(title: "Install \(s.name)", url: share)) }
                    }
                    WebButton(title: "Sign again", kind: s.fileAvailable == true || copy != nil ? .normal : .primary, big: s.fileAvailable != true && copy == nil) {
                        guard let appId = s.appId, server.app(appId) != nil else { router.say("That app is no longer in the library"); return }
                        router.open(.sign(appId, presetId: nil))
                    }
                    if s.fileAvailable == true { WebButton(title: "Reset install link") { confirmRelink = true } }
                    WebButton(title: "Delete", kind: .danger) { confirmDelete = true }
                }
                .padding(.top, 10)
                .confirmationDialog("Delete signed \(s.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete from the server", role: .destructive) { delete(s, alsoPhone: false) }
                    if copy != nil { Button("Delete from the server and this iPhone", role: .destructive) { delete(s, alsoPhone: true) } }
                } message: { Text(copy != nil ? "The copy on this iPhone stays unless you delete it too." : "This only removes the signed copy. The app stays installed.") }
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

    func restore(_ s: SSigned, _ copy: SignedApp) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let fresh = try await server.restoreSigned(s, from: copy) ?? s
                router.startInstall(fresh, server: server)
            } catch { router.say(error.localizedDescription) }
        }
    }

    func delete(_ s: SSigned, alsoPhone: Bool) {
        Task {
            do {
                _ = try await server.data("DELETE", "/api/signed/\(s.id)")
                if alsoPhone, let c = local.copy(of: s.id) { local.delete(c) }
                router.close(); router.say("Deleted"); await server.refresh()
            } catch { router.say(error.localizedDescription) }
        }
    }

    func kv(_ s: SSigned, phone: PhoneStatus, copy: SignedApp?) -> [(String, String)] {
        let left = s.daysLeft
        var items: [(String, String)] = []
        items.append(("Version", s.version ?? "—"))
        items.append(("Certificate", s.certLabel ?? "—"))
        items.append(("Signed", ago(s.signedAt)))
        items.append(("Works until", "\(shortDate(s.expires))\(left.map { $0 < 0 ? " (expired)" : " (\($0) days)" } ?? "")"))
        items.append(("Size", formatBytes(s.size)))
        switch phone.installed {
        case true?: items.append(("On this iPhone", phone.version.map { "Installed · v\($0)" } ?? "Installed"))
        case false?: items.append(("On this iPhone", "Not installed"))
        case nil: break
        }
        items.append(("Saved here", copy != nil ? "Yes · \(formatSize(copy!.size))" : "No"))
        let o = s.options
        let tw = (o?.dylibs ?? []) + (o?.tweaks ?? [])
        if !tw.isEmpty { items.append(("Tweaks", tw.joined(separator: ", "))) }
        var extras: [String] = []
        for k in o?.entitlements ?? [] {
            if let p = SignPresets.ent.first(where: { $0.key == k }) { extras.append(p.short) } else { extras.append(k.components(separatedBy: ".").last ?? k) }
        }
        for k in o?.plist ?? [] {
            if let p = SignPresets.plist.first(where: { $0.key == k }) { extras.append(p.short) } else { extras.append(k) }
        }
        if !extras.isEmpty { items.append(("Changes", extras.joined(separator: ", "))) }
        return items
    }
}
