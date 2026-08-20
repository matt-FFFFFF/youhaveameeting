import Foundation
import Testing
@testable import YouHaveAMeetingCore

private func iso(_ string: String) -> Date {
    guard let date = EventDateParsing.offsetDate(string) else {
        Issue.record("bad fixture date \(string)")
        return .distantPast
    }
    return date
}

@Suite("MeetingLinkParser")
struct MeetingLinkParserTests {
    private let parser = MeetingLinkParser()

    @Test("recognises the default providers")
    func defaults() {
        #expect(
            parser.firstLink(in: "join at https://meet.google.com/abc-defg-hij today")?
                .absoluteString == "https://meet.google.com/abc-defg-hij"
        )
        #expect(
            parser.firstLink(in: "https://teams.microsoft.com/l/meetup-join/19%3ameeting")?
                .absoluteString == "https://teams.microsoft.com/l/meetup-join/19%3ameeting"
        )
        #expect(
            parser.firstLink(in: "https://acme.zoom.us/j/9876543210?pwd=xyz")?
                .absoluteString == "https://acme.zoom.us/j/9876543210?pwd=xyz"
        )
    }

    @Test("ignores unrelated links")
    func ignoresOtherLinks() {
        #expect(parser.firstLink(in: "see https://example.com/agenda") == nil)
    }

    @Test("Webex is available but off by default")
    func webexOptional() {
        let webex = "https://acme.webex.com/meet/matt"
        #expect(parser.firstLink(in: webex) == nil)

        let withWebex = MeetingLinkParser(
            providers: MeetingLinkProvider.defaults + MeetingLinkProvider.optional.map {
                var provider = $0
                provider.isEnabled = true
                return provider
            }
        )
        #expect(withWebex.firstLink(in: webex)?.absoluteString == webex)
    }

    @Test("field order sets priority")
    func fieldPriority() {
        let url = parser.firstLink(in: [
            "https://acme.zoom.us/j/111",
            "https://meet.google.com/abc-defg-hij"
        ])
        #expect(url?.absoluteString == "https://acme.zoom.us/j/111")
    }

    @Test("a disabled provider never matches")
    func disabledProvider() {
        let providers = MeetingLinkProvider.defaults.map { provider -> MeetingLinkProvider in
            var copy = provider
            if copy.id == "zoom" {
                copy.isEnabled = false
            }
            return copy
        }
        let parser = MeetingLinkParser(providers: providers)
        #expect(parser.firstLink(in: "https://acme.zoom.us/j/111") == nil)
        #expect(parser.firstLink(in: "https://meet.google.com/abc-defg-hij") != nil)
    }

    @Test("an invalid pattern is skipped, not fatal")
    func invalidPattern() {
        let broken = MeetingLinkProvider(id: "broken", name: "Broken", pattern: "([unclosed")
        let parser = MeetingLinkParser(providers: [broken] + MeetingLinkProvider.defaults)
        #expect(parser.firstLink(in: "https://meet.google.com/abc-defg-hij") != nil)
    }

    @Test("custom providers can be added")
    func customProvider() {
        let jitsi = MeetingLinkProvider(
            id: "jitsi",
            name: "Self-hosted Jitsi",
            pattern: #"https://meet\.acme\.internal/[^\s"'<>]+"#
        )
        let parser = MeetingLinkParser(providers: [jitsi])
        #expect(
            parser.firstLink(in: "https://meet.acme.internal/standup")?.absoluteString
                == "https://meet.acme.internal/standup"
        )
    }
}

@Suite("Google decoding")
struct GoogleDecodingTests {
    private static let payload = Data("""
    {"items":[
      {"id":"ev1","summary":"Standup",
       "start":{"dateTime":"2026-08-20T09:00:00+01:00"},
       "end":{"dateTime":"2026-08-20T09:15:00+01:00"},
       "organizer":{"email":"alice@example.com","displayName":"Alice"},
       "conferenceData":{"entryPoints":[
         {"entryPointType":"more","uri":"https://meet.google.com/tel/123"},
         {"entryPointType":"video","uri":"https://meet.google.com/abc-defg-hij"}]}},
      {"id":"ev2","summary":"Offsite","start":{"date":"2026-08-21"},"end":{"date":"2026-08-22"}},
      {"id":"ev3","summary":"Zoom sync",
       "start":{"dateTime":"2026-08-20T14:00:00Z"},
       "end":{"dateTime":"2026-08-20T14:30:00Z"},
       "location":"https://acme.zoom.us/j/9876543210?pwd=xyz"},
      {"id":"ev4","summary":"No link",
       "start":{"dateTime":"2026-08-20T16:00:00Z"},
       "end":{"dateTime":"2026-08-20T16:30:00Z"}}
    ]}
    """.utf8)

    private var meetings: [Meeting] {
        GoogleCalendarProvider.decode(Self.payload, accountID: "acc", parser: MeetingLinkParser())
    }

