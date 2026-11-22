import AppKit
import WebKit

/// Owns M.I.S.A.'s window: where she sits, opening/closing the chat,
/// dragging, and the message channel to the web view.
final class MisaController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private let panel: MisaPanel
    private let webView: DropWebView
    private let timer = FocusTimer()
    private lazy var brain = Brain(timer: timer)

    private var mode: Mode = .collapsed
    private var openLayout: Geometry.OpenLayout?
    private var haloOrigin: CGPoint {
        didSet { save(haloOrigin) }
    }

    private var drag: (mouse: CGPoint, origin: CGPoint)?
    private var lastMouseDown: (mouse: CGPoint, origin: CGPoint)?
    private var mouseMonitor: Any?

    private enum Mode { case collapsed, open, docked }

    /// The menu bar slot she docks into (screen coordinates; minY = bottom edge of the menu bar).
    var statusSlot: (() -> NSRect?)?
    /// Tells the menu bar item to make room for the camera (true) or show its icon (false).
    var onDockedChange: ((Bool) -> Void)?
    /// Right-click on the camera shows the menu bar item's menu.
    var onShowMenu: (() -> Void)?

    private var cameraCenter = CGPoint.zero // screen coordinates
    private var dockSlot = NSRect.zero
    private var pendingDock = false
    private var openAfterUndock = false
    private var pointerTimer: Timer?
    private var lastPointer: CGPoint?
    private var ticks = 0
    /// Collapsed: the parts of the window that take clicks (her arms, in web coordinates). The
    /// halo circle always does; everything else clicks through to what's behind her.
    private var hotRects: [CGRect] = []

    var isVisible: Bool { panel.isVisible }
    var isDocked: Bool { mode == .docked }

    override init() {
        haloOrigin = Geometry.ensureOnScreen(Self.loadOrigin() ?? Geometry.defaultHaloOrigin())
        panel = MisaPanel(frame: Geometry.collapsedFrame(haloOrigin: haloOrigin))

        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        // Must be set before the web view is created: WebKit copies the configuration.
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: BundleSchemeHandler.scheme)
        let content = WKUserContentController()
        config.userContentController = content
        webView = DropWebView(frame: .zero, configuration: config)
        super.init()

        content.add(WeakHandler(self), name: "misa")

        webView.setValue(false, forKey: "drawsBackground") // see-through
        webView.underPageBackgroundColor = .clear
        webView.autoresizingMask = [.width, .height]
        webView.frame = panel.contentView!.bounds
        panel.contentView!.addSubview(webView)
        panel.contentView!.wantsLayer = true
        panel.contentView!.layer?.backgroundColor = .clear

        webView.navigationDelegate = self
        webView.onHover = { [weak self] on in self?.send(["type": "dragHover", "on": on]) }
        webView.onDrop = { [weak self] urls in self?.filesDropped(urls) }
        webView.load(URLRequest(url: Self.startURL))
        watchMouseForDragging()

        brain.onDock = { [weak self] in self?.dock() }
        startPointerFeed()

        timer.onChange = { [weak self] in self?.sendTimer() }
        timer.onFinish = { [weak self] label in
            guard let self else { return }
            self.send(self.brain.timerFinished(label).json)
        }
        // Update notices and failures show up in the chat like any reply (with the unread dot).
        Updater.announce = { [weak self] reply in self?.send(reply.json) }
        Updater.startDailyCheck()
    }

    /// The web view may only show M.I.S.A.'s own page. Anything else is cancelled,
    /// never handed to macOS (which would pop an "open with" dialog).
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        let own = url.scheme == BundleSchemeHandler.scheme || url.absoluteString.hasPrefix(Self.startURL.absoluteString)
        decisionHandler(own ? .allow : .cancel)
    }

    /// Developer hook: logs what the page is showing.
    func inspect() {
        let js = """
        (() => { const b = document.querySelector('button[aria-label]');
          const r = b ? b.getBoundingClientRect() : null;
          return JSON.stringify({ root: document.getElementById('root')?.children.length ?? -1,
            halo: r && [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)],
            panel: !!document.querySelector('[role=dialog]'), fonts: document.fonts.status,
            size: [innerWidth, innerHeight], color: getComputedStyle(document.documentElement).getPropertyValue('--color-ember'), iris: document.querySelector('radialGradient[id$="-iris"] stop:nth-child(3)')?.getAttribute('stop-color'), iris2: document.querySelector('radialGradient[id$="-iris2"] stop:nth-child(3)')?.getAttribute('stop-color') }); })()
        """
        webView.evaluateJavaScript(js) { result, error in
            FileOps.log("inspect: \(result ?? "nil") \(error.map { "\($0)" } ?? "")")
        }
    }

    /// `MISA_DEV_URL=http://localhost:5173` loads the Vite dev server instead of the bundled files.
    private static var startURL: URL {
        if let dev = ProcessInfo.processInfo.environment["MISA_DEV_URL"], let url = URL(string: dev) { return url }
        return URL(string: "\(BundleSchemeHandler.scheme)://app/index.html")!
    }

    // MARK: Showing, hiding, opening

    func show() { panel.orderFrontRegardless() }

    func hide() {
        if mode == .open { setCollapsed() }
        panel.orderOut(nil)
    }

    func toggleChat() {
        if !panel.isVisible { show() }
        if mode == .docked { return undock(openChat: true) }
        send(["type": "toggle"])
    }

    /// Opens the chat if it isn't open (never closes it).
    func openChat() {
        if !panel.isVisible { show() }
        if mode == .docked { return undock(openChat: true) }
        if mode != .open { send(["type": "toggle"]) }
    }

    func resetPosition() {
        haloOrigin = Geometry.defaultHaloOrigin()
        switch mode {
        case .open: setOpen()
        case .collapsed: setCollapsed()
        case .docked: break // she comes back here next time
        }
    }

    // MARK: Docking into the menu bar

    /// Teleports her out, then hangs her from the menu bar as a camera.
    func dock() {
        guard mode != .docked, !pendingDock else { return }
        if !panel.isVisible { show() }
        pendingDock = true
        send(["type": "teleportOut"])
        // If the page doesn't answer (e.g. still loading), dock anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.pendingDock == true { self?.enterDocked() }
        }
    }

    /// Retracts the camera and teleports her back to where she was.
    func undock(openChat: Bool = false) {
        guard mode == .docked else { return }
        openAfterUndock = openChat
        send(["type": "retract"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.mode == .docked { self?.finishUndock() }
        }
    }

    private func enterDocked() {
        pendingDock = false
        mode = .docked
        openLayout = nil
        UserDefaults.standard.set(true, forKey: "docked")
        onDockedChange?(true)
        // Let the menu bar make room for the slot before measuring it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.placeCamera(announce: true) }
    }

    private func placeCamera(announce: Bool) {
        guard mode == .docked else { return }
        guard let slot = statusSlot?(), slot.width > 0 else {
            // No menu bar slot to hang from: stay on screen instead.
            UserDefaults.standard.set(false, forKey: "docked")
            onDockedChange?(false)
            panel.level = .floating
            panel.ignoresMouseEvents = false
            return setCollapsed()
        }
        dockSlot = slot
        cameraCenter = CGPoint(x: slot.midX, y: slot.minY)
        let size = Geometry.cameraWindow, c = Geometry.cameraInWindow
        let frame = NSRect(x: cameraCenter.x - c.x, y: cameraCenter.y + c.y - size.height, width: size.width, height: size.height)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2) // above the menu bar
        panel.setFrame(frame, display: true)
        clipToCircle(false)
        panel.ignoresMouseEvents = true // the pointer feed turns clicks on only over the camera
        panel.resignKey()
        panel.orderFrontRegardless()
        if announce {
            send(["type": "layout", "mode": "docked", "camera": ["x": c.x, "y": c.y],
                  "halo": ["x": 0, "y": 0], "right": true, "bottom": false])
        }
    }

    private func finishUndock() {
        guard mode == .docked else { return }
        UserDefaults.standard.set(false, forKey: "docked")
        panel.level = .floating
        panel.ignoresMouseEvents = false
        onDockedChange?(false)
        setCollapsed() // the page replays her teleport-in
        if openAfterUndock {
            openAfterUndock = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                if self?.mode == .collapsed { self?.setOpen() }
            }
        }
    }

    // MARK: Pointer feed

    /// Sends the mouse position to the page ~24×/s so her eye follows your cursor anywhere on screen.
    /// While docked it also makes only the camera clickable; everything else clicks through.
    private func startPointerFeed() {
        let t = Timer(timeInterval: 1.0 / 24, repeats: true) { [weak self] _ in self?.feedPointer() }
        RunLoop.main.add(t, forMode: .common)
        pointerTimer = t
    }

    private func feedPointer() {
        guard panel.isVisible else { return }
        let m = NSEvent.mouseLocation
        if mode == .collapsed || mode == .open, drag == nil {
            // Take clicks over her; let them through elsewhere. While a button is held (a file
            // being dragged in, say) only ever start taking them, so a drop can still land.
            if overHer(m) {
                if panel.ignoresMouseEvents { panel.ignoresMouseEvents = false }
            } else if NSEvent.pressedMouseButtons == 0, !panel.ignoresMouseEvents {
                panel.ignoresMouseEvents = true
            }
        }
        if mode == .docked {
            let over = hypot(m.x - cameraCenter.x, m.y - cameraCenter.y) <= Geometry.camera / 2 + 3
            if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
            // Follow the slot if other menu bar items shift it.
            ticks += 1
            if ticks % 48 == 0, let slot = statusSlot?(), slot != dockSlot { placeCamera(announce: false) }
        }
        if let last = lastPointer, abs(last.x - m.x) < 0.5, abs(last.y - m.y) < 0.5 { return }
        lastPointer = m
        // Inside a clickable window the page already gets real mouse events.
        guard panel.ignoresMouseEvents || !panel.frame.contains(m) else { return }
        let x = m.x - panel.frame.minX, y = panel.frame.maxY - m.y
        webView.evaluateJavaScript("window.misa && window.misa.pointer && window.misa.pointer(\(x), \(y))")
    }

    private func setOpen() {
        guard mode != .docked else { return undock(openChat: true) }
        let layout = Geometry.openLayout(haloOrigin: haloOrigin)
        openLayout = layout
        mode = .open
        panel.ignoresMouseEvents = false
        panel.setFrame(layout.frame, display: true)
        clipToCircle(false)
        haloOrigin = Geometry.haloOrigin(openFrame: layout.frame, haloInWindow: layout.haloInWindow)
        let room = Geometry.armRoom(haloOrigin: haloOrigin)
        panel.makeKeyAndOrderFront(nil) // so typing goes to the chat
        send([
            "type": "layout", "mode": "open",
            "halo": ["x": layout.haloInWindow.x, "y": layout.haloInWindow.y],
            "right": layout.right, "bottom": layout.bottom,
            "arms": ["left": room.left, "right": room.right],
        ])
    }

    private func setCollapsed() {
        mode = .collapsed
        openLayout = nil
        panel.setFrame(Geometry.collapsedFrame(haloOrigin: haloOrigin), display: true)
        clipToCircle(false)
        panel.resignKey()
        sendCollapsedLayout()
    }

    /// Tells the page where the halo sits and which sides have screen room for an arm.
    private func sendCollapsedLayout() {
        let h = Geometry.haloInCollapsed, room = Geometry.armRoom(haloOrigin: haloOrigin)
        send(["type": "layout", "mode": "collapsed", "halo": ["x": h.x, "y": h.y], "right": true, "bottom": true,
              "arms": ["left": room.left, "right": room.right]])
    }

    /// Is the mouse over something of hers: the halo, an arm, or (open) the chat panel?
    private func overHer(_ m: CGPoint) -> Bool {
        let f = panel.frame, r = Geometry.halo / 2
        let h = mode == .open ? (openLayout?.haloInWindow ?? .zero) : Geometry.haloInCollapsed
        // The chat rect was measured when it opened; follow the window if she's been dragged since.
        if mode == .open, let l = openLayout,
           l.chat.offsetBy(dx: f.minX - l.frame.minX, dy: f.minY - l.frame.minY).contains(m) { return true }
        let cx = f.minX + h.x + r, cy = f.maxY - h.y - r
        if hypot(m.x - cx, m.y - cy) <= r - 6 { return true }
        let p = CGPoint(x: m.x - f.minX, y: f.maxY - m.y)
        return hotRects.contains { $0.contains(p) }
    }

    /// Files dropped on her: open the chat if needed, then offer what she can do with them.
    private func filesDropped(_ urls: [URL]) {
        if mode == .collapsed { setOpen() }
        brain.filesDropped(urls) { [weak self] in self?.send($0.json) }
    }

    /// While collapsed, the window itself is a circle, so nothing square can ever show around her.
    private func clipToCircle(_ on: Bool) {
        guard let layer = panel.contentView?.layer else { return }
        layer.cornerRadius = on ? Geometry.halo / 2 : 0
        layer.masksToBounds = on
        panel.invalidateShadow()
    }

    // MARK: Dragging

    /// The web view says when a drag starts; AppKit mouse events move the window,
    /// so dragging keeps working even when the cursor leaves the window.
    private func watchMouseForDragging() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            let mouse = NSEvent.mouseLocation
            switch event.type {
            case .leftMouseDown:
                self.lastMouseDown = (mouse, self.panel.frame.origin)
            case .leftMouseDragged:
                if let d = self.drag {
                    self.panel.setFrameOrigin(CGPoint(x: d.origin.x + mouse.x - d.mouse.x, y: d.origin.y + mouse.y - d.mouse.y))
                }
            case .leftMouseUp:
                if self.drag != nil { self.finishDrag() }
            default: break
            }
            return event
        }
    }

    private func finishDrag() {
        drag = nil
        switch mode {
        case .collapsed:
            // Dragged up into the menu bar? Put her away there.
            let visible = (panel.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            let o = CGPoint(x: panel.frame.minX + Geometry.armSide, y: panel.frame.minY + Geometry.armBottom)
            if o.y + Geometry.halo > visible.maxY + 6 {
                haloOrigin = CGPoint(x: o.x, y: visible.maxY - Geometry.halo - 12) // come back just below the menu bar
                dock()
            } else {
                haloOrigin = o
                sendCollapsedLayout() // screen room for her arms may have changed
            }
        case .open:
            if let layout = openLayout {
                haloOrigin = Geometry.haloOrigin(openFrame: panel.frame, haloInWindow: layout.haloInWindow)
            }
        case .docked:
            break
        }
    }

    // MARK: Messages from the web view

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            // Her saved outfit first, so she appears in it (the web side checks the values).
            if let skin = UserDefaults.standard.dictionary(forKey: "skin") as? [String: String] {
                send(["type": "skin", "skin": skin])
            }
            if UserDefaults.standard.bool(forKey: "docked") || mode == .docked {
                mode = .collapsed
                enterDocked()
            } else if mode == .open { setOpen() } else { setCollapsed() }
            sendTimer()
            // Just restarted after an update: say what's new.
            if let hello = Updater.greeting() { send(hello.json) }
        case "skin":
            // Saved from the wardrobe panel. Only short known fields are kept.
            if let skin = body["skin"] as? [String: Any] {
                let keys = ["color", "custom", "cog", "ring", "clamp", "scanner", "arms", "eye", "eyeCustom", "eye2", "iris", "pupil", "core", "coreCustom"]
                let clean = skin.compactMapValues { $0 as? String }.filter { keys.contains($0.key) && $0.value.count <= 16 }
                UserDefaults.standard.set(clean, forKey: "skin")
                FileOps.log("skin saved: \(clean.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
            }
        case "hot":
            // Where her arms are now, so only they (and the halo) take clicks.
            hotRects = (body["rects"] as? [[Double]] ?? []).prefix(4).compactMap { r in
                r.count == 4 ? CGRect(x: r[0], y: r[1], width: r[2], height: r[3]) : nil
            }
        case "dock":
            dock()
        case "teleportedOut":
            if pendingDock { enterDocked() }
        case "undock":
            finishUndock()
        case "menu":
            onShowMenu?()
        case "timerSeen":
            timer.acknowledge()
        case "open":
            setOpen()
        case "close":
            setCollapsed()
        case "dragStart" where mode != .docked:
            drag = lastMouseDown ?? (NSEvent.mouseLocation, panel.frame.origin)
        case "ask":
            brain.handle(body["text"] as? String ?? "") { [weak self] in self?.send($0.json) }
        case "confirm":
            brain.confirm(body["id"] as? String ?? "") { [weak self] in self?.send($0.json) }
        case "cancel":
            brain.cancel(body["id"] as? String ?? "") { [weak self] in self?.send($0.json) }
        default:
            break
        }
    }

    private func sendTimer() { send(timer.json) }

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.misa && window.misa.receive(\(json))")
    }

    /// Saves the web view's current pixels to $TMPDIR/misa-snapshot.png (developer hook).
    func saveSnapshot() {
        webView.takeSnapshot(with: nil) { image, _ in
            guard let image, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("misa-snapshot.png")
            try? png.write(to: url)
        }
    }

    // MARK: Remembering where she sits

    private func save(_ p: CGPoint) {
        UserDefaults.standard.set([p.x, p.y], forKey: "haloOrigin")
    }

    private static func loadOrigin() -> CGPoint? {
        guard let a = UserDefaults.standard.array(forKey: "haloOrigin") as? [Double], a.count == 2 else { return nil }
        return CGPoint(x: a[0], y: a[1])
    }
}

/// WKUserContentController keeps a strong reference to its handlers; this avoids a retain cycle.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}
