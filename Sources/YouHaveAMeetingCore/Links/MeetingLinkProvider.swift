import Foundation

/// A named pattern that recognises one conferencing service's join links.
///
/// User-configurable: the built-in set covers the common cases, but corporate
/// deployments use their own hosts (self-hosted Jitsi, a vanity Webex domain),
/// so the list is data rather than code.
struct MeetingLinkProvider: Codable, Equatable, Sendable, Identifiable {
    /// Stable key, used to reconcile edits with the built-in defaults.
    var id: String
    var name: String
    /// Regular expression matching the full join URL.
    var pattern: String
    var isEnabled: Bool

    init(id: String, name: String, pattern: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.isEnabled = isEnabled
    }
}

extension MeetingLinkProvider {
    /// Order matters: the first provider that matches wins, so more specific
    /// patterns come first.
    static let defaults: [MeetingLinkProvider] = [
        MeetingLinkProvider(
            id: "google-meet",
            name: "Google Meet",
            pattern: #"https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}(\?[^\s"'<>]*)?"#
        ),
        MeetingLinkProvider(
            id: "teams",
            name: "Microsoft Teams",
            pattern: #"https://teams\.(microsoft|live)\.com/[^\s"'<>]+"#
        ),
        MeetingLinkProvider(
            id: "zoom",
            name: "Zoom",
            pattern: #"https://[\w.-]*zoom\.us/[jws]/[^\s"'<>]+"#
        )
    ]

    /// Not enabled by default, but offered in settings.
    static let optional: [MeetingLinkProvider] = [
        MeetingLinkProvider(
            id: "webex",
            name: "Webex",
            pattern: #"https://[\w.-]*webex\.com/[^\s"'<>]+"#,
            isEnabled: false
        )
    ]

    static var catalogue: [MeetingLinkProvider] { defaults + optional }
}
