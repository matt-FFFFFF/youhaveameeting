import CoreAudio
import CoreMediaIO
import Foundation
import os

/// Pushes a change when the microphone or camera starts or stops.
///
/// Presence is otherwise sampled on demand: an alert only needs the answer at
/// the instant it fires. The menu-bar glyph is the exception, because it is on
/// screen the whole time - a call starting while nothing else happened would
/// leave it stale until the next menu open. CoreAudio and CoreMediaIO both
/// publish property changes, so this is a subscription rather than a poll and
/// idle cost stays at zero.
///
/// What is watched and what is read are deliberately different for the
/// microphone. The truthful answer comes from the per-process input flags, but
/// those publish no notifications - measured: the flag flips and a registered
/// listener never fires - so subscribing to them would mean polling. Device
/// properties do notify, and a capture cannot start without running some input
/// device, so the devices are the doorbell and the processes are the answer.
/// The one thing this misses is a capture starting on a device already running
/// for playback: no device property changes, so the glyph waits for the next
/// sample. An alert reads presence fresh when it fires, so its decision is
/// never the stale one.
///
/// Screen sharing has no equivalent API - it is read from the window list - so
/// that one signal is still only as fresh as the last sample.
@MainActor
final class PresenceObserver {
    private static let log = Logger(subsystem: "app.youhaveameeting", category: "presence")

    /// Which signals are worth watching right now.
    ///
    /// Outside Automatic the mode decides the outcome by itself, so nothing a
    /// sensor reports could change the glyph and there is nothing to subscribe
    /// to. Each signal is also gated on its own setting, for the same reason
    /// `PresenceMonitor` gates the reads.
    struct Subscription: Equatable {
        var microphone = false
        var camera = false

        var isEmpty: Bool { !microphone && !camera }

        init(settings: Settings) {
            guard settings.presenceMode == .automatic else { return }
            microphone = settings.silenceWhenMicActive
            camera = settings.silenceWhenCameraActive
        }
    }

    private struct AudioListener {
        let object: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private struct CameraListener {
        let object: CMIOObjectID
        let address: CMIOObjectPropertyAddress
        let block: CMIOObjectPropertyListenerBlock
    }

    private let onChange: () -> Void
    private var subscription: Subscription?
    private var audioListeners: [AudioListener] = []
    private var cameraListeners: [CameraListener] = []

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    /// Watch whatever the current settings make relevant.
    ///
    /// Cheap to call on every settings change: it returns immediately unless
    /// the set of signals worth watching actually moved.
    func update(for settings: Settings) {
        let wanted = Subscription(settings: settings)
        guard wanted != subscription else { return }
        subscription = wanted
        resubscribe(wanted)
    }

    /// What is being watched, for the `--presence` diagnostic.
    var summary: String {
        guard let subscription, !subscription.isEmpty else {
            return "nothing - the mode decides without the sensors"
        }
        return "\(audioListeners.count) audio + \(cameraListeners.count) camera properties"
    }

    // MARK: - Subscribing

    /// Re-read the device lists and attach a listener to each device.
    ///
    /// Run again whenever a device appears or disappears: a listener is bound
    /// to one device id, so a microphone plugged in later would otherwise go
    /// unwatched.
    private func resubscribe(_ wanted: Subscription) {
        removeAll()

        if wanted.microphone {
            watch(
                audio: AudioObjectID(kAudioObjectSystemObject),
                at: PresenceMonitor.audioDeviceListAddress,
                rescans: true
            )
            for device in PresenceMonitor.inputDevices() {
                watch(audio: device, at: PresenceMonitor.audioRunningAddress, rescans: false)
            }
        }

        if wanted.camera {
            watch(
                camera: CMIOObjectID(kCMIOObjectSystemObject),
                at: PresenceMonitor.cameraDeviceListAddress,
                rescans: true
            )
            for device in PresenceMonitor.cameraDevices() {
                watch(camera: device, at: PresenceMonitor.cameraRunningAddress, rescans: false)
            }
        }
    }

    private func watch(
        audio object: AudioObjectID,
        at address: AudioObjectPropertyAddress,
        rescans: Bool
    ) {
        var address = address
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.changed(rescans: rescans) }
        }
        let status = AudioObjectAddPropertyListenerBlock(object, &address, .main, block)
        guard status == noErr else {
            Self.log.error("could not watch audio object \(object): \(status)")
            return
        }
        audioListeners.append(AudioListener(object: object, address: address, block: block))
    }

    private func watch(
        camera object: CMIOObjectID,
        at address: CMIOObjectPropertyAddress,
        rescans: Bool
    ) {
        var address = address
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.changed(rescans: rescans) }
        }
        let status = CMIOObjectAddPropertyListenerBlock(object, &address, .main, block)
        guard status == noErr else {
            Self.log.error("could not watch camera object \(object): \(status)")
            return
        }
        cameraListeners.append(CameraListener(object: object, address: address, block: block))
    }

    /// Hopping to a task rather than acting inside the listener block is what
    /// makes a rescan safe: the block has returned before its own registration
    /// is torn down and rebuilt.
    private func changed(rescans: Bool) {
        if rescans, let subscription {
            resubscribe(subscription)
        }
        onChange()
    }

    private func removeAll() {
        for listener in audioListeners {
            var address = listener.address
            let status = AudioObjectRemovePropertyListenerBlock(
                listener.object, &address, .main, listener.block
            )
            if status != noErr {
                Self.log.error("could not unwatch audio object \(listener.object): \(status)")
            }
        }
        audioListeners.removeAll()

        for listener in cameraListeners {
            var address = listener.address
            let status = CMIOObjectRemovePropertyListenerBlock(
                listener.object, &address, .main, listener.block
            )
            if status != noErr {
                Self.log.error("could not unwatch camera object \(listener.object): \(status)")
            }
        }
        cameraListeners.removeAll()
    }
}
