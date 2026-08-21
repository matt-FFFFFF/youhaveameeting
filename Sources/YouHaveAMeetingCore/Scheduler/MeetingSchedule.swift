import Foundation

/// Pure selection logic for "what should fire next", separated from the timer
/// so it can be tested without waiting for wall-clock time.
enum MeetingSchedule {
    /// How long after a missed fire time a meeting is still worth alarming.
    ///
    /// Timers do not fire while the Mac is asleep, so after a lid-open there
    /// may be a meeting whose moment passed. Alarming a few minutes late is
    /// useful; alarming for something an hour gone is noise.
    static let overdueGrace: TimeInterval = 300

    static func fireTime(for meeting: Meeting, leadOffset: TimeInterval) -> Date {
        meeting.start.addingTimeInterval(leadOffset)
    }

    /// The meeting that should alarm next, if any.
    ///
    /// Includes meetings whose fire time has just passed, so a machine waking
    /// from sleep still alarms rather than silently skipping.
    ///
    /// Meetings the user has turned down are skipped here rather than dropped
    /// on the way in, so they still appear in the menu - the user has not
    /// stopped caring that the meeting exists, only that it should interrupt
    /// them.
    static func next(
        in meetings: [Meeting],
        now: Date,
        leadOffset: TimeInterval,
        fired: Set<String>,
        alertUnconfirmed: Bool = true,
        grace: TimeInterval = overdueGrace
    ) -> Meeting? {
        meetings
            .filter { $0.response.shouldAlert(includingUnconfirmed: alertUnconfirmed) }
            .filter { !fired.contains(key(for: $0)) }
            .filter { fireTime(for: $0, leadOffset: leadOffset) >= now.addingTimeInterval(-grace) }
            .min { lhs, rhs in
                fireTime(for: lhs, leadOffset: leadOffset)
                    < fireTime(for: rhs, leadOffset: leadOffset)
            }
    }

    /// Identity for dedupe. Includes the start time so a moved meeting alarms
    /// again rather than being suppressed by the old occurrence.
    static func key(for meeting: Meeting) -> String {
        "\(meeting.id)@\(Int(meeting.start.timeIntervalSince1970))"
    }
}
