import Foundation
#if canImport(FoundationModels)
@_weakLinked import FoundationModels
#endif

/// Plain-English understanding with Apple's on-device model (macOS 26 + Apple Intelligence).
///
/// The keyword router in Brain still runs first. Anything it doesn't recognize comes here: the
/// model reads the request and fills in an `Intent` (guided generation, so it can only pick from
/// what she can actually do). The intent becomes one of the plain commands the router already
/// understands ("move this to Desktop"), so every action still goes through the same code and
/// the same confirm cards. Small talk and questions get the model's own short answer.
enum AIBrain {
    /// What she says to explain why plain English isn't working, or nil when it is.
    static var unavailableReason: String? {
        guard enabled else { return "the AI brain is turned off" }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.appleIntelligenceNotEnabled): return "Apple Intelligence is off (System Settings > Apple Intelligence & Siri)"
            case .unavailable(.modelNotReady): return "Apple's on-device model is still downloading"
            case .unavailable(.deviceNotEligible): return "this Mac can't run Apple's on-device model"
            case .unavailable: return "Apple's on-device model isn't available"
            }
        }
        #endif
        return "it needs macOS 26 with Apple Intelligence"
    }

    static var available: Bool { unavailableReason == nil }

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "aiBrain") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "aiBrain") }
    }

    /// "turn off the AI brain", "turn on smart mode". Nil if it isn't about that.
    static func toggle(_ t: String) -> Reply? {
        let words = " \(t) "
        // Only about the brain itself: "turn off the AI brain", "is your AI on" (not "find my AI essay").
        let named = [" ai brain ", " smart mode ", " apple intelligence "].contains(where: words.contains)
        let aiSwitch = words.contains(" ai ") && [" turn ", " switch ", " your ai ", " is ai ", " ai on ", " ai off "].contains(where: words.contains)
        guard named || aiSwitch else { return nil }
        if [" off ", " disable ", " stop using ", " dont use ", " don't use "].contains(where: words.contains) {
            enabled = false
            return Reply(text: "Okay, AI brain off. I'll stick to my exact commands (say “what can you do” for the list).")
        }
        if [" on ", " enable ", " use ", " start using "].contains(where: words.contains) {
            enabled = true
            if let why = unavailableReason { return Reply(text: "AI brain on, but it can't run yet: \(why).") }
            return Reply(text: "AI brain on. Talk to me however you like; it all stays on this Mac. 🧠")
        }
        if [" status ", " working ", " is ", " are you "].contains(where: words.contains) {
            if let why = unavailableReason { return Reply(text: "My AI brain isn't running: \(why).") }
            return Reply(text: "My AI brain is on, running Apple's on-device model. Nothing you say leaves this Mac.")
        }
        return nil
    }

    /// Loads the model ahead of the first question so that one isn't slow.
    static func prewarm() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), available { Engine.shared.prewarm() }
        #endif
    }

    /// What the model decided: a command for the router, or something to say.
    enum Outcome {
        case command(String, note: String)
        case say(String)
        case failed
    }

    /// Reads `text` and decides what to do. `files` are the dropped files ("this", "them").
    static func interpret(_ text: String, files: [URL], timer: String) async -> Outcome {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), available { return await Engine.shared.interpret(text, files: files, timer: timer) }
        #endif
        return .failed
    }
}

#if canImport(FoundationModels)

@available(macOS 26.0, *)
@Generable
enum IntentAction: String {
    case chat, help, currentTime
    case openApps, quitApps, quitAllApps, openWebsites, webSearch, youtubeSearch
    case startFocus, startBreak, startTimer, pauseTimer, resumeTimer, stopTimer, timeLeft
    case calculate, convertUnits
    case moveFiles, copyFiles, undoMove
    case convertToJPG, convertToMP4, shrinkImages, combineIntoPDF, copyTextForAI, prepForCanvas
    case markDisposable, disposableStatus, keepFile
    case tidyScreenshots, trashOldScreenshots, screenshotsToFolder, tidyDownloads, diskUsage, emptyTrash
    case findFiles
    case putAway, checkForUpdates, version
}

