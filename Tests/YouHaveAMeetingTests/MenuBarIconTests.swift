import Foundation
import Testing
@testable import YouHaveAMeetingCore

private let base = Date(timeIntervalSince1970: 1_800_000_000)

@Suite("MenuBarIconState")
struct MenuBarIconStateTests {
    @Test("an alert on screen outranks every other state")
    func alertingWins() {
        let state = MenuBarIconState.current(
            fireTime: base,
            now: base,
            isAlerting: true,
            isQuiet: true
        )
        #expect(state == .alerting)
    }

    @Test("quiet outranks an approaching meeting")
    func quietBeatsImminent() {
        let state = MenuBarIconState.current(
            fireTime: base.addingTimeInterval(60),
            now: base,
            isAlerting: false,
            isQuiet: true
        )
        #expect(state == .quiet)
    }

    @Test("warns once inside the run-up to the alarm")
    func imminentInsideLead() {
        let state = MenuBarIconState.current(
            fireTime: base.addingTimeInterval(MenuBarIconState.imminentLead - 1),
            now: base,
            isAlerting: false,
            isQuiet: false
        )
        #expect(state == .imminent)
    }

    @Test("stays imminent once the fire time has passed")
    func imminentAfterFireTime() {
        let state = MenuBarIconState.current(
            fireTime: base.addingTimeInterval(-30),
            now: base,
            isAlerting: false,
            isQuiet: false
        )
        #expect(state == .imminent)
    }

    @Test("idle further out than the run-up, and with nothing scheduled")
    func idleOtherwise() {
        let far = MenuBarIconState.current(
            fireTime: base.addingTimeInterval(MenuBarIconState.imminentLead + 1),
            now: base,
            isAlerting: false,
            isQuiet: false
        )
        #expect(far == .idle)

        let empty = MenuBarIconState.current(
            fireTime: nil,
            now: base,
            isAlerting: false,
            isQuiet: false
        )
        #expect(empty == .idle)
    }

    @Test("the only time-driven change is the moment the warning starts")
    func transitionMoment() {
        let fire = base.addingTimeInterval(3600)
        #expect(
            MenuBarIconState.nextTimeDrivenChange(fireTime: fire, now: base)
                == fire.addingTimeInterval(-MenuBarIconState.imminentLead)
        )
    }

    @Test("nothing to wait for once the warning has begun, or with no meeting")
    func noTransitionPending() {
        #expect(
            MenuBarIconState.nextTimeDrivenChange(
                fireTime: base.addingTimeInterval(60),
                now: base
            ) == nil
        )
        #expect(MenuBarIconState.nextTimeDrivenChange(fireTime: nil, now: base) == nil)
    }
}

@Suite("BellGlyph")
struct BellGlyphTests {
    /// The mark is drawn from the same geometry at both sizes, so a change
    /// that pushed it outside its declared bounds would silently clip in the
    /// menu bar and misalign in the app icon.
    @Test("every path stays inside the declared bounds")
    func staysInBounds() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let ringed = BellGlyph.paths(in: frame, withRings: true)
        let padding = BellGlyph.strokeWidth * ringed.unit

        for path in [ringed.body, ringed.clapper, ringed.rings, ringed.slash] {
            #expect(frame.insetBy(dx: -padding, dy: -padding).contains(path.boundingBox))
        }
    }

    @Test("adding the rings does not change the space the mark occupies")
    func ringsDoNotResizeTheMark() {
        let frame = CGRect(x: 0, y: 0, width: 18, height: 18)
        let plain = BellGlyph.paths(in: frame).unit
        let ringed = BellGlyph.paths(in: frame, withRings: true).unit
        // Within 5%: the bell may give up a little room for the arcs, but a
        // visible resize would make the menu-bar glyph jump between states.
        #expect(abs(plain - ringed) / plain < 0.05)
    }
}
