import Foundation

/// When the alert chimes while it is still unacknowledged.
///
/// Pure arithmetic, kept separate from the presenter so the ladder can be
/// tested without putting a window on screen.
enum EscalationSchedule {
    /// Seconds after the alert appears at which each of the first chimes fires.
    static let offsets: [TimeInterval] = [0, 15, 30, 60]
    /// Once the ramp is exhausted the chime repeats at this interval forever.
    static let repeatInterval: TimeInterval = 60

    /// Elapsed time from the alert appearing to chime `index` (0-based).
    static func offset(forChime index: Int) -> TimeInterval {
        precondition(index >= 0, "chime index must not be negative")
        guard index >= offsets.count else { return offsets[index] }
        let beyondRamp = TimeInterval(index - offsets.count + 1) * repeatInterval
        // offsets is a non-empty literal, so last is always present.
        return (offsets.last ?? 0) + beyondRamp
    }

    /// How long to wait after chime `index - 1` before sounding chime `index`.
    static func gap(beforeChime index: Int) -> TimeInterval {
        guard index > 0 else { return 0 }
        return offset(forChime: index) - offset(forChime: index - 1)
    }
}
