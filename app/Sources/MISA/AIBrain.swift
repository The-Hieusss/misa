import Foundation
#if canImport(FoundationModels) && !MISA_NO_AI
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
        #if canImport(FoundationModels) && !MISA_NO_AI
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
        #if canImport(FoundationModels) && !MISA_NO_AI
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
        #if canImport(FoundationModels) && !MISA_NO_AI
        if #available(macOS 26.0, *), available { return await Engine.shared.interpret(text, files: files, timer: timer) }
        #endif
        return .failed
    }
}

#if canImport(FoundationModels) && !MISA_NO_AI

// The schema is written out by hand (DynamicGenerationSchema) instead of with the @Generable and
// @Guide macros: those need a compiler plugin that only ships with Xcode, and she must build with
// just the Command Line Tools too.

enum IntentAction: String, CaseIterable {
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
    case setVolume, volumeUp, volumeDown, mute, unmute, muteMic, unmuteMic
    case setBrightness, brightnessUp, brightnessDown
    case switchSoundOutput, switchMicrophone, listSoundDevices
    case connectBluetooth, disconnectBluetooth, bluetoothOn, bluetoothOff
    case doNotDisturbOn, doNotDisturbOff
    case createEvent, createReminder, showAgenda, nextEvent, showReminders, completeReminder
    case rescheduleItem, deleteItem, findItem
    case playMusic, pauseMusic, resumeMusic, nextSong, previousSong, nowPlaying
    case arrangeWindow
}

struct Intent {
    var action: IntentAction
    var items: [String]
    var query: String
    var minutes: Int
    var level: Int
    var destination: String
    var reply: String

    /// The shape the model has to fill in, in this order (it picks the action first).
    @available(macOS 26.0, *)
    static let schema: GenerationSchema = {
        typealias P = DynamicGenerationSchema.Property
        let text = DynamicGenerationSchema(type: String.self)
        let root = DynamicGenerationSchema(name: "Intent", properties: [
            P(name: "action", description: "The one action that matches the request",
              schema: DynamicGenerationSchema(name: "IntentAction", anyOf: IntentAction.allCases.map(\.rawValue))),
            P(name: "items", description: "Every app, website, or file name the request mentions, one per entry, exactly as written. Empty if none.",
              schema: DynamicGenerationSchema(arrayOf: text)),
            P(name: "query", description: "Search words (for findFiles: the name plus any type, folder or time words); the full math expression or unit conversion with every number, like '3 cups in ml'; for createEvent or createReminder the thing plus its day and time exactly as said, like 'dentist friday at 3pm'; for rescheduleItem the thing, 'to', and the new day or time, like 'dentist to monday at 10'; for deleteItem or findItem the thing's name; for playMusic the song, artist or playlist. Empty if none.",
              schema: text),
            P(name: "minutes", description: "Minutes for a focus session, break or timer. 0 if not said.",
              schema: DynamicGenerationSchema(type: Int.self)),
            P(name: "level", description: "Percent 0-100 for setVolume or setBrightness, or how much to change it for up/down. -1 if not said.",
              schema: DynamicGenerationSchema(type: Int.self)),
            P(name: "destination", description: "Destination folder for moving or copying files, like Desktop or Documents; or for arrangeWindow where the window goes: left, right, top, bottom, top left, full screen, center, other screen. Empty if none.",
              schema: text),
            P(name: "reply", description: "For chat: your answer, one or two short sentences. Otherwise a few words, never claiming it's done.",
              schema: text),
        ])
        return try! GenerationSchema(root: root, dependencies: [])
    }()

