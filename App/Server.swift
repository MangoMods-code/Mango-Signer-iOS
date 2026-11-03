import Foundation
import SwiftUI
import UIKit

// MARK: - What the Mango Signer server sends
// Every model is read field by field and forgivingly: a number where text was expected (or the other way
// round), a missing field or an odd value never stops the library from loading.

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// One item of a list; an item that can't be read at all is skipped instead of breaking the whole list.
struct Lossy<T: Decodable>: Decodable {
    var value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// Text that may arrive as text, a number or true/false.
struct FlexString: Decodable {
    var value: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int64.self) { value = String(i) }
        else if let d = try? c.decode(Double.self) { value = String(d) }
        else if let b = try? c.decode(Bool.self) { value = b ? "true" : "false" }
        else { value = nil }
    }
}

/// Any JSON value (used for entitlement values and other free-form settings).
enum JSONValue: Decodable, Hashable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { self = .null }
    }

    var any: Any {
        switch self {
        case .string(let s): return s
        case .number(let d): return d == d.rounded() && abs(d) < 1e15 ? Int(d) as Any : d as Any
        case .bool(let b): return b
        case .array(let a): return a.map { $0.any }
        case .object(let o): return o.mapValues { $0.any }
        case .null: return NSNull()
        }
    }
    var text: String {
        switch self {
        case .string(let s): return s
        case .number(let d): return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
        case .bool(let b): return b ? "true" : "false"
        default: return ""
        }
    }
    /// What an entitlement value means for "does the profile allow this".
    var allows: Bool {
        switch self {
        case .bool(let b): return b
        case .array(let a): return !a.isEmpty
        case .string(let s): return !s.isEmpty
        default: return false
        }
    }
}

extension KeyedDecodingContainer where Key == AnyKey {
    func has(_ k: String) -> Bool { contains(AnyKey(k)) && !((try? decodeNil(forKey: AnyKey(k))) ?? true) }
    func str(_ k: String) -> String? { (try? decodeIfPresent(FlexString.self, forKey: AnyKey(k)))?.value }
    func num(_ k: String) -> Double? {
        let key = AnyKey(k)
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b ? 1 : 0 }
        return nil
    }
    func int(_ k: String) -> Int? { num(k).flatMap { $0.isFinite && abs($0) < 9e15 ? Int($0) : nil } }
    func bool(_ k: String) -> Bool? {
        let key = AnyKey(k)
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return ["true", "1", "yes"].contains(s.lowercased()) }
        return nil
    }
    func strings(_ k: String) -> [String]? {
        guard let list = try? decodeIfPresent([FlexString].self, forKey: AnyKey(k)) else { return nil }
        return list.compactMap { $0.value }
    }
    func obj<T: Decodable>(_ k: String) -> T? { (try? decodeIfPresent(Lossy<T>.self, forKey: AnyKey(k)))?.value }
    func list<T: Decodable>(_ k: String) -> [T]? {
        guard let items = try? decodeIfPresent([Lossy<T>].self, forKey: AnyKey(k)) else { return nil }
        return items.compactMap { $0.value }
    }
    func json(_ k: String) -> JSONValue? { try? decodeIfPresent(JSONValue.self, forKey: AnyKey(k)) }
}

private func keyed(_ decoder: Decoder) throws -> KeyedDecodingContainer<AnyKey> { try decoder.container(keyedBy: AnyKey.self) }

struct Account: Decodable {
    var id: String
    var username: String
    var role: String
    var udid: String?
    var deviceName: String?
    var isOwner: Bool { role == "owner" }
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        role = c.str("role") ?? "user"
        id = c.str("id") ?? (role == "owner" ? "owner" : "")
        username = c.str("username") ?? id
        udid = c.str("udid"); deviceName = c.str("deviceName")
    }
}

/// One custom entitlement or Info.plist change: key, kind of value, and the value.
struct EditRow: Identifiable, Hashable, Decodable {
    var id = UUID()
    var key: String = ""
    var type: String = "bool"   // bool, string, number, delete
    var boolValue = true
    var textValue = ""

    init(key: String = "", type: String = "bool", boolValue: Bool = true, textValue: String = "") {
        self.key = key; self.type = type; self.boolValue = boolValue; self.textValue = textValue
    }
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        key = c.str("key") ?? ""
        type = c.str("type") ?? "bool"
        let v = c.json("value") ?? .null
        if case .bool(let b) = v { boolValue = b } else { boolValue = type == "bool" ? (v.text == "true") : true }
        textValue = v.text
    }
    var json: [String: Any] {
        var value: Any = true
        switch type {
        case "bool": value = boolValue
        case "number": value = Double(textValue) ?? 0
        case "string": value = textValue
        default: value = NSNull()
        }
        return ["key": key.trimmingCharacters(in: .whitespaces), "type": type, "value": value]
    }
}

