import SwiftUI
import UIKit

enum AppTab: String, Hashable { case library, signed, certs, users, settings }

/// Everything needed to run one signing (on the server or on this iPhone).
final class SignRun: Identifiable {
    let id = UUID()
    let app: SApp
    var body: [String: Any]
    var icon: URL?
    var dylibs: [URL]
    /// Set when signing on this iPhone instead of on the server.
    var local: LocalPlan?

    struct LocalPlan {
        var certId: UUID
        var options: SignOptions
    }

    init(app: SApp, body: [String: Any], icon: URL? = nil, dylibs: [URL] = [], local: LocalPlan? = nil) {
        self.app = app; self.body = body; self.icon = icon; self.dylibs = dylibs; self.local = local
    }
}

/// Which sheet is showing. Like the website, one sheet at a time: opening another swaps its content in place.
enum Route: Identifiable, Equatable {
    case app(String)
    case sign(String, presetId: String?)
    case signing(SignRun)
    case ready(String, jit: Bool)
    case readyLocal(UUID)
    case install(String)
    case signed(String)
    case filters
    case myApps
    case requestApp
    case request(String)
    case alerts
    case activity
    case whatsNew
    case addCert
    case newInvite
    case invite(String)
    case user(String)
    case changePassword
    case mySecurity
    case securityLog
    case qr(title: String, url: String)
    case localApps
    case localCerts
    case addLocalCert
    case deviceApps
    case reportBug(String?)
    case bug(String)
    case editApp(String)
    case appShots(String)
    case appCollections(String)
    case appFile(String, newVersion: Bool)
    case moveToGithub(String)
    case autoSort
    case quickSort

    var id: String {
        switch self {
        case .app(let a): return "app-\(a)"
        case .sign(let a, let p): return "sign-\(a)-\(p ?? "")"
        case .signing(let r): return "signing-\(r.id)"
        case .ready(let s, _): return "ready-\(s)"
        case .readyLocal(let u): return "readyLocal-\(u)"
        case .install(let s): return "install-\(s)"
        case .signed(let s): return "signed-\(s)"
        case .filters: return "filters"
        case .myApps: return "myApps"
        case .requestApp: return "requestApp"
        case .request(let r): return "request-\(r)"
        case .alerts: return "alerts"
        case .activity: return "activity"
        case .whatsNew: return "whatsNew"
        case .addCert: return "addCert"
        case .newInvite: return "newInvite"
        case .invite(let c): return "invite-\(c)"
        case .user(let u): return "user-\(u)"
        case .changePassword: return "changePassword"
        case .mySecurity: return "mySecurity"
        case .securityLog: return "securityLog"
        case .qr(let t, let u): return "qr-\(t)-\(u)"
        case .localApps: return "localApps"
        case .localCerts: return "localCerts"
        case .addLocalCert: return "addLocalCert"
        case .deviceApps: return "deviceApps"
        case .reportBug(let a): return "reportBug-\(a ?? "")"
        case .bug(let b): return "bug-\(b)"
        case .editApp(let a): return "editApp-\(a)"
        case .appShots(let a): return "appShots-\(a)"
        case .appCollections(let a): return "appCollections-\(a)"
        case .appFile(let a, let v): return "appFile-\(a)-\(v)"
        case .moveToGithub(let a): return "moveToGithub-\(a)"
        case .autoSort: return "autoSort"
        case .quickSort: return "quickSort"
        }
    }
    static func == (a: Route, b: Route) -> Bool { a.id == b.id }
}

@MainActor
final class Router: ObservableObject {
    @Published var tab: AppTab = .library
    @Published var route: Route?
    @Published var toast: String?
    /// While signing, the sheet can't be swiped away (like the website).
    @Published var locked = false
    /// Signed apps just made, so their sheets work before the next refresh.
    var signedCache: [String: SSigned] = [:]

    // Library filters (kept between launches, like the website).
    @Published var libCat = UserDefaults.standard.string(forKey: "lib.cat") ?? "all" { didSet { UserDefaults.standard.set(libCat, forKey: "lib.cat") } }
    @Published var libSort = UserDefaults.standard.string(forKey: "lib.sort") ?? "smart" { didSet { UserDefaults.standard.set(libSort, forKey: "lib.sort") } }
    @Published var libGrid = UserDefaults.standard.bool(forKey: "lib.grid") { didSet { UserDefaults.standard.set(libGrid, forKey: "lib.grid") } }
    @Published var libQuery = ""
    @Published var libLimit = 40

