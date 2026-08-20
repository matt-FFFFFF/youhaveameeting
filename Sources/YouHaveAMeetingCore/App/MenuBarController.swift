import AppKit

/// Owns the status-bar item and its menu. The menu is rebuilt on demand rather
/// than mutated in place, so it always reflects current settings.
///
/// Menu construction lives in `MenuBarController+Sections`; this file keeps the
/// lifecycle and the actions.
@MainActor
final class MenuBarController: NSObject {
    let statusItem: NSStatusItem
    let settings: SettingsStore
    let accounts: AccountManager
    let scheduler: MeetingScheduler
    private let onShowSettings: () -> Void
    private let onTestAlert: () -> Void

    init(
        settings: SettingsStore,
        accounts: AccountManager,
        scheduler: MeetingScheduler,
        onShowSettings: @escaping () -> Void,
        onTestAlert: @escaping () -> Void
    ) {
        self.settings = settings
        self.accounts = accounts
        self.scheduler = scheduler
        self.onShowSettings = onShowSettings
        self.onTestAlert = onTestAlert
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let icon = NSImage(
            systemSymbolName: "calendar.badge.clock",
            accessibilityDescription: "You Have a Meeting"
        )
        icon?.isTemplate = true
        statusItem.button?.image = icon

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in statusSection() {
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(accountsMenuItem())
        menu.addItem(.separator())
        for item in alertSection() {
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for item in footerSection() {
            menu.addItem(item)
        }
    }

    /// Called when the scheduler's view of the next meeting changes.
    func refreshStatus() {
        guard let menu = statusItem.menu else { return }
        rebuild(menu)
    }

    // MARK: - Actions

    @objc func openSettings() {
        onShowSettings()
    }

    @objc func testAlert() {
        onTestAlert()
    }

    @objc func refreshNow() {
        scheduler.restartPolling()
    }

    @objc func setRefreshInterval(_ sender: NSMenuItem) {
        settings.update { $0.pollIntervalSeconds = sender.tag }
        // Restart so the new cadence applies now rather than after the
        // remaining sleep of the old one.
        scheduler.restartPolling()
    }

    @objc func setPresenceMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = PresenceMode(rawValue: raw)
        else { return }
        // Selecting the active mode turns it off again.
        settings.update { $0.presenceMode = $0.presenceMode == mode ? .normal : mode }
    }

    @objc func toggleSilenceMic() {
        settings.update { $0.silenceWhenMicActive.toggle() }
    }

    @objc func toggleSilenceCamera() {
        settings.update { $0.silenceWhenCameraActive.toggle() }
    }

    @objc func toggleSilenceSharing() {
        settings.update { $0.silenceWhenSharing.toggle() }
    }

    @objc func openScreenRecordingSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func connectAccount(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = ProviderKind(rawValue: raw)
        else { return }

        Task { @MainActor in
            do {
                try await accounts.connect(kind)
            } catch {
                presentError(error, title: "Could not connect \(kind.displayName)")
            }
        }
    }

    @objc func disconnectAccount(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let account = accounts.accounts.first(where: { $0.id == id })
        else { return }
        accounts.disconnect(account)
    }

    @objc func toggleLaunchAtLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            presentError(error, title: "Could not change the login item")
        }
    }

    func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }
}
