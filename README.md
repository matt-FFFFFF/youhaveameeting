# You Have a Meeting

A macOS menu-bar app that makes the start of a meeting impossible to miss.

Normal notifications are a small banner in the corner that disappears on its
own — and Focus modes hide them entirely, which is exactly when you are
heads-down and most likely to miss a call.

This app takes over every display instead: a large card with the meeting name
and a single **Join** button. It stays there until you deal with it, and chimes
at 0s, 15s, 30s, 60s and then every minute while you ignore it. Focus and Do Not
Disturb cannot suppress it, and full-screen apps cannot cover it.

If you are already in a call, sharing your screen, or have set the mode to
**Presenting**, it shows a small silent banner in the corner instead — so it
never hijacks your screen share. **Full Screen** mode is the other way round:
it takes over regardless of what the sensors think. It is never completely
silent.

It is cheap to leave running: about **20 MB** of memory and **0% CPU** while it
waits, which is nearly all the time. Nothing polls on a timer: the microphone
and camera tell the app when they start and stop, and everything else is read
only at the moments something already happens.

## Requirements

- macOS 26 or later
- Xcode Command Line Tools — full Xcode is **not** needed
- [mise](https://mise.jdx.dev), which fetches the few build tools

## Install

```sh
mise install
make install
```

That builds the app and copies it to `/Applications`. Open it from there.

Optional, once:

```sh
./Scripts/make-signing-cert.sh
```

This creates a stable self-signed code-signing identity, so each build is signed
with the same certificate instead of an ad-hoc signature. macOS will ask you to
authorise the certificate.

It does **not** stop the Keychain prompts. macOS asks for access to the stored
OAuth tokens after every rebuild whether or not you run this.

## First run

1. Connect a calendar — see **[SETUP.md](SETUP.md)**. This is the fiddly part:
   Google and Microsoft each need a one-time app registration in their consoles.
2. Open **Settings** (⌘,) → **Accounts**, paste the client ID (and, for Google,
   the client secret), then click **Connect**.
3. Menu bar → **Grant Screen Recording permission…**, then quit and reopen the
   app. Without this it cannot tell when you are sharing your screen, and may
   take over the display mid-presentation.

The menu bar shows your next meeting, or says plainly that nothing is connected
or nothing is scheduled.

The icon itself is a bell, and it tells you where things stand without opening
the menu:

- **Outline** — nothing due soon.
- **Filled** — a meeting is about five minutes from alarming.
- **Filled, with sound lines** — an alert is on screen and has not been dealt
  with.
- **Outline with a slash** — alerts are quiet right now, because you are
  presenting, in a call, or sharing your screen. Playing music through an audio
  interface does not count as being in a call. The next one will be a corner
  banner rather than a takeover.
- **Outline with sound lines** — **Full Screen** mode is on, so the next alert
  will take over the screen whatever you happen to be doing.

## Using it

Click the menu-bar icon for:

- **Your next meeting**, and when the calendar was last checked
- **Refresh Now** (⌘R) and **Check Every** — 1, 5, 15 or 30 minutes
- **Accounts** — connect or disconnect calendars
- **Alert Mode** — **Automatic** lets the sensors decide, **Presenting** forces
  the quiet banner, **Full Screen** forces the takeover
- **Automatic Mode Detection** — in a call, camera on, sharing your screen.
  Says "(not in use)" when the mode is Presenting or Full Screen, since nothing
  in there decides anything then
- **Test Notification** — fires a sample alert. The label tells you whether you
  will get the full screen or a banner, based on what you are doing right now
- **Settings…** (⌘,)

When an alert appears: **Join** opens the meeting, **1/2/5 min** snoozes, and
**Dismiss** closes it. Nothing closes it on its own.

## Settings (⌘,)

**General** — how early to alert, how often to check, how far ahead to look,
and launch at login.

**Alerts** — the alert mode, and which situations Automatic treats as quiet.

**Accounts** — connect and disconnect calendars, and the client IDs from
[SETUP.md](SETUP.md).

**Links** — which conferencing services are recognised in meeting invitations.
Google Meet, Teams and Zoom are on by default; Webex is included but off. You
can edit a pattern, add your own service, or drag to reorder (the first match
wins). There is a box to paste a URL and see which service it matches.

## If something is not working

**No alert fired.** Check the menu shows the meeting. If it says "No calendar
connected", finish [SETUP.md](SETUP.md). If it shows a meeting but nothing
happened, check whether the menu says "Alerts quiet: …" — you may have been in a
call, or have the mode left on **Presenting**.

**It took over the screen while I was presenting.** Screen-share detection needs
Screen Recording permission, granted to the exact copy of the app you are
running. Menu bar → **Grant Screen Recording permission…**, then relaunch.
Setting the mode to **Presenting** always works, permission or not. Also check
the mode is not left on **Full Screen**, which overrides the detection on
purpose.

**No Join button on the alert.** The invitation had no link the app recognises.
Settings → **Links**, paste the URL into the test box, and add a pattern for
that service if nothing matches.

**Google signs me out after about a week.** The OAuth consent screen is still in
*Testing*; Google expires refresh tokens after 7 days in that state. Publish it
— see [SETUP.md](SETUP.md).

**macOS keeps asking for Keychain access.** Expected after every rebuild, with
or without the signing certificate — running `make install` again re-prompts.
Simply running an installed copy, without rebuilding it, does not.

## Contributing

`AGENTS.md` documents the architecture, the invariants that must hold, and the
toolchain quirks — worth reading before changing anything.

```sh
make test    # 85 tests
make lint
make fmt
```

## Licence

[MIT](LICENSE) © Matt White