/// How an app (or a preset) signs by default.
struct SignDefaults: Decodable, Hashable {
    var minOS = ""
    var entitlements: [EditRow] = []
    var plist: [EditRow] = []
    var removeExtensions = false
    var removeWatch: Bool?
    var removeUISD = false
    var enableDocs = false
    var weakDylibs = false
    var injectExtensions = false
    var tweakIds: [String] = []
    var versionIndex = 0

    init() {}
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        minOS = c.str("minOS") ?? ""
        entitlements = c.list("entitlements") ?? []
        plist = c.list("plist") ?? []
        removeExtensions = c.bool("removeExtensions") ?? false
        removeWatch = c.bool("removeWatch")
        removeUISD = c.bool("removeUISD") ?? false
        enableDocs = c.bool("enableDocs") ?? false
        weakDylibs = c.bool("weakDylibs") ?? false
        injectExtensions = c.bool("injectExtensions") ?? false
        tweakIds = c.strings("tweakIds") ?? []
        versionIndex = c.int("versionIndex") ?? 0
    }
    var isEmpty: Bool {
        minOS.isEmpty && entitlements.isEmpty && plist.isEmpty && !removeExtensions && removeWatch != true && !removeUISD
            && !enableDocs && !weakDylibs && !injectExtensions && tweakIds.isEmpty
    }
}

struct SInstalled: Decodable {
    var version: String?
    var at: String?
    var stopped: String?
    var update: Bool?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        version = c.str("version"); at = c.str("at"); stopped = c.str("stopped"); update = c.bool("update")
    }
}

struct SVersion: Decodable {
    var version: String?
    var date: String?
    var size: Double?
    var notes: String?
    var channel: String?
    var manualId: String?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        version = c.str("version"); date = c.str("date"); size = c.num("size"); notes = c.str("notes")
        channel = c.str("channel"); manualId = c.str("manualId")
    }
}

struct SShot: Decodable { var id: String; init(from decoder: Decoder) throws { id = try keyed(decoder).str("id") ?? "" } }

struct SApp: Decodable, Identifiable {
    var id: String
    var name: String
    var bundleId: String?
    var version: String?
    var build: String?
    var versionOverride: String?
    var minOS: String?
    var size: Double?
    var description: String?
    var notes: String?
    var developer: String?
    var categoryId: String?
    var featured: Bool?
    var published: Bool?
    var hasIcon: Bool?
    var customIcon: Bool?
    var useIconWhenSigning: Bool?
    var iconVersion: Double?
    var addedAt: String?
    var updatedAt: String?
    var previousVersion: String?
    var installCount: Int?
    var likes: Int?
    var dislikes: Int?
    var myVote: Int?
    var installed: SInstalled?
    var cloud: String?
    var sourceName: String?
    var missing: Bool?
    var versions: [SVersion]?
    var remoteScreens: [String]?
    var screenshots: [SShot]?
    var tags: [String]?
    var extensions: Int?
    var hasWatch: Bool?
    var signDefaults: SignDefaults?
    var remoteUrl: String?

