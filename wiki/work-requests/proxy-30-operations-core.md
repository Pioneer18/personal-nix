---
status: grabbed
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-17
---

# PROXY — Operations + Objectives + Follow-ups core (slice 30)

DB schema + pgvector extension + filesystem watcher + CLI substrate for Operations, Objectives, Follow-ups. Foundation for slices 31 (triage), 32 (proactive engine), 33 (skills), 34 (TUI), 35 (web), 36 (notebook migration). Layers on top of ADR 006's queue infrastructure (proxy-27/28/29).

## Goal

Daemon watches `~/projects/personal-nix/wiki/OPERATIONS.yaml` and `~/projects/personal-nix/wiki/operations/*.md`, keeps DB in sync. Handler runs CLI commands (`proxy op/obj/fu`) to inspect + mutate. pgvector extension installed; `embedding` column populated on Operation create/update. State machines enforced. Feed items emitted on transitions.

After ship, slice 31 has a queryable substrate for dedup + triage; slices 32-35 consume the synced DB; slice 36 migrates `notebook.todo` entries onto Follow-up.

## Files in scope

- `daemon/src/operations/mod.rs` — public API for Op CRUD + state transitions
- `daemon/src/operations/yaml_watcher.rs` — watcher on `OPERATIONS.yaml` + `operations/` dir (uses `notify` crate, same pattern as queue/yaml_watcher.rs)
- `daemon/src/operations/sync.rs` — filesystem → DB sync (idempotent); emits state transitions when Op/Objective/Follow-up state changes
- `daemon/src/operations/frontmatter.rs` — parser for Op `.md` frontmatter (serde + yaml); Objectives + Follow-ups as structured arrays
- `daemon/src/operations/embedding.rs` — embedding computation on Op create/update; uses Anthropic embedding API (model TBD — initial: `text-embedding-3-small` 1536-dim; revisit at slice 31)
- `daemon/src/cli/op.rs` — `proxy op {list, view, new, grill, next, mv, priority, state, snooze}` subcommands
- `daemon/src/cli/obj.rs` — `proxy obj {add, link, state}` subcommands
- `daemon/src/cli/fu.rs` — `proxy fu {add, remind, state}` subcommands
- All CLI subcommands edit `.md` files / `OPERATIONS.yaml` atomically (temp + rename); daemon watcher picks up changes within 2s
- DB migrations:
  - **Enable pgvector extension** in a separate migration (`CREATE EXTENSION IF NOT EXISTS vector;`)
  - `operations` table: `id UUID PK, slug TEXT UNIQUE, title TEXT, theater TEXT NOT NULL DEFAULT 'relymd', priority TEXT CHECK (priority IN ('P0','P1','P2','P3') OR priority IS NULL), status TEXT NOT NULL DEFAULT 'live' CHECK (status IN ('live','on-ice','done','burned')), description_body TEXT, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ, last_touched_at TIMESTAMPTZ, embedding vector(1536)`
  - `objectives` table: `id UUID PK, op_id UUID REF operations(id) ON DELETE CASCADE, slug TEXT, text TEXT, status TEXT CHECK (status IN ('open','done','dropped')), link_kind TEXT NULL CHECK (link_kind IN ('epic','jira','briefing','draft')), link_ref TEXT NULL, recur TEXT NULL, next_fire_at TIMESTAMPTZ NULL, created_at, updated_at, embedding vector(1536) NULL`
  - `follow_ups` table: `id UUID PK, op_id UUID REF operations(id) ON DELETE CASCADE, slug TEXT, text TEXT, status TEXT CHECK (status IN ('open','resolved','dropped')), remind_at TIMESTAMPTZ NULL, recur TEXT NULL, next_fire_at TIMESTAMPTZ NULL, last_touched_at TIMESTAMPTZ, created_at, updated_at`
  - `operations_order` table: `theater TEXT, position INT, op_slug TEXT, PRIMARY KEY (theater, position)` — derived from OPERATIONS.yaml
  - Index on `operations.embedding` using `vector_cosine_ops` (HNSW or IVFFlat — TBD by slice 31)

## Files out of scope

- Dedup / triage logic (slice 31)
- Proactive engine cron (slice 32)
- Slash command skills (slice 33)
- TUI rendering (slice 34)
- Web surfaces (slice 35)
- `notebook.todo` migration (slice 36)
- Embedding model selection beyond the initial default (revisit slice 31)
- Voice routing — already automatic via existing chat tab routing (ADR 002)

## Stop condition

