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

    var isPresenting: Bool { !shields.isEmpty || banner != nil }

    func present(
        _ meeting: Meeting,
        style: AlertStyle,
        onOutcome: @escaping (AlertOutcome) -> Void
    ) {
        dismissWindows()
        self.onOutcome = onOutcome

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
        let focused = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        for screen in NSScreen.screens {
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
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
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
            NSWorkspace.shared.open(url)
        }
        handler?(outcome)
    }

    private func dismissWindows() {
        escalation?.cancel()
        escalation = nil
        chime?.stop()

        for window in shields {
            window.orderOut(nil)
        }
        shields.removeAll()

        banner?.orderOut(nil)
        banner = nil
    }
}
