import AppKit
import Foundation

/// Authorization-code + PKCE flow against a loopback redirect, shared by both
/// providers. Public clients only - no client secret is stored or sent.
enum OAuthClient {
    /// How long to wait for the user to finish in the browser.
    static let callbackTimeout: TimeInterval = 300

    static func authorize(
        config: OAuthConfig,
        clientID: String,
        clientSecret: String
    ) async throws -> OAuthTokens {
        guard !clientID.isEmpty else { throw AuthError.notConfigured(config.kind) }
        if config.requiresClientSecret, clientSecret.isEmpty {
            throw AuthError.missingClientSecret(config.kind)
        }

        let server = LoopbackServer()
        defer { server.stop() }

        let port = try await server.start()
        let redirectURI = config.redirectURI(port: port)
        let pkce = PKCE()
        let state = PKCE().verifier

        let authorizeURL = try buildAuthorizeURL(
            config: config,
            clientID: clientID,
            redirectURI: redirectURI,
            pkce: pkce,
            state: state
        )
        await MainActor.run { _ = NSWorkspace.shared.open(authorizeURL) }

        let items = try await withThrowingTaskGroup(of: [URLQueryItem].self) { group in
            group.addTask { try await server.waitForCallback() }
            group.addTask {
                try await Task.sleep(for: .seconds(callbackTimeout))
                throw AuthError.userCancelled
            }
            guard let first = try await group.next() else { throw AuthError.userCancelled }
            group.cancelAll()
            return first
        }

        if let error = items.first(where: { $0.name == "error" })?.value {
            let description = items.first { $0.name == "error_description" }?.value
            throw AuthError.provider(description ?? error)
        }
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw AuthError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw AuthError.callbackMissingCode
        }

        return try await exchange(
            config: config,
            clientSecret: clientSecret,
            form: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirectURI,
                "client_id": clientID,
                "code_verifier": pkce.verifier
            ]
        )
    }

    static func refresh(
        config: OAuthConfig,
        clientID: String,
        clientSecret: String,
        refreshToken: String
    ) async throws -> OAuthTokens {
        try await exchange(
            config: config,
            clientSecret: clientSecret,
            form: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientID,
                "scope": config.scopeString
            ]
        )
    }

    // MARK: - Requests

    private static func buildAuthorizeURL(
        config: OAuthConfig,
        clientID: String,
        redirectURI: String,
        pkce: PKCE,
        state: String
    ) throws -> URL {
        guard var components = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)
        else { throw AuthError.provider("Invalid authorize URL for \(config.kind.displayName).") }

        var parameters = [
            "response_type": "code",
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "scope": config.scopeString,
            "state": state,
            "code_challenge": pkce.challenge,
            "code_challenge_method": pkce.method
        ]
        parameters.merge(config.extraAuthorizeParameters) { current, _ in current }
        components.queryItems = parameters.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else {
            throw AuthError.provider("Could not build the sign-in URL.")
        }
        return url
    }

    private static func exchange(
        config: OAuthConfig,
        clientSecret: String,
        form: [String: String]
    ) async throws -> OAuthTokens {
        // Only ever sent to the token endpoint, never in the authorize URL.
        var form = form
        if config.requiresClientSecret, !clientSecret.isEmpty {
            form["client_secret"] = clientSecret
        }

        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncoded(form).utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            throw AuthError.http(status, String(data: data, encoding: .utf8) ?? "")
        }

        return try JSONDecoder().decode(TokenResponseBody.self, from: data).tokens()
    }

    static func formEncoded(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters.sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed)
                    ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }
}
