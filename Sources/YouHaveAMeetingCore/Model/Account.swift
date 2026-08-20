import Foundation

/// A connected calendar account. The refresh token lives in the Keychain under
/// `id`; nothing secret is stored here.
struct Account: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var kind: ProviderKind
    var displayName: String

    init(id: String = UUID().uuidString, kind: ProviderKind, displayName: String) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
    }
}
