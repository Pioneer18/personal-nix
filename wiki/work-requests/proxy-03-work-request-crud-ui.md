---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
shipped_pr: https://github.com/MioMarker/tachikoma-starter/pull/7
shipped_at: 2026-05-11
---

# PROXY — Work Request CRUD API + Web UI Shell

API routes for work request CRUD and a web dashboard showing the queue with PROXY's BMO ASCII face reacting to queue state. This is the first thing you see when you open PROXY.

## Goal

User can create, view, list, and update work requests in the browser. PROXY's face is visible on the dashboard and changes expression based on queue state (smile = empty, neutral = queued, frustrated = needs-triage).

## Files in scope

- `apps/web/src/app/**`
- `apps/web/src/components/**`
- `apps/web/public/**`
- BMO ASCII art source files at `~/projects/personal-nix/assets/bmo-faces/set/` (copy the -small.txt variants into the repo as static assets)

## Files out of scope

- Loop execution code (Slice 4)
- Scheduler (Slice 11)
- Integrations (Slices 6-10)

## Stop condition

- [ ] `GET /api/work-requests` returns paginated list with id, slug, title, status, target_repo, created_at
- [ ] `POST /api/work-requests` creates a work request, returns the new record
- [ ] `GET /api/work-requests/[id]` returns full work request detail
- [ ] `PATCH /api/work-requests/[id]` updates editable fields
- [ ] `DELETE /api/work-requests/[id]` soft-deletes
- [ ] Dashboard `/` page: PROXY face + work request list with status badges
- [ ] PROXY face expression driven by queue state: smile (0 open), neutral (>0 open), frustrated (any needs-triage)
- [ ] All 7 BMO face ASCII art files (`smile-small.txt`, `neutral-small.txt`, `frustrated-small.txt`, `angry-small.txt`, `content-small.txt`, `disbelief-small.txt`, `out-of-wack-small.txt`) copied into the repo and rendered in a `<pre>` / monospace div
- [ ] Work request create form at `/work-requests/new`
- [ ] `npx tsc --noEmit` passes

## Feedback loops

- `npx tsc --noEmit`
- `curl localhost:3000/api/work-requests` (expect JSON array)
- Open browser at `localhost:3000`, verify face renders and work request list works

## Quality bar

production