    struct NoId: Error {}
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        guard let id = c.str("id"), !id.isEmpty else { throw NoId() }
        self.id = id
        bundleId = c.str("bundleId")
        name = c.str("name").flatMap { $0.isEmpty ? nil : $0 } ?? c.str("originalName") ?? bundleId ?? "App"
        version = c.str("version"); build = c.str("build"); versionOverride = c.str("versionOverride")
        minOS = c.str("minOS"); size = c.num("size"); description = c.str("description"); notes = c.str("notes")
        developer = c.str("developer"); categoryId = c.str("categoryId")
        featured = c.bool("featured"); published = c.bool("published"); hasIcon = c.bool("hasIcon"); customIcon = c.bool("customIcon")
        useIconWhenSigning = c.bool("useIconWhenSigning")
        iconVersion = c.num("iconVersion"); addedAt = c.str("addedAt"); updatedAt = c.str("updatedAt")
        previousVersion = c.str("previousVersion")
        installCount = c.int("installCount"); likes = c.int("likes"); dislikes = c.int("dislikes"); myVote = c.int("myVote")
        installed = c.obj("installed")
        cloud = c.str("cloud"); sourceName = c.str("sourceName"); missing = c.bool("missing")
        versions = c.list("versions")
        remoteScreens = c.strings("remoteScreens")
        screenshots = c.list("screenshots")
        tags = c.strings("tags")
        extensions = c.int("extensions"); hasWatch = c.bool("hasWatch")
        signDefaults = c.obj("signDefaults")
        remoteUrl = c.str("remoteUrl")
    }

    var shownVersion: String { [versionOverride, version].compactMap { $0 }.first { !$0.isEmpty } ?? "" }
    var hasUpdate: Bool { installed?.update == true && installed?.stopped == nil }
    var isStopped: Bool { installed?.stopped != nil }
    var isNew: Bool { (Date().timeIntervalSince(parseDate(addedAt) ?? .distantPast)) < 3 * 86400 }
    var isUpdatedRecently: Bool {
        !isNew && previousVersion != nil && (Date().timeIntervalSince(parseDate(updatedAt) ?? .distantPast)) < 3 * 86400
    }
    var sortDate: Date { parseDate(updatedAt) ?? parseDate(addedAt) ?? .distantPast }
    var isSourceApp: Bool { cloud == "source" || cloud == "telegram" }
    var votes: Int { (likes ?? 0) + (dislikes ?? 0) }
    var score: Int { (likes ?? 0) - (dislikes ?? 0) }
    var getLabel: String { hasUpdate ? "Update" : isStopped ? "Fix" : "Get" }
}

struct SCategory: Decodable, Identifiable {
    var id: String
    var name: String
    var emoji: String?
    var order: Int?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        id = c.str("id") ?? UUID().uuidString; name = c.str("name") ?? ""; emoji = c.str("emoji"); order = c.int("order")
    }
}

struct SProfile: Decodable {
    var name: String?
    var type: String?
    var teamName: String?
    var teamId: String?
    var appId: String?
    var wildcard: Bool?
    var expires: String?
    var deviceCount: Int?
    var entitlements: [String]?
    var entitlementValues: [String: JSONValue]?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        name = c.str("name"); type = c.str("type"); teamName = c.str("teamName"); teamId = c.str("teamId")
        appId = c.str("appId"); wildcard = c.bool("wildcard"); expires = c.str("expires"); deviceCount = c.int("deviceCount")
        entitlements = c.strings("entitlements")
        if case .object(let o)? = c.json("entitlementValues") { entitlementValues = o }
    }
}

struct SP12: Decodable {
    var commonName: String?
    var validTo: String?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        commonName = c.str("commonName"); validTo = c.str("validTo")
    }
}

struct SCheck: Decodable {
    var status: String?
    var checkedAt: String?
    var ocsp: String?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        status = c.str("status"); checkedAt = c.str("checkedAt"); ocsp = c.str("ocsp")
    }
}

struct SCert: Decodable, Identifiable {
    var id: String
    var label: String
    var isDefault: Bool?
    var p12: SP12?
    var profile: SProfile?
    var check: SCheck?
    var deviceIncluded: Bool?
    var matches: Bool?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        id = c.str("id") ?? UUID().uuidString; label = c.str("label") ?? "Certificate"; isDefault = c.bool("isDefault")
        p12 = c.obj("p12"); profile = c.obj("profile"); check = c.obj("check"); deviceIncluded = c.bool("deviceIncluded")
        matches = c.bool("matches")
    }

    var expires: Date? { [parseDate(p12?.validTo), parseDate(profile?.expires)].compactMap { $0 }.min() }
    var daysLeft: Int? { expires.map { Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0 } }
    var type: String { profile?.type ?? "" }
    func allows(_ key: String) -> Bool {
        if let vals = profile?.entitlementValues { return vals[key]?.allows ?? false }
        return profile?.entitlements?.contains(key) ?? false
    }
}

struct SSignedOptions: Decodable {
    var entitlements: [String] = []
    var plist: [String] = []
    var dylibs: [String] = []
    var tweaks: [String] = []
    var tweakIds: [String] = []
    var icon = false
    var versionIndex = 0
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        entitlements = c.strings("entitlements") ?? []; plist = c.strings("plist") ?? []; dylibs = c.strings("dylibs") ?? []
        tweaks = c.strings("tweaks") ?? []; tweakIds = c.strings("tweakIds") ?? []; icon = c.bool("icon") ?? false
        versionIndex = c.int("versionIndex") ?? 0
    }
}

