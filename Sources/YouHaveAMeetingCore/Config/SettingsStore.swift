import Foundation
import Observation
import os
import SwiftUI

/// Loads and persists `Settings`. A missing or unreadable file is not an error -
/// the app must still start and alarm, so it falls back to defaults.
@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored private static let log = Logger(
        subsystem: "app.youhaveameeting",
        category: "settings"
    )

    static var directoryURL: URL {
        URL.applicationSupportDirectory.appending(
            path: "YouHaveAMeeting",
            directoryHint: .isDirectory
        )
    }

    static var fileURL: URL {
        directoryURL.appending(path: "settings.json", directoryHint: .notDirectory)
    }

    private(set) var value: Settings

    /// SwiftUI binding that persists on every change, so no view has to
    /// remember to save.
    func binding<T>(_ keyPath: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(
            get: { self.value[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    init() {
        value = Self.read() ?? Settings()
    }

    /// Mutate and persist in one step so callers cannot forget to save.
    func update(_ mutate: (inout Settings) -> Void) {
        var copy = value
        mutate(&copy)
        guard copy != value else { return }
        value = copy
        write(copy)
    }

    /// Write the full current settings so the file can be hand-edited.
    ///
    /// Always writes, rather than only when the file is missing: a file saved
    /// by an older build decodes fine but omits the newer keys, which would
    /// leave nowhere to type the client IDs. Rewriting materialises every key
    /// at its current value.
    func ensureFileIsComplete() {
        write(value)
    }

    private static func read() -> Settings? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            log.error("settings unreadable, using defaults: \(error.localizedDescription)")
            return nil
        }
    }

    private func write(_ settings: Settings) {
        do {
            try FileManager.default.createDirectory(
                at: Self.directoryURL,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: Self.fileURL, options: .atomic)
        } catch {
            Self.log.error("could not save settings: \(error.localizedDescription)")
        }
    }
}
