import SwiftUI
import UniformTypeIdentifiers
import UIKit

// Everything kept on this iPhone only: .ipa files you add yourself, certificates saved here,
// and apps signed here. Lives under Settings → On this iPhone.

struct LocalIcon: View {
    let id: UUID
    var name: String = ""
    var size: CGFloat = 52
    var body: some View {
        ZStack {
            if let img = UIImage(contentsOfFile: Paths.icon(id).path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Theme.card2
                Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(Theme.mango)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).stroke(Theme.line))
    }
}

struct LocalAppsScreen: View {
    @EnvironmentObject var local: LocalStore
    @State private var picking = false
    @State private var importing = 0
    @State private var toast: String?
    @State private var signing: LibraryApp?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if importing > 0 {
                    HStack(spacing: 10) { ProgressView().tint(Theme.mango); Text("Adding \(importing) app\(importing == 1 ? "" : "s")…").foregroundStyle(Theme.muted) }
                        .padding(.vertical, 12)
                }
                if local.apps.isEmpty && importing == 0 {
                    EmptyState(icon: "square.and.arrow.down", title: "No apps on this iPhone",
                               message: "Tap + to add an .ipa from Files, or use \"Open in Mango Signer\" from another app.")
                } else {
                    Card {
                        ForEach(Array(local.apps.enumerated()), id: \.element.id) { i, app in
                            if i > 0 { Divider().overlay(Theme.line).padding(.leading, 80) }
                            HStack(spacing: 14) {
                                LocalIcon(id: app.id, name: app.name)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                                    Text("\(app.version.isEmpty ? "?" : app.version) · \(formatSize(app.size))").font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                PillButton(title: "Sign") { signing = app }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .contextMenu {
                                ShareLink(item: app.url) { Label("Share .ipa", systemImage: "square.and.arrow.up") }
                                Button(role: .destructive) { local.delete(app) } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                    Text("Touch and hold an app to share or delete it.").font(.caption).foregroundStyle(Theme.muted).padding(.top, 10)
                }
            }
            .padding(16)
        }
        .mangoScreen()
        .navigationTitle("Apps on this iPhone")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { Button { picking = true } label: { Image(systemName: "plus") } }
        }
        .toast($toast)
        .fileImporter(isPresented: $picking, allowedContentTypes: [FileTypes.ipa], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            importing += urls.count
            Task {
                for url in urls {
                    do { let a = try await local.importIPA(url); toast = "Added \(a.name)" } catch { toast = "\(url.lastPathComponent): \(error.localizedDescription)" }
                    importing -= 1
                }
            }
        }
        .sheet(item: $signing) { LocalSignSheet(app: $0) }
    }
}

struct LocalSignSheet: View {
    @EnvironmentObject var local: LocalStore
    @Environment(\.dismiss) private var dismiss
    let app: LibraryApp

    @State private var certId: UUID?
    @State private var options = SignOptions()
    @State private var pickingDylib = false
    @State private var phase: Phase = .ready
    @State private var result: SignedApp?
    @State private var addingCert = false

    enum Phase: Equatable { case ready, signing, done, failed(String) }

