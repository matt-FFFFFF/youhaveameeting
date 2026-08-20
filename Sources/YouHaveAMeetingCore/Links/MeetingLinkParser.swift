import Foundation
import os

/// Finds a join link in an event's fields.
///
/// Providers whose regex fails to compile are skipped rather than fatal - the
/// list is user-editable, and a bad pattern must not stop every other provider
/// from matching.
struct MeetingLinkParser: Sendable {
    private static let log = Logger(subsystem: "app.youhaveameeting", category: "links")

    private let compiled: [(provider: MeetingLinkProvider, regex: NSRegularExpression)]

    init(providers: [MeetingLinkProvider] = MeetingLinkProvider.defaults) {
        compiled = providers.compactMap { provider in
            guard provider.isEnabled else { return nil }
            do {
                let regex = try NSRegularExpression(
                    pattern: provider.pattern,
                    options: [.caseInsensitive]
                )
                return (provider, regex)
            } catch {
                Self.log.error(
                    "ignoring link provider \(provider.id): \(error.localizedDescription)"
                )
                return nil
            }
        }
    }

    /// Searches the given fields in order and returns the first match.
    ///
    /// Field order is the priority: a structured URL beats a link buried in a
    /// description, which may be stale or belong to a different meeting.
    func firstLink(in fields: [String?]) -> URL? {
        for field in fields.compactMap(\.self) where !field.isEmpty {
            if let url = firstLink(in: field) {
                return url
            }
        }
        return nil
    }

    func firstLink(in text: String) -> URL? {
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        for entry in compiled {
            guard let match = entry.regex.firstMatch(in: text, range: range),
                  let matched = Range(match.range, in: text)
            else { continue }
            let candidate = String(text[matched]).trimmingCharacters(
                in: CharacterSet(charactersIn: ".,;:)]}\"'")
            )
            if let url = URL(string: candidate) {
                return url
            }
        }
        return nil
    }
}
