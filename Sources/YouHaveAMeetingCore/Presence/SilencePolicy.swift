/// What the next alert will do, and why.
struct SilenceDecision: Equatable, Sendable {
    var style: AlertStyle
    /// Why alerts are quiet, for the menu and the log. `nil` when they are not:
    /// the full-screen takeover is the ordinary outcome and needs no excuse.
    var reason: String?
}

/// Decides how loudly an alert may present.
///
/// Pure, so the whole truth table is testable. Style and reason are decided in
/// one pass rather than by two cascades that could come to disagree. Note that
/// no combination yields silence: the quietest outcome is a banner. An alert
/// you never see is the failure this app exists to prevent.
enum SilencePolicy {
    static func decide(for signals: PresenceSignals, settings: Settings) -> SilenceDecision {
        // The manual mode beats every inferred signal and every per-signal
        // setting, in both directions: it is a direct statement of intent.
        switch signals.mode {
        case .presenting:
            return SilenceDecision(style: .banner, reason: "Presenting")
        case .fullScreen:
            return SilenceDecision(style: .takeover)
        case .automatic:
            break
        }

        if settings.silenceWhenMicActive, signals.microphoneInUse {
            return SilenceDecision(style: .banner, reason: "Microphone in use")
        }
        if settings.silenceWhenCameraActive, signals.cameraInUse {
            return SilenceDecision(style: .banner, reason: "Camera in use")
        }
        if settings.silenceWhenSharing, signals.screenBeingShared {
            return SilenceDecision(style: .banner, reason: "Screen being shared")
        }

        return SilenceDecision(style: .takeover)
    }
}
