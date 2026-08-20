# AGENTS.md

This file provides guidance to coding agents (Claude Code and similar) when
working with code in this repository. Human-facing docs are `README.md` and
`SETUP.md`.

## Commands

```sh
mise install                 # first, always: Make itself is a mise tool
make                         # build + assemble "build/You Have a Meeting.app"
make install                 # build, then install to /Applications
make test                    # swift test
make lint                    # SwiftFormat --lint + SwiftLint --strict
make fmt                     # rewrite sources with SwiftFormat
make icons                   # redraw Resources/AppIcon.icns (committed art)
make clean
```

Run a single suite or test (SwiftPM filters on the suite/test display name,
not the type name):

```sh
swift test --filter "SilencePolicy"
swift test --filter "no combination of any signal or mode is ever fully silent"
```

`make lint` must pass before a change is done. SwiftFormat rewrites files, so
run `make fmt` before `make lint` or the two will disagree.

### Diagnostics

Real behaviour is easier to check by running the built binary than by reasoning
about it. Each flag exercises the production path, not a parallel one.

```sh
APP="build/You Have a Meeting.app/Contents/MacOS/YouHaveAMeeting"
"$APP" --list-meetings [--verbose]   # fetch + what the scheduler would arm
"$APP" --presence                    # live signals and the style they produce
"$APP" --windows                     # on-screen windows, to find share markers
"$APP" --keychain-selftest           # which keychain backends this build can use
"$APP" --settings                    # open the settings window at launch
make alert / make alert-banner       # force a style, for window rendering only
```

`--list-meetings` omits meeting titles unless `--verbose`, so its output can be
pasted into a conversation without disclosing the user's calendar.

**Running the binary from a terminal inherits the terminal's TCC permissions.**
`--presence` can report Screen Recording as available while the GUI app has
none. Never conclude a permission is granted from a terminal run.

## Architecture

A library (`YouHaveAMeetingCore`) holds all behaviour; `Sources/YouHaveAMeeting`
is `main.swift` alone. Tests `@testable import` the library.

### The one path that matters

```
MeetingScheduler  ── armed timer fires ──▶  AppDelegate.present(meeting)
                                                    │
                              PresenceMonitor.currentSignals(settings:)
                                                    │
                              SilencePolicy.style(for:settings:)
                                                    │
                                    AlertPresenter.present(_:style:)
                                       ShieldWindow │ BannerWindow
```

Anything that shows an alert must go through `AppDelegate.present(_:)`. The
"Test Notification" menu item does, deliberately: a test that forced its own
style could disagree with real behaviour, which is worse than no test.

### Ownership

- **`SettingsStore`** is the single source of truth, `@Observable`, persisted as
  JSON. `settings.binding(\.someKey)` yields a SwiftUI binding that writes
  through and saves, so no view has a save step to forget.
- **`AccountManager`** turns stored `Account`s plus client IDs into live
  providers and owns the interactive sign-in. Call `rebuildProviders()` after
  anything that changes accounts or link providers.
- **`CalendarService`** (actor) fans a time window across providers, merges, and
  dedupes by `(title, start)`, preferring the copy that has a join link.
- **`AuthSession`** (actor, one per account) holds the access token and refreshes
  on demand. Serialised so concurrent fetches cannot double-refresh.
- **`MeetingScheduler`** arms exactly one sleeping task for the next fire time —
  there is no polling loop. Re-arms on refresh, `didWakeNotification`, and
  timezone change.

### Branding

The bell is one path set, `BellGlyph`, drawn on a 24x24 grid and fitted to
whatever rectangle the caller asks for. Both the menu-bar glyph
(`MenuBarIcon`, template images) and the app icon
(`Scripts/GenerateAppIcon.swift`) come from it, so they cannot drift apart.
`BRAND.md` is the spec: read it before changing any of the geometry.

`Resources/AppIcon.icns` is generated art but is committed - `make` must not
depend on a drawing step. Re-run `make icons` after changing the mark.

### Testable seams

These are pure functions or pure decoding, and are where new logic belongs:

`MeetingSchedule.next` · `SilencePolicy.style`/`reason` ·
`MenuBarIconState.current`/`nextTimeDrivenChange` ·
`EscalationSchedule.offset`/`gap` · `MeetingLinkParser` ·
`PresenceMonitor.isSharing(windows:)` · `Google/GraphCalendarProvider.decode` ·
`OAuthClient.formEncoded` · `LoopbackServer.queryItems(fromRequestHead:)`

## Invariants

Breaking one of these breaks the product, not just a test.

- **No sensor combination is ever fully silent.** The quietest inferred outcome
  is a banner. `PresenceMode` deliberately has no "do not disturb" case; a
  fully silent state was proposed and rejected. A property test asserts this
  across all signals × all modes.
- **Alerts never auto-dismiss.** They end only on Join, Snooze or Dismiss. An
  alert that disappears on its own is the failure the app exists to fix.
- **`FiredLog` keys on meeting id *and* start time**, so a rescheduled meeting
  alarms again instead of being suppressed by the old occurrence.
