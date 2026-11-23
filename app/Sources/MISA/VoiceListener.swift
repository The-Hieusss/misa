import AVFoundation
import SoundAnalysis
import Speech

/// "Hey MISA": listens for her name and takes the request that follows. All on this Mac.
///
/// Like Siri's voice trigger, it works in stages so the costly parts only run when needed:
///  1. Apple's built-in sound classifier (SoundAnalysis) listens to the mic and only says whether
///     someone is talking. Silence, music and typing never go further.
///  2. While someone talks, on-device speech recognition transcribes it (with ~2 s of audio from
///     just before, so the start isn't lost) and looks for "Hey MISA" at the start of a phrase.
///  3. After her name, the rest of what's said, up to a pause, is the request. "Hey MISA" on its
///     own opens the chat and the next thing said within a few seconds is the request.
///
/// Off unless turned on (menu bar, or "start listening"). Paused while she's put away or hidden,
/// and while the screen is locked. macOS shows its orange mic dot whenever it's listening.
final class VoiceListener: NSObject, SNResultsObserving {
    static let shared = VoiceListener()

    enum Event {
        /// She heard her name; `text` is the request so far (may be empty).
        case awake(String)
        /// The finished request.
        case heard(String)
        /// Went back to waiting for her name without a request.
        case sleep
        /// Something she should say in the chat (no permission, no on-device speech...).
        case problem(String)
    }
    /// Called on the main thread.
    var onEvent: ((Event) -> Void)?

