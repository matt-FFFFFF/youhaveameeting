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
3. **APIs & Services → OAuth consent screen** → configure it.

   If this is a **Google Workspace** account — a work address rather than
   `@gmail.com` — choose **User type: Internal**, and skip step 4. Internal is
   the better option wherever it is offered: no verification process, no
   "unverified app" interstitial, no seven-day token expiry, and the client
   only works for accounts in your own organisation.

   Otherwise choose **External**, and add your own address under *Test users*.
4. *External only.* **Publish the consent screen** (`Publishing status → In
   production`). This matters: while the screen is in *Testing*, Google expires
   refresh tokens after **7 days** and the app will silently log itself out
   every week. Staying *unverified* in production is fine for personal use —
   you will see a "Google hasn't verified this app" interstitial on first
   sign-in.
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

If the sign-in is refused outright on a Workspace account, an administrator has
restricted third-party apps under **Admin console → Security → Access and data
control → API controls → App access control**, and has to trust the client ID.
An app registered inside your own organisation is the easiest case for this.

## Microsoft 365

**Check this first.** Graph reads calendars out of Exchange Online mailboxes. If
your organisation runs Google Workspace and only uses Entra for single sign-on —
federated to Google as the identity provider — there is no mailbox behind it,
and Graph returns no events however the registration is set up. Use the Google
section above with your work address instead. `dig MX <your-domain>` answers
this in one command: Google Workspace domains point at `aspmx.l.google.com`.

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
account types. A **single-tenant** registration is rejected by the shared
`common` endpoint with **AADSTS50194** (*"not configured as a multi-tenant
application"*), so it has to sign in against its own tenant — which is why the
directory (tenant) ID is asked for. Multi-tenant can use `common`, but buys
nothing here and is subject to an extra restriction, so single-tenant is what
this app assumes.

If you sign in with a personal Microsoft account rather than a work one, there
is no tenant to name: register for **personal Microsoft accounts** and put
`common` in the tenant field.

### "Need admin approval"

Most work tenants stop here, and no registration setting gets round it.

The default tenant policy is *"Allow user consent for apps from verified
publishers, for selected permissions"*. It lets a user consent only when
**both** of these hold — they are separate gates, and it is the second one that
bites:

1. the app is from a [verified publisher][verify] **or** is registered in your
   own tenant, and
2. every permission it requests is classified **low impact**.

By default exactly five permissions are classified low impact: `openid`,
`profile`, `email`, `offline_access` and `User.Read`. `Calendars.Read` is not
among them, and neither is `Calendars.ReadBasic`.

So a single-tenant registration clears the first gate and still fails the
second. Nothing available on the registration changes that:

- **Multi-tenant** fails both gates rather than one.
- **Publisher verification** only ever satisfies the first gate — the one a
  single-tenant registration already meets — so it would not help. It also
  requires a verified Microsoft partner global account, an app registered with
  a work account, and a publisher domain that is not `*.onmicrosoft.com`.
- **`Calendars.ReadBasic`** is no more consentable than `Calendars.Read`, and
  it omits the event body, which is where most non-Teams join links live. It
  would cost Join buttons without buying anything.

The **API permissions** page reporting *Admin consent required: **No*** is not a
contradiction. That column is a static property of the permission as published
by Graph — it means the scope is not inherently admin-only — and it knows
nothing about your tenant's [consent policy][consent]. **AADSTS90094** (*the
grant requires admin permission*) on the failure page is the tenant policy
talking.

What resolves it is one of:

- an administrator pressing **Grant admin consent for &lt;organisation&gt;** on
  the registration's **API permissions** page, once. It is scoped to this one
  app, and is the smallest thing to ask for.
- an administrator classifying `Calendars.Read` as low impact under
  **Enterprise applications → Consent and permissions → Permission
  classifications**. This applies to every app in the tenant, so the option
  above is usually preferred.
- the [admin consent workflow][workflow], where it is enabled: the block screen
  gains a *Request approval* button and the request is filed in-product.

[verify]: https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview
[consent]: https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-user-consent
[workflow]: https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-admin-consent-workflow

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

Meetings organised inside your own organisation usually carry a structured
link; invitations from outside it often do not, and arrive with the join URL
in the description and a location reading only "Microsoft Teams Meeting". Both
paths matter, which is why the description is scanned at all.

Manage that list in **Settings (⌘,) → Links**. Google Meet, Microsoft Teams and
Zoom are on by default, and Webex is included but switched off. You can edit any
pattern, add your own service, or drag to reorder — the first match wins.

Paste a URL into the test box on that page to see which service it matches. A
pattern that is not valid is flagged there, and is ignored until you fix it
rather than breaking anything else.
