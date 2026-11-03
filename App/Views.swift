import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct MangoSignerApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(.mango)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var tab = 0
    @State private var incomingError: String?

    var body: some View {
        TabView(selection: $tab) {
            LibraryView().tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }.tag(0)
            SignedView().tabItem { Label("Signed", systemImage: "checkmark.seal.fill") }.tag(1)
            CertificatesView().tabItem { Label("Certificates", systemImage: "shield.lefthalf.filled") }.tag(2)
            AboutView().tabItem { Label("About", systemImage: "info.circle.fill") }.tag(3)
        }
        // "Open in Mango Signer" from Files, Safari or another app.
        .onOpenURL { url in
            guard url.pathExtension.lowercased() == "ipa" else { return }
            Task {
                do { _ = try await store.importIPA(url); tab = 0 } catch { incomingError = error.localizedDescription }
            }
        }
        .alert("Couldn't add that app", isPresented: Binding(get: { incomingError != nil }, set: { if !$0 { incomingError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(incomingError ?? "") }
    }
}

// MARK: - Shared bits

struct AppIconView: View {
    let id: UUID
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let img = UIImage(contentsOfFile: Paths.icon(id).path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.mango.opacity(0.18)
                    Image(systemName: "app.fill").foregroundStyle(Color.mango).font(.system(size: size * 0.45))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).stroke(Color.primary.opacity(0.08)))
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(Color.mango)
            Text(title).font(.title3.bold())
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Library

struct LibraryView: View {
    @EnvironmentObject var store: AppStore
    @State private var picking = false
    @State private var importing = 0
    @State private var error: String?
    @State private var search = ""

    var shown: [LibraryApp] {
        search.isEmpty ? store.apps : store.apps.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.bundleId.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.apps.isEmpty && importing == 0 {
                    EmptyState(icon: "square.and.arrow.down", title: "No apps yet",
                               message: "Tap + to add an .ipa from Files, or use \"Open in Mango Signer\" from another app.")
                } else {
                    List {
                        if importing > 0 {
                            HStack { ProgressView(); Text("Adding \(importing) app\(importing == 1 ? "" : "s")…").foregroundStyle(.secondary) }
                        }
                        ForEach(shown) { app in
                            NavigationLink(value: app) {
                                HStack(spacing: 12) {
                                    AppIconView(id: app.id)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(app.name).font(.headline)
                                        Text("\(app.version.isEmpty ? "?" : app.version) · \(formatSize(app.size))").font(.caption).foregroundStyle(.secondary)
                                        Text(app.bundleId).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                        .onDelete { idx in idx.map { shown[$0] }.forEach { store.delete($0) } }
                    }
                    .searchable(text: $search)
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: LibraryApp.self) { AppDetailView(app: $0) }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { picking = true } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [FileTypes.ipa], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                importing += urls.count
                Task {
                    for url in urls {
                        do { _ = try await store.importIPA(url) } catch { self.error = "\(url.lastPathComponent): \(error.localizedDescription)" }
                        importing -= 1
                    }
                }
            }
            .alert("Couldn't add that app", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
}

struct AppDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let app: LibraryApp
    @State private var signing = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    AppIconView(id: app.id, size: 76)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.title2.bold())
                        Text(app.bundleId).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                Button { signing = true } label: {
                    Label("Sign", systemImage: "signature").frame(maxWidth: .infinity).font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            }
            Section("Info") {
                LabeledContent("Version", value: app.build.isEmpty || app.build == app.version ? app.version : "\(app.version) (\(app.build))")
                LabeledContent("Size", value: formatSize(app.size))
                if !app.minOS.isEmpty { LabeledContent("Minimum iOS", value: app.minOS) }
                LabeledContent("Added", value: app.addedAt.formatted(date: .abbreviated, time: .shortened))
            }
            Section {
                ShareLink(item: app.url) { Label("Share .ipa", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { store.delete(app); dismiss() } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $signing) { SignSheet(app: app) }
    }
}

// MARK: - Signing

struct SignSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let app: LibraryApp

    @State private var certId: UUID?
    @State private var options = SignOptions()
    @State private var pickingDylib = false
    @State private var state: Phase = .ready
    @State private var result: SignedApp?
    @State private var addingCert = false

    enum Phase: Equatable { case ready, signing, done, failed(String) }

    var cert: SigningCert? { store.certs.first { $0.id == certId } ?? store.defaultCert }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        AppIconView(id: app.id, size: 44)
                        VStack(alignment: .leading) {
                            Text(app.name).font(.headline)
                            Text("\(app.version) · \(formatSize(app.size))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Certificate") {
                    if store.certs.isEmpty {
                        Button { addingCert = true } label: { Label("Add a certificate first", systemImage: "plus.circle") }
                    } else {
                        Picker("Sign with", selection: Binding(get: { cert?.id }, set: { certId = $0 })) {
                            ForEach(store.certs) { c in Text(c.label).tag(Optional(c.id)) }
                        }
                        if let c = cert, let d = c.daysLeft {
                            Text(d < 0 ? "This certificate has expired" : "Expires in \(d) day\(d == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(d < 7 ? Color.red : Color.secondary)
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
                    switch state {
                    case .ready:
                        Button { Task { await sign() } } label: {
                            Label("Sign \(app.name)", systemImage: "signature").frame(maxWidth: .infinity).font(.headline)
                        }
                        .disabled(cert == nil)
                    case .signing:
                        HStack { ProgressView(); Text("Signing… big apps can take a minute") }
                    case .done:
                        Label("Signed ✓", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        if let r = result { ShareLink(item: r.url) { Label("Share signed .ipa", systemImage: "square.and.arrow.up") } }
                        Button("Done") { dismiss() }
                    case .failed(let msg):
                        Text(msg).foregroundStyle(.red)
                        Button("Try again") { state = .ready }
                    }
                }
            }
            .navigationTitle("Sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(state == .signing) } }
            .interactiveDismissDisabled(state == .signing)
            .fileImporter(isPresented: $pickingDylib, allowedContentTypes: [FileTypes.dylib, .data], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for url in urls {
                    let dest = Paths.work.appendingPathComponent(String(UUID().uuidString.prefix(6)) + "-" + url.lastPathComponent)
                    if (try? copyPicked(url, to: dest)) != nil { options.dylibs.append(dest) }
                }
            }
            .sheet(isPresented: $addingCert) { AddCertSheet() }
        }
    }

    func sign() async {
        guard let c = cert else { return }
        state = .signing
        do {
            result = try await store.sign(app, with: c, options: options)
            state = .done
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Signed

struct SignedView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            Group {
                if store.signed.isEmpty {
                    EmptyState(icon: "checkmark.seal", title: "Nothing signed yet", message: "Pick an app in the Library and tap Sign.")
                } else {
                    List {
                        ForEach(store.signed) { s in
                            HStack(spacing: 12) {
                                AppIconView(id: s.id, size: 48)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(s.name).font(.headline)
                                    Text("\(s.version) · \(s.certLabel)").font(.caption).foregroundStyle(.secondary)
                                    Text("Signed \(s.signedAt.formatted(.relative(presentation: .named))) · \(formatSize(s.size))").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                ShareLink(item: s.url) { Image(systemName: "square.and.arrow.up") }
                                    .buttonStyle(.borderless)
                            }
                        }
                        .onDelete { idx in idx.map { store.signed[$0] }.forEach { store.delete($0) } }
                    }
                }
            }
            .navigationTitle("Signed")
        }
    }
}

// MARK: - Certificates

struct CertificatesView: View {
    @EnvironmentObject var store: AppStore
    @State private var adding = false

    var body: some View {
        NavigationStack {
            Group {
                if store.certs.isEmpty {
                    EmptyState(icon: "shield.lefthalf.filled", title: "No certificates",
                               message: "Add your .p12 and .mobileprovision to start signing. They stay on this iPhone.")
                } else {
                    List {
                        ForEach(store.certs) { c in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(c.label).font(.headline)
                                    if c.id == store.defaultCert?.id {
                                        Text("Default").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.mango.opacity(0.2)).clipShape(Capsule())
                                    }
                                }
                                Text(c.profileName).font(.caption).foregroundStyle(.secondary)
                                if let d = c.daysLeft {
                                    Text(d < 0 ? "Expired" : "\(d) days left").font(.caption).foregroundStyle(d < 7 ? Color.red : Color.secondary)
                                }
                                Text(c.allDevices ? "Any device (enterprise)" : "\(c.deviceCount) device\(c.deviceCount == 1 ? "" : "s")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Default") { store.defaultCertId = c.id; store.persist() }.tint(.mango)
                            }
                        }
                        .onDelete { idx in idx.map { store.certs[$0] }.forEach { store.delete($0) } }
                    }
                }
            }
            .navigationTitle("Certificates")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
            .sheet(isPresented: $adding) { AddCertSheet() }
        }
    }
}

struct AddCertSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var p12: URL?
    @State private var provision: URL?
    @State private var password = ""
    @State private var label = ""
    @State private var picking: Kind?
    @State private var error: String?

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
                } footer: { Text("Both files are copied into Mango Signer and never leave this iPhone.") }
                Section {
                    SecureField("Certificate password", text: $password)
                    TextField("Name (optional)", text: $label)
                }
                if let e = error { Section { Text(e).foregroundStyle(.red) } }
                Section {
                    Button("Add certificate") { save() }.disabled(p12 == nil || provision == nil).font(.headline)
                }
            }
            .navigationTitle("Add Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
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

    func save() {
        guard let p = p12, let m = provision else { return }
        do {
            _ = try store.addCert(p12: p, provision: m, password: password, label: label)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - About

struct AboutView: View {
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "seal.fill").font(.system(size: 40)).foregroundStyle(Color.mango)
                        VStack(alignment: .leading) {
                            Text("Mango Signer").font(.title2.bold())
                            Text("Version \(version)").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("Where your files are") {
                    Text("Added and signed apps are in the Files app under On My iPhone › Mango Signer. Certificates stay private inside the app.")
                        .font(.callout)
                }
                Section("Made with") {
                    Text("zsign by zhlynn (MIT License)")
                    Text("OpenSSL (Apache License 2.0)")
                }
                Section {
                    Text("© 2026 MangoMods. All rights reserved.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About")
        }
    }
}
