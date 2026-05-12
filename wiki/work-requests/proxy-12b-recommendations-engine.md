---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# PROXY — System manager / recommendations engine (slice 12b)

The "PROXY actively manages the system" feature. The daemon emits `system_recommendations` rows when host state warrants user action (close Chrome, shut down idle sims, reboot, disable Apple Intelligence, etc.). Recommendations surface in the inbox (slice 12 — extended) and via macOS notifications (slice 15 — extended). User confirmation is required for every action; nothing happens silently.

## Goal

When admission rejects a job for memory reasons, a `close-app` recommendation appears in the inbox with a candidate app (the largest enabled app from `apps_registry`). When uptime > 14 days, a `reboot` recommendation appears. When Apple Intelligence is detected loaded + idle, an info-tier recommendation appears. Etc. for the full catalog (~12 kinds — see ARCHITECTURE.md § 8). User actions ("Close Chrome", "Snooze", "Dismiss") update the row's `actioned_at` and `actioned_outcome`. Macros UI for each action invokes the right osascript/pmset/etc. with user confirmation.

## Files in scope

- `daemon/src/manager/mod.rs` (recommendation generators)
- `daemon/src/manager/close_app.rs`, `daemon/src/manager/reboot.rs`, etc. (one file per recommendation kind)
- `daemon/src/manager/actions.rs` (action executors: osascript quit, pmset, etc.)
- Migration: `apps/web/drizzle/NNN_system_recommendations.sql` per ARCHITECTURE.md § 8 schema
- Migration: `apps/web/drizzle/NNN_apps_registry.sql` per ARCHITECTURE.md § 8 schema; seed with: Chrome, Notion, Slack, Discord, Teams, Spotify, VS Code (with `state_safety='open-docs-lost'` warning)
- `apps/web/src/app/api/recommendations/**` (list / action / dismiss endpoints)
- `apps/web/src/app/settings/apps-registry/**` (UI for editing the curated apps list)

## Files out of scope

- The actual rendering of recommendations in the inbox (lives in slice 12)
- macOS notification action-button delivery (lives in slice 15b — bundled signed app)

## Stop condition

- [ ] `system_recommendations` and `apps_registry` tables exist via migration
- [ ] Apps registry seeded with at least 7 entries (Chrome, Notion, Slack, Discord, Teams, Spotify, VS Code)
- [ ] At least these recommendation kinds generate: `close-app`, `reboot`, `disable-apple-intelligence`, `shutdown-idle-sims`, `docker-prune`, `thermal-throttling`, `low-power-mode`, `disk-free-low`
- [ ] Actions executable (with confirmation): `osascript-quit`, `pmset-set`, `shell-cmd` (only specific allowlisted commands)
- [ ] User must confirm every action; no silent execution
- [ ] Recommendation lifecycle: created → dismissed_until / actioned_at → expires_at (auto-cleanup)
- [ ] Settings → Apps Registry UI allows enable/disable per app
- [ ] Test: `stress` to force pressure, observe `close-app` recommendation appears with the largest enabled app named

## Feedback loops

- `cargo test` (recommendation generators)
- Manual test: force pressure, see recommendation, action it, verify Chrome quits

## Quality bar

production

## v2 context

See `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` § 8. This is the "PROXY as system steward" feature core. Depends on 01b (daemon), 04b (sensor — generators consume sensor state).
