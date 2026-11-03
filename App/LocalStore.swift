import Foundation
import SwiftUI
import UIKit

struct LibraryApp: Identifiable, Codable, Hashable {
    var id = UUID()
    var fileName: String
    var name: String
    var bundleId: String
    var version: String
    var build: String
    var minOS: String
    var size: Int64
    var addedAt = Date()
    var url: URL { Paths.apps.appendingPathComponent(fileName) }
}

struct SigningCert: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var p12File: String
    var provFile: String
    var profileName: String
    var teamName: String
    var teamId: String
    var expires: Date?
    var deviceCount: Int
    var allDevices: Bool
    var addedAt = Date()
    /// Set for a copy of a certificate on your account (kept in step with the server, never added by hand).
    var serverId: String? = nil
    var p12URL: URL { Paths.certs.appendingPathComponent(p12File) }
    var provURL: URL { Paths.certs.appendingPathComponent(provFile) }
    var password: String { Keychain.get(id.uuidString) ?? "" }
    var daysLeft: Int? {
        guard let e = expires else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: e).day
    }
}

struct SignedApp: Identifiable, Codable, Hashable {
    var id = UUID()
    var fileName: String
    var name: String
    var bundleId: String
    var version: String
    var certLabel: String
    var size: Int64
    var signedAt = Date()
    var expires: Date?
    /// Set when this is a copy of an app signed on the server (its signed id there).
    var serverId: String?
    var url: URL { Paths.signed.appendingPathComponent(fileName) }
}

/// Everything the app knows, saved as small JSON files in Application Support.
@MainActor
final class LocalStore: ObservableObject {
    @Published var apps: [LibraryApp] = []
    @Published var certs: [SigningCert] = []
    @Published var signed: [SignedApp] = []
    @Published var defaultCertId: UUID?

    init() {
        Paths.prepare()
        apps = load("apps.json") ?? []
        certs = load("certs.json") ?? []
        signed = load("signed.json") ?? []
        defaultCertId = load("default-cert.json")
        // Drop entries whose file was deleted from the Files app.
        apps.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
        signed.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
    }

    var defaultCert: SigningCert? { ownCerts.first { $0.id == defaultCertId } ?? ownCerts.first }
    /// Certificates added to this iPhone by hand (not the copies of your account's certificates).
    var ownCerts: [SigningCert] { certs.filter { $0.serverId == nil } }
    /// The phone's copy of one of your account's certificates.
    func accountCopy(_ serverId: String?) -> SigningCert? { serverId.flatMap { id in certs.first { $0.serverId == id } } }

    // MARK: saving

