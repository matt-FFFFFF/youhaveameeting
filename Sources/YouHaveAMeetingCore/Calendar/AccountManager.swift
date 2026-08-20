import Foundation

/// Turns stored accounts plus settings into live providers, and runs the
/// interactive sign-in that creates them.
@MainActor
final class AccountManager {
    private let settings: SettingsStore
    let service = CalendarService()
    private var sessions: [String: AuthSession] = [:]

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var accounts: [Account] { settings.value.accounts }

    /// Signs in, stores the refresh token, and records the account.
    func connect(_ kind: ProviderKind) async throws {
        let clientID = settings.value.clientID(for: kind)
        guard !clientID.isEmpty else { throw AuthError.notConfigured(kind) }

        let account = Account(kind: kind, displayName: kind.displayName)
        let session = try await AuthSession.connect(
            config: settings.value.oauthConfig(for: kind),
            clientID: clientID,
            clientSecret: settings.value.clientSecret(for: kind),
            accountID: account.id
        )
        sessions[account.id] = session
        settings.update { $0.accounts.append(account) }
        await rebuildProviders()
    }

    func disconnect(_ account: Account) {
        sessions[account.id] = nil
        try? TokenStore.delete(accountID: account.id)
        settings.update { $0.accounts.removeAll { $0.id == account.id } }
        Task { await rebuildProviders() }
    }

    /// Rebuilds the provider list from current settings. Safe to call whenever
    /// accounts or link providers change.
    func rebuildProviders() async {
        let parser = MeetingLinkParser(providers: settings.value.meetingLinkProviders)

        let providers: [any CalendarProvider] = settings.value.accounts.compactMap { account in
            let clientID = settings.value.clientID(for: account.kind)
            guard !clientID.isEmpty else { return nil }

            let session = sessions[account.id] ?? AuthSession(
                config: settings.value.oauthConfig(for: account.kind),
                clientID: clientID,
                clientSecret: settings.value.clientSecret(for: account.kind),
                accountID: account.id
            )
            sessions[account.id] = session

            switch account.kind {
            case .google:
                return GoogleCalendarProvider(
                    accountID: account.id,
                    session: session,
                    parser: parser
                )
            case .microsoft:
                return GraphCalendarProvider(
                    accountID: account.id,
                    session: session,
                    parser: parser
                )
            }
        }

        await service.replaceProviders(providers)
    }
}
