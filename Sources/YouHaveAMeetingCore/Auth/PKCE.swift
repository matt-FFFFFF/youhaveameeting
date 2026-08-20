import CryptoKit
import Foundation

/// RFC 7636 PKCE pair. Both providers are public clients with no usable
/// secret, so PKCE is what actually binds the redirect to this app.
struct PKCE: Sendable, Equatable {
    let verifier: String

    init(verifier: String) {
        self.verifier = verifier
    }

    init() {
        // 32 random bytes -> 43 base64url characters, within the 43...128 the
        // spec allows.
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: .min ... .max)
        }
        verifier = Data(bytes).base64URLEncodedString()
    }

    var challenge: String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    let method = "S256"
}

extension Data {
    /// base64url without padding, per RFC 4648 section 5.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
