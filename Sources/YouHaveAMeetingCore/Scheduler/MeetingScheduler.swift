import AppKit
import os

/// Keeps one timer armed for the next meeting and fires it.
///
/// There is no polling loop ticking every second: the calendar is re-fetched on
/// an interval, and between fetches a single sleeping task waits for exactly
/// the next fire time. Idle cost is effectively zero.
@MainActor
final class MeetingScheduler {
    private static let log = Logger(subsystem: "app.youhaveameeting", category: "scheduler")

    private let settings: SettingsStore
    private let service: CalendarService
    private let firedLog: FiredLog

    private var meetings: [Meeting] = []
    private var armed: Task<Void, Never>?
    private var poller: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []

    /// Called on the main actor when a meeting's moment arrives.
    var onFire: ((Meeting) -> Void)?
    /// Called whenever the upcoming meeting changes, so the menu can update.
    var onUpcomingChanged: (() -> Void)?

    private(set) var upcoming: Meeting?
    private(set) var lastRefresh: Date?
    private(set) var lastError: String?

    init(settings: SettingsStore, service: CalendarService, firedLog: FiredLog = FiredLog()) {
        self.settings = settings
        self.service = service
        self.firedLog = firedLog
    }

    func start() {
        if observers.isEmpty {
            observeSystemChanges()
        }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = await MainActor.run { self?.settings.value.pollInterval ?? 300 }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Refresh immediately and restart the polling cadence from now.
    ///
    /// Used by "Refresh Now" and after the interval changes - otherwise a new
    /// interval would not take effect until the current sleep finished.
    func restartPolling() {
        poller?.cancel()
        start()
    }

    func stop() {
        poller?.cancel()
        armed?.cancel()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    /// Re-fetch the window and re-arm. Safe to call at any time.
    func refresh() async {
        let now = Date.now
        // Reach slightly into the past so a meeting whose moment passed during
        // sleep is still in the window and can be caught up.
        let fetched = await service.meetings(
            from: now.addingTimeInterval(-MeetingSchedule.overdueGrace),
            to: now.addingTimeInterval(settings.value.lookahead)
        )
        meetings = fetched
        lastRefresh = now
        arm()
    }

    /// Cancel any pending timer and schedule the next one.
    private func arm() {
        armed?.cancel()

        guard let next = MeetingSchedule.next(
            in: meetings,
            now: .now,
            leadOffset: settings.value.leadOffset,
            fired: firedLog.keys,
            alertUnconfirmed: settings.value.alertUnconfirmedInvitations
        ) else {
            setUpcoming(nil)
            return
        }
        setUpcoming(next)

        let fireTime = MeetingSchedule.fireTime(
            for: next,
            leadOffset: settings.value.leadOffset
        )
        let delay = max(0, fireTime.timeIntervalSinceNow)

        armed = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.fire(next) }
        }
    }

    private func fire(_ meeting: Meeting) {
        // Record before presenting: if presentation throws or the app dies, a
        // duplicate alarm is worse than none, and the meeting is still visible
        // in the menu.
        firedLog.record(meeting)
        Self.log.info("firing alert for meeting starting \(meeting.start, privacy: .private)")
        onFire?(meeting)
        arm()
    }

    // MARK: - System changes

    private func observeSystemChanges() {
        // Timers do not run while asleep, so re-arm - and catch up - on wake.
        let wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        observers.append(wake)

        // A time-zone change moves every meeting relative to the clock.
        let timeZone = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.arm() }
        }
        observers.append(timeZone)
    }

    private func setUpcoming(_ meeting: Meeting?) {
        guard upcoming != meeting else { return }
        upcoming = meeting
        onUpcomingChanged?()
    }
}
