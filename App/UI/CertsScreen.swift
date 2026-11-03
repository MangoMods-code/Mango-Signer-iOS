import SwiftUI

struct CertsScreen: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var local: LocalStore
    @State private var adding = false
    @State private var toast: String?
    @State private var confirmDelete: SCert?
    @State private var checking: String?

    var certs: [SCert] { server.state?.certs ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if certs.isEmpty {
                        EmptyState(icon: "checkmark.shield", title: "No certificates yet",
                                   message: "Add your .p12 and .mobileprovision to start signing apps.")
                        BigButton(title: "Add a certificate", icon: "plus") { adding = true }
                    } else {
                        SectionTitle(text: "Your certificates", count: certs.count)
                        VStack(spacing: 12) {
                            ForEach(certs) { c in card(c) }
                        }
                    }
                    NavigationLink {
                        LocalCertsScreen()
                    } label: {
                        HStack {
                            Image(systemName: "iphone").foregroundStyle(Theme.mango)
                            Text("Certificates on this iPhone").foregroundStyle(Theme.text)
                            Spacer()
                            Text("\(local.certs.count)").foregroundStyle(Theme.muted)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                        }
                        .padding(14).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.top, 22)
                    Text("These are only used for \"Sign on this iPhone\" and never leave it.")
                        .font(.caption).foregroundStyle(Theme.muted).padding(.top, 6)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .refreshable { await server.refresh() }
            .navigationTitle("Certificates")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
            .mangoScreen()
            .toast($toast)
            .sheet(isPresented: $adding) { AddCertSheet(target: .server) }
            .confirmationDialog("Delete \(confirmDelete?.label ?? "")?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let c = confirmDelete { delete(c) } }
            } message: { Text("Apps you already installed with it keep working until it expires.") }
        }
    }

    func statusBadge(_ c: SCert) -> Badge {
        if let d = c.daysLeft, d < 0 { return Badge(text: "Expired", style: .bad) }
        switch c.check?.status {
        case "revoked": return Badge(text: "Revoked", style: .bad)
        case "valid": return Badge(text: "Valid", style: .good)
        default: return Badge(text: "Status unknown")
        }
    }

    func card(_ c: SCert) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(c.label).font(.headline).foregroundStyle(Theme.text)
                if c.isDefault == true { Badge(text: "Default", style: .mango) }
                Spacer()
                Menu {
                    if c.isDefault != true {
                        Button { act(c, "Now your default") { _ = try await server.post("/api/certs/\(c.id)", ["makeDefault": true], method: "PATCH") } } label: {
                            Label("Make default", systemImage: "star")
                        }
                    }
                    Button { check(c) } label: { Label("Check status", systemImage: "arrow.clockwise") }
                    Button(role: .destructive) { confirmDelete = c } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Theme.muted)
                }
            }
            HStack(spacing: 6) {
                if checking == c.id { ProgressView().scaleEffect(0.7) } else { statusBadge(c) }
                if let d = c.daysLeft, d >= 0 { Badge(text: "\(d) days left", style: d < 7 ? .bad : .plain) }
                if let t = c.profile?.type, !t.isEmpty { Badge(text: t) }
                if c.profile?.type == "Enterprise" { Badge(text: "Any device") }
                else if let n = c.profile?.deviceCount, n > 0 { Badge(text: "\(n) device\(n == 1 ? "" : "s")") }
            }
            if let t = c.profile?.teamName, !t.isEmpty { Text(t).font(.caption).foregroundStyle(Theme.muted) }
            if let n = c.profile?.name, !n.isEmpty { Text(n).font(.caption2).foregroundStyle(Theme.muted) }
            if c.check?.status == "revoked" {
                Text("⚠️ This certificate is revoked, so apps signed with it won't open.").font(.caption).foregroundStyle(Theme.red)
            } else if c.deviceIncluded == false {
                Text("This iPhone isn't in this certificate's profile, so apps signed with it won't install here.").font(.caption).foregroundStyle(Theme.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func act(_ c: SCert, _ msg: String, _ work: @escaping () async throws -> Void) {
        Task {
            do { try await work(); await server.refresh(); toast = msg } catch { toast = error.localizedDescription }
        }
    }

    func check(_ c: SCert) {
        checking = c.id
        Task {
            defer { checking = nil }
            do { try await server.post("/api/certs/\(c.id)/check"); await server.refresh(); toast = "Checked" } catch { toast = error.localizedDescription }
        }
    }

    func delete(_ c: SCert) {
        act(c, "Deleted") { _ = try await server.data("DELETE", "/api/certs/\(c.id)") }
    }
}
