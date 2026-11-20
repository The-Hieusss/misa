import AppKit

/// A borderless, see-through window that floats above every app,
/// on every desktop and over full-screen apps, without stealing focus.
final class MisaPanel: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovable = false // dragging is handled by MisaController
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    // Needed so the chat input can receive typing.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
