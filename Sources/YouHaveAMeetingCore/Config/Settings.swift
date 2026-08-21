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
    var presenceMode: PresenceMode = .automatic

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
    /// Which Entra authority signs the user in - see `OAuthConfig.microsoft`.
    ///
    /// A single-tenant registration, which is what the portal offers by
    /// default, has to name its own tenant here; `common` rejects it. Going
    /// multi-tenant instead is usually the longer road, not the shorter one:
    /// under risk-based step-up consent a multi-tenant registration with no
    /// verified publisher cannot be consented to by an ordinary user for
    /// anything past basic sign-in, and `Calendars.Read` is past it, so every
    /// sign-in stops for admin approval. See SETUP.md.
    var microsoftTenant: String = OAuthConfig.defaultMicrosoftTenant

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
        // Migrate the old boolean: a file written before the mode enum
        // existed has manualPresenting instead. An unknown mode string is not a
        // migration problem - PresenceMode absorbs that itself.
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
        microsoftTenant = try value(.microsoftTenant, default: fallback.microsoftTenant)
        accounts = try value(.accounts, default: fallback.accounts)
        meetingLinkProviders = try value(
            .meetingLinkProviders,
            default: fallback.meetingLinkProviders
        )
    }
}

extension Settings {
    /// The endpoints and scopes for `kind`, with the per-installation parts
    /// filled in from here. Pairs with `clientID(for:)`: both are things only
    /// this installation knows.
    func oauthConfig(for kind: ProviderKind) -> OAuthConfig {
        switch kind {
        case .google: .google
        case .microsoft: .microsoft(tenant: microsoftTenant)
        }
    }

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
