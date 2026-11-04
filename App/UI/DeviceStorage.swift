import SwiftUI

/// How full this iPhone is, and how much of that is Mango Signer.
struct DeviceStorageInfo: Sendable {
    var total: Double = 0
    var free: Double = 0
    var apps: Double = 0       // .ipa files added to "Apps on this iPhone"
    var signed: Double = 0     // signed copies kept on this iPhone
    var certs: Double = 0      // certificates and icons
    var temp: Double = 0       // downloads in progress, leftovers and cached pictures
    var mango: Double { apps + signed + certs + temp }

    static func folderSize(_ url: URL) -> Double {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Double = 0
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]), v.isRegularFile == true else { continue }
            total += Double(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    static var caches: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0] }

    /// Adds everything up (reads a lot of files, so run it off the main thread).
    static func measure() -> DeviceStorageInfo {
        var i = DeviceStorageInfo()
        if let v = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]) {
            i.total = Double(v.volumeTotalCapacity ?? 0)
            i.free = Double(v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0))
        }
        i.apps = folderSize(Paths.apps)
        i.signed = folderSize(Paths.signed)
        i.certs = folderSize(Paths.certs) + folderSize(Paths.icons)
        i.temp = folderSize(FileManager.default.temporaryDirectory) + folderSize(caches)
        return i
    }

    /// Removes temporary files and cached pictures. Files from the last 10 minutes are left alone,
    /// in case something is downloading or signing right now. Returns how much was freed.
    static func clearTemp() -> Double {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-600)
        var freed: Double = 0
        for dir in [fm.temporaryDirectory, caches] {
            guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .totalFileAllocatedSizeKey]) else { continue }
            for case let f as URL in e {
                guard let v = try? f.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .totalFileAllocatedSizeKey]),
                      v.isRegularFile == true, (v.contentModificationDate ?? .distantPast) < cutoff else { continue }
                if (try? fm.removeItem(at: f)) != nil { freed += Double(v.totalFileAllocatedSize ?? 0) }
            }
        }
        URLCache.shared.removeAllCachedResponses()
        try? fm.createDirectory(at: Paths.work, withIntermediateDirectories: true)
        return freed
    }
}

struct DeviceStorageCard: View {
    @EnvironmentObject var local: LocalStore
    @EnvironmentObject var router: Router
    @State private var info: DeviceStorageInfo?
    @State private var clearing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let i = info, i.total > 0 {
                let used = max(0, i.total - i.free)
                HStack {
                    (Text(formatBytes(used)).bold() + Text(" of \(formatBytes(i.total)) used")).foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(formatBytes(i.free)) free").foregroundStyle(i.free < 2_147_483_648 ? Theme.red : Theme.muted)
                }
                .font(.subheadline)
                if i.free < 2_147_483_648 {
                    WarningBox(text: "This iPhone is almost full. Installing a big app needs about its size free, and signing on this iPhone needs about twice that.", bad: true)
                }
                GeometryReader { g in
                    HStack(spacing: 0) {
                        bar(max(0, used - i.mango), i.total, g.size.width, Theme.muted.opacity(0.45))
                        bar(i.apps, i.total, g.size.width, Theme.mango)
                        bar(i.signed, i.total, g.size.width, Theme.blue)
                        bar(i.certs, i.total, g.size.width, Theme.leaf)
                        bar(i.temp, i.total, g.size.width, Theme.muted)
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 10).background(Theme.bg2).clipShape(Capsule())
                FlowLayout(spacing: 12) {
                    legend("Everything else", max(0, used - i.mango), Theme.muted.opacity(0.45))
                    legend("Apps", i.apps, Theme.mango)
                    legend("Signed copies", i.signed, Theme.blue)
                    legend("Certs", i.certs, Theme.leaf)
                    legend("Temp", i.temp, Theme.muted)
                }
                Hint(text: "Mango Signer uses \(formatBytes(i.mango).isEmpty ? "0 KB" : formatBytes(i.mango)) of it: \(local.apps.count) app\(local.apps.count == 1 ? "" : "s") and \(local.signed.count) signed cop\(local.signed.count == 1 ? "y" : "ies") saved here.")
                HStack(spacing: 8) {
                    WebButton(title: clearing ? "Clearing…" : "Clear temp", disabled: clearing || i.temp < 1) { clear() }
                    WebButton(title: "Saved apps") { router.go(.apps) }
                }
            } else {
                HStack { ProgressView().tint(Theme.mango); Text("Checking this iPhone…").font(.subheadline).foregroundStyle(Theme.muted) }
            }
        }
        .padding(16).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task { await measure() }
        .onChange(of: local.signed.count) { _ in Task { await measure() } }
        .onChange(of: local.apps.count) { _ in Task { await measure() } }
    }

    func measure() async {
        info = await Task.detached(priority: .utility) { DeviceStorageInfo.measure() }.value
    }

    func clear() {
        clearing = true
        Task {
            let freed = await Task.detached(priority: .userInitiated) { DeviceStorageInfo.clearTemp() }.value
            ImageCache.shared.clear()
            await measure()
            clearing = false
            router.say(freed > 0 ? "Freed \(formatBytes(freed))" : "Nothing to clear")
        }
    }

    func bar(_ n: Double, _ total: Double, _ width: CGFloat, _ color: Color) -> some View {
        color.frame(width: n > 0 ? max(width * 0.005, width * CGFloat(n / max(1, total))) : 0)
    }

    func legend(_ t: String, _ n: Double, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(t) \(formatBytes(n).isEmpty ? "0 KB" : formatBytes(n))").font(.caption).foregroundStyle(Theme.muted)
        }
    }
}
