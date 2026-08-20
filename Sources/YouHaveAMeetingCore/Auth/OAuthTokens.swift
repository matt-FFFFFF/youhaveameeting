import Foundation

/// A token-endpoint response, normalised across both providers.
struct OAuthTokens: Sendable, Equatable {
    let accessToken: String
    /// Absent when a refresh response reuses the existing refresh token.
    let refreshToken: String?
    let expiresAt: Date

    /// Treat a token as expired slightly early so a request in flight cannot
    /// straddle the expiry.
    func isValid(at now: Date = .now, leeway: TimeInterval = 60) -> Bool {
        expiresAt.addingTimeInterval(-leeway) > now
    }
}

/// Wire format of the token endpoint. Both providers use the same field names.
struct TokenResponseBody: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }

    func tokens(receivedAt: Date = .now) -> OAuthTokens {
        OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            // Providers may omit expires_in; an hour matches both defaults.
            expiresAt: receivedAt.addingTimeInterval(TimeInterval(expiresIn ?? 3600))
        )
    }
}

enum AuthError: Error, LocalizedError, Equatable {
    case notConfigured(ProviderKind)
    case missingClientSecret(ProviderKind)
    case listenerFailed(String)
    case userCancelled
    case callbackMissingCode
    case stateMismatch
    case provider(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case let .notConfigured(kind):
            "No client ID configured for \(kind.displayName)."
        case let .missingClientSecret(kind):
            "\(kind.displayName) requires a client secret as well as a client ID. "
                + "Copy it from the same credentials page into the settings file."
        case let .listenerFailed(detail):
            "Could not start the local sign-in listener: \(detail)"
        case .userCancelled:
            "Sign-in was cancelled."
        case .callbackMissingCode:
            "The sign-in response contained no authorization code."
        case .stateMismatch:
            "The sign-in response did not match this request."
        case let .provider(message):
            message
        case let .http(status, body):
            "The provider returned HTTP \(status): \(body)"
        }
    }
}
