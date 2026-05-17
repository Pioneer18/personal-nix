---
title: "PROXY web host port = 3737 (off 3000)"
tags: [proxy, ports, docker, configuration, relymd]
last_updated: "2026-05-14"
status: accepted
---

# PROXY web host port = 3737

**Status**: Accepted — 2026-05-14.

**Scope**: Pioneer18's MacBook-Pro-2. PROXY's `proxy-web` Docker container host-side port mapping.

## Context

`proxy-web` defaulted to host port 3000 (`docker-compose.yml`: `${WEB_HOST_PORT:-3000}:3000`). RelyMD platform's `apps/api` dev server also binds host port 3000. With both wanting the same port, only one can run at a time — and the user works in `~/Projects/platform` daily, so `apps/api` wins ergonomically. Observed 2026-05-14: `mcp__relymd-devtools__restart_server { app: "api" }` failed with "Port 3000 still in use" because `proxy-web` was squatting it.

The `.env` already shifts `POSTGRES_HOST_PORT` (5432 → 5433) and `REDIS_HOST_PORT` (6379 → 6380) for the same reason — they collide with RelyMD's local Postgres/Redis. `proxy-web` is the last service still on its default.

## Decision

**`proxy-web` host port = 3737.** Set via `WEB_HOST_PORT=3737` in `~/Projects/tachikoma-starter/.env`. Container-internal port unchanged (still 3000); only the host mapping moves.

Rationale for **3737**:
- Outside RelyMD's typical 3000-3010 dev-server range (api, insight, patient-web, insight-2, patient-web-3, group-portal, apollo-hermes, foundry).
- Not in common-tool defaults (5173 Vite, 8080 generic, 5000 macOS AirPlay receiver, etc).
- Memorable and easy to type.
- Doesn't conflict with any service currently on this machine (verified via `lsof -i :3737`).

## Consequences

**Positive:**
- RelyMD `apps/api` can run on 3000 unobstructed; PROXY web reachable at `http://localhost:3737`.
- Pattern consistency with the other already-shifted ports in `.env`.

**Negative:**
- Anything hardcoding `localhost:3000` for PROXY needs updating. Known references:
  - `~/projects/personal-nix/skills/work-queue/SKILL.md` — **updated 2026-05-14**
  - `~/Projects/tachikoma-starter/README.md` — 4 references (low priority; docs)
  - `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` — 2 references (low priority; docs)
  - `apps/tui` (defaults to `http://localhost:3000`, overridable via `PROXY_API_URL`) — set `PROXY_API_URL=http://localhost:3737` in shell rc if Ink TUI ships before then
- Future README/docs PRs should target `localhost:3737`; the `.env.example` should also bump its example value from `# WEB_HOST_PORT=3000` to a comment noting 3737 is Pioneer18's pick.

## Verification

```bash
# After applying:
cd ~/Projects/tachikoma-starter && docker compose up -d proxy-web
curl -fsS http://localhost:3737/api/work-requests?limit=1 | jq .total
# Expected: a number (PROXY API responding on new port).
```

## See also

- [`decisions/container-explicit-opt-in.md`](./container-explicit-opt-in.md) — substrate carve-out for `proxy-web` restart
- [`~/Projects/tachikoma-starter/.env`](~/Projects/tachikoma-starter/.env) — the actual override
- [`~/Projects/tachikoma-starter/docker-compose.yml`](~/Projects/tachikoma-starter/docker-compose.yml) line 42 — the env-driven mapping