struct SSigned: Decodable, Identifiable {
    var id: String
    var name: String
    var appId: String?
    var certId: String?
    var bundleId: String?
    var version: String?
    var certLabel: String?
    var size: Double?
    var hasIcon: Bool?
    var signedAt: String?
    var expires: String?
    var token: String?
    var fileAvailable: Bool?
    var savedOnGithub: Bool?
    var onPhone: Bool?
    var installUrl: String?
    var shareUrl: String?
    var downloadUrl: String?
    var options: SSignedOptions?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        id = c.str("id") ?? UUID().uuidString; name = c.str("name") ?? "App"
        appId = c.str("appId"); certId = c.str("certId"); bundleId = c.str("bundleId"); version = c.str("version"); certLabel = c.str("certLabel")
        size = c.num("size"); hasIcon = c.bool("hasIcon"); signedAt = c.str("signedAt") ?? c.str("createdAt"); expires = c.str("expires")
        token = c.str("token"); fileAvailable = c.bool("fileAvailable"); savedOnGithub = c.bool("savedOnGithub"); onPhone = c.bool("onPhone")
        installUrl = c.str("installUrl"); shareUrl = c.str("shareUrl"); downloadUrl = c.str("downloadUrl"); options = c.obj("options")
    }
    var daysLeft: Int? { parseDate(expires).map { Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0 } }
}

struct SAlert: Decodable, Identifiable {
    var id: String
    var kind: String?
    var title: String?
    var body: String?
    var at: String?
    var read: Bool?
    var appId: String?
    var requestId: String?
    var userId: String?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        id = c.str("id") ?? UUID().uuidString; kind = c.str("kind"); title = c.str("title"); body = c.str("body")
        at = c.str("at"); read = c.bool("read"); appId = c.str("appId"); requestId = c.str("requestId"); userId = c.str("userId")
    }
}

struct SSettings: Decodable {
    var signsPerDay: Int?
    var signsToday: Int?
    var maxSignedPerUser: Int?
    var signedRetentionDays: Int?
    var signedOnGithub: Bool?
    var zipLevel: Int?
    var deleteAfterInstall: Bool?
    var udidLogin: Bool?
    var lastBackup: String?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        signsPerDay = c.int("signsPerDay"); signsToday = c.int("signsToday"); maxSignedPerUser = c.int("maxSignedPerUser")
        signedRetentionDays = c.int("signedRetentionDays"); signedOnGithub = c.bool("signedOnGithub"); zipLevel = c.int("zipLevel")
        deleteAfterInstall = c.bool("deleteAfterInstall"); udidLogin = c.bool("udidLogin"); lastBackup = c.str("lastBackup")
    }
}

struct SStorage: Decodable {
    var library: Double?, signed: Double?, certs: Double?, temp: Double?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        library = c.num("library"); signed = c.num("signed"); certs = c.num("certs"); temp = c.num("temp")
    }
}

struct SDisk: Decodable {
    var total: Double?, free: Double?
    init(from decoder: Decoder) throws { let c = try keyed(decoder); total = c.num("total"); free = c.num("free") }
}

struct SServerInfo: Decodable {
    var version: String?
    var https: Bool?
    var baseUrl: String?
    var zsign: String?
    var passwordSet: Bool?
    var storage: Double?
    var storageBreakdown: SStorage?
    var disk: SDisk?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        version = c.str("version"); https = c.bool("https"); baseUrl = c.str("baseUrl"); zsign = c.str("zsign")
        passwordSet = c.bool("passwordSet"); storage = c.num("storage"); storageBreakdown = c.obj("storageBreakdown"); disk = c.obj("disk")
    }
}

struct SAnnouncement: Decodable {
    var text: String?
    init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) { text = s; return }
        text = try keyed(decoder).str("text")
    }
}

struct STweakFile: Decodable { var name: String; var needsSubstrate: Bool
    init(from decoder: Decoder) throws { let c = try keyed(decoder); name = c.str("name") ?? ""; needsSubstrate = c.bool("needsSubstrate") ?? false }
}

struct STweak: Decodable, Identifiable {
    var id: String
    var name: String
    var version: String?
    var description: String?
    var warnings: [String]
    var files: [STweakFile]
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        id = c.str("id") ?? UUID().uuidString; name = c.str("name") ?? "Tweak"; version = c.str("version"); description = c.str("description")
        warnings = c.strings("warnings") ?? []; files = c.list("files") ?? []
    }
}

struct SPreset: Decodable, Identifiable {
    var id: String
    var name: String
    var options: SignDefaults
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        id = c.str("id") ?? UUID().uuidString; name = c.str("name") ?? "Preset"; options = c.obj("options") ?? SignDefaults()
    }
}

