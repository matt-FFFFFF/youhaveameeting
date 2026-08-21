import Foundation
import Testing
@testable import YouHaveAMeetingCore

private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func meeting(
    _ id: String,
    minutesFromBase: Double,
    response: MeetingResponse = .accepted
) -> Meeting {
    Meeting(
        id: id,
        title: id,
        start: base.addingTimeInterval(minutesFromBase * 60),
        end: base.addingTimeInterval((minutesFromBase + 30) * 60),
        response: response
    )
}

@Suite("MeetingSchedule")
struct MeetingScheduleTests {
    @Test("picks the earliest meeting still ahead")
    func earliestAhead() {
        let next = MeetingSchedule.next(
            in: [meeting("late", minutesFromBase: 30), meeting("soon", minutesFromBase: 10)],
            now: base,
            leadOffset: 0,
            fired: []
        )
        #expect(next?.id == "soon")
    }

    @Test("skips meetings that already alarmed")
    func skipsFired() {
        let soon = meeting("soon", minutesFromBase: 10)
        let next = MeetingSchedule.next(
            in: [soon, meeting("late", minutesFromBase: 30)],
            now: base,
            leadOffset: 0,
            fired: [MeetingSchedule.key(for: soon)]
        )
        #expect(next?.id == "late")
    }

    @Test("catches up a meeting missed while asleep")
    func catchesUpAfterSleep() {
        // Fire time was two minutes ago - inside the grace window.
        let next = MeetingSchedule.next(
            in: [meeting("missed", minutesFromBase: -2)],
            now: base,
            leadOffset: 0,
            fired: []
        )
        #expect(next?.id == "missed")
    }

    @Test("ignores meetings long past")
    func ignoresStale() {
        let next = MeetingSchedule.next(
            in: [meeting("ancient", minutesFromBase: -60)],
            now: base,
            leadOffset: 0,
            fired: []
        )
        #expect(next == nil)
    }

    @Test("a negative lead offset fires early and shifts the grace window")
    func leadOffset() {
        let soon = meeting("soon", minutesFromBase: 10)
        #expect(
            MeetingSchedule.fireTime(for: soon, leadOffset: -60)
                == soon.start.addingTimeInterval(-60)
        )

        // Starts in 4 minutes; with a 5-minute lead the moment already passed,
        // but it is within grace so it must still alarm.
        let imminent = meeting("imminent", minutesFromBase: 4)
        let next = MeetingSchedule.next(
            in: [imminent],
            now: base,
            leadOffset: -300,
            fired: []
        )
        #expect(next?.id == "imminent")
    }

    @Test("a moved meeting alarms again")
    func movedMeetingIsNotSuppressed() {
        let original = meeting("standup", minutesFromBase: 10)
        let moved = Meeting(
            id: "standup",
            title: "standup",
            start: original.start.addingTimeInterval(3600),
            end: original.end.addingTimeInterval(3600)
        )
        #expect(MeetingSchedule.key(for: original) != MeetingSchedule.key(for: moved))

        let next = MeetingSchedule.next(
            in: [moved],
            now: base,
            leadOffset: 0,
            fired: [MeetingSchedule.key(for: original)]
        )
        #expect(next?.id == "standup")
    }

    @Test("returns nothing when everything has alarmed")
    func allFired() {
        let one = meeting("one", minutesFromBase: 10)
        let next = MeetingSchedule.next(
            in: [one],
            now: base,
            leadOffset: 0,
            fired: [MeetingSchedule.key(for: one)]
        )
        #expect(next == nil)
    }
}

@Suite("FiredLog")
@MainActor
struct FiredLogTests {
    private func temporaryLog() -> FiredLog {
        let url = URL.temporaryDirectory.appending(path: "fired-\(UUID().uuidString).json")
        return FiredLog(fileURL: url)
    }

    @Test("records and recognises a meeting")
    func records() {
        let log = temporaryLog()
        let one = meeting("one", minutesFromBase: 10)
        #expect(!log.contains(one))
        log.record(one, at: base)
        #expect(log.contains(one))
    }

    @Test("drops entries old enough that they can never match again")
    func prunes() {
        let log = temporaryLog()
        let one = meeting("one", minutesFromBase: 10)
        log.record(one, at: base)
        log.prune(now: base.addingTimeInterval(86400 * 3))
        #expect(!log.contains(one))
    }
}

@Suite("Invitation response gating")
struct InvitationResponseTests {
    private func next(_ meetings: [Meeting], alertUnconfirmed: Bool = true) -> Meeting? {
        MeetingSchedule.next(
            in: meetings,
            now: base,
            leadOffset: 0,
            fired: [],
            alertUnconfirmed: alertUnconfirmed
        )
    }

    @Test("a declined meeting never fires, whatever the setting says")
    func declinedNeverFires() {
        let declined = [meeting("declined", minutesFromBase: 10, response: .declined)]
        #expect(next(declined) == nil)
        #expect(next(declined, alertUnconfirmed: false) == nil)
    }

    @Test("a declined meeting is skipped over, not treated as the end of the list")
    func skipsToTheNextAcceptable() {
        let picked = next([
            meeting("declined", minutesFromBase: 10, response: .declined),
            meeting("accepted", minutesFromBase: 20)
        ])
        #expect(picked?.id == "accepted")
    }

    @Test("tentative and unanswered follow the setting")
    func unconfirmedFollowsSetting() {
        for response in [MeetingResponse.tentative, .needsAction] {
            let meetings = [meeting("maybe", minutesFromBase: 10, response: response)]
            #expect(next(meetings)?.id == "maybe")
            #expect(next(meetings, alertUnconfirmed: false) == nil)
        }
    }

    @Test("turning the setting off still fires for accepted meetings")
    func acceptedAlwaysFires() {
        let picked = next(
            [meeting("accepted", minutesFromBase: 10)],
            alertUnconfirmed: false
        )
        #expect(picked?.id == "accepted")
    }
}
