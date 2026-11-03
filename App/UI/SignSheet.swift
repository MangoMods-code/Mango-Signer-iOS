import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins

/// The same one-tap settings the website offers.
enum SignPresets {
    struct P { let key: String; let label: String; let short: String; let sub: String }
    static let ent = [
        P(key: "get-task-allow", label: "JIT support", short: "JIT", sub: "Lets StikDebug and other JIT tools attach to the app"),
        P(key: "com.apple.developer.kernel.increased-memory-limit", label: "Increased memory limit", short: "More RAM", sub: "GetMoreRam — more RAM for emulators and games"),
        P(key: "com.apple.developer.kernel.extended-virtual-addressing", label: "Extended virtual addressing", short: "Extended VA", sub: "Bigger memory space, used by some emulators"),
    ]
    static let plist = [
        P(key: "CADisableMinimumFrameDurationOnPhone", label: "120Hz ProMotion", short: "120Hz", sub: "Unlocks 120fps on ProMotion iPhones"),
        P(key: "GCSupportsGameMode", label: "Game Mode", short: "Game Mode", sub: "Lower latency for controllers and AirPods"),
        P(key: "UIRequiresFullScreen", label: "Require full screen", short: "Full screen", sub: "Turns off iPad split view for the app"),
    ]
}

// MARK: - Sign with options

