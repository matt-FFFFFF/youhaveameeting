import Foundation
import Testing
@testable import YouHaveAMeetingCore

@Suite("Browser choice")
struct BrowserChoiceTests {
    @Test("list() sorts by display name")
    func sortsByDisplayName() throws {
        let safari = try #require(URL(string: "file:///Applications/Safari.app"))
        let firefox = try #require(URL(string: "file:///Applications/Firefox.app"))
        let brave = try #require(URL(string: "file:///Applications/Brave%20Browser.app"))
        let ids = [safari: "com.apple.Safari", firefox: "org.mozilla.firefox", brave: "com.brave.Browser"]
        let names = [safari: "Safari", firefox: "Firefox", brave: "Brave Browser"]

        // Listed Safari-first on disk; the menu must still read alphabetically.
        let browsers = BrowserChoice.list(
            appURLs: [safari, firefox, brave],
            bundleIdentifier: { ids[$0] },
            displayName: { names[$0] ?? "" }
        )

        #expect(browsers.map(\.name) == ["Brave Browser", "Firefox", "Safari"])
    }

    @Test("list() dedupes by bundle identifier, keeping the first occurrence")
    func dedupesKeepingFirst() throws {
        let userCopy = try #require(URL(string: "file:///Users/me/Applications/Chromium.app"))
        let systemCopy = try #require(URL(string: "file:///Applications/Chromium.app"))
        let firefox = try #require(URL(string: "file:///Applications/Firefox.app"))
        let ids = [
            userCopy: "org.chromium.Chromium",
            systemCopy: "org.chromium.Chromium",
            firefox: "org.mozilla.firefox"
        ]
        let names = [
            userCopy: "Chromium (user)",
            systemCopy: "Chromium (system)",
            firefox: "Firefox"
        ]

        // Launch Services ranks copies; the first listing wins so the choice
        // matches what the system would launch.
        let browsers = BrowserChoice.list(
            appURLs: [userCopy, systemCopy, firefox],
            bundleIdentifier: { ids[$0] },
            displayName: { names[$0] ?? "" }
        )

        #expect(browsers == [
            InstalledBrowser(bundleIdentifier: "org.chromium.Chromium", name: "Chromium (user)"),
            InstalledBrowser(bundleIdentifier: "org.mozilla.firefox", name: "Firefox")
        ])
    }

    @Test("list() drops entries with no bundle identifier")
    func dropsNilBundleIdentifiers() throws {
        let safari = try #require(URL(string: "file:///Applications/Safari.app"))
        let notAnApp = try #require(URL(string: "file:///Applications/NotAnApp.bundle"))

        let browsers = BrowserChoice.list(
            appURLs: [notAnApp, safari],
            bundleIdentifier: { $0 == safari ? "com.apple.Safari" : nil },
            displayName: { $0 == safari ? "Safari" : "Not An App" }
        )

        #expect(browsers == [InstalledBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")])
    }

    @Test("resolve() falls back to the system default when the stored identifier is empty")
    func emptyStoredIdentifierFallsBack() throws {
        let firefox = try #require(URL(string: "file:///Applications/Firefox.app"))

        #expect(BrowserChoice.resolve(storedBundleID: "", appURL: firefox) == .systemDefault)
    }

    @Test("resolve() opens the chosen application when both are set")
    func resolvesToApplication() throws {
        let firefox = try #require(URL(string: "file:///Applications/Firefox.app"))

        #expect(
            BrowserChoice.resolve(storedBundleID: "org.mozilla.firefox", appURL: firefox)
                == .application(firefox)
        )
    }

    @Test("resolve() falls back to the system default when no app URL is available")
    func missingAppURLFallsBack() {
        #expect(BrowserChoice.resolve(storedBundleID: "org.mozilla.firefox", appURL: nil) == .systemDefault)
    }
}
