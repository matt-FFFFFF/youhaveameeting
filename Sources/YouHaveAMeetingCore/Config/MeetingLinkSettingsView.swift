import SwiftUI

/// The configurable list of conferencing services recognised in event text.
///
/// Patterns are editable in place. An invalid one is flagged here rather than
/// being silently skipped by the parser at alert time.
struct MeetingLinkSettingsView: View {
    let settings: SettingsStore

    @State private var newName = ""
    @State private var newPattern = ""
    @State private var addError: String?
    @State private var testURL = ""
    @State private var testResult = "Enter a URL to see which service matches."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                Section("Recognised services") {
                    let providers = settings.value.meetingLinkProviders
                    ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                        MeetingLinkRow(settings: settings, index: index, provider: provider)
                    }
                    .onMove { source, destination in
                        settings.update {
                            $0.meetingLinkProviders.move(fromOffsets: source, toOffset: destination)
                        }
                    }
                }

                Section("Test a link") {
                    TextField("Paste a meeting URL", text: $testURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: testURL) { updateTestResult() }
                        .onChange(of: settings.value.meetingLinkProviders) { updateTestResult() }
                    Text(testResult)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("Add a service") {
                    TextField("Name", text: $newName)
                    TextField("URL pattern (regular expression)", text: $newPattern)
                        .font(.system(.body, design: .monospaced))
                    if let addError {
                        Label(addError, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    Button("Add", action: add)
                        .disabled(newName.isEmpty || newPattern.isEmpty)
                }
                .textFieldStyle(.roundedBorder)
            }

            Text("Drag to reorder. The first pattern that matches wins.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    /// Runs the real parser, so this reports exactly what an alert would do.
    private func updateTestResult() {
        guard !testURL.isEmpty else {
            testResult = "Enter a URL to see which service matches."
            return
        }
        for provider in settings.value.meetingLinkProviders where provider.isEnabled {
            let parser = MeetingLinkParser(providers: [provider])
            if parser.firstLink(in: testURL) != nil {
                testResult = "Matches \(provider.name)."
                return
            }
        }
        testResult = "No enabled service matches this URL."
    }

    private func add() {
        do {
            _ = try NSRegularExpression(pattern: newPattern)
        } catch {
            addError = "Not a valid regular expression: \(error.localizedDescription)"
            return
        }
        addError = nil

        let slug = newName.lowercased().replacingOccurrences(of: " ", with: "-")
        settings.update {
            $0.meetingLinkProviders.append(
                MeetingLinkProvider(id: slug, name: newName, pattern: newPattern)
            )
        }
        newName = ""
        newPattern = ""
    }
}

/// One editable provider.
private struct MeetingLinkRow: View {
    let settings: SettingsStore
    let index: Int
    let provider: MeetingLinkProvider

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Name", text: settings.binding(\.meetingLinkProviders[index].name))
                TextField(
                    "URL pattern",
                    text: settings.binding(\.meetingLinkProviders[index].pattern)
                )
                .font(.system(.body, design: .monospaced))

                if let error = patternError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                Button("Remove", role: .destructive) {
                    settings.update {
                        $0.meetingLinkProviders.removeAll { $0.id == provider.id }
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.top, 4)
        } label: {
            HStack {
                // Reordering works by dragging the row, but nothing said so.
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .help("Drag to reorder")
                Toggle(
                    provider.name,
                    isOn: settings.binding(\.meetingLinkProviders[index].isEnabled)
                )
                Spacer()
                if patternError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("This pattern will be ignored until it is fixed")
                }
            }
        }
    }

    /// Recomputed as you type, so a broken pattern is obvious immediately
    /// rather than at alert time.
    private var patternError: String? {
        do {
            _ = try NSRegularExpression(pattern: provider.pattern)
            return nil
        } catch {
            return "Invalid regular expression: \(error.localizedDescription)"
        }
    }
}