    func open(_ r: Route) { route = r }
    func close() { locked = false; route = nil }
    func say(_ message: String) { toast = message }
    func go(_ tab: AppTab) { close(); self.tab = tab }

    func signed(_ id: String, _ server: Server) -> SSigned? {
        server.state?.signed?.first { $0.id == id } ?? signedCache[id]
    }

    /// "Get": installs a matching signed copy right away, or signs with the app's default settings.
    func quickGet(_ app: SApp, server: Server, versionIndex: Int = 0) {
        guard !server.certs.isEmpty else {
            go(.certs)
            say("Add your certificate first")
            return
        }
        if versionIndex == 0, let ready = server.reusableSigned(app) {
            startInstall(ready, server: server)
            return
        }
        open(.signing(SignRun(app: app, body: server.signBodyFromDefaults(app, versionIndex: versionIndex))))
    }

    /// Starts the iPhone's install pop-up right away, then shows live progress.
    func startInstall(_ s: SSigned, server: Server) {
        signedCache[s.id] = s
        if !server.https { say("Install needs HTTPS — open your server from its Railway link") }
        if let iu = s.installUrl, let u = URL(string: iu) { UIApplication.shared.open(u) }
        Task { _ = try? await server.post("/api/signed/\(s.id)/install") }
        open(.install(s.id))
    }
}

/// The scrolling body every sheet uses.
struct SheetScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 18).padding(.top, 26).padding(.bottom, 34)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.card.ignoresSafeArea())
    }
}

/// Shows whichever sheet the router says, swapping content in place.
struct SheetHost: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var server: Server

    var body: some View {
        Group {
            switch router.route {
            case .app(let id): AppSheet(appId: id)
            case .sign(let id, let preset): SignSheet(appId: id, presetId: preset)
            case .signing(let run): SigningSheet(run: run)
            case .ready(let id, let jit): ReadySheet(signedId: id, jit: jit)
            case .readyLocal(let id): ReadyLocalSheet(signedId: id)
            case .install(let id): InstallSheet(signedId: id)
            case .signed(let id): SignedSheet(signedId: id)
            case .filters: FilterSheet()
            case .myApps: MyAppsSheet()
            case .requestApp: RequestAppSheet()
            case .request(let id): RequestSheet(requestId: id)
            case .alerts: AlertsSheet()
            case .activity: ActivitySheet()
            case .whatsNew: WhatsNewSheet()
            case .addCert: AddServerCertSheet()
            case .newInvite: NewInviteSheet()
            case .invite(let code): InviteSheet(code: code, signupUrl: nil)
            case .user(let id): UserSheet(userId: id)
            case .changePassword: ChangePasswordSheet()
            case .mySecurity: MySecuritySheet()
            case .securityLog: SecurityLogSheet()
            case .qr(let title, let url): QRSheet(title: title, url: url)
            case .localApps: NavigationStack { LocalAppsScreen() }
            case .localCerts: NavigationStack { LocalCertsScreen() }
            case .addLocalCert: AddCertSheet(target: .phone)
            case .deviceApps: DeviceAppsSheet()
            case .reportBug(let a): ReportBugSheet(appId: a)
            case .bug(let id): BugSheet(bugId: id)
            case .editApp(let id): EditAppSheet(appId: id)
            case .appShots(let id): AppShotsSheet(appId: id)
            case .appCollections(let id): AppCollectionsSheet(appId: id)
            case .appFile(let id, let v): AppFileSheet(appId: id, newVersion: v)
            case .moveToGithub(let id): MoveToGithubSheet(appId: id)
            case .autoSort: AutoSortSheet()
            case .quickSort: QuickSortSheet()
            case nil: Theme.card.ignoresSafeArea()
            }
        }
        .id(router.route?.id ?? "none")
        .toast($router.toast)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(router.locked)
        .tint(Theme.mango)
        .preferredColorScheme(.dark)
    }
}
