import Testing
@testable import YouHaveAMeetingCore

@Suite("SilencePolicy")
struct SilencePolicyTests {
    private var defaults: Settings { Settings() }

    @Test("a quiet machine gets the full takeover")
    func quiet() {
        let decision = SilencePolicy.decide(for: PresenceSignals(), settings: defaults)
        #expect(decision.style == .takeover)
        #expect(decision.reason == nil)
    }

    @Test("microphone in use downgrades to a banner by default")
    func microphone() {
        let signals = PresenceSignals(microphoneInUse: true)
        let decision = SilencePolicy.decide(for: signals, settings: defaults)
        #expect(decision.style == .banner)
        #expect(decision.reason == "Microphone in use")
    }

    @Test("camera alone does not downgrade unless enabled")
    func cameraOptIn() {
        let signals = PresenceSignals(cameraInUse: true)
        #expect(SilencePolicy.decide(for: signals, settings: defaults).style == .takeover)

        var settings = defaults
        settings.silenceWhenCameraActive = true
        #expect(SilencePolicy.decide(for: signals, settings: settings).style == .banner)
    }

    @Test("screen sharing downgrades by default")
    func sharing() {
        let signals = PresenceSignals(screenBeingShared: true)
        #expect(SilencePolicy.decide(for: signals, settings: defaults).style == .banner)
    }

    @Test("a disabled signal is ignored even when active")
    func disabledSignal() {
        var settings = defaults
        settings.silenceWhenMicActive = false
        let signals = PresenceSignals(microphoneInUse: true)
        #expect(SilencePolicy.decide(for: signals, settings: settings).style == .takeover)
    }

    @Test("Presenting wins over every setting")
    func presentingOverride() {
        var settings = defaults
        settings.silenceWhenMicActive = false
        settings.silenceWhenCameraActive = false
        settings.silenceWhenSharing = false
        let decision = SilencePolicy.decide(
            for: PresenceSignals(mode: .presenting),
            settings: settings
        )
        #expect(decision.style == .banner)
        #expect(decision.reason == "Presenting")
    }

    @Test("Full Screen wins over every sensor that would have quietened it")
    func fullScreenOverride() {
        let signals = PresenceSignals(
            microphoneInUse: true,
            cameraInUse: true,
            screenBeingShared: true,
            mode: .fullScreen
        )
        var settings = defaults
        settings.silenceWhenCameraActive = true
        let decision = SilencePolicy.decide(for: signals, settings: settings)
        #expect(decision.style == .takeover)
        // Nothing quietened the alert, so there is nothing to explain.
        #expect(decision.reason == nil)
    }

    @Test("no combination of any signal or mode is ever fully silent")
    func neverSilent() {
        for mic in [false, true] {
            for camera in [false, true] {
                for sharing in [false, true] {
                    for mode in PresenceMode.allCases {
                        let style = SilencePolicy.decide(
                            for: PresenceSignals(
                                microphoneInUse: mic,
                                cameraInUse: camera,
                                screenBeingShared: sharing,
                                mode: mode
                            ),
                            settings: defaults
                        ).style
                        #expect(style == .takeover || style == .banner)
                    }
                }
            }
        }
    }

    @Test("a reason is given exactly when alerts are quiet")
    func reasonMatchesStyle() {
        for mic in [false, true] {
            for camera in [false, true] {
                for sharing in [false, true] {
                    for mode in PresenceMode.allCases {
                        let decision = SilencePolicy.decide(
                            for: PresenceSignals(
                                microphoneInUse: mic,
                                cameraInUse: camera,
                                screenBeingShared: sharing,
                                mode: mode
                            ),
                            settings: defaults
                        )
                        #expect((decision.reason != nil) == (decision.style == .banner))
                    }
                }
            }
        }
    }
}

@Suite("Presence subscription")
struct PresenceSubscriptionTests {
    private typealias Subscription = PresenceObserver.Subscription

    @Test("Automatic watches whichever signals are switched on")
    func followsTheSettings() {
        var settings = Settings()
        settings.silenceWhenCameraActive = true
        let subscription = Subscription(settings: settings)
        #expect(subscription.microphone)
        #expect(subscription.camera)
    }

    @Test("a signal that is switched off is not watched")
    func skipsDisabledSignals() {
        // The camera default is off, and touching CoreMediaIO at all is more
        // intrusive than reading audio properties.
        #expect(!Subscription(settings: Settings()).camera)

        var settings = Settings()
        settings.silenceWhenMicActive = false
        #expect(!Subscription(settings: settings).microphone)
    }

    @Test("no mode but Automatic watches anything")
    func onlyAutomaticWatches() {
        for mode in PresenceMode.allCases where mode != .automatic {
            var settings = Settings()
            settings.silenceWhenMicActive = true
            settings.silenceWhenCameraActive = true
            settings.presenceMode = mode
            // The mode alone settles the outcome, so a sensor change could not
            // alter the glyph and there is nothing worth subscribing to.
            #expect(Subscription(settings: settings).isEmpty)
        }
    }

    @Test("screen sharing never contributes - it has no signal to watch")
    func sharingIsNotWatchable() {
        var settings = Settings()
        settings.silenceWhenMicActive = false
        settings.silenceWhenCameraActive = false
        settings.silenceWhenSharing = true
        #expect(Subscription(settings: settings).isEmpty)
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
