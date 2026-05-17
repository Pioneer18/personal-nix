---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-13
blocked_by: [proxy-27-queue-epic-core]
---

# PROXY — Queue web UI (slice 28, queue-infrastructure-v1)

Web `/queue` route with list view, drag-reorder UX, Epic expand/collapse, pause/resume. Consumes the daemon-synced DB rows from slice 27. Emits `epic_completed` feed events when Epics drain.

## Goal

User navigates to `/queue` in the PROXY web dashboard and sees:

- Ordered list of Epics + standalones (top → bottom)
- Each Epic row shows: title, goal, derived status, slice count (`3 done / 5 open / 8 total`), expand chevron
- Expand Epic → reveals its ordered slice list with per-slice status
- Drag-and-drop reorder for: Epics in queue, slices within Epic, standalones
- "Pause" button per Epic toggles to "Resume"
- Standalone rows show single slice with status

After ship, user can drive priority from the web UI instead of editing QUEUE.yaml by hand.

## Files in scope

- `apps/web/src/app/queue/page.tsx` — main route
- `apps/web/src/app/queue/components/QueueList.tsx` — sortable list root
- `apps/web/src/app/queue/components/EpicRow.tsx` — Epic display + expand
- `apps/web/src/app/queue/components/SliceRow.tsx` — slice display
- `apps/web/src/app/queue/components/StandaloneRow.tsx`
- `apps/web/src/app/queue/components/PauseButton.tsx`
- `apps/web/src/app/queue/hooks/useQueueDragDrop.ts` — drag-and-drop state
- `apps/web/src/app/api/queue/route.ts` — GET full queue snapshot
- `apps/web/src/app/api/queue/mv/route.ts` — POST reorder action
- `apps/web/src/app/api/queue/pause/route.ts` — POST pause/resume
- `apps/web/src/lib/queue/yaml-writer.ts` — atomic write to QUEUE.yaml from API routes (delegates to daemon CLI subcommand if running, else direct file edit)
- Feed integration: `apps/web/src/lib/feed/epic-completion.ts` — emit feed item when Epic transitions to done (subscribes to daemon state-transition events)

## Files out of scope

- Daemon core, CLI, DB schema (slice 27)
- TUI updates (slice 29)
- Tachikoma auto-grab (slice 29)
- Existing inbox/feed components (proxy-12) — extended additively for `epic_completed` rendering

## Stop condition

- [ ] `/queue` route loads from `/api/queue` and renders the full queue
- [ ] Epic rows show: title, goal (1-line), status chip (`open` / `active` / `paused` / `done`), slice count, expand chevron
- [ ] Expanding Epic reveals slice rows in intra-Epic order; each slice shows: slug, title, status chip, blocked-by indicator if applicable
- [ ] Standalone rows render between Epic blocks per queue order
- [ ] Drag-handle on every reorderable item; drop fires `/api/queue/mv` with new position
- [ ] Drag-reorder works for: Epics in queue, slices within Epic, standalones; drop target is visually clear
- [ ] Reorder is optimistic (UI updates immediately) with rollback on API failure
- [ ] Pause button on Epic row toggles between "Pause" / "Resume" label; API call updates QUEUE.yaml
- [ ] Paused Epics visually distinguished (dim + "paused" badge)
- [ ] Done Epics: collapsible, shown below open/active by default (toggle to see history)
- [ ] `epic_completed` feed item emitted when Epic transitions to done (single feed item, not one per slice). Click → links to Epic detail in queue
- [ ] Empty queue state renders "Add an Epic" CTA (links to docs / CLI command)
- [ ] Mobile-responsive (vertical stack on narrow viewports; drag-reorder works on touch)
- [ ] `npx tsc --noEmit` passes
- [ ] Component tests for QueueList, EpicRow expand/collapse, drag-drop hook
- [ ] E2E test: load `/queue` → drag Epic A above Epic B → verify QUEUE.yaml reflects new order

## Feedback loops

- `npx tsc --noEmit`
- `npm test` (component + drag-drop tests)
- Manual: open `/queue`, perform reorders, verify QUEUE.yaml + DB state match

## Quality bar

production

## v3 context

- See ADR 006 § D6 for surface scope decisions
- Builds on `proxy-12-extended-web-dashboard` (Next.js app shell already exists, M6)
- Extends `proxy-12-activity-feed-inbox` (renders `epic_completed` feed event type alongside existing feed items)
- API routes delegate to slice 27's CLI subcommands when daemon is running, else direct atomic file edit on QUEUE.yaml (covers daemon-down case)
