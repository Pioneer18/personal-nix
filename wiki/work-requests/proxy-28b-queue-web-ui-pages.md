---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-14
blocked_by: [proxy-27b-queue-watcher-sync-cli]
---

# PROXY — Queue web UI pages + components (slice 28b, queue-infrastructure-v1-completion)

Complete the parts of `proxy-28-queue-web-ui` that landed only partially in PR #49 (commit `ed34663`). YAML parser + writer libs are in develop (`apps/web/src/lib/queue/`); this slice adds the `/queue` route, components, drag-reorder UX, API routes, and `epic_completed` feed integration.

## Goal

User navigates to `/queue` and sees the ordered queue with Epics + standalones. Can drag-reorder, expand/collapse Epics to see slices, pause/resume Epics. `epic_completed` feed item emits when an Epic transitions to done. Inbox tab (proxy-12) renders these feed items alongside other feed events.

## Files in scope

- `apps/web/src/app/queue/page.tsx` — main route
- `apps/web/src/app/queue/[id]/page.tsx` — single Epic detail (optional)
- `apps/web/src/app/queue/components/QueueList.tsx`
- `apps/web/src/app/queue/components/EpicRow.tsx`
- `apps/web/src/app/queue/components/SliceRow.tsx`
- `apps/web/src/app/queue/components/StandaloneRow.tsx`
- `apps/web/src/app/queue/components/PauseButton.tsx`
- `apps/web/src/app/queue/hooks/useQueueDragDrop.ts`
- `apps/web/src/app/api/queue/route.ts` — GET (proxies to daemon)
- `apps/web/src/app/api/queue/mv/route.ts` — POST (proxies to daemon)
- `apps/web/src/app/api/queue/pause/route.ts` — POST (proxies to daemon)
- Extend `apps/web/src/lib/feed/` — add `epic_completed` event type rendering
- Reuse `apps/web/src/lib/queue/yaml-parser.ts` + `yaml-writer.ts` (from PR #49)

## Files out of scope

- YAML parser/writer libs — shipped in PR #49
- Daemon-side queue logic, REST handlers, grab algorithm (slice 27b owns)
- TUI updates (slice 29b)

## Stop condition

- [ ] `/queue` route loads, calls Next.js `/api/queue` which proxies to daemon's `/api/queue` (slice 27b)
- [ ] Epic rows show: title, goal (1-line), derived status chip, slice count (`N done / M open / total`), expand chevron
- [ ] Expanding Epic reveals intra-Epic slice list with per-slice status chip + blocked-by indicator if applicable
- [ ] Standalone rows interleave with Epics per queue order
- [ ] Drag-handle on every reorderable item; drop fires `/api/queue/mv` with new position
- [ ] Drag-reorder works for: Epics in queue, slices within Epic, standalones
- [ ] Drop is optimistic (UI updates immediately) with rollback on API failure
- [ ] Pause button on Epic row toggles between "Pause" / "Resume" label; API call updates QUEUE.yaml via daemon
- [ ] Paused Epics visually distinguished (dim + "paused" badge)
- [ ] Done Epics: collapsible, hidden below open/active by default (toggle to see history)
- [ ] `epic_completed` feed item emitted when Epic transitions to done; rendered in inbox tab alongside existing feed item types with link back to Epic in `/queue`
- [ ] Empty queue state CTA ("Add an Epic")
- [ ] Mobile-responsive (touch drag works on narrow viewports)
- [ ] `npx tsc --noEmit` passes
- [ ] Component tests for QueueList, EpicRow expand/collapse, drag-drop hook
- [ ] E2E test: open `/queue` → drag Epic A above Epic B → verify QUEUE.yaml reflects new order via filesystem check

## Feedback loops

- `npx tsc --noEmit`
- `npm test` (component + drag-drop tests)
- Manual: open `/queue`, perform reorders, verify QUEUE.yaml + DB state match

## Quality bar

production

## v3 context

- See ADR 006 § D6 (surface scope) + the gap-analysis seed
- Builds on `proxy-12-extended-web-dashboard` (Next.js app shell, M6)
- Extends `proxy-12-activity-feed-inbox` (`epic_completed` event type)
- Reuses YAML libs shipped in PR #49 (`apps/web/src/lib/queue/`)
- Depends on slice 27b for daemon-side endpoints
- **Recommended Tachikoma cap: `--afk 12`** — ~12 acceptance items

