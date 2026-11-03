import SwiftUI
import UniformTypeIdentifiers

struct CertsTab: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var router: Router
    @State private var checking: String?
    @State private var renaming: SCert?
    @State private var newLabel = ""
    @State private var deleting: SCert?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if server.certs.isEmpty {
                WebEmpty(icon: "checkmark.shield", title: "No certificates", text: "Add your .p12 and .mobileprovision to start signing.", button: "Add Certificate") { router.open(.addCert) }
            } else {
                ForEach(server.certs) { c in card(c) }
            }
            SectionTitle(text: "On this iPhone")
            ListBox {
                LinkRow(title: "📱 Certificates on this iPhone", value: "\(local.ownCerts.count)") { router.open(.localCerts) }
                RowLine()
                LinkRow(title: "📦 Apps on this iPhone", value: "\(local.apps.count)") { router.open(.localApps) }
            }
            Hint(text: "These are only used for \"Sign on this iPhone\" and never leave it.").padding(.top, 8)
        }
        .alert("Certificate nickname", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nickname", text: $newLabel)
            Button("Save") { if let c = renaming { rename(c) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(deleting?.label ?? "this certificate")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let c = deleting { delete(c) } }
        } message: { Text("Apps you already installed keep working.") }
    }

    func statusBadge(_ c: SCert) -> Badge {
        if let d = c.daysLeft, d < 0 { return Badge(text: "Expired", style: .bad) }
        switch c.check?.status {
        case "revoked": return Badge(text: "Revoked", style: .bad)
        case "valid": return Badge(text: "Valid", style: .good)
        default: return Badge(text: "Status unknown")
        }
    }

    func badges(_ c: SCert) -> [Badge] {
        var b = [statusBadge(c), Badge(text: c.type.isEmpty ? "Profile" : c.type)]
        if let left = c.daysLeft, left >= 0 { b.append(Badge(text: "\(left) days left", style: left < 14 ? .warn : .mango)) }
        if c.deviceIncluded == true && c.type != "Enterprise" { b.append(Badge(text: "Your iPhone ✓", style: .good)) }
        return b
    }

    func kv(_ c: SCert) -> [(String, String)] {
        var items: [(String, String)] = [
            ("Certificate", c.p12?.commonName ?? "—"),
            ("Team", "\(c.profile?.teamName ?? "—")\(c.profile?.teamId.map { " (\($0))" } ?? "")"),
            ("App ID", c.profile?.appId ?? "—"),
            ("Profile", c.profile?.name ?? "—"),
        ]
        if c.type != "Enterprise" { items.append(("Devices", "\(c.profile?.deviceCount ?? 0)")) }
        items.append(("Cert expires", shortDate(c.p12?.validTo)))
        items.append(("Profile expires", shortDate(c.profile?.expires)))
        if let at = c.check?.checkedAt { items.append(("Last checked", ago(at))) }
        return items
    }

    func card(_ c: SCert) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(c.label).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
                if c.isDefault == true { Badge(text: "Default", style: .mango) }
                Spacer()
            }
            BadgeFlow(badges: badges(c)).padding(.vertical, 10)
            KVList(items: kv(c))
            SectionTitle(text: "Profile allows").padding(.top, -8)
            BadgeFlow(badges: SignPresets.ent.map { p in Badge(text: "\(c.allows(p.key) ? "✓" : "✕") \(p.short)", style: c.allows(p.key) ? .good : .plain) })
            if c.matches == false { WarningBox(text: "This .p12 isn't listed in the provisioning profile, so signed apps won't install. Use the profile made for this certificate.", bad: true).padding(.top, 8) }
            if c.type == "App Store" { WarningBox(text: "App Store profiles can't install apps directly. Use a Development, Ad Hoc or Enterprise profile.").padding(.top, 8) }
            if c.deviceIncluded == false {
                WarningBox(text: "Your iPhone isn't in this profile, so apps signed with it won't install on it. Add your UDID to the profile in your Apple Developer account.", bad: true).padding(.top, 8)
            } else if c.deviceIncluded == nil && server.account?.udid == nil && c.type != "Enterprise" {
                Hint(text: "Link your iPhone in \(server.isOwner ? "Settings" : "Account") to check if it's in this profile.").padding(.top, 8)
            }
            HStack(spacing: 8) {
                smallBtn(checking == c.id ? "Checking…" : "Check") { check(c) }
                if c.isDefault != true { smallBtn("Make Default") { makeDefault(c) } }
                smallBtn("Rename") { newLabel = c.label; renaming = c }
                smallBtn("Delete", danger: true) { deleting = c }
            }
            .padding(.top, 14)
        }
        .padding(16)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 12)
    }

    func smallBtn(_ t: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 14, weight: .semibold)).foregroundStyle(danger ? Theme.red : Theme.text).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).padding(.vertical, 10).background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }

    func check(_ c: SCert) {
        checking = c.id
        Task {
            defer { checking = nil }
            do {
                let r = try await server.post("/api/certs/\(c.id)/check")
                let st = ((r["cert"] as? [String: Any])?["check"] as? [String: Any])?["status"] as? String
                router.say(st == "valid" ? "Certificate is valid ✓" : st == "revoked" ? "Certificate is revoked" : "Couldn't confirm status")
                await server.refresh()
            } catch { router.say(error.localizedDescription) }
        }
    }
    func makeDefault(_ c: SCert) {
        Task { do { try await server.post("/api/certs/\(c.id)", ["makeDefault": true], method: "PATCH"); await server.refresh() } catch { router.say(error.localizedDescription) } }
    }
    func rename(_ c: SCert) {
        let l = newLabel.trimmingCharacters(in: .whitespaces)
        guard !l.isEmpty else { return }
        Task { do { try await server.post("/api/certs/\(c.id)", ["label": l], method: "PATCH"); await server.refresh() } catch { router.say(error.localizedDescription) } }
    }
    func delete(_ c: SCert) {
        Task { do { _ = try await server.data("DELETE", "/api/certs/\(c.id)"); router.say("Deleted"); await server.refresh() } catch { router.say(error.localizedDescription) } }
    }
}