struct SignSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var router: Router
    let appId: String
    let presetId: String?

    enum Place: Hashable { case server, phone }
    @State private var place: Place = .server
    @State private var certId = ""
    @State private var localCertId: UUID?
    @State private var versionIndex = 0
    @State private var more = false
    @State private var name = ""
    @State private var bundleId = ""
    @State private var version = ""
    @State private var minOS = ""
    @State private var ent: [String: Bool] = [:]
    @State private var plist: [String: Bool] = [:]
    @State private var customEnt: [EditRow] = []
    @State private var customPlist: [EditRow] = []
    @State private var removeExtensions = false
    @State private var removeWatch = true
    @State private var removeUISD = false
    @State private var enableDocs = false
    @State private var tweakIds: Set<String> = []
    @State private var dylibs: [URL] = []
    @State private var weak = false
    @State private var injectExt = false
    @State private var icon: URL?
    @State private var iconItem: PhotosPickerItem?
    @State private var pickingDylib = false
    @State private var savingPreset = false
    @State private var presetName = ""
    @State private var ready = false

    var app: SApp? { server.state?.apps.first { $0.id == appId } }
    var certs: [SCert] { server.certs }
    var cert: SCert? { certs.first { $0.id == certId } ?? server.defaultCert }
    var presets: [SPreset] { server.state?.presets ?? [] }
    var defaults: SignDefaults {
        if let p = presets.first(where: { $0.id == presetId }) { return p.options }
        return app?.signDefaults ?? SignDefaults()
    }

    var body: some View {
        if let a = app {
            SheetScroll { form(a) }
                .onAppear { if !ready { load(a); ready = true } }
                .onChange(of: iconItem) { item in loadIcon(item) }
                .fileImporter(isPresented: $pickingDylib, allowedContentTypes: [.data], allowsMultipleSelection: true) { r in
                    guard case .success(let urls) = r else { return }
                    for u in urls {
                        let ext = u.pathExtension.lowercased()
                        guard ext == "dylib" || ext == "deb" else { router.say("\(u.lastPathComponent) isn't a .dylib or .deb"); continue }
                        let dest = Paths.work.appendingPathComponent(String(UUID().uuidString.prefix(6)) + "-" + u.lastPathComponent)
                        if (try? copyPicked(u, to: dest)) != nil { dylibs.append(dest) }
                    }
                }
                .alert("Name this preset", isPresented: $savingPreset) {
                    TextField("Preset name", text: $presetName)
                    Button("Save") { savePreset() }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Using an existing name updates it.") }
        } else {
            SheetScroll { WebEmpty(icon: "questionmark.app", title: "Not in the library", text: "That app is no longer in the library.") }
        }
    }

    func load(_ a: SApp) {
        let d = defaults
        certId = server.defaultCert?.id ?? ""
        localCertId = local.defaultCert?.id
        if certs.isEmpty && !local.certs.isEmpty { place = .phone }
        versionIndex = min(d.versionIndex, max(0, (a.versions?.count ?? 1) - 1))
        minOS = d.minOS
        for p in SignPresets.ent { ent[p.key] = d.entitlements.contains { $0.key == p.key } }
        for p in SignPresets.plist { plist[p.key] = d.plist.contains { $0.key == p.key } }
        customEnt = d.entitlements.filter { e in !SignPresets.ent.contains { $0.key == e.key } }
        customPlist = d.plist.filter { e in !SignPresets.plist.contains { $0.key == e.key } }
        removeExtensions = d.removeExtensions
        removeWatch = d.removeWatch ?? true
        removeUISD = d.removeUISD
        enableDocs = d.enableDocs
        weak = d.weakDylibs
        injectExt = d.injectExtensions
        tweakIds = Set(d.tweakIds.filter { tid in (server.state?.tweaks ?? []).contains { $0.id == tid } })
        if let c = cert, c.profile?.wildcard == false, let appId = c.profile?.appId, !appId.isEmpty { bundleId = appId }
    }

    @ViewBuilder
    func form(_ a: SApp) -> some View {
        let summary = defaultsSummary(defaults, server)
        SheetHead(title: "Sign \(a.name)", sub: "\(a.shownVersion) · \(formatBytes(a.size))") { AppIconImage(app: a, size: 76) }

        if !local.certs.isEmpty {
            Picker("Where", selection: $place) {
                Text("Sign on server").tag(Place.server)
                Text("Sign on this iPhone").tag(Place.phone)
            }
            .pickerStyle(.segmented).padding(.bottom, 14)
        }

        if place == .server {
            Field(label: "Certificate", hint: certHint) {
                SelectBox(selection: $certId, options: certs.map { ($0.id, "\($0.label) · \($0.type)") })
            }
        } else {
            Field(label: "Certificate on this iPhone", hint: "The app downloads to this iPhone and is signed here.") {
                SelectBox(selection: Binding(get: { localCertId ?? UUID() }, set: { localCertId = $0 }),
                          options: local.certs.map { ($0.id, "\($0.label)\($0.daysLeft.map { $0 < 0 ? " · expired" : " · \($0)d left" } ?? "")") })
            }
        }
        if let versions = a.versions, versions.count > 1 {
            Field(label: "App version") {
                SelectBox(selection: $versionIndex, options: versions.enumerated().map { i, v in
                    (i, "\(v.version ?? "Version \(i + 1)")\(i == 0 ? " (newest)" : "")\(v.date.map { " · " + String($0.prefix(10)) } ?? "")")
                })
            }
        }
        if !presets.isEmpty {
            Field(label: "Preset") {
                SelectBox(selection: Binding(get: { presetId ?? "" }, set: { router.open(.sign(a.id, presetId: $0.isEmpty ? nil : $0)) }),
                          options: [("", presetId != nil ? "App defaults" : "None (app defaults)")] + presets.map { ($0.id, $0.name) })
            }
        }
        if !summary.isEmpty {
            Text("✨ \(presetId != nil ? "From your preset" : "Set up for you"): \(summary.joined(separator: " · "))")
                .font(.subheadline).foregroundStyle(Theme.soft).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.mango.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).padding(.bottom, 12)
        }
        if place == .server && (server.state?.signed ?? []).contains(where: { $0.appId == a.id }) {
            Hint(text: "This replaces your current signed copy of this app.", center: true).padding(.bottom, 10)
        }
        WebButton(title: "Sign App", kind: .primary, big: true, disabled: place == .server ? certs.isEmpty : localCertId == nil) { go(a) }
        LinkButton(title: more ? "Fewer options ▴" : "More options ▾") { withAnimation(.easeOut(duration: 0.2)) { more.toggle() } }

        if more { advanced(a) }
    }

    var certHint: String {
        guard let c = cert else { return "" }
        var bits: [String] = []
        if c.check?.status == "revoked" { bits.append("⚠️ This certificate is revoked, so apps won't open.") }
        if let left = c.daysLeft { bits.append(left < 0 ? "⚠️ This certificate has expired." : "Expires in \(left) days.") }
        if c.deviceIncluded == false { bits.append("⚠️ Your iPhone isn't in this profile.") }
        if c.profile?.wildcard == false, let id = c.profile?.appId, !id.isEmpty { bits.append("This profile only signs \(id).") }
        let blocked = SignPresets.ent.filter { ent[$0.key] == true && !c.allows($0.key) }.map { $0.short }
        if !blocked.isEmpty { bits.append("⚠️ This profile doesn't allow \(blocked.joined(separator: ", ")) — open More options to turn it off, or the app may not install.") }
        return bits.joined(separator: " ")
    }

    @ViewBuilder
    func advanced(_ a: SApp) -> some View {
        SectionTitle(text: "App details")
        Field(label: "Name") { TextField(a.name, text: $name).inputStyle() }
        Field(label: "Bundle ID", hint: "Change it to install a second copy next to the original.") { TextField(a.bundleId ?? "", text: $bundleId).plainInput().inputStyle() }
        Field(label: "Version") { TextField(a.shownVersion, text: $version).plainInput().inputStyle() }
        Field(label: "Minimum iOS") { TextField(a.minOS?.isEmpty == false ? a.minOS! : "unchanged", text: $minOS).keyboardType(.decimalPad).inputStyle() }

        SectionTitle(text: "Icon")
        PhotosPicker(selection: $iconItem, matching: .images) {
            fileButton(icon: "photo", title: "Change icon", sub: icon != nil ? "New icon chosen" : (a.customIcon == true && a.useIconWhenSigning != false ? "Using the library's custom icon" : "Optional · square image"), chosen: icon != nil)
        }
        .buttonStyle(.plain)

        SectionTitle(text: "Entitlements")
        ListBox(fill: Theme.bg2) {
            ForEach(Array(SignPresets.ent.enumerated()), id: \.offset) { i, p in
                if i > 0 { RowLine() }
                ToggleRow(title: p.label, sub: p.sub, isOn: Binding(get: { ent[p.key] ?? false }, set: { ent[p.key] = $0 }),
                          warning: place == .server && ent[p.key] == true && cert.map { !$0.allows(p.key) } == true
                            ? "Your profile doesn't allow this, so the app may not install. Turn on this capability for your App ID in your Apple Developer account." : nil)
            }
        }
        editorRows($customEnt, kind: "ent")
        addKeyButton("+ Add custom entitlement") { customEnt.append(EditRow()) }

        SectionTitle(text: "Info.plist")
        if place == .phone { Hint(text: "Info.plist changes only work when signing on the server.").padding(.bottom, 6) }
        ListBox(fill: Theme.bg2) {
            ForEach(Array(SignPresets.plist.enumerated()), id: \.offset) { i, p in
                if i > 0 { RowLine() }
                ToggleRow(title: p.label, sub: p.sub, isOn: Binding(get: { plist[p.key] ?? false }, set: { plist[p.key] = $0 }))
            }
        }
        .opacity(place == .phone ? 0.5 : 1)
        editorRows($customPlist, kind: "plist")
        addKeyButton("+ Add Info.plist key") { customPlist.append(EditRow()) }

        SectionTitle(text: "Options")
        ListBox(fill: Theme.bg2) {
            ToggleRow(title: "Remove extensions", sub: "Fixes installs on profiles without matching App IDs", isOn: $removeExtensions)
            RowLine()
            ToggleRow(title: "Remove Watch app", sub: "Smaller install, avoids Watch signing errors", isOn: $removeWatch)
            RowLine()
            ToggleRow(title: "Remove device limits", sub: "Lets apps install on devices they weren't built for", isOn: $removeUISD)
            RowLine()
            ToggleRow(title: "Show in Files app", sub: "Turns on file sharing and document browser", isOn: $enableDocs)
        }

        SectionTitle(text: "Tweaks")
        let tweaks = server.state?.tweaks ?? []
        if !tweaks.isEmpty {
            if place == .phone { Hint(text: "Tweaks from the library only work when signing on the server.").padding(.bottom, 6) }
            ListBox(fill: Theme.bg2) {
                ForEach(Array(tweaks.enumerated()), id: \.element.id) { i, t in
                    if i > 0 { RowLine() }
                    ToggleRow(title: "🧩 \(t.name)\(t.version.map { " " + $0 } ?? "")",
                              sub: t.description.flatMap { $0.split(separator: "\n").first.map { String($0.prefix(90)) } } ?? (t.warnings.first.map { "⚠️ " + $0 } ?? "\(t.files.count) file\(t.files.count == 1 ? "" : "s")"),
                              isOn: Binding(get: { tweakIds.contains(t.id) }, set: { if $0 { tweakIds.insert(t.id) } else { tweakIds.remove(t.id) } }))
                }
            }
            .opacity(place == .phone ? 0.5 : 1)
            .padding(.bottom, 10)
        }
        Button { pickingDylib = true } label: {
            fileButton(icon: "plus", title: "Add your own .dylib or .deb", sub: place == .phone ? ".dylib only when signing on this iPhone" : "Jailbreak tweaks work too — Mango pulls the tweak out of the .deb", chosen: false)
        }
        .buttonStyle(.plain)
        if !dylibs.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(Array(dylibs.enumerated()), id: \.offset) { i, u in
                    HStack(spacing: 6) {
                        Text(u.lastPathComponent.split(separator: "-", maxSplits: 1).last.map(String.init) ?? u.lastPathComponent).font(.system(size: 13, weight: .semibold))
                        Button { dylibs.remove(at: i) } label: { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                    }
                    .foregroundStyle(Theme.text).padding(.horizontal, 10).padding(.vertical, 6).background(Theme.card2).clipShape(Capsule())
                }
            }
            .padding(.top, 8)
        }
        ListBox(fill: Theme.bg2) {
            ToggleRow(title: "Weak injection", sub: "App still opens if a tweak fails to load", isOn: $weak)
            RowLine()
            ToggleRow(title: "Inject into extensions", sub: "Also load tweaks in widgets and share extensions", isOn: $injectExt)
        }
        .padding(.top, 10)

        WebButton(title: "Sign App", kind: .primary, big: true, disabled: place == .server ? certs.isEmpty : localCertId == nil) { go(a) }.padding(.top, 16)
        LinkButton(title: "💾 Save these settings as a preset") {
            presetName = presets.first { $0.id == presetId }?.name ?? ""
            savingPreset = true
        }
    }

    func fileButton(icon: String, title: String, sub: String, chosen: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: chosen ? "checkmark.circle.fill" : icon).font(.title3).foregroundStyle(chosen ? Theme.leaf : Theme.mango).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                Text(sub).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(chosen ? Theme.leaf.opacity(0.5) : Theme.line, style: StrokeStyle(lineWidth: 1, dash: chosen ? [] : [5, 4])))
    }

    func addKeyButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mango)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .padding(.top, 8)
    }

    @ViewBuilder
    func editorRows(_ rows: Binding<[EditRow]>, kind: String) -> some View {
        ForEach(rows) { $row in
            VStack(spacing: 8) {
                TextField(kind == "plist" ? "Info.plist key, e.g. UIFileSharingEnabled" : "Entitlement, e.g. com.apple.developer.…", text: $row.key)
                    .plainInput().inputStyle()
                HStack(spacing: 8) {
                    Menu {
                        ForEach(kind == "plist" ? [("bool", "Yes / No"), ("string", "Text"), ("number", "Number"), ("delete", "Remove key")] : [("bool", "Yes / No"), ("string", "Text")], id: \.0) { k, l in
                            Button(l) { row.type = k }
                        }
                    } label: {
                        Text(["bool": "Yes / No", "string": "Text", "number": "Number", "delete": "Remove key"][row.type] ?? row.type)
                            .foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading).inputStyle()
                    }
                    Group {
                        switch row.type {
                        case "bool":
                            Menu {
                                Button("YES") { row.boolValue = true }
                                Button("NO") { row.boolValue = false }
                            } label: { Text(row.boolValue ? "YES" : "NO").foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading).inputStyle() }
                        case "delete":
                            Text("Key will be removed").font(.caption).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                        default:
                            TextField("Value", text: $row.textValue).plainInput().keyboardType(row.type == "number" ? .decimalPad : .default).inputStyle()
                        }
                    }
                    Button { rows.wrappedValue.removeAll { $0.id == row.id } } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(Theme.muted).frame(width: 40, height: 44)
                    }
                }
            }
            .padding(10).background(Theme.bg2.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 8)
        }
    }

    func loadIcon(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data), let png = img.pngData() else {
                router.say("Couldn't open that picture"); return
            }
            let u = Paths.work.appendingPathComponent("icon-\(UUID().uuidString.prefix(6)).png")
            do { try png.write(to: u); icon = u } catch { router.say(error.localizedDescription) }
        }
    }

    var entRows: [EditRow] {
        SignPresets.ent.filter { ent[$0.key] == true }.map { EditRow(key: $0.key) } + customEnt.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    var plistRows: [EditRow] {
        SignPresets.plist.filter { plist[$0.key] == true }.map { EditRow(key: $0.key) } + customPlist.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var formOptions: [String: Any] {
        [
            "minOS": minOS.trimmingCharacters(in: .whitespaces), "entitlements": entRows.map { $0.json }, "plist": plistRows.map { $0.json },
            "weakDylibs": weak, "injectExtensions": injectExt, "removeExtensions": removeExtensions, "removeWatch": removeWatch,
            "removeUISD": removeUISD, "enableDocs": enableDocs, "tweakIds": Array(tweakIds),
        ]
    }

    func go(_ a: SApp) {
        if place == .phone {
            guard let cid = localCertId else { return }
            var o = SignOptions()
            o.name = name.trimmingCharacters(in: .whitespaces)
            o.bundleId = bundleId.trimmingCharacters(in: .whitespaces)
            o.version = version.trimmingCharacters(in: .whitespaces)
            o.minOS = minOS.trimmingCharacters(in: .whitespaces)
            o.icon = icon
            o.removeExtensions = removeExtensions; o.removeWatch = removeWatch; o.removeDeviceLimits = removeUISD; o.fileSharing = enableDocs
            o.dylibs = dylibs.filter { $0.pathExtension.lowercased() == "dylib" }
            o.weakDylibs = weak; o.injectExtensions = injectExt
            o.entitlementEdits = entRows.map { r in
                switch r.type {
                case "delete": return (r.key, nil)
                case "string": return (r.key, r.textValue)
                case "number": return (r.key, Double(r.textValue) ?? 0)
                default: return (r.key, r.boolValue)
                }
            }
            router.open(.signing(SignRun(app: a, body: ["versionIndex": versionIndex], local: .init(certId: cid, options: o))))
            return
        }
        var body = formOptions
        body["appId"] = a.id
        body["certId"] = certId
        body["name"] = name.trimmingCharacters(in: .whitespaces)
        body["bundleId"] = bundleId.trimmingCharacters(in: .whitespaces)
        body["version"] = version.trimmingCharacters(in: .whitespaces)
        body["versionIndex"] = versionIndex
        router.open(.signing(SignRun(app: a, body: body, icon: icon, dylibs: dylibs)))
    }

    func savePreset() {
        let n = presetName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        Task {
            do {
                let r = try await server.post("/api/presets", ["name": n, "options": formOptions])
                await server.refresh()
                router.say((r["replaced"] as? Bool) == true ? "Updated “\(n)”" : "Saved “\(n)”")
            } catch { router.say(error.localizedDescription) }
        }
    }
}

// MARK: - Signing in progress

struct SigningSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var router: Router
    let run: SignRun

    @State private var title = "Getting ready…"
    @State private var sub = "Keep this screen open"
    @State private var progress: Double?
    @State private var log: [String] = []
    @State private var failure: String?
    @State private var jobId: String?
    @State private var started = false

    var body: some View {
        SheetScroll {
            VStack(spacing: 10) {
                AppIconImage(app: run.app, size: 76).padding(.top, 4)
                if let failure {
                    Text("Signing failed").font(.title2.bold()).foregroundStyle(Theme.text)
                    WarningBox(text: failure, bad: true)
                    logBox
                    WebButton(title: "Try Again", kind: .primary) { router.open(.sign(run.app.id, presetId: nil)) }.padding(.top, 8)
                    WebButton(title: "Close") { router.close() }
                } else {
                    ProgressView().controlSize(.large).tint(Theme.mango).padding(.vertical, 6)
                    Text(title).font(.title3.bold()).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                    Text(sub).font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    if let progress { ProgressView(value: progress).tint(Theme.mango).padding(.horizontal, 8) }
                    logBox
                    WebButton(title: run.local == nil ? "Cancel signing" : "Cancel") { cancel() }.padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            guard !started else { return }
            started = true
            router.locked = true
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            do {
                if run.local != nil { try await signHere() } else { try await signOnServer() }
            } catch {
                router.locked = false
                if Task.isCancelled || error is CancellationError { return }
                failure = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    var logBox: some View {
        if !log.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(log.joined(separator: "\n")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10).textSelection(.enabled)
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxHeight: 180)
                .background(Theme.bg).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onChange(of: log.count) { _ in proxy.scrollTo("end") }
            }
        }
    }

    func cancel() {
        if let jobId { Task { _ = try? await server.post("/api/jobs/\(jobId)/cancel") } }
        router.close()
        router.say("Signing cancelled")
    }

    func signOnServer() async throws {
        var body = run.body
        if let icon = run.icon {
            title = "Uploading icon…"
            let iconId = try await server.upload(icon)
            body["iconUploadId"] = iconId
        }
        var ds: [[String: Any]] = []
        for (i, d) in run.dylibs.enumerated() {
            let shown = d.lastPathComponent.split(separator: "-", maxSplits: 1).last.map(String.init) ?? d.lastPathComponent
            title = "Uploading tweak \(i + 1) of \(run.dylibs.count)…"; sub = shown
            let uploadId = try await server.upload(d)
            ds.append(["uploadId": uploadId, "name": shown])
        }
        body["dylibs"] = ds
        title = "Signing…"; sub = "Big apps can take a minute"
        let r = try await server.post("/api/sign", body)
        guard let id = r["jobId"] as? String else { throw MangoError("The server didn't start signing. Try again.") }
        jobId = id
        while true {
            try Task.checkCancellation()
            let j: JobStatus = try await server.get("/api/jobs/\(id)")
            if j.status == "queued" { title = "Waiting in line…"; sub = "Someone else is signing right now" }
            else { title = "Signing…"; sub = "Big apps can take a minute" }
            progress = j.progress
            if let l = j.log, !l.isEmpty { log = l }
            switch j.status {
            case "done":
                guard let s = j.result?.signed else { throw MangoError("Signing finished but the server didn't send the app back.") }
                router.signedCache[s.id] = s
                router.locked = false
                await server.refresh()
                let jit = ((run.body["entitlements"] as? [[String: Any]]) ?? []).contains { ($0["key"] as? String) == "get-task-allow" }
                router.open(.ready(s.id, jit: jit))
                return
            case "error", "cancelled":
                throw MangoError(j.error ?? "Signing stopped.")
            default:
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func signHere() async throws {
        guard let plan = run.local, let cert = local.certs.first(where: { $0.id == plan.certId }) else { throw MangoError("Pick a certificate on this iPhone.") }
        let vi = (run.body["versionIndex"] as? Int) ?? 0
        title = "Downloading \(run.app.name)…"; sub = "Keep this screen open"; progress = 0
        let file = try await server.downloadIPA(run.app, versionIndex: vi) { p in progress = p }
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        title = "Signing on this iPhone…"; sub = "Big apps can take a minute"; progress = nil
        var iconData: Data?
        if let u = server.iconURL(run.app) { iconData = await ImageCache.shared.image(u)?.pngData() }
        let version = vi == 0 ? run.app.shownVersion : (run.app.versions?[safe: vi]?.version ?? run.app.shownVersion)
        let s = try await local.signFile(file, name: run.app.name, bundleId: run.app.bundleId ?? "", version: version,
                                         icon: iconData, with: cert, options: plan.options)
        router.locked = false
        router.open(.readyLocal(s.id))
    }
}

// MARK: - Ready to install

struct ReadySheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let signedId: String
    let jit: Bool

    var body: some View {
        SheetScroll {
            if let s = router.signed(signedId, server) {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.onAccent)
                        .frame(width: 72, height: 72).background(Theme.leaf).clipShape(Circle()).padding(.top, 6)
                    Text("Ready to install").font(.title2.bold()).foregroundStyle(Theme.text)
                    Text("\(s.name) \(s.version ?? "") · \(formatBytes(s.size))").font(.footnote).foregroundStyle(Theme.muted)
                    if !server.https { WarningBox(text: "Install needs HTTPS. Generate a Railway domain and open the app from it.", bad: true) }
                    VStack(spacing: 10) {
                        WebButton(title: "Install", kind: .primary, big: true) { router.startInstall(s, server: server) }
                        if let share = s.shareUrl {
                            WebButton(title: "Copy install link") { UIPasteboard.general.string = share; router.say("Install link copied") }
                            WebButton(title: "Show QR code") { router.open(.qr(title: "Install \(s.name)", url: share)) }
                        }
                        WebButton(title: "Done") { router.go(.signed) }
                    }
                    .padding(.top, 14)
                    if jit { WarningBox(text: "JIT is allowed for this app. Open StikDebug (or your JIT tool) and turn on JIT for it each time you launch it.") }
                    Hint(text: "After tapping Install, go to your home screen to watch it download. For enterprise certs you may need to trust it in Settings › General › VPN & Device Management.").padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct ReadyLocalSheet: View {
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var router: Router
    let signedId: UUID
    var body: some View {
        SheetScroll {
            if let s = local.signed.first(where: { $0.id == signedId }) {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.onAccent)
                        .frame(width: 72, height: 72).background(Theme.leaf).clipShape(Circle()).padding(.top, 6)
                    Text("Signed on this iPhone").font(.title2.bold()).foregroundStyle(Theme.text)
                    Text("\(s.name) \(s.version) · \(formatSize(s.size)) · \(s.certLabel)").font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    ShareLink(item: s.url) {
                        Text("Share .ipa").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 16)
                            .foregroundStyle(Theme.onAccent).background(Theme.gradient).clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .padding(.top, 14)
                    WebButton(title: "Done") { router.go(.signed) }
                    Hint(text: "It's saved in Files › On My iPhone › Mango Signer › Signed. Share it to an installer app, or open it from Files.", center: true).padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Install progress

struct InstallSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let signedId: String
    @State private var st: InstallStatus?

    var body: some View {
        SheetScroll {
            if let s = router.signed(signedId, server) {
                VStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(Theme.card2, lineWidth: 8)
                        Circle().trim(from: 0, to: phase == "done" ? 1 : max(0.02, st?.progress ?? 0))
                            .stroke(phase == "done" ? Theme.leaf : Theme.mango, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.4), value: st?.progress)
                        WebIcon(url: server.iconURL(s), name: s.name, size: 72)
                    }
                    .frame(width: 124, height: 124).padding(.top, 8)
                    Text(s.name).font(.title3.bold()).foregroundStyle(Theme.text)
                    Group {
                        switch phase {
                        case "confirm": Text("Tap Install on the pop-up").foregroundStyle(Theme.mango)
                        case "downloading":
                            Text("Installing… \(Int(((st?.progress ?? 0) * 100).rounded()))%\(st?.size.map { " of \(formatBytes($0))" } ?? "")").foregroundStyle(Theme.text)
                        case "done": Text("✓ Sent to your iPhone — check your home screen").foregroundStyle(Theme.leaf)
                        default: Text("Waiting for your iPhone…").foregroundStyle(Theme.muted)
                        }
                    }
                    .font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                    VStack(spacing: 10) {
                        WebButton(title: "Show the pop-up again") { if let iu = s.installUrl, let u = URL(string: iu) { UIApplication.shared.open(u) } }
                        WebButton(title: phase == "done" ? "Done" : "Close", kind: phase == "done" ? .primary : .normal) { router.close() }
                    }
                    .padding(.top, 8)
                    Hint(text: "Nothing happening? Check your home screen — the app shows up there while it downloads. Enterprise certificates may need trusting in Settings › General › VPN & Device Management.", center: true)
                }
                .frame(maxWidth: .infinity)
                .task {
                    struct R: Decodable { var install: InstallStatus }
                    for _ in 0..<600 {
                        if Task.isCancelled { return }
                        if let r: R = try? await server.get("/api/signed/\(s.id)/install") {
                            st = r.install
                            if r.install.phase == "done" { await server.refresh(); return }
                        }
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            }
        }
    }

    var phase: String { st?.phase ?? "waiting" }
}

// MARK: - QR code

struct QRSheet: View {
    @EnvironmentObject var router: Router
    let title: String
    let url: String

    var image: UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(url.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    var body: some View {
        SheetScroll {
            SheetTitle(text: title)
            if let image {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                    .padding(16).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: 280).frame(maxWidth: .infinity)
            }
            Text(url).font(.caption.monospaced()).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 10).textSelection(.enabled)
            VStack(spacing: 10) {
                WebButton(title: "Copy link", kind: .primary) { UIPasteboard.general.string = url; router.say("Link copied") }
                if let u = URL(string: url) {
                    ShareLink(item: u) {
                        Text("Share").font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(Theme.text).background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
            }
            .padding(.top, 14)
            Hint(text: "Scan it with another iPhone's camera to install there.", center: true).padding(.top, 8)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
