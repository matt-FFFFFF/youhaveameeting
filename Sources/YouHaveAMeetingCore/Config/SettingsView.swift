import SwiftUI

/// Every persisted setting, in one window. Values write through the store's
/// bindings, so there is no Save button and nothing to forget.
struct SettingsView: View {
    let settings: SettingsStore
    let accounts: AccountManager
    /// Called when a change needs the scheduler to re-arm immediately.
    let onScheduleAffectingChange: () -> Void

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(
                    settings: settings,
                    onScheduleAffectingChange: onScheduleAffectingChange
                )
            }
            Tab("Alerts", systemImage: "bell.badge") {
                AlertSettingsView(settings: settings)
            }
            Tab("Accounts", systemImage: "person.crop.circle") {
                AccountSettingsView(settings: settings, accounts: accounts)
            }
            Tab("Links", systemImage: "link") {
                MeetingLinkSettingsView(settings: settings)
            }
        }
        // A sidebar rather than a top tab bar: four labels overflow into a
        // ">>" chevron at any reasonable window width, hiding most of the
        // settings behind a menu.
        .tabViewStyle(.sidebarAdaptable)
        .frame(width: 640, height: 460)
    }
}

private struct GeneralSettingsView: View {
    let settings: SettingsStore
    let onScheduleAffectingChange: () -> Void

    var body: some View {
        Form {
            Section("Timing") {
                Picker("Alert me", selection: settings.binding(\.leadOffsetSeconds)) {
                    Text("When the meeting starts").tag(0)
                    Text("1 minute before").tag(-60)
                    Text("2 minutes before").tag(-120)
                    Text("5 minutes before").tag(-300)
                }
                Picker("Check calendars every", selection: settings.binding(\.pollIntervalSeconds)) {
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("30 minutes").tag(1800)
                }
                Picker("Load meetings", selection: settings.binding(\.lookaheadSeconds)) {
                    Text("Next 12 hours").tag(43200)
                    Text("Next 24 hours").tag(86400)
                    Text("Next 48 hours").tag(172_800)
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { try? LoginItem.setEnabled($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.value.pollIntervalSeconds) { onScheduleAffectingChange() }
        .onChange(of: settings.value.leadOffsetSeconds) { onScheduleAffectingChange() }
        .onChange(of: settings.value.lookaheadSeconds) { onScheduleAffectingChange() }
    }
}

private struct AlertSettingsView: View {
    let settings: SettingsStore

    var body: some View {
        Form {
            Section("Alert mode") {
                Picker("When a meeting starts", selection: settings.binding(\.presenceMode)) {
                    ForEach(PresenceMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section("Invitations") {
                Toggle(
                    "Alert for tentative and unanswered invitations",
                    isOn: settings.binding(\.alertUnconfirmedInvitations)
                )
                Text(
                    """
                    Meetings you have declined never alert. Turn this off to \
                    hear only from the ones you accepted.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            // Named for the mode that uses them. Left editable in the other
            // modes rather than greyed: they are still worth setting up for
            // when Automatic comes back, and the section title already says
            // who reads them.
            Section("Automatic mode detection") {
                Toggle("I'm in a call", isOn: settings.binding(\.silenceWhenMicActive))
                Toggle("My camera is on", isOn: settings.binding(\.silenceWhenCameraActive))
                Toggle("I'm sharing my screen", isOn: settings.binding(\.silenceWhenSharing))
            }

            Section {
                Text(
                    """
                    A quiet alert is a small banner in the corner instead of the \
                    full-screen takeover. Automatic decides from the conditions \
                    above; Presenting is always a banner; Full Screen always \
                    takes over, even when it looks like you are presenting. \
                    Alerts are never silenced completely.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                if settings.value.silenceWhenSharing, !PresenceMonitor.canReadWindowTitles() {
                    Label(
                        """
                        Screen Recording permission is needed to detect screen \
                        sharing. Without it, switch to Presenting by hand.
                        """,
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
    }
}
