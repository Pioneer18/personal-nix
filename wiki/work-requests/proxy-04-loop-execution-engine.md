---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
shipped_pr: https://github.com/MioMarker/tachikoma-starter/pull/8
shipped_at: 2026-05-11
superseded_by: proxy-04c-run-backend-trait-and-local-docker
v2_note: "Spawn mechanism (host-side `claude -p`) reversed in v2 redesign. v2 spawns ephemeral Docker containers per loop. API surface (POST /api/runs, SSE log stream, DELETE for SIGTERM) is preserved; the runner implementation behind it changes. See docs/ARCHITECTURE.md § 5."
---

> **⚠️ v2 NOTE (2026-05-11)**: This slice shipped under PROXY v1 assumptions (host-spawned `claude -p`). The v2 redesign reverses the spawn mechanism — loops now run as ephemeral Docker containers with per-container memory caps. See [`~/Projects/tachikoma-starter/docs/ARCHITECTURE.md`](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) § 5 for the v2 architecture and [`proxy-04c-run-backend-trait-and-local-docker.md`](proxy-04c-run-backend-trait-and-local-docker.md) for the replacement slice. The shipped API contracts (POST /api/runs, SSE log stream, DELETE for stop) are preserved; only the underlying runner implementation is replaced.

# PROXY — Loop Execution Engine

Spawn `claude -p` as a child process in a git worktree, inject `PROXY_API_URL` + `PROXY_RUN_TOKEN`, capture stdout for live log streaming, and receive state transition callbacks from the loop. This is the core of what makes PROXY a real execution engine.

## Goal

A work request can be started from the UI. The server spawns `claude -p` in a sibling git worktree of the target repo, streams stdout logs to the browser via Server-Sent Events, and updates the work request state as the loop calls back with transitions.

## Files in scope

- `apps/web/src/lib/runner/**`
- `apps/web/src/app/api/runs/**`
- `apps/web/src/app/runs/**` (live log view page)
- `apps/web/src/lib/agent-brief.tmpl` (AGENT-BRIEF template with PROXY vars injected)

## Files out of scope

- Jira/GitHub integrations (Slices 8-10)
- Scheduler (Slice 11)

## Stop condition

- [ ] `POST /api/runs` creates a Run record and spawns `claude -p` in a new git worktree sibling to the target repo (e.g. `~/Projects/platform-proxy-<slug>`)
- [ ] Loop subprocess receives `PROXY_API_URL` and `PROXY_RUN_TOKEN` as env vars
- [ ] `POST /api/runs/[id]/events` accepts `{ state, actor, metadata }` callbacks from the loop — updates work request state machine
- [ ] `GET /api/runs/[id]/logs` streams captured stdout as Server-Sent Events (text/event-stream)
- [ ] `/runs/[id]` page in browser shows live scrolling log output
- [ ] Run status badge updates in UI when loop completes, errors, or is stopped
- [ ] `DELETE /api/runs/[id]` sends SIGTERM to the subprocess and cleans up the worktree
- [ ] Worktree is removed on run completion/stop
- [ ] `npx tsc --noEmit` passes

## Feedback loops

- `npx tsc --noEmit`
- Manual test: create a work request targeting a local repo, click Run, observe live log stream in browser, verify state machine transitions

## Quality bar

production
