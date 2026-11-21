import AppKit

/// Turns what you say (or drop) into one action.
/// Keyword matching for now, like the portfolio's brain.ts; Apple's on-device model plugs in here later.
/// All state lives on the main thread; actions run on a background queue.
final class Brain {
    /// Files you dropped on M.I.S.A.: "these" / "them" in later requests.
    private var files: [URL] = []
    /// Files the last action produced, for "Show in Finder".
    private var outputs: [URL] = []
    /// Confirm cards waiting for a click.
    private var pending: [String: Reply.Confirm] = [:]
    private let work = DispatchQueue(label: "misa.actions", qos: .userInitiated)
    let timer: FocusTimer
    /// Asks the window to put her away into the menu bar.
    var onDock: (() -> Void)?

    init(timer: FocusTimer) { self.timer = timer }

    private static let starters: [Reply.Suggestion] = [
        .init(label: "What can you do?", prompt: "What can you do?"),
        .init(label: "Focus for 25 min", prompt: "Focus for 25 minutes"),
        .init(label: "Tidy my screenshots", prompt: "Tidy my screenshots"),
        .init(label: "What's in Disposable?", prompt: "What's in Disposable?"),
        .init(label: "What's using my disk?", prompt: "What's using my disk?"),
    ]

    // MARK: Entry points (call on main; `done` is called on main)

    func handle(_ raw: String, done: @escaping (Reply) -> Void) {
        let t = Self.normalize(raw)
        if let action = route(t, raw: raw) { perform(action, done: done) } else { done(chat(t)) }
    }

    func filesDropped(_ urls: [URL], done: @escaping (Reply) -> Void) {
        files = urls
        done(describeDrop(urls))
    }

    func confirm(_ id: String, done: @escaping (Reply) -> Void) {
        guard let c = pending.removeValue(forKey: id) else { return done(Reply(text: "That request expired. Ask me again.")) }
        perform(c.run, done: done)
    }

    func cancel(_ id: String, done: @escaping (Reply) -> Void) {
        pending[id] = nil
        done(Reply(text: "Okay, I left everything as it was."))
    }

    /// What she says when a timer runs out.
    func timerFinished(_ label: String) -> Reply {
        if label == "Break" {
            return Reply(text: "Break's over. Ready for another focus session?",
                         suggestions: [.init(label: "Focus 25 min", prompt: "Focus for 25 minutes"),
                                       .init(label: "Focus 50 min", prompt: "Focus for 50 minutes")])
        }
        let text = label == "Focus" ? "⏰ Focus session done. Nice work." : "⏰ Time's up."
        return Reply(text: text,
                     suggestions: [.init(label: "5-min break", prompt: "Take a 5 minute break"),
                                   .init(label: "Focus 25 more", prompt: "Focus for 25 minutes")])
    }

    private func perform(_ action: @escaping () -> Reply, done: @escaping (Reply) -> Void) {
        work.async {
            let reply = action()
            DispatchQueue.main.async {
                if let c = reply.confirm { self.pending[c.id] = c }
                if !reply.outputs.isEmpty { self.outputs = reply.outputs }
                done(reply)
            }
        }
    }

    // MARK: Routing

