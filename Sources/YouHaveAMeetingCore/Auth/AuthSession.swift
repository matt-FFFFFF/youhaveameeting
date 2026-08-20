import Foundation

/// Holds the live access token for one account and mints a new one when it
/// expires. Serialised through an actor so concurrent calendar fetches cannot
/// trigger two refreshes at once.
actor AuthSession {
    private let config: OAuthConfig
    private let clientID: String
    private let clientSecret: String
    private let accountID: String
    private var tokens: OAuthTokens?

    init(config: OAuthConfig, clientID: String, clientSecret: String, accountID: String) {
        self.config = config
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.accountID = accountID
    }

    /// Runs the interactive sign-in and persists the refresh token.
    static func connect(
        config: OAuthConfig,
        clientID: String,
        clientSecret: String,
        accountID: String
    ) async throws -> AuthSession {
        let tokens = try await OAuthClient.authorize(
            config: config,
            clientID: clientID,
            clientSecret: clientSecret
        )
        guard let refreshToken = tokens.refreshToken else {
            throw AuthError.provider(
                "\(config.kind.displayName) returned no refresh token. "
                    + "For Google, publish the OAuth consent screen: while it is in Testing, "
                    + "refresh tokens expire after 7 days."
            )
        }
        try TokenStore.save(refreshToken: refreshToken, for: accountID)
        let session = AuthSession(
            config: config,
            clientID: clientID,
            clientSecret: clientSecret,
            accountID: accountID
        )
        await session.adopt(tokens)
        return session
    }

    func accessToken() async throws -> String {
        if let tokens, tokens.isValid() {
            return tokens.accessToken
        }

        guard let refreshToken = TokenStore.refreshToken(for: accountID) else {
            throw AuthError.notConfigured(config.kind)
        }

        let refreshed = try await OAuthClient.refresh(
            config: config,
            clientID: clientID,
            clientSecret: clientSecret,
            refreshToken: refreshToken
        )
        // Microsoft rotates refresh tokens on every refresh, so a new one must
        // replace the stored value or the next refresh fails.
        if let rotated = refreshed.refreshToken, rotated != refreshToken {
            try TokenStore.save(refreshToken: rotated, for: accountID)
        }
        tokens = refreshed
        return refreshed.accessToken
    }

    private func adopt(_ tokens: OAuthTokens) {
        self.tokens = tokens
    }
}
