# You Have a Meeting

A macOS menu-bar app that makes meeting starts impossible to miss.

Standard notifications are a corner banner that vanishes on its own, and Focus
modes suppress them entirely — exactly when you are heads-down and most likely
to miss a call. This app instead takes over every display with a large card and
a single **Join** button. Because the alert is a plain window at
`CGShieldingWindowLevel`, not a user notification, Focus and Do Not Disturb
cannot suppress it and full-screen apps cannot cover it. It stays until you act
on it, and chimes at 0s / 15s / 30s / 60s and then every 60s while ignored.

When you are already in a call or presenting, it downgrades to a small,
silent corner banner rather than hijacking your screen share. It is never
fully silent.

## Status

| Phase | State |
|---|---|
| 1. Skeleton — build, bundle, menu bar, settings, login item | done |
| 2. Alert engine — shield windows, card, escalation, snooze, banner | done |
| 3. Auth + calendar providers (Google, Microsoft Graph) | done |
| 4a. Scheduler — armed timer, wake catch-up, fired log | done |
| 4b. Presence detection + silence policy | done |
| 5. Settings UI, per-account calendars, missed-meeting log | not started |

Connected calendars are polled, the next meeting is armed, and alerts fire for
real — downgrading to a corner banner when you are in a call, sharing your
screen, or have the **Presenting** toggle on.

Everything is configurable from the settings window (Command-comma) or the
menu bar. Remaining: per-account calendar selection and a missed-meeting log.

See [SETUP.md](SETUP.md) to connect an account.

## Requirements

