import AppKit
import CoreAudio
import IOBluetooth

/// Control Center from the chat: volume, mute, the microphone, screen brightness, which speaker
/// or mic is used, Bluetooth devices, and Do Not Disturb.
///
///   "volume 40", "turn it up", "mute", "mute my mic", "brightness 70", "dim the screen",
///   "switch output to AirPods", "use the MacBook mic", "connect to Home Speaker",
///   "disconnect my headphones", "turn on do not disturb"
enum SystemControls {
    /// `t` is the normalized request (lowercase, no punctuation).
    static func route(_ t: String, raw: String) -> (() -> Reply)? {
        let w = " \(t) "
        func has(_ words: String...) -> Bool { words.contains { w.contains(" \($0) ") } }
        let number = Self.number(in: t)
        let up = has("up", "louder", "raise", "increase", "higher", "brighter", "more")
        let down = has("down", "quieter", "softer", "lower", "decrease", "less", "dimmer", "darker")
        let off = has("off", "disable", "stop", "end")
        let on = has("on", "enable", "start") && !off

        // Do Not Disturb (not "focus for 25 min", which is the timer)
        if has("do not disturb", "dnd", "focus mode", "don't disturb", "dont disturb") || t.hasPrefix("silence notification") {
            return { Focus.set(!off && !has("turn off", "disable") ) }
        }

        // Microphone (input volume)
        if (has("mic", "microphone", "mics", "microphones") && !has("switch", "use", "change", "set", "select")) || (has("input") && has("mute", "unmute")) {
            if has("unmute") || (on && !has("mute")) { return { Volume.setInput(UserDefaults.standard.object(forKey: "micBefore") as? Int ?? 75) } }
            if has("mute") || off { return { Volume.setInput(0) } }
            if let n = number { return { Volume.setInput(n) } }
        }

        // Sound output and input devices
        if has("audio devices", "sound devices", "speakers", "outputs", "inputs") && has("what", "list", "show", "which") {
            return { AudioDevices.list() }
        }
        if let name = AudioDevices.target(in: t) { return { AudioDevices.switchTo(name.name, input: name.input) } }

        // Bluetooth
        if has("bluetooth") && has("devices", "list", "what", "show", "paired") { return { Bluetooth.list() } }
        if has("bluetooth") && (on || off) && Bluetooth.command(t) == nil {
            return { Bluetooth.power(on: !off) }
        }
        if let (connect, name) = Bluetooth.command(t) { return { connect ? Bluetooth.connect(name) : Bluetooth.disconnect(name) } }

        // Volume
        let aboutSound = has("volume", "sound", "audio", "louder", "quieter", "softer")
        if t == "mute" || t == "unmute" || (has("mute", "unmute") && (aboutSound || has("mac", "computer", "it", "everything"))) {
            return { Volume.mute(!has("unmute")) }
        }
        if aboutSound || t == "turn it up" || t == "turn it down" {
            if has("max", "full", "maximum", "all the way up") { return { Volume.set(100) } }
            if let n = number, (!up && !down) || has("to", "at") { return { Volume.set(n) } }
            if up || down { return { Volume.step(up ? 1 : -1, by: number) } }
            if has("what", "what's", "whats", "how loud", "level") { return { Volume.status() } }
        }

        // Brightness
        if has("brightness", "brighter", "dimmer", "dim", "screen brightness") || (has("screen") && (up || down)) {
            if has("max", "full", "maximum") { return { Brightness.set(100) } }
            if let n = number, (!up && !down) || has("to", "at") { return { Brightness.set(n) } }
            if up || has("brighter") { return { Brightness.step(1, by: number) } }
            if down || has("dim", "dimmer", "darker") { return { Brightness.step(-1, by: number) } }
            return { Brightness.status() }
        }
        return nil
    }

    /// "40", "40 percent", "to 40%": a whole number 0-100.
    static func number(in t: String) -> Int? {
        guard let m = t.range(of: "\\b(100|[0-9]{1,2})\\b", options: .regularExpression) else { return nil }
        return Int(t[m])
    }

