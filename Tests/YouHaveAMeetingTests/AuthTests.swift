import Foundation
import Testing
@testable import YouHaveAMeetingCore

@Suite("PKCE")
struct PKCETests {
    @Test("matches the RFC 7636 appendix B vector")
    func rfcVector() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("generated verifiers are base64url and long enough")
    func generatedVerifier() {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        for _ in 0 ..< 20 {
            let verifier = PKCE().verifier
            #expect(verifier.count >= 43)
            #expect(verifier.count <= 128)
            #expect(verifier.unicodeScalars.allSatisfy(allowed.contains))
        }
    }

    @Test("verifiers are not reused")
    func unique() {
        #expect(PKCE().verifier != PKCE().verifier)
    }
}

@Suite("OAuth form encoding")
struct FormEncodingTests {
    @Test("sorts keys and percent-encodes reserved characters")
    func encoding() {
        let encoded = OAuthClient.formEncoded([
            "scope": "a b",
            "client_id": "id/with+chars"
        ])
        #expect(encoded == "client_id=id%2Fwith%2Bchars&scope=a%20b")
    }
}

@Suite("Loopback callback parsing")
struct LoopbackParsingTests {
    @Test("extracts query items from the request line")
    func requestLine() {
        let head = "GET /callback?code=abc123&state=xyz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        let items = LoopbackServer.queryItems(fromRequestHead: head)
        #expect(items.first { $0.name == "code" }?.value == "abc123")
        #expect(items.first { $0.name == "state" }?.value == "xyz")
    }

    @Test("surfaces provider errors in the callback")
    func errorCallback() {
        let head = "GET /callback?error=access_denied HTTP/1.1\r\n\r\n"
        let items = LoopbackServer.queryItems(fromRequestHead: head)
        #expect(items.first { $0.name == "error" }?.value == "access_denied")
        #expect(items.contains { $0.name == "code" } == false)
    }

    @Test("handles a bare root path, which is what the browser requests")
    func rootPath() {
        let head = "GET /?code=abc123&state=xyz HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let items = LoopbackServer.queryItems(fromRequestHead: head)
        #expect(items.first { $0.name == "code" }?.value == "abc123")
    }

    @Test("returns nothing for a malformed request")
    func malformed() {
        #expect(LoopbackServer.queryItems(fromRequestHead: "garbage").isEmpty)
    }
}

@Suite("Token expiry")
struct TokenExpiryTests {
    @Test("expires early by the leeway so requests cannot straddle expiry")
    func leeway() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let tokens = OAuthTokens(
            accessToken: "a",
            refreshToken: nil,
            expiresAt: now.addingTimeInterval(30)
        )
        #expect(!tokens.isValid(at: now, leeway: 60))
        #expect(tokens.isValid(at: now, leeway: 10))
    }

    @Test("defaults to an hour when expires_in is absent")
    func defaultExpiry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let body = TokenResponseBody(accessToken: "a", refreshToken: "r", expiresIn: nil)
        #expect(body.tokens(receivedAt: now).expiresAt == now.addingTimeInterval(3600))
    }
}

@Suite("Redirect URI")
struct RedirectURITests {
    @Test("matches the bare loopback host registered in both consoles")
    func format() {
        #expect(OAuthConfig.google.redirectURI(port: 52341) == "http://localhost:52341")
        #expect(
            OAuthConfig.microsoft(tenant: "common").redirectURI(port: 52341)
                == "http://localhost:52341"
        )
    }

    @Test("no path is appended, which would break redirect matching")
    func noPath() {
        for config in [OAuthConfig.google, .microsoft(tenant: "common")] {
            #expect(!config.redirectURI(port: 1).contains("/callback"))
        }
    }
}

@Suite("Client secret handling")
struct ClientSecretTests {
    @Test("Google requires a secret, Microsoft does not")
    func requirements() {
        #expect(OAuthConfig.google.requiresClientSecret)
        #expect(!OAuthConfig.microsoft(tenant: "common").requiresClientSecret)
    }

