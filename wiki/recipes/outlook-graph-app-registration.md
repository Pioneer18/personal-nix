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
- **Client secret value** — string starting with random chars; **shown exactly once** at creation. Treat it like a PAT.
- **Redirect URI** — fixed: `http://localhost:3000/api/integrations/outlook/callback`.

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

- **Application (client) ID** → `OUTLOOK_CLIENT_ID`
- **Directory (tenant) ID** → `OUTLOOK_TENANT_ID`

### 3. Configure the redirect URI's response mode

Side nav → **Authentication**.

Under **Web → Redirect URIs**, confirm `http://localhost:3000/api/integrations/outlook/callback` is present. Microsoft only allows `http://localhost` (no port restriction) and `https://...` for web platform URIs — `http://127.0.0.1:3000/...` would be rejected; use `localhost`.

Under **Implicit grant and hybrid flows**, leave both boxes **unchecked** (PROXY uses the authorization code flow, not implicit).

Under **Advanced settings → Allow public client flows**, leave **No**. We're a confidential web client; the callback runs server-side in Next.js and the `client_secret` never leaves the daemon/web tier.

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

### 6. Create a client secret

Side nav → **Certificates & secrets** → **Client secrets** tab → **+ New client secret**.

- **Description:** `proxy-daemon (dev machine — <your-username>)`
- **Expires:** **180 days** for active dev machines (forces rotation, surfaces stale secrets fast). 24-month max if you really need to.

Click **Add**. The new row appears with two columns of interest:

- **Value** — the secret string. **Copy this NOW** — Microsoft hides it forever after you leave the page. This becomes `OUTLOOK_CLIENT_SECRET`.
- **Secret ID** — a separate GUID. Not used by PROXY; ignore.

If you lose the value, delete the row and create a new secret. There's no "show again" path.

### 7. (Optional) Pin a single user for testing

For dev machines you can scope the app to a single user during testing to avoid accidentally affecting other RelyMD mailboxes. Side nav → **Enterprise applications → PROXY — Outlook … → Properties → Assignment required = Yes**, then **Users and groups → + Add user** and pick yourself.

Skip this for production-style usage where any user in the tenant should be able to connect.

### 8. Wire the values into PROXY config

Three values land in two places.

**`~/.config/proxy/proxy.toml`** (machine-wide config; per ADR 004):

```toml
[email.outlook]
tenant_id   = "<paste tenant_id GUID>"
client_id   = "<paste application/client_id GUID>"
redirect_uri = "http://localhost:3000/api/integrations/outlook/callback"
```

**`.env`** in the tachikoma-starter checkout (gitignored; mirrored from `.env.example`):

```bash
OUTLOOK_TENANT_ID=<paste tenant_id GUID>
OUTLOOK_CLIENT_ID=<paste application/client_id GUID>
OUTLOOK_CLIENT_SECRET=<paste client_secret value>
OUTLOOK_OAUTH_REDIRECT_URI=http://localhost:3000/api/integrations/outlook/callback
```

The `tenant_id` + `client_id` + `redirect_uri` triple is non-secret and lives in `proxy.toml` so the Rust daemon can read it without the web app's env. The `client_secret` is secret and only the Next.js callback handler needs it, so it lives in `.env` (loaded into `process.env`).

### 9. Verify

Restart the web app (`npm run dev` in `apps/web/`) so the new env vars are picked up. Restart the daemon (`launchctl kickstart -k gui/$UID/com.proxy.daemon`).

Run `proxy outlook connect`. Mac default browser should open Microsoft's consent screen showing the 5 delegated scopes from step 4. Click **Accept**. You should land on `http://localhost:3000/settings/integrations?status=connected&email=jonathan.sells@relymd.com`.

Sanity-check the token round-trip with `proxy outlook test` — it should print the connected mailbox's folder list (Inbox, Sent Items, Drafts, Deleted Items, etc.).

## Rotation

Client secrets created in step 6 expire on the date you picked. Calendar two events:

- **T-14 days** — generate a new secret in **Certificates & secrets**, update `.env`, restart the web app, run `proxy outlook test` to confirm.
- **T-0 (expiry day)** — delete the old secret row in the Entra portal.

Refresh tokens have their own 90-day inactivity window. PROXY auto-refreshes the access token every ~50 minutes (10-minute safety buffer ahead of the 1h TTL), which also refreshes the refresh token's sliding window. If you don't touch the mailbox for 90 days straight, the refresh token expires; the daemon will detect this on the next call, mark the account inactive, and the Settings page will surface a "Reconnect" button.

## Revocation

If a machine is lost or a developer offboards:

1. Entra portal → **App registrations → PROXY — Outlook (…) → Certificates & secrets** → delete the relevant client-secret row.
2. The user's refresh token can also be revoked individually via Graph: `POST /me/revokeSignInSessions` while authenticated as that user, or admin-side via **Users → <user> → Authentication methods → Revoke sessions**.

PROXY's local `proxy outlook disconnect` (Settings → Integrations) hits the Microsoft `/oauth2/v2.0/logout` endpoint for the local refresh token and clears the Keychain entry, but does **not** delete the Entra app registration. The app registration is per-tenant infrastructure and outlives any individual machine's credentials.

## Cross-references

- ADR 005 § D1 — substrate decision (MS Graph + body-gated flag).
- Work request `proxy-19-outlook-msgraph-auth.md` — slice that consumes this recipe.
- `proxy-07-encrypted-pat-management` — AES-256-GCM crypto pattern used to encrypt the refresh token at-rest.
- `proxy-13-email-ingestion-job` — analogous Gmail OAuth flow; PROXY follows the same web-app-callback + DB-stored encrypted token pattern.
- [`relymd-work-data-pragmatic-compliance`](../decisions/relymd-work-data-pragmatic-compliance.md) — compliance posture context for delegated mailbox access.
