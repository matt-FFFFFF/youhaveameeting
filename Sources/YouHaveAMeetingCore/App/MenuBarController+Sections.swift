import AppKit

/// Menu construction, split out so the controller itself stays about lifecycle
/// and actions.
extension MenuBarController {
    /// Refresh cadences offered in the menu, in minutes.
    private static var refreshChoices: [Int] { [1, 5, 15, 30] }

    // MARK: - Sections

    func statusSection() -> [NSMenuItem] {
        var items = [disabledItem(statusTitle)]

        if let refreshed = scheduler.lastRefresh {
            let stamp = refreshed.formatted(date: .omitted, time: .shortened)
            items.append(disabledItem("Updated \(stamp)"))
        }

        let refresh = NSMenuItem(
            title: "Refresh Now",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refresh.target = self
        items.append(refresh)
        items.append(refreshIntervalMenuItem())
        return items
    }

    func alertSection() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        // .normal is the absence of an override, so it needs no menu row.
        for mode in PresenceMode.allCases where mode != .normal {
            let item = toggle(
                title: mode.title,
                isOn: settings.value.presenceMode == mode,
                action: #selector(setPresenceMode(_:))
            )
            item.representedObject = mode.rawValue
            items.append(item)
        }

        items.append(silenceMenuItem())

        // Say plainly whether the next alert would be downgraded, rather than
        // leaving the user to discover it when one fires.
        let signals = PresenceMonitor.currentSignals(settings: settings.value)
        let style = SilencePolicy.style(for: signals, settings: settings.value)
        if let reason = SilencePolicy.reason(for: signals, settings: settings.value) {
            items.append(disabledItem("Alerts quiet: \(reason)"))
        }

        // Name the outcome so the menu says what the test will actually do.
        let outcome = style == .takeover ? "Full Screen" : "Banner"
        let test = NSMenuItem(
            title: "Test Notification (\(outcome))",
            action: #selector(testAlert),
            keyEquivalent: ""
        )
        test.target = self
        items.append(test)
        return items
    }

    func footerSection() -> [NSMenuItem] {
        var items = [toggle(
            title: "Launch at Login",
            isOn: LoginItem.isEnabled,
            action: #selector(toggleLaunchAtLogin)
        )]

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        items.append(settingsItem)

        items.append(NSMenuItem(
            title: "Quit You Have a Meeting",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        return items
    }

    // MARK: - Submenus

    func accountsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Accounts", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for account in accounts.accounts {
            let entry = NSMenuItem(
                title: "Disconnect \(account.displayName)",
                action: #selector(disconnectAccount(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = account.id
            submenu.addItem(entry)
        }
        if !accounts.accounts.isEmpty {
            submenu.addItem(.separator())
        }

        for kind in ProviderKind.allCases {
            let entry = NSMenuItem(
                title: "Connect \(kind.displayName)...",
                action: #selector(connectAccount(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = kind.rawValue
            // Sign-in cannot start without a client ID, so say so rather than
            // failing after the browser opens.
            entry.isEnabled = !settings.value.clientID(for: kind).isEmpty
            submenu.addItem(entry)
        }

        item.submenu = submenu
        return item
    }

    func silenceMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Quiet Alerts When", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let current = settings.value

        submenu.addItem(toggle(
            title: "In a Call (microphone)",
            isOn: current.silenceWhenMicActive,
            action: #selector(toggleSilenceMic)
        ))
        submenu.addItem(toggle(
            title: "Camera Is On",
            isOn: current.silenceWhenCameraActive,
            action: #selector(toggleSilenceCamera)
        ))
        submenu.addItem(toggle(
            title: "Sharing My Screen",
            isOn: current.silenceWhenSharing,
            action: #selector(toggleSilenceSharing)
        ))

        // Share detection needs window titles, which need this permission.
        if current.silenceWhenSharing, !PresenceMonitor.canReadWindowTitles() {
            submenu.addItem(.separator())
            let warning = NSMenuItem(
                title: "Screen Recording permission needed for share detection",
                action: #selector(openScreenRecordingSettings),
                keyEquivalent: ""
            )
            warning.target = self
            submenu.addItem(warning)
        }

        item.submenu = submenu
        return item
    }

    func refreshIntervalMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Check Every", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let current = settings.value.pollIntervalSeconds

        for minutes in Self.refreshChoices {
            let entry = NSMenuItem(
                title: minutes == 1 ? "1 minute" : "\(minutes) minutes",
                action: #selector(setRefreshInterval(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.tag = minutes * 60
            entry.state = current == minutes * 60 ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    // MARK: - Helpers

    /// Says what the app actually knows, rather than implying it checked and
    /// found nothing.
    private var statusTitle: String {
        if accounts.accounts.isEmpty {
            return "No calendar connected"
        }
        if let meeting = scheduler.upcoming {
            let time = meeting.start.formatted(date: .omitted, time: .shortened)
            return "\(time)  \(meeting.title)"
        }
        if scheduler.lastRefresh == nil {
            return "Checking for meetings..."
        }
        let hours = Int(settings.value.lookahead / 3600)
        return "No meetings in the next \(hours)h"
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func toggle(title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isOn ? .on : .off
        return item
    }
}
