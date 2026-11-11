import Foundation
import Security
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Look

extension Color {
    static let mango = Color(red: 1.0, green: 0.624, blue: 0.110)
}

// MARK: - Errors

struct MangoError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Where things are kept
// Documents (visible in the Files app): Apps (imported .ipa files) and Signed (signed .ipa files).
// Application Support (private): certificates, icons and the lists.

enum Paths {
    static let fm = FileManager.default
    static let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mango", isDirectory: true)
    static var apps: URL { documents.appendingPathComponent("Apps", isDirectory: true) }
    static var signed: URL { documents.appendingPathComponent("Signed", isDirectory: true) }
    static var certs: URL { support.appendingPathComponent("Certificates", isDirectory: true) }
    static var icons: URL { support.appendingPathComponent("Icons", isDirectory: true) }
    static var work: URL { fm.temporaryDirectory.appendingPathComponent("work", isDirectory: true) }

    static func prepare() {
        for url in [apps, signed, certs, icons, work] {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func icon(_ id: UUID) -> URL { icons.appendingPathComponent("\(id.uuidString).png") }
}

enum FileTypes {
    static let ipa = UTType(filenameExtension: "ipa") ?? .data
    static let p12 = UTType(filenameExtension: "p12") ?? .data
    static let provision = UTType(filenameExtension: "mobileprovision") ?? .data
    static let dylib = UTType(filenameExtension: "dylib") ?? .data
}

func formatSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func fileSize(_ url: URL) -> Int64 {
    ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
}

/// Copies a file the user picked (which may be outside the app) to `dest`.
func copyPicked(_ url: URL, to dest: URL) throws {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
    try FileManager.default.copyItem(at: url, to: dest)
}

// MARK: - Keychain (certificate passwords)

enum Keychain {
    private static let service = "MangoSigner.certificates"

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Reading .ipa files (through minizip in MangoEngine)

struct IPAMeta {
    var name: String
    var bundleId: String
    var version: String
    var build: String
    var minOS: String
    var icon: UIImage?
}

enum IPAReader {
    static func names(in url: URL) throws -> [String] {
        guard let raw = mango_zip_names(url.path) else { throw MangoError("That file isn't a valid .ipa (it couldn't be opened).") }
        defer { mango_free(raw) }
        return String(cString: raw).split(separator: "\n").map(String.init)
    }

    static func entry(_ name: String, in url: URL, max: UInt = 8 << 20) throws -> Data {
        var ptr: UnsafeMutableRawPointer?
        var len: UInt = 0
        guard mango_zip_read(url.path, name, max, &ptr, &len) == 0, let p = ptr else {
            throw MangoError("Couldn't read \(name) from the .ipa.")
        }
        defer { mango_free(p) }
        return Data(bytes: p, count: Int(len))
    }

    static func read(_ url: URL) throws -> IPAMeta {
        let all = try names(in: url)
        guard let plistPath = all.first(where: { $0.hasPrefix("Payload/") && $0.hasSuffix(".app/Info.plist") && $0.split(separator: "/").count == 3 }) else {
            throw MangoError("That .ipa has no app inside (no Payload/….app/Info.plist).")
        }
        let appDir = String(plistPath.dropLast("Info.plist".count))
        let data = try entry(plistPath, in: url)
        let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]

        func str(_ key: String) -> String { (info[key] as? String) ?? "" }
        let name = [str("CFBundleDisplayName"), str("CFBundleName"), str("CFBundleExecutable")].first { !$0.isEmpty } ?? "App"

        // Icon: names listed in Info.plist, preferring the 180px (60x60@3x) one.
        var iconNames: [String] = []
        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            if let icons = info[key] as? [String: Any], let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] {
                iconNames += (primary["CFBundleIconFiles"] as? [String]) ?? []
                if let n = primary["CFBundleIconName"] as? String { iconNames.append(n) }
            }
        }
        iconNames += (info["CFBundleIconFiles"] as? [String]) ?? []
        if let one = info["CFBundleIconFile"] as? String { iconNames.append(one) }
        let topLevelPNGs = all.filter { $0.hasPrefix(appDir) && $0.lowercased().hasSuffix(".png") && !$0.dropFirst(appDir.count).contains("/") }
        var candidates = topLevelPNGs.filter { path in
            let base = String(path.dropFirst(appDir.count))
            return iconNames.contains { !$0.isEmpty && base.hasPrefix($0) }
        }
        if candidates.isEmpty { candidates = topLevelPNGs.filter { $0.lowercased().contains("icon") } }
        func rank(_ p: String) -> Int {
            if p.contains("60x60@3x") { return 0 }
            if p.contains("@3x") { return 1 }
            if p.contains("@2x") { return 2 }
            return 3
        }
        candidates.sort { rank($0) < rank($1) }
        var icon: UIImage?
        for c in candidates.prefix(4) {
            if let d = try? entry(c, in: url, max: 4 << 20), let img = UIImage(data: d) { icon = img; break }
        }

        return IPAMeta(name: name, bundleId: str("CFBundleIdentifier"), version: str("CFBundleShortVersionString"),
                       build: str("CFBundleVersion"), minOS: str("MinimumOSVersion"), icon: icon)
    }
}

