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
    /// "admin" or "tester" (given by the owner), nil for everyone else.
    var rank: String?
    var isOwner: Bool { role == "owner" }
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        role = c.str("role") ?? "user"
        rank = c.str("rank")
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
    /// The version's real number for signing (lists may skip beta versions for non-testers).
    var vi: Int?
    var version: String?
    var date: String?
    var size: Double?
    var notes: String?
    var channel: String?
    var manualId: String?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        vi = c.int("vi")
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
    var useVersionWhenSigning: Bool?
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
    var testersOnly = false
    var madeByMango = false
    // Your own imported apps (the Apps tab)
    var isImport = false
    var importId: String?
    var iconSrc: String?
    var onGithub = false
    var savingToGithub = false
    var expires: String?
    var available = true
    var fileName: String?
    var lastSigned: String?
    /// "Spanish" etc. when the description was translated to English.
    var translatedFrom: String?
    /// Set for an app saved on this iPhone (not decoded from the server).
    var localFile: URL?
    var localIcon: URL?
    var localId: UUID?

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
        useVersionWhenSigning = c.bool("useVersionWhenSigning")
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
        testersOnly = c.bool("testersOnly") ?? false
        madeByMango = c.bool("madeByMango") ?? false
        isImport = c.bool("isImport") ?? false; importId = c.str("importId"); iconSrc = c.str("iconSrc")
        onGithub = c.bool("onGithub") ?? false; savingToGithub = c.bool("savingToGithub") ?? false; expires = c.str("expires")
        available = c.bool("available") ?? true; fileName = c.str("fileName"); lastSigned = c.str("lastSigned")
        translatedFrom = c.str("translatedFrom")
        let added = parseDate(addedAt), updated = parseDate(updatedAt)
        isNew = Date().timeIntervalSince(added ?? .distantPast) < 3 * 86400
        isUpdatedRecently = !isNew && previousVersion != nil && Date().timeIntervalSince(updated ?? .distantPast) < 3 * 86400
        sortDate = updated ?? added ?? .distantPast
    }

    var shownVersion: String { [versionOverride, version].compactMap { $0 }.first { !$0.isEmpty } ?? "" }
    var hasUpdate: Bool { installed?.update == true && installed?.stopped == nil }
    var isStopped: Bool { installed?.stopped != nil }
    // Worked out once when the library loads (sorting thousands of apps re-reads these constantly).
    var isNew = false
    var isUpdatedRecently = false
    var sortDate = Date.distantPast
    var isSourceApp: Bool { cloud == "source" || cloud == "telegram" }
    var votes: Int { (likes ?? 0) + (dislikes ?? 0) }
    var score: Int { (likes ?? 0) - (dislikes ?? 0) }
    var getLabel: String { hasUpdate ? "Update" : isStopped ? "Fix" : "Get" }

    /// An app saved on this iPhone, shaped like a library app so the sign screen can use it.
    static func local(_ l: LibraryApp) -> SApp? {
        let d: [String: Any] = ["id": "local_\(l.id.uuidString)", "name": l.name, "bundleId": l.bundleId, "version": l.version, "build": l.build,
                                "minOS": l.minOS, "size": Double(l.size), "hasIcon": FileManager.default.fileExists(atPath: Paths.icon(l.id).path), "addedAt": ISO8601DateFormatter().string(from: l.addedAt)]
        guard let data = try? JSONSerialization.data(withJSONObject: d), var a = try? JSONDecoder().decode(SApp.self, from: data) else { return nil }
        a.localFile = l.url; a.localIcon = Paths.icon(l.id); a.localId = l.id
        return a
    }
}