    @Test("skips all-day events")
    func skipsAllDay() {
        #expect(meetings.map(\.id) == ["ev1", "ev3", "ev4"])
    }

    @Test("prefers the video conference entry point")
    func videoEntryPoint() {
        #expect(
            meetings.first?.joinURL?.absoluteString == "https://meet.google.com/abc-defg-hij"
        )
    }

    @Test("falls back to parsing the location")
    func locationFallback() {
        let zoom = meetings.first { $0.id == "ev3" }
        #expect(zoom?.joinURL?.absoluteString == "https://acme.zoom.us/j/9876543210?pwd=xyz")
    }

    @Test("keeps events that have no join link")
    func noLink() {
        let event = meetings.first { $0.id == "ev4" }
        #expect(event != nil)
        #expect(event?.joinURL == nil)
    }

    @Test("parses offset timestamps")
    func timestamps() {
        #expect(meetings.first?.start == iso("2026-08-20T09:00:00+01:00"))
        #expect(meetings.first?.organiser == "Alice")
    }
}

@Suite("Graph decoding")
struct GraphDecodingTests {
    private static let payload = Data("""
    {"value":[
      {"id":"g1","subject":"Roadmap","isAllDay":false,
       "start":{"dateTime":"2026-08-20T13:00:00.0000000","timeZone":"UTC"},
       "end":{"dateTime":"2026-08-20T14:00:00.0000000","timeZone":"UTC"},
       "onlineMeeting":{"joinUrl":"https://teams.microsoft.com/l/meetup-join/abc"},
       "organizer":{"emailAddress":{"name":"Bob","address":"bob@example.com"}}},
      {"id":"g2","subject":"Holiday","isAllDay":true,
       "start":{"dateTime":"2026-08-21T00:00:00.0000000","timeZone":"UTC"},
       "end":{"dateTime":"2026-08-22T00:00:00.0000000","timeZone":"UTC"}},
      {"id":"g3","subject":"Legacy link","isAllDay":false,
       "start":{"dateTime":"2026-08-20T15:00:00.0000000","timeZone":"UTC"},
       "end":{"dateTime":"2026-08-20T15:30:00.0000000","timeZone":"UTC"},
       "bodyPreview":"dial in via https://acme.zoom.us/j/555"}
    ]}
    """.utf8)

    private var meetings: [Meeting] {
        GraphCalendarProvider.decode(Self.payload, accountID: "acc", parser: MeetingLinkParser())
    }

    @Test("skips all-day events")
    func skipsAllDay() {
        #expect(meetings.map(\.id) == ["g1", "g3"])
    }

    @Test("uses onlineMeeting.joinUrl")
    func joinURL() {
        #expect(
            meetings.first?.joinURL?.absoluteString
                == "https://teams.microsoft.com/l/meetup-join/abc"
        )
    }

    @Test("parses the UTC timestamps requested via the Prefer header")
    func timestamps() {
        #expect(meetings.first?.start == iso("2026-08-20T13:00:00Z"))
        #expect(meetings.first?.organiser == "Bob")
    }

    @Test("falls back to parsing the body preview")
    func bodyFallback() {
        #expect(meetings.last?.joinURL?.absoluteString == "https://acme.zoom.us/j/555")
    }
}

@Suite("CalendarService merge")
struct CalendarMergeTests {
    private func meeting(_ id: String, link: String?) -> Meeting {
        Meeting(
            id: id,
            title: "Weekly sync",
            start: iso("2026-08-20T10:00:00Z"),
            end: iso("2026-08-20T10:30:00Z"),
            joinURL: link.flatMap(URL.init(string:)),
            accountID: id
        )
    }

    @Test("collapses the same meeting from two accounts")
    func dedupes() {
        let merged = CalendarService.merge([
            meeting("a", link: nil),
            meeting("b", link: "https://meet.google.com/abc-defg-hij")
        ])
        #expect(merged.count == 1)
    }

    @Test("keeps the copy that has a join link, whichever arrives first")
    func prefersJoinable() {
        let linkFirst = CalendarService.merge([
            meeting("b", link: "https://meet.google.com/abc-defg-hij"),
            meeting("a", link: nil)
        ])
        #expect(linkFirst.first?.joinURL != nil)

        let linkSecond = CalendarService.merge([
            meeting("a", link: nil),
            meeting("b", link: "https://meet.google.com/abc-defg-hij")
        ])
        #expect(linkSecond.first?.joinURL != nil)
    }

    @Test("returns meetings in start order")
    func sorted() {
        let later = Meeting(
            id: "z",
            title: "Later",
            start: iso("2026-08-20T12:00:00Z"),
            end: iso("2026-08-20T12:30:00Z")
        )
        let merged = CalendarService.merge([later, meeting("a", link: nil)])
        #expect(merged.map(\.title) == ["Weekly sync", "Later"])
    }
}
