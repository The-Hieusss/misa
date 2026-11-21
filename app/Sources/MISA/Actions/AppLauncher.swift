import AppKit

/// "Open Claude", "launch Safari and Notes", "quit Spotify": finds apps by name and opens or quits them.
enum AppLauncher {
    struct App { let name: String; let url: URL; let key: String; let words: [String] }

    /// Words that can start a request to open an app.
    static let verbs = ["open", "launch", "start", "run", "switch to", "bring up", "pull up", "fire up", "go to"]

    /// Common nicknames → the app's real name.
    private static let aliases: [String: String] = [
        "vscode": "visual studio code", "vs code": "visual studio code", "code": "visual studio code",
        "settings": "system settings", "preferences": "system settings", "system preferences": "system settings",
        "chrome": "google chrome", "word": "microsoft word", "excel": "microsoft excel",
        "powerpoint": "microsoft powerpoint", "outlook": "microsoft outlook", "teams": "microsoft teams",
        "app store": "app store", "activity": "activity monitor", "task manager": "activity monitor",
        "files": "finder", "photo": "photos", "itunes": "music", "imessage": "messages", "texts": "messages",
    ]

    private static let folders: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
            home.appendingPathComponent("Applications").path, home.appendingPathComponent("Applications/Chrome Apps").path,
            "/System/Library/CoreServices/Applications",
        ].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }()

    /// Words that can start a request to quit an app.
    static let quitVerbs = ["quit", "close", "exit"]

    static func key(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    static func make(_ name: String, _ url: URL) -> App {
        App(name: name, url: url, key: key(name), words: name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    /// Every app in the usual folders (and one folder deep, e.g. "Microsoft Office/…"). Earlier folders win.
    static func installed() -> [App] {
        let fm = FileManager.default
        var seen = Set<String>(), apps: [App] = []
        func add(_ url: URL) {
            let name = (fm.displayName(atPath: url.path) as NSString).deletingPathExtension
            let k = key(name)
            guard !k.isEmpty, !seen.contains(k), name != "M.I.S.A." else { return }
            seen.insert(k)
            apps.append(make(name, url))
        }
        // Listed by path: Safari in /Applications is a hidden link into a system volume, which a
        // hidden-files-skipping listing leaves out.
        func list(_ dir: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted().map { dir.appendingPathComponent($0) }
        }
        for dir in folders {
            for url in list(dir) {
                if url.pathExtension == "app" { add(url) }
                else if dir.path == "/Applications", (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    for inner in list(url) where inner.pathExtension == "app" { add(inner) }
                }
            }
        }
        add(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        return apps
    }

    /// Best match for what was said, or nil.
    static func find(_ query: String, in apps: [App]) -> App? {
        var q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let alias = aliases[q] { q = alias }
        let qk = key(q)
        guard qk.count >= 2 else { return nil }
        let qWords = q.split { !$0.isLetter && !$0.isNumber }.map(String.init)

        func score(_ a: App) -> Int {
            if a.key == qk { return 100 }
            if a.key.hasPrefix(qk) { return 85 }
            // Every word said starts a word of the name ("visual code", "studio")
            if !qWords.isEmpty, qWords.allSatisfy({ w in a.words.contains { $0.hasPrefix(w) } }) { return 75 }
            // Initials ("vsc" → Visual Studio Code)
            if qk.count >= 2, a.words.count >= 2, String(a.words.compactMap(\.first)) == qk { return 70 }
            if qk.count >= 3, a.key.contains(qk) { return 55 }
            return 0
        }
        let best = apps.map { ($0, score($0)) }.filter { $0.1 > 0 }
            .max { l, r in l.1 != r.1 ? l.1 < r.1 : l.0.name.count > r.0.name.count }
        return best?.0
    }

    /// The app names in "open safari and notes" (after the verb).
    static func names(in text: String) -> [String] {
        var s = text.lowercased()
        for filler in ["please", "for me", "can you", "could you", "would you", "the app", "app", "application", "up"] {
            s = s.replacingOccurrences(of: "\\b\(filler)\\b", with: " ", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "^\\s*(the|my)\\s+", with: "", options: .regularExpression)
        return s.components(separatedBy: CharacterSet(charactersIn: ",&"))
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.replacingOccurrences(of: "^\\s*(the|my)\\s+", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }
    }

    /// What follows a launch verb at the start of the request, or nil if it doesn't start with one.
    static func target(of raw: String, verbs: [String] = verbs) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for lead in ["please ", "hey misa ", "misa ", "can you ", "could you ", "would you "] where s.hasPrefix(lead) {
            s = String(s.dropFirst(lead.count))
        }
        for v in verbs where s.hasPrefix(v + " ") {
            return String(s.dropFirst(v.count + 1))
        }
        return nil
    }

    /// Opens the apps named in `rest`. Returns nil when nothing matched, so the request can go elsewhere.
    static func open(_ rest: String) -> Reply? {
        let wanted = names(in: rest)
        guard !wanted.isEmpty else { return nil }
        let apps = installed()
        var opened: [String] = [], missing: [String] = []
        for w in wanted {
            guard let app = find(w, in: apps) else { missing.append(w); continue }
            guard !opened.contains(app.name) else { continue }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, error in
                if let error { FileOps.log("open-app: \(app.name) failed: \(error.localizedDescription)") }
            }
            opened.append(app.name)
        }
        guard !opened.isEmpty else { return nil }
        FileOps.log("open-app: \(opened.joined(separator: ", "))")
        var text = "Opening \(list(opened))."
        if !missing.isEmpty { text += " I couldn't find \(list(missing.map { "“\($0)”" }))." }
        return Reply(text: text)
    }

    static func notFound(_ rest: String) -> Reply {
        let what = names(in: rest).first ?? rest
        return Reply(text: "I couldn't find an app called “\(what)” in Applications.")
    }

    // MARK: Quitting

    /// Apps with a Dock icon that are running now, except M.I.S.A. and Finder (which can't quit).
    static func running() -> [(app: App, proc: NSRunningApplication)] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { r in
            guard r.activationPolicy == .regular, r.processIdentifier != me, r.bundleIdentifier != "com.apple.finder",
                  let name = r.localizedName, let url = r.bundleURL else { return nil }
            return (make(name, url), r)
        }
    }

    /// Quits the apps named in `rest` the normal way, so they can ask to save first.
    /// "quit everything" asks on a confirm card. Returns nil when nothing matched.
    static func quit(_ rest: String) -> Reply? {
        let wanted = names(in: rest)
        guard !wanted.isEmpty else { return nil }
        let live = running()

        if wanted.count == 1, ["all", "everything", "all apps", "all my apps", "everything open", "all of them"].contains(wanted[0]) {
            guard !live.isEmpty else { return Reply(text: "No other apps are open.") }
            let procs = live.map(\.proc), names = live.map(\.app.name)
            return Reply(
                text: "\(FileOps.plural(live.count, "app")) are open.",
                confirm: .init(title: "Quit all of them? Apps with unsaved work will ask first.", items: names, button: "Quit \(live.count)", danger: false) {
                    procs.forEach { $0.terminate() }
                    FileOps.log("quit-app: all (\(names.joined(separator: ", ")))")
                    return Reply(text: "Quitting \(list(names)).")
                }
            )
        }

        var quit: [String] = [], notOpen: [String] = [], unknown: [String] = []
        var installedApps: [App]?
        for w in wanted {
            if let hit = find(w, in: live.map(\.app)), let r = live.first(where: { $0.app.name == hit.name }) {
                if !quit.contains(hit.name) { r.proc.terminate(); quit.append(hit.name) }
            } else {
                if installedApps == nil { installedApps = installed() }
                if let app = find(w, in: installedApps!) { notOpen.append(app.name) } else { unknown.append("“\(w)”") }
            }
        }
        guard !quit.isEmpty || !notOpen.isEmpty else { return nil }
        if !quit.isEmpty { FileOps.log("quit-app: \(quit.joined(separator: ", "))") }
        var parts: [String] = []
        if !quit.isEmpty { parts.append("Quitting \(list(quit)).") }
        if !notOpen.isEmpty { parts.append("\(list(notOpen)) \(notOpen.count == 1 ? "isn't" : "aren't") open.") }
        if !unknown.isEmpty { parts.append("I couldn't find \(list(unknown)).") }
        return Reply(text: parts.joined(separator: " "))
    }

    static func notRunning(_ rest: String) -> Reply {
        let what = names(in: rest).first ?? rest
        return Reply(text: "I couldn't find an open app called “\(what)”.")
    }

    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0, 1: return items.first ?? ""
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items.last!
        }
    }
}