struct SInstallLog: Decodable, Identifiable {
    var id = UUID()
    var appId: String?
    var name: String
    var version: String?
    var shownVersion: String?
    var certLabel: String?
    var at: String?
    var via: String?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        appId = c.str("appId"); name = c.str("name") ?? "App"; version = c.str("version"); shownVersion = c.str("shownVersion")
        certLabel = c.str("certLabel"); at = c.str("at"); via = c.str("via")
    }
}

struct SRequest: Decodable, Identifiable {
    var id: String
    var name: String
    var username: String?
    var link: String?
    var note: String?
    var status: String
    var reply: String?
    var appId: String?
    var createdAt: String?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        id = c.str("id") ?? UUID().uuidString; name = c.str("name") ?? "App"; username = c.str("username"); link = c.str("link")
        note = c.str("note"); status = c.str("status") ?? "pending"; reply = c.str("reply"); appId = c.str("appId"); createdAt = c.str("createdAt")
    }
}

struct SInvite: Decodable, Identifiable {
    var code: String
    var note: String?
    var maxUses: Int
    var uses: Int
    var usedBy: [String]
    var expiresAt: String?
    var id: String { code }
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        code = c.str("code") ?? ""; note = c.str("note"); maxUses = c.int("maxUses") ?? 1; uses = c.int("uses") ?? 0
        usedBy = c.strings("usedBy") ?? []; expiresAt = c.str("expiresAt")
    }
    var expired: Bool { parseDate(expiresAt).map { $0 < Date() } ?? false }
}

struct SSignin: Decodable, Identifiable {
    var id: String
    var type: String
    var user: String?
    var ok: Bool
    var ip: String?
    var device: String?
    var detail: String?
    var at: String?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        id = c.str("id") ?? UUID().uuidString; type = c.str("type") ?? ""; user = c.str("user"); ok = c.bool("ok") ?? false
        ip = c.str("ip"); device = c.str("device"); detail = c.str("detail"); at = c.str("at")
    }
}

struct SUser: Decodable, Identifiable {
    var id: String
    var username: String
    var udid: String?
    var deviceName: String?
    var createdAt: String?
    var lastLogin: String?
    var disabled: Bool
    var invite: String?
    var certCount: Int
    var signedCount: Int
    var signLimit: Int?
    var signsToday: Int
    var recentSignins: [SSignin]
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        id = c.str("id") ?? UUID().uuidString; username = c.str("username") ?? "?"; udid = c.str("udid"); deviceName = c.str("deviceName")
        createdAt = c.str("createdAt"); lastLogin = c.str("lastLogin"); disabled = c.bool("disabled") ?? false; invite = c.str("invite")
        certCount = c.int("certCount") ?? 0; signedCount = c.int("signedCount") ?? 0; signLimit = c.int("signLimit"); signsToday = c.int("signsToday") ?? 0
        recentSignins = c.list("recentSignins") ?? []
    }
}

struct SGithubInfo: Decodable {
    var connected: Bool
    var signedToGithub: Bool
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        connected = c.bool("connected") ?? false; signedToGithub = c.bool("signedToGithub") ?? false
    }
}

struct ServerState: Decodable {
    var account: Account
    var apps: [SApp]
    var categories: [SCategory]?
    var certs: [SCert]?
    var signed: [SSigned]?
    var favorites: [String]?
    var alerts: [SAlert]?
    var settings: SSettings?
    var server: SServerInfo?
    var announcement: SAnnouncement?
    var tweaks: [STweak]
    var presets: [SPreset]
    var installs: [SInstallLog]
    var requests: [SRequest]
    var invites: [SInvite]
    var users: [SUser]
    var mySignins: [SSignin]
    var securityLog: [SSignin]
    var github: SGithubInfo?
    var skipped = 0

    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        account = try c.decode(Account.self, forKey: AnyKey("account"))
        let rawApps = (try? c.decodeIfPresent([Lossy<SApp>].self, forKey: AnyKey("apps"))) ?? []
        apps = rawApps.compactMap { $0.value }
        skipped = rawApps.count - apps.count
        categories = c.list("categories")
        certs = c.list("certs")
        signed = c.list("signed")
        favorites = c.strings("favorites")
        alerts = c.list("alerts")
        settings = c.obj("settings")
        server = c.obj("server")
        announcement = c.obj("announcement")
        tweaks = c.list("tweaks") ?? []
        presets = c.list("presets") ?? []
        installs = c.list("installs") ?? []
        requests = c.list("requests") ?? []
        invites = c.list("invites") ?? []
        users = c.list("users") ?? []
        mySignins = c.list("mySignins") ?? []
        securityLog = c.list("securityLog") ?? []
        github = c.obj("github")
    }
}

