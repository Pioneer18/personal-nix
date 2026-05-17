---
title: "Complete queue-infrastructure-v1 Epic gaps (proxy-27/28/29 partial ship)"
tags: [seed, proxy, queue, epic, tachikoma-quality, followup]
type: cleanup
last_updated: 2026-05-14
discovered_during: "Reviewing merged PRs #48/49/50 after Tachikoma loops hit cap=5"
priority: medium-high
related_pr_review: "PR #48 +640/-13 (9 files), PR #49 +5 files lib only, PR #50 +14 TUI files"
---

# Complete queue-infrastructure-v1 Epic gaps

The three slices in `queue-infrastructure-v1` Epic (proxy-27/28/29) all shipped + merged to develop 2026-05-14, **but each shipped substantially less than its stop conditions specified**. Tachikoma loops hit their `--afk 5` cap with partial work; the auto-merge gate didn't reject (no CI, no required reviews); PRs got squash-merged into `develop`.

The merged code is foundational + correct as far as it goes — **not broken, just incomplete**. The user still drives queue mutations via direct `QUEUE.yaml` edits; the ergonomic surfaces aren't there yet.

## Per-slice gap

### PR #48 → proxy-27-queue-epic-core (commit `75cd76d`)

**Shipped**:
- `daemon/migrations/20260514000000_epics_and_queue.sql` — DB schema (epics, queue_items, work_requests.epic_id)
- `daemon/src/queue/mod.rs` — module skeleton
- `daemon/src/lib.rs` — module registration
- 9 files, +640/-13

**Missing vs spec** (`~/projects/personal-nix/wiki/work-requests/proxy-27-queue-epic-core.md`):
- `daemon/src/queue/yaml_watcher.rs` — kqueue/notify watcher on QUEUE.yaml
- `daemon/src/queue/sync.rs` — filesystem→DB sync logic
- `daemon/src/queue/grab.rs` — grab algorithm (Epic order + intra-Epic + blocked_by)
- `daemon/src/queue/rules.rs` — routing/precedence helpers
- `daemon/src/cli/queue.rs` — `proxy queue {add-epic, add-slice, mv, pause, resume, grab, next}` subcommands (only `list` exists, and it was pre-existing)
- `daemon/src/work_requests/blocked_by_parser.rs` — frontmatter parsing
- REST endpoints: `/api/queue`, `/api/queue/mv`, `/api/queue/pause`, etc.
- Daily auto-archive sweep job (this was in proxy-20 scope but referenced here)
- Tests for grab algorithm, sync idempotence, status derivation

### PR #49 → proxy-28-queue-web-ui (commit `ed34663`)

**Shipped**:
- `apps/web/src/lib/queue/yaml-parser.ts` + tests
- `apps/web/src/lib/queue/yaml-writer.ts` + tests
- `apps/web/src/lib/queue/types.ts`
- 5 files, pure library

**Missing vs spec**:
- `apps/web/src/app/queue/page.tsx` — `/queue` route
- `apps/web/src/app/queue/[id]/page.tsx` — single Epic detail
- Components: `QueueList`, `EpicRow`, `SliceRow`, `StandaloneRow`, `PauseButton`
- `useQueueDragDrop` hook + drag-reorder UX
- API routes: `/api/queue` (GET), `/api/queue/mv` (POST), `/api/queue/pause` (POST)
- Daemon delegation for write ops
- `epic_completed` feed integration

### PR #50 → proxy-29-queue-tui-and-tachikoma (commit `dc3f20e`)

**Shipped**:
- `apps/tui/src/views/QueuePane.tsx`, `EpicDetail.tsx`, `SliceDetail.tsx`, `SliceRow.tsx`
- `apps/tui/src/state/queue-store.ts`
- `apps/tui/src/keybindings/queue.ts`
- `apps/tui/src/lib/queue-api.ts` + tests
- `apps/tui/src/components/StatusBar.tsx`, lib/face.ts updates
- 14 files — substantial

**Missing vs spec**:
- Tachikoma skill update at `~/projects/personal-nix/skills/tachikoma/` for **no-arg auto-grab** form (`tachikoma queue` calls `proxy queue grab`)
- Tachikoma queue-grab integration tests
- README/USER-GUIDE updates documenting the new no-arg form

This was respected by Tachikoma deliberately (per CLAUDE.md hard rule #5: "Do not modify files in `~/projects/personal-nix/skills/` until the migration is complete"). Now that the rule has been updated to mark the migration as in-progress on proxy-27/28/29, the rule may need a second update: skills/ unblocked specifically for the no-arg auto-grab wiring. Worth a CLAUDE.md edit + a focused follow-up slice.

## Recommended follow-up slices

| Slug | Scope | Priority |
|---|---|---|
| `proxy-27b-queue-watcher-sync-cli` | YAML watcher + filesystem→DB sync + missing CLI subcommands (add-epic, add-slice, mv, pause, resume, grab, next) + REST endpoints | high — gates daily workflow ergonomics |
| `proxy-28b-queue-web-ui-pages-and-routes` | `/queue` route + components + drag-reorder UX + API routes | medium — direct YAML edit works as fallback |
| `proxy-29b-tachikoma-queue-no-arg-wiring` | Tachikoma skill update + integration tests; CLAUDE.md unblock for this directory | medium-high — needed for true autonomous queue draining |

These should form a new Epic — call it `queue-infrastructure-v1-completion` — and slot above email-vertical in QUEUE.yaml since email vertical is what consumed the queue infrastructure first.

## Tachikoma quality root cause

`--afk 5` was insufficient. Each slice's stop conditions list ~15-20 acceptance items; 5 iterations leaves 60-80% of the work unfinished. Tachikoma's quality bar in v1.0 is "lands in develop without breaking the build" — it doesn't validate against the full work-request acceptance criteria.

**Tachikoma improvements worth seeding separately**:
- Higher default cap for substantial slices (--afk 10 or 15)
- Stop-condition validation gate before opening PR (Tachikoma reads its own work-request + checks acceptance items)
- "Partial-ship" tagging — when a slice ships < N% of acceptance items, label the PR `partial` so a follow-up is obvious

Worth a separate seed (`tachikoma-cap-and-acceptance-validation.md`) when there's bandwidth.

## What works today (post-merge)

- DB schema in place: `epics`, `queue_items`, `work_requests.epic_id` columns
- Queue YAML libs in web app — parsing + writing is correct (per tests)
- TUI components built — visual rendering works in TUI when wired
- `proxy queue list` still exists from earlier, lists `work_requests` rows (not Epic-aware)
- **QUEUE.yaml direct edit** remains the canonical mutation path

## What still doesn't work

- `proxy queue add-epic/add-slice/mv/pause/resume/grab/next` — CLI subcommands not present
- Web `/queue` page — 404
- Web `/api/queue` — 404
- `tachikoma queue` (no-arg) — falls back to old behavior; no auto-grab
- Daemon doesn't watch QUEUE.yaml — no automatic sync to DB

## Mitigation until follow-up slices ship

User continues editing `~/projects/personal-nix/wiki/QUEUE.yaml` directly. To dispatch a slice from the queue, the user picks the top of the active Epic by eye and runs `tachikoma queue <slug>` interactively (or the REST workaround documented in [`fix-tachikoma-dispatch-bugs`](fix-tachikoma-dispatch-bugs.md)).
