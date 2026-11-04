import Foundation
import UIKit
import UserNotifications

/// Uploads big .ipa files with iOS's background transfer service, so they keep going when you leave the app
/// (or lock your iPhone). The file is split into the same numbered pieces the server already understands;
/// each piece is its own background upload, and failed pieces are sent again.
final class BackgroundUploader: NSObject, URLSessionDataDelegate {
    static let shared = BackgroundUploader()
    static let sessionId = "com.mangomods.mangosigner.uploads"

    /// Set by the app delegate when iOS wakes the app to finish background uploads.
    var systemCompletion: (() -> Void)?

    private let lock = NSLock()
    private struct Job {
        var count: Int
        var sizes: [Int: Int64]
        var sent: [Int: Int64] = [:]
        var done = Set<Int>()
        var tries: [Int: Int] = [:]
        var total: Int64
        var name: String
        var progress: (@MainActor (Double, String) -> Void)?
        var continuation: CheckedContinuation<Void, Error>?
        var began = Date()
    }
    private var jobs: [String: Job] = [:]

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.background(withIdentifier: BackgroundUploader.sessionId)
        c.sessionSendsLaunchEvents = true
        c.isDiscretionary = false
        c.httpCookieStorage = .shared
        c.httpCookieAcceptPolicy = .always
        c.timeoutIntervalForRequest = 300
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    /// Wakes the session up after a relaunch, so finished uploads are reported.
    func reconnect() { _ = session }

    private static func dir(_ uid: String) -> URL { Paths.work.appendingPathComponent("bg-\(uid)", isDirectory: true) }

    /// Sends every piece of `file` to the upload `uid` the server already started.
    func upload(_ file: URL, uid: String, pieceSize: Int64, count: Int, base: URL, name: String,
                progress: @escaping @MainActor (Double, String) -> Void) async throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        let folder = BackgroundUploader.dir(uid)
        await progress(0, "Getting the file ready…")
        // Background uploads must come from files, so the pieces are written out first.
        let sizes: [Int: Int64] = try await Task.detached(priority: .userInitiated) {
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var out: [Int: Int64] = [:]
            for i in 0..<count {
                try Task.checkCancellation()
                let offset = Int64(i) * pieceSize
                let length = Int(min(pieceSize, size - offset))
                try handle.seek(toOffset: UInt64(offset))
                guard let d = try handle.read(upToCount: length), d.count == length else { throw MangoError("Couldn't read the file. Pick it again.") }
                try d.write(to: folder.appendingPathComponent("\(i).part"))
                out[i] = Int64(length)
            }
            return out
        }.value
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                lock.lock()
                jobs[uid] = Job(count: count, sizes: sizes, total: size, name: name, progress: progress, continuation: cont)
                lock.unlock()
                for i in 0..<count { send(uid: uid, index: i, base: base) }
            }
        } onCancel: { [weak self] in
            self?.cancel(uid)
        }
    }

    private func send(uid: String, index: Int, base: URL) {
        guard let u = URL(string: "/api/upload/\(uid)?index=\(index)", relativeTo: base)?.absoluteURL else { return }
        var req = URLRequest(url: u)
        req.httpMethod = "PUT"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        for (k, v) in HTTPCookie.requestHeaderFields(with: HTTPCookieStorage.shared.cookies(for: u) ?? []) { req.setValue(v, forHTTPHeaderField: k) }
        let task = session.uploadTask(with: req, fromFile: BackgroundUploader.dir(uid).appendingPathComponent("\(index).part"))
        task.taskDescription = "\(uid):\(index):\(base.absoluteString)"
        task.resume()
    }

    private func cancel(_ uid: String) {
        session.getAllTasks { tasks in
            for t in tasks where t.taskDescription?.hasPrefix(uid + ":") == true { t.cancel() }
        }
        finish(uid, error: CancellationError())
    }

    private func finish(_ uid: String, error: Error?) {
        lock.lock()
        let job = jobs.removeValue(forKey: uid)
        lock.unlock()
        try? FileManager.default.removeItem(at: BackgroundUploader.dir(uid))
        if let c = job?.continuation {
            if let error { c.resume(throwing: error) } else { c.resume() }
        }
        if error == nil, let name = job?.name {
            DispatchQueue.main.async {
                guard UIApplication.shared.applicationState != .active else { return }
                let n = UNMutableNotificationContent()
                n.title = "✅ \(name) is uploaded"
                n.body = "Open Mango Signer to keep going."
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "upload-\(uid)", content: n, trigger: nil))
            }
        }
    }

    private func report(_ uid: String) {
        lock.lock()
        guard let j = jobs[uid] else { lock.unlock(); return }
        var sent: Int64 = 0
        for i in 0..<j.count { sent += j.done.contains(i) ? (j.sizes[i] ?? 0) : (j.sent[i] ?? 0) }
        let rate = Double(sent) / max(1, Date().timeIntervalSince(j.began))
        let p = j.total > 0 ? Double(sent) / Double(j.total) : 0
        let line = "\(formatBytes(Double(sent))) of \(formatBytes(Double(j.total))) · \(formatBytes(rate))/s · keeps going if you leave the app"
        let cb = j.progress
        lock.unlock()
        if let cb { Task { @MainActor in cb(min(1, p), line) } }
    }

    // MARK: URLSession delegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let parts = task.taskDescription?.split(separator: ":", maxSplits: 2), parts.count == 3, let i = Int(parts[1]) else { return }
        let uid = String(parts[0])
        lock.lock(); jobs[uid]?.sent[i] = totalBytesSent; lock.unlock()
        report(uid)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let parts = task.taskDescription?.split(separator: ":", maxSplits: 2), parts.count == 3, let i = Int(parts[1]),
              let base = URL(string: String(parts[2])) else { return }
        let uid = String(parts[0])
        let code = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        lock.lock()
        guard var j = jobs[uid] else { lock.unlock(); return } // cancelled, or from before the app was closed
        if error == nil && (200..<300).contains(code) {
            j.done.insert(i)
            try? FileManager.default.removeItem(at: BackgroundUploader.dir(uid).appendingPathComponent("\(i).part"))
            jobs[uid] = j
            let all = j.done.count == j.count
            lock.unlock()
            report(uid)
            if all { finish(uid, error: nil) }
            return
        }
        if (error as? URLError)?.code == .cancelled { lock.unlock(); return }
        if code == 404 { lock.unlock(); finish(uid, error: MangoError("The upload expired. Pick the file again.")); return }
        let tries = (j.tries[i] ?? 0) + 1
        j.tries[i] = tries
        j.sent[i] = 0
        jobs[uid] = j
        lock.unlock()
        if tries > 8 { finish(uid, error: MangoError("The upload keeps failing. Check your connection and try again.")); return }
        DispatchQueue.global().asyncAfter(deadline: .now() + min(20, Double(tries) * 1.5)) { [weak self] in self?.send(uid: uid, index: i, base: base) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.systemCompletion?()
            self?.systemCompletion = nil
        }
    }
}

/// Lets iOS hand finished background uploads back to the app.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == BackgroundUploader.sessionId else { completionHandler(); return }
        BackgroundUploader.shared.systemCompletion = completionHandler
        BackgroundUploader.shared.reconnect()
    }
}