- [ ] DB migrations run clean; pgvector extension installed; `operations`, `objectives`, `follow_ups`, `operations_order` tables exist with all columns and constraints
- [ ] `OPERATIONS.yaml` parser handles: empty file, per-Theater grouped Ops, position ordering, missing operations/<slug>.md files (log warning, skip)
- [ ] `operations/<slug>.md` parser handles: full frontmatter (all fields), missing optional fields (use defaults), malformed YAML (log error, surface in feed)
- [ ] Filesystem watcher fires on both `OPERATIONS.yaml` change AND any `operations/<slug>.md` change (verified with manual edit during `proxy daemon` running)
- [ ] Sync logic idempotent: running sync twice from same FS state = no diff
- [ ] Sync emits feed_items: `operation_created`, `operation_state_changed`, `operation_priority_changed`, `objective_added`, `objective_state_changed`, `objective_linked`, `follow_up_added`, `follow_up_state_changed`
- [ ] Embedding computed on Op create/update; stored in `operations.embedding`; failure to compute logs warning + leaves NULL (does not crash sync)
- [ ] State machine transitions enforced at API level: `Operation.state` only `live ⇄ on-ice → done|burned`; `Objective.status` only `open → done|dropped`; `Follow-up.status` only `open → resolved|dropped`. Invalid transitions return error, don't crash
- [ ] `proxy op list` shows current Theater's open + live Ops, ordered by position, with bucket + status + last_touched_at
- [ ] `proxy op list --all` includes all Theaters, all states (including burned + done)
- [ ] `proxy op view <slug>` shows full Op including Objectives + Follow-ups with link refs
- [ ] `proxy op new` invokes capture flow (basic version — slice 33 enhances with grill UX)
- [ ] `proxy op mv <slug> <position>` updates OPERATIONS.yaml ordering atomically
- [ ] `proxy op priority <slug> <P0..P3>` updates `priority`; bumps position to bottom of new bucket's range
- [ ] `proxy op state <slug> <state>` runs state transition; enforces machine
- [ ] `proxy op snooze <slug> <duration>` bumps `last_touched_at` by duration (parse durations like `2d`, `1w`)
- [ ] `proxy obj add <op-slug> "text"` adds Objective with generated `obj-NN` id; appends to frontmatter; sync picks up
- [ ] `proxy obj link <obj-id> --epic <slug>` (or `--jira <key>` / `--briefing <id>` / `--draft <id>`) sets `link` field; validates target exists when possible
- [ ] `proxy obj state <obj-id> <state>` runs state transition
- [ ] `proxy fu add <op-slug> "text"` adds Follow-up
- [ ] `proxy fu remind <fu-id> <iso8601>` sets `remind_at`; daemon's notification scheduler picks it up (extends `proxy-11b-pg-scheduler`)
- [ ] `proxy fu state <fu-id> <state>` runs state transition
- [ ] OPERATIONS.yaml + operations/<slug>.md atomic edits: write temp, rename (same pattern as QUEUE.yaml)
- [ ] Concurrent CLI invocations don't corrupt files (parallel test)
- [ ] `OPERATIONS.yaml` seed is intentionally empty (`relymd: []`) — the prior `relymd-q2-platform-stability` and `relymd-standing-reminders` seed Ops were retired on 2026-05-17 once their objectives shipped. The CLI / watcher path must handle an empty theater without crashing.
- [ ] `cargo test` covers: frontmatter roundtrip, sync idempotence, state machine enforcement, embedding computation (mocked API), CLI command atomic edits
- [ ] `cargo clippy --all-targets -- -D warnings`

## Feedback loops

- `cargo test`
- `cargo clippy --all-targets -- -D warnings`
- Manual: edit OPERATIONS.yaml, run `proxy op list`, verify reflects changes within 2s
- Manual: edit operations/<slug>.md frontmatter (add Objective), run `proxy op view <slug>`, verify

## Quality bar

production

## v3 context

- See ADR 007 for full design — D1-D15 decisions captured there
- Depends on ADR 006's queue infrastructure (proxy-27 + 28 + 29) being shipped first
- pgvector extension adoption is new — install via sqlx migration; verify on OrbStack Postgres
- Initial embedding model: `text-embedding-3-small` (1536-dim); slice 31 may revisit based on cost/quality at dedup thresholds
- Existing `proxy-11b-pg-scheduler` extended for Follow-up `remind_at` notifications (handler-facing macOS + browser push via `proxy-15-extended` notify-app)
- Operation state machine emits feed_items via existing `feed_items` table pattern (ADR 005 / 006 precedent)
- Theater is free-text in V1 (default `relymd`); first-class entity deferred to V2 per ADR 007 D15
