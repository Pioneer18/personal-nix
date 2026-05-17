---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-13
blocked_by: [proxy-27-queue-epic-core]
---

# PROXY — Queue TUI + Tachikoma auto-grab (slice 29, queue-infrastructure-v1)

TUI queue pane shows top-5 queue items with drill-into-Epic on cursor select. Tachikoma `queue` command gains no-slug form that auto-grabs the next ready slice via `proxy queue grab`. After this ships, the bootstrap manual-grab workflow is replaced by `tachikoma queue` (no args).

## Goal

Two surfaces wired:

1. **TUI queue pane**: collapsed Epic + standalone view, expandable on cursor, refreshes on daemon state-transition events. Shows the top 5 queue items by default; PageDown/Up for more.

2. **Tachikoma auto-grab**: `tachikoma queue` with no slug → invokes `proxy queue grab` to get the next ready slice → proceeds with existing Tachikoma preflight + execution flow. Existing `tachikoma queue <slug>` form preserved for manual override.

## Files in scope

- `apps/tui/src/views/QueuePane.tsx` — main queue pane
- `apps/tui/src/views/EpicDetail.tsx` — drill-into-Epic view
- `apps/tui/src/views/SliceRow.tsx`
- `apps/tui/src/state/queue-store.ts` — subscribes to daemon SSE for state changes
- `apps/tui/src/keybindings/queue.ts` — pane-local keys (Enter to expand, p to pause, etc.)
- Tachikoma skill update at `~/projects/personal-nix/skills/tachikoma/SKILL.md` and impl: support no-slug auto-grab
- `~/projects/personal-nix/skills/tachikoma/lib/queue-grab.sh` (or equivalent) — wraps `proxy queue grab` invocation
- Documentation update: `~/projects/personal-nix/skills/tachikoma/README.md` reflects new no-arg form

## Files out of scope

- Daemon core, CLI, DB schema (slice 27)
- Web UI (slice 28)
- Reformulating Tachikoma's overall design (out of scope; this is a tactical integration point)

## Stop condition

- [ ] TUI queue pane renders top 5 items by default
- [ ] Each row shows: kind icon (Epic / Standalone), title, status chip, slice count for Epics
- [ ] Cursor up/down moves selection; PageDown reveals more items
- [ ] Enter on Epic row → expands to show intra-Epic slice list
- [ ] Enter on slice row → opens slice detail view (read-only render of work-request body)
- [ ] `p` on selected Epic toggles pause/resume (calls `proxy queue pause/resume`)
- [ ] State refreshes on daemon SSE event for `queue_changed` / `epic_status_transition` (real-time updates)
- [ ] Empty queue state: face changes to `out-of-wack` per `proxy-12-activity-feed-inbox` convention if standalones-only queue accumulates; smile face on empty
- [ ] `tachikoma queue` (no args) → invokes `proxy queue grab`; if returns slice slug, proceeds with existing Tachikoma flow as if user typed `tachikoma queue <slug>`
- [ ] `tachikoma queue` (no args) when queue empty → prints "Nothing to grab. Add an Epic with `proxy queue add-epic` or create work-requests."
- [ ] `tachikoma queue <slug>` (existing form) still works for manual override
- [ ] Tachikoma queue-grab respects status: only grabs `open` slices; doesn't re-grab `grabbed` ones
- [ ] After Tachikoma completes a slice (transitions to `done`), daemon's queue sync fires; next `tachikoma queue` invocation picks up the next ready slice
- [ ] `npx tsc --noEmit` passes (TUI)
- [ ] Tachikoma skill tests cover both forms (no-arg + with-slug)
- [ ] E2E test: queue has Epic A with 3 open slices → run `tachikoma queue` three times → each invocation grabs the next slice in Epic A's order

## Feedback loops

- `npx tsc --noEmit`
- `npm test`
- Manual: live test of `tachikoma queue` (no args) against the seeded QUEUE.yaml's email-vertical Epic

## Quality bar

production

## v3 context

- See ADR 006 § D6 (surface scope) and § D7 (CLI) for design context
- Builds on `proxy-16-tui-v2` (Ink TUI scaffold, M4 shipped)
- Closes the loop: after this slice ships, the full Epic + Queue workflow is end-to-end (CLI add → web UI reorder → TUI view → Tachikoma auto-grab)
- Bootstrap path before this ships: user invokes `tachikoma queue <slug>` manually for slices 27 + 28; once 29 ships, switch to `tachikoma queue` no-arg form