@available(macOS 26.0, *)
@Generable
struct Intent {
    @Guide(description: "The one action that matches the request")
    var action: IntentAction
    @Guide(description: "Every app, website, or file name the request mentions, one per entry, exactly as written. Empty if none.")
    var items: [String]
    @Guide(description: "Search words (for findFiles: the name plus any type, folder or time words), or the full math expression or unit conversion with every number, like '3 cups in ml'. Empty if none.")
    var query: String
    @Guide(description: "Minutes for a focus session, break or timer. 0 if not said.")
    var minutes: Int
    @Guide(description: "Destination folder for moving or copying files, like Desktop or Documents. Empty if none.")
    var destination: String
    @Guide(description: "For chat: your answer, one or two short sentences. Otherwise a few words, never claiming it's done.")
    var reply: String
}

@available(macOS 26.0, *)
final class Engine: @unchecked Sendable {
    static let shared = Engine()

    private let lock = NSLock()
    private var session: LanguageModelSession?
    private var lastUse = Date.distantPast

    private static let instructions = """
    You are M.I.S.A., a small helper that floats on the user's Mac. You're upbeat, brief, a little robotic. \
    Turn each request into one action. Use chat for greetings, thanks and opinions, answering in one or two short sentences.
    Files the user dropped on you: convertToJPG, convertToMP4, shrinkImages, combineIntoPDF, copyTextForAI (to paste \
    into an AI chat), prepForCanvas (hand in for a class), markDisposable (not needed soon, auto-trash), moveFiles, copyFiles.
    startFocus is any work or study session; startBreak is rest; startTimer is a plain countdown (cooking, laundry).
    Examples:
    "I need to grind for an hour" -> startFocus, minutes 60
    "my disk is almost full" -> diskUsage
    "clear out the bin" -> emptyTrash
    "find lofi on youtube" -> youtubeSearch, query "lofi"
    "how many cups is 2 liters" -> convertUnits, query "2 liters in cups"
    "20% of 85" -> calculate, query "20% of 85"
    "close slack" -> quitApps, items ["Slack"]
    "put this on my desktop" -> moveFiles, destination "Desktop"
    "my screenshots are everywhere" -> tidyScreenshots
    "go hide up top" or "get out of the way" -> putAway
    "how long till my focus ends" -> timeLeft
    "where did I save my resume" -> findFiles, query "resume"
    "that pdf I downloaded yesterday" -> findFiles, query "pdf downloaded yesterday"
    """

    private func current() -> LanguageModelSession {
        lock.lock(); defer { lock.unlock() }
        // A fresh conversation after a quiet spell (and keep the small context window clear).
        if session == nil || Date().timeIntervalSince(lastUse) > 15 * 60 {
            session = LanguageModelSession(instructions: Self.instructions)
        }
        lastUse = Date()
        return session!
    }

    private func reset() {
        lock.lock(); session = nil; lock.unlock()
    }

    func prewarm() { current().prewarm() }

    func interpret(_ text: String, files: [URL], timer: String) async -> AIBrain.Outcome {
        var context: [String] = []
        if !files.isEmpty { context.append("Files the user dropped on you: \(files.map(\.lastPathComponent).prefix(8).joined(separator: ", ")).") }
        if !timer.isEmpty { context.append("Timer: \(timer).") }
        let prompt = (context + ["Request: \(text)"]).joined(separator: "\n")

        do {
            let started = Date()
            let intent = try await respond(prompt)
            FileOps.log("ai: “\(text.prefix(80))” → \(intent.action.rawValue) items=\(intent.items) q=\(intent.query) min=\(intent.minutes) dest=\(intent.destination) (\(String(format: "%.1f", Date().timeIntervalSince(started)))s)")
            return Self.outcome(intent, files: files)
        } catch {
            FileOps.log("ai: failed: \(error)")
            reset()
            if "\(error)".contains("guardrail") { return .say("I'd rather not help with that one.") }
            return .failed
        }
    }

    private func respond(_ prompt: String) async throws -> Intent {
        let options = GenerationOptions(temperature: 0.3)
        do {
            return try await current().respond(to: prompt, generating: Intent.self, options: options).content
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // The conversation got too long: start over and try once more.
            reset()
            return try await current().respond(to: prompt, generating: Intent.self, options: options).content
        }
    }