- **Access tokens are never persisted.** Only refresh tokens reach the Keychain.
  Microsoft rotates refresh tokens on every refresh — write the new one back or
  the next refresh fails.
- **One failing account must not hide the others.** `CalendarService` logs and
  skips a failing provider rather than failing the whole fetch.

## Toolchain constraints

All consequences of building without full Xcode. Each cost real time to
diagnose; do not re-derive them.

- **GNU Make is pinned via mise** (`conda:make@4.4.1`). Apple's `/usr/bin/make`
  is 3.81 and lacks `.ONESHELL`. The Makefile hard-errors under it.
- **swift-testing is pinned to 6.2.4** as a package dependency. Command Line
  Tools ships neither `Testing` nor `XCTest`. From 6.3.0 swift-testing links
  `_TestingInterop`, which only the Xcode toolchain provides, so 6.3.x fails at
  link. This is the only dependency, and it is test-only.
- **SwiftLint needs `DYLD_FRAMEWORK_PATH="$(xcode-select -p)/usr/lib"`** to find
  `sourcekitdInProc`. Already in the Makefile.
- **`swift test` prints two `Internal Error: DecodingError.dataCorrupted` lines**
  before running. That is the 6.2.4 runner under a 6.3.3 toolchain, not this
  package. Tests pass; ignore it.
- **`Settings` decodes by hand.** Synthesised `Codable` treats a missing key as
  an error even when the property has a default, which would make an older
  settings file fail to decode and silently reset every setting. New fields must
  be added to `init(from:)` with a default, and legacy keys migrated via
  `LegacyKeys` (see `presenceMode`).
- **SwiftFormat strips trailing commas and rewrites `case .x(let y)` to
  `case let .x(y)`.** Patch scripts that match on those forms will silently
  fail. Prefer targeted edits and re-read the file after `make fmt`.
- **Icon Composer needs full Xcode**, so the macOS 26 Liquid Glass look is
  painted by hand in `Scripts/GenerateAppIcon.swift` and baked into the
  `.icns`. A real `.icon` bundle would additionally follow the system's tinted
  and clear icon modes; a baked `.icns` cannot.

## Platform gotchas

- **OAuth uses a loopback redirect, not a custom URL scheme.** Google's scheme
  derives from the client ID, which is supplied at runtime and so cannot be in
  `Info.plist`. The redirect is `http://localhost:PORT` with no path — adding a
  path breaks redirect matching.
- **Google requires `client_secret` for Desktop-app clients** despite being a
  public client; Microsoft public clients reject one. Hence
  `OAuthConfig.requiresClientSecret`. The secret goes only to the token
  endpoint, never the authorize URL.
- **The Entra authority is per-installation, not a constant.** It was hardcoded
  to `common`, which every single-tenant registration — the portal's default —
  rejects with AADSTS50194. `Settings.microsoftTenant` supplies it via
  `OAuthConfig.microsoft(tenant:)`. Do not "simplify" it back to a constant:
  the other shape, a multi-tenant registration on `common`, is strictly worse.
  On a default tenant neither shape can user-consent to `Calendars.Read` — that
  gate is the low-impact permission classification, which no registration
  setting and no publisher verification alters — and multi-tenant additionally
  fails the verified-publisher gate that a registration in your own tenant
  passes for free. SETUP.md explains this to users.
- **Presence is sampled, never polled.** The menu-bar glyph's quiet state is
  read at the moments something already happens - the menu opening, the next
  meeting changing, an alert appearing, the five-minute warning starting - so
  it can lag a call that begins while nothing else is going on. Adding a poll
  to close that gap would undo `PresenceMonitor`'s on-demand design.
- **`CGWindowListCopyWindowInfo` never triggers a TCC check.** It silently
  returns blank titles, so an app that only calls it never appears in the Screen
  Recording list. Only `CGRequestScreenCaptureAccess()` registers it. Permission
  applies on next launch, and is per bundle path — `build/` and `/Applications`
  are separate grants.
- **Screen-share indicator wording varies**: `is sharing your screen`,
  `is sharing a window.`, `is sharing a tab.` Match the stem. Use `--windows`
  during a real share to capture a service's actual marker rather than guessing.
- **Keychain prompts on rebuild are inherent to self-signed builds.** Measured:
  three builds differing only in cdhash each prompted, including one right after
  "Always Allow". The legacy keychain ACL pins the exact code; the
  certificate-based Designated Requirement does not override it. The
  prompt-free data-protection keychain returns
  `OSStatus -34018` without a Team ID. Do not attempt to "fix" this again.
- **A microphone permission prompt was once attributed to the terminal** while
  launching the binary from it. `--presence` exercises the whole CoreAudio path
  without prompting, so it is not this app's device-property reads. Unexplained,
  not reproduced.

## Conventions

- Comments explain *why*, especially where the code encodes a platform
  workaround. Do not add comments that restate the code.
- British spelling in user-facing strings and comments.
- The executable is `YouHaveAMeeting` (no spaces, so `ps`/`pkill` work); the
  bundle and display name are `You Have a Meeting`.
