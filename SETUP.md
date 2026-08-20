# Connecting calendar accounts

The app talks to Google Calendar and Microsoft Graph directly, as a public
OAuth client. Public clients have no usable secret, so each installation
registers its own client ID. This is a one-time job per provider.

Both providers use a **loopback redirect** — the app opens your browser, then
listens on a temporary `localhost` port for the response. Nothing is exposed to
the network and there is no URL scheme to register.

## Google

1. [Google Cloud Console](https://console.cloud.google.com) → create or pick a
   project.
2. **APIs & Services → Library** → enable **Google Calendar API**.
3. **APIs & Services → OAuth consent screen** → configure it. Add your own
   address under *Test users* if the user type is External.
4. **Publish the consent screen** (`Publishing status → In production`).
   This matters: while the screen is in *Testing*, Google expires refresh
   tokens after **7 days** and the app will silently log itself out every week.
   Staying *unverified* in production is fine for personal use — you will see a
   "Google hasn't verified this app" interstitial on first sign-in.
5. **Credentials → Create credentials → OAuth client ID → Desktop app.**
   Copy **both the Client ID and the Client Secret**. There is no redirect URI
   to enter; the desktop client type permits loopback automatically.

   Google's token endpoint rejects Desktop-app exchanges that omit
   `client_secret`, so both values are required. Google does not treat this
   secret as confidential — it ships inside the JSON the console offers for
   download, and anyone holding the app holds it too. PKCE is what actually
   secures the exchange. It is sent only to the token endpoint, never in the
   authorize URL.

Scope requested: `calendar.events.readonly`.

## Microsoft 365

1. [Entra admin centre](https://entra.microsoft.com) → **App registrations →
   New registration**.
2. Under **Redirect URI**, choose **Public client/native (mobile & desktop)**
   and enter `http://localhost`.
3. After creating it, open **Authentication** and confirm **Allow public client
   flows** is **Yes**.
4. **API permissions → Add a permission → Microsoft Graph → Delegated
   permissions → `Calendars.Read`.** Some tenants require an administrator to
   grant consent — if the app reports a consent error at sign-in, this is why.
5. Copy the **Application (client) ID** from the Overview page.

Scopes requested: `Calendars.Read offline_access openid profile`.

## Entering the client IDs

There is no settings window yet (phase 5), so the IDs go into the settings file
by hand:

1. Menu bar icon → **Accounts → Reveal Settings File**.
2. Edit `settings.json`, filling in `googleClientID` **and** `googleClientSecret`,
   and/or `microsoftClientID`. Microsoft takes no secret.
3. Quit and relaunch the app.
4. Menu bar icon → **Accounts → Connect Google...** / **Connect Microsoft...**.
   Your browser opens; approve, and the tab will tell you it is done.

Refresh tokens are stored in the **login Keychain**, one item per account under
the service `app.youhaveameeting.oauth`. Access tokens are held in memory only.
**Accounts → Disconnect** removes both the account and its Keychain item.

If you are still on an ad-hoc-signed build, macOS will ask for Keychain access
again after every rebuild, because each build has a different code identity.
Run `Scripts/make-signing-cert.sh` once to stop that.

## Recognised meeting links

Join links are taken from the provider's structured field first
(`conferenceData.entryPoints` on Google, `onlineMeeting.joinUrl` on Graph). If
the event has none, the location and description are scanned using the
configurable provider list in `settings.json`:

```json
"meetingLinkProviders": [
  { "id": "google-meet", "name": "Google Meet", "pattern": "...", "isEnabled": true },
  { "id": "teams",       "name": "Microsoft Teams", "pattern": "...", "isEnabled": true },
  { "id": "zoom",        "name": "Zoom", "pattern": "...", "isEnabled": true }
]
```

Order is priority — the first pattern that matches wins. Webex ships as a
built-in but is disabled by default; add it, or add your own entry for a
self-hosted service, by appending to this list. A pattern that fails to compile
is skipped and logged, never fatal.
