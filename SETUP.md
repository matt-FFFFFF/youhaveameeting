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
2. Leave **Supported account types** on **Accounts in this organizational
   directory only** — the single-tenant default. Do not make it multi-tenant;
   see below.
3. Under **Redirect URI**, choose **Public client/native (mobile & desktop)**
   and enter `http://localhost`.
4. After creating it, open **Authentication** and confirm **Allow public client
   flows** is **Yes**.
5. **API permissions → Add a permission → Microsoft Graph → Delegated
   permissions → `Calendars.Read`.** Delegated, not Application: application
   permissions always require an administrator.
6. Copy **both** the **Application (client) ID** and the **Directory (tenant)
   ID** from the Overview page. The app needs both.

Scopes requested: `Calendars.Read offline_access openid profile`.

### Why single-tenant, and why the tenant ID

Entra decides which sign-in endpoint a registration may use from its supported
account types, and the two settings fail in opposite directions:

- A **single-tenant** registration is rejected by the shared `common` endpoint
  with **AADSTS50194** (*"not configured as a multi-tenant application"*). It
  has to sign in against its own tenant, which is why the directory (tenant) ID
  is asked for.
- A **multi-tenant** registration can use `common`, but it then runs into
  [risk-based step-up consent][consent]: since November 2020, an ordinary user
  cannot consent to a multi-tenant app from an unverified publisher for
  anything beyond basic sign-in. `Calendars.Read` is beyond it, so every
  sign-in stops at **"Need admin approval"**. [Publisher verification][verify]
  clears that, and is far more work than pasting a tenant ID.

Single-tenant with your own tenant ID avoids both. If an admin has set user
consent to **Do not allow user consent** for the whole tenant, no registration
shape gets round it — an administrator has to press **Grant admin consent for
&lt;organisation&gt;** on the registration's **API permissions** page once.

If you sign in with a personal Microsoft account rather than a work one, there
is no tenant to name: register for **personal Microsoft accounts** and put
`common` in the tenant field.

[consent]: https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-risk-based-step-up-consent
[verify]: https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview

## Entering the client IDs

1. Open **Settings** (⌘,) → **Accounts**.
2. Paste the Google **client ID** and **client secret**, and/or the Microsoft
   **client ID** and **directory (tenant) ID**. Microsoft does not use a
   secret. Leaving the tenant field empty means `common`, which only works for
   a registration that allows other tenants.
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
