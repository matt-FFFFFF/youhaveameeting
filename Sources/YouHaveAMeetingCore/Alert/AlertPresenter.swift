import AppKit
import SwiftUI

/// Puts a meeting alert on screen and owns it until the user acts.
///
/// There is no auto-dismiss by design: an alert that goes away on its own is
/// the failure mode this app exists to fix.
@MainActor
final class AlertPresenter {
    private var shields: [ShieldWindow] = []
    private var banner: BannerWindow?
    private var escalation: Task<Void, Never>?
    private var chime: NSSound?
    private var onOutcome: ((AlertOutcome) -> Void)?
    /// What is on screen right now, so a display change can redraw it.
    private var currentMeeting: Meeting?
    private var currentStyle: AlertStyle?
    private var screenObserver: (any NSObjectProtocol)?

    /// How a Join click opens the link. Injectable so the alert can route to
    /// the user's chosen browser; defaults to the system handler.
    var openLink: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// Which displays an alert covers. Read at each presentation and again on
    /// every display-change redraw, so a change made mid-alert applies when
    /// the windows are rebuilt. Injectable for the same reason as `openLink`.
    var displayScope: () -> AlertDisplayScope = { .allDisplays }

    var isPresenting: Bool { !shields.isEmpty || banner != nil }

    func present(
        _ meeting: Meeting,
        style: AlertStyle,
        onOutcome: @escaping (AlertOutcome) -> Void
    ) {
        dismissWindows()
        self.onOutcome = onOutcome
        currentMeeting = meeting
        currentStyle = style
        watchScreenChanges()

        switch style {
        case .takeover:
            presentTakeover(meeting)
            startEscalation()
        case .banner:
            presentBanner(meeting)
        }
    }

    /// Tear down without reporting an outcome - used when the caller, not the
    /// user, ends the alert.
    func cancel() {
        onOutcome = nil
        dismissWindows()
    }

    // MARK: - Presentation

    private func presentTakeover(_ meeting: Meeting) {
        let screens = screensCovering(displayScope())
        let focused = screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? screens.first

        for screen in screens {
            let window = ShieldWindow(screen: screen)
            let hosting = NSHostingView(
                rootView: shieldContent(meeting, isFocused: screen == focused)
            )
            hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
            hosting.autoresizingMask = [.width, .height]
            window.contentView = hosting
            window.orderFrontRegardless()
            shields.append(window)
            if screen == focused {
                window.makeKey()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The displays a presentation covers. Primary-only pins to
    /// `NSScreen.screens[0]` - the menu-bar display - not `NSScreen.main`,
    /// which follows keyboard focus.
    private func screensCovering(_ scope: AlertDisplayScope) -> [NSScreen] {
        let all = NSScreen.screens
        guard !all.isEmpty else { return [] }
        switch scope {
        case .allDisplays:
            return all
        case .primaryDisplayOnly:
            return [all[0]]
        }
    }

    private func shieldContent(_ meeting: Meeting, isFocused: Bool) -> some View {
        ZStack {
            Color.black.opacity(0.55)
            if isFocused {
                card(for: meeting, compact: false)
            } else {
                ShieldBackdropView(title: meeting.title)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func presentBanner(_ meeting: Meeting) {
        // All-displays keeps the historical placement: wherever the user is
        // working. Primary-only anchors to the menu-bar display instead, since
        // that is what the user asked to be alerted on.
        let screen: NSScreen? = switch displayScope() {
        case .allDisplays:
            NSScreen.main ?? NSScreen.screens.first
        case .primaryDisplayOnly:
            NSScreen.screens.first
        }
        guard let screen else { return }
        // The banner panel never becomes key, and SwiftUI greys controls in
        // inactive windows - which would make Join look disabled. Force the
        // active appearance so the primary action still reads as primary.
        let hosting = NSHostingView(
            rootView: card(for: meeting, compact: true)
                .environment(\.controlActiveState, .active)
        )
        let size = hosting.fittingSize
        let panel = BannerWindow(contentSize: size, screen: screen)
        panel.contentView = hosting
        panel.reposition(on: screen, size: size)
        panel.orderFrontRegardless()
        banner = panel
    }

    private func card(for meeting: Meeting, compact: Bool) -> AlertCardView {
        AlertCardView(
            meeting: meeting,
            compact: compact,
            onJoin: { [weak self] in self?.finish(.joined, opening: meeting.joinURL) },
            onSnooze: { [weak self] minutes in self?.finish(.snoozed(seconds: minutes * 60)) },
            onDismiss: { [weak self] in self?.finish(.dismissed) }
        )
    }

    // MARK: - Escalation

    private func startEscalation() {
        escalation?.cancel()
        escalation = Task { [weak self] in
            var index = 0
            while !Task.isCancelled {
                let gap = EscalationSchedule.gap(beforeChime: index)
                if gap > 0 {
                    try? await Task.sleep(for: .seconds(gap))
                }
                guard !Task.isCancelled else { return }
                self?.playChime()
                index += 1
            }
        }
    }

    private func playChime() {
        if chime == nil {
            chime = NSSound(named: NSSound.Name("Submarine"))
        }
        guard let chime else {
            NSSound.beep()
            return
        }
        chime.stop()
        chime.play()
    }

    // MARK: - Teardown

    private func finish(_ outcome: AlertOutcome, opening url: URL? = nil) {
        let handler = onOutcome
        onOutcome = nil
        dismissWindows()
        if let url {
            openLink(url)
        }
        handler?(outcome)
    }

    private func dismissWindows() {
        escalation?.cancel()
        escalation = nil
        chime?.stop()

        removeWindows()

        currentMeeting = nil
        currentStyle = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    /// Order out the alert windows, leaving escalation and the record of what
    /// is being presented alone - used when the windows must be rebuilt rather
    /// than torn down.
    private func removeWindows() {
        for window in shields {
            window.orderOut(nil)
        }
        shields.removeAll()

        banner?.orderOut(nil)
        banner = nil
    }

    // MARK: - Display changes

    /// A display reconfiguration invalidates every alert frame: shields pinned
    /// to a removed screen end up piled onto whichever screen survives, and
    /// the banner keeps the dead display's coordinates. Redraw against the new
    /// screen set rather than repair individual frames - once a screen appears
    /// or vanishes even the window count is wrong. The observer exists only
    /// while an alert is up; there is nothing to redraw otherwise.
    private func watchScreenChanges() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.redrawForCurrentScreens() }
        }
    }

    private func redrawForCurrentScreens() {
        guard let meeting = currentMeeting, !NSScreen.screens.isEmpty else { return }
        removeWindows()
        switch currentStyle {
        case .takeover:
            presentTakeover(meeting)
        case .banner, .none:
            presentBanner(meeting)
        }
    }
}