    /// Ranks names against what was asked for: exact, then contained, then sharing words.
    static func best<T>(_ query: String, _ items: [T], name: (T) -> String) -> [T] {
        let clean = { (s: String) in s.lowercased().replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression) }
        let filler: Set<String> = ["my", "the", "to", "a", "on", "bluetooth", "device", "speaker", "speakers", "headphones"]
        let all = clean(query).split(separator: " ").map(String.init)
        let kept = all.filter { !filler.contains($0) }
        let q = kept.isEmpty ? all : kept
        let qs = q.joined(separator: " ")
        guard !qs.isEmpty else { return [] }
        let scored = items.map { item -> (T, Int) in
            let n = clean(name(item))
            let squash = { (s: String) in s.replacingOccurrences(of: " ", with: "") }
            var score = 0
            if squash(n) == squash(qs) { score = 4 }
            else if squash(n).contains(squash(qs)) { score = 3 }
            else if q.allSatisfy({ n.contains($0) }) { score = 2 }
            else if q.contains(where: { $0.count >= 3 && n.contains($0) }) { score = 1 }
            return (item, score)
        }
        guard let top = scored.map(\.1).max(), top > 0 else { return [] }
        return scored.filter { $0.1 == top }.map(\.0)
    }

    static func osascript(_ script: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Volume

enum Volume {
    static var level: Int { Int(SystemControls.osascript("output volume of (get volume settings)") ?? "") ?? 0 }
    static var muted: Bool { SystemControls.osascript("output muted of (get volume settings)") == "true" }

    static func set(_ n: Int) -> Reply {
        let v = max(0, min(100, n))
        _ = SystemControls.osascript("set volume output volume \(v)" + (v > 0 ? " without output muted" : ""))
        FileOps.log("volume → \(v)")
        return Reply(text: v == 0 ? "Volume at 0. 🔇" : "Volume at \(v)%. 🔊", suggestions: [.init(label: "Louder", prompt: "Volume up"), .init(label: "Quieter", prompt: "Volume down")])
    }

    static func step(_ dir: Int, by amount: Int?) -> Reply { set(level + dir * (amount ?? 12)) }

    static func mute(_ on: Bool) -> Reply {
        _ = SystemControls.osascript(on ? "set volume with output muted" : "set volume without output muted")
        FileOps.log("mute → \(on)")
        return Reply(text: on ? "Muted. 🔇" : "Sound's back on, at \(level)%. 🔊", suggestions: [.init(label: on ? "Unmute" : "Mute", prompt: on ? "Unmute" : "Mute")])
    }

    static func status() -> Reply { Reply(text: muted ? "You're muted (volume \(level)%)." : "Volume is at \(level)%.") }

    /// Microphone level: 0 mutes it.
    static func setInput(_ n: Int) -> Reply {
        let v = max(0, min(100, n))
        // Remember the level before muting, so unmuting puts it back.
        if v == 0, let now = Int(SystemControls.osascript("input volume of (get volume settings)") ?? ""), now > 0 {
            UserDefaults.standard.set(now, forKey: "micBefore")
        }
        _ = SystemControls.osascript("set volume input volume \(v)")
        FileOps.log("mic → \(v)")
        return Reply(text: v == 0 ? "Microphone muted. 🎙️🚫" : "Microphone on, at \(v)%. 🎙️", suggestions: [.init(label: v == 0 ? "Unmute mic" : "Mute mic", prompt: v == 0 ? "Unmute my mic" : "Mute my mic")])
    }
}

// MARK: - Brightness

/// The built-in display's brightness, through macOS's own DisplayServices (what the brightness
/// keys use; it has no public API). External monitors don't support it.
enum Brightness {
    private typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (UInt32, Float) -> Int32
    private static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFn = lib.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
    private static let setFn = lib.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }

    /// The built-in screen if there is one, else the main screen.
    private static var display: UInt32 {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(8, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    static var level: Int? {
        var b: Float = 0
        guard let getFn, getFn(display, &b) == 0 else { return nil }
        return Int((b * 100).rounded())
    }

    static func set(_ n: Int) -> Reply {
        let v = max(0, min(100, n))
        guard let setFn, setFn(display, Float(v) / 100) == 0 else {
            return Reply(text: "I can't change the brightness on this screen (it works on a Mac's built-in display).")
        }
        FileOps.log("brightness → \(v)")
        return Reply(text: "Brightness at \(v)%. ☀️", suggestions: [.init(label: "Brighter", prompt: "Brighter"), .init(label: "Dimmer", prompt: "Dim the screen")])
    }

    static func step(_ dir: Int, by amount: Int?) -> Reply {
        guard let now = level else { return set(dir > 0 ? 100 : 0) }
        return set(now + dir * (amount ?? 12))
    }

    static func status() -> Reply {
        guard let l = level else { return Reply(text: "I can't read this screen's brightness.") }
        return Reply(text: "Brightness is at \(l)%.")
    }
}

// MARK: - Sound devices

enum AudioDevices {
    struct Device { let id: AudioObjectID; let name: String; let output: Bool; let input: Bool }

    private static func address(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func all() -> [Device] {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size)
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids)
        return ids.compactMap { id in
            var na = address(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var ns = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &na, 0, nil, &ns, &name) == noErr, let n = name?.takeRetainedValue() as String? else { return nil }
            func streams(_ scope: AudioObjectPropertyScope) -> Bool {
                var sa = address(kAudioDevicePropertyStreams, scope)
                var s: UInt32 = 0
                return AudioObjectGetPropertyDataSize(id, &sa, 0, nil, &s) == noErr && s > 0
            }
            return Device(id: id, name: n, output: streams(kAudioObjectPropertyScopeOutput), input: streams(kAudioObjectPropertyScopeInput))
        }
    }

    static func current(input: Bool) -> AudioObjectID {
        var a = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return id
    }

    /// "switch output to AirPods", "play sound through the speakers", "use the MacBook mic",
    /// "set input to Yeti". Nil if it isn't that.
    static func target(in t: String) -> (name: String, input: Bool)? {
        let patterns: [(String, Bool?)] = [
            ("^(?:switch|change|set) (?:the )?(?:sound|audio|output|speaker|speakers|sound output|audio output)(?: device)? to (.+)$", false),
            ("^(?:switch|change|set) (?:the )?(?:input|mic|microphone|sound input|audio input)(?: device)? to (.+)$", true),
            ("^(?:play|send|route) (?:the )?(?:sound|audio|music) (?:through|on|out of|from|to) (?:the |my )?(.+)$", false),
            ("^(?:output|sound|audio) (?:to|through|on) (?:the |my )?(.+)$", false),
            ("^use (?:the |my )?(.+?) (?:for|as) (?:the )?(?:sound|audio|output|speakers?)$", false),
            ("^use (?:the |my )?(.+?) (?:for|as) (?:the )?(?:input|mic|microphone)$", true),
            ("^use (?:the |my )?(.+? (?:mic|microphone))$", true),
            ("^use (?:the |my )?(.+? (?:speakers?|headphones|airpods|earbuds))$", false),
            ("^(?:switch|change) to (?:the |my )?(.+? (?:speakers?|headphones|airpods|earbuds|mic|microphone))$", nil),
        ]
        for (p, input) in patterns {
            guard let r = t.range(of: p, options: .regularExpression), let m = try? NSRegularExpression(pattern: p).firstMatch(in: t, range: NSRange(r, in: t)),
                  let nr = Range(m.range(at: 1), in: t) else { continue }
            let name = String(t[nr]).trimmingCharacters(in: .whitespaces)
            let isInput = input ?? (name.hasSuffix("mic") || name.hasSuffix("microphone"))
            return (name, isInput)
        }
        return nil
    }

    static func switchTo(_ query: String, input: Bool) -> Reply {
        let kind = input ? "input" : "output"
        let q = query.replacingOccurrences(of: "\\b(mic|microphone|speakers?)$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let options = all().filter { input ? $0.input : $0.output }
        let hits = SystemControls.best(q.isEmpty ? query : q, options) { $0.name }
        guard let d = hits.first else {
            // Maybe it's a Bluetooth device that isn't connected yet.
            if let bt = Bluetooth.paired().first(where: { SystemControls.best(query, [$0]) { $0.name ?? "" }.count == 1 }) {
                return Reply(text: "\(bt.name ?? query) isn't connected. Want me to connect it?", suggestions: [.init(label: "Connect it", prompt: "Connect to \(bt.name ?? query)")])
            }
            return Reply(text: "I don't see a sound \(kind) called “\(query)”. You have: \(options.map(\.name).joined(separator: ", ")).",
                         suggestions: options.prefix(3).map { .init(label: $0.name, prompt: "Switch \(kind) to \($0.name)") })
        }
        if hits.count > 1 {
            return Reply(text: "Which one?", suggestions: hits.prefix(4).map { .init(label: $0.name, prompt: "Switch \(kind) to \($0.name)") })
        }
        var id = d.id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var a = AudioObjectPropertyAddress(mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(sys, &a, 0, nil, size, &id)
        if !input {
            // Alerts and sound effects follow too.
            a.mSelector = kAudioHardwarePropertyDefaultSystemOutputDevice
            AudioObjectSetPropertyData(sys, &a, 0, nil, size, &id)
        }
        guard status == noErr else { return Reply(text: "macOS wouldn't switch the sound \(kind) to \(d.name).") }
        FileOps.log("audio \(kind) → \(d.name)")
        return Reply(text: input ? "Using \(d.name) as the microphone. 🎙️" : "Sound now plays through \(d.name). 🔊")
    }

    static func list() -> Reply {
        let devices = all()
        let out = current(input: false), inp = current(input: true)
        let outs = devices.filter(\.output).map { $0.id == out ? "\($0.name) (in use)" : $0.name }
        let ins = devices.filter(\.input).map { $0.id == inp ? "\($0.name) (in use)" : $0.name }
        return Reply(text: "Speakers: \(outs.joined(separator: ", ")).\nMicrophones: \(ins.joined(separator: ", ")).",
                     suggestions: devices.filter { $0.output && $0.id != out }.prefix(3).map { .init(label: $0.name, prompt: "Switch output to \($0.name)") })
    }
}

// MARK: - Bluetooth

enum Bluetooth {
    static func paired() -> [IOBluetoothDevice] {
        FileOps.onMain { (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] }
    }

    /// "connect to Home Speaker", "connect my airpods", "disconnect from the JBL". Nil if it isn't that.
    static func command(_ t: String) -> (connect: Bool, name: String)? {
        guard let m = t.range(of: "^(dis)?connect (?:to |from |with )?(?:my |the )?(.+?)(?: (?:via|over|with|using) bluetooth)?$", options: .regularExpression) else {
            return nil
        }
        let s = String(t[m])
        let connect = !s.hasPrefix("dis")
        var name = s.replacingOccurrences(of: "^(dis)?connect (?:to |from |with )?(?:my |the )?", with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: " (?:via|over|with|using) bluetooth$", with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: "^bluetooth (?:to |device )?", with: "", options: .regularExpression)
        guard !name.isEmpty, !["it", "wifi", "wi fi", "the internet", "internet", "vpn"].contains(name) else { return nil }
        return (connect, name)
    }

    /// A paired device named in the request, if any.
    static func named(in t: String) -> IOBluetoothDevice? { SystemControls.best(t, paired()) { $0.name ?? "" }.first }

    static func connect(_ query: String) -> Reply {
        let devices = paired()
        guard !devices.isEmpty else {
            return Reply(text: "I don't see any paired Bluetooth devices. Pair it once in System Settings > Bluetooth, then I can connect it any time. (If macOS asked whether I may use Bluetooth, I need that too.)")
        }
        let hits = SystemControls.best(query, devices) { $0.name ?? "" }
        guard let d = hits.first else {
            return Reply(text: "I don't have a paired Bluetooth device called “\(query)”. If it's an AirPlay speaker (like a HomePod), macOS only lets you pick it from Control Center > Sound.",
                         suggestions: devices.prefix(4).map { .init(label: $0.name ?? "?", prompt: "Connect to \($0.name ?? "")") })
        }
        if hits.count > 1 { return Reply(text: "Which one?", suggestions: hits.prefix(4).map { .init(label: $0.name ?? "?", prompt: "Connect to \($0.name ?? "")") }) }
        let name = d.name ?? query
        if FileOps.onMain({ d.isConnected() }) { return Reply(text: "\(name) is already connected. 🎧") }
        guard FileOps.onMain({ IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON }) else {
            return Reply(text: "Bluetooth is off.", suggestions: [.init(label: "Turn Bluetooth on", prompt: "Turn Bluetooth on")])
        }
        let result = Waiter.connect(d)
        FileOps.log("bluetooth connect \(name) → \(result)")
        guard result == kIOReturnSuccess else {
            return Reply(text: "I couldn't reach \(name). Is it on and nearby?", suggestions: [.init(label: "Try again", prompt: "Connect to \(name)")])
        }
        return Reply(text: "Connected to \(name). 🎧", suggestions: [.init(label: "Play sound on it", prompt: "Switch output to \(name)")])
    }

    static func disconnect(_ query: String) -> Reply {
        let connected = paired().filter { FileOps.onMain($0.isConnected) }
        let hits = SystemControls.best(query, connected) { $0.name ?? "" }
        guard let d = hits.first else {
            return Reply(text: connected.isEmpty ? "No Bluetooth devices are connected." : "“\(query)” isn't connected. Connected now: \(connected.compactMap(\.name).joined(separator: ", ")).")
        }
        let name = d.name ?? query
        _ = FileOps.onMain { d.closeConnection() }
        FileOps.log("bluetooth disconnect \(name)")
        return Reply(text: "Disconnected \(name).")
    }

    static func list() -> Reply {
        let devices = paired()
        guard !devices.isEmpty else { return Reply(text: "No paired Bluetooth devices (or macOS hasn't let me use Bluetooth yet).") }
        let lines = devices.map { d in "\(d.name ?? "?")\(FileOps.onMain(d.isConnected) ? " (connected)" : "")" }
        return Reply(text: "Paired: \(lines.joined(separator: ", ")).",
                     suggestions: devices.filter { !FileOps.onMain($0.isConnected) }.prefix(3).map { .init(label: "Connect \($0.name ?? "")", prompt: "Connect to \($0.name ?? "")") })
    }

    // Bluetooth on/off has no public API; these are what Control Center itself uses.
    private typealias SetPower = @convention(c) (Int32) -> Void
    private static let setPower: SetPower? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOBluetoothPreferenceSetControllerPowerState").map { unsafeBitCast($0, to: SetPower.self) }

    static func power(on: Bool) -> Reply {
        guard let setPower else { return Reply(text: "I can't switch Bluetooth on this Mac. Use Control Center > Bluetooth.") }
        if !on {
            return Reply(text: "Turn Bluetooth off?", confirm: .init(
                title: "Turn Bluetooth off?",
                items: ["A Bluetooth keyboard, mouse or trackpad stops working until it's back on"],
                button: "Turn off", danger: true,
                run: { FileOps.onMain { setPower(0) }; FileOps.log("bluetooth power off"); return Reply(text: "Bluetooth is off.") }))
        }
        FileOps.onMain { setPower(1) }
        FileOps.log("bluetooth power on")
        return Reply(text: "Bluetooth is on. 📶")
    }
}

/// Connects without blocking the main thread (her animations keep running while it tries):
/// starts the connection there, then waits here for macOS to report back.
private final class Waiter: NSObject {
    private let done = DispatchSemaphore(value: 0)
    private var status = kIOReturnTimeout

    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        self.status = status
        done.signal()
    }

    static func connect(_ d: IOBluetoothDevice) -> IOReturn {
        let w = Waiter()
        let started = FileOps.onMain { d.openConnection(w) }
        guard started == kIOReturnSuccess else { return started }
        _ = w.done.wait(timeout: .now() + 20)
        return w.status
    }
}

// MARK: - Do Not Disturb

/// macOS has no API for Focus, so she uses two tiny Shortcuts ("MISA Do Not Disturb On" / "Off").
/// The first time, she builds them and asks Shortcuts to add them (one click each).
enum Focus {
    static let names = (on: "MISA Do Not Disturb On", off: "MISA Do Not Disturb Off")

    private static func shortcuts(_ args: [String]) -> (ok: Bool, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return (false, "") }
        p.waitUntilExit()
        return (p.terminationStatus == 0, String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
    }

    static func set(_ on: Bool) -> Reply {
        let name = on ? names.on : names.off
        let installed = shortcuts(["list"]).out.split(separator: "\n").map(String.init)
        guard installed.contains(name) else { return setup(then: on) }
        let r = shortcuts(["run", name])
        FileOps.log("do not disturb → \(on) (\(r.ok ? "ok" : r.out))")
        guard r.ok else { return Reply(text: "The “\(name)” shortcut didn't run. Open it in Shortcuts to check it.") }
        return Reply(text: on ? "Do Not Disturb is on. 🌙" : "Do Not Disturb is off. 🔔",
                     suggestions: [.init(label: on ? "Turn it off" : "Turn it on", prompt: on ? "Turn off do not disturb" : "Turn on do not disturb")])
    }

    private static func setup(then on: Bool) -> Reply {
        Reply(text: "macOS doesn't let apps switch Focus directly, so I use two small Shortcuts for it. I can make them now.",
              confirm: .init(title: "Add two shortcuts?", items: [names.on, names.off, "Shortcuts asks you to add each one"],
                             button: "Make them", danger: false, run: { install(then: on) }))
    }

    private static func install(then on: Bool) -> Reply {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MISA", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var made: [URL] = []
        for (name, enabled) in [(names.on, true), (names.off, false)] {
            let workflow: [String: Any] = [
                "WFWorkflowClientVersion": "2607.0.1", "WFWorkflowMinimumClientVersion": 900, "WFWorkflowMinimumClientVersionString": "900",
                "WFWorkflowIcon": ["WFWorkflowIconStartColor": 1440408063, "WFWorkflowIconGlyphNumber": 59782],
                "WFWorkflowTypes": [String](), "WFWorkflowInputContentItemClasses": [String](), "WFWorkflowImportQuestions": [String](),
                "WFWorkflowOutputContentItemClasses": [String](),
                "WFWorkflowActions": [[
                    "WFWorkflowActionIdentifier": "is.workflow.actions.dnd.set",
                    "WFWorkflowActionParameters": [
                        "Enabled": enabled ? 1 : 0,
                        "FocusModes": ["Identifier": "com.apple.donotdisturb.mode.default", "DisplayString": "Do Not Disturb"],
                    ],
                ]],
            ]
            let raw = dir.appendingPathComponent("\(name) unsigned.shortcut")
            let signed = dir.appendingPathComponent("\(name).shortcut")
            guard let data = try? PropertyListSerialization.data(fromPropertyList: workflow, format: .binary, options: 0), (try? data.write(to: raw)) != nil else { continue }
            try? FileManager.default.removeItem(at: signed)
            let r = shortcuts(["sign", "--mode", "anyone", "--input", raw.path, "--output", signed.path])
            try? FileManager.default.removeItem(at: raw)
            if r.ok { made.append(signed) } else { FileOps.log("shortcut sign failed: \(r.out)") }
        }
        guard made.count == 2 else {
            return Reply(text: """
            I couldn't make the shortcuts here (signing them needs the internet). You can make them in the Shortcuts app instead: \
            a new shortcut with the “Set Focus” action, Do Not Disturb, On, named “\(names.on)”, and another set to Off named “\(names.off)”.
            """)
        }
        for u in made { FileOps.onMain { _ = NSWorkspace.shared.open(u) } }
        FileOps.log("do not disturb shortcuts offered to Shortcuts")
        return Reply(text: "Shortcuts is asking you to add them: click “Add Shortcut” on each. Then ask me again.",
                     suggestions: [.init(label: on ? "Turn on Do Not Disturb" : "Turn off Do Not Disturb", prompt: on ? "Turn on do not disturb" : "Turn off do not disturb")])
    }
}
