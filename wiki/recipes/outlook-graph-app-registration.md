---
title: Outlook + Microsoft Graph — one-time Entra app registration for PROXY
tags: [outlook, msgraph, oauth, entra, azure-ad, email-vertical, proxy-19, tier-2]
---

# Outlook + Microsoft Graph — one-time Entra app registration for PROXY

## Problem

PROXY's email-management vertical (ADR 005; slices 19 → 26) needs delegated access to the RelyMD Outlook mailbox via Microsoft Graph: read folders/messages, send mail, move/delete, manage `MailboxSettings`, plus read-only calendar for slice 26. None of that works without an Entra (Azure AD) app registration in the RelyMD tenant.

This is a one-time setup. Jonathan is tenant admin for RelyMD, so no external IT gate — he self-registers, self-consents, and copies the resulting `tenant_id` + `client_id` + `client_secret` into PROXY's config.

This recipe is the prerequisite for `proxy outlook connect` (CLI) and the Settings → Integrations → "Connect Outlook" button to do anything. Run it once per tenant per developer machine that needs PROXY's Outlook integration.

## Outputs (what you'll paste into PROXY config when done)

- **Tenant ID** — RelyMD's directory GUID. Same value every developer sees.
- **Application (client) ID** — GUID identifying the PROXY app in the tenant.
- **Redirect URI** — fixed: `http://localhost:3000/api/integrations/outlook/callback`.

> Slice 19 ships an **OAuth 2.0 code + PKCE** flow (RFC 7636). The app is registered as a **public client** with `code_challenge_method=S256`, so there is **no client secret to generate, store, or rotate** — the PKCE verifier on each consent attempt is the ephemeral substitute. If your previous notes mentioned a `client_secret`, ignore them: PROXY no longer asks for one.

## Steps

### 1. Open the Entra admin center

Sign in at <https://entra.microsoft.com> with your tenant-admin account (`jonathan.sells@relymd.com`). Top-left "Directory" picker → confirm RelyMD tenant is selected.

Navigate: **Identity → Applications → App registrations**.

### 2. Register a new application

Click **+ New registration**.

- **Name:** `PROXY — Outlook (developer machine — <your-username>)`. Per-machine naming makes credential rotation/revocation surgical when one machine is decommissioned.
- **Supported account types:** *Accounts in this organizational directory only (RelyMD only — Single tenant)*. We do not need multi-tenant access; staying single-tenant tightens the blast radius.
- **Redirect URI:**
  - Platform: **Web**
  - Value: `http://localhost:3000/api/integrations/outlook/callback`

Click **Register**.

You're dropped on the app's **Overview** page. Copy now:

- **Application (client) ID** → `MS_CLIENT_ID`
- **Directory (tenant) ID** → `MS_TENANT_ID`

### 3. Configure the redirect URI's response mode

Side nav → **Authentication**.

Under **Web → Redirect URIs**, confirm `http://localhost:3000/api/integrations/outlook/callback` is present. Microsoft only allows `http://localhost` (no port restriction) and `https://...` for web platform URIs — `http://127.0.0.1:3000/...` would be rejected; use `localhost`.

Under **Implicit grant and hybrid flows**, leave both boxes **unchecked** (PROXY uses the authorization code flow, not implicit).

Under **Advanced settings → Allow public client flows**, set to **Yes**. Slice 19 uses the public-client / PKCE flow — no client secret, the PKCE `code_verifier` on each consent attempt is what proves possession of the code.

**Save**.

### 4. Add API permissions

Side nav → **API permissions**. By default the app has `User.Read` (Microsoft Graph, delegated). Click **+ Add a permission → Microsoft Graph → Delegated permissions** and add:

| Permission | Why PROXY needs it |
|---|---|
| `Mail.ReadWrite` | List folders, fetch messages, move between folders, mark read/unread (slices 19 → 21). |
| `Mail.Send` | Reviewer "approve & send" / iterative compose (slice 22). |
| `MailboxSettings.ReadWrite` | Read working hours + signature; write auto-reply (folder taxonomy bootstrap, slice 21). |
| `User.Read` | Resolve the connected mailbox's email + display name for the Settings page label (already present by default). |
| `Calendars.Read` | Email-to-calendar conflict detection (slice 26; batched here so users consent once, not twice). |
| `offline_access` | Required to receive a refresh token. **Easy to miss** — without it, every access token expires after 1h and the daemon has no way to silently refresh. |

Click **Add permissions**.

You'll now see 6 delegated Microsoft Graph permissions in the list, each with the **Status** column showing "Not granted for RelyMD" with a yellow icon.

### 5. Grant admin consent

Click **Grant admin consent for RelyMD** (the button just above the permissions list). Confirm in the dialog. All 6 rows should flip to a green check and "Granted for RelyMD".

