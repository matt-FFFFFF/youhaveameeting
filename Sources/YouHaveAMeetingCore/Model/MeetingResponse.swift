import Foundation

/// The user's own answer to an invitation, as the calendar reports it.
///
/// Only the user's own row matters. What anyone else answered has no bearing
/// on whether this Mac should alarm, so the providers reduce the attendee list
/// to this one value before it reaches the rest of the app.
///
/// Ordered by how committed the user is, least to most. `CalendarService.merge`
/// relies on that order when the same meeting arrives from two accounts.
enum MeetingResponse: String, Codable, Comparable, Sendable {
    case declined
    case needsAction
    case tentative
    case accepted

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .declined: 0
        case .needsAction: 1
        case .tentative: 2
        case .accepted: 3
        }
    }

    /// Whether a meeting with this response is worth alarming for.
    ///
    /// Declined never is: the user has already said they are not going, so the
    /// takeover is pure noise. Tentative and unanswered are a real judgement
    /// call - plenty of people join meetings they never got round to
    /// accepting - so that one is the user's to make.
    func shouldAlert(includingUnconfirmed: Bool) -> Bool {
        switch self {
        case .declined: false
        case .needsAction, .tentative: includingUnconfirmed
        case .accepted: true
        }
    }
}
