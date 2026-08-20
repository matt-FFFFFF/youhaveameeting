import Foundation

struct GraphCalendarProvider: CalendarProvider {
    let kind = ProviderKind.microsoft
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
        var components = URLComponents(string: "https://graph.microsoft.com/v1.0/me/calendarView")
        let formatter = ISO8601DateFormatter()
        components?.queryItems = [
            URLQueryItem(name: "startDateTime", value: formatter.string(from: from)),
            URLQueryItem(name: "endDateTime", value: formatter.string(from: to)),
            URLQueryItem(name: "$orderby", value: "start/dateTime"),
            URLQueryItem(name: "$top", value: "50")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        try await request.setValue("Bearer \(session.accessToken())", forHTTPHeaderField: "Authorization")
        // Makes every returned timestamp UTC, so they can be parsed uniformly.
        request.setValue("outlook.timezone=\"UTC\"", forHTTPHeaderField: "Prefer")

        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            throw CalendarError.http(status, String(data: data, encoding: .utf8) ?? "")
        }

        return Self.decode(data, accountID: accountID, parser: parser)
    }

    static func decode(_ data: Data, accountID: String, parser: MeetingLinkParser) -> [Meeting] {
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return [] }
        return body.value.compactMap { $0.meeting(accountID: accountID, parser: parser) }
    }

    // MARK: - Wire format

    struct Body: Decodable {
        let value: [Event]
    }

    struct Event: Decodable {
        let id: String
        let subject: String?
        let start: DateTime
        let end: DateTime
        let isAllDay: Bool?
        let bodyPreview: String?
        let onlineMeetingUrl: String?
        let onlineMeeting: OnlineMeeting?
        let location: Location?
        let organizer: Recipient?

        func meeting(accountID: String, parser: MeetingLinkParser) -> Meeting? {
            guard isAllDay != true,
                  let startDate = start.resolved,
                  let endDate = end.resolved
            else { return nil }

            let structuredLink = onlineMeeting?.joinUrl ?? onlineMeetingUrl
            let joinURL = structuredLink.flatMap(URL.init(string:))
                ?? parser.firstLink(in: [location?.displayName, bodyPreview])

            return Meeting(
                id: id,
                title: subject ?? "(no title)",
                start: startDate,
                end: endDate,
                organiser: organizer?.emailAddress?.name ?? organizer?.emailAddress?.address,
                joinURL: joinURL,
                accountID: accountID
            )
        }
    }

    struct DateTime: Decodable {
        let dateTime: String?
        let timeZone: String?

        var resolved: Date? {
            dateTime.flatMap { EventDateParsing.graphDate($0, timeZone: timeZone) }
        }
    }

    struct OnlineMeeting: Decodable {
        let joinUrl: String?
    }

    struct Location: Decodable {
        let displayName: String?
    }

    struct Recipient: Decodable {
        let emailAddress: EmailAddress?
    }

    struct EmailAddress: Decodable {
        let name: String?
        let address: String?
    }
}
