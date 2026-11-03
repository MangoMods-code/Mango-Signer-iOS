import SwiftUI
import UIKit

struct SignedScreen: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @State private var toast: String?
    @State private var installing: SSigned?
    @State private var confirmDelete: SSigned?

    var list: [SSigned] { (server.state?.signed ?? []).sorted { (parseDate($0.signedAt) ?? .distantPast) > (parseDate($1.signedAt) ?? .distantPast) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if list.isEmpty && local.signed.isEmpty {
                        EmptyState(icon: "checkmark.seal", title: "Nothing signed yet", message: "Pick an app in the Library and tap Get.")
                    }
                    if !list.isEmpty {
                        SectionTitle(text: "Signed on the server", count: list.count)
                        Card {
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                                if i > 0 { Divider().overlay(Theme.line).padding(.leading, 80) }
                                row(s)
                            }
                        }
                    }
                    if !local.signed.isEmpty {
                        SectionTitle(text: "Signed on this iPhone", count: local.signed.count)
                        Card {
                            ForEach(Array(local.signed.enumerated()), id: \.element.id) { i, s in
                                if i > 0 { Divider().overlay(Theme.line).padding(.leading, 80) }
                                HStack(spacing: 14) {
                                    LocalIcon(id: s.id, name: s.name)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(s.name).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                                        Text("\(s.version) · \(s.certLabel)").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                                        Text("Signed \(s.signedAt.formatted(.relative(presentation: .named))) · \(formatSize(s.size))")
                                            .font(.caption2).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    ShareLink(item: s.url) { Image(systemName: "square.and.arrow.up").font(.title3) }
                                        .foregroundStyle(Theme.mango)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .contextMenu {
                                    Button(role: .destructive) { local.delete(s) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .refreshable { await server.refresh() }
            .navigationTitle("Signed")
            .mangoScreen()
            .toast($toast)
            .sheet(item: $installing) { InstallSheet(signed: $0) }
            .confirmationDialog("Delete \(confirmDelete?.name ?? "")?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let s = confirmDelete { delete(s) }
                }
            } message: { Text("This only removes the signed copy. Apps already on your iPhone stay installed.") }
        }
    }

    func row(_ s: SSigned) -> some View {
        HStack(spacing: 14) {
            RemoteIcon(url: server.iconURL(s), name: s.name, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(s.name).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                    if s.onPhone == true { Badge(text: "✓ On iPhone", style: .good) }
                }
                Text([s.version ?? "", s.certLabel ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                Text(["Signed \(ago(s.signedAt))", formatBytes(s.size)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Theme.muted)
                if s.fileAvailable == false { Text("Cleaned up — sign it again").font(.caption2).foregroundStyle(Theme.red) }
            }
            Spacer(minLength: 6)
            if s.fileAvailable != false {
                PillButton(title: "Install") { installing = s }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu {
            if let share = s.shareUrl, let u = URL(string: share) {
                ShareLink(item: u) { Label("Share install link", systemImage: "link") }
                Button { UIPasteboard.general.string = share; toast = "Link copied" } label: { Label("Copy install link", systemImage: "doc.on.doc") }
            }
            Button(role: .destructive) { confirmDelete = s } label: { Label("Delete", systemImage: "trash") }
        }
    }

    func delete(_ s: SSigned) {
        Task {
            do { _ = try await server.data("DELETE", "/api/signed/\(s.id)"); await server.refresh(); toast = "Deleted" } catch { toast = error.localizedDescription }
        }
    }
}

/// Installs a signed app over the air and follows it until it lands on the Home Screen.
struct InstallSheet: View {
    @EnvironmentObject var server: Server
    @Environment(\.dismiss) private var dismiss
    let signed: SSigned
    @State private var install: InstallStatus?
    @State private var worker: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 18) {
            RemoteIcon(url: server.iconURL(signed), name: signed.name, size: 80).padding(.top, 30)
            Text(signed.name).font(.title3.bold()).foregroundStyle(Theme.text)
            Group {
                switch install?.phase ?? "waiting" {
                case "confirm": Text("Tap Install on the popup").foregroundStyle(Theme.mango)
                case "downloading":
                    VStack(spacing: 8) {
                        ProgressView(value: install?.progress ?? 0).tint(Theme.mango)
                        Text("Installing… \(Int((install?.progress ?? 0) * 100))%").foregroundStyle(Theme.muted)
                    }
                case "done": Text("✓ Sent to your iPhone — check your Home Screen").foregroundStyle(Theme.leaf)
                default: HStack(spacing: 8) { ProgressView().tint(Theme.mango); Text("Waiting for your iPhone…").foregroundStyle(Theme.muted) }
                }
            }
            .font(.subheadline).multilineTextAlignment(.center)
            Spacer()
            BigButton(title: "Show the popup again", primary: false) { openInstall() }
            BigButton(title: install?.phase == "done" ? "Done" : "Close") { dismiss() }
        }
        .padding(20)
        .background(Theme.bg.ignoresSafeArea())
        .presentationDetents([.medium])
        .onAppear { start() }
        .onDisappear { worker?.cancel() }
    }

    struct R: Decodable { var install: InstallStatus }

    func openInstall() {
        guard let iu = signed.installUrl, let u = URL(string: iu) else { return }
        UIApplication.shared.open(u)
    }

    func start() {
        worker = Task {
            if let d = try? await server.data("POST", "/api/signed/\(signed.id)/install", json: [:]), let r = try? JSONDecoder().decode(R.self, from: d) {
                install = r.install
            }
            openInstall()
            for _ in 0..<400 {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if let r: R = try? await server.get("/api/signed/\(signed.id)/install") {
                    install = r.install
                    if r.install.phase == "done" { await server.refresh(); return }
                }
            }
        }
    }
}