/// Adds a certificate to your account on the server (a .zip, or the .p12 + profile).
struct AddServerCertSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    enum Kind { case zip, p12, prov }
    @State private var picking: Kind?
    @State private var p12: URL?
    @State private var prov: URL?
    @State private var password = ""
    @State private var label = ""
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        SheetScroll {
            SheetTitle(text: "Add Certificate")
            fileButton(icon: "doc.zipper", title: "Got a .zip? Import it in one go", sub: "The .p12, profile and password are found for you", chosen: false) { picking = .zip }
            SectionTitle(text: "Or pick the files")
            fileButton(icon: "doc", title: "Certificate (.p12)", sub: p12?.lastPathComponent ?? "Tap to choose", chosen: p12 != nil) { picking = .p12 }.padding(.bottom, 12)
            fileButton(icon: "doc", title: "Provisioning profile (.mobileprovision)", sub: prov?.lastPathComponent ?? "Tap to choose", chosen: prov != nil) { picking = .prov }.padding(.bottom, 12)
            Field(label: "Password") { SecureField("Leave blank if none", text: $password).inputStyle() }
            Field(label: "Nickname") { TextField("Optional, e.g. My Dev Cert", text: $label).inputStyle() }
            WebButton(title: "Add Certificate", kind: .primary, big: true, disabled: busy) { add() }
            if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.top, 8) }
            Hint(text: "Your certificate is private to your account. Its password is stored encrypted and only used for signing.").padding(.top, 10)
        }
        .fileImporter(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }), allowedContentTypes: [.data, .zip]) { r in
            let kind = picking
            picking = nil
            guard case .success(let u) = r else { return }
            let dest = Paths.work.appendingPathComponent(String(UUID().uuidString.prefix(6)) + "-" + u.lastPathComponent)
            guard (try? copyPicked(u, to: dest)) != nil else { router.say("Couldn't open \(u.lastPathComponent)"); return }
            let ext = u.pathExtension.lowercased()
            switch kind {
            case .zip:
                guard ext == "zip" else { router.say("That's not a .zip file"); return }
                importZip(dest)
            case .p12:
                guard ext == "p12" || ext == "pfx" else { router.say("That's not a .p12 file"); return }
                p12 = dest
            case .prov:
                guard ext == "mobileprovision" else { router.say("That's not a .mobileprovision file"); return }
                prov = dest
            case nil: break
            }
        }
    }

    func fileButton(icon: String, title: String, sub: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: chosen ? "checkmark.circle.fill" : icon).font(.title3).foregroundStyle(chosen ? Theme.leaf : Theme.mango).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(sub).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(chosen ? Theme.leaf.opacity(0.5) : Theme.line, style: StrokeStyle(lineWidth: 1, dash: chosen ? [] : [5, 4])))
        }
        .buttonStyle(PressStyle())
    }

    func importZip(_ file: URL) {
        busy = true; message = "Uploading…"
        Task {
            defer { busy = false; try? FileManager.default.removeItem(at: file) }
            do {
                let id = try await server.upload(file)
                message = "Looking inside…"
                let r = try await server.post("/api/certs/zip", ["uploadId": id, "password": password, "label": label])
                let name = (r["cert"] as? [String: Any])?["label"] as? String ?? "certificate"
                router.close()
                router.say("Added \(name)\((r["passwordFound"] as? Bool) == true ? " (password found in the zip)" : "")")
                await server.refresh()
            } catch {
                message = ""
                router.say(error.localizedDescription + (error.localizedDescription.lowercased().contains("password") ? " (type it in the Password box, then import again)" : ""))
            }
        }
    }

    func add() {
        guard let p = p12, let m = prov else { router.say("Choose both files first"); return }
        busy = true; message = "Uploading…"
        Task {
            defer { busy = false }
            do {
                let pid = try await server.upload(p)
                let mid = try await server.upload(m)
                message = "Checking certificate…"
                let r = try await server.post("/api/certs", ["p12UploadId": pid, "provUploadId": mid, "password": password, "label": label])
                let name = (r["cert"] as? [String: Any])?["label"] as? String ?? "certificate"
                router.close(); router.say("Added \(name)")
                await server.refresh()
            } catch { message = ""; router.say(error.localizedDescription) }
        }
    }
}