    var cert: SigningCert? { local.certs.first { $0.id == certId } ?? local.defaultCert ?? local.certs.first }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        LocalIcon(id: app.id, name: app.name, size: 44)
                        VStack(alignment: .leading) {
                            Text(app.name).font(.headline)
                            Text("\(app.version) · \(formatSize(app.size))").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
                Section("Certificate") {
                    if local.certs.isEmpty {
                        Button { addingCert = true } label: { Label("Add a certificate first", systemImage: "plus.circle") }
                    } else {
                        Picker("Sign with", selection: Binding(get: { cert?.id }, set: { certId = $0 })) {
                            ForEach(local.certs) { c in Text(c.label).tag(Optional(c.id)) }
                        }
                        if let c = cert, let d = c.daysLeft {
                            Text(d < 0 ? "This certificate has expired" : "Expires in \(d) day\(d == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(d < 7 ? Theme.red : Theme.muted)
                        }
                    }
                }
                Section("Change (optional)") {
                    TextField("Name (\(app.name))", text: $options.name)
                    TextField("Bundle ID (\(app.bundleId))", text: $options.bundleId)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Version (\(app.version))", text: $options.version)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Options") {
                    Toggle("Remove app extensions", isOn: $options.removeExtensions)
                    Toggle("Remove device limits", isOn: $options.removeDeviceLimits)
                    Toggle("Files app access", isOn: $options.fileSharing)
                }
                Section {
                    ForEach(options.dylibs, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "puzzlepiece.extension")
                    }
                    .onDelete { options.dylibs.remove(atOffsets: $0) }
                    Button { pickingDylib = true } label: { Label("Add a .dylib tweak", systemImage: "plus") }
                } header: { Text("Tweaks") } footer: { Text("Tweaks are injected into the app before it's signed.") }

                Section {
                    switch phase {
                    case .ready:
                        Button { Task { await sign() } } label: {
                            Label("Sign \(app.name)", systemImage: "signature").frame(maxWidth: .infinity).font(.headline)
                        }
                        .disabled(cert == nil)
                    case .signing:
                        HStack { ProgressView(); Text("Signing… big apps can take a minute") }
                    case .done:
                        Label("Signed ✓", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.leaf)
                        if let r = result { ShareLink(item: r.url) { Label("Share signed .ipa", systemImage: "square.and.arrow.up") } }
                        Button("Done") { dismiss() }
                    case .failed(let msg):
                        Text(msg).foregroundStyle(Theme.red)
                        Button("Try again") { phase = .ready }
                    }
                }
            }
            .mangoScreen()
            .navigationTitle("Sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(phase == .signing) } }
            .interactiveDismissDisabled(phase == .signing)
            .fileImporter(isPresented: $pickingDylib, allowedContentTypes: [FileTypes.dylib, .data], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for url in urls {
                    let dest = Paths.work.appendingPathComponent(String(UUID().uuidString.prefix(6)) + "-" + url.lastPathComponent)
                    if (try? copyPicked(url, to: dest)) != nil { options.dylibs.append(dest) }
                }
            }
            .sheet(isPresented: $addingCert) { AddCertSheet(target: .phone) }
        }
    }

    func sign() async {
        guard let c = cert else { return }
        phase = .signing
        do {
            result = try await local.sign(app, with: c, options: options)
            phase = .done
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

struct LocalCertsScreen: View {
    @EnvironmentObject var local: LocalStore
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Certificates on your account (the Certificates tab) already work for signing on this iPhone, and they come back by themselves if you reinstall the app. Add one here only if you want it on this iPhone and not on your account.")
                    .font(.caption).foregroundStyle(Theme.muted).padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
                if local.ownCerts.isEmpty {
                    EmptyState(icon: "shield.lefthalf.filled", title: "No certificates only on this iPhone",
                               message: "Add a .p12 and .mobileprovision to sign apps right on this iPhone. They never leave it.")
                } else {
                    Card {
                        ForEach(Array(local.ownCerts.enumerated()), id: \.element.id) { i, c in
                            if i > 0 { Divider().overlay(Theme.line) }
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(c.label).font(.headline).foregroundStyle(Theme.text)
                                        if c.id == local.defaultCert?.id { Badge(text: "Default", style: .mango) }
                                    }
                                    Text(c.profileName).font(.caption).foregroundStyle(Theme.muted)
                                    if let d = c.daysLeft {
                                        Text(d < 0 ? "Expired" : "\(d) days left").font(.caption).foregroundStyle(d < 7 ? Theme.red : Theme.muted)
                                    }
                                    Text(c.allDevices ? "Any device (enterprise)" : "\(c.deviceCount) device\(c.deviceCount == 1 ? "" : "s")")
                                        .font(.caption2).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Menu {
                                    if c.id != local.defaultCert?.id {
                                        Button { local.defaultCertId = c.id; local.persist() } label: { Label("Make default", systemImage: "star") }
                                    }
                                    Button(role: .destructive) { local.delete(c) } label: { Label("Delete", systemImage: "trash") }
                                } label: {
                                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Theme.muted)
                                }
                            }
                            .padding(14)
                        }
                    }
                }
            }
            .padding(16)
        }
        .mangoScreen()
        .navigationTitle("Certificates on this iPhone")
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $adding) { AddCertSheet(target: .phone) }
    }
}

/// Adds a certificate either to your account on the server or only to this iPhone.
struct AddCertSheet: View {
    enum Target { case server, phone }
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var server: Server
    @Environment(\.dismiss) private var dismiss
    let target: Target

    @State private var p12: URL?
    @State private var provision: URL?
    @State private var password = ""
    @State private var label = ""
    @State private var picking: Kind?
    @State private var error: String?
    @State private var busy = false

    enum Kind { case p12, provision }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { picking = .p12 } label: {
                        Label(p12?.lastPathComponent ?? "Choose .p12", systemImage: p12 == nil ? "doc.badge.plus" : "checkmark.circle.fill")
                    }
                    Button { picking = .provision } label: {
                        Label(provision?.lastPathComponent ?? "Choose .mobileprovision", systemImage: provision == nil ? "doc.badge.plus" : "checkmark.circle.fill")
                    }
                } footer: {
                    Text(target == .phone ? "Both files are copied into Mango Signer and never leave this iPhone."
                                          : "Both files are sent to your Mango Signer server and saved with your account.")
                }
                Section {
                    SecureField("Certificate password", text: $password)
                    TextField("Name (optional)", text: $label)
                }
                if let e = error { Section { Text(e).foregroundStyle(Theme.red) } }
                Section {
                    if busy {
                        HStack { ProgressView(); Text("Adding…").foregroundStyle(Theme.muted) }
                    } else {
                        Button("Add certificate") { Task { await save() } }.disabled(p12 == nil || provision == nil).font(.headline)
                    }
                }
            }
            .mangoScreen()
            .navigationTitle("Add Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
            .fileImporter(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
                          allowedContentTypes: picking == .p12 ? [FileTypes.p12, .data] : [FileTypes.provision, .data]) { result in
                guard case .success(let url) = result else { return }
                // Copy right away: the picked file's access ends when this returns.
                let dest = Paths.work.appendingPathComponent(String(UUID().uuidString.prefix(6)) + "-" + url.lastPathComponent)
                guard (try? copyPicked(url, to: dest)) != nil else { error = "Couldn't open \(url.lastPathComponent)"; return }
                if picking == .p12 { p12 = dest } else { provision = dest }
                picking = nil
            }
        }
    }

    func save() async {
        guard let p = p12, let m = provision else { return }
        busy = true
        defer { busy = false }
        do {
            switch target {
            case .phone:
                _ = try local.addCert(p12: p, provision: m, password: password, label: label)
            case .server:
                let p12Id = try await server.upload(p)
                let provId = try await server.upload(m)
                var body: [String: Any] = ["p12UploadId": p12Id, "provUploadId": provId, "password": password]
                if !label.trimmingCharacters(in: .whitespaces).isEmpty { body["label"] = label }
                try await server.post("/api/certs", body)
                await server.refresh()
            }
            try? FileManager.default.removeItem(at: p)
            try? FileManager.default.removeItem(at: m)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
