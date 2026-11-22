import AppKit
import UserNotifications

/// Keeps M.I.S.A. up to date from the folder she was built in: `git pull`, then `./install.sh`,
/// which rebuilds her, swaps the app and reopens her.
///
/// build.sh writes the source folder, commit and PATH into Info.plist. Once a day she fetches
/// from GitHub; when there's something new she says so in the chat (the unread dot) and posts a
/// macOS notification. Nothing is downloaded or installed until you say so.
enum Updater {
    struct Build { let source: URL; let commit: String; let path: String }

    /// Where this copy was built from, or nil for a build made before updates existed.
    static let build: Build? = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let src = info["MISASource"] as? String, !src.isEmpty else { return nil }
        return Build(source: URL(fileURLWithPath: src, isDirectory: true),
                     commit: info["MISACommit"] as? String ?? "",
                     path: info["MISABuildPath"] as? String ?? "")
    }()

    /// Things she says on her own (an update is out, an update failed). Called on main.
    static var announce: ((Reply) -> Void)?

    static let updateLog = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/misa-update.log")
    private static let defaults = UserDefaults.standard

    // MARK: What you can say

    /// "update yourself", "check for updates", "what version are you", "stop checking for updates".
    static func route(_ t: String) -> (() -> Reply)? {
        let words = " \(t) "
        func says(_ p: String...) -> Bool { p.contains { words.contains(" \($0) ") } }

        if says("update", "updates", "upgrade", "updated") {
            if says("stop", "dont", "don't", "turn off", "disable", "no more", "never") { return { setAutoCheck(false) } }
            if says("turn on", "enable", "automatically", "every day", "daily") { return { setAutoCheck(true) } }
        }
        if says("what version", "which version", "your version", "version are you", "version number") { return { version() } }
        let asks = says("update", "updates", "upgrade") || says("latest version", "new version", "newest version")
        // Only about her: "update yourself", "check for updates", "update" alone, not "update my resume".
        let mine = t == "update" || t == "update now" || t == "upgrade"
            || says("yourself", "misa", "m.i.s.a", "you", "check", "any", "there", "install", "get", "latest", "new", "newest", "available", "out")
        return asks && mine ? { check() } : nil
    }

    static func version() -> Reply {
        guard let b = build, !b.commit.isEmpty else { return Reply(text: "I don't know my version: this copy was built before I could update myself. Run ./install.sh once from the misa folder and I'll keep track.") }
        let date = git(b.source, "show", "-s", "--format=%cd", "--date=format:%B %-d, %Y", b.commit).out
        return Reply(text: "I'm version \(b.commit.prefix(7))\(date.isEmpty ? "" : ", from \(date)").",
                     suggestions: [.init(label: "Check for updates", prompt: "Check for updates")])
    }

    // MARK: Checking

    private enum Status { case upToDate(String), available([String], head: String), problem(Reply) }

    private static func status() -> Status {
        guard let b = build else {
            return .problem(Reply(text: "This copy of me was built before I could update myself. Open Terminal in the misa folder and run git pull, then ./install.sh. After that, just ask me."))
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: b.source.appendingPathComponent(".git").path) else {
            return .problem(Reply(text: "I was installed from a download, not with git, so I can't pull updates. Get the newest version from github.com/The-Hieusss/misa, or clone it with git so I can update myself next time."))
        }
        guard fm.fileExists(atPath: b.source.appendingPathComponent("install.sh").path) else {
            return .problem(Reply(text: "I can't find my source folder anymore (\(b.source.path)). If you moved it, run ./install.sh from its new spot."))
        }
        let fetch = git(b.source, "fetch", "--quiet")
        guard fetch.status == 0 else {
            FileOps.log("update: fetch failed: \(fetch.err)")
            return .problem(Reply(text: "I couldn't reach GitHub to check for updates. Are you online?"))
        }
        var upstream = git(b.source, "rev-parse", "--abbrev-ref", "@{u}").out
        if upstream.isEmpty || upstream.contains("fatal") { upstream = "origin/main" }
        let head = git(b.source, "rev-parse", upstream).out
        // Compare against the commit she was built from; fall back to the folder's HEAD.
        let base = !b.commit.isEmpty && git(b.source, "cat-file", "-e", b.commit + "^{commit}").status == 0 ? b.commit : "HEAD"
        let log = git(b.source, "log", "--no-merges", "--format=%s", "\(base)..\(upstream)")
        guard log.status == 0 else {
            FileOps.log("update: log failed: \(log.err)")
            return .problem(Reply(text: "I couldn't compare my version with GitHub's."))
        }
        let changes = log.out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return changes.isEmpty ? .upToDate(String(git(b.source, "rev-parse", "--short", base).out)) : .available(changes, head: head)
    }

    /// "Update yourself" / "check for updates": a confirm card listing what's new.
    static func check() -> Reply {
        switch status() {
        case .problem(let r):
            return r
        case .upToDate(let v):
            return Reply(text: "I'm up to date (version \(v)). ✨")
        case .available(let changes, _):
            var items = Array(changes.prefix(12))
            if changes.count > items.count { items.append("…and \(changes.count - items.count) more") }
            return Reply(
                text: "There's a new version of me with \(FileOps.plural(changes.count, "change")).",
                confirm: .init(title: "Update now? I'll download it, rebuild myself and restart. It takes a minute or two.",
                               items: items, button: "Update", danger: false) { apply(changes) }
            )
        }
    }

    // MARK: Installing

    private static func apply(_ changes: [String]) -> Reply {
        guard let b = build else { return Reply(text: "I don't know where I was built from.") }
        let pull = git(b.source, "pull", "--ff-only", "--quiet")
        guard pull.status == 0 else {
            FileOps.log("update: pull failed: \(pull.err)")
            if pull.err.contains("overwritten") || pull.err.contains("local changes") {
                return Reply(text: "Some of my files in \(b.source.path) were edited on this Mac, and the update would overwrite them. Commit or stash those edits, then ask me again.")
            }
            if pull.err.contains("fast-forward") || pull.err.contains("diverge") {
                return Reply(text: "My folder has its own commits that GitHub doesn't, so I can't update on my own. Run git pull in \(b.source.path) to merge them, then ./install.sh.")
            }
            return Reply(text: "The download failed: \(pull.err.split(separator: "\n").first ?? "unknown error").")
        }

        // install.sh rebuilds, quits this copy, swaps the app and reopens it. It outlives us, so its
        // output goes to a file (a pipe to a quit app would break it).
        let fm = FileManager.default
        fm.createFile(atPath: updateLog.path, contents: Data("Update started \(Date())\n".utf8))
        guard let out = try? FileHandle(forWritingTo: updateLog) else { return Reply(text: "I couldn't start the update.") }
        out.seekToEndOfFile()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [b.source.appendingPathComponent("install.sh").path]
        p.currentDirectoryURL = b.source
        var env = ProcessInfo.processInfo.environment
        let home = fm.homeDirectoryForCurrentUser.path
        env["PATH"] = [b.path, "\(home)/.bun/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            .filter { !$0.isEmpty }.joined(separator: ":")
        // Reinstall where she lives now, unless this is the copy in the source folder's build/.
        let here = Bundle.main.bundleURL.deletingLastPathComponent()
        if !here.path.hasPrefix(b.source.path + "/") { env["INSTALL_DIR"] = here.path }
        env["OPEN"] = "1"
        p.environment = env
        p.standardOutput = out
        p.standardError = out
        p.terminationHandler = { proc in
            // Only reached if we're still running: the build failed before install.sh quit us.
            guard proc.terminationStatus != 0 else { return }
            FileOps.log("update: install.sh exited \(proc.terminationStatus)")
            DispatchQueue.main.async {
                defaults.removeObject(forKey: "updateFrom")
                announce?(Reply(text: "The update didn't finish, so I'm still on the old version. What went wrong is in ~/Library/Logs/misa-update.log.",
                                suggestions: [.init(label: "Try again", prompt: "Update yourself")]))
            }
        }
        do { try p.run() } catch {
            FileOps.log("update: couldn't run install.sh: \(error)")
            return Reply(text: "I couldn't start the update.")
        }
        defaults.set(b.commit, forKey: "updateFrom")
        defaults.set(Array(changes.prefix(12)), forKey: "updateChanges")
        FileOps.log("update: pulled \(changes.count) change(s), rebuilding")
        return Reply(text: "Downloaded \(FileOps.plural(changes.count, "change")). Rebuilding myself now; I'll be back in a minute or two. 🔧")
    }

    /// After an update she restarts as the new version and says what changed. Nil otherwise.
    static func greeting() -> Reply? {
        guard let from = defaults.string(forKey: "updateFrom") else { return nil }
        let changes = defaults.stringArray(forKey: "updateChanges") ?? []
        defaults.removeObject(forKey: "updateFrom")
        defaults.removeObject(forKey: "updateChanges")
        guard let b = build, b.commit != from else { return nil }
        FileOps.log("update: now on \(b.commit.prefix(7))")
        let list = changes.map { "• \($0)" }.joined(separator: "\n")
        return Reply(text: "I'm updated to version \(b.commit.prefix(7)). ✨" + (list.isEmpty ? "" : " What's new:\n\(list)"))
    }

    // MARK: Daily check

    private static var autoCheck: Bool { defaults.object(forKey: "updateChecks") as? Bool ?? true }
    private static var timer: Timer?

    private static func setAutoCheck(_ on: Bool) -> Reply {
        defaults.set(on, forKey: "updateChecks")
        return Reply(text: on ? "Okay, I'll check GitHub for a new version once a day and tell you when there is one."
                              : "Okay, I'll stop checking for updates. Say “check for updates” any time.")
    }

    /// Checks a minute after launch, then hourly, fetching at most once a day.
    static func startDailyCheck() {
        guard build != nil else { return }
        let t = Timer(timeInterval: 3600, repeats: true) { _ in checkInBackground() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { checkInBackground() }
    }

    private static func checkInBackground() {
        guard autoCheck else { return }
        let last = defaults.object(forKey: "updateLastCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 20 * 3600 else { return }
        defaults.set(Date(), forKey: "updateLastCheck")
        DispatchQueue.global(qos: .utility).async {
            guard case .available(let changes, let head) = status() else { return }
            DispatchQueue.main.async {
                // Tell once per new version, not every day.
                guard defaults.string(forKey: "updateNotified") != head else { return }
                defaults.set(head, forKey: "updateNotified")
                FileOps.log("update: \(changes.count) new change(s) on GitHub")
                let first = changes.first ?? ""
                announce?(Reply(text: "A new version of me is out, with \(FileOps.plural(changes.count, "change")) (latest: “\(first)”).",
                                suggestions: [.init(label: "Update now", prompt: "Update yourself"),
                                              .init(label: "Stop update checks", prompt: "Stop checking for updates")]))
                notify(title: "M.I.S.A. has an update",
                       body: "\(FileOps.plural(changes.count, "change")) on GitHub. Click to open the chat, then tap Update now.")
            }
        }
    }

    // MARK: macOS notifications

    /// A banner in the top-right corner. macOS asks the first time; if you say no, the chat message is still there.
    static func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted else {
                if let error { FileOps.log("notify: \(error.localizedDescription)") }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "misa-update", content: content, trigger: nil)) { error in
                if let error { FileOps.log("notify: \(error.localizedDescription)") }
            }
        }
    }

    // MARK: git

    private static func git(_ src: URL, _ args: String...) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", src.path] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0" // never wait for a password prompt nobody can see
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return (-1, "", "\(error)") }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let trim = { (d: Data) in String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
        return (p.terminationStatus, trim(o), trim(e))
    }
}
