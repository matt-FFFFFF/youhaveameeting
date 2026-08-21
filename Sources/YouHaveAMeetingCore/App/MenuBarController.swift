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

    /// What the glyph is currently showing, so it is only redrawn on a change.
    private var iconState: MenuBarIconState?
    private var isAlerting = false
    /// Sleeps until the moment the glyph would change on its own, mirroring
    /// how the scheduler waits for a fire time rather than polling.
    private var iconTransition: Task<Void, Never>?
    /// Pushes microphone and camera changes, so those two do not wait for
    /// something else to happen before the glyph catches up.
    private lazy var presence = PresenceObserver { [weak self] in
        self?.updateIcon()
    }

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

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        settingsChanged()
        observeSettings()
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
        updateIcon()
        guard let menu = statusItem.menu else { return }
        rebuild(menu)
    }

    // MARK: - Icon

    /// Told by the app when an alert goes up and when it comes down.
    ///
    /// The presenter owns that fact and there is no notification for it, so it
    /// is pushed here rather than discovered.
    func setAlerting(_ isAlerting: Bool) {
        guard self.isAlerting != isAlerting else { return }
        self.isAlerting = isAlerting
        updateIcon()
    }

    /// Redraw the glyph if the state it should show has changed, then sleep
    /// until the next time-driven change.
    ///
    /// Presence is read here rather than held: `PresenceMonitor` is
    /// deliberately on-demand. `PresenceObserver` says *when* to read it for
    /// the microphone and the camera; screen sharing has no such signal, so
    /// that one is only as fresh as the last thing that called this - the menu
    /// opening, a meeting approaching, an alert appearing.
    private func updateIcon() {
        let current = settings.value
        let signals = PresenceMonitor.currentSignals(settings: current)
        let fireTime = scheduler.upcoming.map {
            MeetingSchedule.fireTime(for: $0, leadOffset: current.leadOffset)
        }
        let state = MenuBarIconState.current(
            fireTime: fireTime,
            now: .now,
            isAlerting: isAlerting,
            isQuiet: SilencePolicy.decide(for: signals, settings: current).style == .banner,
            isForced: current.presenceMode == .fullScreen
        )

        if state != iconState {
            iconState = state
            statusItem.button?.image = MenuBarIcon.image(for: state)
        }

        iconTransition?.cancel()
        guard let next = MenuBarIconState.nextTimeDrivenChange(fireTime: fireTime, now: .now)
        else { return }
        iconTransition = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.updateIcon()
        }
    }

    /// Any settings change can flip the glyph - the alert mode and the
    /// quiet-alert conditions both live in settings, and both can be changed
    /// from the settings window as well as the menu. Observing the store once
    /// covers every route, so a mode switch redraws the icon immediately.
    private func observeSettings() {
        withObservationTracking {
            _ = settings.value
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.settingsChanged()
                // The tracking API fires once, so re-register for the next.
                self?.observeSettings()
            }
        }
    }

    /// What settings decide: which signals are worth watching, and the glyph.
    private func settingsChanged() {
        presence.update(for: settings.value)
        updateIcon()
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
        settings.update { $0.presenceMode = mode }
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
        // Opening the menu is a sampling moment for presence, so take the
        // glyph with it: a call that started while nothing else was happening
        // is picked up here rather than staying stale behind the open menu.
        updateIcon()
        rebuild(menu)
    }
}
