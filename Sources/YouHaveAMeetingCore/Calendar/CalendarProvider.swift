import Foundation

/// The plugin boundary. Adding a service means one new conforming type and one
/// registration line; nothing else in the app changes.
protocol CalendarProvider: Sendable {
    var kind: ProviderKind { get }
    var accountID: String { get }

    /// Concrete occurrences overlapping the window. Recurring events must be
    /// expanded by the provider, not the caller.
    func meetings(from: Date, to: Date) async throws -> [Meeting]
}

enum CalendarError: Error, LocalizedError {
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case let .http(status, body):
            "Calendar request failed with HTTP \(status): \(body)"
        }
    }
}

/// Shared decoding for the two providers' timestamp formats.
enum EventDateParsing {
    /// Offset-bearing RFC 3339, with or without fractional seconds.
    static func offsetDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    /// Microsoft Graph returns a local-looking timestamp plus a separate time
    /// zone field. Requests set `Prefer: outlook.timezone="UTC"`, so these are
    /// parsed as UTC.
    static func graphDate(_ string: String, timeZone: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZone ?? "UTC") ?? TimeZone(identifier: "UTC")
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return offsetDate(string)
    }
}
