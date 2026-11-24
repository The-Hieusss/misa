import AppKit
import ApplicationServices

/// Arranging windows: halves, quarters, thirds, full, centered, or onto the other display.
///
///   "put Safari on the left", "snap this to the right half", "make Notes full screen",
///   "Safari on the left and Notes on the right", "move this window to the other screen"
///
/// "This window" is the app you were last using (not M.I.S.A.). macOS only lets apps move other
/// apps' windows with Accessibility permission.
enum Windows {
    enum Spot: String, CaseIterable {
        case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
        case leftThird, middleThird, rightThird, leftTwoThirds, rightTwoThirds
        case full, center, otherScreen

        var words: [String] {
            switch self {
            case .left: return ["left", "left half", "left side"]
            case .right: return ["right", "right half", "right side"]
            case .top: return ["top", "top half"]
            case .bottom: return ["bottom", "bottom half"]
            case .topLeft: return ["top left", "upper left", "top left corner", "top left quarter"]
            case .topRight: return ["top right", "upper right", "top right corner", "top right quarter"]
            case .bottomLeft: return ["bottom left", "lower left", "bottom left corner", "bottom left quarter"]
            case .bottomRight: return ["bottom right", "lower right", "bottom right corner", "bottom right quarter"]
            case .leftThird: return ["left third", "first third"]
            case .middleThird: return ["middle third", "center third", "centre third"]
            case .rightThird: return ["right third", "last third"]
            case .leftTwoThirds: return ["left two thirds"]
            case .rightTwoThirds: return ["right two thirds"]
            case .full: return ["full screen", "fullscreen", "whole screen", "entire screen", "maximized", "maximize", "fill the screen", "full", "big"]
            case .center: return ["center", "centre", "middle"]
            case .otherScreen: return ["other screen", "other display", "next screen", "next display", "second screen", "second display", "other monitor", "next monitor"]
            }
        }

        var label: String {
            switch self {
            case .full: return "full screen"
            case .center: return "the center"
            case .otherScreen: return "the other screen"
            case .topLeft: return "the top left"
            case .topRight: return "the top right"
            case .bottomLeft: return "the bottom left"
            case .bottomRight: return "the bottom right"
            case .leftThird: return "the left third"
            case .middleThird: return "the middle third"
            case .rightThird: return "the right third"
            case .leftTwoThirds: return "the left two thirds"
            case .rightTwoThirds: return "the right two thirds"
            default: return "the \(rawValue) half"
            }
        }
    }

    // MARK: Which app "this window" means

    private static var lastApp: NSRunningApplication?