- macOS 26+
- Xcode Command Line Tools (full Xcode is **not** required)
- [mise](https://mise.jdx.dev) — pins GNU Make, SwiftLint and SwiftFormat

## Getting started

```sh
mise install     # Make is itself a mise tool, so this comes first
make             # build + assemble "build/You Have a Meeting.app"
make install     # copy it to /Applications
```

| Target | Does |
|---|---|
| `make build` | `swift build -c release` |
| `make bundle` | build, assemble the `.app`, codesign |
| `make install` | build, then install to `/Applications` |
| `make test` | `swift test` |
| `make lint` | SwiftFormat `--lint` + SwiftLint `--strict` |
| `make fmt` | rewrite sources with SwiftFormat |
| `make alert` | build and show a fake full-screen alert |
| `make alert-banner` | same, in the silenced banner presentation |

Diagnostics, run against the built binary
(`"build/You Have a Meeting.app/Contents/MacOS/YouHaveAMeeting" --flag`):

| Flag | Does |
|---|---|
| `--list-meetings [--verbose]` | fetch the window and show what would be armed; titles only with `--verbose` |
| `--presence` | current presence signals and the alert style they produce |
| `--keychain-selftest` | which keychain backends this build can use |
| `--windows` | on-screen windows with owner and title, for identifying share markers |
| `--settings` | open the settings window at launch |
| `make clean` | remove `.build` and `build` |

### Meeting links

Join links come from the provider's structured field when there is one, and
otherwise from scanning the event location and description. The services
recognised by that scan are **configurable** in `settings.json` — Google Meet,
Microsoft Teams and Zoom are on by default, Webex ships disabled, and you can
add your own pattern for a self-hosted service. Order is priority. See
[SETUP.md](SETUP.md#recognised-meeting-links).

### Code signing

Builds are ad-hoc signed by default, which gives the app a new code identity on
every rebuild — the Keychain then treats each build as a different app and
re-prompts for the stored OAuth refresh tokens. Run
`Scripts/make-signing-cert.sh` once to create a stable self-signed identity;
`bundle.sh` picks it up automatically and falls back to ad-hoc if it is absent.

Two things to know about that:

- The certificate must be **trusted for code signing**, not merely present.
  `codesign` refuses an identity it cannot build a chain to, and
  `security find-identity -v` will not list an untrusted one. The script does
  this, and macOS prompts to authorise it.
- **A stable identity does not stop the Keychain prompt on rebuild.** Measured,
  not assumed: with the identity in place, three builds differing only in
  cdhash each prompted, including one immediately after choosing *Always
  Allow*. The ACL on a legacy keychain item pins the exact code that created
  it, and the certificate-based designated requirement does not override that.

  The prompt-free alternative is the data-protection keychain, which has no
  per-item ACLs — but `--keychain-selftest` reports
  `OSStatus -34018: A required entitlement isn't present.` for it, because that
  needs an application-identifier entitlement and therefore a real Team ID.

  So the prompt is inherent to self-signed development builds. It appears only
  when the binary actually changes, never on repeated runs of one build, so it
  costs nothing in normal use. Run `--keychain-selftest` to re-check if the app
  is ever signed with a Developer ID.

  The stable identity is still worth having — it is what makes the signature
  verifiable and the Designated Requirement meaningful.

The script imports the key and certificate as separate PEM files rather than a
PKCS#12 bundle. OpenSSL 3 writes PKCS#12 with AES-256 and a SHA-256 MAC, which
Apple's importer cannot verify — it reports `MAC verification failed (wrong
password?)`. Note also that `security import -f openssl` rejects the PKCS#8 key
OpenSSL 3 emits; letting `security` auto-detect the format is what works.

## Layout

```
Sources/YouHaveAMeetingCore/   library — all behaviour, unit-testable
  App/        AppDelegate, MenuBarController, LoginItem, LaunchOptions
  Alert/      ShieldWindow, BannerWindow, AlertCardView, AlertPresenter,
              EscalationSchedule
  Auth/       PKCE, OAuthConfig, OAuthClient, LoopbackServer, AuthSession,
              TokenStore
  Calendar/   CalendarProvider, GoogleCalendarProvider, GraphCalendarProvider,
              CalendarService, AccountManager
  Config/     Settings, SettingsStore
  Links/      MeetingLinkProvider, MeetingLinkParser
  Model/      Meeting, Account
Sources/YouHaveAMeeting/       executable — main.swift only
Scripts/                       bundle.sh, make-signing-cert.sh
```

## Toolchain notes

These are all consequences of building without full Xcode. They are recorded
because each one cost time to diagnose.

- **GNU Make is pinned through mise** (`conda:make@4.4.1`). Apple ships Make
  3.81 (2006) at `/usr/bin/make`, which lacks `.ONESHELL`. The Makefile refuses
  to run under it rather than failing obscurely later.
- **swift-testing is a package dependency, pinned to 6.2.4.** The Command Line
  Tools toolchain ships neither `Testing` nor `XCTest` — both come with Xcode.
  Consuming swift-testing as a package works, but from 6.3.0 its `Testing`
  target links `_TestingInterop`, a library only the Xcode toolchain provides,
  so 6.3.x fails at link time. 6.2.4 is the newest version that builds here.
  This is the app's only dependency and it is test-only.
- **The package is split into a library plus a thin executable.** Test targets
  cannot cleanly `@testable import` an executable target under this toolchain,
  and the split is better structure anyway.
- **SwiftLint needs a dyld hint.** It loads `sourcekitdInProc` at runtime and
  does not find it under Command Line Tools, so `make lint` sets
  `DYLD_FRAMEWORK_PATH="$(xcode-select -p)/usr/lib"`. No Xcode needed.
- **`swift test` prints two `Internal Error: DecodingError.dataCorrupted`
  lines** before the run starts. That is the test runner, not this package —
  a side effect of a 6.2.4 testing library under a 6.3.3 toolchain. Tests pass.
- **`Settings` decodes by hand.** The compiler-synthesised `Codable`
  initialiser treats a missing key as an error even when the property has a
  default, so a settings file written by an older build would fail to decode and
  silently reset every setting.

## Screen sharing detection

There is no public API for "is another app capturing the screen", so this
matches the indicator window the sharing app puts on screen. Two things make
that fragile, and both cost real debugging time:

- **The wording varies with what is shared.** Chromium browsers say
  `is sharing your screen`, `is sharing a window.` or `is sharing a tab.`
  depending on the choice, so the matcher keys off the common stem. The matcher
  is a pure function tested against strings captured from real sessions, plus a
  negative case built from an ordinary desktop so it cannot over-match.
- **Reading window titles needs Screen Recording permission, and asking for it
  is a separate act.** `CGWindowListCopyWindowInfo` never triggers a TCC check;
  it silently returns blank titles. An app that only calls it never appears in
  the Screen Recording list at all, because it has never asked. The menu item
  calls `CGRequestScreenCaptureAccess()`, which is what registers it. The
  permission takes effect on the next launch.

Running the binary from a terminal inherits the terminal's permission, so
`--presence` can report `true` while the GUI app has none. Trust the menu.

Use `--windows` while sharing to capture the actual marker for a service that
is not detected.

## Design notes

- **OAuth uses a loopback redirect, not a custom URL scheme.** The plan
  originally called for a custom scheme, but Google's is derived from the
  client ID, which the user supplies at runtime — so it cannot be declared in
  `Info.plist` at build time. A loopback listener works for both providers,
  needs nothing in the bundle, and removes the `ASWebAuthenticationSession`
  dependency. The listener binds an ephemeral port on the loopback interface
  only and shuts down as soon as the redirect arrives.
- **Access tokens are never persisted.** Only refresh tokens reach the
  Keychain; access tokens live in memory and are re-minted on demand.
- **Google needs a client secret; Microsoft does not.** Google's token endpoint
  rejects Desktop-app exchanges without `client_secret`, despite the client
  being public — so `OAuthConfig` carries a `requiresClientSecret` flag and the
  value is added only to token requests, never to the authorize URL. Entra ID
  public clients take no secret at all.
- **One failing account does not hide the others.** `CalendarService` logs and
  skips a provider that errors rather than failing the whole fetch.

## Open questions

- Launching the ad-hoc-signed binary from a terminal triggered a **microphone**
  permission prompt attributed to the terminal. Nothing in the code touches
  audio input yet. To be pinned down when `PresenceMonitor` is built in phase 4.
