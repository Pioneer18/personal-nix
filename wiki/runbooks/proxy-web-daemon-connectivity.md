---
title: "PROXY web UI shows 'fetch failed' / 500 on /api/work-requests"
tags: [proxy, web, daemon, docker, orbstack, host.docker.internal, connectivity]
last_updated: "2026-05-14"
---

## Symptom

- Web UI at `localhost:3000/work-requests` shows red "fetch failed" message.
- `curl localhost:3000/api/work-requests` returns `{"error":"internal error"}` HTTP 500.
- Direct daemon `curl 127.0.0.1:4321/api/work-requests` returns 200 with data.

## Diagnosis

`proxy-web` runs in an OrbStack/Docker container (per `docker-compose.yml`). Inside the container, `127.0.0.1:4321` is the container's loopback, NOT the host's. The daemon binds to `127.0.0.1:4321` on the *host*, so the container can't reach it via that address.

Confirm:

```bash
docker exec proxy-web sh -c 'echo "DAEMON_API_URL=$DAEMON_API_URL"'
# Empty → falls back to 127.0.0.1:4321 → container loopback → nothing listening
docker exec proxy-web sh -c 'getent hosts host.docker.internal'
# Should resolve to the Docker bridge gateway (OrbStack handles this natively)
```

## Fix

Add to `docker-compose.yml` under the `web` service `environment:` block:

```yaml
DAEMON_API_URL: ${DAEMON_API_URL:-http://host.docker.internal:4321}
NEXT_PUBLIC_DAEMON_API: ${NEXT_PUBLIC_DAEMON_API:-http://127.0.0.1:4321}
```

- `DAEMON_API_URL` is consumed server-side (Next.js in container → host daemon) — uses `host.docker.internal`.
- `NEXT_PUBLIC_DAEMON_API` is consumed browser-side (browser is on the host) — uses `127.0.0.1`.

Recreate the container so the env takes effect:

```bash
cd ~/Projects/tachikoma-starter && docker compose up -d web
```

Verify:

```bash
curl -sS -w "\nHTTP %{http_code}\n" http://localhost:3000/api/work-requests
# Expect HTTP 200 with items array
```

## Alternatives considered (and rejected)

- **Bind daemon to `0.0.0.0:4321`**: security regression — daemon API would be reachable from any LAN client.
- **Move daemon into a container**: large architectural change; daemon owns mic / system-pressure sensor / Docker control, not easily containerized.
- **Use `host.docker.internal` from browser too**: the browser runs on the host (not in the container), so `host.docker.internal` doesn't resolve there.

## Related

- `~/Projects/tachikoma-starter/docs/adr/004-cargo-workspace-and-tech-stack-lockin.md` — daemon binding + proxy.toml
- `~/Projects/tachikoma-starter/docker-compose.yml` — web service env block
- `~/projects/personal-nix/wiki/decisions/orbstack-over-docker-desktop.md` — OrbStack supports `host.docker.internal` natively
