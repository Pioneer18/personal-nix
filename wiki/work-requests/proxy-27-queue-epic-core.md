---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-13
---

# PROXY — Queue + Epic core (slice 27, queue-infrastructure-v1)

DB schema for Epics + ordered queue. QUEUE.yaml file watcher + filesystem→DB sync. CLI subcommands for queue management. Grab logic that respects Epic order + intra-Epic slice order + `blocked_by` dependencies. Foundation for slices 28 (web UI) + 29 (TUI + Tachikoma auto-grab).

## Goal

Daemon watches `~/projects/personal-nix/wiki/QUEUE.yaml` and keeps the DB in sync with it. User runs CLI commands to inspect + modify the queue. `proxy queue grab` returns the next ready slice respecting Epic order, intra-Epic position, and `blocked_by` constraints.

After ship, the daemon's state machine + scheduler can answer "what's next?" deterministically. Slice 28 (web UI) and slice 29 (TUI + Tachikoma) consume this foundation.

## Files in scope

- `daemon/src/queue/mod.rs` — public API: `grab() -> Option<WorkRequestSlug>`, `next() -> Option<WorkRequestSlug>`, `list() -> QueueView`, `add_epic(...)`, `add_slice(...)`, `mv(...)`, `pause/resume(...)`
- `daemon/src/queue/yaml_watcher.rs` — kqueue (or `notify` crate) watcher on QUEUE.yaml; debounced reload on change
- `daemon/src/queue/sync.rs` — filesystem → DB sync logic; idempotent; emits state transitions when Epic status changes
- `daemon/src/queue/grab.rs` — grab algorithm: walk queue top-down, find next ready slice (Epic order → intra-Epic order → blocked_by satisfied → status = open)
- `daemon/src/cli/queue.rs` — `proxy queue {list, add-epic, add-slice, mv, pause, resume, grab, next}` subcommands; atomic file edits (temp + rename)
- DB migrations:
  - `epics` table: `id UUID PK, slug TEXT UNIQUE, title TEXT, goal TEXT, status TEXT, paused BOOL DEFAULT false, created_at, updated_at`
  - `queue_items` table: `id UUID PK, position INT, kind TEXT CHECK (kind IN ('epic', 'work_request')), epic_id UUID nullable REF epics(id), work_request_id UUID nullable REF work_requests(id), CHECK (...polymorphic constraint...)`
  - Alter `work_requests`: add `epic_id UUID nullable REF epics(id)`, `intra_epic_position INT nullable`, `blocked_by JSONB DEFAULT '[]'::JSONB`
- `daemon/src/work_requests/blocked_by_parser.rs` — read `blocked_by` from frontmatter when slice file is parsed; sync to DB

## Files out of scope

- Web UI (slice 28)
- TUI updates (slice 29)
- Tachikoma auto-grab integration (slice 29)
- Existing work_request schema (proxy-02-db-schema-state-machine) — extended additively

## Stop condition

- [ ] DB migrations run clean; `epics`, `queue_items` tables exist; `work_requests` has new columns
- [ ] QUEUE.yaml parser handles: epics with slices, standalones, paused flag, missing/unknown slugs (log warning, don't crash)
- [ ] Filesystem watcher fires on QUEUE.yaml change (verified with manual edit during `proxy daemon` running)
- [ ] Sync logic is idempotent: running sync twice from same QUEUE.yaml = no diff
- [ ] Sync emits state transitions when Epic status changes (e.g. all slices done → Epic `done` → `state_transitions` row written)
- [ ] `proxy queue list` returns formatted output (similar to `git log --oneline` style) showing Epics, slices within Epics, standalones, with status indicators
- [ ] `proxy queue list --all` includes paused + done items
- [ ] `proxy queue add-epic <slug> --title "..." --goal "..."` appends Epic to QUEUE.yaml
- [ ] `proxy queue add-slice <slug> --epic <epic-slug>` appends slice to Epic's slice list
- [ ] `proxy queue add-slice <slug>` (no --epic) appends as standalone
- [ ] `proxy queue mv <slug> <position>` updates QUEUE.yaml ordering; works for Epics, slices-within-Epic, and standalones
- [ ] `proxy queue pause <epic-slug>` sets `paused: true` on Epic in QUEUE.yaml; pause hides Epic from grab
- [ ] `proxy queue resume <epic-slug>` removes `paused: true`
- [ ] `proxy queue grab` algorithm:
  1. Walk queue top-down
  2. If item is Epic and not paused: find next slice in its ordered list where status=open AND all `blocked_by` slugs are status=done
  3. If item is standalone work-request and status=open AND blocked_by satisfied: return it
  4. Otherwise skip to next item
  5. Return None if nothing ready
- [ ] `proxy queue grab` returns the slug as plain text (machine-consumable for Tachikoma)
- [ ] `proxy queue next` runs the same algorithm but doesn't claim/transition the slice; pure peek
- [ ] `blocked_by` frontmatter parsing: read on slice file ingest, sync to DB, used by grab logic
- [ ] All CLI commands edit QUEUE.yaml atomically: write to temp file in same directory, rename over original
- [ ] Concurrent CLI invocations don't corrupt QUEUE.yaml (verify with parallel test)
- [ ] Existing work-requests not yet in QUEUE.yaml are NOT in the grab queue (they're "unqueued")
- [ ] `cargo test` covers: parse + roundtrip QUEUE.yaml, grab algorithm (Epic order, intra-Epic order, blocked_by, paused), sync idempotence, status derivation
- [ ] `cargo clippy --all-targets -- -D warnings`

## Feedback loops

- `cargo test`
- `cargo clippy --all-targets -- -D warnings`
- Manual: edit QUEUE.yaml, run `proxy queue list`, verify reflects changes within 2 seconds (watcher latency)

## Quality bar

production

## v3 context

- See ADR 006 for full design — Q1-Q8 decisions captured there
- This slice IS the "Slice 17 (filesystem queue migration)" referenced in CLAUDE.md hard rule #5; hard rule updated by this slice to reference proxy-27 + 28 + 29
- Initial QUEUE.yaml seed lands alongside this slice (with queue-infrastructure-v1 + email-vertical Epics, plus standalones); see `~/projects/personal-nix/wiki/QUEUE.yaml`
- Daemon watches QUEUE.yaml via `notify` crate (cross-platform; kqueue on macOS)
- Bootstrap: user manually drives this slice via `tachikoma queue proxy-27-queue-epic-core` (existing slug-arg invocation, since auto-grab needs slice 29 to ship)
