import Foundation

struct GoogleCalendarProvider: CalendarProvider {
    let kind = ProviderKind.google
    let accountID: String
    private let session: AuthSession
    private let parser: MeetingLinkParser
    private let urlSession: URLSession

    init(
        accountID: String,
        session: AuthSession,
        parser: MeetingLinkParser,
        urlSession: URLSession = .shared
    ) {
        self.accountID = accountID
        self.session = session
        self.parser = parser
        self.urlSession = urlSession
    }

    func meetings(from: Date, to: Date) async throws -> [Meeting] {
        var components = URLComponents(
            string: "https://www.googleapis.com/calendar/v3/calendars/primary/events"
        )
        let formatter = ISO8601DateFormatter()
        components?.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: from)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: to)),
            // Expands recurring events into concrete instances.
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        try await request.setValue("Bearer \(session.accessToken())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            throw CalendarError.http(status, String(data: data, encoding: .utf8) ?? "")
        }

        return Self.decode(data, accountID: accountID, parser: parser)
    }

    static func decode(_ data: Data, accountID: String, parser: MeetingLinkParser) -> [Meeting] {
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return [] }
        return body.items.compactMap { $0.meeting(accountID: accountID, parser: parser) }
    }

    // MARK: - Wire format

    struct Body: Decodable {
        let items: [Event]
    }

    struct Event: Decodable {
        let id: String
        let summary: String?
        let start: DateTime
        let end: DateTime
        let location: String?
        let description: String?
        let hangoutLink: String?
        let organizer: Organizer?
        let conferenceData: ConferenceData?

        func meeting(accountID: String, parser: MeetingLinkParser) -> Meeting? {
            // All-day events carry `date` instead of `dateTime` and never need
            // a join alarm.
            guard let startDate = start.resolved, let endDate = end.resolved else { return nil }

            let structuredLink = conferenceData?.videoEntryPoint ?? hangoutLink
            let joinURL = structuredLink.flatMap(URL.init(string:))
                ?? parser.firstLink(in: [location, description])

            return Meeting(
                id: id,
                title: summary ?? "(no title)",
                start: startDate,
                end: endDate,
                organiser: organizer?.displayName ?? organizer?.email,
                joinURL: joinURL,
                accountID: accountID
            )
        }
    }

    struct DateTime: Decodable {
        let dateTime: String?
        let date: String?

        var resolved: Date? {
            dateTime.flatMap(EventDateParsing.offsetDate)
        }
    }

    struct Organizer: Decodable {
        let email: String?
        let displayName: String?
    }

    struct ConferenceData: Decodable {
        let entryPoints: [EntryPoint]?

        var videoEntryPoint: String? {
            entryPoints?.first { $0.entryPointType == "video" }?.uri
        }
    }

    struct EntryPoint: Decodable {
        let entryPointType: String?
        let uri: String?
    }
}
