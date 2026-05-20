---
status: open
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-20
quality_bar: production
---

# PROXY — spawn engine doesn't inject `PROXY_PROVIDER` / API-key env into loop container

After `proxy-loop-image-version-pins-stale` shipped and the `proxy-loop:v2` image rebuilt, `proxy infil phantom --dossier <slug>` successfully creates the `infils` row in `LIVE` state and spawns the Docker container — but the container exits immediately (exit code 2) with:

```
entrypoint: PROXY_PROVIDER unset
```

The loop image's entrypoint requires `PROXY_PROVIDER` (claude or codex) plus the corresponding API-key env, but the spawn engine at `daemon/src/spawn/mod.rs` doesn't inject them. `proxy-v2-25` (PR #148) was supposed to land env+auth injection but either landed in a different code path or never wired into the v2 spawn flow.

Net effect: infil row briefly shows LIVE in DB, container crashes in <1s, no heartbeat ever fires, dashboard computes the infil as DARK (computed-from-heartbeat-staleness per ARCHITECTURE.md). Phantom card never shows real LIVE=1.

Observed 2026-05-20 with infil `2d553f3f-fe02-4c40-85b9-e1299698b91f` (container `763a563e19ef…`).

## Goal

`proxy infil phantom --dossier <slug>` spawns a loop container that stays running, writes heartbeats, and shows up on the Dashboard's Phantom card as LIVE=1 (not DARK). Container picks `PROXY_PROVIDER=claude` by default (per the dossier's recommended_provider or the repo's default_provider, then `proxy.toml` [provider].default), and the matching API key gets mounted/injected.

## Files in scope

- `daemon/src/spawn/mod.rs` — the spawn engine that builds the docker run command. Add env injection for `PROXY_PROVIDER`, `ANTHROPIC_API_KEY` (or oauth token), `CODEX_API_KEY`, plus any required volume mounts (e.g. `~/.claude/`).
- `daemon/src/cli/infil.rs` — pass through the provider override from `--provider` flag if used
- `daemon/loop-image/Dockerfile` and/or `entrypoint.sh` — verify what env vars the entrypoint actually reads; document them
- Possibly `proxy.toml` schema if a new `[provider].default` key is required

## Files out of scope

- Adding new providers beyond claude/codex
- MCP tachikoma_dispatch cutover (still separate)
- Computer-use clearance gating (v3.0)

## Stop condition

- [ ] `proxy infil phantom --dossier <slug>` against a freshly briefed dossier results in a loop container that stays running past 1 minute
- [ ] `docker exec <container> env | grep PROXY_PROVIDER` shows `PROXY_PROVIDER=claude` (or whatever override is in effect)
- [ ] Heartbeat from the container reaches the daemon — `SELECT last_heartbeat_at FROM infils WHERE id = <id>` updates within 30s of spawn
- [ ] Dashboard Phantom card shows LIVE=1 (not DARK) after refresh
- [ ] `proxy infil --provider codex phantom --dossier <slug>` also works (CODEX_API_KEY injected instead)
- [ ] Test: `cd daemon && cargo test spawn_smoke -- --include-ignored` (or whatever the spawn integration test is named — see PR #172) passes with env-injection assertion added

## Feedback loops

- `cd daemon && cargo build --workspace`
- `cd daemon && cargo test --workspace`
- Manual e2e: `proxy infil phantom --dossier <slug>`, then `docker ps` shows the container alive, refresh http://localhost:3737/ and Phantom card shows LIVE=1

## Quality bar

production
