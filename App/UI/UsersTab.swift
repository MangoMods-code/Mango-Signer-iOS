import SwiftUI

let requestStatus: [String: (String, BadgeStyle)] = ["pending": ("⏳ Waiting", .plain), "added": ("✅ Added", .good), "declined": ("✕ Declined", .bad)]

struct RequestRow: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let r: SRequest
    var body: some View {
        let st = requestStatus[r.status] ?? requestStatus["pending"]!
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(server.isStaff ? "\(r.username ?? "?") · " : "")\(ago(r.createdAt))\(r.reply?.isEmpty == false ? " · “\(r.reply!)”" : "")")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            Badge(text: st.0, style: st.1)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { router.open(.request(r.id)) }
    }
}

struct UsersTab: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router

    var body: some View {
        let reqs = server.state?.requests ?? []
        let pending = reqs.filter { $0.status == "pending" }
        let others = Array(reqs.filter { $0.status != "pending" }.prefix(10))
        let invites = server.state?.invites ?? []
        let users = server.state?.users ?? []
        VStack(alignment: .leading, spacing: 0) {
            if !reqs.isEmpty {
                HStack(spacing: 6) {
                    SectionTitle(text: "App requests")
                    if !pending.isEmpty { Badge(text: "\(pending.count) new", style: .mango, small: true).padding(.top, 10) }
                }
                ListBox {
                    ForEach(Array((pending + others).enumerated()), id: \.element.id) { i, r in
                        if i > 0 { RowLine() }
                        RequestRow(r: r)
                    }
                }
            }
            let bugs = server.state?.bugs ?? []
            if !bugs.isEmpty {
                let open = bugs.filter { $0.status == "open" }
                HStack(spacing: 6) {
                    SectionTitle(text: "🐞 Bug reports")
                    if !open.isEmpty { Badge(text: "\(open.count) open", style: .mango, small: true).padding(.top, 10) }
                }
                ListBox {
                    let shown = open + Array(bugs.filter { $0.status != "open" }.prefix(10))
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, b in
                        if i > 0 { RowLine() }
                        BugRow(b: b)
                    }
                }
            }
            SectionTitle(text: "Invite codes")
            if invites.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Make an invite code and send it to someone so they can create an account.").foregroundStyle(Theme.muted)
                    WebButton(title: "New Invite", kind: .primary) { router.open(.newInvite) }
                }
                .padding(16).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ListBox {
                    ForEach(Array(invites.enumerated()), id: \.element.id) { i, inv in
                        if i > 0 { RowLine() }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(inv.code).font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
                                Text("\(inv.rank == "admin" ? "⭐ Admin · " : inv.rank == "tester" ? "🧪 Tester · " : "")\(inv.note?.isEmpty == false ? inv.note! : "No note") · \(inv.uses)/\(inv.maxUses) used\(inv.expiresAt != nil && !inv.expired ? " · expires \(shortDate(inv.expiresAt))" : "")")
                                    .font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                            if inv.uses >= inv.maxUses { Badge(text: "Used up") } else if inv.expired { Badge(text: "Expired") } else { Badge(text: "Active", style: .good) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .onTapGesture { router.open(.invite(inv.code)) }
                    }
                }
            }
            SectionTitle(text: "People", count: users.count)
            if users.isEmpty {
                WebEmpty(icon: "person.2", title: "No users yet", text: "Share an invite code to get started.")
            } else {
                ListBox {
                    ForEach(Array(users.enumerated()), id: \.element.id) { i, u in
                        if i > 0 { RowLine() }
                        HStack(spacing: 12) {
                            Avatar(name: u.username)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(u.username).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                                    if let r = u.rank { Badge(text: rankLabel(r), style: r == "tester" ? .blue : .mango, small: true) }
                                    if u.disabled { Badge(text: "Off", style: .bad, small: true) }
                                }
                                Text("\(u.deviceName ?? "No iPhone linked") · \(u.certCount) cert\(u.certCount == 1 ? "" : "s") · \(u.signedCount) signed").font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                                Text("Last seen \(ago(u.lastLogin).isEmpty ? "never" : ago(u.lastLogin))").font(.system(size: 13)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .onTapGesture { router.open(.user(u.id)) }
                    }
                }
            }
        }
    }
}

