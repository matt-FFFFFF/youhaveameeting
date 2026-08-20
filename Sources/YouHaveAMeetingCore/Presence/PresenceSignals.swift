/// What the machine looks like it is doing right now.
struct PresenceSignals: Equatable, Sendable {
    var microphoneInUse = false
    var cameraInUse = false
    var screenBeingShared = false
    /// The manual override. Always believed, whatever the sensors say.
    var mode: PresenceMode = .normal
}