This step is what makes the consent screen during `proxy outlook connect` a single-click affirmation rather than a long-form delegated-permissions consent — the tenant already approved on behalf of all users.

If the button is greyed out, you're signed in with an account that isn't Global Admin or Application Admin in the RelyMD tenant. Switch accounts.

### 6. (No client secret — PKCE replaces it)

Skip this step. PROXY's public-client + PKCE flow does not use a `client_secret`; the **Certificates & secrets** blade stays empty. RFC 7636's `code_verifier` ↔ `code_challenge` round-trip is what proves the daemon owns the authorization code, so there is no long-lived secret to rotate or revoke.

If your tenant policy requires every app registration to have *some* credential, you can add a certificate instead of a secret — but slice 19 will not use it.

### 7. (Optional) Pin a single user for testing

For dev machines you can scope the app to a single user during testing to avoid accidentally affecting other RelyMD mailboxes. Side nav → **Enterprise applications → PROXY — Outlook … → Properties → Assignment required = Yes**, then **Users and groups → + Add user** and pick yourself.

Skip this for production-style usage where any user in the tenant should be able to connect.

### 8. Wire the values into PROXY config

Two values land in two places. There is no `client_secret` (see step 6).

**`.env`** in the tachikoma-starter checkout (gitignored; mirrored from `.env.example`). Both the Rust daemon and the Next.js app read these via `process.env` / `std::env::var`:

```dotenv
# Outlook / MS Graph OAuth — values from the Entra app you registered above.
MS_TENANT_ID=<paste tenant_id GUID>
MS_CLIENT_ID=<paste application/client_id GUID>
MS_OAUTH_REDIRECT_URI=http://localhost:3000/api/integrations/outlook/callback
```

**`~/.config/proxy/proxy.toml`** (machine-wide config; per ADR 004) — optional, useful when running the daemon as a LaunchAgent where `.env` isn't loaded. The parser tolerates the section being absent, so existing PROXY installs don't need this block until they want Outlook connected.

```toml
[email.outlook]
tenant_id    = "<paste tenant_id GUID>"
client_id    = "<paste application/client_id GUID>"
redirect_uri = "http://localhost:3000/api/integrations/outlook/callback"
```

### 9. Verify

Restart the web app (`npm run dev` in `apps/web/`) so the new env vars are picked up. Restart the daemon (`launchctl kickstart -k gui/$UID/com.proxy.daemon`).

Run `proxy outlook connect`. Mac default browser should open Microsoft's consent screen showing the 5 delegated scopes from step 4. Click **Accept**. You should land on `http://localhost:3000/settings/integrations?status=connected&email=jonathan.sells@relymd.com`.

Sanity-check the token round-trip with `proxy outlook test` — it should print the connected mailbox's folder list (Inbox, Sent Items, Drafts, Deleted Items, etc.).

## Rotation

There is no client secret to rotate (see step 6). The only long-lived credential PROXY holds is each user's **refresh token**, which Microsoft issues a fresh 90-day window for on every successful refresh.

Refresh-token rotation is automatic: PROXY refreshes the access token ~60 s before its 1 h TTL elapses, which also slides the refresh-token window forward. If a mailbox sits untouched for 90 days, the refresh token expires; on the next call the daemon receives `invalid_grant`, flips `outlook_accounts.active` to FALSE, and the Settings page surfaces a **Reconnect** button. Clicking it re-enters the consent flow and lands a fresh token pair on the same row.

## Revocation

If a machine is lost or a developer offboards:

1. Entra portal → **App registrations → PROXY — Outlook (…) → Branding & properties** → **Delete** the entire registration if it was created per-machine. Tenant-wide registrations stay; revoke the user's tokens instead (step 2).
2. The user's refresh token can be revoked via Graph: `POST /me/revokeSignInSessions` while authenticated as that user, or admin-side via **Users → <user> → Authentication methods → Revoke sessions**.

PROXY's local `proxy outlook disconnect` (Settings → Integrations) hits the Microsoft `/oauth2/v2.0/logout` endpoint for the local refresh token and sets `outlook_accounts.active = FALSE`, but does **not** delete the Entra app registration. The app registration is per-tenant infrastructure and outlives any individual machine's credentials.

## Cross-references

- ADR 005 § D1 — substrate decision (MS Graph + body-gated flag).
- Work request `proxy-19-outlook-msgraph-auth.md` — slice that consumes this recipe.
- `proxy-07-encrypted-pat-management` — AES-256-GCM crypto pattern used to encrypt the refresh token at-rest.
- `proxy-13-email-ingestion-job` — analogous Gmail OAuth flow; PROXY follows the same web-app-callback + DB-stored encrypted token pattern.
- [`relymd-work-data-pragmatic-compliance`](../decisions/relymd-work-data-pragmatic-compliance.md) — compliance posture context for delegated mailbox access.