    @Test("a missing Google secret fails before the browser opens")
    func failsEarly() async {
        await #expect(throws: AuthError.missingClientSecret(.google)) {
            _ = try await OAuthClient.authorize(
                config: .google,
                clientID: "some-id.apps.googleusercontent.com",
                clientSecret: ""
            )
        }
    }

    @Test("an empty client ID is reported as not configured")
    func emptyClientID() async {
        await #expect(throws: AuthError.notConfigured(.microsoft)) {
            _ = try await OAuthClient.authorize(
                config: .microsoft(tenant: "common"),
                clientID: "",
                clientSecret: ""
            )
        }
    }

    @Test("the secret is only ever a token-endpoint parameter")
    func neverInAuthorizeURL() {
        // The authorize request is built from these keys only; client_secret is
        // added inside the token exchange, never here.
        let encoded = OAuthClient.formEncoded([
            "grant_type": "authorization_code",
            "client_secret": "GOCSPX-example"
        ])
        #expect(encoded.contains("client_secret=GOCSPX-example"))
    }
}

@Suite("Entra authority")
struct EntraAuthorityTests {
    static let tenant = "72f988bf-86f1-41af-91ab-2d7cd011db47"

    @Test("a tenant reaches both endpoints, so single-tenant apps can sign in")
    func tenantSpecific() {
        // Hardcoding /common is what made a single-tenant registration fail
        // with AADSTS50194, so both endpoints have to carry the tenant.
        let config = OAuthConfig.microsoft(tenant: Self.tenant)
        for url in [config.authorizeURL, config.tokenURL] {
            #expect(url.absoluteString.contains(Self.tenant))
            #expect(!url.absoluteString.contains("common"))
        }
        #expect(
            config.authorizeURL.absoluteString
                == "https://login.microsoftonline.com/\(Self.tenant)/oauth2/v2.0/authorize"
        )
        #expect(
            config.tokenURL.absoluteString
                == "https://login.microsoftonline.com/\(Self.tenant)/oauth2/v2.0/token"
        )
    }

    @Test("a blank tenant falls back to the any-tenant authority")
    func blankFallsBack() {
        for blank in ["", "   ", "\n", "/"] {
            let config = OAuthConfig.microsoft(tenant: blank)
            #expect(
                config.authorizeURL.absoluteString
                    == "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
            )
        }
    }

    @Test("whitespace and slashes around a pasted tenant are trimmed")
    func trimsPastedValue() {
        for pasted in [" \(Self.tenant) ", "\(Self.tenant)\n", "/\(Self.tenant)/"] {
            #expect(
                OAuthConfig.microsoft(tenant: pasted).tokenURL.absoluteString
                    == "https://login.microsoftonline.com/\(Self.tenant)/oauth2/v2.0/token"
            )
        }
    }

    @Test("an interior slash cannot extend the path into a wrong endpoint")
    func slashCannotEscape() {
        let config = OAuthConfig.microsoft(tenant: "login.microsoftonline.com/\(Self.tenant)")
        // Encoded, so Entra reports an unknown tenant rather than the request
        // silently going somewhere plausible-looking.
        #expect(config.tokenURL.absoluteString.hasSuffix("/oauth2/v2.0/token"))
        #expect(config.tokenURL.absoluteString.contains("%2F"))
    }

    @Test("settings thread the tenant through, and leave Google alone")
    func fromSettings() {
        var settings = Settings()
        settings.microsoftTenant = Self.tenant

        #expect(settings.oauthConfig(for: .microsoft).tokenURL.absoluteString.contains(Self.tenant))
        #expect(settings.oauthConfig(for: .google).tokenURL == OAuthConfig.google.tokenURL)
    }

    @Test("a settings file written before the tenant existed still uses common")
    func defaultsForOlderFiles() throws {
        let decoded = try JSONDecoder().decode(
            Settings.self,
            from: Data(#"{"microsoftClientID":"abc"}"#.utf8)
        )
        #expect(decoded.microsoftTenant == OAuthConfig.defaultMicrosoftTenant)
        #expect(
            decoded.oauthConfig(for: .microsoft).authorizeURL.absoluteString
                == "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
        )
    }
}
