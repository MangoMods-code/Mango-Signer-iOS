import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// The owner's and admins' tools for one library app — the same screens the website has:
// Edit app, Screenshots, Add to collection, Update IPA, Add a newer version and Move to GitHub.

/// Upload / server progress, like the website's progress box.
struct BusyCard: View {
    let progress: Double?
    let line: String
    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.large).tint(Theme.mango)
            if let progress { ProgressView(value: min(1, max(0, progress))).tint(Theme.mango) }
            Text(line).font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Text("Keep this screen open").font(.caption).foregroundStyle(Theme.muted.opacity(0.8))
        }
        .frame(maxWidth: .infinity).padding(16)
        .background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 14)
    }
}

/// A dashed "pick a file" button, like the website's .file-btn.
struct FilePickButtonLabel: View {
    let icon: String
    let title: String
    let sub: String
    var chosen = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: chosen ? "checkmark.circle.fill" : icon).font(.title3).foregroundStyle(chosen ? Theme.leaf : Theme.mango).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                Text(sub).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(chosen ? Theme.leaf.opacity(0.5) : Theme.line, style: StrokeStyle(lineWidth: 1, dash: chosen ? [] : [5, 4])))
    }
}

/// Custom entitlement / Info.plist rows (key, type, value).
struct KeyRowsEditor: View {
    @Binding var rows: [EditRow]
    let kind: String
    var body: some View {
        ForEach($rows) { $row in
            VStack(spacing: 8) {
                TextField(kind == "plist" ? "Info.plist key, e.g. UIFileSharingEnabled" : "Entitlement, e.g. com.apple.developer.…", text: $row.key)
                    .plainInput().inputStyle()
                HStack(spacing: 8) {
                    Menu {
                        ForEach(kind == "plist" ? [("bool", "Yes / No"), ("string", "Text"), ("number", "Number"), ("delete", "Remove key")] : [("bool", "Yes / No"), ("string", "Text")], id: \.0) { k, l in
                            Button(l) { row.type = k }
                        }
                    } label: {
                        Text(["bool": "Yes / No", "string": "Text", "number": "Number", "delete": "Remove key"][row.type] ?? row.type)
                            .foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading).inputStyle()
                    }
                    Group {
                        switch row.type {
                        case "bool":
                            Menu {
                                Button("YES") { row.boolValue = true }
                                Button("NO") { row.boolValue = false }
                            } label: { Text(row.boolValue ? "YES" : "NO").foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading).inputStyle() }
                        case "delete":
                            Text("Key will be removed").font(.caption).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                        default:
                            TextField("Value", text: $row.textValue).plainInput().keyboardType(row.type == "number" ? .decimalPad : .default).inputStyle()
                        }
                    }
                    Button { let id = row.id; rows.removeAll { $0.id == id } } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(Theme.muted).frame(width: 40, height: 44)
                    }
                }
            }
            .padding(10).background(Theme.bg2.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 8)
        }
    }
}

struct AddRowButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mango)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .padding(.top, 8)
    }
}

/// Picture from Photos as PNG (icons) or JPEG/PNG (screenshots).
private func pickedImage(_ item: PhotosPickerItem, png: Bool) async -> Data? {
    guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
    let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
    let isJPEG = data.starts(with: [0xFF, 0xD8, 0xFF])
    if png { return isPNG ? data : UIImage(data: data)?.pngData() }
    if isPNG || isJPEG { return data }
    return UIImage(data: data)?.jpegData(compressionQuality: 0.9) // HEIC and others
}

// MARK: - Edit app

