import CoreAudio
import CoreGraphics
import CoreMediaIO
import Foundation
import os

/// Reads presence signals on demand.
///
/// Queried only when an alert is about to fire rather than polled in the
/// background: the answer is only needed at that instant, and not polling keeps
/// idle cost at zero.
enum PresenceMonitor {
    private static let log = Logger(subsystem: "app.youhaveameeting", category: "presence")

    static func currentSignals(settings: Settings) -> PresenceSignals {
        PresenceSignals(
            microphoneInUse: settings.silenceWhenMicActive && isMicrophoneInUse(),
            // Only touched when enabled: querying CoreMediaIO devices is more
            // intrusive than reading audio device properties.
            cameraInUse: settings.silenceWhenCameraActive && isCameraInUse(),
            screenBeingShared: settings.silenceWhenSharing && isScreenBeingShared(),
            mode: settings.presenceMode
        )
    }

    // MARK: - Microphone

    /// True when any input device is running for some process.
    ///
    /// This reads device properties only. It does not open a stream and does
    /// not require microphone permission.
    static func isMicrophoneInUse() -> Bool {
        audioDevices().contains { device in
            hasInputStreams(device) && isRunningSomewhere(device)
        }
    }

    private static func audioDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        ) == noErr else { return [] }
        return devices
    }

    private static func hasInputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size > 0
        else { return false }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }

        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else {
            return false
        }
        let list = buffer.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).contains { $0.mNumberChannels > 0 }
    }

    private static func isRunningSomewhere(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else {
            return false
        }
        return running != 0
    }

    // MARK: - Camera

    static func isCameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return false }

        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices
        ) == noErr else { return false }

        return devices.contains { isCameraRunning($0) }
    }

    private static func isCameraRunning(_ device: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        var running: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(
            device, &address, 0, nil, size, &used, &running
        ) == noErr else { return false }
        return running != 0
    }

    // MARK: - Screen sharing

    /// Best effort. There is no public API for "is another app capturing the
    /// screen", so this looks for the floating indicator windows the common
    /// conferencing apps create while sharing.
    ///
    /// Window *titles* are redacted unless the app holds Screen Recording
    /// permission; owner names are always visible. Without that permission this
    /// degrades to owner-only matching, which is why the manual Presenting
    /// toggle exists as the dependable path.
    /// Whether this process may read other apps' window titles.
    ///
    /// Uses the documented preflight rather than inferring from redacted
    /// titles. Note that reading the window list never triggers a TCC check,
    /// which is why an app that only calls CGWindowListCopyWindowInfo never
    /// appears in the Screen Recording list at all - it has never asked.
    static func canReadWindowTitles() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Ask for Screen Recording access.
    ///
    /// This is what registers the app in System Settings > Privacy & Security >
    /// Screen & System Audio Recording. macOS shows the prompt once; after
    /// that the entry exists and can be toggled there. The permission only
    /// takes effect after a relaunch.
    @discardableResult
    static func requestScreenCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Diagnostic: every on-screen window with its owner and title.
    ///
    /// Used to find the real sharing-indicator markers rather than guessing at
    /// them. Titles are blank without Screen Recording permission.
    static func windowInventory() -> [String] {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        return windows.compactMap { window in
            let owner = window[kCGWindowOwnerName as String] as? String ?? "?"
            let title = window[kCGWindowName as String] as? String ?? ""
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            guard !owner.isEmpty else { return nil }
            return "layer \(layer)  \(owner)  |  \(title)"
        }
    }

    static func isScreenBeingShared() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        let pairs = windows.map { window in
            (
                owner: window[kCGWindowOwnerName as String] as? String ?? "",
                title: window[kCGWindowName as String] as? String ?? ""
            )
        }
        return isSharing(windows: pairs)
    }

    /// Pure matcher, so the markers can be tested against strings captured
    /// from real sharing sessions rather than guessed at.
    static func isSharing(windows: [(owner: String, title: String)]) -> Bool {
        windows.contains { window in
            if sharingTitleFragments.contains(where: {
                window.title.localizedCaseInsensitiveContains($0)
            }) {
                return true
            }
            return ownerMarkers.contains { $0.matches(owner: window.owner, title: window.title) }
        }
    }

    /// Phrasing used by the indicator bar, whichever app shows it.
    ///
    /// Chromium browsers vary the ending - "your screen", "a window.", "a tab."
    /// - so match the stem they share rather than one variant.
    private static let sharingTitleFragments = [
        "is sharing your screen",
        "is sharing a window",
        "is sharing a tab",
        "is sharing your"
    ]

    /// Each marker is one app's "you are sharing" indicator, for apps that do
    /// not use the phrasing above.
    private struct ShareMarker {
        let owner: String
        /// Any of these in the window title confirms sharing. Empty means the
        /// owner alone is enough.
        let titles: [String]

        func matches(owner candidateOwner: String, title: String) -> Bool {
            guard !candidateOwner.isEmpty,
                  candidateOwner.localizedCaseInsensitiveContains(owner)
            else { return false }
            guard !titles.isEmpty else { return true }
            return titles.contains { title.localizedCaseInsensitiveContains($0) }
        }
    }

    private static let ownerMarkers: [ShareMarker] = [
        // Zoom's floating share toolbar.
        ShareMarker(owner: "zoom", titles: ["as_toolbar", "sharing", "screen share"]),
        ShareMarker(owner: "Microsoft Teams", titles: ["sharing", "you're presenting"]),
        // Apple's own screen sharing has no other purpose.
        ShareMarker(owner: "Screen Sharing", titles: [])
    ]
}
