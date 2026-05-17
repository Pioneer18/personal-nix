---
status: done
priority: 3
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-16
---

# Fix proxy-web container daemon reach

> Seeded from `wiki/seeds/web-container-daemon-host-reach.md`. Body below is the original seed; treat as
> rough — needs grilling + scope refinement before tachikoma dispatch.

The `proxy-web` Next.js container (running under `docker-compose` via OrbStack) has hardcoded references to `127.0.0.1:4321` — the proxy daemon's HTTP API port on the **host**. From inside the container, `127.0.0.1` resolves to the **container's own loopback**, not the host. The daemon runs on the host (LaunchAgent `com.proxy.daemon`), not inside a container — so any web route that proxies to the daemon fails with:

```
Error: connect ECONNREFUSED 127.0.0.1:4321
  at <unknown> ...
  errno: -111, code: 'ECONNREFUSED', address: '127.0.0.1', port: 4321
```

Surfaced 2026-05-14 in `docker logs proxy-web` while investigating an unrelated bundle crash.

## What's currently broken

Any web route that calls the daemon REST API. Confirmed seen:
- `GET /api/voice/state` → 404 (404 likely because the underlying handler fails to reach daemon + returns 404 instead of 500; or the route itself isn't implemented + the ECONNREFUSED is from another path)

Likely also broken (will surface as slices ship):
- Any sensor / admission / scheduler / dispatch endpoint surfaced through web
- `/api/queue` and queue mutation endpoints (once slice 28b ships)

## Root cause

Hardcoded host string. Likely in a config file or constant such as `apps/web/src/lib/daemon/url.ts` (or wherever daemon-client lives — verify during fix). The string `127.0.0.1` should be variable / env-driven:

| Environment | Correct value |
|---|---|
| Host (daemon-managed Next.js subprocess) | `127.0.0.1:4321` |
| Docker container on macOS via OrbStack | `host.docker.internal:4321` OR `host.orb.internal:4321` (both resolve identically on OrbStack) |
| Docker container on Linux host | host's bridge gateway IP (typically `172.17.0.1` or via `--add-host=host.docker.internal:host-gateway`) |

## Fix shape

Two options:

1. **Env var override** ⭐ — `DAEMON_URL` env var, default `http://127.0.0.1:4321`, container's `docker-compose.yml` sets `DAEMON_URL=http://host.docker.internal:4321`. Web app reads from env.
2. **`network_mode: host`** on web service — then `127.0.0.1` IS the host. But this disables docker port mapping + may interact poorly with OrbStack's network model + breaks reproducibility across substrates.

**Recommendation: (1) env var override.** Cleaner; doesn't change network topology; works cross-platform; future-proofs for a remote daemon.

## Fix scope

- Find all hardcoded `127.0.0.1:4321` references in `apps/web/` (probably 1-3 files)
- Add `DAEMON_URL` env var support: `process.env.DAEMON_URL ?? "http://127.0.0.1:4321"`
- Add `DAEMON_URL` to web service in `docker-compose.yml`:
  ```yaml
  web:
    environment:
      DAEMON_URL: http://host.docker.internal:4321
  ```
- Smoke test routes that hit daemon: voice/state, sensor, queue (once 27b/28b land)
- Document in `apps/web/README.md` or similar that the env var exists + when to override

## Related

- [`complete-queue-infrastructure-gaps`](complete-queue-infrastructure-gaps.md) — sibling post-merge cleanup; this fix will be needed before slice 28b's web routes work
- `proxy-28b-queue-web-ui-pages` — its API routes delegate to daemon and will fail until this is fixed
- `~/projects/personal-nix/wiki/decisions/orbstack-over-docker-desktop.md` — substrate choice; relevant since `host.docker.internal` semantics depend on it (OrbStack supports both `host.docker.internal` and `host.orb.internal`)

## Estimated scope

~30 minutes including:
- Finding every hardcoded `127.0.0.1:4321` reference
- Replacing with env-var-with-default pattern
- Adding env to docker-compose web service
- Restarting container + smoke testing voice/sensor endpoints

Promote to a numbered work-request when ready: `proxy-XX-web-daemon-url-env-var`. Could ship in parallel with 27b/28b — independent areas of code.
