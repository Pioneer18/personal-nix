---
status: grabbed
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# PROXY — RunBackend trait + LocalDockerBackend (slice 04c)

Replaces the host-spawn loop runner (originally slice 04) with an abstraction that allows multiple backends. v1 ships exactly one impl — `LocalDockerBackend`, which spawns one ephemeral Docker container per loop, with a `--memory` cap, bind-mounting a git worktree of the target repo.

This slice also builds the loop container image: `proxy-loop:latest`. The image contains node (for MCP servers), git, the `claude` CLI, basic utilities, and an entrypoint that runs `claude -p` against the bind-mounted worktree.

The existing slice-04 HTTP API contracts (`POST /api/runs`, `GET /api/runs/[id]/logs` SSE, `DELETE /api/runs/[id]` SIGTERM) are preserved; only the runner backing them changes.

## Goal

A loop spawned via `POST /api/runs` lands as a Docker container `proxy-loop-<run_id>` inside the Docker VM, with `--memory=<repo_config.memory_limit_mb>m` set. The container's stdout is captured (`docker logs -f`) and streamed via SSE to the web UI just as today. SIGTERM via `DELETE /api/runs/[id]` translates to `docker stop`. The container's worktree is cleaned up on container exit.

Internally, a `RunBackend` trait is defined; `LocalDockerBackend` implements it; future impls (`RemoteDockerBackend`) will be additive.

## Files in scope

- `daemon/src/backend/mod.rs` (the `RunBackend` trait)
- `daemon/src/backend/local_docker.rs` (the impl)
- `daemon/src/run.rs` (per-run orchestration: pre-admission, spawn, log streaming, finalize)
- `daemon/Dockerfile.loop` (the proxy-loop:latest image)
- `daemon/src/run_image_build.rs` (helper to build/pull the image at install time)
- `apps/web/src/lib/runner/**` — gutted; thin client that POSTs to the daemon's local API (daemon-on-Mac listens on Unix socket or 127.0.0.1:8001)
- `apps/web/src/app/api/runs/**` — proxy to daemon (the existing HTTP API contracts remain; their backing logic moves out of Next.js)

## Files out of scope

- Sensor (04b) — already implemented
- Scheduler (11b)
- Cleanup tools (one-off)

## Stop condition

- [ ] `RunBackend` trait defined with `spawn`, `observe` (stream), `terminate`, `current_resource_usage`, `current_budget` methods
- [ ] `LocalDockerBackend` impls all methods via Docker socket / Docker CLI
- [ ] `proxy-loop:latest` image builds from `Dockerfile.loop`; image size < 1.5 GB
- [ ] Container image entrypoint reads `PROXY_API_URL` + `PROXY_RUN_TOKEN` env vars, invokes `claude -p` with the worktree as cwd
- [ ] `POST /api/runs` admits (via 04b's admission rule), spawns container, returns run_id
- [ ] `GET /api/runs/[id]/logs` SSE streams container stdout in real time
- [ ] `DELETE /api/runs/[id]` issues `docker stop --time=10` (graceful SIGTERM + 10s grace + SIGKILL)
- [ ] Container exit cleans up: removes container, removes git worktree, updates run record
- [ ] Admission rejection on `POST /api/runs` returns 503 with reason; run sits in queue
- [ ] Test: spawn a loop targeting a small test repo, observe logs, verify container shows up in `docker ps`, kill it, verify cleanup

## Feedback loops

- `cargo test` (unit tests for trait + LocalDocker)
- Manual test: full loop-in-container against a test repo

## Quality bar

production

## v2 context

See `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` § 5 (component table) and § 7 (admission). Replaces slice 04's host-spawn approach (see [`proxy-04-loop-execution-engine.md`](proxy-04-loop-execution-engine.md) for the superseded shipped slice — its API surface is preserved; only the runner inside changes). Depends on 01b (daemon scaffold) and 04b (sensor + admission).
