import AppKit

/// Sizes must match web/src/App.tsx.
enum Geometry {
    static let halo: CGFloat = 140
    static let panelWidth: CGFloat = 400
    static let panelHeight: CGFloat = 510
    static let gap: CGFloat = 6

    /// Collapsed, the window has room around the halo for her arms (empty space clicks through).
    static let armSide: CGFloat = 90
    static let armTop: CGFloat = 64 // room for her arms and for a hat
    static let armBottom: CGFloat = 50
    static var collapsedSize: NSSize { NSSize(width: halo + armSide * 2, height: halo + armTop + armBottom) }
    /// The halo's top-left inside the collapsed window (web coordinates, y down).
    static var haloInCollapsed: CGPoint { CGPoint(x: armSide, y: armTop) }
    static func collapsedFrame(haloOrigin o: CGPoint) -> NSRect {
        NSRect(origin: CGPoint(x: o.x - armSide, y: o.y - armBottom), size: collapsedSize)
    }

    /// Docked: the camera hangs from the bottom edge of the menu bar.
    static let camera: CGFloat = 64
    static let cameraWindow = NSSize(width: 320, height: 330)
    /// Camera center inside the docked window (web coordinates, y down): its top half sits in the menu bar.
    static let cameraInWindow = CGPoint(x: 160, y: 36)
    /// Width reserved in the menu bar while docked.
    static let menuBarSlot: CGFloat = 72

    static var openSize: NSSize {
        NSSize(width: max(panelWidth, halo), height: panelHeight + gap + halo)
    }

    struct OpenLayout {
        var frame: NSRect
        /// Halo's top-left inside the window (web coordinates, y down).
        var haloInWindow: CGPoint
        var right: Bool
        var bottom: Bool
        /// The chat panel on screen (it and the halo take clicks; the rest clicks through).
        var chat: NSRect
    }

    /// Grows the window from the halo toward the middle of the screen. The chat and halo stay on
    /// screen; the room for her arms around the halo may hang off the edge.
    static func openLayout(haloOrigin: CGPoint) -> OpenLayout {
        let haloRect = NSRect(origin: haloOrigin, size: NSSize(width: halo, height: halo))
        let screen = screenFor(haloRect)
        let visible = screen.visibleFrame
        let right = haloRect.midX > visible.midX
        let bottom = haloRect.midY < visible.midY

        let size = openSize
        var core = NSRect(
            x: right ? haloRect.maxX - size.width : haloRect.minX,
            y: bottom ? haloRect.minY : haloRect.maxY - size.height,
            width: size.width,
            height: size.height
        )
        core = clamp(core, to: visible)

        // Where the halo ends up after clamping (screen coordinates), plus room for her arms.
        let haloScreen = CGPoint(x: right ? core.maxX - halo : core.minX, y: bottom ? core.minY : core.maxY - halo)
        let frame = core.union(collapsedFrame(haloOrigin: haloScreen))
        let haloInWindow = CGPoint(x: haloScreen.x - frame.minX, y: frame.maxY - (haloScreen.y + halo))
        let chat = NSRect(x: core.minX, y: bottom ? core.maxY - panelHeight : core.minY, width: core.width, height: panelHeight)
        return OpenLayout(frame: frame, haloInWindow: haloInWindow, right: right, bottom: bottom, chat: chat)
    }

    /// Which sides of a halo at `origin` have screen room for an arm.
    static func armRoom(haloOrigin o: CGPoint) -> (left: Bool, right: Bool) {
        let visible = screenFor(NSRect(origin: o, size: NSSize(width: halo, height: halo))).visibleFrame
        return (o.x - armSide + 10 >= visible.minX, o.x + halo + armSide - 10 <= visible.maxX)
    }

    /// The halo's screen origin (bottom-left, AppKit coordinates) for a window in open mode.
    static func haloOrigin(openFrame frame: NSRect, haloInWindow p: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + p.x, y: frame.maxY - p.y - halo)
    }

    static func defaultHaloOrigin() -> CGPoint {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return CGPoint(x: visible.maxX - halo - armSide, y: visible.minY + armBottom) // room for her arms
    }

    static func screenFor(_ rect: NSRect) -> NSScreen {
        NSScreen.screens.max { a, b in
            a.frame.intersection(rect).area < b.frame.intersection(rect).area
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Keeps at least part of the halo on some screen (e.g. after unplugging a monitor).
    static func ensureOnScreen(_ origin: CGPoint) -> CGPoint {
        let rect = NSRect(origin: origin, size: NSSize(width: halo, height: halo))
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersection(rect).area > halo * halo * 0.25 }
        return onScreen ? origin : defaultHaloOrigin()
    }

    static func clamp(_ frame: NSRect, to bounds: NSRect) -> NSRect {
        var f = frame
        f.origin.x = min(max(f.minX, bounds.minX), bounds.maxX - f.width)
        f.origin.y = min(max(f.minY, bounds.minY), bounds.maxY - f.height)
        return f
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