struct SessionInfo: Decodable {
    var authed: Bool
    var account: Account?
    var udidLogin: Bool?
    var version: String?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        authed = c.bool("authed") ?? false; account = c.obj("account"); udidLogin = c.bool("udidLogin"); version = c.str("version")
    }
}

struct JobResult: Decodable {
    var signed: SSigned?
    init(from decoder: Decoder) throws { signed = try keyed(decoder).obj("signed") }
}

struct JobStatus: Decodable {
    var status: String
    var log: [String]?
    var error: String?
    var progress: Double?
    var result: JobResult?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        status = c.str("status") ?? "running"; log = c.strings("log"); error = c.str("error"); progress = c.num("progress"); result = c.obj("result")
    }
}

struct InstallStatus: Decodable {
    var phase: String
    var progress: Double?
    var sent: Double?
    var size: Double?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        phase = c.str("phase") ?? "idle"; progress = c.num("progress"); sent = c.num("sent"); size = c.num("size")
    }
}

struct WhatsNewSection: Decodable {
    var title: String
    var items: [String]
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        title = c.str("title") ?? ""; items = c.strings("items") ?? []
    }
}

struct WhatsNewEntry: Decodable, Identifiable {
    var version: String
    var date: String?
    var title: String?
    var summary: String?
    var sections: [WhatsNewSection]?
    var id: String { version }
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        version = c.str("version") ?? ""; date = c.str("date"); title = c.str("title"); summary = c.str("summary"); sections = c.list("sections")
    }
}

struct TaskInfo: Decodable, Identifiable {
    var id: String
    var title: String?
    var status: String
    var progress: Double?
    var last: String?
    var error: String?
    var cancellable: Bool?
    var waitingFor: String?
    var position: Int?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        id = c.str("id") ?? UUID().uuidString; title = c.str("title"); status = c.str("status") ?? "running"
        progress = c.num("progress"); last = c.str("last"); error = c.str("error"); cancellable = c.bool("cancellable")
        waitingFor = c.str("waitingFor"); position = c.int("position")
    }
}

// MARK: - Dates

private let isoFrac: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
private let isoPlain = ISO8601DateFormatter()

func parseDate(_ s: String?) -> Date? {
    guard let s, !s.isEmpty else { return nil }
    if let d = isoFrac.date(from: s) ?? isoPlain.date(from: s) { return d }
    // "2026-11-02" style
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.date(from: String(s.prefix(10)))
}

func ago(_ s: String?) -> String {
    guard let d = parseDate(s) else { return "" }
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f.localizedString(for: d, relativeTo: Date())
}

// MARK: - Talking to the server

