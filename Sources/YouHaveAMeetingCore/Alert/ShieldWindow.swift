import AppKit

/// A borderless window that sits above everything, including full-screen apps.
///
/// This is deliberately a plain window rather than a user notification: Focus
/// and Do Not Disturb suppress notifications, which is exactly the situation
/// the app exists to survive.
final class ShieldWindow: NSWindow {
    init(screen: NSScreen) {
        // The screen: variant is a convenience initialiser, so use the
        // designated one and place the window with setFrame below.
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        // CGShieldingWindowLevel is above the screen saver, so full-screen
        // video and presentation apps cannot cover the alert.
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        animationBehavior = .none
        setFrame(screen.frame, display: true)
    }

    // Borderless windows refuse key status by default, which would break the
    // Return-to-join shortcut.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