    var enabled: Bool { UserDefaults.standard.bool(forKey: "voiceListen") }
    private(set) var running = false
    private var paused: Set<String> = []

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "misa.voice")
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    // Everything below is only touched on `queue`.
    private var analyzer: SNAudioStreamAnalyzer?
    private var framePosition: AVAudioFramePosition = 0
    private var preroll: [AVAudioPCMBuffer] = []
    private var prerollFrames: AVAudioFrameCount = 0
    private var prerollLimit: AVAudioFrameCount = 96_000
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var segmentStart = Date()
    private var speaking = false
    private var quiet = 0
    private var awake = false
    private var awakeAt = Date()
    private var wakeEnd: String.Index?
    private var command = ""
    private var followUpUntil: Date?
    private var generation = 0 // ignores late results from a cancelled recognition

    private override init() {
        super.init()
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.pause("locked") }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.resume("locked") }
        // A new mic (AirPods connecting, etc.) changes the input format: start over with it.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.running else { return }
            self.stopEngine()
            self.startEngine()
        }
    }

    // MARK: On and off

    /// Turns listening on or off (remembered), asking for the mic and speech permissions first.
    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "voiceListen")
        FileOps.log("voice listening → \(on)")
        DispatchQueue.main.async { if on { self.startIfAllowed() } else { self.stopEngine() } }
    }

    /// At launch: picks up where it was left.
    func restore() { if enabled { startIfAllowed() } }

    func pause(_ reason: String) {
        paused.insert(reason)
        if running { stopEngine() }
    }

    func resume(_ reason: String) {
        paused.remove(reason)
        if enabled, paused.isEmpty, !running { startIfAllowed() }
    }

    private func startIfAllowed() {
        guard paused.isEmpty, !running else { return }
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            return tell(.problem("I can't listen for “Hey MISA” on this Mac: it needs on-device speech recognition for English, which this Mac doesn't have."))
        }
        AVCaptureDevice.requestAccess(for: .audio) { micOK in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    guard micOK else {
                        UserDefaults.standard.set(false, forKey: "voiceListen")
                        return self.tell(.problem("I need the microphone to hear “Hey MISA”. Allow it in System Settings > Privacy & Security > Microphone, then turn listening on again."))
                    }
                    guard status == .authorized else {
                        UserDefaults.standard.set(false, forKey: "voiceListen")
                        return self.tell(.problem("I need Speech Recognition to understand you. Allow it in System Settings > Privacy & Security > Speech Recognition, then turn listening on again."))
                    }
                    if self.enabled, self.paused.isEmpty { self.startEngine() }
                }
            }
        }
    }

    private func startEngine() {
        guard !running else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            return tell(.problem("I can't find a microphone to listen with."))
        }
        let analyzer = SNAudioStreamAnalyzer(format: format)
        do {
            let speech = try SNClassifySoundRequest(classifierIdentifier: .version1)
            speech.windowDuration = CMTime(seconds: 1, preferredTimescale: 1000)
            speech.overlapFactor = 0.5 // a result every half second
            try analyzer.add(speech, withObserver: self)
        } catch {
            return tell(.problem("I couldn't start listening (\(error.localizedDescription))."))
        }
        queue.sync {
            self.analyzer = analyzer
            self.framePosition = 0
            self.prerollLimit = AVAudioFrameCount(format.sampleRate * 2)
            self.resetSegment()
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let copy = buffer.copied() else { return }
            self.queue.async { self.feed(copy) }
        }
        do {
            engine.prepare()
            try engine.start()
            running = true
            FileOps.log("voice: listening (\(Int(format.sampleRate)) Hz)")
        } catch {
            input.removeTap(onBus: 0)
            tell(.problem("I couldn't use the microphone (\(error.localizedDescription))."))
        }
    }

    private func stopEngine() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        queue.async {
            self.analyzer?.removeAllRequests()
            self.analyzer = nil
            self.resetSegment()
            self.preroll = []
            self.prerollFrames = 0
        }
        FileOps.log("voice: stopped")
    }

    // MARK: Stage 1: is someone talking?

    private func feed(_ buffer: AVAudioPCMBuffer) {
        analyzer?.analyze(buffer, atAudioFramePosition: framePosition)
        framePosition += AVAudioFramePosition(buffer.frameLength)
        preroll.append(buffer)
        prerollFrames += buffer.frameLength
        while prerollFrames > prerollLimit, let first = preroll.first {
            prerollFrames -= first.frameLength
            preroll.removeFirst()
        }
        request?.append(buffer)
        guard request != nil else { return }
        if awake, Date().timeIntervalSince(awakeAt) > 12 {
            request?.endAudio() // a request has had long enough
        } else if !awake, Date().timeIntervalSince(segmentStart) > 10 {
            restartSegment() // long talk without her name: start fresh, keeping the last 2 s
        }
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let talking = (result.classification(forIdentifier: "speech")?.confidence ?? 0) > 0.5
        queue.async { self.speech(talking) }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        FileOps.log("voice: sound analysis failed: \(error)")
    }

    private func speech(_ talking: Bool) {
        if talking {
            quiet = 0
            if !speaking {
                speaking = true
                if request == nil { startSegment() }
            }
        } else if speaking {
            quiet += 1
            if quiet >= 2 { // about a second of quiet
                speaking = false
                segmentEnded()
            }
        }
    }

    // MARK: Stage 2 and 3: her name, then the request

    private func startSegment() {
        guard let recognizer else { return }
        generation += 1
        let gen = generation
        let r = SFSpeechAudioBufferRecognitionRequest()
        r.requiresOnDeviceRecognition = true
        r.shouldReportPartialResults = true
        r.contextualStrings = ["Misa", "Hey Misa", "M.I.S.A."]
        r.taskHint = .dictation
        preroll.forEach { r.append($0) }
        request = r
        segmentStart = Date()
        // Right after a lone "Hey MISA", whatever comes next is the request.
        if let until = followUpUntil, until > Date() {
            awake = true
            awakeAt = Date()
            followUpUntil = nil
        }
        task = recognizer.recognitionTask(with: r) { [weak self] result, error in
            guard let self else { return }
            self.queue.async {
                guard gen == self.generation else { return }
                if let result { self.transcribed(result.bestTranscription.formattedString, final: result.isFinal) }
                else if error != nil { self.finish() }
            }
        }
    }

    private func transcribed(_ text: String, final: Bool) {
        if !awake, let end = Self.wakeEnd(in: text) {
            awake = true
            awakeAt = Date()
            wakeEnd = end
            FileOps.log("voice: heard her name")
        }
        if awake {
            let start = wakeEnd.map { $0 <= text.endIndex ? $0 : text.endIndex } ?? text.startIndex
            let now = String(text[start...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?-").union(.whitespaces))
            if now != command || command.isEmpty {
                command = now
                tell(.awake(now))
            }
        }
        if final { finish() }
    }

    private func segmentEnded() {
        guard request != nil else { return }
        if awake {
            request?.endAudio() // the final result calls finish()
            let gen = generation
            queue.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                if self?.generation == gen, self?.request != nil { self?.finish() }
            }
        } else {
            resetSegment()
        }
    }

    private func finish() {
        guard request != nil else { return }
        let wasAwake = awake, said = command
        resetSegment()
        guard wasAwake else { return }
        if said.isEmpty {
            followUpUntil = Date().addingTimeInterval(6) // "Hey MISA" … "mute my mic"
            let gen = generation
            queue.asyncAfter(deadline: .now() + 6.5) { [weak self] in
                guard let self, self.generation == gen, self.followUpUntil != nil else { return }
                self.followUpUntil = nil
                self.tell(.sleep)
            }
        } else {
            FileOps.log("voice: request “\(said.prefix(80))”")
            tell(.heard(said))
        }
    }

    private func restartSegment() {
        resetSegment()
        if speaking { startSegment() }
    }

    private func resetSegment() {
        generation += 1
        task?.cancel()
        task = nil
        request = nil
        awake = false
        wakeEnd = nil
        command = ""
    }

    /// Where "Hey MISA" (as the recognizer tends to spell it) ends, if it starts a phrase.
    static func wakeEnd(in text: String) -> String.Index? {
        let pattern = #"(?i)(?:^|[.!?]\s+)(?:(?:hey|hi|okay|ok|yo|a)[\s,]+)?(?:misa|mesa|meesa|misha|missa|mi sa|miss a|m\.?\s?i\.?\s?s\.?\s?a\.?)(?=[\s,.!?]|$)[\s,.!?]*"#
        let needsGreeting = #"(?i)(?:hey|hi|okay|ok|yo)[\s,]+(?:misa|mesa|meesa|misha|missa|mi sa|miss a|m\.?\s?i\.?\s?s\.?\s?a\.?)(?=[\s,.!?]|$)[\s,.!?]*"#
        // "Hey MISA" anywhere, or just "MISA, …" at the very start.
        if let r = text.range(of: needsGreeting, options: .regularExpression) { return r.upperBound }
        if let r = text.range(of: pattern, options: .regularExpression), r.lowerBound == text.startIndex { return r.upperBound }
        if text.lowercased().hasPrefix("amisa") || text.lowercased().hasPrefix("amesa") {
            return text.index(text.startIndex, offsetBy: 5)
        }
        return nil
    }

    private func tell(_ e: Event) { DispatchQueue.main.async { self.onEvent?(e) } }

    // MARK: Chat commands

    /// "start listening", "stop listening", "turn on hey misa", "are you listening". Nil if not about that.
    static func route(_ t: String) -> Reply? {
        let about = t.contains("listening") || t.contains("hey misa") || t.contains("voice activation") || t.contains("wake word") || t.contains("voice control")
        guard about, !t.contains("music"), !t.contains("song"), !t.contains("podcast") else { return nil }
        let w = " \(t) "
        let off = [" stop ", " off ", " disable ", " quit ", " don't ", " dont ", " no more "].contains { w.contains($0) }
        let on = [" start ", " on ", " enable ", " listen for ", " turn on ", " begin "].contains { w.contains($0) } || t == "listen for hey misa"
        let me = VoiceListener.shared
        if off {
            me.setEnabled(false)
            return Reply(text: "Okay, I've stopped listening. The mic is off. (Turn it back on with “start listening” or from my menu bar menu.)")
        }
        if on {
            me.setEnabled(true)
            return Reply(text: "Listening for “Hey MISA”. 👂 Say “Hey MISA” and then what you need, like “Hey MISA, mute my mic”. macOS shows its orange mic dot while I listen. It all stays on this Mac.")
        }
        if t.contains("are you listening") || t.contains("listening status") {
            if !me.enabled { return Reply(text: "No, I'm not listening. Say “start listening” to turn on “Hey MISA”.") }
            return Reply(text: me.running ? "Yes, I'm listening for “Hey MISA”." : "“Hey MISA” is on, but paused right now (I'm put away, hidden or the screen is locked).")
        }
        return nil
    }
}

private extension AVAudioPCMBuffer {
    /// A copy that stays valid after the tap returns.
    func copied() -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
        out.frameLength = frameLength
        let channels = Int(format.channelCount)
        if let src = floatChannelData, let dst = out.floatChannelData {
            for c in 0..<(format.isInterleaved ? 1 : channels) {
                memcpy(dst[c], src[c], Int(frameLength) * MemoryLayout<Float>.size * (format.isInterleaved ? channels : 1))
            }
        } else if let src = int16ChannelData, let dst = out.int16ChannelData {
            for c in 0..<(format.isInterleaved ? 1 : channels) {
                memcpy(dst[c], src[c], Int(frameLength) * MemoryLayout<Int16>.size * (format.isInterleaved ? channels : 1))
            }
        } else {
            return nil
        }
        return out
    }
}
