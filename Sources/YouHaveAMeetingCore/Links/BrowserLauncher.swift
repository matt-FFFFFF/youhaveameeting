import AppKit
import os

/// Opens meeting links, honouring the browser chosen in Settings.
///
/// The stored preference is re-resolved at click time rather than trusted:
/// a chosen browser can be uninstalled or reset at any moment, and an alert
/// must never lose its one job — opening the meeting — because a preference
/// went stale.
@MainActor
enum BrowserLauncher {
    private static let log = Logger(subsystem: "app.youhaveameeting", category: "links")

    /// The browsers Launch Services knows about, as the picker should show them.
    ///
    /// Probed with a web URL so Launch Services lists apps that can actually
    /// open one; `BrowserChoice.list` does the filtering, deduping and sorting.
    static func installedBrowsers() -> [InstalledBrowser] {
        let https = URL(string: "https://example.com/")!
        return BrowserChoice.list(
            appURLs: NSWorkspace.shared.urlsForApplications(toOpen: https),
            bundleIdentifier: { Bundle(url: $0)?.bundleIdentifier },
            displayName: { FileManager.default.displayName(atPath: $0.path) }
        )
    }

    /// Opens `url` in the user's chosen browser.
    ///
    /// An empty or unresolvable preference falls back to the system default,
    /// logged at info: degrading to the default beats failing to open, because
    /// an alert must never lose its one job because a preference went stale.
    static func open(_ url: URL, preferringBundleID storedID: String) {
        switch BrowserChoice.resolve(
            storedBundleID: storedID,
            appURL: NSWorkspace.shared.urlForApplication(withBundleIdentifier: storedID)
        ) {
        case .systemDefault:
            log.info(
                """
                Opening link in system default browser; \
                stored browser \(storedID, privacy: .public) is unset or not installed
                """
            )
            NSWorkspace.shared.open(url)
        case let .application(app):
            log.info("Opening link in \(app.path, privacy: .public)")
            // The trailing completionHandler argument is required: without it
            // Swift resolves to the async overload, which cannot be awaited
            // from this synchronous Void function.
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: app,
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil
            )
        }
    }
}
