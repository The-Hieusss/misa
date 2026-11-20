import AppKit

/// A focus or break timer. Swift owns the clock (so it survives the web view reloading);
/// the web view only draws the ring around her halo. Use on the main thread.
final class FocusTimer {
    enum State: String { case idle, running, paused, done }

    private(set) var state = State.idle
    private(set) var label = "Focus"
    private(set) var total: TimeInterval = 0
    private var endsAt = Date()
    private var pausedRemaining: TimeInterval = 0
    private var timer: Timer?

    /// Called whenever the state changes, so the halo can update.
    var onChange: (() -> Void)?
    /// Called when time is up, with the label ("Focus" or "Break").
    var onFinish: ((String) -> Void)?

    var remaining: TimeInterval {
        switch state {
        case .running: return max(0, endsAt.timeIntervalSinceNow)
        case .paused: return pausedRemaining
        default: return 0
        }
    }

    func start(_ seconds: TimeInterval, label: String) {
        self.label = label
        total = seconds
        endsAt = Date().addingTimeInterval(seconds)
        state = .running
        schedule()
        onChange?()
    }

    func pause() {
        guard state == .running else { return }
        pausedRemaining = remaining
        timer?.invalidate()
        state = .paused
        onChange?()
    }

    func resume() {
        guard state == .paused else { return }
        endsAt = Date().addingTimeInterval(pausedRemaining)
        state = .running
        schedule()
        onChange?()
    }

    func stop() {
        timer?.invalidate()
        state = .idle
        onChange?()
    }

    /// The user has seen the "time's up" state; go back to idle.
    func acknowledge() {
        guard state == .done else { return }
        state = .idle
        onChange?()
    }

    private func schedule() {
        timer?.invalidate()
        let t = Timer(fire: endsAt, interval: 0, repeats: false) { [weak self] _ in self?.finish() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func finish() {
        state = .done
        NSSound(named: "Glass")?.play()
        FileOps.log("timer: \(label) finished (\(Self.describe(total)))")
        onChange?()
        onFinish?(label)
    }

    var json: [String: Any] {
        [
            "type": "timer",
            "state": state.rawValue,
            "label": label,
            "total": total,
            "remaining": remaining,
            "endsAt": endsAt.timeIntervalSince1970 * 1000,
        ]
    }

    /// 1500 → "25 min", 5400 → "1 h 30 min", 45 → "45 sec"
    static func describe(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) h") }
        if m > 0 { parts.append("\(m) min") }
        if sec > 0 && h == 0 { parts.append("\(sec) sec") }
        return parts.isEmpty ? "0 sec" : parts.joined(separator: " ")
    }

    /// Reads "25 minutes", "1h 30m", "half an hour", "90 sec". Nil if there's no duration.
    static func parseDuration(_ text: String) -> TimeInterval? {
        let t = text.lowercased()
        if t.contains("half an hour") || t.contains("half hour") { return 1800 }
        var total: TimeInterval = 0
        let re = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b"#)
        for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
            guard let n = Range(m.range(at: 1), in: t).flatMap({ Double(t[$0]) }),
                  let u = Range(m.range(at: 2), in: t).map({ String(t[$0]) }) else { continue }
            total += n * (u.hasPrefix("h") ? 3600 : u.hasPrefix("m") ? 60 : 1)
        }
        if total == 0, t.range(of: #"\ban hour\b"#, options: .regularExpression) != nil { return 3600 }
        return total > 0 ? min(total, 12 * 3600) : nil
    }
}