/// A hand-picked list of apps shown in the library (owner and admins make these).
struct SCollection: Decodable, Identifiable {
    var id: String
    var name: String
    var emoji: String?
    var appIds: [String]
    var description: String?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        description = c.str("description")
        id = c.str("id") ?? UUID().uuidString; name = c.str("name") ?? ""; emoji = c.str("emoji"); appIds = c.strings("appIds") ?? []
    }
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
    var bugId: String?
    var signedId: String?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        id = c.str("id") ?? UUID().uuidString; kind = c.str("kind"); title = c.str("title"); body = c.str("body")
        at = c.str("at"); read = c.bool("read"); appId = c.str("appId"); requestId = c.str("requestId"); userId = c.str("userId"); bugId = c.str("bugId"); signedId = c.str("signedId")
    }
}

struct SSettings: Decodable {
    var signsPerDay: Int?
    var signsToday: Int?
    var everyoneSignsPerDay: Int?
    var maxSignedPerUser: Int?
    var signedRetentionDays: Int?
    var signedOnGithub: Bool?
    var zipLevel: Int?
    var deleteAfterInstall: Bool?
    var udidLogin: Bool?
    var lastBackup: String?
    var catRules: [SCatRule] = []
    var translateOn = false
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        catRules = c.list("catRules") ?? []
        translateOn = c.bool("translateOn") ?? false
        signsPerDay = c.int("signsPerDay"); signsToday = c.int("signsToday"); everyoneSignsPerDay = c.int("everyoneSignsPerDay"); maxSignedPerUser = c.int("maxSignedPerUser")
        signedRetentionDays = c.int("signedRetentionDays"); signedOnGithub = c.bool("signedOnGithub"); zipLevel = c.int("zipLevel")
        deleteAfterInstall = c.bool("deleteAfterInstall"); udidLogin = c.bool("udidLogin"); lastBackup = c.str("lastBackup")
    }
}

/// "Apps whose name mentions these words go in this category" (owner's auto-sort rules).
struct SCatRule: Decodable {
    var words: String
    var categoryId: String?
    init(from decoder: Decoder) throws { let c = try keyed(decoder); words = c.str("words") ?? ""; categoryId = c.str("categoryId") }
    init(words: String, categoryId: String?) { self.words = words; self.categoryId = categoryId }
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
    var style: String?
    init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) { text = s; return }
        text = try keyed(decoder).str("text"); style = try keyed(decoder).str("style")
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
    var author: String?
    var published = true
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        author = c.str("author"); published = c.bool("published") ?? true
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
    /// The role everyone who joins with it gets ("tester" or "admin"), if any.
    var rank: String?
    var id: String { code }
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        code = c.str("code") ?? ""; note = c.str("note"); maxUses = c.int("maxUses") ?? 1; uses = c.int("uses") ?? 0
        usedBy = c.strings("usedBy") ?? []; expiresAt = c.str("expiresAt"); rank = c.str("rank")
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

struct SBug: Decodable, Identifiable {
    var id: String
    var username: String?
    var text: String
    var appId: String?
    var appName: String?
    var device: String?
    var status: String
    var reply: String?
    var createdAt: String?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        id = c.str("id") ?? UUID().uuidString; username = c.str("username"); text = c.str("text") ?? ""; appId = c.str("appId")
        appName = c.str("appName"); device = c.str("device"); status = c.str("status") ?? "open"; reply = c.str("reply"); createdAt = c.str("createdAt")
    }
}

struct SUser: Decodable, Identifiable {
    var id: String
    var username: String
    var rank: String?
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
        id = c.str("id") ?? UUID().uuidString; username = c.str("username") ?? "?"; rank = c.str("rank"); udid = c.str("udid"); deviceName = c.str("deviceName")
        createdAt = c.str("createdAt"); lastLogin = c.str("lastLogin"); disabled = c.bool("disabled") ?? false; invite = c.str("invite")
        certCount = c.int("certCount") ?? 0; signedCount = c.int("signedCount") ?? 0; signLimit = c.int("signLimit"); signsToday = c.int("signsToday") ?? 0
        recentSignins = c.list("recentSignins") ?? []
    }
}

