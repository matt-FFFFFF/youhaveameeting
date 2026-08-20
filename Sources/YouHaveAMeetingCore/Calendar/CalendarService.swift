import Foundation
import os

/// Fans a time window out across every connected provider and merges the
/// results.
///
/// One provider failing must not hide the others' meetings, so failures are
/// logged and skipped rather than propagated.
actor CalendarService {
    private static let log = Logger(subsystem: "app.youhaveameeting", category: "calendar")

    private var providers: [any CalendarProvider]

    init(providers: [any CalendarProvider] = []) {
        self.providers = providers
    }

    func replaceProviders(_ providers: [any CalendarProvider]) {
        self.providers = providers
    }

    func meetings(from: Date, to: Date) async -> [Meeting] {
        let providers = providers
        guard !providers.isEmpty else { return [] }

        var collected: [Meeting] = []
        await withTaskGroup(of: [Meeting].self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return try await provider.meetings(from: from, to: to)
                    } catch {
                        Self.log.error(
                            """
                            \(provider.kind.rawValue) account \(provider.accountID) failed: \
                            \(error.localizedDescription)
                            """
                        )
                        return []
                    }
                }
            }
            for await batch in group {
                collected.append(contentsOf: batch)
            }
        }

        return Self.merge(collected)
    }

    /// The same meeting often appears on two connected accounts. Collapse by
    /// title and start so it only alarms once, preferring the copy that has a
    /// join link.
    static func merge(_ meetings: [Meeting]) -> [Meeting] {
        var best: [String: Meeting] = [:]
        for meeting in meetings {
            let key = "\(meeting.title)|\(meeting.start.timeIntervalSince1970)"
            if let existing = best[key], existing.joinURL != nil || meeting.joinURL == nil {
                continue
            }
            best[key] = meeting
        }
        return best.values.sorted { $0.start < $1.start }
    }
}