    private func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: Paths.support.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: Paths.support.appendingPathComponent(name), options: .atomic)
        }
    }

    func persist() {
        save(apps, "apps.json")
        save(certs, "certs.json")
        save(signed, "signed.json")
        save(defaultCertId, "default-cert.json")
    }

    // MARK: apps

    /// Copies a picked .ipa into the library and reads its name, version and icon.
    func importIPA(_ picked: URL) async throws -> LibraryApp {
        let id = UUID()
        let dest = Paths.apps.appendingPathComponent("\(id.uuidString.prefix(8))-\(picked.lastPathComponent)")
        let meta: IPAMeta = try await Task.detached(priority: .userInitiated) {
            try copyPicked(picked, to: dest)
            do { return try IPAReader.read(dest) } catch {
                try? FileManager.default.removeItem(at: dest)
                throw error
            }
        }.value
        var app = LibraryApp(fileName: dest.lastPathComponent, name: meta.name, bundleId: meta.bundleId, version: meta.version,
                             build: meta.build, minOS: meta.minOS, size: fileSize(dest))
        app.id = id
        if let png = meta.icon?.pngData() { try? png.write(to: Paths.icon(id)) }
        apps.insert(app, at: 0)
        persist()
        return app
    }

    func delete(_ app: LibraryApp) {
        try? FileManager.default.removeItem(at: app.url)
        try? FileManager.default.removeItem(at: Paths.icon(app.id))
        apps.removeAll { $0.id == app.id }
        persist()
    }

    // MARK: certificates

    func addCert(p12: URL, provision: URL, password: String, label: String, serverId: String? = nil) throws -> SigningCert {
        let id = UUID()
        let p12Dest = Paths.certs.appendingPathComponent("\(id.uuidString).p12")
        let provDest = Paths.certs.appendingPathComponent("\(id.uuidString).mobileprovision")
        try copyPicked(p12, to: p12Dest)
        try copyPicked(provision, to: provDest)
        do {
            let provInfo = try CertReader.provision(Data(contentsOf: provDest))
            let certName = try CertReader.p12Name(Data(contentsOf: p12Dest), password: password)
            var cert = SigningCert(
                label: label.trimmingCharacters(in: .whitespaces).isEmpty ? (provInfo.teamName.isEmpty ? (certName ?? provInfo.name) : provInfo.teamName) : label,
                p12File: p12Dest.lastPathComponent, provFile: provDest.lastPathComponent, profileName: provInfo.name,
                teamName: provInfo.teamName, teamId: provInfo.teamId, expires: provInfo.expires,
                deviceCount: provInfo.devices.count, allDevices: provInfo.allDevices
            )
            cert.id = id
            cert.serverId = serverId
            if !Keychain.set(password, for: id.uuidString) { throw MangoError("Couldn't save the certificate password on this iPhone.") }
            certs.append(cert)
            if defaultCertId == nil && serverId == nil { defaultCertId = id }
            persist()
            return cert
        } catch {
            try? FileManager.default.removeItem(at: p12Dest)
            try? FileManager.default.removeItem(at: provDest)
            throw error
        }
    }

    func delete(_ cert: SigningCert) {
        try? FileManager.default.removeItem(at: cert.p12URL)
        try? FileManager.default.removeItem(at: cert.provURL)
        Keychain.delete(cert.id.uuidString)
        certs.removeAll { $0.id == cert.id }
        if defaultCertId == cert.id { defaultCertId = ownCerts.first?.id }
        persist()
    }

    /// Keeps a copy of each certificate on your account here, so signing on this iPhone can use them and they
    /// come back after reinstalling the app. Only missing ones are downloaded; copies of certificates that are
    /// gone from your account (or belong to another account) are removed.
    func syncAccountCerts(server: Server) async {
        guard !syncingCerts else { return }
        syncingCerts = true
        defer { syncingCerts = false }
        let wanted = server.authed ? server.certs : []
        for c in certs where c.serverId != nil && !wanted.contains(where: { $0.id == c.serverId }) { delete(c) }
        struct CertBundle: Decodable { var label: String; var p12: String; var profile: String; var password: String }
        for sc in wanted {
            if var have = accountCopy(sc.id), FileManager.default.fileExists(atPath: have.p12URL.path) {
                if have.label != "☁ \(sc.label)", let i = certs.firstIndex(where: { $0.id == have.id }) {
                    have.label = "☁ \(sc.label)"; certs[i] = have; persist()
                }
                continue
            }
            if let old = accountCopy(sc.id) { delete(old) }
            guard let b: CertBundle = try? await server.get("/api/certs/\(sc.id)/bundle"),
                  let p12 = Data(base64Encoded: b.p12), let prof = Data(base64Encoded: b.profile) else { continue }
            let tmp = Paths.work.appendingPathComponent("acct-\(UUID().uuidString.prefix(8))", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let p12URL = tmp.appendingPathComponent("cert.p12"), provURL = tmp.appendingPathComponent("profile.mobileprovision")
            guard (try? p12.write(to: p12URL)) != nil, (try? prof.write(to: provURL)) != nil else { continue }
            _ = try? addCert(p12: p12URL, provision: provURL, password: b.password, label: "☁ \(b.label)", serverId: sc.id)
        }
    }
    private var syncingCerts = false

    // MARK: signing

    func sign(_ app: LibraryApp, with cert: SigningCert, options: SignOptions) async throws -> SignedApp {
        let icon = try? Data(contentsOf: Paths.icon(app.id))
        return try await signFile(app.url, name: app.name, bundleId: app.bundleId, version: app.version, icon: icon, with: cert, options: options)
    }

    /// Signs any .ipa on this iPhone (one from the library here, or one just downloaded from the server).
    func signFile(_ input: URL, name: String, bundleId: String, version: String, icon: Data?, with cert: SigningCert, options: SignOptions) async throws -> SignedApp {
        let id = UUID()
        let shownName = options.name.isEmpty ? name : options.name
        let safeName = shownName.replacingOccurrences(of: "/", with: "-")
        let out = Paths.signed.appendingPathComponent("\(safeName) \(id.uuidString.prefix(6)).ipa")
        let p12 = cert.p12URL, prov = cert.provURL, password = cert.password
        _ = try await Task.detached(priority: .userInitiated) {
            try Signer.sign(input: input, output: out, p12: p12, password: password, provision: prov, options: options)
        }.value
        var result = SignedApp(fileName: out.lastPathComponent, name: shownName,
                               bundleId: options.bundleId.isEmpty ? bundleId : options.bundleId,
                               version: options.version.isEmpty ? version : options.version,
                               certLabel: cert.label, size: fileSize(out), expires: cert.expires)
        result.id = id
        if let icon { try? icon.write(to: Paths.icon(id)) }
        signed.insert(result, at: 0)
        persist()
        return result
    }

    // MARK: copies of apps signed on the server (like ESign: everything you sign stays on your iPhone)

    @Published var saving: [String: Double] = [:]
    private var copyQueue = false
    static var keepCopies: Bool {
        get { UserDefaults.standard.object(forKey: "keepSignedCopies") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "keepSignedCopies") }
    }

    func copy(of serverId: String) -> SignedApp? { signed.first { $0.serverId == serverId } }

    /// Downloads one signed app from the server into this iPhone.
    func saveCopy(_ s: SSigned, server: Server) async throws {
        if copy(of: s.id) != nil || saving[s.id] != nil { return }
        guard let u = server.url("/api/signed/\(s.id)/file") else { return }
        saving[s.id] = 0
        defer { saving[s.id] = nil }
        let tmp = try await server.downloadFile(u) { [weak self] p in self?.saving[s.id] = p }
        let safe = s.name.replacingOccurrences(of: "/", with: "-")
        let dest = Paths.signed.appendingPathComponent("\(safe) \(s.version ?? "") \(s.id.prefix(4)).ipa")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        var copy = SignedApp(fileName: dest.lastPathComponent, name: s.name, bundleId: s.bundleId ?? "", version: s.version ?? "",
                             certLabel: s.certLabel ?? "", size: fileSize(dest), expires: parseDate(s.expires))
        copy.signedAt = parseDate(s.signedAt) ?? Date()
        copy.serverId = s.id
        if let iu = server.iconURL(s), let png = await ImageCache.shared.image(iu)?.pngData() { try? png.write(to: Paths.icon(copy.id)) }
        signed.insert(copy, at: 0)
        persist()
    }

    /// Saves every signed app that's still on the server and not on this iPhone yet, one at a time.
    func saveMissingCopies(server: Server) async {
        guard LocalStore.keepCopies, !copyQueue else { return }
        copyQueue = true
        defer { copyQueue = false }
        for s in server.state?.signed ?? [] where s.fileAvailable == true && copy(of: s.id) == nil {
            try? await saveCopy(s, server: server)
        }
    }

    func delete(_ s: SignedApp) {
        try? FileManager.default.removeItem(at: s.url)
        try? FileManager.default.removeItem(at: Paths.icon(s.id))
        signed.removeAll { $0.id == s.id }
        persist()
    }
}
