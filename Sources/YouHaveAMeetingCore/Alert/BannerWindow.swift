import AppKit

/// The silenced presentation: a small non-activating panel in the top-right
/// corner. Never steals focus, never makes a sound, but stays put until acted
/// on so the meeting cannot be missed entirely.
final class BannerWindow: NSPanel {
    private static let margin: CGFloat = 16

    init(contentSize: NSSize, screen: NSScreen) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

        reposition(on: screen, size: contentSize)
    }

    func reposition(on screen: NSScreen, size: NSSize) {
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - size.width - Self.margin,
            y: visible.maxY - size.height - Self.margin
        )
        setFrame(NSRect(origin: origin, size: size), display: true)
    }

    override var canBecomeKey: Bool { false }
}