struct SGithubInfo: Decodable {
    var connected: Bool
    var signedToGithub: Bool
    var storeUploads: Bool
    var owner: String?
    var repo: String?
    var tag: String?
    var isPrivate: Bool
    var apps: Int
    var lastSync: String?
    var lastError: String?
    var signedSaved: Int
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        connected = c.bool("connected") ?? false; signedToGithub = c.bool("signedToGithub") ?? false
        storeUploads = c.bool("storeUploads") ?? false
        owner = c.str("owner"); repo = c.str("repo"); tag = c.str("tag"); isPrivate = c.bool("private") ?? false
        apps = c.int("apps") ?? 0; lastSync = c.str("lastSync"); lastError = c.str("lastError"); signedSaved = c.int("signedSaved") ?? 0
    }
}

/// A source (AltStore-style list, GitHub repo, downloads page) or a Telegram channel.
struct SSource: Decodable, Identifiable {
    struct Options: Decodable {
        var storage: String?
        var skipHave: Bool?
        var updateMine: Bool?
        var matchName: Bool?
        var captionNotes: Bool?
        var autoSync: Bool?
        var keywords: String?
        init(from decoder: Decoder) throws {
            let c = try keyed(decoder)
            storage = c.str("storage"); skipHave = c.bool("skipHave"); updateMine = c.bool("updateMine"); matchName = c.bool("matchName")
            captionNotes = c.bool("captionNotes"); autoSync = c.bool("autoSync"); keywords = c.str("keywords")
        }
        init() {}
    }
    struct Result: Decodable {
        var added = 0, updated = 0, same = 0, failed = 0
        init(from decoder: Decoder) throws {
            let c = try keyed(decoder)
            added = c.int("added") ?? 0; updated = c.int("updated") ?? 0; same = c.int("same") ?? 0; failed = c.int("failed") ?? 0
        }
    }
    struct Excluded: Decodable { var name: String?; var bundleId: String?
        init(from decoder: Decoder) throws { let c = try keyed(decoder); name = c.str("name"); bundleId = c.str("bundleId") }
    }
    var id: String
    var kind: String
    var name: String
    var url: String
    var iconURL: String?
    var subtitle: String?
    var username: String?
    var apps: Int
    var lastSync: String?
    var lastError: String?
    var showInLibrary: Bool
    var skipHave: Bool?
    var pinned: Bool?
    var repoOwner: String?
    var repoName: String?
    var categoryId: String?
    var options: Options
    var lastResult: Result?
    var excluded: [Excluded]
    var deepest: Int?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        guard let id = c.str("id") else { throw SApp.NoId() }
        self.id = id
        kind = c.str("kind") ?? "source"; name = c.str("name") ?? "Source"; url = c.str("url") ?? ""
        iconURL = c.str("iconURL"); subtitle = c.str("subtitle"); username = c.str("username")
        apps = c.int("apps") ?? 0; lastSync = c.str("lastSync"); lastError = c.str("lastError")
        showInLibrary = c.bool("showInLibrary") ?? true; skipHave = c.bool("skipHave"); pinned = c.bool("pinned")
        struct Repo: Decodable { var owner: String?; var repo: String? }
        let r: Repo? = c.obj("repo")
        repoOwner = r?.owner; repoName = r?.repo
        categoryId = c.str("categoryId"); options = c.obj("options") ?? Options(); lastResult = c.obj("lastResult")
        excluded = c.list("excluded") ?? []; deepest = c.int("deepest")
    }
    var isTelegram: Bool { kind == "telegram" }
    /// Sources with "Mango" in the name start out pinned (same as the website).
    var isPinned: Bool { pinned ?? (name.range(of: "mango", options: .caseInsensitive) != nil) }
}

