---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
shipped_pr: https://github.com/MioMarker/tachikoma-starter/pull/6
shipped_at: 2026-05-11
---

# PROXY — Core DB Schema + State Machine

Define the PostgreSQL schema for work requests, state transitions, and active runs. Implement the state machine logic with all transitions enforced and logged with actor + timestamp.

## Goal

DB schema is live via migrations. The state machine enforces valid transitions (open → grabbed → done, with needs-triage as quarantine). Every transition is recorded in `state_transitions` with who/what triggered it and when.

## Files in scope

- `apps/web/src/lib/db/**`
- `apps/web/src/lib/state-machine/**`
- `apps/web/drizzle/**` (or equivalent migration directory)
- DB migration files

## Files out of scope

- UI files
- Docker config (already set up in Slice 1)
- API routes (Slice 3)

## Stop condition

- [ ] `work_requests` table: id, slug, title, description, status, target_repo, config JSONB, created_at, updated_at
- [ ] `state_transitions` table: id, work_request_id, from_state, to_state, actor, timestamp, metadata JSONB
- [ ] `runs` table: id, work_request_id, pid, worktree_path, started_at, ended_at, status, exit_code
- [ ] State machine module exports `transition(workRequestId, toState, actor)` — throws on invalid transition
- [ ] Valid transitions enforced: open→grabbed, grabbed→done, grabbed→needs-triage, grabbed→open (retry), needs-triage is terminal until manual reset
- [ ] Migrations run automatically on `docker compose up`
- [ ] TypeScript types generated/inferred from schema (no `any`)

## Feedback loops

- `docker compose up` (migrations run cleanly, check logs)
- `cd apps/web && npx tsc --noEmit`

## Quality bar

production
