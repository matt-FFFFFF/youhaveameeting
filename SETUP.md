# Connecting calendar accounts

The app talks to Google Calendar and Microsoft Graph directly, so each
installation registers its own credentials with them. It is a one-time job per
provider, and the fiddliest part of setting the app up.

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

1. Open **Settings** (⌘,) → **Accounts**.
2. Paste the Google **client ID** and **client secret**, and/or the Microsoft
   **client ID**. Microsoft does not use a secret.
3. Click **Connect Google…** or **Connect Microsoft…**. Your browser opens;
   approve the request, and the tab will tell you when it is done.

Refresh tokens are stored in the **login Keychain**, one item per account under
the service `app.youhaveameeting.oauth`. Access tokens are held in memory only.
**Accounts → Disconnect** removes both the account and its Keychain item.

macOS asks for Keychain access again after every rebuild, because each build is
a different app as far as it is concerned. This does not happen when you just
run an installed copy.

## Recognised meeting links

The Join button uses the meeting link the calendar provides directly, when there
is one. Many invitations do not have one — the link is just text in the
description — so those are scanned for known services.

Manage that list in **Settings (⌘,) → Links**. Google Meet, Microsoft Teams and
Zoom are on by default, and Webex is included but switched off. You can edit any
pattern, add your own service, or drag to reorder — the first match wins.

Paste a URL into the test box on that page to see which service it matches. A
pattern that is not valid is flagged there, and is ignored until you fix it
rather than breaking anything else.
