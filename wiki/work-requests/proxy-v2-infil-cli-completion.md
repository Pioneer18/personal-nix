---
status: grabbed
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-20
depends_on: [proxy-v2-01-schema-migration, proxy-v2-04-presets-seed]
quality_bar: production
---

# PROXY v2 — finish `proxy infil` CLI + expose HTTP ingress

`daemon/src/cli/infil.rs::run_infil` currently bails with `"proxy infil is registered but not implemented yet"`. The clap surface (proxy-v2-28) and the underlying spawn engine pieces (proxy-v2-08 / PR #157) have shipped, but the CLI entry point is still a stub — and no `POST /api/dossiers` / `POST /api/infils` endpoints exist in `daemon/src/api/mod.rs`. The result: `dossiers` and `infils` tables stay empty even when callsigns are deployed, and the v2 section grid shows zero activity no matter what's actually running. This slice closes that gap and unblocks MCP `tachikoma_dispatch` from cutting over to v2 (see Out-of-scope).

## Goal

`proxy infil phantom --dossier <slug>` resolves the dossier, creates an `infils` row (state `LIVE`, callsign + clearance + comms applied from `proxy_presets`), spawns the loop-container via the existing v2 spawn engine, and the row appears in the web dashboard's section grid under the correct callsign card.

## Why now

Bug surfaced 2026-05-20: dispatching 3 Phantoms via MCP `tachikoma_dispatch` left the section grid empty (`dossiers=0`, `infils=0`) even after the v2-08 / v2-32 cutover. Root cause: CLI is stubbed, no HTTP create-ingress, so nothing writes the rows. Telemetry vs. substrate are decoupled today; this re-couples them.

## Files in scope

- `daemon/src/cli/infil.rs` — replace the `bail!` with the full implementation
- `daemon/src/api/mod.rs` — merge a new `infils::create` router (alongside the existing `infils::standby` merge that's also missing)
- `daemon/src/api/infils/mod.rs` — re-export the new `create` router
- `daemon/src/api/infils/create.rs` (new) — `POST /api/infils` handler that mirrors the CLI path
- `daemon/src/api/dossiers/mod.rs` (new) + `daemon/src/api/dossiers/lookup.rs` (new) — `GET /api/dossiers?slug=<slug>` lookup endpoint the CLI + MCP both need
- `daemon/src/spawn/*.rs` — wire whatever the proxy-v2-08 spawn engine exposed (likely a `pub async fn spawn_infil(pool, dossier_id, callsign, clearance, comms) -> Result<Uuid>`)

## Files out of scope

- MCP `tachikoma_dispatch` cutover — lives in `~/projects/personal-nix/mcps/tachikoma-mcp/index.ts`, separate slice once this lands
- Computer-use clearance level (v3 surface, ADR 003)
- Provider abstraction beyond what proxy-v2-22 / v2-23 already shipped (claude default is fine)
- TUI / voice surfaces (covered by their own MV6 / MV5 slices)

## Stop condition

- [ ] `proxy infil phantom --dossier <slug>` against a `BRIEFED` dossier returns `0` and prints the new infil id
- [ ] The new `infils` row has `state='LIVE'`, `callsign='phantom'`, `clearance` + `comms` from the `proxy_presets` row, `started_at` ≈ now
- [ ] The web dashboard at `http://localhost:3737/` shows the Phantom card with `LIVE=1` (auto-refresh ≤ 30s)
- [ ] `--clearance` flag is rejected if above the callsign's ceiling (Hard rule 13) — `read` / `patch` / `commit` for phantom; `push` accepted
- [ ] `POST /api/infils` with body `{ "dossier_slug": "...", "callsign": "phantom" }` does the same thing and returns the row
- [ ] `GET /api/dossiers?slug=<slug>` returns the dossier (404 if missing)
- [ ] The standby router (`daemon/src/api/infils/standby.rs`) is also merged into `daemon/src/api/mod.rs` (currently orphaned)
- [ ] `cargo build --workspace` clean, `cargo clippy --workspace --all-targets -- -D warnings` clean
- [ ] At least one integration test that exercises the full path: brief dossier → infil row → spawn engine called → row observable via GET

## Feedback loops

- `cd daemon && cargo build --workspace`
- `cd daemon && cargo clippy --workspace --all-targets -- -D warnings`
- `cd daemon && cargo test --workspace`
- Manual: `proxy brief <slug>` (already shipped via PR #158) → `proxy infil phantom --dossier <slug>` → refresh `http://localhost:3737/` and confirm Phantom LIVE=1
- DB check: `docker exec proxy-postgres psql -U proxy -d proxy -c "SELECT id, callsign, state FROM infils;"`

## Quality bar

production
