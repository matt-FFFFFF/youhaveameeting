/// Decides how loudly an alert may present.
///
/// Pure, so the whole truth table is testable. Note that no combination yields
/// silence: the quietest outcome is a banner. An alert you never see is the
/// failure this app exists to prevent.
enum SilencePolicy {
    static func style(for signals: PresenceSignals, settings: Settings) -> AlertStyle {
        // The manual mode beats every inferred signal and every per-signal
        // setting: it is a direct statement of intent.
        if signals.mode == .presenting {
            return .banner
        }

        if settings.silenceWhenMicActive, signals.microphoneInUse {
            return .banner
        }
        if settings.silenceWhenCameraActive, signals.cameraInUse {
            return .banner
        }
        if settings.silenceWhenSharing, signals.screenBeingShared {
            return .banner
        }

        return .takeover
    }

    /// Short explanation for the menu, so the current state is never a mystery.
    static func reason(for signals: PresenceSignals, settings: Settings) -> String? {
        if signals.mode == .presenting {
            return "Presenting"
        }
        if settings.silenceWhenMicActive, signals.microphoneInUse {
            return "Microphone in use"
        }
        if settings.silenceWhenCameraActive, signals.cameraInUse {
            return "Camera in use"
        }
        if settings.silenceWhenSharing, signals.screenBeingShared {
            return "Screen being shared"
        }
        return nil
    }
}
