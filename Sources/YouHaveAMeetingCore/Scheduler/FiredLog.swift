import Foundation
import os

/// Remembers which meetings have already alarmed, so a calendar refresh or an
/// app restart cannot re-alarm something you already joined.
@MainActor
final class FiredLog {
    private static let log = Logger(subsystem: "app.youhaveameeting", category: "firedlog")
    /// Entries older than this are dropped; they can never match again.
    private static let retention: TimeInterval = 86400 * 2

    private var entries: [String: Date]
    private let fileURL: URL

    init(fileURL: URL = FiredLog.defaultURL) {
        self.fileURL = fileURL
        entries = Self.read(from: fileURL)
    }

    static var defaultURL: URL {
        SettingsStore.directoryURL.appending(path: "fired.json", directoryHint: .notDirectory)
    }

    var keys: Set<String> { Set(entries.keys) }

    func contains(_ meeting: Meeting) -> Bool {
        entries[MeetingSchedule.key(for: meeting)] != nil
    }

    func record(_ meeting: Meeting, at now: Date = .now) {
        entries[MeetingSchedule.key(for: meeting)] = now
        prune(now: now)
        write()
    }

    func prune(now: Date = .now) {
        entries = entries.filter { now.timeIntervalSince($0.value) < Self.retention }
    }

    private static func read(from url: URL) -> [String: Date] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return decoded
    }

    private func write() {
        do {
            try FileManager.default.createDirectory(
                at: SettingsStore.directoryURL,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Losing this only risks a duplicate alert, never a missed one.
            Self.log.error("could not persist fired log: \(error.localizedDescription)")
        }
    }
}