    /// Returns the action to run, or nil for small talk.
    private func route(_ t: String, raw: String) -> (() -> Reply)? {
        let files = self.files

        if has(t, "show in finder", "reveal", "show me", "open folder") && !outputs.isEmpty {
            let outs = outputs
            return { FileOps.onMain { NSWorkspace.shared.activateFileViewerSelecting(outs) }; return Reply(text: "Opened in Finder.") }
        }

        // Disposable
        if t.hasPrefix("keep ") || t == "keep" {
            let query = String(raw.trimmingCharacters(in: .whitespaces).dropFirst(4)).trimmingCharacters(in: .whitespaces)
            return { DisposableActions.keep(matching: query) }
        }
        // Put her away into the menu bar
        if has(t, "go away", "put yourself away", "put away", "hide", "dock", "minimize", "menu bar", "get out of the way", "go to the menu bar") {
            return { [weak self] in
                // Let her reply show for a moment, then teleport up.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { self?.onDock?() }
                return Reply(text: "Heading up to the menu bar. Click the camera when you need me.")
            }
        }

        // Quit apps: "quit Spotify", "close Safari and Notes" (before the timer, which also hears "quit")
        if let rest = AppLauncher.target(of: raw, verbs: AppLauncher.quitVerbs),
           !has(t, "timer", "focus", "break", "countdown", "pomodoro", "chat") {
            return { AppLauncher.quit(rest) ?? AppLauncher.notRunning(rest) }
        }

        // Timer
        if let action = timerAction(t, raw: raw) { return action }

        // Open apps: "open Claude", "launch Safari and Notes"
        if let rest = AppLauncher.target(of: raw) {
            let firm = ["open", "launch", "fire up", "bring up", "pull up", "switch to"].contains { t.hasPrefix($0 + " ") || t.contains(" \($0) ") }
            if let reply = AppLauncher.open(rest) { return { reply } }
            if firm { return { AppLauncher.notFound(rest) } }
        }

        // Unit conversions, then plain math (both need a number)
        if let r = UnitConverter.answer(raw) { return { r } }
        if let r = Calculator.answer(raw) { return { r } }

        if has(t, "disposable", "throw away", "throwaway", "temporary", "dont need", "don't need") {
            if !files.isEmpty && has(t, "mark", "make", "move", "these", "them", "this", "it", "throw away", "throwaway", "temporary", "dont need", "don't need") {
                return { DisposableActions.mark(files) }
            }
            return { DisposableActions.status() }
        }
        if has(t, "expiring", "expire", "expires") { return { DisposableActions.status() } }

        // Trash
        if has(t, "trash", "trash can", "bin", "recycle") && has(t, "empty", "clear", "clean", "take out", "delete", "purge")
            && !has(t, "screenshot", "screenshots") {
            return { TrashBin.empty() }
        }

        // Screenshots
        if has(t, "screenshot", "screenshots", "screen shot", "screen recording", "screen recordings") {
            if has(t, "old", "older", "trash", "delete", "remove") { return { Screenshots.trashOld() } }
            if has(t, "save", "location", "go to", "default", "stop", "instead") { return { Screenshots.saveToFolder() } }
            return { Screenshots.tidy() }
        }

        // Downloads and disk
        if has(t, "downloads") && has(t, "tidy", "clean", "cleanup", "old", "organize", "clear", "declutter") {
            return { DownloadsTidy.run() }
        }
        if has(t, "disk", "storage", "space", "big files", "biggest", "taking up", "using my") {
            return { DiskReport.run() }
        }

        // Actions on dropped files
        let fileAction: (() -> Reply)? = {
            if has(t, "canvas", "submit", "submission", "turn in", "assignment") { return { CanvasPrep.run(files) } }
            if has(t, "copy", "text", "for ai", "claude", "chatgpt", "paste", "clipboard", "read") { return { CopyForAI.run(files) } }
            if has(t, "mp4", "video", "videos", "recording") { return { Convert.toMP4(files) } }
            if has(t, "jpg", "jpeg", "heic") { return { Convert.toJPG(files) } }
            if has(t, "shrink", "resize", "smaller", "compress", "reduce") { return { Convert.shrink(files) } }
            if has(t, "combine", "merge", "one pdf", "into a pdf", "into pdf") { return { Convert.imagesToPDF(files) } }
            if has(t, "pdf") {
                return files.allSatisfy({ FileOps.kind($0) == .image }) ? { Convert.imagesToPDF(files) } : { CanvasPrep.run(files) }
            }
            if has(t, "convert") {
                if files.contains(where: { FileOps.kind($0) == .video }) { return { Convert.toMP4(files) } }
                if files.contains(where: { FileOps.kind($0) == .image }) { return { Convert.toJPG(files) } }
            }
            return nil
        }()
        if let fileAction {
            if files.isEmpty { return { Reply(text: "Drop the files on me first, then tell me what to do with them.") } }
            return fileAction
        }
        return nil
    }

    private func timerAction(_ t: String, raw: String) -> (() -> Reply)? {
        let timer = self.timer
        let active = timer.state == .running || timer.state == .paused
        // File requests ("prep my study guide for Canvas") never start a timer.
        if has(t, "canvas", "pdf", "jpg", "jpeg", "mp4", "copy", "convert", "shrink", "screenshot", "screenshots") { return nil }
        let mentionsTimer = has(t, "timer", "focus", "pomodoro", "break", "countdown")
            || (has(t, "study", "studying") && FocusTimer.parseDuration(raw) != nil)

        if active && has(t, "time left", "how long left", "how much time", "how much longer", "remaining", "status") {
            return { FileOps.onMain {
                Reply(text: "\(FocusTimer.describe(timer.remaining)) left on your \(timer.label.lowercased()) timer\(timer.state == .paused ? " (paused)" : "").")
            } }
        }
        if has(t, "pause") && (mentionsTimer || active) {
            return { FileOps.onMain { () -> Reply in
                guard timer.state == .running else { return Reply(text: "There's no timer running.") }
                timer.pause()
                return Reply(text: "Paused with \(FocusTimer.describe(timer.remaining)) left.", suggestions: [.init(label: "Resume", prompt: "Resume the timer")])
            } }
        }
        if has(t, "resume", "continue", "unpause") && (mentionsTimer || timer.state == .paused) {
            return { FileOps.onMain { () -> Reply in
                guard timer.state == .paused else { return Reply(text: "There's no paused timer.") }
                timer.resume()
                return Reply(text: "Resumed. \(FocusTimer.describe(timer.remaining)) to go.")
            } }
        }
        if has(t, "stop", "cancel", "end", "reset", "quit") && (mentionsTimer || active) {
            return { FileOps.onMain { () -> Reply in
                guard active else { return Reply(text: "There's no timer running.") }
                timer.stop()
                return Reply(text: "Timer stopped.")
            } }
        }
        guard mentionsTimer else { return nil }

        let isBreak = has(t, "break")
        let label = isBreak ? "Break" : (has(t, "timer", "countdown") && !has(t, "focus", "study", "studying", "pomodoro") ? "Timer" : "Focus")
        let fallback: TimeInterval? = isBreak ? (has(t, "long break") ? 900 : 300) : (label == "Focus" ? 1500 : nil)
        guard let seconds = FocusTimer.parseDuration(raw) ?? fallback else {
            return { Reply(text: "For how long?", suggestions: [
                .init(label: "5 min", prompt: "Set a timer for 5 minutes"),
                .init(label: "25 min", prompt: "Set a timer for 25 minutes"),
                .init(label: "1 hour", prompt: "Set a timer for 1 hour"),
            ]) }
        }
        return { FileOps.onMain { () -> Reply in
            let replacing = active ? " (replaced your other timer)" : ""
            timer.start(seconds, label: label)
            let what = label == "Focus" ? "Focus timer" : label == "Break" ? "Break" : "Timer"
            return Reply(text: "\(what) started: \(FocusTimer.describe(seconds))\(replacing). Watch the ring around me.",
                         suggestions: [.init(label: "Pause", prompt: "Pause the timer"), .init(label: "Stop", prompt: "Stop the timer")])
        } }
    }

