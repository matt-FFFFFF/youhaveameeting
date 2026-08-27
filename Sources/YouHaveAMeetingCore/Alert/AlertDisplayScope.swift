/// Which displays an alert is drawn on.
enum AlertDisplayScope: String, Codable, CaseIterable, Sendable {
    /// A takeover shields every display; a banner appears where the user is
    /// working. How every build before the setting existed behaved.
    case allDisplays
    /// Everything is confined to the primary display - `NSScreen.screens[0]`,
    /// the one carrying the menu bar. Deliberately not `NSScreen.main`, which
    /// follows keyboard focus instead of the hardware arrangement.
    case primaryDisplayOnly

    var title: String {
        switch self {
        case .allDisplays: "Every display"
        case .primaryDisplayOnly: "Primary display only"
        }
    }

    /// Falls back to `.allDisplays` for any spelling this build does not know.
    ///
    /// `Settings` decodes by hand so that a file written by another build keeps
    /// the values it does contain; an unrecognised scope string would otherwise
    /// throw and take every other setting down with it. The same guard as
    /// `PresenceMode`.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AlertDisplayScope(rawValue: raw) ?? .allDisplays
    }
}
