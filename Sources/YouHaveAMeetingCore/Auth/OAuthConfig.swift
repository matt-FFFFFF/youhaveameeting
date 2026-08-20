import Foundation

enum ProviderKind: String, Codable, Sendable, CaseIterable {
    case google
    case microsoft

    var displayName: String {
        switch self {
        case .google: "Google"
        case .microsoft: "Microsoft"
        }
    }
}

/// Everything that differs between the two OAuth providers.
///
/// Both use a loopback redirect rather than a custom URL scheme: Google's
/// scheme is derived from the client ID, which the user supplies at runtime,
/// so it cannot be declared in Info.plist at build time. Loopback needs no
/// registration in the bundle at all.
struct OAuthConfig: Sendable {
    let kind: ProviderKind
    let authorizeURL: URL
    let tokenURL: URL
    let scopes: [String]
    /// Both providers register the bare loopback host `http://localhost`.
    let redirectHost: String
    /// Provider-specific parameters added to the authorize request.
    let extraAuthorizeParameters: [String: String]
    /// Whether the token endpoint demands `client_secret`.
    ///
    /// Google requires it even for Desktop-app clients, which is why its
    /// console hands one out. It is not confidential - anyone holding the app
    /// holds it too - and PKCE is what actually secures the exchange. Entra ID
    /// public clients reject a secret outright.
    let requiresClientSecret: Bool

    /// Must match the registered redirect exactly apart from the port, which
    /// loopback clients are allowed to vary. No path is appended: the console
    /// registers a bare `http://localhost`, and a `/callback` path would not
    /// match it.
    func redirectURI(port: UInt16) -> String {
        "http://\(redirectHost):\(port)"
    }

    var scopeString: String { scopes.joined(separator: " ") }
}

extension OAuthConfig {
    static let google = OAuthConfig(
        kind: .google,
        authorizeURL: URL(staticString: "https://accounts.google.com/o/oauth2/v2/auth"),
        tokenURL: URL(staticString: "https://oauth2.googleapis.com/token"),
        scopes: ["https://www.googleapis.com/auth/calendar.events.readonly"],
        redirectHost: "localhost",
        // Without these Google issues no refresh token on repeat consent.
        extraAuthorizeParameters: ["access_type": "offline", "prompt": "consent"],
        requiresClientSecret: true
    )

    /// Entra's any-tenant authority.
    ///
    /// It accepts only registrations whose supported account types include
    /// tenants other than their own. A single-tenant registration - the
    /// default the portal offers - is rejected here with AADSTS50194 and has
    /// to name its own tenant instead.
    static let defaultMicrosoftTenant = "common"

    /// - Parameter tenant: the authority to sign in against: `common`,
    ///   `organizations`, `consumers`, or one tenant's GUID or verified
    ///   domain. It has to match how the registration's supported account
    ///   types are set; SETUP.md covers which to choose.
    static func microsoft(tenant: String) -> OAuthConfig {
        let authority = authoritySegment(tenant)
        return OAuthConfig(
            kind: .microsoft,
            authorizeURL: entraEndpoint(authority: authority, "authorize"),
            tokenURL: entraEndpoint(authority: authority, "token"),
            scopes: ["Calendars.Read", "offline_access", "openid", "profile"],
            redirectHost: "localhost",
            extraAuthorizeParameters: [:],
            requiresClientSecret: false
        )
    }

    /// This is pasted out of the Entra portal, so surrounding whitespace and
    /// slashes are expected, and a cleared field means the any-tenant
    /// authority.
    ///
    /// Whatever survives that is percent-encoded rather than validated. A
    /// tenant Entra does not recognise then comes back as its own "tenant not
    /// found", which names the mistake better than a guess made here could.
    private static func authoritySegment(_ tenant: String) -> String {
        let trimmed = tenant
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return defaultMicrosoftTenant }
        // Excluding "/" stops a pasted authority URL spilling into the path
        // and forming a plausible-looking but wrong endpoint.
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
    }

    private static func entraEndpoint(authority: String, _ endpoint: String) -> URL {
        let string = "https://login.microsoftonline.com/\(authority)/oauth2/v2.0/\(endpoint)"
        // `authority` is percent-encoded above, so this cannot fail.
        guard let url = URL(string: string) else {
            preconditionFailure("invalid Entra endpoint: \(string)")
        }
        return url
    }
}

extension URL {
    /// For URLs that are compile-time constants and cannot fail.
    init(staticString: StaticString) {
        guard let url = URL(string: "\(staticString)") else {
            preconditionFailure("invalid static URL: \(staticString)")
        }
        self = url
    }
}
