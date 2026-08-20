import Foundation

/// What the menu-bar glyph is saying right now.
///
/// Deriving this is a pure function so the precedence between states is
/// testable without a menu bar, a clock, or a calendar.
enum MenuBarIconState: Equatable, Sendable {
    /// Nothing due soon.
    case idle
    /// Inside the run-up to the next alarm.
    case imminent
    /// An alert is on screen and has not been dealt with.
    case alerting
    /// Alerts would be downgraded to a banner - presenting, or in a call.
    case quiet

    /// How long before the alarm the glyph starts warning.
    ///
    /// Fixed rather than derived from `leadOffset`: the lead offset says when
    /// to interrupt, this says when to give a quiet heads-up first, and a user
    /// who sets the offset to zero still wants the warning.
    static let imminentLead: TimeInterval = 300

    /// Resolve the glyph from everything that could claim it.
    ///
    /// Precedence is deliberate. An alert on screen outranks everything: it is
    /// the loudest fact about the app. Quiet outranks imminent because it
    /// changes what the next alarm will *do*, which matters more than knowing
    /// one is coming.
    static func current(
        fireTime: Date?,
        now: Date,
        isAlerting: Bool,
        isQuiet: Bool
    ) -> MenuBarIconState {
        if isAlerting {
            return .alerting
        }
        if isQuiet {
            return .quiet
        }
        guard let fireTime, fireTime.timeIntervalSince(now) <= imminentLead else {
            return .idle
        }
        return .imminent
    }

    /// When the glyph would change on its own, with nothing else happening.
    ///
    /// Only the idle-to-imminent step is time-driven; every other transition
    /// is caused by an event the app already hears about. Returning the moment
    /// lets the caller sleep until exactly then instead of polling.
    static func nextTimeDrivenChange(fireTime: Date?, now: Date) -> Date? {
        guard let fireTime else { return nil }
        let warning = fireTime.addingTimeInterval(-imminentLead)
        return warning > now ? warning : nil
    }

    var accessibilityDescription: String {
        switch self {
        case .idle: "You Have a Meeting"
        case .imminent: "Meeting starting soon"
        case .alerting: "Meeting alert showing"
        case .quiet: "You Have a Meeting - alerts quiet"
        }
    }
}
