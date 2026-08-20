import Foundation
import Testing
@testable import YouHaveAMeetingCore

@Suite("Settings")
struct SettingsTests {
    @Test("round-trips through JSON")
    func roundTrip() throws {
        var settings = Settings()
        settings.leadOffsetSeconds = -60
        settings.presenceMode = .presenting

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)

        #expect(decoded == settings)
    }

    @Test("decodes a file missing newer keys, using defaults")
    func forwardCompatibleDecode() throws {
        let json = Data(#"{"leadOffsetSeconds":-30}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: json)

        #expect(decoded.leadOffsetSeconds == -30)
        #expect(decoded.pollIntervalSeconds == Settings().pollIntervalSeconds)
        #expect(decoded.silenceWhenMicActive)
    }
}

@Suite("Presence mode migration")
struct PresenceModeMigrationTests {
    @Test("an old file with manualPresenting true becomes .presenting")
    func migratesTrue() throws {
        let json = Data(#"{"manualPresenting":true}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        #expect(decoded.presenceMode == .presenting)
    }

    @Test("an old file with manualPresenting false becomes .normal")
    func migratesFalse() throws {
        let json = Data(#"{"manualPresenting":false}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        #expect(decoded.presenceMode == .normal)
    }

    @Test("a new file's presenceMode wins over any legacy key")
    func newKeyWins() throws {
        let json = Data(#"{"manualPresenting":true,"presenceMode":"normal"}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        #expect(decoded.presenceMode == .normal)
    }
}
