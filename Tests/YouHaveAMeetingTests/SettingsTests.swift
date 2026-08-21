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
        // Absent from an older file, so it must land on the default rather
        // than silently turning alerts off for unanswered invitations.
        #expect(decoded.alertUnconfirmedInvitations)
    }

    @Test("the unconfirmed-invitation choice round-trips")
    func unconfirmedInvitations() throws {
        #expect(Settings().alertUnconfirmedInvitations)

        var settings = Settings()
        settings.alertUnconfirmedInvitations = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)

        #expect(!decoded.alertUnconfirmedInvitations)
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

    @Test("an old file with manualPresenting false becomes .automatic")
    func migratesFalse() throws {
        let json = Data(#"{"manualPresenting":false}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        #expect(decoded.presenceMode == .automatic)
    }

    @Test("a new file's presenceMode wins over any legacy key")
    func newKeyWins() throws {
        let json = Data(#"{"manualPresenting":true,"presenceMode":"presenting"}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        #expect(decoded.presenceMode == .presenting)
    }

    /// `normal` is what `automatic` was called before Full Screen existed.
    @Test("the old spelling of automatic still decodes")
    func migratesNormalSpelling() throws {
        let json = Data(#"{"presenceMode":"normal","leadOffsetSeconds":-30}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        #expect(decoded.presenceMode == .automatic)
        // The whole file must survive, not just the mode: an unknown mode that
        // threw would reset every other setting to its default.
        #expect(decoded.leadOffsetSeconds == -30)
    }

    @Test("a mode from a future build falls back without losing the file")
    func unknownModeFallsBack() throws {
        let json = Data(#"{"presenceMode":"holographic","leadOffsetSeconds":-30}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        #expect(decoded.presenceMode == .automatic)
        #expect(decoded.leadOffsetSeconds == -30)
    }
}