struct STelegramInfo: Decodable {
    var connected: Bool
    var pending: String?
    var meName: String?
    var meUsername: String?
    var mePhone: String?
    var error: String?
    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        connected = c.bool("connected") ?? false; pending = c.str("pending"); error = c.str("error")
        struct Me: Decodable { var name: String?; var username: String?; var phone: String? }
        let me: Me? = c.obj("me")
        meName = me?.name; meUsername = me?.username; mePhone = me?.phone
    }
}

struct ServerState: Decodable {
    var account: Account
    var apps: [SApp]
    var imports: [SApp]
    var importsOnGithub = false
    var categories: [SCategory]?
    var collections: [SCollection]
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
    var bugs: [SBug]
    var invites: [SInvite]
    var users: [SUser]
    var mySignins: [SSignin]
    var securityLog: [SSignin]
    var github: SGithubInfo?
    var sources: [SSource]
    var telegram: STelegramInfo?
    var skipped = 0

    init(from decoder: Decoder) throws {
        let c = try keyed(decoder)
        account = try c.decode(Account.self, forKey: AnyKey("account"))
        let rawApps = (try? c.decodeIfPresent([Lossy<SApp>].self, forKey: AnyKey("apps"))) ?? []
        apps = rawApps.compactMap { $0.value }
        skipped = rawApps.count - apps.count
        imports = c.list("imports") ?? []
        importsOnGithub = c.bool("importsOnGithub") ?? false
        categories = c.list("categories")
        collections = c.list("collections") ?? []
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
        bugs = c.list("bugs") ?? []
        invites = c.list("invites") ?? []
        users = c.list("users") ?? []
        mySignins = c.list("mySignins") ?? []
        securityLog = c.list("securityLog") ?? []
        github = c.obj("github")
        sources = c.list("sources") ?? []
        telegram = c.obj("telegram")
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
    return dayOnly.date(from: String(s.prefix(10)))
}
private let dayOnly: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
private let relative: RelativeDateTimeFormatter = { let f = RelativeDateTimeFormatter(); f.unitsStyle = .full; return f }()

func ago(_ s: String?) -> String {
    guard let d = parseDate(s) else { return "" }
    return relative.localizedString(for: d, relativeTo: Date())
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
    @Published var state: ServerState? { didSet { libCache.removeAll(); countCache.removeAll(); appIndex = Dictionary(((state?.apps ?? []) + (state?.imports ?? [])).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) } }
    /// Library lists and filter counts, worked out once per library load instead of on every redraw.
    var libCache: [String: [SApp]] = [:]
    var countCache: [String: Int] = [:]
    var appIndex: [String: SApp] = [:]
    func app(_ id: String?) -> SApp? { id.flatMap { appIndex[$0] } }
    @Published var authed = false
    @Published var checking = true
    @Published var tasks: [TaskInfo] = []
    /// Why the library couldn't be loaded (shown on screen instead of failing quietly).
    @Published var loadError: String?

    var account: Account? { state?.account }
    var isOwner: Bool { account?.isOwner == true }
    /// Admins help run the library and users; testers see "Testers only" apps and beta versions first.
    var isAdmin: Bool { account?.isOwner == false && account?.rank == "admin" }
    var isStaff: Bool { isOwner || isAdmin }
    var isTester: Bool { account?.isOwner == false && account?.rank == "tester" }
    var seesTesterApps: Bool { isStaff || isTester }

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

    private var sessionCheck: Task<Void, Never>?
    /// One check at a time (a second call waits for the first), and it isn't stopped if the screen changes.
    func checkSession() async {
        if let running = sessionCheck { await running.value; return }
        let t = Task { await runSessionCheck() }
        sessionCheck = t
        await t.value
        sessionCheck = nil
    }

    private func runSessionCheck() async {
        checking = true
        defer { checking = false }
        guard baseURL != nil else { authed = false; return }
        if let s: SessionInfo = try? await get("/api/session"), s.authed {
            authed = true
            await refresh()
        } else if let saved = savedLogin, mayAutoLogin {
            // Signed out (new install, or the session ran out): sign back in with the saved login, at most once a
            // minute. If it doesn't work (password changed, or the server says too many tries), say why and stop.
            lastAutoLogin = Date()
            do { try await login(username: saved.0, password: saved.1); autoLoginError = nil } catch {
                authed = false
                autoLoginError = "Couldn't sign you back in automatically: \(error.localizedDescription)"
            }
        } else {
            authed = false
        }
    }

    private var lastAutoLogin = Date.distantPast
    /// Why the automatic sign-in didn't work (shown on the sign-in screen).
    @Published var autoLoginError: String?
    var mayAutoLogin: Bool { Date().timeIntervalSince(lastAutoLogin) > 60 }

    /// Puts a signed app's file back on the server from the copy on this iPhone, so it can be installed again.
    func restoreSigned(_ s: SSigned, from copy: SignedApp) async throws -> SSigned? {
        let id = try await upload(copy.url)
        struct R: Decodable { var signed: SSigned }
        let d = try await data("POST", "/api/signed/\(s.id)/restore", json: ["uploadId": id], timeout: 300)
        await refresh()
        return (try? JSONDecoder().decode(R.self, from: d))?.signed
    }

    // MARK: what's really on this iPhone

    /// Bumped after checking the iPhone, so screens showing "Installed" redraw.
    @Published var deviceCheck = 0
    private var lastDeviceSync = Date.distantPast

    /// The bundle IDs a library app could be installed under (its own, or whatever you signed it as).
    func bundleIds(for a: SApp) -> [String] {
        var ids = (state?.signed ?? []).filter { $0.appId == a.id }.compactMap { $0.bundleId }
        if let b = a.bundleId { ids.append(b) }
        var seen = Set<String>()
        return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The installed version of a library app on this iPhone, "" if it's installed but iOS gives no version,
    /// or nil if it isn't installed (or iOS can't tell).
    func installedVersion(_ a: SApp) -> String? {
        for id in bundleIds(for: a) where DeviceApps.isInstalled(id) == true { return DeviceApps.version(id) ?? "" }
        return nil
    }

    /// Keeps "your installed apps" true to the iPhone: apps you deleted drop off, and apps you already updated
    /// stop asking to be updated. Only runs when iOS really answers.
    func syncWithDevice(force: Bool = false) async {
        guard DeviceApps.available, let st = state else { return }
        guard force || Date().timeIntervalSince(lastDeviceSync) > 20 else { return }
        lastDeviceSync = Date()
        DeviceApps.rescan()
        var changed = false
        for a in st.apps where a.installed != nil {
            let ids = bundleIds(for: a)
            if DeviceApps.installedByName(a.name) != nil { continue } // there under another app ID
            guard !ids.isEmpty else { continue }
            let here = ids.filter { DeviceApps.isInstalled($0) == true }
            if here.isEmpty {
                // Only when iOS really answers about other apps (otherwise "not installed" means nothing).
                let gone = ids.allSatisfy { DeviceApps.isInstalled($0) == false }
                if gone, (try? await post("/api/my-apps/\(a.id)", ["action": "remove"])) != nil { changed = true }
            } else if a.hasUpdate {
                let newest = here.compactMap { DeviceApps.version($0) }.max { versionCompare($0, $1) < 0 }
                if let v = newest, versionCompare(v, a.shownVersion) >= 0,
                   (try? await post("/api/my-apps/\(a.id)", ["action": "latest"])) != nil { changed = true }
            }
        }
        if changed { await refresh() }
        deviceCheck += 1
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

    /// Counts refreshes, so an older one that finishes late can't put old data back on screen.
    private var refreshGen = 0
    /// The server's fingerprint of the library we already have. Sent back so an unchanged library isn't downloaded again.
    private var stateTag: String?

    @discardableResult
    func refresh() async -> String? {
        refreshGen += 1
        let gen = refreshGen
        do {
            var d: Data?
            // Quick check first: "do I already have this?" The server answers with a tiny "yes" when nothing changed,
            // so there's no download, no reading 6,000 apps and no redraw.
            if let u = url("/api/state") {
                var req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
                if let t = stateTag, state != nil { req.setValue(t, forHTTPHeaderField: "If-None-Match") }
                if let (body, resp) = try? await session.data(for: req), let http = resp as? HTTPURLResponse {
                    if http.statusCode == 304 { loadError = nil; return nil }
                    if http.statusCode == 200 { d = body; stateTag = http.value(forHTTPHeaderField: "ETag") }
                }
            }
            // Anything else (signed out, server down…) goes the normal way, which explains what's wrong.
            if d == nil { d = try await data("GET", "/api/state"); stateTag = nil }
            guard let d else { return loadError }
            do {
                // Reading a big library takes a moment; do it off the main thread so the app never freezes.
                let decoded = try await Task.detached(priority: .userInitiated) { try JSONDecoder().decode(ServerState.self, from: d) }.value
                guard gen == refreshGen else { return loadError }
                state = decoded
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
        if let f = app.localIcon { return app.hasIcon == true ? f : nil }
        if app.isImport { return app.iconSrc.flatMap { url($0) } }
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

    /// Uploads a big file (an .ipa) in 8 MB pieces, a few at a time, retrying pieces if the connection drops —
    /// the same way the website does. Small files go up in one go. Returns the upload id.
    /// background: big files keep uploading when you leave the app (iOS background transfers).
    func uploadLarge(_ fileURL: URL, purpose: String? = nil, background: Bool = false, name: String = "Your app",
                     progress: @escaping @MainActor (Double, String) -> Void) async throws -> String {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw MangoError("That file is empty.") }
        let chunk: Int64 = 8 * 1024 * 1024
        if size <= chunk {
            progress(0, "Uploading…")
            let id = try await uploadData(try Data(contentsOf: fileURL))
            progress(1, "Uploaded")
            return id
        }
        var startBody: [String: Any] = ["size": size, "chunkSize": chunk]
        if let purpose { startBody["purpose"] = purpose }
        let start = try await post("/api/upload/start", startBody)
        guard let uid = start["uploadId"] as? String else { throw MangoError("The server didn't start the upload. Try again.") }
        let piece = (start["chunkSize"] as? NSNumber)?.int64Value ?? chunk
        let count = (start["count"] as? NSNumber)?.intValue ?? Int((size + piece - 1) / piece)
        if background, count > 2, let base = baseURL {
            try await BackgroundUploader.shared.upload(fileURL, uid: uid, pieceSize: piece, count: count, base: base, name: name, progress: progress)
            return uid
        }
        let began = Date()
        final class Tally: @unchecked Sendable { var sent: Int64 = 0; var next = 0; let lock = NSLock() }
        let tally = Tally()
        func take() -> Int? { tally.lock.lock(); defer { tally.lock.unlock() }; guard tally.next < count else { return nil }; tally.next += 1; return tally.next - 1 }
        func sendPiece(_ i: Int) async throws {
            let offset = Int64(i) * piece
            let length = Int(min(piece, size - offset))
            let body: Data = try await Task.detached(priority: .userInitiated) {
                let handle = try FileHandle(forReadingFrom: fileURL)
                defer { try? handle.close() }
                try handle.seek(toOffset: UInt64(offset))
                guard let d = try handle.read(upToCount: length), d.count == length else { throw MangoError("Couldn't read the file. Pick it again.") }
                return d
            }.value
            var failures = 0
            while true {
                do {
                    _ = try await data("PUT", "/api/upload/\(uid)?index=\(i)", body: body, timeout: 300)
                    break
                } catch {
                    if (error as? MangoError)?.message.contains("expired") == true { throw error }
                    failures += 1
                    if failures > 8 { throw MangoError("The upload keeps failing. Check your connection and try again.") }
                    let wait = min(15.0, 0.8 * Double(failures))
                    progress(Double(tally.sent) / Double(size), "Connection dropped — retrying (\(failures))…")
                    try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                }
            }
            tally.lock.lock(); tally.sent += Int64(length); let sent = tally.sent; tally.lock.unlock()
            let rate = Double(sent) / max(1, Date().timeIntervalSince(began))
            progress(Double(sent) / Double(size), "\(formatBytes(Double(sent))) of \(formatBytes(Double(size))) · \(formatBytes(rate))/s")
        }
        progress(0, "Uploading…")
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<min(3, count) {
                group.addTask { @MainActor in while let i = take() { try await sendPiece(i) } }
            }
            try await group.waitForAll()
        }
        return uid
    }

    /// Waits for a server job (adding or updating an app) and returns its result. Reports the progress and last log line.
    func waitJob(_ id: String, update: @escaping @MainActor (Double?, String) -> Void) async throws -> [String: Any] {
        var misses = 0
        while true {
            try await Task.sleep(nanoseconds: 900_000_000)
            try Task.checkCancellation()
            let j: [String: Any]
            do {
                j = (try JSONSerialization.jsonObject(with: try await data("GET", "/api/jobs/\(id)")) as? [String: Any]) ?? [:]
                misses = 0
            } catch {
                misses += 1
                if misses > 60 { throw error }
                try await Task.sleep(nanoseconds: UInt64(min(10, misses)) * 1_000_000_000)
                continue
            }
            let status = j["status"] as? String ?? "running"
            let last = (j["log"] as? [String])?.last ?? (j["last"] as? String) ?? "Working…"
            update((j["progress"] as? NSNumber)?.doubleValue, last)
            switch status {
            case "done": return j["result"] as? [String: Any] ?? [:]
            case "error", "cancelled": throw MangoError(j["error"] as? String ?? "That didn't work.")
            default: continue
            }
        }
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
        let path = app.isImport ? "/api/imports/\(app.importId ?? "")/file" : "/api/apps/\(app.id)/ipa?v=\(versionIndex)"
        guard let u = url(path) else { throw MangoError("No server") }
        return try await downloadFile(u, progress: progress)
    }

    /// Downloads any file from the server to a temporary place on this iPhone.
    func downloadFile(_ u: URL, progress: @escaping (Double) -> Void) async throws -> URL {
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

/// Icons are downloaded, decoded and shrunk off the main thread, so scrolling never waits on them.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache: NSCache<NSURL, UIImage> = { let c = NSCache<NSURL, UIImage>(); c.countLimit = 600; return c }()
    @MainActor private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    /// Forgets every picture kept in memory (they download again when shown).
    func clear() { cache.removeAllObjects() }

    /// Already downloaded (NSCache is safe to read from anywhere).
    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    @MainActor
    func image(_ url: URL, maxPixels: CGFloat = 0) async -> UIImage? {
        if let img = cache.object(forKey: url as NSURL) { return img }
        if let t = inFlight[url] { return await t.value }
        let t = Task.detached(priority: .utility) { () -> UIImage? in
            guard let (d, r) = try? await URLSession.shared.data(from: url),
                  url.isFileURL || ((r as? HTTPURLResponse)?.statusCode ?? 0) == 200, let img = UIImage(data: d) else { return nil }
            if maxPixels > 0, max(img.size.width, img.size.height) * img.scale > maxPixels {
                return await img.byPreparingThumbnail(ofSize: CGSize(width: maxPixels, height: maxPixels)) ?? img.preparingForDisplay() ?? img
            }
            return await img.byPreparingForDisplay() ?? img
        }
        inFlight[url] = t
        let img = await t.value
        inFlight[url] = nil
        if let img { cache.setObject(img, forKey: url as NSURL) }
        return img
    }
}
