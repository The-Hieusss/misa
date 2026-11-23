import AppKit

/// Turns what you say (or drop) into one action.
/// Keyword matching for now, like the portfolio's brain.ts; Apple's on-device model plugs in here later.
/// All state lives on the main thread; actions run on a background queue.
final class Brain {
    /// Files you dropped on M.I.S.A.: "these" / "them" in later requests.
    private var files: [URL] = []
    /// Files the last action produced, for "Show in Finder".
    private var outputs: [URL] = []
    /// The last file search's results, for "open 2" / "use 1".
    private var found: [URL] = []
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
        if let r = AIBrain.toggle(t) { return done(r) }
        // Exact commands first: instant, and the same every time.
        if let action = route(t, raw: raw) { return perform(action, done: done) }
        if has(t, "what can you do", "help", "commands") || t.isEmpty { return done(chat(t)) }
        if ["never mind", "nevermind", "no", "nope", "cancel", "no thanks"].contains(t) { return done(Reply(text: "Okay, I'll leave it.")) }
        // Anything else: Apple's on-device model works out what was meant.
        guard AIBrain.available else { return done(chat(t)) }
        let files = self.files, timerNow = describeTimer()
        Task {
            let outcome = await AIBrain.interpret(raw, files: files, timer: timerNow)
            await MainActor.run { self.finish(outcome, fallback: t, done: done) }
        }
    }

    /// Runs what the AI brain decided, through the same router (and confirm cards) as typed commands.
    private func finish(_ outcome: AIBrain.Outcome, fallback t: String, done: @escaping (Reply) -> Void) {
        switch outcome {
        case .say(let text):
            done(Reply(text: text))
        case .failed:
            done(chat(t))
        case .command(let command, _):
            let c = Self.normalize(command)
            // Quitting has no confirm card of its own, so check first when the model chose it.
            if c.hasPrefix("quit ") {
                let what = String(command.dropFirst(5))
                return done(Reply(text: what == "everything" ? "Quit all your apps?" : "Quit \(what)?",
                                  suggestions: [.init(label: "Yes, quit", prompt: command), .init(label: "No", prompt: "never mind")]))
            }
            if let action = route(c, raw: command) { perform(action, done: done) } else { done(chat(c)) }
        }
    }

    /// The timer, in words for the AI brain ("running, 12 min left"), or "" when idle.
    private func describeTimer() -> String {
        switch timer.state {
        case .running: return "\(timer.label) running, \(FocusTimer.describe(timer.remaining)) left"
        case .paused: return "\(timer.label) paused, \(FocusTimer.describe(timer.remaining)) left"
        default: return ""
        }
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
                if let moved = reply.replacesFiles { self.files = moved }
                if let hits = reply.found { self.found = hits }
                done(reply)
            }
        }
    }

    // MARK: Routing

    /// Returns the action to run, or nil for small talk.
    private func route(_ t: String, raw: String) -> (() -> Reply)? {
        let files = self.files

        // "Hey MISA": "start listening", "stop listening", "are you listening"
        if let r = VoiceListener.route(t) { return { r } }

        // Updating herself: "update yourself", "check for updates", "what version are you"
        if let action = Updater.route(t) { return action }

        // Picking from the last file search: "open 2", "show 3 in finder", "use the first one"
        if let r = FindFiles.pick(t, from: found) { return { r } }
        // "open it" / "open them": the file(s) she's holding (found or dropped)
        if !files.isEmpty, ["open it", "open this", "open that", "open them", "open these", "open those", "open the file", "open the files"].contains(t) {
            let targets = files
            return {
                if targets.count == 1 { return FindFiles.open(targets[0]) }
                targets.forEach { u in FileOps.onMain { _ = NSWorkspace.shared.open(u) } }
                return Reply(text: "Opening \(FileOps.plural(targets.count, "file")).")
            }
        }
        // Finding files: "find my resume pdf", "where is homework 6", "find photos from last week"
        if let q = FindFiles.parse(raw) { return { FindFiles.run(q) } }

        // Control Center: volume, mic, brightness, sound devices, Bluetooth, Do Not Disturb
        if let action = SystemControls.route(t, raw: raw) { return action }

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

        // Move or copy files: "move this to Desktop", "copy Homework 6.pdf to Documents", "undo"
        if ["undo", "undo that", "undo it", "undo the move", "undo the copy", "put it back", "put them back", "move it back", "move them back"]
            .contains(t.trimmingCharacters(in: CharacterSet(charactersIn: " .!"))) {
            return { MoveFiles.undo() }
        }
        if let req = MoveFiles.parse(raw),
           !has(t, "timer", "focus", "break", "countdown", "menu bar", "clipboard", "canvas", "for ai", "claude", "chatgpt") {
            if req.dest.lowercased().contains("disposable") && !files.isEmpty && MoveFiles.meansDropped(req.source) {
                return { DisposableActions.mark(files) }
            }
            return { MoveFiles.run(req, dropped: files) }
        }

        // Quit apps: "quit Spotify", "close Safari and Notes" (before the timer, which also hears "quit")
        if let rest = AppLauncher.target(of: raw, verbs: AppLauncher.quitVerbs),
           !has(t, "timer", "focus", "break", "countdown", "pomodoro", "chat") {
            return { AppLauncher.quit(rest) ?? AppLauncher.notRunning(rest) }
        }

        // Timer
        if let action = timerAction(t, raw: raw) { return action }

        // Open apps and websites: "open Claude", "launch Safari and Notes", "open youtube.com"
        if let rest = AppLauncher.target(of: raw) {
            let firm = ["open", "launch", "fire up", "bring up", "pull up", "switch to"].contains { t.hasPrefix($0 + " ") || t.contains(" \($0) ") }
            if let reply = AppLauncher.open(rest, raw: raw) { return { reply } }
            if firm { return { AppLauncher.notFound(rest) } }
        }

        // Unit conversions, then plain math (both need a number)
        if let r = UnitConverter.answer(raw) { return { r } }
        if let r = Calculator.answer(raw) { return { r } }

        // Web search: "search for mac shortcuts", "google pomodoro technique", "search youtube for lofi"
        if let r = WebOpener.search(raw) { return { r } }

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

        // A question about the timer ("how long till my focus ends") never stops it.
        let question = ["how ", "when ", "what ", "whats ", "what's ", "is ", "does ", "will "].contains { t.hasPrefix($0) } || raw.contains("?")
        if active && (has(t, "time left", "how long left", "how much time", "how much longer", "remaining", "status", "how long till", "how long until", "when does", "when will") || question) {
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
        if has(t, "stop", "cancel", "end", "reset", "quit") && (mentionsTimer || active) && !question {
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
            • Move or copy them ("move this to Desktop")

            Or ask me to:
            • Start a focus timer ("focus for 25 min", "take a break")
            • Do math ("15% of $84.50", "sqrt(2) * 3")
            • Convert units ("3 cups in ml", "72 f to c")
            • Tidy your screenshots, or trash old ones
            • Save new screenshots to a folder
            • Tidy old downloads
            • Empty the Trash
            • Move a file by name ("move Homework 6.pdf to Downloads"), or undo it
            • Open or quit apps ("open Claude", "quit Spotify")
            • Open websites or search ("open youtube.com", "search for mac shortcuts")
            • Find files ("find my resume pdf", "find photos from last week"), then open, show or use one
            • Show what's using your disk
            • Control Center: volume ("volume 40", "mute"), mic ("mute my mic"), brightness ("dim the screen"), \
            sound devices ("switch output to AirPods"), Bluetooth ("connect to Home Speaker"), Do Not Disturb
            • Show what's in Disposable, or keep a file
            • Listen for “Hey MISA” ("start listening", "stop listening")
            • Update myself from GitHub ("update yourself", "what version are you")

            You don't need the exact words: with Apple Intelligence on, I understand plain English, all on this Mac.
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
