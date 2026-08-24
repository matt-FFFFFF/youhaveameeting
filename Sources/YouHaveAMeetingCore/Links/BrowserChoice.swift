import Foundation

/// A browser installed on this Mac, as the browser picker should show it.
///
/// Pure data: discovery itself stays in the AppKit layer, so this seam can be
/// tested without touching Launch Services.
struct InstalledBrowser: Identifiable, Equatable, Sendable {
    let bundleIdentifier: String
    let name: String
    var id: String { bundleIdentifier }
}

/// Where a meeting link should be opened.
enum LinkDestination: Equatable {
    case systemDefault
    case application(URL)
}

/// Decides how a meeting link is opened and which browsers can be offered.
///
/// Pure functions over injected lookups so the choice logic is testable
/// without Launch Services; the AppKit wrapper supplies `NSWorkspace` answers.
enum BrowserChoice {
    /// Turns a Launch Services application listing into the picker's rows.
    ///
    /// Entries whose bundle identifier cannot be read are dropped — they
    /// cannot be launched by identifier later. Duplicates keep the *first*
    /// occurrence because Launch Services returns copies in its own ranking
    /// order (user ≻ Applications ≻ …), so the first listing is the one the
    /// system would launch. Sorted for display with a localized, numeric-aware
    /// comparison so names read naturally in the menu.
    static func list(
        appURLs: [URL],
        bundleIdentifier: (URL) -> String?,
        displayName: (URL) -> String
    ) -> [InstalledBrowser] {
        var seen = Set<String>()
        var browsers: [InstalledBrowser] = []
        for url in appURLs {
            guard let id = bundleIdentifier(url), seen.insert(id).inserted else { continue }
            browsers.append(InstalledBrowser(bundleIdentifier: id, name: displayName(url)))
        }
        return browsers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Maps the stored preference onto an openable destination.
    ///
    /// Never fails open onto a guess: a stored identifier only counts when an
    /// app URL has actually been resolved for it. If either half is missing —
    /// empty preference, or the browser uninstalled since it was chosen — the
    /// link goes to the system default rather than to a stale target.
    static func resolve(storedBundleID: String, appURL: URL?) -> LinkDestination {
        guard !storedBundleID.isEmpty, let appURL else { return .systemDefault }
        return .application(appURL)
    }
}
