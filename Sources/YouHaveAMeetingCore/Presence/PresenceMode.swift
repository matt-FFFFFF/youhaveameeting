/// The manual override, chosen from the menu or the settings window.
///
/// An enum rather than a boolean: these are mutually exclusive states, and more
/// are expected. No case may result in showing nothing at all - an alert you
/// never see is the failure this app exists to prevent.
enum PresenceMode: String, Codable, CaseIterable, Sendable {
    /// No override. Sensors decide.
    case normal
    /// Downgrade to a corner banner.
    case presenting

    var title: String {
        switch self {
        case .normal: "Normal"
        case .presenting: "Presenting"
        }
    }
}