// MARK: - Provisioning profiles and .p12 files

struct ProvisionInfo {
    var name: String
    var teamName: String
    var teamId: String
    var appIdName: String
    var expires: Date?
    var devices: [String]
    var allDevices: Bool
}

enum CertReader {
    static func provision(_ data: Data) throws -> ProvisionInfo {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else {
            throw MangoError("That isn't a valid .mobileprovision file.")
        }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let p = try PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any] else {
            throw MangoError("That .mobileprovision file couldn't be read.")
        }
        return ProvisionInfo(
            name: p["Name"] as? String ?? "Profile",
            teamName: p["TeamName"] as? String ?? "",
            teamId: (p["TeamIdentifier"] as? [String])?.first ?? "",
            appIdName: p["AppIDName"] as? String ?? "",
            expires: p["ExpirationDate"] as? Date,
            devices: p["ProvisionedDevices"] as? [String] ?? [],
            allDevices: p["ProvisionsAllDevices"] as? Bool ?? false
        )
    }

    /// The entitlements a profile allows (used as the starting point for custom entitlements).
    static func entitlements(_ data: Data) throws -> [String: Any] {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return [:] }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        let p = try PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any]
        return p?["Entitlements"] as? [String: Any] ?? [:]
    }

    /// Checks the .p12 password. Returns the certificate's name when iOS can read it, or nil if iOS can't
    /// open this kind of .p12 (zsign may still can, so that's not treated as an error).
    static func p12Name(_ data: Data, password: String) throws -> String? {
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, [kSecImportExportPassphrase as String: password] as CFDictionary, &items)
        if status == errSecAuthFailed { throw MangoError("Wrong password for that .p12 certificate.") }
        guard status == errSecSuccess, let list = items as? [[String: Any]], let first = list.first,
              let identityRef = first[kSecImportItemIdentity as String] else { return nil }
        let identity = identityRef as! SecIdentity
        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity, &cert)
        guard let c = cert else { return nil }
        return SecCertificateCopySubjectSummary(c) as String?
    }
}

// MARK: - Signing (zsign)

struct SignOptions {
    var name = ""
    var bundleId = ""
    var version = ""
    var minOS = ""
    var icon: URL?
    var removeExtensions = false
    var removeWatch = false
    var removeDeviceLimits = false
    var fileSharing = false
    var dylibs: [URL] = []
    var weakDylibs = false
    var injectExtensions = false
    /// Entitlement changes (on top of what the profile allows): key -> value, nil removes the key.
    var entitlementEdits: [(String, Any?)] = []
}

