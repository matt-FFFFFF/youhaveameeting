import AppKit
import SwiftUI

/// Hosts the settings window. Kept as a single reusable instance so reopening
/// brings the existing window forward rather than stacking duplicates.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: SettingsStore
    private let accounts: AccountManager
    private let onScheduleAffectingChange: () -> Void

    init(
        settings: SettingsStore,
        accounts: AccountManager,
        onScheduleAffectingChange: @escaping () -> Void
    ) {
        self.settings = settings
        self.accounts = accounts
        self.onScheduleAffectingChange = onScheduleAffectingChange
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        // An accessory app is not active by default, so the window would open
        // behind whatever the user is looking at.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = SettingsView(
            settings: settings,
            accounts: accounts,
            onScheduleAffectingChange: onScheduleAffectingChange
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        return window
    }
}
