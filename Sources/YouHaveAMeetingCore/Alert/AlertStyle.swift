/// How forcefully an alert is shown. `SilencePolicy` chooses between these.
enum AlertStyle: Equatable, Sendable {
    /// Full-screen dimmed takeover on every display, with escalating sound.
    case takeover
    /// Small corner banner, silent. Used while in a call or presenting.
    case banner
}

/// What the user did with an alert.
enum AlertOutcome: Equatable, Sendable {
    case joined
    case dismissed
    case snoozed(seconds: Int)
}