struct NewInviteSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    @State private var note = ""
    @State private var uses = 1
    @State private var days = 7
    @State private var rank = ""
    @State private var made: (String, String?)?

    var body: some View {
        if let made {
            InviteSheet(code: made.0, signupUrl: made.1)
        } else {
            SheetScroll {
                SheetTitle(text: "New Invite")
                Field(label: "Note") { TextField("Who it's for, e.g. Jake", text: $note).inputStyle() }
                Field(label: "How many people can use it") { SelectBox(selection: $uses, options: [1, 2, 5, 10, 25, 100].map { ($0, $0 == 1 ? "1 person" : "\($0) people") }) }
                Field(label: "Expires") { SelectBox(selection: $days, options: [(0, "Never"), (1, "In 1 day"), (7, "In 7 days"), (30, "In 30 days")]) }
                if server.isOwner {
                    Field(label: "Role for everyone who joins with it",
                          hint: rank == "tester" ? "They join as testers right away: a 🧪 badge and the apps you mark for testers. Nothing else changes for them."
                              : rank == "admin" ? "⚠️ They join as admins right away and can manage the library and users. Only use this for people you trust, and keep uses low."
                              : "They join as a regular member.") {
                        SelectBox(selection: $rank, options: [("", "Member"), ("tester", "🧪 Tester"), ("admin", "⭐ Admin")])
                    }
                }
                WebButton(title: "Create Invite", kind: .primary, big: true) {
                    Task {
                        do {
                            let r = try await server.post("/api/invites", ["note": note, "maxUses": uses, "expiresDays": days, "rank": rank])
                            await server.refresh()
                            if let code = (r["invite"] as? [String: Any])?["code"] as? String { made = (code, r["signupUrl"] as? String) }
                        } catch { router.say(error.localizedDescription) }
                    }
                }
            }
        }
    }
}

struct InviteSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let code: String
    let signupUrl: String?
    @State private var confirmDelete = false

    var body: some View {
        SheetScroll {
            let inv = server.state?.invites.first { $0.code == code }
            let link = signupUrl ?? "\(server.state?.server?.baseUrl ?? server.baseURL?.absoluteString ?? "")/?invite=\(code)"
            SheetTitle(text: inv?.note?.isEmpty == false ? "Invite for \(inv!.note!)" : "Invite code")
            Text(code).font(.system(size: 30, weight: .bold, design: .monospaced)).foregroundStyle(Theme.mango).tracking(2)
                .frame(maxWidth: .infinity).padding(.vertical, 20).background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .textSelection(.enabled)
            if let r = inv?.rank, !r.isEmpty {
                Badge(text: r == "admin" ? "Joins as ⭐ Admin" : "Joins as 🧪 Tester", style: r == "admin" ? .warn : .blue)
                    .frame(maxWidth: .infinity).padding(.top, 10)
            }
            if let inv {
                Text("\(inv.uses)/\(inv.maxUses) used\(inv.usedBy.isEmpty ? "" : " · " + inv.usedBy.joined(separator: ", "))").font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.top, 8)
            }
            VStack(spacing: 10) {
                WebButton(title: "Copy invite link", kind: .primary) { UIPasteboard.general.string = link; router.say("Invite link copied") }
                WebButton(title: "Copy code") { UIPasteboard.general.string = code; router.say("Code copied") }
                if let u = URL(string: link) {
                    ShareLink(item: u) {
                        Text("Share").font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(Theme.text).background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
                WebButton(title: "Delete invite", kind: .danger) { confirmDelete = true }
            }
            .padding(.top, 14)
            Hint(text: "The link opens the sign-up screen with the code filled in. Deleting an invite doesn't remove accounts already made with it.").padding(.top, 12)
        }
        .confirmationDialog("Delete this invite code?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    do { _ = try await server.data("DELETE", "/api/invites/\(code)"); router.close(); router.say("Invite deleted"); await server.refresh() } catch { router.say(error.localizedDescription) }
                }
            }
        }
    }
}

