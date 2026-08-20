import SwiftUI

/// Client credentials and connected accounts.
struct AccountSettingsView: View {
    let settings: SettingsStore
    let accounts: AccountManager

    @State private var error: String?
    @State private var connecting: ProviderKind?

    var body: some View {
        Form {
            Section("Connected") {
                if accounts.accounts.isEmpty {
                    Text("No accounts connected.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accounts.accounts) { account in
                        HStack {
                            Text(account.displayName)
                            Spacer()
                            Button("Disconnect") { accounts.disconnect(account) }
                        }
                    }
                }

                ForEach(ProviderKind.allCases, id: \.self) { kind in
                    Button("Connect \(kind.displayName)...") { connect(kind) }
                        .disabled(
                            settings.value.clientID(for: kind).isEmpty || connecting != nil
                        )
                }
            }

            Section("Google") {
                TextField("Client ID", text: settings.binding(\.googleClientID))
                SecureField("Client secret", text: settings.binding(\.googleClientSecret))
                Text(
                    """
                    Google requires both. Its token endpoint rejects Desktop-app \
                    sign-in without the secret. See SETUP.md.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section("Microsoft") {
                TextField("Client ID", text: settings.binding(\.microsoftClientID))
                TextField("Directory (tenant) ID", text: settings.binding(\.microsoftTenant))
                Text(
                    """
                    Microsoft public clients take no secret. Paste the directory \
                    (tenant) ID from the same Overview page: `common` works only \
                    for a registration that allows other tenants, and one of those \
                    will stop for admin approval. See SETUP.md.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .textFieldStyle(.roundedBorder)
    }

    private func connect(_ kind: ProviderKind) {
        connecting = kind
        error = nil
        Task {
            do {
                try await accounts.connect(kind)
            } catch {
                self.error = error.localizedDescription
            }
            connecting = nil
        }
    }
}
