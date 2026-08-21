/// The manual override, chosen from the menu or the settings window.
///
/// Tri-state rather than a boolean: these are mutually exclusive statements of
/// intent, and two of them point in opposite directions. No case may result in
/// showing nothing at all - an alert you never see is the failure this app
/// exists to prevent.
enum PresenceMode: String, Codable, CaseIterable, Sendable {
    /// No override. Sensors decide.
    case automatic
    /// Downgrade to a corner banner, whatever the sensors say.
    case presenting
    /// Take over the screen, even when the sensors think you are presenting.
    case fullScreen

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .presenting: "Presenting"
        case .fullScreen: "Full Screen"
        }
    }

    /// Falls back to `.automatic` for any spelling this build does not know.
    ///
    /// `Settings` decodes by hand so that a file written by another build keeps
    /// the values it does contain; an unrecognised mode string would otherwise
    /// throw and take every other setting down with it. This covers both
    /// `normal`, which is what `automatic` was called before `fullScreen`
    /// existed, and any mode a future build adds.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PresenceMode(rawValue: raw) ?? .automatic
    }
}