    private func describeDrop(_ urls: [URL]) -> Reply {
        let kinds = Set(urls.map(FileOps.kind))
        var s: [Reply.Suggestion] = []
        if kinds.contains(.image) {
            s += [.init(label: "Convert to JPG", prompt: "Convert to JPG"),
                  .init(label: "Shrink", prompt: "Shrink them"),
                  .init(label: "Combine into PDF", prompt: "Combine into one PDF")]
        }
        if kinds.contains(.video) { s.append(.init(label: "Convert to MP4", prompt: "Convert to MP4")) }
        if !kinds.isDisjoint(with: [.pdf, .document, .text, .folder]) {
            s.append(.init(label: "Copy text for AI", prompt: "Copy the text for AI"))
        }
        if !kinds.isDisjoint(with: [.pdf, .document, .text, .image]) {
            s.append(.init(label: "Prep for Canvas", prompt: "Prep for Canvas"))
        }
        s.append(.init(label: "Mark disposable", prompt: "Mark these disposable"))

        let names = urls.map { FileOps.kind($0) == .folder ? $0.lastPathComponent + "/" : $0.lastPathComponent }
        return Reply(text: "Got \(FileOps.plural(urls.count, "item")):\n\(FileOps.bullets(names, max: 5))\n\nWhat should I do with \(urls.count == 1 ? "it" : "them")?",
                     suggestions: s)
    }

    // MARK: Small talk

    private func chat(_ t: String) -> Reply {
        guard !t.isEmpty else { return Reply(text: "I'm listening.") }
        if has(t, "what can you do", "help", "abilities", "features", "commands") {
            return Reply(text: """
            Drop files on me, then pick:
            • Convert images to JPG, shrink them, or combine them into one PDF
            • Convert videos to MP4
            • Copy the text of PDFs, Word files or a code folder for AI
            • Prep a file for Canvas (PDF + a proper file name)
            • Mark files disposable (Trash in \(DisposableActions.hours)h)

            Or ask me to:
            • Start a focus timer ("focus for 25 min", "take a break")
            • Do math ("15% of $84.50", "sqrt(2) * 3")
            • Convert units ("3 cups in ml", "72 f to c")
            • Tidy your screenshots, or trash old ones
            • Save new screenshots to a folder
            • Tidy old downloads
            • Empty the Trash
            • Open or quit apps ("open Claude", "quit Spotify")
            • Show what's using your disk
            • Show what's in Disposable, or keep a file
            """, suggestions: Array(Self.starters.dropFirst()))
        }
        if has(t, "time left", "how long left", "how much time") {
            return Reply(text: "There's no timer running.", suggestions: [.init(label: "Focus 25 min", prompt: "Focus for 25 minutes")])
        }
        if has(t, "time", "date", "day", "today") {
            let f = DateFormatter()
            f.dateFormat = "EEEE, MMMM d · h:mm a"
            return Reply(text: "It's \(f.string(from: Date())).")
        }
        if has(t, "who are you", "what are you", "your name", "misa", "m.i.s.a") {
            return Reply(text: "I'm M.I.S.A., Mac Internal Services Assistant. I run entirely on this Mac: no account, no API key, and nothing you type or drop leaves your computer.")
        }
        if has(t, "hi", "hello", "hey", "yo", "sup", "good morning", "good evening") {
            return Reply(text: "Hey. Drop a file on me or pick something:", suggestions: Self.starters)
        }
        if has(t, "thank", "thanks", "thx", "ty") { return Reply(text: "Anytime.") }
        return Reply(text: "I can't do that yet. Here's what I can do:", suggestions: Self.starters)
    }

    // MARK: Text helpers

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "[^a-z0-9.'\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// True when any phrase appears as whole words (a trailing "s" is allowed).
    private func has(_ t: String, _ phrases: String...) -> Bool {
        let padded = " \(t) "
        return phrases.contains { padded.contains(" \($0) ") || padded.contains(" \($0)s ") }
    }
}
