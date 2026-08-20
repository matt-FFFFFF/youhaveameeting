import Foundation

/// A single concrete meeting occurrence. Recurring events are expanded by the
/// provider, so every `Meeting` has real start and end dates.
struct Meeting: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let organiser: String?
    let joinURL: URL?
    let accountID: String

    init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        organiser: String? = nil,
        joinURL: URL? = nil,
        accountID: String = ""
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.organiser = organiser
        self.joinURL = joinURL
        self.accountID = accountID
    }
}