    /// Remembers the app you were using before talking to her.
    static func startTracking() {
        lastApp = NSWorkspace.shared.frontmostApplication.flatMap { $0 == .current ? nil : $0 }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app != .current else { return }
            lastApp = app
        }
    }

    // MARK: Parsing

    struct Move { let app: String?; let spot: Spot }

    /// "put Safari on the left (half)", "snap this right", "make notes full screen", "maximize chrome",
    /// "move this to the other screen", "Safari left and Notes right". Nil if it isn't that.
    static func parse(_ t: String) -> [Move]? {
        let parts = t.components(separatedBy: " and ")
        var moves: [Move] = []
        for part in parts {
            guard let m = parseOne(part.trimmingCharacters(in: .whitespaces)) else { return nil }
            moves.append(m)
        }
        return moves.isEmpty ? nil : moves
    }

    private static let spotPhrases: [(String, Spot)] = Spot.allCases.flatMap { s in s.words.map { ($0, s) } }.sorted { $0.0.count > $1.0.count }

    private static func parseOne(_ t: String) -> Move? {
        var s = t
        // The verb (optional when an app name and a place are both given: "safari on the left")
        let verbs = ["put", "move", "snap", "send", "throw", "push", "place", "make", "set", "tile", "maximize", "maximise", "center", "centre", "resize"]
        var verb: String?
        for v in verbs where s.hasPrefix(v + " ") || s == v { verb = v; s = String(s.dropFirst(v.count)).trimmingCharacters(in: .whitespaces); break }
        // "maximize safari", "center this"
        if verb == "maximize" || verb == "maximise" { return Move(app: target(s), spot: .full) }
        if (verb == "center" || verb == "centre") && !s.contains(" on ") && !s.contains(" to ") { return Move(app: target(s), spot: .center) }
        // The place at the end: "... (to|on|onto) (the) <spot> (half|side|of the screen)"
        s = s.replacingOccurrences(of: #"\s+(?:of the screen|of my screen|of the display|please)$"#, with: "", options: .regularExpression)
        guard let (phrase, spot) = spotPhrases.first(where: { s == $0.0 || s.hasSuffix(" " + $0.0) }) else { return nil }
        var who = String(s.dropLast(phrase.count)).trimmingCharacters(in: .whitespaces)
        who = who.replacingOccurrences(of: #"\s*(?:to|on|onto|into|in|at)?\s*(?:the|my)?$"#, with: "", options: .regularExpression)
        // Without a verb, only "<app> on the left" counts (not "the left" alone, or other sentences).
        if verb == nil && (who.isEmpty || who.split(separator: " ").count > 3) { return nil }
        // "make it big" / "make safari full screen": only full screen goes with "make"
        if verb == "make" && spot != .full { return nil }
        return Move(app: target(who), spot: spot)
    }

    /// Nil means "the app you were using"; otherwise the app's name as said.
    private static func target(_ who: String) -> String? {
        let w = who.replacingOccurrences(of: #"^(?:the |my )"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*(?:window|windows|app|'s window)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return ["", "this", "it", "that", "this one", "current", "the current", "front", "the front"].contains(w) ? nil : w
    }

    // MARK: Moving

    static func run(_ moves: [Move]) -> Reply {
        guard trusted(prompt: true) else {
            return Reply(text: "To move windows I need Accessibility permission. Turn on M.I.S.A. in System Settings > Privacy & Security > Accessibility, then ask again. (After I update myself macOS may ask again.)")
        }
        var done: [String] = []
        var problems: [String] = []
        for m in moves {
            guard let app = resolve(m.app) else {
                problems.append(m.app.map { "\($0) isn't open" } ?? "I'm not sure which window you mean")
                continue
            }
            let name = app.localizedName ?? "that app"
            switch FileOps.onMain({ place(app, m.spot) }) {
            case .ok: done.append("\(name) → \(m.spot.label)")
            case .noWindow: problems.append("\(name) has no window I can move")
            case .noOtherScreen: problems.append("there's only one screen")
            }
        }
        FileOps.log("windows: \(done.joined(separator: ", "))\(problems.isEmpty ? "" : " (\(problems.joined(separator: "; ")))")")
        if done.isEmpty { return Reply(text: problems.first.map { $0.prefix(1).uppercased() + $0.dropFirst() + "." } ?? "Nothing to move.") }
        var text = done.count == 1 ? "Moved \(done[0].replacingOccurrences(of: " → ", with: " to ")). 🪟" : "Done: " + done.joined(separator: ", ") + ". 🪟"
        if !problems.isEmpty { text += " (" + problems.joined(separator: "; ") + ".)" }
        return Reply(text: text)
    }

    private static func resolve(_ name: String?) -> NSRunningApplication? {
        guard let name else { return lastApp.flatMap { $0.isTerminated ? nil : $0 } }
        let running = AppLauncher.running()
        guard let hit = AppLauncher.find(name, in: running.map(\.app)) else { return nil }
        return running.first { $0.app.url == hit.url }?.proc
    }

    static func trusted(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary)
    }

    private enum Result { case ok, noWindow, noOtherScreen }

    private static func place(_ app: NSRunningApplication, _ spot: Spot) -> Result {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        guard let win = window(of: ax) else { return .noWindow }
        let current = frame(of: win)
        // The screen the window is mostly on (AX uses top-left origin coordinates).
        let screens = NSScreen.screens
        guard let primary = screens.first else { return .noWindow }
        func axRect(_ r: NSRect) -> CGRect { CGRect(x: r.minX, y: primary.frame.maxY - r.maxY, width: r.width, height: r.height) }
        let here = screens.max { axRect($0.frame).intersection(current).area < axRect($1.frame).intersection(current).area } ?? primary
        var screen = here
        if spot == .otherScreen {
            guard screens.count > 1, let i = screens.firstIndex(of: here) else { return .noOtherScreen }
            screen = screens[(i + 1) % screens.count]
        }
        let v = axRect(screen.visibleFrame)
        let gap: CGFloat = 0
        var r: CGRect
        switch spot {
        case .left: r = CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height)
        case .right: r = CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height)
        case .top: r = CGRect(x: v.minX, y: v.minY, width: v.width, height: v.height / 2)
        case .bottom: r = CGRect(x: v.minX, y: v.midY, width: v.width, height: v.height / 2)
        case .topLeft: r = CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height / 2)
        case .topRight: r = CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height / 2)
        case .bottomLeft: r = CGRect(x: v.minX, y: v.midY, width: v.width / 2, height: v.height / 2)
        case .bottomRight: r = CGRect(x: v.midX, y: v.midY, width: v.width / 2, height: v.height / 2)
        case .leftThird: r = CGRect(x: v.minX, y: v.minY, width: v.width / 3, height: v.height)
        case .middleThird: r = CGRect(x: v.minX + v.width / 3, y: v.minY, width: v.width / 3, height: v.height)
        case .rightThird: r = CGRect(x: v.minX + v.width * 2 / 3, y: v.minY, width: v.width / 3, height: v.height)
        case .leftTwoThirds: r = CGRect(x: v.minX, y: v.minY, width: v.width * 2 / 3, height: v.height)
        case .rightTwoThirds: r = CGRect(x: v.minX + v.width / 3, y: v.minY, width: v.width * 2 / 3, height: v.height)
        case .full: r = v
        case .center:
            let w = min(current.width, v.width), h = min(current.height, v.height)
            r = CGRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h)
        case .otherScreen:
            // Same relative spot and size on the other display.
            let old = axRect(here.visibleFrame)
            let fx = (current.minX - old.minX) / old.width, fy = (current.minY - old.minY) / old.height
            let w = min(current.width, v.width), h = min(current.height, v.height)
            r = CGRect(x: v.minX + fx * v.width, y: v.minY + fy * v.height, width: w, height: h)
        }
        r = r.insetBy(dx: gap, dy: gap).integral
        // Some apps clamp sizes; set position, then size, then position again.
        set(win, position: r.origin)
        set(win, size: r.size)
        set(win, position: r.origin)
        app.activate()
        return .ok
    }

    private static func window(of app: AXUIElement) -> AXUIElement? {
        for attr in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attr as CFString, &v) == .success, let v { return (v as! AXUIElement) }
        }
        var list: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &list) == .success, let wins = list as? [AXUIElement] { return wins.first }
        return nil
    }

    private static func frame(of win: AXUIElement) -> CGRect {
        var p = CGPoint.zero, s = CGSize.zero
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &v) == .success, let v { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
        if AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &v) == .success, let v { AXValueGetValue(v as! AXValue, .cgSize, &s) }
        return CGRect(origin: p, size: s)
    }

    private static func set(_ win: AXUIElement, position: CGPoint) {
        var p = position
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
    }

    private static func set(_ win: AXUIElement, size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, v) }
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
