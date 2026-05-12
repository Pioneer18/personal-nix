---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
v2_note: "Extended in v2 to surface `system_recommendations` alongside feed items. See proxy-12b-recommendations-engine for the table + recommendation kinds; this slice still owns the inbox UI surface."
---

> **v2 NOTE (2026-05-11)**: PROXY v2 adds a parallel `system_recommendations` table (see [`proxy-12b-recommendations-engine.md`](proxy-12b-recommendations-engine.md) and [`~/Projects/tachikoma-starter/docs/ARCHITECTURE.md`](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) § 8). The inbox UI built by this slice should render BOTH feed items AND recommendations (with visual differentiation — recommendations have an action button, feed items don't). If this work-request shipped without rendering recommendations, a follow-up amendment is needed.

# PROXY — Activity Feed + Inbox UI

Build the unified activity feed and inbox tab. All state machine transitions automatically emit feed items. Feed items have read/unread state. The inbox shows only unread items needing attention.

## Goal

The main dashboard has a Feed page with two tabs: All Activity (chronological log of everything PROXY has done) and Inbox (unread items). State machine transitions create feed items automatically. PROXY's face in the nav reacts to unread inbox count.

## Files in scope

- `apps/web/src/app/feed/**`
- `apps/web/src/app/api/feed/**`
- `apps/web/src/lib/state-machine/**` (emit feed items on transition)
- DB migration for `feed_items` table

## Files out of scope

- Email ingestion (Slice 13)
- Notification delivery (Slice 15)

## Stop condition

- [ ] `feed_items` table: id, type (string), title, body (nullable), read (bool, default false), action (JSONB nullable — e.g. `{ label: "View Run", href: "/runs/123" }`), source (string — e.g. `state_machine`, `scheduled_job`, `jira_sync`), work_request_id (nullable FK), created_at
- [ ] State machine `transition()` automatically inserts a feed item for every transition
- [ ] `GET /api/feed?tab=all` returns all items paginated (newest first)
- [ ] `GET /api/feed?tab=inbox` returns unread items only
- [ ] `POST /api/feed/[id]/read` marks a single item read
- [ ] `POST /api/feed/read-all` marks all inbox items read
- [ ] Feed page: two tabs (All Activity / Inbox), infinite scroll or "load more"
- [ ] Unread count badge on nav link
- [ ] PROXY face in header: smile (0 unread), neutral (1-5 unread), out-of-wack (>5 unread)
- [ ] `npx tsc --noEmit` passes

## Feedback loops

- `npx tsc --noEmit`
- Manual test: run a work request through a few state transitions, verify feed items appear in correct tabs with correct read/unread state

## Quality bar

production
