import Testing
@testable import YouHaveAMeetingCore

@Suite("SilencePolicy")
struct SilencePolicyTests {
    private var defaults: Settings { Settings() }

    @Test("a quiet machine gets the full takeover")
    func quiet() {
        #expect(SilencePolicy.style(for: PresenceSignals(), settings: defaults) == .takeover)
        #expect(SilencePolicy.reason(for: PresenceSignals(), settings: defaults) == nil)
    }

    @Test("microphone in use downgrades to a banner by default")
    func microphone() {
        let signals = PresenceSignals(microphoneInUse: true)
        #expect(SilencePolicy.style(for: signals, settings: defaults) == .banner)
        #expect(SilencePolicy.reason(for: signals, settings: defaults) == "Microphone in use")
    }

    @Test("camera alone does not downgrade unless enabled")
    func cameraOptIn() {
        let signals = PresenceSignals(cameraInUse: true)
        #expect(SilencePolicy.style(for: signals, settings: defaults) == .takeover)

        var settings = defaults
        settings.silenceWhenCameraActive = true
        #expect(SilencePolicy.style(for: signals, settings: settings) == .banner)
    }

    @Test("screen sharing downgrades by default")
    func sharing() {
        let signals = PresenceSignals(screenBeingShared: true)
        #expect(SilencePolicy.style(for: signals, settings: defaults) == .banner)
    }

    @Test("a disabled signal is ignored even when active")
    func disabledSignal() {
        var settings = defaults
        settings.silenceWhenMicActive = false
        let signals = PresenceSignals(microphoneInUse: true)
        #expect(SilencePolicy.style(for: signals, settings: settings) == .takeover)
    }

    @Test("the manual toggle wins over every setting")
    func manualOverride() {
        var settings = defaults
        settings.silenceWhenMicActive = false
        settings.silenceWhenCameraActive = false
        settings.silenceWhenSharing = false
        let signals = PresenceSignals(mode: .presenting)
        #expect(SilencePolicy.style(for: signals, settings: settings) == .banner)
        #expect(SilencePolicy.reason(for: signals, settings: settings) == "Presenting")
    }

    @Test("no combination of any signal or mode is ever fully silent")
    func neverSilent() {
        for mic in [false, true] {
            for camera in [false, true] {
                for sharing in [false, true] {
                    for mode in PresenceMode.allCases {
                        let style = SilencePolicy.style(
                            for: PresenceSignals(
                                microphoneInUse: mic,
                                cameraInUse: camera,
                                screenBeingShared: sharing,
                                mode: mode
                            ),
                            settings: defaults
                        )
                        #expect(style == .takeover || style == .banner)
                    }
                }
            }
        }
    }
}

@Suite("Screen share detection")
struct ScreenShareDetectionTests {
    /// Captured from a real Chrome window-share session.
    @Test("matches Chrome sharing a single window")
    func chromeWindowShare() {
        #expect(PresenceMonitor.isSharing(windows: [
            (owner: "Google Chrome", title: "meet.google.com is sharing a window."),
            (owner: "Google Chrome", title: "Meet - Test")
        ]))
    }

    @Test("matches the other Chromium phrasings")
    func chromePhrasings() {
        #expect(PresenceMonitor.isSharing(windows: [
            (owner: "Google Chrome", title: "meet.google.com is sharing your screen.")
        ]))
        #expect(PresenceMonitor.isSharing(windows: [
            (owner: "Google Chrome", title: "teams.microsoft.com is sharing a tab.")
        ]))
    }

    @Test("matches Zoom's share toolbar")
    func zoom() {
        #expect(PresenceMonitor.isSharing(windows: [
            (owner: "zoom.us", title: "as_toolbar")
        ]))
    }

    @Test("an ordinary desktop is not sharing")
    func notSharing() {
        #expect(!PresenceMonitor.isSharing(windows: [
            (owner: "Google Chrome", title: "Meet - Test"),
            (owner: "Window Server", title: "StatusIndicator"),
            (owner: "Control Centre", title: "AudioVideoModule"),
            (owner: "Finder", title: "Desktop")
        ]))
    }

    @Test("blank owners from redacted window lists do not match")
    func redacted() {
        #expect(!PresenceMonitor.isSharing(windows: [
            (owner: "", title: ""),
            (owner: "", title: "")
        ]))
    }
}
