---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-12
---

# PROXY web dashboard (slice proxy-12-extended, M6)

Build the full Next.js dashboard at `apps/web`. Daemon manages it as an always-warm subprocess. Visual escape hatch from the Ink TUI — richer rendering for charts, kanban, notebook, inbox, settings.

## Goal

`proxy ui` opens browser to `localhost:3000`. Dashboard shows live sensor data, work-request kanban, notebook, recommendation inbox, and settings. All data via daemon API (`127.0.0.1:4321`) — no direct DB access from Next.js.

## Tech stack

- Next.js 14 App Router, TailwindCSS, shadcn/ui
- SWR for client-side data fetching + mutations
- Recharts for sensor time-series charts
- No auth (local-only, single-Mac)

## Pages / features

### `/` — Dashboard
- Sensor chart: memory pressure level, used_mb, swap_rate, load5, docker_vm_used_mb — last 1h windowed, auto-refreshes every 30s
- Quick stats: queue depth, runs in flight, pressure status badge

### `/work-requests` — Kanban
- Columns: open → grabbed → done / needs-triage
- Cards show slug, repo, failure_count
- Drag-drop between columns → PATCH /api/work-requests/:id status

### `/notebook` — Notebook
- List entries by category (idea / todo / custom)
- Markdown rendering
- "Promote to work-request" action on idea entries
- Overdue todo highlighting

### `/inbox` — Recommendations inbox
- Full markdown body rendering
- Approve / Dismiss / Snooze buttons → POST /api/recommendations/:id/action or dismiss
- Badge count in nav

### `/settings` — Settings
- Per-repo config editor (repo path, quality_bar, memory_limit_mb, max_concurrent)
- Voice mode default (dropdown)
- Cost cap (number input, for future computer use v2.0)
- App allowlist toggle list (forward-compat)

## Files in scope

- `apps/web/app/` — App Router pages for all 5 routes above
- `apps/web/components/` — domain components (SensorChart, WorkRequestKanban, NotebookEntry, InboxCard, SettingsForm)
- `apps/web/lib/api.ts` — typed fetcher wrappers for daemon API endpoints
- `apps/web/tailwind.config.ts`, `apps/web/package.json` — add Recharts, shadcn components as needed

## Files out of scope

- Drizzle ORM removal from `apps/web` (proxy-drizzle-05)
- `proxy ui` CLI command to open browser (wire in daemon CLI — small, can add here or leave for M7)
- First-run wizard (M7)

## Stop condition

- [ ] `npm run dev` (or `turbo run dev --filter=@proxy/web`) starts without error
- [ ] All 5 pages render without JS errors in browser console
- [ ] Sensor chart shows data (daemon must be running with postgres)
- [ ] Drag work-request card between columns → DB row status updates → TUI reflects within 2s
- [ ] Promote notebook idea → creates work-request row → appears in kanban
- [ ] Approve a recommendation → row actioned_at set → disappears from inbox
- [ ] Settings save persists to DB via daemon API

## Feedback loops

- `npm run dev` hot reload
- Browser devtools console (0 errors target)
- `./target/release/proxy-daemon queue list` — verify drag-drop writes through

## Quality bar

production

## Context refs

- `daemon/src/api/` — all available endpoints
- `daemon/migrations/` — schema reference
- `apps/tui/src/` — Ink TUI for parity reference (what web does best differently)
- `docs/ARCHITECTURE.md` § 22 M6 — spec
- `proxy.toml.example` [api] section for port config
