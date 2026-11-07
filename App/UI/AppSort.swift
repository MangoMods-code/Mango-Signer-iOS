import SwiftUI

// Sorting apps that have no category, like the website: ✨ Auto-sort (runs on the server) and
// Sort by hand (one app at a time, with Mango's best guess on top).

struct AutoSortSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router
    @State private var count = 0
    @State private var progress: Double?
    @State private var lines: [String] = []
    @State private var jobId: String?
    @State private var failure: String?
    @State private var started = false

    var body: some View {
        SheetScroll {
            VStack(spacing: 10) {
                Text("✨").font(.system(size: 52)).padding(.top, 4)
                Text(count > 0 ? "Sorting \(count) app\(count == 1 ? "" : "s")…" : "Starting…").font(.title3.bold()).foregroundStyle(Theme.text)
                if let failure {
                    WarningBox(text: failure, bad: true)
                    WebButton(title: "Close") { router.close() }
                } else {
                    if let progress { ProgressView(value: progress).tint(Theme.mango).padding(.horizontal, 8) } else { ProgressView().tint(Theme.mango) }
                    if !lines.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView {
                                Text(lines.joined(separator: "\n")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                Color.clear.frame(height: 1).id("end")
                            }
                            .frame(maxHeight: 200)
                            .background(Theme.bg).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onChange(of: lines.count) { _ in proxy.scrollTo("end") }
                        }
                    }
                    Hint(text: "Apps the App Store has to look up take a few seconds each. It runs on your server, so you can leave.", center: true)
                    WebButton(title: "Keep going in the background") {
                        router.close(); router.say("Still sorting on the server. Pull to refresh in a bit.")
                    }
                    .disabled(jobId == nil)
                    LinkButton(title: "Stop") {
                        guard let jobId else { return }
                        Task { _ = try? await server.post("/api/jobs/\(jobId)/cancel") }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            guard !started else { return }
            started = true
            do {
                let r = try await server.post("/api/apps/auto-categorize", [:])
                count = (r["count"] as? NSNumber)?.intValue ?? 0
                guard count > 0, let id = r["jobId"] as? String else { router.close(); router.say("Nothing to sort"); return }
                jobId = id
                let result = try await server.waitJob(id) { p, l in
                    progress = p
                    if lines.last != l { lines.append(l); if lines.count > 300 { lines.removeFirst(lines.count - 300) } }
                }
                await server.refresh()
                let n = { (k: String) in (result[k] as? NSNumber)?.intValue ?? 0 }
                let how = [(n("byAppStore"), "App Store"), (n("bySimilar"), "like apps you sorted"), (n("byKeyword"), "by name"), (n("byContent"), "by description"), (n("bySource"), "by source"), (n("byRule"), "your rules"), (n("toOther"), "to Other")]
                    .filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
                let unknown = n("unknown")
                router.say("Sorted \(n("sorted"))\(how.isEmpty ? "" : " (\(how))")\(unknown > 0 ? " · \(unknown) still need you" : "")")
                if unknown > 0 { router.open(.quickSort) } else { router.close() }
            } catch is CancellationError {
                // Closed with "Keep going in the background": the server keeps sorting.
            } catch {
                await server.refresh()
                if error.localizedDescription == "Cancelled" { router.close(); router.say("Stopped. Apps sorted so far keep their category."); return }
                failure = error.localizedDescription
            }
        }
    }
}

struct QuickSortSheet: View {
    @EnvironmentObject var server: Server
    @EnvironmentObject var router: Router

    struct Guess { var categoryId: String?; var newCategory: String?; var why: String }
    @State private var queue: [String] = []
    @State private var guesses: [String: Guess] = [:]
    @State private var i = 0
    @State private var done = 0
    @State private var history: [String] = []
    @State private var loaded = false
    @State private var busy = false
    @State private var newCat = false
    @State private var newCatName = ""
    @State private var newCatEmoji = "📁"
    /// Categories set here, so the screen is right before the library refreshes.
    @State private var placed: [String: String] = [:]
    @State private var gone: Set<String> = []
    @State private var confirmDelete: SApp?

    var cats: [SCategory] { server.state?.categories ?? [] }
    var current: SApp? { i < queue.count && !gone.contains(queue[i]) ? server.app(queue[i]) : nil }

    var body: some View {
        SheetScroll {
            if !loaded {
                ProgressView().tint(Theme.mango).frame(maxWidth: .infinity).padding(.top, 40)
            } else if let a = current {
                appCard(a)
            } else {
                WebEmpty(icon: "checkmark.circle", title: queue.isEmpty ? "Every app has a category 🎉" : "All done",
                         text: queue.isEmpty ? "Nothing left to sort." : "\(done) sorted\(gone.isEmpty ? "" : ", \(gone.count) deleted")\(queue.count - done - gone.count > 0 ? ", \(queue.count - done - gone.count) skipped" : "").")
                if !history.isEmpty { WebButton(title: "↩ Undo the last one") { undo() }.padding(.top, 10) }
                WebButton(title: "Close", kind: .primary) { finish() }.padding(.top, 8)
            }
        }
        .task {
            guard !loaded else { return }
            // Start from what the server has now (so apps you just sorted don't come back).
            await server.refresh()
            queue = (server.state?.apps ?? []).filter { server.category($0.categoryId) == nil }.map { $0.id }
            if !queue.isEmpty, let r = try? await server.post("/api/apps/category-guesses", ["ids": queue]), let g = r["guesses"] as? [String: [String: Any]] {
                for (id, v) in g { guesses[id] = Guess(categoryId: v["categoryId"] as? String, newCategory: v["newCategory"] as? String, why: v["why"] as? String ?? "") }
            }
            loaded = true
        }
        .confirmationDialog("Delete \(confirmDelete?.name ?? "this app") from the library?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let a = confirmDelete { delete(a) } }
        } message: {
            Text("People who installed it keep it.\(confirmDelete?.isSourceApp == true ? " \(confirmDelete?.sourceName ?? "Its source") won't add it back." : "") This can't be undone.")
        }
        // Closed by swiping down: still bring the library up to date with what you sorted.
        .onDisappear { if done > 0 || !gone.isEmpty { Task { await server.refresh() } } }
        .alert("New category", isPresented: $newCat) {
            TextField("Name, e.g. Emulators", text: $newCatName)
            TextField("Emoji", text: $newCatEmoji)
            Button("Add") { if let a = current { makeCategory(newCatName, newCatEmoji, for: a) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    func appCard(_ a: SApp) -> some View {
        let g = guesses[a.id]
        let guessCat = g?.categoryId.flatMap { id in cats.first { $0.id == id } }
        let sub = [a.developer ?? "", a.bundleId ?? "", a.sourceName.map { "\(a.cloud == "telegram" ? "✈️" : "☁") \($0)" } ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        let about = (a.description?.isEmpty == false ? a.description! : a.notes ?? "").replacingOccurrences(of: "\n", with: " ")

        Text("\(i + 1) of \(queue.count) · \(done) sorted\(gone.isEmpty ? "" : " · \(gone.count) deleted")").font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.bottom, 10)
        SheetHead(title: a.name, sub: sub) { AppIconImage(app: a, size: 76) }
        if !about.isEmpty {
            Text(about.count > 160 ? String(about.prefix(160)) + "…" : about).font(.footnote).foregroundStyle(Theme.muted).padding(.bottom, 12)
        }
        if let guessCat {
            guessButton("\(guessCat.emoji ?? "") \(guessCat.name)", why: g?.why ?? "") { put(a, guessCat.id) }
        } else if let nc = g?.newCategory {
            guessButton("+ \(nc) (new)", why: g?.why ?? "") { makeCategory(nc, "📁", for: a) }
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(cats.filter { $0.id != guessCat?.id }) { c in
                gridButton("\(c.emoji ?? "") \(c.name)") { put(a, c.id) }
            }
            gridButton("+ New…") { newCatName = ""; newCatEmoji = "📁"; newCat = true }
        }
        .padding(.top, 10)
        .disabled(busy)
        WebButton(title: "Skip for now") { i += 1; skipGone() }.padding(.top, 12)
        WebButton(title: "🗑 Delete from library", kind: .danger, disabled: busy) { confirmDelete = a }.padding(.top, 8)
        if !history.isEmpty { LinkButton(title: "↩ Undo the last one") { undo() } }
        LinkButton(title: "Open the app's page") { finish(open: a.id) }
        LinkButton(title: "Done") { finish() }
    }

    func guessButton(_ title: String, why: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title).font(.system(size: 18, weight: .bold))
                if !why.isEmpty { Text("Best guess: \(why)").font(.system(size: 12, weight: .medium)).opacity(0.8) }
            }
            .foregroundStyle(Theme.onAccent).frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Theme.gradient).clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(PressStyle()).disabled(busy)
    }

    func gridButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }

    /// Steps past apps that were deleted while sorting.
    func skipGone() { while i < queue.count && (gone.contains(queue[i]) || server.app(queue[i]) == nil) { i += 1 } }

    func delete(_ a: SApp) {
        busy = true
        Task {
            defer { busy = false }
            do {
                _ = try await server.data("DELETE", "/api/apps/\(a.id)")
                gone.insert(a.id)
                history.removeAll { $0 == a.id }
                i += 1; skipGone()
            } catch { router.say(error.localizedDescription) }
        }
    }

    func put(_ a: SApp, _ cid: String) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await server.post("/api/apps/\(a.id)", ["categoryId": cid], method: "PATCH")
                placed[a.id] = cid
                history.append(a.id)
                done += 1; i += 1; skipGone()
            } catch { router.say(error.localizedDescription) }
        }
    }

    func makeCategory(_ name: String, _ emoji: String, for a: SApp) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let r = try await server.post("/api/categories", ["name": n, "emoji": emoji.isEmpty ? "📁" : emoji])
                await server.refresh()
                if let c = r["category"] as? [String: Any], let id = c["id"] as? String { busy = false; put(a, id) }
            } catch { router.say(error.localizedDescription) }
        }
    }

    func undo() {
        guard let aid = history.popLast() else { return }
        Task {
            do {
                try await server.post("/api/apps/\(aid)", ["categoryId": NSNull()], method: "PATCH")
                placed[aid] = nil
                done -= 1
                if let at = queue.firstIndex(of: aid) { i = at }
            } catch { router.say(error.localizedDescription); history.append(aid) }
        }
    }

    func finish(open: String? = nil) {
        Task {
            await server.refresh()
            if let open { router.open(.app(open)) } else { router.close() }
            if done > 0 { router.say("Sorted \(done) app\(done == 1 ? "" : "s")") }
        }
    }
}