struct UserSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let userId: String
    @State private var resetting = false
    @State private var newPassword = ""
    @State private var confirmDelete = false

    var body: some View {
        SheetScroll {
            if let u = server.state?.users.first(where: { $0.id == userId }) {
                SheetHead(title: u.username, sub: u.disabled ? "Turned off" : "Active") {
                    Text(String(u.username.prefix(1)).uppercased()).font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.mango)
                        .frame(width: 76, height: 76).background(LinearGradient(colors: [Theme.card2, Theme.icon], startPoint: .topLeading, endPoint: .bottomTrailing)).clipShape(Circle())
                }
                KVList(items: kv(u))
                let locked = u.rank == "admin" && !server.isOwner
                if server.isOwner {
                    ListBox(fill: Theme.bg2) {
                        PickerRow(title: "Role", sub: "Admins help run the library and users. Testers get a 🧪 badge and see the apps you mark for testers.",
                                  selection: Binding(get: { u.rank ?? "" }, set: { v in setRank(u, v) }),
                                  options: [("", "Member"), ("tester", "🧪 Tester"), ("admin", "⭐ Admin")])
                    }
                    .padding(.top, 12)
                } else if let r = u.rank {
                    Hint(text: "\(rankLabel(r))\(r == "admin" ? " · only the owner can change admins" : "")").padding(.top, 10)
                }
                if !locked {
                    ListBox(fill: Theme.bg2) {
                        PickerRow(title: "Signs per day", selection: Binding(get: { u.signLimit ?? -1 }, set: { v in setLimit(u, v) }), options: limitOptions)
                    }
                    .padding(.top, 12)
                }
                if !u.recentSignins.isEmpty {
                    SectionTitle(text: "Recent sign-ins")
                    ListBox(fill: Theme.bg2) {
                        ForEach(Array(u.recentSignins.enumerated()), id: \.offset) { i, e in
                            if i > 0 { RowLine() }
                            SigninRow(e: e)
                        }
                    }
                }
                VStack(spacing: 10) {
                    if let udid = u.udid { WebButton(title: "Copy UDID") { UIPasteboard.general.string = udid; router.say("UDID copied") } }
                    if !locked {
                    WebButton(title: "Reset password") { newPassword = ""; resetting = true }
                    WebButton(title: "Sign them out everywhere") { patch(u, ["signOut": true], "\(u.username) is signed out on every device") }
                    if u.udid != nil { WebButton(title: "Unlink iPhone") { patch(u, ["unlinkDevice": true], "iPhone unlinked") } }
                    WebButton(title: u.disabled ? "Turn account on" : "Turn account off") { patch(u, ["disabled": !u.disabled], u.disabled ? "Account turned on" : "Account turned off") }
                    WebButton(title: "Delete account", kind: .danger) { confirmDelete = true }
                    }
                }
                .padding(.top, 12)
                .alert("New password for \(u.username)", isPresented: $resetting) {
                    SecureField("6+ characters", text: $newPassword)
                    Button("Reset") { patch(u, ["password": newPassword], "Password reset — they'll need to sign in again") }
                    Button("Cancel", role: .cancel) {}
                }
                .confirmationDialog("Delete \(u.username)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        Task { do { _ = try await server.data("DELETE", "/api/users/\(u.id)"); router.close(); router.say("Account deleted"); await server.refresh() } catch { router.say(error.localizedDescription) } }
                    }
                } message: { Text("Their certificates and signed apps are removed too.") }
            } else {
                WebEmpty(icon: "person.crop.circle.badge.questionmark", title: "Not found", text: "This account was removed.")
            }
        }
    }

    func kv(_ u: SUser) -> [(String, String)] {
        var items: [(String, String)] = []
        items.append(("iPhone", u.udid != nil ? "\(u.deviceName ?? "iPhone")\n\(u.udid!)" : "Not linked"))
        items.append(("Certificates", "\(u.certCount)"))
        items.append(("Signed apps", "\(u.signedCount)"))
        items.append(("Joined", shortDate(u.createdAt)))
        items.append(("Last seen", ago(u.lastLogin).isEmpty ? "never" : ago(u.lastLogin)))
        if let inv = u.invite { items.append(("Invite", inv)) }
        items.append(("Signs today", "\(u.signsToday)"))
        return items
    }

    func setRank(_ u: SUser, _ v: String) {
        Task {
            do {
                try await server.post("/api/users/\(u.id)", ["rank": v.isEmpty ? NSNull() : v], method: "PATCH")
                await server.refresh()
                router.say(v.isEmpty ? "\(u.username) is a member again" : "\(u.username) is now \(v == "admin" ? "an admin ⭐" : "a tester 🧪")")
            } catch { router.say(error.localizedDescription) }
        }
    }

    var limitOptions: [(Int, String)] {
        let everyone = server.isOwner ? (server.state?.settings?.signsPerDay ?? 0) : (server.state?.settings?.everyoneSignsPerDay ?? 0)
        return [(-1, "Everyone's limit (\(everyone > 0 ? "\(everyone)" : "none"))"), (0, "No limit"), (3, "3"), (5, "5"), (10, "10"), (20, "20"), (50, "50")]
    }

    func setLimit(_ u: SUser, _ v: Int) {
        Task {
            do { try await server.post("/api/users/\(u.id)", ["signLimit": v < 0 ? NSNull() : v], method: "PATCH"); await server.refresh(); router.say("Saved") } catch { router.say(error.localizedDescription) }
        }
    }
    func patch(_ u: SUser, _ body: [String: Any], _ msg: String) {
        Task {
            do { try await server.post("/api/users/\(u.id)", body, method: "PATCH"); router.say(msg); await server.refresh() } catch { router.say(error.localizedDescription) }
        }
    }
}