    /// The intent as a command the keyword router understands.
    private static func outcome(_ i: Intent, files: [URL]) -> AIBrain.Outcome {
        let hasFiles = !files.isEmpty
        let items = i.items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0.lowercased() != "none" }
        let list = items.joined(separator: ", ")
        let query = i.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let dest = i.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = i.reply
        let mins = i.minutes > 0 ? "\(i.minutes) minutes" : ""
        func cmd(_ s: String) -> AIBrain.Outcome { .command(s, note: note) }

        switch i.action {
        case .chat: return .say(note.isEmpty ? "🙂" : note)
        case .help: return cmd("what can you do")
        case .currentTime: return cmd("what time is it")
        case .openApps, .openWebsites: return items.isEmpty ? .say(note) : cmd("open \(list)")
        case .quitApps: return items.isEmpty ? .say(note) : cmd("quit \(list)")
        case .quitAllApps: return cmd("quit everything")
        case .webSearch: return query.isEmpty ? .say(note) : cmd("search for \(query)")
        case .youtubeSearch: return query.isEmpty ? .say(note) : cmd("search youtube for \(query)")
        case .startFocus: return cmd(mins.isEmpty ? "focus" : "focus for \(mins)")
        case .startBreak: return cmd(mins.isEmpty ? "take a break" : "take a \(mins) break")
        case .startTimer: return cmd(mins.isEmpty ? "set a timer" : "set a timer for \(mins)")
        case .pauseTimer: return cmd("pause the timer")
        case .resumeTimer: return cmd("resume the timer")
        case .stopTimer: return cmd("stop the timer")
        case .timeLeft: return cmd("how much time left on the timer")
        case .calculate, .convertUnits: return query.isEmpty ? .say(note) : cmd(query)
        case .moveFiles, .copyFiles:
            guard !dest.isEmpty else { return .say("Where should I put \(hasFiles && items.isEmpty ? "them" : "it")?") }
            let verb = i.action == .moveFiles ? "move" : "copy"
            // With files dropped, "the pdf" or "that video" means those files, not a search by name.
            // With files dropped, "the pdf" or their own names mean those files; only a name that
            // isn't one of them is looked up on the Mac.
            let names = files.map { $0.lastPathComponent.lowercased() }
            let elsewhere = items.filter { item in
                let l = item.lowercased()
                return !isPronoun(l) && !names.contains { $0.contains(l) || l.contains($0) } && !(hasFiles && Self.generic.contains(l))
            }
            let what = hasFiles && elsewhere.isEmpty ? "this" : (elsewhere.isEmpty ? "this" : elsewhere.joined(separator: ", "))
            return cmd("\(verb) \(what) to \(dest)")
        case .undoMove: return cmd("undo")
        case .convertToJPG: return cmd("convert to jpg")
        case .convertToMP4: return cmd("convert to mp4")
        case .shrinkImages: return cmd("shrink them")
        case .combineIntoPDF: return cmd("combine into one pdf")
        case .copyTextForAI: return cmd("copy the text for ai")
        case .prepForCanvas: return cmd("prep for canvas")
        case .markDisposable: return cmd("mark these disposable")
        case .disposableStatus: return cmd("what's in disposable")
        case .keepFile: return items.isEmpty ? cmd("what's in disposable") : cmd("keep \(items[0])")
        case .tidyScreenshots: return cmd("tidy my screenshots")
        case .trashOldScreenshots: return cmd("trash old screenshots")
        case .screenshotsToFolder: return cmd("save screenshots to a folder")
        case .tidyDownloads: return cmd("tidy my downloads")
        case .diskUsage: return cmd("what's using my disk")
        case .emptyTrash: return cmd("empty the trash")
        case .findFiles: return query.isEmpty && items.isEmpty ? .say("What should I look for?") : cmd("find \(query.isEmpty ? list : query)")
        case .putAway: return cmd("put away")
        case .checkForUpdates: return cmd("check for updates")
        case .version: return cmd("what version are you")
        }
    }

    /// Words that describe a dropped file rather than name one ("the pdf", "that video").
    private static let generic: Set<String> = ["pdf", "the pdf", "that pdf", "file", "files", "video", "the video", "photo", "photos",
                                               "image", "images", "picture", "pictures", "document", "doc", "screenshot", "folder"]

    private static func isPronoun(_ s: String) -> Bool {
        ["this", "that", "it", "these", "those", "them", "the file", "the files", "this file", "these files"].contains(s.lowercased())
    }
}

#endif
