import Foundation

/// User-tunable behaviour, persisted as JSON.
///
/// Decoding is deliberately hand-written: the compiler-synthesised
/// `init(from:)` treats a missing key as an error even when the property has a
/// default, so a settings file written by an older build would fail to decode
/// and silently reset every setting. Each field falls back to its default
/// instead, so old files keep the values they do contain.
struct Settings: Codable, Equatable, Sendable {
    /// Offset applied to the meeting start time. Negative fires early.
    var leadOffsetSeconds: Int = 0
    /// How often calendars are re-fetched.
    var pollIntervalSeconds: Int = 300
    /// How far ahead meetings are loaded.
    var lookaheadSeconds: Int = 86400

    /// Silence conditions - each downgrades the takeover to a corner banner.
    var silenceWhenMicActive: Bool = true
    var silenceWhenCameraActive: Bool = false
    var silenceWhenSharing: Bool = true
    /// Manual override, chosen from the menu bar or settings window.
    var presenceMode: PresenceMode = .normal

    /// OAuth client credentials, per installation rather than compiled in.
    ///
    /// `googleClientSecret` is required: Google's token endpoint rejects
    /// Desktop-app exchanges without it. Google does not treat it as
    /// confidential - it ships inside the JSON the console hands you - and PKCE
    /// is what actually secures the flow. Microsoft public clients take no
    /// secret at all.
    var googleClientID: String = ""
    var googleClientSecret: String = ""
    var microsoftClientID: String = ""

    /// Connected accounts. Refresh tokens live in the Keychain, keyed by id.
    var accounts: [Account] = []

    /// Which conferencing services are recognised in event fields, in priority
    /// order.
    var meetingLinkProviders: [MeetingLinkProvider] = MeetingLinkProvider.defaults

    /// Keys that no longer map to a property, kept only for migration.
    private enum LegacyKeys: String, CodingKey {
        case manualPresenting
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Settings()

        func value<T: Decodable>(_ key: CodingKeys, default fallback: T) throws -> T {
            try container.decodeIfPresent(T.self, forKey: key) ?? fallback
        }

        leadOffsetSeconds = try value(.leadOffsetSeconds, default: fallback.leadOffsetSeconds)
        pollIntervalSeconds = try value(.pollIntervalSeconds, default: fallback.pollIntervalSeconds)
        lookaheadSeconds = try value(.lookaheadSeconds, default: fallback.lookaheadSeconds)
        silenceWhenMicActive = try value(.silenceWhenMicActive, default: fallback.silenceWhenMicActive)
        silenceWhenCameraActive = try value(
            .silenceWhenCameraActive,
            default: fallback.silenceWhenCameraActive
        )
        silenceWhenSharing = try value(.silenceWhenSharing, default: fallback.silenceWhenSharing)
        // Migrate the old boolean: a file written before the tri-state mode
        // existed has manualPresenting instead.
        if let mode = try container.decodeIfPresent(PresenceMode.self, forKey: .presenceMode) {
            presenceMode = mode
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let wasPresenting = try legacy.decodeIfPresent(
                Bool.self,
                forKey: .manualPresenting
            ) ?? false
            presenceMode = wasPresenting ? .presenting : fallback.presenceMode
        }
        googleClientID = try value(.googleClientID, default: fallback.googleClientID)
        googleClientSecret = try value(.googleClientSecret, default: fallback.googleClientSecret)
        microsoftClientID = try value(.microsoftClientID, default: fallback.microsoftClientID)
        accounts = try value(.accounts, default: fallback.accounts)
        meetingLinkProviders = try value(
            .meetingLinkProviders,
            default: fallback.meetingLinkProviders
        )
    }
}

extension Settings {
    func clientID(for kind: ProviderKind) -> String {
        switch kind {
        case .google: googleClientID
        case .microsoft: microsoftClientID
        }
    }

    func clientSecret(for kind: ProviderKind) -> String {
        switch kind {
        case .google: googleClientSecret
        case .microsoft: ""
        }
    }

    var leadOffset: TimeInterval { TimeInterval(leadOffsetSeconds) }
    var pollInterval: TimeInterval { TimeInterval(pollIntervalSeconds) }
    var lookahead: TimeInterval { TimeInterval(lookaheadSeconds) }
}
