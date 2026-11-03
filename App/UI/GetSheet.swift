import SwiftUI
import UIKit

/// "Get": sign an app from the library, either on the server (then install over the air)
/// or right here on the iPhone with a certificate saved on this iPhone.
struct GetSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @Environment(\.dismiss) private var dismiss
    let app: SApp
    let versionIndex: Int

    enum Place: String { case server, phone }
    enum Stage: Equatable { case setup, working, signed, failed }

    @State private var place: Place = .server
    @State private var certId: String = ""
    @State private var localCertId: UUID?
    @State private var showOptions = false
    @State private var name = ""
    @State private var bundleId = ""
    @State private var version = ""

    @State private var stage: Stage = .setup
    @State private var status = ""
    @State private var progress: Double?
    @State private var error = ""
    @State private var signed: SSigned?
    @State private var localSigned: SignedApp?
    @State private var install: InstallStatus?
    @State private var worker: Task<Void, Never>?

    var certs: [SCert] { server.state?.certs ?? [] }
    var versionLabel: String {
        if versionIndex == 0 { return app.shownVersion }
        return app.versions?[safe: versionIndex]?.version ?? app.shownVersion
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        RemoteIcon(url: server.iconURL(app), name: app.name, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).font(.title3.bold()).foregroundStyle(Theme.text)
                            Text([versionLabel.isEmpty ? "" : "v\(versionLabel)", formatBytes(app.versions?[safe: versionIndex]?.size ?? app.size)]
                                .filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 4)

                    switch stage {
                    case .setup: setup
                    case .working: working
                    case .signed: done
                    case .failed: failed
                    }
                }
                .padding(16)
            }
            .mangoScreen()
            .navigationTitle(stage == .signed ? "Ready" : "Get")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(stage == .signed ? "Done" : "Close") { worker?.cancel(); dismiss() }
                }
            }
        }
        .onAppear {
            if certId.isEmpty { certId = (certs.first { $0.isDefault == true } ?? certs.first)?.id ?? "" }
            if localCertId == nil { localCertId = local.defaultCert?.id }
            if certs.isEmpty && !local.certs.isEmpty { place = .phone }
        }
        .onDisappear { worker?.cancel() }
        .interactiveDismissDisabled(stage == .working)
    }

    // MARK: setup

    @ViewBuilder
    var setup: some View {
        Picker("Where", selection: $place) {
            Text("Sign on server").tag(Place.server)
            Text("Sign on this iPhone").tag(Place.phone)
        }
        .pickerStyle(.segmented)

        if place == .server {
            if certs.isEmpty {
                hint("You don't have a certificate on the server yet. Add one in the Certificates tab.")
            } else {
                Card {
                    ForEach(Array(certs.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { Divider().overlay(Theme.line) }
                        certRow(title: c.label, detail: certDetail(c), warn: certWarning(c), selected: certId == c.id) { certId = c.id }
                    }
                }
                if let s = server.state?.settings, let limit = s.signsPerDay, limit > 0 {
                    Text("\(max(0, limit - (s.signsToday ?? 0))) of \(limit) signs left today")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
            }
        } else {
            if local.certs.isEmpty {
                hint("Signing on this iPhone uses a certificate saved on this iPhone. Add one in Settings → On this iPhone.")
            } else {
                Card {
                    ForEach(Array(local.certs.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { Divider().overlay(Theme.line) }
                        certRow(title: c.label, detail: c.daysLeft.map { $0 < 0 ? "Expired" : "\($0) days left" } ?? c.teamName,
                                warn: (c.daysLeft ?? 1) < 0 ? "Expired" : nil, selected: localCertId == c.id) { localCertId = c.id }
                    }
                }
                Text("The app downloads to this iPhone and is signed here. When it's done you can share it or open it in another app.")
                    .font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
        }

        DisclosureGroup(isExpanded: $showOptions) {
            VStack(spacing: 10) {
                option("App name", app.name, $name)
                option("Bundle ID", app.bundleId ?? "", $bundleId)
                option("Version", versionLabel, $version)
            }
            .padding(.top, 10)
        } label: {
            Text("Options").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
        }
        .padding(14).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

        BigButton(title: "Sign \(app.name)", icon: "signature") { start() }
            .disabled(place == .server ? certId.isEmpty : localCertId == nil)
            .opacity((place == .server ? certId.isEmpty : localCertId == nil) ? 0.5 : 1)
    }

    func certDetail(_ c: SCert) -> String {
        var bits: [String] = []
        if let d = c.daysLeft { bits.append(d < 0 ? "Expired" : "\(d) days left") }
        if let t = c.profile?.teamName, !t.isEmpty { bits.append(t) }
        return bits.joined(separator: " · ")
    }

    func certWarning(_ c: SCert) -> String? {
        if let d = c.daysLeft, d < 0 { return "Expired" }
        if c.check?.status == "revoked" { return "Revoked — apps won't open" }
        if c.deviceIncluded == false { return "This iPhone isn't in the profile" }
        return nil
    }

    func certRow(title: String, detail: String, warn: String?, selected: Bool, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? Theme.mango : Theme.muted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(Theme.text)
                    if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(Theme.muted) }
                    if let warn { Text(warn).font(.caption.weight(.semibold)).foregroundStyle(Theme.red) }
                }
                Spacer()
            }
            .padding(14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func option(_ label: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.muted)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(10).background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Theme.text)
        }
    }

    func hint(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            .padding(16).frame(maxWidth: .infinity).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: working / done

    var working: some View {
        VStack(spacing: 14) {
            if let progress {
                ProgressView(value: progress).tint(Theme.mango)
            } else {
                ProgressView().tint(Theme.mango)
            }
            Text(status).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineLimit(3)
            Button("Cancel") { worker?.cancel(); stage = .setup }.foregroundStyle(Theme.muted)
        }
        .padding(20).frame(maxWidth: .infinity).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    var done: some View {
        if let s = signed {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(Theme.leaf)
                Text("Signed with \(s.certLabel ?? "your certificate")").font(.headline).foregroundStyle(Theme.text)
                if let install, install.phase != "idle" {
                    installProgress(install)
                }
            }
            .padding(20).frame(maxWidth: .infinity).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
            BigButton(title: install?.phase == "done" ? "Installed" : "Install", icon: "arrow.down.app.fill") { startInstall(s) }
            if let share = s.shareUrl, let u = URL(string: share) {
                ShareLink(item: u) {
                    Label("Share install link", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Theme.mango).padding(.top, 4)
            }
        } else if let s = localSigned {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(Theme.leaf)
                Text("Signed on this iPhone with \(s.certLabel)").font(.headline).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                Text("Saved in Files → On My iPhone → Mango Signer → Signed.").font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
            .padding(20).frame(maxWidth: .infinity).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
            ShareLink(item: s.url) {
                HStack(spacing: 8) { Image(systemName: "square.and.arrow.up"); Text("Share .ipa") }
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .foregroundStyle(Theme.onAccent).background(Theme.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    func installProgress(_ i: InstallStatus) -> some View {
        VStack(spacing: 6) {
            switch i.phase {
            case "waiting": Text("Waiting for your iPhone…").foregroundStyle(Theme.muted)
            case "confirm": Text("Tap Install on the popup").foregroundStyle(Theme.mango)
            case "downloading":
                ProgressView(value: i.progress ?? 0).tint(Theme.mango)
                Text("Installing… \(Int((i.progress ?? 0) * 100))%").foregroundStyle(Theme.muted)
            case "done": Text("✓ Sent to your iPhone — check your Home Screen").foregroundStyle(Theme.leaf)
            default: EmptyView()
            }
        }
        .font(.subheadline)
    }

    var failed: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(Theme.red)
            Text(error).font(.subheadline).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            BigButton(title: "Try again", primary: false) { stage = .setup }
        }
        .padding(20).frame(maxWidth: .infinity).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: actions

    func start() {
        stage = .working
        progress = nil
        status = "Starting…"
        worker = Task {
            do {
                if place == .server { try await signOnServer() } else { try await signHere() }
                if !Task.isCancelled { stage = .signed }
            } catch {
                if Task.isCancelled { return }
                self.error = error.localizedDescription
                stage = .failed
            }
        }
    }

    func signOnServer() async throws {
        var body: [String: Any] = ["appId": app.id, "certId": certId, "versionIndex": versionIndex]
        if !name.isEmpty { body["name"] = name }
        if !bundleId.isEmpty { body["bundleId"] = bundleId }
        if !version.isEmpty { body["version"] = version }
        let r = try await server.post("/api/sign", body)
        guard let jobId = r["jobId"] as? String else { throw MangoError("The server didn't start signing. Try again.") }
        status = "Signing on the server…"
        while !Task.isCancelled {
            let j: JobStatus = try await server.get("/api/jobs/\(jobId)")
            if let p = j.progress { progress = p }
            if let last = j.log?.last(where: { !$0.isEmpty }) { status = last }
            switch j.status {
            case "done":
                guard let s = j.result?.signed else { throw MangoError("Signing finished but the server didn't send the app back.") }
                signed = s
                await server.refresh()
                return
            case "error", "cancelled":
                throw MangoError(j.error ?? "Signing stopped.")
            default:
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func signHere() async throws {
        guard let cert = local.certs.first(where: { $0.id == localCertId }) else { throw MangoError("Pick a certificate.") }
        status = "Downloading \(app.name)…"
        progress = 0
        let file = try await server.downloadIPA(app, versionIndex: versionIndex) { p in progress = p }
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        status = "Signing on this iPhone…"
        progress = nil
        var icon: Data?
        if let u = server.iconURL(app) { icon = await ImageCache.shared.image(u)?.pngData() }
        var opts = SignOptions()
        opts.name = name
        opts.bundleId = bundleId
        opts.version = version
        localSigned = try await local.signFile(file, name: app.name, bundleId: app.bundleId ?? "", version: versionLabel,
                                               icon: icon, with: cert, options: opts)
    }

    func startInstall(_ s: SSigned) {
        guard let iu = s.installUrl, let u = URL(string: iu) else { return }
        worker?.cancel()
        worker = Task {
            struct R: Decodable { var install: InstallStatus }
            if let r: R = try? await JSONDecoder().decode(R.self, from: server.data("POST", "/api/signed/\(s.id)/install", json: [:])) {
                install = r.install
            }
            _ = await UIApplication.shared.open(u)
            // Follow the install for up to 10 minutes.
            for _ in 0..<400 {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if let r: R = try? await server.get("/api/signed/\(s.id)/install") {
                    install = r.install
                    if r.install.phase == "done" { await server.refresh(); return }
                }
            }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
