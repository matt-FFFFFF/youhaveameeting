import AppKit
import os

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "app.youhaveameeting", category: "app")

    private let settings = SettingsStore()
    private let presenter = AlertPresenter()
    private lazy var accounts = AccountManager(settings: settings)
    private lazy var scheduler = MeetingScheduler(
        settings: settings,
        service: accounts.service
    )
    private var menuBar: MenuBarController?
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings,
        accounts: accounts,
        onScheduleAffectingChange: { [weak self] in self?.scheduler.restartPolling() }
    )

    override public init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_: Notification) {
        installMainMenu()
        menuBar = MenuBarController(
            settings: settings,
            accounts: accounts,
            scheduler: scheduler,
            onShowSettings: { [weak self] in self?.showSettings() },
            onTestAlert: { [weak self] in self?.showTestAlert() }
        )

        scheduler.onFire = { [weak self] meeting in
            self?.present(meeting)
        }
        scheduler.onUpcomingChanged = { [weak self] in
            self?.menuBar?.refreshStatus()
        }

        Task {
            await accounts.rebuildProviders()
            scheduler.start()
        }

        let options = LaunchOptions(arguments: CommandLine.arguments)
        if options.openSettings {
            showSettings()
        }
        if options.testAlert {
            presentTestAlert(style: options.testAlertStyle)
        }
        if options.listWindows {
            let canRead = PresenceMonitor.canReadWindowTitles()
            print("screen recording permission: \(canRead)")
            print(PresenceMonitor.windowInventory().joined(separator: "\n"))
            NSApp.terminate(nil)
            return
        }
        if options.presence {
            print(presenceReport())
            NSApp.terminate(nil)
            return
        }
        if options.keychainSelfTest {
            print(KeychainSelfTest.run())
            NSApp.terminate(nil)
            return
        }
        if options.listMeetings {
            Task { await listMeetings(verbose: options.verbose) }
        }
    }

    /// Diagnostic path: proves sign-in, fetching and link extraction work
    /// against real calendars without waiting for a meeting to start.
    private func listMeetings(verbose: Bool) async {
        await accounts.rebuildProviders()

        let now = Date.now
        let window = settings.value.lookahead
        let meetings = await accounts.service.meetings(from: now, to: now.addingTimeInterval(window))

        var lines = ["\(meetings.count) meeting(s) in the next \(Int(window / 3600))h"]
        for meeting in meetings {
            let start = meeting.start.formatted(date: .abbreviated, time: .shortened)
            let link = meeting.joinURL?.host() ?? "no join link"
            let title = verbose ? "  \(meeting.title)" : ""
            lines.append("  \(start)  \(link)\(title)")
        }
        // Report what the scheduler would actually arm, so the selection logic
        // is exercised against real data and not only fixtures.
        let firedLog = FiredLog()
        if let next = MeetingSchedule.next(
            in: meetings,
            now: now,
            leadOffset: settings.value.leadOffset,
            fired: firedLog.keys
        ) {
            let fireTime = MeetingSchedule.fireTime(
                for: next,
                leadOffset: settings.value.leadOffset
            )
            let minutes = Int(fireTime.timeIntervalSince(now) / 60)
            let when = fireTime.formatted(date: .abbreviated, time: .shortened)
            lines.append("next alarm: \(when) (in \(minutes)m)")
        } else {
            lines.append("next alarm: none armed")
        }

        print(lines.joined(separator: "\n"))

        NSApp.terminate(nil)
    }

    @objc func showSettings() {
        settingsWindow.show()
    }

    /// Fires a sample alert through the real presentation path, so what you see
    /// is exactly what a genuine meeting would produce right now - including
    /// the banner downgrade if you are in a call or sharing.
    func showTestAlert() {
        present(Meeting(
            id: "test-alert",
            title: "Test alert - not a real meeting",
            start: .now,
            end: .now.addingTimeInterval(1800),
            organiser: "You Have a Meeting",
            joinURL: URL(string: "https://example.com/join"),
            accountID: "test"
        ))
    }

    /// A menu-bar app has no menu bar of its own, but one is still needed for
    /// the standard Command-comma shortcut to reach anything.
    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "Quit You Have a Meeting",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        mainMenu.addItem(editMenuItem())
        NSApp.mainMenu = mainMenu
    }

    /// Without an Edit menu the standard text shortcuts do nothing: AppKit
    /// routes Command-C/V/A/Z through its key equivalents, not the text view.
    /// Every text field in the app depends on this existing.
    private func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")

        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())

        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(
            withTitle: "Delete",
            action: #selector(NSText.delete(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        item.submenu = menu
        return item
    }

    /// Diagnostic: what the presence sensors report right now, and what the
    /// policy would do with it.
    private func presenceReport() -> String {
        let signals = PresenceMonitor.currentSignals(settings: settings.value)
        let style = SilencePolicy.style(for: signals, settings: settings.value)
        let reason = SilencePolicy.reason(for: signals, settings: settings.value)

        var lines = [
            "microphone in use: \(signals.microphoneInUse)",
            "camera in use:     \(signals.cameraInUse)",
            "screen shared:     \(signals.screenBeingShared)",
            "manual mode:       \(signals.mode.rawValue)",
            "window titles readable: \(PresenceMonitor.canReadWindowTitles()) "
                + "(Screen Recording permission)"
        ]
        let outcome = style == .takeover ? "takeover" : "banner"
        lines.append("-> alert style:    \(outcome)\(reason.map { " (\($0))" } ?? "")")
        return lines.joined(separator: "\n")
    }

    private func present(_ meeting: Meeting) {
        let signals = PresenceMonitor.currentSignals(settings: settings.value)
        let style = SilencePolicy.style(for: signals, settings: settings.value)
        if let reason = SilencePolicy.reason(for: signals, settings: settings.value) {
            Self.log.info("alert quietened: \(reason, privacy: .public)")
        }

        presenter.present(meeting, style: style) { [weak self] outcome in
            guard case let .snoozed(seconds) = outcome else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.present(meeting)
            }
        }
    }

    /// Manual-verification path for the alert engine. Real alerts come from the
    /// scheduler; this exists so the window behaviour can be checked without a
    /// calendar account or a meeting three minutes away.
    private func presentTestAlert(style: AlertStyle) {
        let meeting = Meeting(
            id: "test-alert",
            title: "Design review with the platform team",
            start: .now,
            end: .now.addingTimeInterval(1800),
            organiser: "Organised by test@example.com",
            joinURL: URL(string: "https://example.com/join"),
            accountID: "test"
        )

        presenter.present(meeting, style: style) { [weak self] outcome in
            guard case let .snoozed(seconds) = outcome else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.presentTestAlert(style: style)
            }
        }
    }
}