struct SigninRow: View {
    let e: SSignin
    var body: some View {
        let labels = ["login": "Signed in", "login-udid": "Signed in with iPhone", "signout-all": "Signed out other devices", "signup": "Joined", "locked": "Locked", "cert-download": "Certificate sent to the iPhone app"]
        HStack(alignment: .top, spacing: 12) {
            Text(e.ok ? (e.type == "signout-all" ? "🚪" : "✅") : "⛔").font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.ok ? (labels[e.type] ?? e.type) : (e.type == "locked" ? "Locked after wrong passwords" : "Wrong password"))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                let dev = [e.user.map { "@\($0)" } ?? "", e.device ?? "", e.ip ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                if !dev.isEmpty { Text(dev).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1) }
                Text("\(ago(e.at))\(e.ok && e.detail?.isEmpty == false ? " · \(e.detail!)" : "")").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

struct RequestSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let requestId: String
    @State private var reply = ""
    @State private var linkApp = ""
    @State private var loaded = false

    var body: some View {
        SheetScroll {
            if let r = server.state?.requests.first(where: { $0.id == requestId }) {
                let app = (server.state?.apps ?? []).first { $0.id == r.appId }
                SheetTitle(text: r.name)
                KVList(items: kv(r))
                if let n = r.note, !n.isEmpty { Text(n).font(.system(size: 15)).foregroundStyle(Theme.soft).padding(.vertical, 6) }
                if let rep = r.reply, !rep.isEmpty {
                    Text("💬 \(rep)").font(.subheadline).foregroundStyle(Theme.soft).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.mango.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if let app { WebButton(title: "Open \(app.name)", kind: .primary) { router.open(.app(app.id)) }.padding(.top, 8) }
                if server.isStaff {
                    Field(label: "Reply (optional)") { TextField("e.g. Added! Turn on JIT first", text: $reply).inputStyle() }.padding(.top, 12)
                    Field(label: "Link it to a library app (optional)") {
                        SelectBox(selection: $linkApp, options: [("", "—")] + (server.state?.apps ?? []).map { ($0.id, $0.name) })
                    }
                    HStack(spacing: 8) {
                        WebButton(title: "✅ Mark added") { set(r, "added") }
                        WebButton(title: "✕ Decline") { set(r, "declined") }
                    }
                }
                if server.isStaff || r.status == "pending" {
                    WebButton(title: "Delete request", kind: .danger) {
                        Task { do { _ = try await server.data("DELETE", "/api/requests/\(r.id)"); await server.refresh(); router.say("Deleted"); router.close() } catch { router.say(error.localizedDescription) } }
                    }
                    .padding(.top, 8)
                }
                Color.clear.frame(height: 0).onAppear { if !loaded { reply = r.reply ?? ""; linkApp = r.appId ?? ""; loaded = true } }
            }
        }
    }

    func kv(_ r: SRequest) -> [(String, String)] {
        var items: [(String, String)] = []
        if server.isStaff { items.append(("From", r.username ?? "?")) }
        items.append(("Asked", ago(r.createdAt)))
        items.append(("Status", requestStatus[r.status]?.0 ?? r.status))
        if let l = r.link, !l.isEmpty { items.append(("Link", l)) }
        return items
    }

    func set(_ r: SRequest, _ status: String) {
        Task {
            do {
                try await server.post("/api/requests/\(r.id)", ["status": status, "reply": reply, "appId": linkApp], method: "PATCH")
                await server.refresh(); router.say(status == "added" ? "Marked as added" : "Declined"); router.close()
            } catch { router.say(error.localizedDescription) }
        }
    }
}


func rankLabel(_ r: String) -> String { r == "admin" ? "⭐ Admin" : r == "tester" ? "🧪 Tester" : r }

// MARK: - Bug reports (testers and admins send them; you and admins answer)

let bugStatus: [String: (String, BadgeStyle)] = ["open": ("🐞 Open", .plain), "fixed": ("✅ Fixed", .good), "wontfix": ("✕ Won't fix", .bad)]

struct BugRow: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let b: SBug
    var body: some View {
        let st = bugStatus[b.status] ?? bugStatus["open"]!
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(b.appName ?? "General").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(server.isStaff ? "\(b.username ?? "?") · " : "")\(ago(b.createdAt)) · \(b.text.split(separator: "\n").first.map(String.init) ?? "")")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            Badge(text: st.0, style: st.1)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { router.open(.bug(b.id)) }
    }
}

struct ReportBugSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let appId: String?
    @State private var app = ""
    @State private var text = ""
    @State private var busy = false
    @State private var loaded = false
    var body: some View {
        SheetScroll {
            SheetTitle(text: "🐞 Report a bug")
            Hint(text: "It goes straight to the owner\(server.isAdmin ? "" : " and admins"). Say what you did and what went wrong.").padding(.bottom, 12)
            Field(label: "App") {
                SelectBox(selection: $app, options: [("", "Mango Signer itself / general")] + (server.state?.apps ?? []).map { ($0.id, $0.name) })
            }
            Field(label: "What happened?") {
                TextField("e.g. Crashes when I open the settings page", text: $text, axis: .vertical).lineLimit(4...10).inputStyle()
            }
            WebButton(title: busy ? "Sending…" : "Send Report", kind: .primary, big: true, disabled: busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                busy = true
                Task {
                    defer { busy = false }
                    do {
                        try await server.post("/api/bugs", ["text": text, "appId": app.isEmpty ? NSNull() : app])
                        await server.refresh(); router.close(); router.say("Thanks! Report sent 🐞")
                    } catch { router.say(error.localizedDescription) }
                }
            }
        }
        .onAppear { if !loaded { app = appId ?? ""; loaded = true } }
    }
}

