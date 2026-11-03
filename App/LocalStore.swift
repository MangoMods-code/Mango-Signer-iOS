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

    var defaultCert: SigningCert? { certs.first { $0.id == defaultCertId } ?? certs.first }

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

    func addCert(p12: URL, provision: URL, password: String, label: String) throws -> SigningCert {
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
            if !Keychain.set(password, for: id.uuidString) { throw MangoError("Couldn't save the certificate password on this iPhone.") }
            certs.append(cert)
            if defaultCertId == nil { defaultCertId = id }
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
        if defaultCertId == cert.id { defaultCertId = certs.first?.id }
        persist()
    }

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

    func delete(_ s: SignedApp) {
        try? FileManager.default.removeItem(at: s.url)
        try? FileManager.default.removeItem(at: Paths.icon(s.id))
        signed.removeAll { $0.id == s.id }
        persist()
    }
}
