/// Command-line switches. Parsed into a value so the behaviour can be tested
/// without launching the app.
struct LaunchOptions: Equatable, Sendable {
    /// Show a fake alert immediately at launch, for manual verification.
    var testAlert = false
    /// Which presentation the fake alert uses.
    var testAlertStyle: AlertStyle = .takeover
    /// Fetch the upcoming window, print it, and exit.
    var listMeetings = false
    /// Include meeting titles in that listing. Off by default so the output can
    /// be shared without disclosing what the meetings are.
    var verbose = false
    /// Report which keychain backends this build can actually use.
    var keychainSelfTest = false
    /// Print current presence signals and the alert style they produce.
    var presence = false
    /// Open the settings window at launch.
    var openSettings = false
    /// Dump on-screen windows, to identify screen-sharing markers.
    var listWindows = false

    init() {}

    init(arguments: [String]) {
        testAlert = arguments.contains("--test-alert")
        testAlertStyle = arguments.contains("--banner") ? .banner : .takeover
        listMeetings = arguments.contains("--list-meetings")
        verbose = arguments.contains("--verbose")
        keychainSelfTest = arguments.contains("--keychain-selftest")
        presence = arguments.contains("--presence")
        openSettings = arguments.contains("--settings")
        listWindows = arguments.contains("--windows")
    }
}