struct BugSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let bugId: String
    @State private var reply = ""
    @State private var loaded = false
    var body: some View {
        SheetScroll {
            if let b = server.state?.bugs.first(where: { $0.id == bugId }) {
                SheetTitle(text: "🐞 \(b.appName ?? "General")")
                KVList(items: kv(b))
                Text(b.text).font(.system(size: 15)).foregroundStyle(Theme.soft).textSelection(.enabled).padding(.vertical, 6)
                if let r = b.reply, !r.isEmpty {
                    Text("💬 \(r)").font(.subheadline).foregroundStyle(Theme.soft).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.mango.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if let id = b.appId, server.app(id) != nil { WebButton(title: "Open \(b.appName ?? "app")") { router.open(.app(id)) }.padding(.top, 8) }
                if server.isStaff {
                    Field(label: "Reply (optional)") { TextField("e.g. Fixed in the next version", text: $reply).inputStyle() }.padding(.top, 12)
                    HStack(spacing: 8) {
                        WebButton(title: "✅ Fixed") { set(b, "fixed") }
                        WebButton(title: "✕ Won't fix") { set(b, "wontfix") }
                        WebButton(title: "Reopen") { set(b, "open") }
                    }
                }
                WebButton(title: "Delete report", kind: .danger) {
                    Task { do { _ = try await server.data("DELETE", "/api/bugs/\(b.id)"); await server.refresh(); router.say("Deleted"); router.close() } catch { router.say(error.localizedDescription) } }
                }
                .padding(.top, 8)
                Color.clear.frame(height: 0).onAppear { if !loaded { reply = b.reply ?? ""; loaded = true } }
            } else {
                WebEmpty(icon: "ladybug", title: "Not found", text: "This report was deleted.")
            }
        }
    }
    func kv(_ b: SBug) -> [(String, String)] {
        var items: [(String, String)] = []
        if server.isStaff { items.append(("From", b.username ?? "?")) }
        items.append(("Sent", ago(b.createdAt)))
        items.append(("Status", bugStatus[b.status]?.0 ?? b.status))
        if let d = b.device, !d.isEmpty { items.append(("Device", d)) }
        return items
    }
    func set(_ b: SBug, _ status: String) {
        Task {
            do { try await server.post("/api/bugs/\(b.id)", ["status": status, "reply": reply], method: "PATCH"); await server.refresh(); router.say("Saved"); router.close() } catch { router.say(error.localizedDescription) }
        }
    }
}
