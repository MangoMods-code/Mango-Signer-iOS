import UIKit
import UniformTypeIdentifiers

/// "Mango Signer" in the share sheet for links (Safari, Telegram, Messages…).
/// It hands the link to the app, which downloads the .ipa into the Apps tab.
/// (.ipa files themselves already show "Mango Signer" in the share sheet as an app.)
final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.08, green: 0.05, blue: 0.1, alpha: 1)
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .headline)
        label.text = "🥭 Sending to Mango Signer…"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await handle() }
    }

    private func findLink() async -> String? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for p in item.attachments ?? [] {
                if p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let u = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, !u.isFileURL {
                    return u.absoluteString
                }
                if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let t = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                   let m = t.range(of: #"https?://\S+"#, options: .regularExpression) {
                    return String(t[m])
                }
            }
        }
        return nil
    }

    @MainActor private func handle() async {
        guard let link = await findLink() else {
            label.text = "There's no link to send.\n\nFor an .ipa file, pick \"Mango Signer\" in the row of apps instead."
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        SharedLink.put(link) // picked up when Mango Signer opens, in case it can't be opened from here
        var c = URLComponents()
        c.scheme = "mangosigner"; c.host = "import"; c.queryItems = [URLQueryItem(name: "url", value: link)]
        if let u = c.url, openApp(u) {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            label.text = "✅ Sent!\n\nOpen Mango Signer to download it into your Apps tab."
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Share extensions can't open apps directly, but the app hosting the share sheet can.
    private func openApp(_ url: URL) -> Bool {
        // UIApplication's open(_:options:completionHandler:) is called by name, since extensions can't use it directly.
        let sel = NSSelectorFromString("openURL:options:completionHandler:")
        var r: UIResponder? = self
        while let cur = r {
            if NSStringFromClass(type(of: cur)).contains("Application"), cur.responds(to: sel) {
                typealias OpenFn = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let fn = unsafeBitCast(cur.method(for: sel), to: OpenFn.self)
                fn(cur, sel, url as NSURL, NSDictionary(), nil)
                return true
            }
            r = cur.next
        }
        return false
    }
}
