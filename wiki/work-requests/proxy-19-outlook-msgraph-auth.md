---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-13
---

# PROXY — Outlook MS Graph OAuth + token storage (slice 19, email vertical)

Add MS Graph delegated OAuth for the email management vertical. Tenant admin (Jonathan) self-registers an Entra app for `jonathan.sells@relymd.com`. PROXY consumes OAuth code+PKCE flow, stores refresh tokens encrypted in macOS Keychain (reusing `proxy-07-encrypted-pat-management`), refreshes on expiry, and exposes a typed `OutlookGraphClient` to downstream slices (20, 21, 26).

## Goal

User runs `proxy outlook connect` (CLI) or clicks "Connect Outlook" in Settings → Integrations. Mac default browser opens Microsoft consent screen, requests `Mail.ReadWrite + Mail.Send + MailboxSettings.ReadWrite + User.Read + Calendars.Read` delegated scopes. After consent, PROXY stores the refresh token in Keychain and the daemon can call Graph to list folders, fetch messages, move/delete, send mail, etc.

## Files in scope

- `daemon/src/outlook/auth.rs` — OAuth code+PKCE flow, token refresh, expiry tracking
- `daemon/src/outlook/client.rs` — `OutlookGraphClient` struct with typed methods: `list_folders()`, `list_messages(folder_id, since)`, `get_message(id)`, `send_mail(draft)`, `move_message(id, target_folder)`, `mark_read(id)`, `delete_message(id)` (soft-delete to Trash)
- `daemon/src/outlook/scopes.rs` — scope constants
- `apps/web/src/app/settings/integrations/outlook/page.tsx` — Settings UI with connect/disconnect
- `apps/web/src/app/api/integrations/outlook/callback/route.ts` — OAuth callback handler
- DB migration: extend `proxy-07` PAT table OR add `oauth_credentials` table for OAuth tokens (decide during impl; lean: extend existing table with a `provider` enum)
- `~/.config/proxy/proxy.toml` schema additions:
  ```toml
  [email.outlook]
  tenant_id = "..."         # RelyMD tenant
  client_id = "..."         # Entra app ID
  redirect_uri = "http://localhost:3000/api/integrations/outlook/callback"
  ```
- Recipe doc: `~/projects/personal-nix/wiki/recipes/outlook-graph-app-registration.md` — one-time Entra app setup steps for the user

## Files out of scope

- Email polling + briefing engine (slice 20)
- Folder taxonomy setup (slice 21)
- Reviewer UX (slice 22)
- Gmail OAuth (already done — see `proxy-13-email-ingestion-job`)

## Stop condition

- [ ] Entra app registration recipe at `~/projects/personal-nix/wiki/recipes/outlook-graph-app-registration.md` documenting: register app, configure redirect URI, request scopes, admin-consent, get tenant_id + client_id
- [ ] OAuth code+PKCE flow in `daemon/src/outlook/auth.rs` — Mac default browser opens consent URL, callback hits `/api/integrations/outlook/callback`, refresh + access tokens stored
- [ ] Refresh tokens encrypted via `proxy-07` Keychain crypto (AES-256-GCM); never plaintext on disk
- [ ] Token refresh handled automatically before expiry (1h access TTL, 90d refresh TTL); silent refresh via Graph endpoint
- [ ] `OutlookGraphClient::new()` returns a usable client; tested against the real RelyMD tenant
- [ ] All 7 client methods implemented + integration-tested against real tenant (mocked unit tests fine for unhappy paths)
- [ ] Settings page shows connected account email + "Disconnect" button
- [ ] Disconnect revokes refresh token at Microsoft (`/oauth2/v2.0/logout` endpoint) + clears Keychain entry + sets DB record inactive
- [ ] Token-expiry edge case: stale refresh token (>90d) → re-prompt consent flow, don't crash daemon
- [ ] `Calendars.Read` scope included in the initial consent (slice 26 needs it, batch with this flow)
- [ ] `cargo test` passes (auth flow unit tests with mocked Graph)
- [ ] `cargo clippy --all-targets -- -D warnings`
- [ ] `npx tsc --noEmit` passes (Settings UI)

## Feedback loops

- `cargo test`
- `cargo clippy --all-targets -- -D warnings`
- Manual: `proxy outlook connect` → real consent flow → `proxy outlook test` runs `list_folders()` + prints output

## Quality bar

production

## v3 context

- See ADR 005 § D1 for the substrate decision (MS Graph + body-gated flag)
- See `proxy-07-encrypted-pat-management` for crypto pattern + Keychain integration
- See `proxy-13-email-ingestion-job` for the analogous Gmail OAuth flow
- Tenant admin status (Jonathan) means self-serve Entra app registration — no external IT gate. See [`relymd-work-data-pragmatic-compliance`](~/projects/personal-nix/wiki/decisions/relymd-work-data-pragmatic-compliance.md) for the compliance posture context
