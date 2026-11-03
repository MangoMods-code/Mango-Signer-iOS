import Foundation
import SwiftUI
import UIKit

// MARK: - What the Mango Signer server sends (only the fields the app uses; everything is optional
// so a newer or older server never breaks decoding)

struct Account: Decodable {
    var id: String
    var username: String
    var role: String
    var udid: String?
    var deviceName: String?
    var isOwner: Bool { role == "owner" }
}

struct SInstalled: Decodable {
    var version: String?
    var at: String?
    var stopped: String?
    var update: Bool?
}

struct SVersion: Decodable {
    var version: String?
    var date: String?
    var size: Double?
    var notes: String?
    var channel: String?
    var manualId: String?
}

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
    var tags: [String]?

    var shownVersion: String { [versionOverride, version].compactMap { $0 }.first { !$0.isEmpty } ?? "" }
    var hasUpdate: Bool { installed?.update == true && installed?.stopped == nil }
    var isStopped: Bool { installed?.stopped != nil }
    var isNew: Bool { (Date().timeIntervalSince(parseDate(addedAt) ?? .distantPast)) < 3 * 86400 }
    var isUpdatedRecently: Bool {
        !isNew && previousVersion != nil && (Date().timeIntervalSince(parseDate(updatedAt) ?? .distantPast)) < 3 * 86400
    }
    var sortDate: Date { parseDate(updatedAt) ?? parseDate(addedAt) ?? .distantPast }
}

struct SCategory: Decodable, Identifiable {
    var id: String
    var name: String
    var emoji: String?
    var order: Int?
}

struct SProfile: Decodable {
    var name: String?
    var type: String?
    var teamName: String?
    var expires: String?
    var deviceCount: Int?
}

struct SP12: Decodable {
    var commonName: String?
    var validTo: String?
}

struct SCheck: Decodable {
    var status: String?
}

struct SCert: Decodable, Identifiable {
    var id: String
    var label: String
    var isDefault: Bool?
    var p12: SP12?
    var profile: SProfile?
    var check: SCheck?
    var deviceIncluded: Bool?

    var expires: Date? { [parseDate(p12?.validTo), parseDate(profile?.expires)].compactMap { $0 }.min() }
    var daysLeft: Int? { expires.map { Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0 } }
}

struct SSigned: Decodable, Identifiable {
    var id: String
    var name: String
    var appId: String?
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
}

struct SAlert: Decodable, Identifiable {
    var id: String
    var kind: String?
    var title: String?
    var body: String?
    var at: String?
    var read: Bool?
    var appId: String?
}

struct SSettings: Decodable {
    var signsPerDay: Int?
    var signsToday: Int?
}

struct SServerInfo: Decodable {
    var version: String?
    var https: Bool?
    var baseUrl: String?
}

struct SAnnouncement: Decodable {
    var text: String?
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
}

struct SessionInfo: Decodable {
    var authed: Bool
    var account: Account?
    var udidLogin: Bool?
    var version: String?
}

struct JobResult: Decodable {
    var signed: SSigned?
}

struct JobStatus: Decodable {
    var status: String
    var log: [String]?
    var error: String?
    var progress: Double?
    var result: JobResult?
}

struct InstallStatus: Decodable {
    var phase: String
    var progress: Double?
    var sent: Double?
    var size: Double?
}

struct WhatsNewSection: Decodable {
    var title: String
    var items: [String]
}

struct WhatsNewEntry: Decodable, Identifiable {
    var version: String
    var date: String?
    var title: String?
    var summary: String?
    var sections: [WhatsNewSection]?
    var id: String { version }
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
    @Published var baseURL: URL? = UserDefaults.standard.url(forKey: "serverURL")
    @Published var state: ServerState?
    @Published var authed = false
    @Published var checking = true
    @Published var tasks: [TaskInfo] = []

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
        } else {
            authed = false
        }
    }

    func login(username: String, password: String) async throws {
        try await post("/api/login", ["username": username, "password": password])
        authed = true
        await refresh()
    }

    func signup(username: String, password: String, invite: String) async throws {
        try await post("/api/signup", ["username": username, "password": password, "invite": invite])
        authed = true
        await refresh()
    }

    func logout() async {
        _ = try? await post("/api/logout")
        if let cookies = HTTPCookieStorage.shared.cookies { cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) } }
        state = nil
        authed = false
    }

    @discardableResult
    func refresh() async -> String? {
        do {
            state = try await get("/api/state")
            return nil
        } catch {
            return error.localizedDescription
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
    func isFavorite(_ app: SApp) -> Bool { state?.favorites?.contains(app.id) == true }

    /// Uploads a file in one go (certificates, small files). Returns the upload id the server gives back.
    func upload(_ fileURL: URL) async throws -> String {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        let body = try Data(contentsOf: fileURL)
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