enum Signer {
    /// Signs `input` into `output`. Returns zsign's log. Throws with the last error line if it fails.
    static func sign(input: URL, output: URL, p12: URL, password: String, provision: URL, options: SignOptions) throws -> String {
        let tmp = Paths.work.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let logURL = tmp.appendingPathComponent("zsign.log")

        var args = ["zsign", "-f", "-k", p12.path, "-p", password, "-m", provision.path, "-z", "1", "-t", tmp.path, "-o", output.path]
        if !options.bundleId.isEmpty { args += ["-b", options.bundleId] }
        if !options.name.isEmpty { args += ["-n", options.name] }
        if !options.version.isEmpty { args += ["-r", options.version] }
        if !options.minOS.isEmpty { args += ["-M", options.minOS] }
        if let icon = options.icon { args += ["-I", icon.path] }
        if !options.entitlementEdits.isEmpty {
            // Start from what the profile allows, then apply the changes.
            var ent = (try? CertReader.entitlements(Data(contentsOf: provision))) ?? [:]
            for (k, v) in options.entitlementEdits { if let v { ent[k] = v } else { ent.removeValue(forKey: k) } }
            let entURL = tmp.appendingPathComponent("entitlements.plist")
            let data = try PropertyListSerialization.data(fromPropertyList: ent, format: .xml, options: 0)
            try data.write(to: entURL)
            args += ["-e", entURL.path]
        }
        if options.removeExtensions { args.append("-E") }
        if options.removeWatch { args.append("-W") }
        if options.removeDeviceLimits { args.append("-U") }
        if options.fileSharing { args.append("-S") }
        for d in options.dylibs { args += ["-l", d.path] }
        if !options.dylibs.isEmpty && options.weakDylibs { args.append("-w") }
        if !options.dylibs.isEmpty && options.injectExtensions { args.append("-P") }
        args.append(input.path)

        var cargs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        defer { cargs.forEach { free($0) } }
        let rc: Int32 = cargs.withUnsafeMutableBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buf.count) { ptr in
                mango_zsign(Int32(args.count), ptr, logURL.path)
            }
        }
        let raw = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        // zsign colors its output for terminals; drop those codes.
        let log = raw.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
        if rc != 0 || !FileManager.default.fileExists(atPath: output.path) {
            let last = log.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .last { $0.hasPrefix(">>>") && !$0.contains("Done") } ?? "Signing failed"
            throw MangoError(last.replacingOccurrences(of: ">>> ", with: ""))
        }
        return log
    }
}

// MARK: - Picking files by copy

/// A file picker that hands the app its own copy of what you pick (like ESign), instead of reaching into Files.
/// Reaching into Files needs the app to be signed with its own app ID, which isn't the case with most certificates,
/// so the copy way is the one that always works.
struct CopyPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let multiple: Bool
    let done: (Result<[URL], Error>) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        p.allowsMultipleSelection = multiple
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: CopyPicker
        init(_ p: CopyPicker) { parent = p }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.done(.success(urls))
            parent.dismiss()
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.done(.failure(CocoaError(.userCancelled)))
            parent.dismiss()
        }
    }

    /// Copies left over from earlier picks. Called when the app opens.
    static func clearOldCopies() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        for u in (try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? [] where u.lastPathComponent.hasSuffix("-Inbox") {
            for f in (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: f) }
        }
    }
}

extension View {
    /// Same shape as `.fileImporter`, but the app gets a copy of each file.
    func copyImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool, onCompletion: @escaping (Result<[URL], Error>) -> Void) -> some View {
        sheet(isPresented: isPresented) {
            CopyPicker(types: allowedContentTypes, multiple: allowsMultipleSelection, done: onCompletion).ignoresSafeArea()
        }
    }
    func copyImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View {
        copyImporter(isPresented: isPresented, allowedContentTypes: allowedContentTypes, allowsMultipleSelection: false) { r in
            switch r {
            case .success(let urls): if let u = urls.first { onCompletion(.success(u)) } else { onCompletion(.failure(CocoaError(.userCancelled))) }
            case .failure(let e): onCompletion(.failure(e))
            }
        }
    }
}