    @available(macOS 26.0, *)
    init(_ c: GeneratedContent) throws {
        let raw = try c.value(String.self, forProperty: "action")
        action = IntentAction(rawValue: raw) ?? .chat
        items = (try? c.value([String].self, forProperty: "items")) ?? []
        query = (try? c.value(String.self, forProperty: "query")) ?? ""
        minutes = (try? c.value(Int.self, forProperty: "minutes")) ?? 0
        level = (try? c.value(Int.self, forProperty: "level")) ?? -1
        destination = (try? c.value(String.self, forProperty: "destination")) ?? ""
        reply = (try? c.value(String.self, forProperty: "reply")) ?? ""
    }
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
    "it's way too loud" -> volumeDown
    "I can barely hear anything" -> volumeUp
    "half volume" -> setVolume, level 50
    "it's too dark, I can't see my screen" -> brightnessUp
    "I'm on a call, kill my mic" -> muteMic
    "play it on my AirPods" -> switchSoundOutput, items ["AirPods"]
    "hook up my home speaker" -> connectBluetooth, items ["Home Speaker"]
    "no notifications for a while" -> doNotDisturbOn
    "don't let me forget to call mom at 6" -> createReminder, query "call mom at 6"
    "I have a dentist appointment friday at 3" -> createEvent, query "dentist appointment friday at 3"
    "am I busy tomorrow" -> showAgenda, query "tomorrow"
    "what do I still have to do" -> showReminders
    "I submitted the essay" -> completeReminder, query "essay"
    "the dentist can't do friday, make it monday at 10" -> rescheduleItem, query "dentist to monday at 10"
    "scrap tomorrow's study session" -> deleteItem, query "tomorrow's study session"
    "when am I seeing the dentist" -> findItem, query "dentist"
    "put on some lofi" -> playMusic, query "lofi"
    "skip this one" -> nextSong
    "shove chrome to the right side" -> arrangeWindow, items ["Chrome"], destination "right"
    "make this window take up the whole screen" -> arrangeWindow, destination "full screen"
    """

    /// A fresh session for every request, so an earlier request can't leak into the next one
    /// ("put Chrome on the right" coming back for "make this full screen"). The next one is
    /// warmed up in the background so it's ready.
    private func current() -> LanguageModelSession {
        lock.lock()
        let s = session ?? LanguageModelSession(instructions: Self.instructions)
        session = nil
        lastUse = Date()
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            let next = LanguageModelSession(instructions: Self.instructions)
            next.prewarm()
            self.lock.lock()
            if self.session == nil { self.session = next }
            self.lock.unlock()
        }
        return s
    }

    private func reset() {
        lock.lock(); session = nil; lock.unlock()
    }

    func prewarm() {
        lock.lock()
        if session == nil { session = LanguageModelSession(instructions: Self.instructions) }
        let s = session!
        lock.unlock()
        s.prewarm()
    }

    func interpret(_ text: String, files: [URL], timer: String) async -> AIBrain.Outcome {
        var context: [String] = []
        if !files.isEmpty { context.append("Files the user dropped on you: \(files.map(\.lastPathComponent).prefix(8).joined(separator: ", ")).") }
        if !timer.isEmpty { context.append("Timer: \(timer).") }
        let prompt = (context + ["Request: \(text)"]).joined(separator: "\n")

        do {
            let started = Date()
            let intent = try await respond(prompt)
            FileOps.log("ai: “\(text.prefix(80))” → \(intent.action.rawValue) items=\(intent.items) q=\(intent.query) min=\(intent.minutes) lvl=\(intent.level) dest=\(intent.destination) (\(String(format: "%.1f", Date().timeIntervalSince(started)))s)")
            return Self.outcome(Self.grounded(Self.safeLevels(intent, text: text), text: text), files: files)
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
            return try Intent(await current().respond(to: prompt, schema: Intent.schema, options: options).content)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // The conversation got too long: start over and try once more.
            reset()
            return try Intent(await current().respond(to: prompt, schema: Intent.schema, options: options).content)
        }
    }

    /// The model sometimes turns "it's too loud" into "volume 100" or "volume down 100". A level
    /// only stands when the request gives one (a number, half, all the way...); otherwise it's a
    /// normal step in the direction asked.
    /// The model sometimes copies an app or a place from its examples ("Chrome", "right").
    /// For window moves, keep only what the request actually says.
    private static func grounded(_ i: Intent, text: String) -> Intent {
        guard i.action == .arrangeWindow else { return i }
        let t = text.lowercased()
        var out = i
        out.items = i.items.filter { t.contains($0.lowercased()) }
        if out.destination.isEmpty || !t.contains(out.destination.lowercased().replacingOccurrences(of: "the ", with: "")) {
            let places: [(String, [String])] = [
                ("full screen", ["whole screen", "full screen", "fullscreen", "entire screen", "maximize", "maximise", "bigger", "fill"]),
                ("other screen", ["other screen", "other display", "other monitor", "second screen", "next screen"]),
                ("top left", ["top left", "upper left"]), ("top right", ["top right", "upper right"]),
                ("bottom left", ["bottom left", "lower left"]), ("bottom right", ["bottom right", "lower right"]),
                ("left", ["left"]), ("right", ["right"]), ("top", ["top"]), ("bottom", ["bottom"]), ("center", ["center", "centre", "middle"]),
            ]
            out.destination = places.first { $0.1.contains(where: t.contains) }?.0 ?? "full screen"
        }
        return out
    }

    private static func safeLevels(_ i: Intent, text: String) -> Intent {
        let volume: Set<IntentAction> = [.setVolume, .volumeUp, .volumeDown]
        let bright: Set<IntentAction> = [.setBrightness, .brightnessUp, .brightnessDown]
        guard volume.contains(i.action) || bright.contains(i.action) else { return i }
        let t = text.lowercased()
        let isVolume = volume.contains(i.action)
        var out = i
        if t.range(of: "[0-9]", options: .regularExpression) != nil { return i }
        let says = { (words: [String]) in words.contains { t.contains($0) } }
        let downward = says(["down", "lower", "less", "dim", "darker", "quieter", "softer", "too loud", "too bright", "blinding", "blasting"])
        if says(["half"]) { out.action = isVolume ? .setVolume : .setBrightness; out.level = 50; return out }
        if says(["max", "full", "all the way", "maximum", "highest", "lowest", "minimum", "zero", "silent"]) {
            out.action = isVolume ? .setVolume : .setBrightness
            out.level = says(["lowest", "minimum", "zero", "silent"]) || (says(["all the way"]) && downward) ? 0 : 100
            return out
        }
        out.level = -1
        if i.action == .setVolume || i.action == .setBrightness {
            let lower = downward && !says(["too quiet", "too dim", "too dark", "can't hear", "cant hear", "barely"])
            out.action = isVolume ? (lower ? .volumeDown : .volumeUp) : (lower ? .brightnessDown : .brightnessUp)
        }
        return out
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
        case .setVolume: return i.level >= 0 ? cmd("set volume to \(min(100, i.level))") : cmd("what's the volume")
        case .volumeUp: return cmd(i.level > 0 ? "volume up \(min(100, i.level))" : "volume up")
        case .volumeDown: return cmd(i.level > 0 ? "volume down \(min(100, i.level))" : "volume down")
        case .mute: return cmd("mute")
        case .unmute: return cmd("unmute")
        case .muteMic: return cmd("mute my mic")
        case .unmuteMic: return cmd("unmute my mic")
        case .setBrightness: return i.level >= 0 ? cmd("set brightness to \(min(100, i.level))") : cmd("brightness")
        case .brightnessUp: return cmd(i.level > 0 ? "brightness up \(min(100, i.level))" : "brightness up")
        case .brightnessDown: return cmd(i.level > 0 ? "brightness down \(min(100, i.level))" : "brightness down")
        case .switchSoundOutput: return items.isEmpty ? cmd("list sound devices") : cmd("switch output to \(items[0])")
        case .switchMicrophone: return items.isEmpty ? cmd("list sound devices") : cmd("switch input to \(items[0])")
        case .listSoundDevices: return cmd("list sound devices")
        case .connectBluetooth: return items.isEmpty ? cmd("list bluetooth devices") : cmd("connect to \(items[0])")
        case .disconnectBluetooth: return items.isEmpty ? cmd("list bluetooth devices") : cmd("disconnect \(items[0])")
        case .bluetoothOn: return cmd("turn bluetooth on")
        case .bluetoothOff: return cmd("turn bluetooth off")
        case .doNotDisturbOn: return cmd("turn on do not disturb")
        case .doNotDisturbOff: return cmd("turn off do not disturb")
        case .createEvent: return query.isEmpty ? .say("What's the event, and when?") : cmd("add \(query) to my calendar")
        case .createReminder: return query.isEmpty && items.isEmpty ? .say("What should I remind you about?") : cmd("remind me to \(query.isEmpty ? list : query)")
        case .showAgenda: return cmd("what's on my calendar \(query.isEmpty ? "today" : query)")
        case .nextEvent: return cmd("what's next")
        case .rescheduleItem: return query.isEmpty ? .say("What should I move, and to when?") : cmd(query.lowercased().hasPrefix("move ") ? query : "reschedule \(query)")
        case .deleteItem: return query.isEmpty && items.isEmpty ? .say("What should I delete?") : cmd("delete \(query.isEmpty ? items[0] : query)")
        case .findItem: return query.isEmpty && items.isEmpty ? cmd("what's on my calendar this week") : cmd("when is \(query.isEmpty ? items[0] : query)")
        case .showReminders: return cmd("what are my reminders")
        case .completeReminder: return query.isEmpty && items.isEmpty ? cmd("what are my reminders") : cmd("mark \(query.isEmpty ? items[0] : query) done")
        case .playMusic: return query.isEmpty ? cmd("play music") : cmd("play \(query) on \(Music.preferred == .spotify ? "spotify" : "apple music")")
        case .pauseMusic: return cmd("pause the music")
        case .resumeMusic: return cmd("resume the music")
        case .nextSong: return cmd("next song")
        case .previousSong: return cmd("previous song")
        case .nowPlaying: return cmd("what's playing")
        case .arrangeWindow:
            let place = dest.isEmpty ? (query.isEmpty ? "full screen" : query) : dest
            return cmd("put \(items.first ?? "this window") on the \(place.lowercased().replacingOccurrences(of: "the ", with: ""))")
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
