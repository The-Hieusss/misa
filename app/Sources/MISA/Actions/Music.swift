import AppKit

/// Music: Spotify or Apple Music (whichever is playing, or open), and the media keys for
/// anything else (YouTube in a browser, podcasts...).
///
///   "pause", "play music", "next song", "previous song", "what's playing",
///   "play my study playlist", "play lofi on spotify", "shuffle on"
enum Music {
    enum Player: String, CaseIterable {
        case spotify = "Spotify", music = "Music"
        var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
        var display: String { self == .spotify ? "Spotify" : "Apple Music" }
        var running: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
        var installed: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }
        /// "playing", "paused" or "stopped" (only asks a player that's already open).
        var state: String? { running ? SystemControls.osascript("tell application \"\(rawValue)\" to player state as string") : nil }
    }

    /// The player to talk to: the one playing, else one that's open.
    static var active: Player? {
        Player.allCases.first { $0.state == "playing" } ?? Player.allCases.first { $0.running }
    }

    /// For "play X": the open player, else Spotify if it's installed, else Apple Music.
    static var preferred: Player { active ?? (Player.spotify.installed ? .spotify : .music) }

    static var playing: Bool { Player.allCases.contains { $0.state == "playing" } }

    // MARK: Routing

    static func route(_ t: String, raw: String) -> (() -> Reply)? {
        let w = " \(t) "
        func has(_ s: String...) -> Bool { s.contains { w.contains(" \($0) ") } }
        let aboutMusic = has("music", "song", "songs", "track", "spotify", "apple music", "playlist", "album", "playback", "tune", "tunes")
        guard !has("youtube", "video", "timer", "focus", "break", "pomodoro") else { return nil }

        if has("what's playing", "whats playing", "what song", "what's this song", "whats this song", "now playing", "who sings", "what is playing", "song is this") {
            return { nowPlaying() }
        }
        if ["next", "skip", "next song", "next track", "skip this", "skip song", "skip this song", "skip it"].contains(t) || (has("next", "skip") && aboutMusic) {
            return { command(.next) }
        }
        if ["previous", "previous song", "previous track", "last song", "go back a song", "back a song", "replay that"].contains(t) || (has("previous", "last song", "go back") && aboutMusic) {
            return { command(.previous) }
        }
        if has("shuffle") { return { shuffle(!has("off", "stop", "disable")) } }
        // "pause" alone pauses music only while something is playing (otherwise it's the timer's).
        if (t == "pause" || t == "stop") && playing || (has("pause", "stop") && aboutMusic) {
            return { command(.pause) }
        }
        if ["resume", "unpause", "play", "keep playing", "continue playing", "resume music", "play music", "play some music", "play my music"].contains(t)
            || (has("resume", "unpause") && aboutMusic) {
            return { command(.play) }
        }
        // "play my study playlist", "play lofi on spotify", "play Taylor Swift in apple music"
        if t.hasPrefix("play ") || t.hasPrefix("put on ") {
            var what = String(raw.trimmingCharacters(in: .whitespaces).dropFirst(t.hasPrefix("play ") ? 5 : 7))
            var player: Player?
            for (suffix, p) in [(" on spotify", Player.spotify), (" in spotify", .spotify), (" on apple music", .music), (" in apple music", .music), (" in music", .music), (" on music", .music)]
            where what.lowercased().hasSuffix(suffix) {
                what = String(what.dropLast(suffix.count)); player = p
            }
            let explicit = player != nil || aboutMusic
            guard explicit || active != nil else { return nil }
            what = what.replacingOccurrences(of: #"^(?:me |some |my )"#, with: "", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: #"\s+(?:playlist|album|music|songs)$"#, with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespaces)
            let chosen = player ?? preferred
            return { play(what, on: chosen) }
        }
        return nil
    }

    // MARK: Actions

    enum Command { case play, pause, next, previous }

    static func command(_ c: Command) -> Reply {
        guard let p = active ?? (c == .play ? preferred : nil) else {
            // Nothing open: the media keys reach whatever was playing last (a browser tab, Podcasts...).
            if MediaKeys.send(c) { return Reply(text: c == .pause ? "Paused. ⏸" : c == .play ? "Playing. ▶️" : c == .next ? "Skipped. ⏭" : "Back one. ⏮") }
            return Reply(text: "Spotify and Apple Music aren't open. Say “play music” to start one.")
        }
        let verb: String
        switch c {
        case .play: verb = "play"
        case .pause: verb = "pause"
        case .next: verb = "next track"
        case .previous: verb = p == .spotify ? "previous track" : "back track"
        }
        if c == .play && !p.running { NSWorkspace.shared.openApplication(at: NSWorkspace.shared.urlForApplication(withBundleIdentifier: p.bundleID)!, configuration: .init()) }
        guard SystemControls.osascript("tell application \"\(p.rawValue)\" to \(verb)") != nil else { return blocked(p) }
        FileOps.log("music: \(verb) (\(p.display))")
        switch c {
        case .pause: return Reply(text: "Paused \(p.display). ⏸", suggestions: [.init(label: "Resume", prompt: "Resume the music")])
        case .play:
            Thread.sleep(forTimeInterval: 0.4)
            return Reply(text: "Playing\(trackLine(p).map { ": \($0)" } ?? "") ▶️", suggestions: [.init(label: "Next song", prompt: "Next song"), .init(label: "Pause", prompt: "Pause the music")])
        case .next, .previous:
            Thread.sleep(forTimeInterval: 0.5)
            return Reply(text: "\(c == .next ? "⏭" : "⏮") \(trackLine(p) ?? "Done.")", suggestions: [.init(label: "Next song", prompt: "Next song"), .init(label: "Pause", prompt: "Pause the music")])
        }
    }

    static func nowPlaying() -> Reply {
        guard let p = active, let line = trackLine(p) else { return Reply(text: "Nothing's playing in Spotify or Apple Music right now.") }
        return Reply(text: "\(p.state == "playing" ? "Now playing" : "Paused on"): \(line) (\(p.display))", suggestions: [.init(label: "Next song", prompt: "Next song")])
    }

    /// "Song by Artist"
    private static func trackLine(_ p: Player) -> String? {
        guard let name = SystemControls.osascript("tell application \"\(p.rawValue)\" to name of current track"), !name.isEmpty,
              let artist = SystemControls.osascript("tell application \"\(p.rawValue)\" to artist of current track") else { return nil }
        return artist.isEmpty ? name : "\(name) by \(artist)"
    }

    static func shuffle(_ on: Bool) -> Reply {
        guard let p = active else { return Reply(text: "Spotify and Apple Music aren't open.") }
        let script = p == .spotify ? "tell application \"Spotify\" to set shuffling to \(on)" : "tell application \"Music\" to set shuffle enabled to \(on)"
        guard SystemControls.osascript(script) != nil else { return blocked(p) }
        return Reply(text: "Shuffle \(on ? "on 🔀" : "off").")
    }

    static func play(_ what: String, on p: Player) -> Reply {
        guard !what.isEmpty else { return command(.play) }
        let q = what.replacingOccurrences(of: "\"", with: "")
        if p == .music {
            // A playlist by name, else the first song or artist match in your library.
            let script = """
            tell application "Music"
              set hits to (every user playlist whose name contains "\(q)")
              if (count of hits) > 0 then
                play item 1 of hits
                return "playlist:" & name of item 1 of hits
              end if
              set songs to (every track of library playlist 1 whose name contains "\(q)" or artist contains "\(q)" or album contains "\(q)")
              if (count of songs) > 0 then
                play item 1 of songs
                return "track:" & name of item 1 of songs & " by " & artist of item 1 of songs
              end if
              return "none"
            end tell
            """
            guard let r = SystemControls.osascript(script) else { return blocked(p) }
            if r == "none" { return Reply(text: "I couldn't find “\(what)” in your Apple Music library.") }
            FileOps.log("music: play \(r)")
            return Reply(text: r.hasPrefix("playlist:") ? "Playing your “\(r.dropFirst(9))” playlist. ▶️" : "Playing \(r.dropFirst(6)). ▶️",
                         suggestions: [.init(label: "Shuffle on", prompt: "Shuffle on"), .init(label: "Pause", prompt: "Pause the music")])
        }
        // Spotify can't search from a script, so open the search: one click on the top result plays it.
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? q
        if let url = URL(string: "spotify:search:\(enc)") { NSWorkspace.shared.open(url) }
        FileOps.log("music: spotify search \(q)")
        return Reply(text: "Opened Spotify's search for “\(what)”. Click the top result to play it. (Spotify doesn't let other apps pick songs.)")
    }

    private static func blocked(_ p: Player) -> Reply {
        Reply(text: "macOS stopped me from controlling \(p.display). Allow it in System Settings > Privacy & Security > Automation > M.I.S.A. (\(p.display)).")
    }
}

/// The keyboard's play/pause and skip keys, for players other than Spotify and Apple Music.
/// macOS only lets apps press keys with Accessibility permission.
enum MediaKeys {
    static func send(_ c: Music.Command) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let key: Int32 = c == .next ? 17 : c == .previous ? 18 : 16 // NX_KEYTYPE_NEXT / PREVIOUS / PLAY
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key << 16) | ((down ? 0xa : 0xb) << 8))
            guard let e = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                             windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1) else { return false }
            e.cgEvent?.post(tap: .cghidEventTap)
        }
        return true
    }
}