struct EditAppSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let appId: String

    @State private var loaded = false
    @State private var name = ""
    @State private var categoryId = ""
    @State private var tags = ""
    @State private var version = ""
    @State private var versionWhenSigning = true
    @State private var developer = ""
    @State private var about = ""
    @State private var notes = ""
    @State private var published = true
    @State private var featured = false
    @State private var testersOnly = false
    @State private var iconItem: PhotosPickerItem?
    @State private var iconPNG: Data?
    @State private var resetIcon = false
    @State private var iconWhenSigning = true
    @State private var minOS = ""
    @State private var ent: [String: Bool] = [:]
    @State private var plist: [String: Bool] = [:]
    @State private var customEnt: [EditRow] = []
    @State private var customPlist: [EditRow] = []
    @State private var removeExtensions = false
    @State private var removeWatch = false
    @State private var removeUISD = false
    @State private var enableDocs = false
    @State private var weak = false
    @State private var injectExt = false
    @State private var tweakIds: Set<String> = []
    @State private var saving = false
    @State private var newCat = false
    @State private var newCatName = ""
    @State private var newCatEmoji = "📁"

    var app: SApp? { server.app(appId) }

    var body: some View {
        if let a = app {
            SheetScroll { form(a) }
                .onAppear { if !loaded { load(a); loaded = true } }
                .onChange(of: iconItem) { item in
                    guard let item else { return }
                    Task {
                        if let d = await pickedImage(item, png: true) { iconPNG = d; resetIcon = false } else { router.say("Couldn't open that picture") }
                    }
                }
                .alert("New category", isPresented: $newCat) {
                    TextField("Name, e.g. Emulators", text: $newCatName)
                    TextField("Emoji", text: $newCatEmoji)
                    Button("Add") { addCategory() }
                    Button("Cancel", role: .cancel) {}
                }
        } else {
            SheetScroll { WebEmpty(icon: "questionmark.app", title: "Not in the library", text: "That app is no longer in the library.") }
        }
    }

    func load(_ a: SApp) {
        name = a.name
        categoryId = a.categoryId ?? ""
        tags = (a.tags ?? []).joined(separator: ", ")
        version = a.versionOverride ?? ""
        versionWhenSigning = a.useVersionWhenSigning != false
        developer = a.developer ?? ""
        about = a.description ?? ""
        notes = a.notes ?? ""
        published = a.published != false
        featured = a.featured == true
        testersOnly = a.testersOnly
        iconWhenSigning = a.useIconWhenSigning != false
        let d = a.signDefaults ?? SignDefaults()
        minOS = d.minOS
        for p in SignPresets.ent { ent[p.key] = d.entitlements.contains { $0.key == p.key } }
        for p in SignPresets.plist { plist[p.key] = d.plist.contains { $0.key == p.key } }
        customEnt = d.entitlements.filter { e in !SignPresets.ent.contains { $0.key == e.key } }
        customPlist = d.plist.filter { e in !SignPresets.plist.contains { $0.key == e.key } }
        removeExtensions = d.removeExtensions
        removeWatch = d.removeWatch ?? (a.hasWatch ?? false)
        removeUISD = d.removeUISD
        enableDocs = d.enableDocs
        weak = d.weakDylibs
        injectExt = d.injectExtensions
        tweakIds = Set(d.tweakIds)
    }

    var tagList: [String] { tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    var tagSuggestions: [String] {
        var seen = Set<String>(), out: [String] = []
        for t in ["Needs JIT", "Controller support", "iPad friendly", "Tweaked", "No ads"] + (server.state?.apps ?? []).flatMap({ $0.tags ?? [] }) where !seen.contains(t) {
            seen.insert(t); out.append(t)
            if out.count >= 24 { break }
        }
        return out
    }

    @ViewBuilder
    func form(_ a: SApp) -> some View {
        SheetHead(title: "Edit app", sub: "\(a.name) · \(a.shownVersion.isEmpty ? "—" : a.shownVersion)") {
            if let iconPNG, let img = UIImage(data: iconPNG) {
                Image(uiImage: img).resizable().scaledToFill().frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            } else { AppIconImage(app: a, size: 76) }
        }

        Field(label: "Name in the library") { TextField(a.name, text: $name).inputStyle() }
        Field(label: "Category") {
            SelectBox(selection: Binding(get: { categoryId }, set: { v in if v == "__new" { newCatName = ""; newCatEmoji = "📁"; newCat = true } else { categoryId = v } }),
                      options: [("", "Uncategorized")] + (server.state?.categories ?? []).map { ($0.id, [$0.emoji ?? "", $0.name].filter { !$0.isEmpty }.joined(separator: " ")) } + [("__new", "+ New category…")])
        }
        Field(label: "Tags", hint: "Separate with commas. Tags show on the app's page and as filters in the library.") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("e.g. Needs JIT, Controller support", text: $tags).textInputAutocapitalization(.words).inputStyle()
                FlowLayout(spacing: 6) {
                    ForEach(tagSuggestions.filter { !tagList.contains($0) }, id: \.self) { t in
                        Button { tags = (tagList + [t]).joined(separator: ", ") } label: {
                            Text("+ \(t)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.soft)
                                .padding(.horizontal, 9).padding(.vertical, 5).background(Theme.bg2).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        Field(label: "Version", hint: "Leave blank to use the version from the .ipa (\(a.version?.isEmpty == false ? a.version! : "none")). Cleared automatically when you Update IPA.") {
            TextField(a.version?.isEmpty == false ? a.version! : "1.0", text: $version).plainInput().inputStyle()
        }
        ListBox(fill: Theme.bg2) {
            ToggleRow(title: "Use this version when signing", sub: "Installed apps show it in Settings › General › iPhone Storage. Only numbers, letters, dots and dashes are used.", isOn: $versionWhenSigning)
        }
        .padding(.bottom, 12)
        Field(label: "Developer / source") { TextField("e.g. Nintendo, or where you got it", text: $developer).inputStyle() }
        Field(label: "Description") { TextField("What it is, in a sentence or two", text: $about, axis: .vertical).lineLimit(3...10).inputStyle() }
        Field(label: "Notes / what's tweaked") { TextField("e.g. Ad-free, works with controllers, turn on JIT in StikDebug first", text: $notes, axis: .vertical).lineLimit(3...10).inputStyle() }

        ListBox(fill: Theme.bg2) {
            ToggleRow(title: "Show in App Library", sub: "Visible to everyone you invite", isOn: $published)
            RowLine()
            ToggleRow(title: "Featured", sub: "Pinned to the top of the library", isOn: $featured)
            RowLine()
            ToggleRow(title: "Testers only", sub: "Only testers (and admins) can see it", isOn: $testersOnly)
        }

        SectionTitle(text: "Icon")
        PhotosPicker(selection: $iconItem, matching: .images) {
            FilePickButtonLabel(icon: "photo", title: iconPNG != nil ? "New icon chosen" : a.customIcon == true && !resetIcon ? "Custom icon set" : "Change icon",
                                sub: iconPNG != nil ? "Saved when you tap Save" : a.customIcon == true && !resetIcon ? "Tap to pick a different one" : resetIcon ? "Will use the app's own icon" : "Square picture works best",
                                chosen: iconPNG != nil || (a.customIcon == true && !resetIcon))
        }
        .buttonStyle(.plain)
        if a.customIcon == true || iconPNG != nil {
            LinkButton(title: "Go back to the app's own icon") { resetIcon = true; iconPNG = nil; iconItem = nil }
        }
        ListBox(fill: Theme.bg2) {
            ToggleRow(title: "Use this icon when signing", sub: "The installed app shows your custom icon", isOn: $iconWhenSigning)
        }
        .padding(.top, 6)

        SectionTitle(text: "Default sign settings")
        Hint(text: "These are switched on automatically when anyone signs this app, so they can just tap Get.").padding(.bottom, 10)
        Field(label: "Minimum iOS (optional)") { TextField(a.minOS?.isEmpty == false ? a.minOS! : "unchanged", text: $minOS).keyboardType(.decimalPad).inputStyle() }

        SectionTitle(text: "Entitlements")
        ListBox(fill: Theme.bg2) {
            ForEach(Array(SignPresets.ent.enumerated()), id: \.offset) { i, p in
                if i > 0 { RowLine() }
                ToggleRow(title: p.label, sub: p.sub, isOn: Binding(get: { ent[p.key] ?? false }, set: { ent[p.key] = $0 }))
            }
        }
        KeyRowsEditor(rows: $customEnt, kind: "ent")
        AddRowButton(title: "+ Add custom entitlement") { customEnt.append(EditRow()) }

        SectionTitle(text: "Info.plist")
        ListBox(fill: Theme.bg2) {
            ForEach(Array(SignPresets.plist.enumerated()), id: \.offset) { i, p in
                if i > 0 { RowLine() }
                ToggleRow(title: p.label, sub: p.sub, isOn: Binding(get: { plist[p.key] ?? false }, set: { plist[p.key] = $0 }))
            }
        }
        KeyRowsEditor(rows: $customPlist, kind: "plist")
        AddRowButton(title: "+ Add Info.plist key") { customPlist.append(EditRow()) }

        SectionTitle(text: "Options")
        ListBox(fill: Theme.bg2) {
            ToggleRow(title: "Remove extensions", sub: "Fixes installs on profiles without matching App IDs", isOn: $removeExtensions)
            RowLine()
            ToggleRow(title: "Remove Watch app", sub: "Smaller install, avoids Watch signing errors", isOn: $removeWatch)
            RowLine()
            ToggleRow(title: "Remove device limits", sub: "Lets apps install on devices they weren't built for", isOn: $removeUISD)
            RowLine()
            ToggleRow(title: "Show in Files app", sub: "Turns on file sharing and document browser", isOn: $enableDocs)
            RowLine()
            ToggleRow(title: "Weak injection", sub: "App still opens if a tweak fails to load", isOn: $weak)
            RowLine()
            ToggleRow(title: "Inject into extensions", sub: "Also load tweaks in widgets and share extensions", isOn: $injectExt)
        }

        let tweaks = server.state?.tweaks ?? []
        if !tweaks.isEmpty {
            SectionTitle(text: "Default tweaks")
            ListBox(fill: Theme.bg2) {
                ForEach(Array(tweaks.enumerated()), id: \.element.id) { i, t in
                    if i > 0 { RowLine() }
                    ToggleRow(title: "🧩 \(t.name)\(t.version.map { " " + $0 } ?? "")",
                              sub: t.description.flatMap { $0.split(separator: "\n").first.map { String($0.prefix(90)) } } ?? "",
                              isOn: Binding(get: { tweakIds.contains(t.id) }, set: { if $0 { tweakIds.insert(t.id) } else { tweakIds.remove(t.id) } }))
                }
            }
        }

        WebButton(title: saving ? "Saving…" : "Save", kind: .primary, big: true, disabled: saving) { save(a) }.padding(.top, 18)
        LinkButton(title: "Back to \(a.name)") { router.open(.app(a.id)) }
    }

    func addCategory() {
        let n = newCatName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        Task {
            do {
                let r = try await server.post("/api/categories", ["name": n, "emoji": newCatEmoji.isEmpty ? "📁" : newCatEmoji])
                await server.refresh()
                if let c = r["category"] as? [String: Any], let id = c["id"] as? String { categoryId = id }
                router.say("Added \(newCatEmoji) \(n)")
            } catch { router.say(error.localizedDescription) }
        }
    }

    func save(_ a: SApp) {
        saving = true
        Task {
            defer { saving = false }
            do {
                let entRows = SignPresets.ent.filter { ent[$0.key] == true }.map { EditRow(key: $0.key) } + customEnt.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
                let plistRows = SignPresets.plist.filter { plist[$0.key] == true }.map { EditRow(key: $0.key) } + customPlist.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
                var body: [String: Any] = [
                    "name": name, "categoryId": categoryId.isEmpty ? NSNull() : categoryId, "developer": developer, "tags": tagList,
                    "versionOverride": version.trimmingCharacters(in: .whitespaces), "useVersionWhenSigning": versionWhenSigning,
                    "description": about, "notes": notes, "published": published, "featured": featured, "testersOnly": testersOnly,
                    "useIconWhenSigning": iconWhenSigning,
                    "signDefaults": [
                        "minOS": minOS.trimmingCharacters(in: .whitespaces), "entitlements": entRows.map { $0.json }, "plist": plistRows.map { $0.json },
                        "removeExtensions": removeExtensions, "removeWatch": removeWatch, "removeUISD": removeUISD, "enableDocs": enableDocs,
                        "weakDylibs": weak, "injectExtensions": injectExt, "tweakIds": Array(tweakIds),
                    ] as [String: Any],
                ]
                if let iconPNG { body["iconUploadId"] = try await server.uploadData(iconPNG) }
                if resetIcon { body["resetIcon"] = true }
                try await server.post("/api/apps/\(a.id)", body, method: "PATCH")
                await server.refresh()
                router.say("Saved")
                router.open(.app(a.id))
            } catch { router.say(error.localizedDescription) }
        }
    }
}

// MARK: - Screenshots

struct AppShotsSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let appId: String
    @State private var items: [PhotosPickerItem] = []
    @State private var status: String?

    var body: some View {
        if let a = server.app(appId) {
            let shots = a.screenshots ?? []
            SheetScroll {
                SheetTitle(text: "Screenshots")
                Hint(text: "Up to 8. They show on the app's page — tap one there to view it full screen.").padding(.bottom, 12)
                if shots.isEmpty, !(a.remoteScreens ?? []).isEmpty {
                    Hint(text: "Showing \(a.remoteScreens!.count) from the App Store or the source right now. Adding your own replaces them.").padding(.bottom, 10)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
                    ForEach(Array(shots.enumerated()), id: \.element.id) { i, sh in
                        VStack(spacing: 6) {
                            if let u = server.url("/api/apps/\(a.id)/screenshots/\(sh.id)") { RemoteShot(url: u).frame(height: 220) }
                            HStack(spacing: 6) {
                                PillButton(title: "←") { move(a, shots, i, i - 1) }.disabled(i == 0).opacity(i == 0 ? 0.4 : 1)
                                PillButton(title: "✕", danger: true) { remove(a, sh.id) }
                                PillButton(title: "→") { move(a, shots, i, i + 1) }.disabled(i == shots.count - 1).opacity(i == shots.count - 1 ? 0.4 : 1)
                            }
                        }
                    }
                }
                if shots.count < 8 {
                    PhotosPicker(selection: $items, maxSelectionCount: 8 - shots.count, matching: .images) {
                        FilePickButtonLabel(icon: "plus", title: "Add screenshots", sub: "PNG, JPEG or photos · pick several at once")
                    }
                    .buttonStyle(.plain).padding(.top, 12).disabled(status != nil)
                }
                if let status { BusyCard(progress: nil, line: status) }
                WebButton(title: "Back to \(a.name)") { router.open(.app(a.id)) }.padding(.top, 14)
            }
            .onChange(of: items) { picked in add(a, picked) }
        } else {
            SheetScroll { WebEmpty(icon: "questionmark.app", title: "Not in the library", text: "That app is no longer in the library.") }
        }
    }

    func add(_ a: SApp, _ picked: [PhotosPickerItem]) {
        guard !picked.isEmpty else { return }
        items = []
        Task {
            defer { status = nil }
            do {
                for (i, item) in picked.enumerated() {
                    status = "Uploading \(i + 1) of \(picked.count)…"
                    guard let d = await pickedImage(item, png: false) else { router.say("Couldn't open one of those pictures"); continue }
                    let up = try await server.uploadData(d)
                    try await server.post("/api/apps/\(a.id)/screenshots", ["uploadId": up])
                }
                await server.refresh()
                router.say("Screenshots added")
            } catch { await server.refresh(); router.say(error.localizedDescription) }
        }
    }

    func move(_ a: SApp, _ shots: [SShot], _ from: Int, _ to: Int) {
        guard to >= 0, to < shots.count else { return }
        var ids = shots.map { $0.id }
        ids.insert(ids.remove(at: from), at: to)
        Task {
            do { try await server.post("/api/apps/\(a.id)/screenshots/order", ["ids": ids]); await server.refresh() } catch { router.say(error.localizedDescription) }
        }
    }

    func remove(_ a: SApp, _ id: String) {
        Task {
            do { _ = try await server.data("DELETE", "/api/apps/\(a.id)/screenshots/\(id)"); await server.refresh() } catch { router.say(error.localizedDescription) }
        }
    }
}

// MARK: - Add to collection

struct AppCollectionsSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let appId: String
    @State private var making = false
    @State private var newName = ""
    @State private var newEmoji = "📦"

    var body: some View {
        if let a = server.app(appId) {
            let cols = server.state?.collections ?? []
            SheetScroll {
                SheetTitle(text: "Add \(a.name) to…")
                ListBox(fill: Theme.bg2) {
                    if cols.isEmpty {
                        Text("No collections yet").foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    }
                    ForEach(Array(cols.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { RowLine() }
                        Button { toggle(a, c) } label: {
                            HStack(spacing: 12) {
                                Text(c.emoji ?? "📦").font(.title3)
                                Text(c.name).foregroundStyle(Theme.text)
                                Spacer()
                                if c.appIds.contains(a.id) { Image(systemName: "checkmark").font(.headline).foregroundStyle(Theme.mango) }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 13).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                WebButton(title: "+ New collection") { newName = ""; newEmoji = "📦"; making = true }.padding(.top, 12)
                WebButton(title: "Back") { router.open(.app(a.id)) }.padding(.top, 8)
            }
            .alert("New collection", isPresented: $making) {
                TextField("Name, e.g. Best emulators", text: $newName)
                TextField("Emoji", text: $newEmoji)
                Button("Make it") { create(a) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("\(a.name) goes in it right away.") }
        } else {
            SheetScroll { WebEmpty(icon: "questionmark.app", title: "Not in the library", text: "That app is no longer in the library.") }
        }
    }

    func toggle(_ a: SApp, _ c: SCollection) {
        let ids = c.appIds.contains(a.id) ? c.appIds.filter { $0 != a.id } : c.appIds + [a.id]
        Task {
            do {
                try await server.post("/api/collections/\(c.id)", ["appIds": ids], method: "PATCH")
                await server.refresh()
                router.say(ids.contains(a.id) ? "Added to \(c.name)" : "Removed from \(c.name)")
            } catch { router.say(error.localizedDescription) }
        }
    }

    func create(_ a: SApp) {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        Task {
            do {
                try await server.post("/api/collections", ["name": n, "emoji": newEmoji.isEmpty ? "📦" : newEmoji, "appIds": [a.id]])
                await server.refresh()
                router.say("Made \(n)")
            } catch { router.say(error.localizedDescription) }
        }
    }
}

// MARK: - Update IPA / Add a newer version

/// "Update IPA" for apps you added yourself, and "Add a newer version" for apps from a source.
struct AppFileSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let appId: String
    /// true: add a newer version to a source app. false: swap in a new .ipa.
    let newVersion: Bool

    @State private var picking = false
    @State private var link = ""
    @State private var linkOnly = true
    @State private var notes = ""
    @State private var busy = false
    @State private var progress: Double?
    @State private var line = ""
    @State private var loaded = false

    var gh: Bool { server.state?.github?.connected == true }
    var ghStoring: Bool { gh && server.state?.github?.storeUploads == true }

    var body: some View {
        if let a = server.app(appId) {
            SheetScroll {
                SheetHead(title: newVersion ? "Add a newer version" : "Update \(a.name)", sub: newVersion ? "\(a.name) · now \(a.shownVersion.isEmpty ? "—" : a.shownVersion)" : "Now \(a.shownVersion.isEmpty ? "—" : a.shownVersion)") {
                    AppIconImage(app: a, size: 76)
                }
                Hint(text: newVersion
                     ? "It becomes the newest version for everyone, like \(a.sourceName ?? "the source") had posted it. The source's versions stay under \"Other versions\". If the source posts this version later, its copy takes over and yours is removed."
                     : "Swap in a new .ipa. The name, category, description, notes, icon and default sign settings all stay the same.")
                    .padding(.bottom, 12)

                Button { picking = true } label: {
                    FilePickButtonLabel(icon: "doc", title: newVersion ? "Choose .ipa" : "Choose new .ipa",
                                        sub: newVersion ? (gh ? "Saved to your GitHub storage, not this server" : "Connect GitHub storage first (Settings › Cloud Library on the website)")
                                                        : (ghStoring ? "Saved to your GitHub repo" : "Resumes if your connection drops"))
                }
                .buttonStyle(.plain).disabled(busy || (newVersion && !gh)).opacity(newVersion && !gh ? 0.5 : 1)

                SectionTitle(text: "Or from a link")
                TextField("https://example.com/app.ipa", text: $link).plainInput().keyboardType(.URL).inputStyle().padding(.bottom, 12)
                ListBox(fill: Theme.bg2) {
                    ToggleRow(title: "Link only (uses no storage)",
                              sub: newVersion ? "Keeps just the link. Turn off to copy the file to your GitHub storage." : "Keeps just the link instead of downloading the file to the server",
                              isOn: $linkOnly)
                }
                if newVersion {
                    Field(label: "What's new (optional)") { TextField("What changed in this version", text: $notes, axis: .vertical).lineLimit(3...8).inputStyle() }
                        .padding(.top, 12)
                }
                WebButton(title: newVersion ? "Add from link" : "Update from link", kind: newVersion ? .primary : .normal,
                          disabled: busy || link.trimmingCharacters(in: .whitespaces).isEmpty) { fromLink(a) }
                    .padding(.top, 10)

                if busy { BusyCard(progress: progress, line: line) }
                LinkButton(title: "Back to \(a.name)") { router.open(.app(a.id)) }.disabled(busy)
            }
            .onAppear {
                if !loaded { loaded = true; linkOnly = newVersion ? true : (a.cloud == "link" || a.cloud == nil) }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [FileTypes.ipa, .data]) { r in
                guard case .success(let u) = r else { return }
                guard u.pathExtension.lowercased() == "ipa" else { router.say("Pick an .ipa file"); return }
                fromFile(a, u)
            }
        } else {
            SheetScroll { WebEmpty(icon: "questionmark.app", title: "Not in the library", text: "That app is no longer in the library.") }
        }
    }

    func run(_ a: SApp, _ work: @escaping () async throws -> [String: Any]) {
        busy = true; router.locked = true; progress = 0; line = "Starting…"
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            defer { busy = false; router.locked = false; UIApplication.shared.isIdleTimerDisabled = false }
            do {
                var r = try await work()
                if let job = r["jobId"] as? String {
                    r = try await server.waitJob(job) { p, l in progress = p; line = l }
                }
                await server.refresh()
                let v = ((r["app"] as? [String: Any])?["version"] as? String) ?? server.app(a.id)?.shownVersion ?? ""
                router.say(newVersion ? "\(a.name) is now \(v.isEmpty ? "updated" : v)" : "Updated to \(v.isEmpty ? "the new version" : v)")
                router.open(.app(a.id))
            } catch { router.say(error.localizedDescription) }
        }
    }

    func fromFile(_ a: SApp, _ u: URL) {
        run(a) {
            let up = try await server.uploadLarge(u) { p, l in progress = p; line = l }
            progress = nil; line = "Reading app info…"
            if newVersion { return try await server.post("/api/apps/\(a.id)/versions", ["uploadId": up, "notes": notes]) }
            return try await server.post("/api/apps/\(a.id)/replace", ["uploadId": up])
        }
    }

    func fromLink(_ a: SApp) {
        let url = link.trimmingCharacters(in: .whitespaces)
        if newVersion && !linkOnly && !gh { router.say("Connect GitHub storage first, or keep Link only on"); return }
        run(a) {
            if newVersion { return try await server.post("/api/apps/\(a.id)/versions", ["url": url, "linkOnly": linkOnly, "notes": notes]) }
            return try await server.post("/api/apps/\(a.id)/replace", ["url": url, "linkOnly": linkOnly])
        }
    }
}

// MARK: - Move to GitHub

struct MoveToGithubSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    let appId: String
    @State private var progress: Double?
    @State private var line = "Starting…"
    @State private var failure: String?
    @State private var started = false

    var body: some View {
        SheetScroll {
            if let a = server.app(appId) {
                SheetHead(title: "Moving to GitHub", sub: a.name) { AppIconImage(app: a, size: 76) }
                if let failure {
                    WarningBox(text: failure, bad: true)
                    WebButton(title: "Back to \(a.name)") { router.open(.app(a.id)) }.padding(.top, 12)
                } else {
                    BusyCard(progress: progress, line: line)
                }
            }
        }
        .task {
            guard !started else { return }
            started = true
            router.locked = true
            defer { router.locked = false }
            do {
                let r = try await server.post("/api/github/move", ["ids": [appId]])
                guard let job = r["jobId"] as? String else { throw MangoError("The server didn't start the move. Try again.") }
                _ = try await server.waitJob(job) { p, l in progress = p; line = l }
                await server.refresh()
                router.say("Moved to GitHub ☁")
                router.open(.app(appId))
            } catch { failure = error.localizedDescription }
        }
    }
}
