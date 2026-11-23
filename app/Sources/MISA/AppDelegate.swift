import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MisaController!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var visibilityItem: NSMenuItem!
    private var dockItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var listenItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MisaController()
        setUpMenuBar()

        controller.statusSlot = { [weak self] in self?.slotOnScreen() }
        controller.onDockedChange = { [weak self] docked in self?.showDocked(docked) }
        controller.onShowMenu = { [weak self] in
            self?.statusItem.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        controller.show()

        // ⌥Space opens or closes the chat from anywhere (and brings her back out if she's put away).
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
            self?.controller.toggleChat()
        }

        listenForDevCommands()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Developer hooks, e.g. from Terminal:
    ///   swift -e 'import Foundation; DistributedNotificationCenter.default().post(name: .init("app.misa.toggleChat"), object: nil)'
    /// "app.misa.snapshot" saves what the web view shows to $TMPDIR/misa-snapshot.png.
    private func listenForDevCommands() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("app.misa.toggleChat"), object: nil, queue: .main) { [weak self] _ in
            self?.controller.toggleChat()
        }
        center.addObserver(forName: .init("app.misa.toggleDock"), object: nil, queue: .main) { [weak self] _ in
            self?.toggleDock()
        }
        center.addObserver(forName: .init("app.misa.snapshot"), object: nil, queue: .main) { [weak self] _ in
            self?.controller.saveSnapshot()
        }
        center.addObserver(forName: .init("app.misa.toggleLogin"), object: nil, queue: .main) { [weak self] _ in
            self?.toggleLaunchAtLogin()
            NSLog("MISA login item: %d", SMAppService.mainApp.status.rawValue)
        }
        center.addObserver(forName: .init("app.misa.inspect"), object: nil, queue: .main) { [weak self] _ in
            self?.controller.inspect()
        }
    }

    // MARK: Menu bar

    private func setUpMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        showDocked(false)

        let menu = NSMenu()
        let chat = NSMenuItem(title: "Open Chat", action: #selector(openChat), keyEquivalent: " ")
        chat.keyEquivalentModifierMask = [.option]
        menu.addItem(chat)
        dockItem = NSMenuItem(title: "Put Away in Menu Bar", action: #selector(toggleDock), keyEquivalent: "")
        menu.addItem(dockItem)
        visibilityItem = NSMenuItem(title: "Hide M.I.S.A.", action: #selector(toggleVisible), keyEquivalent: "")
        menu.addItem(visibilityItem)
        menu.addItem(NSMenuItem(title: "Reset Position", action: #selector(resetPosition), keyEquivalent: ""))
        menu.addItem(.separator())
        listenItem = NSMenuItem(title: "Listen for “Hey MISA”", action: #selector(toggleListening), keyEquivalent: "")
        menu.addItem(listenItem)
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        menu.addItem(loginItem)
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Quit M.I.S.A.", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    /// Docked: an empty slot the camera hangs over. Otherwise: the normal icon.
    private func showDocked(_ docked: Bool) {
        guard let button = statusItem.button else { return }
        if docked {
            statusItem.length = Geometry.menuBarSlot
            button.image = nil
            button.setAccessibilityLabel("M.I.S.A. (put away)")
        } else {
            statusItem.length = NSStatusItem.squareLength
            button.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "M.I.S.A.")
        }
        dockItem?.title = docked ? "Bring Out M.I.S.A." : "Put Away in Menu Bar"
    }

    /// The menu bar item's slot on screen. Its minY is the bottom edge of the menu bar.
    private func slotOnScreen() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let r = window.convertToScreen(button.convert(button.bounds, to: nil))
        return NSRect(x: r.minX, y: window.frame.minY, width: r.width, height: window.frame.height)
    }

    @objc private func openChat() { controller.toggleChat() }

    @objc private func toggleDock() {
        if controller.isDocked { controller.undock() } else { controller.dock() }
    }

    @objc private func toggleVisible() {
        if controller.isVisible {
            controller.hide()
            visibilityItem.title = "Show M.I.S.A."
        } else {
            controller.show()
            visibilityItem.title = "Hide M.I.S.A."
        }
    }

    @objc private func resetPosition() { controller.resetPosition() }

    @objc private func toggleListening() {
        VoiceListener.shared.setEnabled(!VoiceListener.shared.enabled)
        listenItem.state = VoiceListener.shared.enabled ? .on : .off
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Launch at login (macOS login items; also listed in System Settings > General > Login Items)

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nYou can also add M.I.S.A. in System Settings > General > Login Items."
            alert.runModal()
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        refreshLoginItem()
    }

    private func refreshLoginItem() {
        loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show her banners even while she's the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    /// Clicking a banner opens the chat, where the message (and its Update button) is waiting.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.controller.show()
            self?.controller.openChat()
            done()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    /// The user can also change it in System Settings, so check each time the menu opens.
    func menuWillOpen(_ menu: NSMenu) {
        refreshLoginItem()
        listenItem?.state = VoiceListener.shared.enabled ? .on : .off
    }
}