@MainActor
final class Server: ObservableObject {
    /// Your server. Built into the app (MangoServerURL in project.yml) so a fresh install connects right away;
    /// "Use a different server" can still change it.
    @Published var baseURL: URL? = UserDefaults.standard.url(forKey: "serverURL") ?? Server.builtInServer
    static var builtInServer: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "MangoServerURL") as? String).flatMap { $0.isEmpty ? nil : normalize($0) }
    }
    @Published var state: ServerState?
    @Published var authed = false
    @Published var checking = true
    @Published var tasks: [TaskInfo] = []
    /// Why the library couldn't be loaded (shown on screen instead of failing quietly).
    @Published var loadError: String?

    var account: Account? { state?.account }
    var isOwner: Bool { account?.isOwner == true }

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared
        c.httpCookieAcceptPolicy = .always
        c.timeoutIntervalForRequest = 60
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    func url(_ path: String) -> URL? {
        guard let base = baseURL else { return nil }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    /// Normalizes what someone typed ("mango.up.railway.app" -> "https://mango.up.railway.app").
    static func normalize(_ input: String) -> URL? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard var c = URLComponents(string: s), c.host != nil else { return nil }
        c.path = ""
        c.query = nil
        return c.url
    }

    func setServer(_ url: URL?) {
        baseURL = url
        UserDefaults.standard.set(url, forKey: "serverURL")
        state = nil
        authed = false
    }

    // Raw request. Throws the server's own error message when there is one.
    func data(_ method: String, _ path: String, json: [String: Any]? = nil, body: Data? = nil, timeout: TimeInterval = 60) async throws -> Data {
        guard let u = url(path) else { throw MangoError("Pick your Mango Signer server first.") }
        var req = URLRequest(url: u, timeoutInterval: timeout)
        req.httpMethod = method
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        } else if let body {
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) } catch {
            throw MangoError("Couldn't reach your server. Check your connection and try again.")
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && path != "/api/login" {
            authed = false
            throw MangoError("Please sign in again.")
        }
        if !(200..<300).contains(code) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw MangoError(msg ?? "Request failed (HTTP \(code))")
        }
        return data
    }

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await data("GET", path))
    }

    @discardableResult
    func post(_ path: String, _ json: [String: Any] = [:], method: String = "POST") async throws -> [String: Any] {
        let d = try await data(method, path, json: json)
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }

    // MARK: session

    func checkSession() async {
        checking = true
        defer { checking = false }
        guard baseURL != nil else { authed = false; return }
        if let s: SessionInfo = try? await get("/api/session"), s.authed {
            authed = true
            await refresh()
        } else if let saved = savedLogin, (try? await login(username: saved.0, password: saved.1)) != nil {
            // Signed out (new install, or the session ran out): sign back in with the saved login.
        } else {
            authed = false
        }
    }

    // The login is kept in the iPhone's Keychain so updates and reinstalls sign straight back in.
    private var loginKey: String { "login:" + (baseURL?.host ?? "") }
    var savedLogin: (String, String)? {
        guard let raw = Keychain.get(loginKey), let i = raw.firstIndex(of: "\n") else { return nil }
        return (String(raw[..<i]), String(raw[raw.index(after: i)...]))
    }
    private func saveLogin(_ username: String, _ password: String) { _ = Keychain.set("\(username)\n\(password)", for: loginKey) }
    /// After changing your password in the app, so the next automatic sign-in uses the new one.
    func rememberNewPassword(_ password: String) { if let u = savedLogin?.0 { saveLogin(u, password) } }

    func login(username: String, password: String) async throws {
        try await post("/api/login", ["username": username, "password": password])
        saveLogin(username, password)
        authed = true
        await refresh()
    }

    func signup(username: String, password: String, invite: String) async throws {
        try await post("/api/signup", ["username": username, "password": password, "invite": invite])
        saveLogin(username, password)
        authed = true
        await refresh()
    }

    func logout() async {
        Keychain.delete(loginKey)
        _ = try? await post("/api/logout")
        if let cookies = HTTPCookieStorage.shared.cookies { cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) } }
        state = nil
        authed = false
    }

    @discardableResult
    func refresh() async -> String? {
        do {
            let d = try await data("GET", "/api/state")
            do {
                state = try JSONDecoder().decode(ServerState.self, from: d)
                loadError = nil
            } catch {
                loadError = "The app couldn't read your server's library (\(Server.describe(error))). Make sure the server is up to date."
            }
        } catch {
            loadError = error.localizedDescription
        }
        return loadError
    }

    static func describe(_ error: Error) -> String {
        guard let e = error as? DecodingError else { return error.localizedDescription }
        func path(_ c: DecodingError.Context) -> String { c.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".") }
        switch e {
        case .keyNotFound(let k, let c): return "missing \(k.stringValue) at \(path(c))"
        case .typeMismatch(_, let c), .valueNotFound(_, let c): return "unexpected value at \(path(c))"
        case .dataCorrupted(let c): return "unreadable data at \(path(c))"
        @unknown default: return "unreadable data"
        }
    }

    func refreshTasks() async {
        struct L: Decodable { var jobs: [TaskInfo] }
        if let l: L = try? await get("/api/jobs") { tasks = l.jobs }
    }

    // MARK: helpers for views

    func iconURL(_ app: SApp) -> URL? {
        guard app.hasIcon == true || app.customIcon == true else { return nil }
        return url("/api/apps/\(app.id)/icon?v=\(Int(app.iconVersion ?? 0))")
    }

    func iconURL(_ s: SSigned) -> URL? {
        guard s.hasIcon == true, let t = s.token else { return nil }
        return url("/i/\(t)/icon.png")
    }

    func category(_ id: String?) -> SCategory? { state?.categories?.first { $0.id == id } }
    func categoryLabel(_ id: String?) -> String {
        guard let c = category(id) else { return "Uncategorized" }
        return [c.emoji ?? "", c.name].filter { !$0.isEmpty }.joined(separator: " ")
    }
    var certs: [SCert] { state?.certs ?? [] }
    var defaultCert: SCert? { certs.first { $0.isDefault == true } ?? certs.first }
    var https: Bool { state?.server?.https ?? (baseURL?.scheme == "https") }
    var unreadAlerts: Int { (state?.alerts ?? []).filter { $0.read != true }.count }

    func screenshotURLs(_ app: SApp) -> [URL] {
        let local = (app.screenshots ?? []).compactMap { url("/api/apps/\(app.id)/screenshots/\($0.id)") }
        return local.isEmpty ? (app.remoteScreens ?? []).compactMap { URL(string: $0) } : local
    }

    /// What "Get" signs with: the app's own default sign settings and your default certificate.
    func signBodyFromDefaults(_ a: SApp, versionIndex: Int = 0) -> [String: Any] {
        let d = a.signDefaults ?? SignDefaults()
        let tweakIds = d.tweakIds.filter { tid in (state?.tweaks ?? []).contains { $0.id == tid } }
        return [
            "appId": a.id, "certId": defaultCert?.id ?? "", "minOS": d.minOS,
            "entitlements": d.entitlements.map { $0.json }, "plist": d.plist.map { $0.json },
            "removeExtensions": d.removeExtensions, "removeWatch": d.removeWatch ?? (a.hasWatch ?? false),
            "removeUISD": d.removeUISD, "enableDocs": d.enableDocs, "weakDylibs": d.weakDylibs,
            "injectExtensions": d.injectExtensions, "tweakIds": tweakIds, "versionIndex": versionIndex,
        ]
    }

    /// A signed copy that can be installed again instead of signing the same app twice.
    func reusableSigned(_ a: SApp) -> SSigned? {
        guard let cert = defaultCert else { return nil }
        let wanted = ((signBodyFromDefaults(a)["tweakIds"] as? [String]) ?? []).sorted()
        let since = parseDate(a.updatedAt ?? a.addedAt) ?? .distantPast
        return (state?.signed ?? []).first { s in
            guard s.appId == a.id, s.fileAvailable == true, s.certId == cert.id, (parseDate(s.signedAt) ?? .distantPast) >= since else { return false }
            let o = s.options
            return (o?.dylibs ?? []).isEmpty && o?.icon != true && (o?.versionIndex ?? 0) == 0 && (o?.tweakIds ?? []).sorted() == wanted
        }
    }
    func isFavorite(_ app: SApp) -> Bool { state?.favorites?.contains(app.id) == true }

    /// Uploads a file in one go (certificates, small files). Returns the upload id the server gives back.
    func upload(_ fileURL: URL) async throws -> String {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        return try await uploadData(try Data(contentsOf: fileURL))
    }

    func uploadData(_ body: Data) async throws -> String {
        let d = try await data("POST", "/api/upload", body: body, timeout: 300)
        guard let id = (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["uploadId"] as? String else {
            throw MangoError("The upload didn't work. Try again.")
        }
        return id
    }

    /// Downloads an app's original .ipa (for signing on this iPhone). Reports progress 0...1.
    func downloadIPA(_ app: SApp, versionIndex: Int, progress: @escaping (Double) -> Void) async throws -> URL {
        guard let u = url("/api/apps/\(app.id)/ipa?v=\(versionIndex)") else { throw MangoError("No server") }
        let dest = Paths.work.appendingPathComponent("\(UUID().uuidString.prefix(8))-download.ipa")
        let delegate = DownloadDelegate(progress: progress)
        let (tmp, resp) = try await session.download(for: URLRequest(url: u, timeoutInterval: 120), delegate: delegate)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(code) {
            let msg = (try? JSONSerialization.jsonObject(with: Data(contentsOf: tmp)) as? [String: Any])?["error"] as? String
            throw MangoError(msg ?? "Download failed (HTTP \(code))")
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }
}

final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progress: (Double) -> Void
    init(progress: @escaping (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.progress(p) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

// MARK: - Images from the server (with the login cookie), cached in memory

@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    func image(_ url: URL) async -> UIImage? {
        if let img = cache.object(forKey: url as NSURL) { return img }
        if let t = inFlight[url] { return await t.value }
        let t = Task<UIImage?, Never> {
            guard let (d, r) = try? await URLSession.shared.data(from: url),
                  ((r as? HTTPURLResponse)?.statusCode ?? 0) == 200, let img = UIImage(data: d) else { return nil }
            return img
        }
        inFlight[url] = t
        let img = await t.value
        inFlight[url] = nil
        if let img { cache.setObject(img, forKey: url as NSURL) }
        return img
    }
}
