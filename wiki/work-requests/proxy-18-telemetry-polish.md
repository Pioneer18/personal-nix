---
status: blocked
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
blocked_reason: "Depends on proxy-17 (which archives the filesystem queue); must run after proxy-17 ships successfully. Flip status to `open` when ready."
v2_note: "Extend telemetry charts to include sensor data (host free pages, swap-rate, compressor size, load avg, Docker VM RSS over time, per-container RSS over time, thermal state). See sensor_samples table introduced in proxy-04b-sensor-and-admission."
---

> **v2 NOTE (2026-05-11)**: PROXY v2 adds a sensor (`proxy-04b-sensor-and-admission`) that writes time-series metrics to a `sensor_samples` table. This slice should render those as live charts on the dashboard: free pages over time, swap rate (paging in/out per sec), compressor size, load1/5/15, Docker VM total RSS, per-container RSS (top 5), thermal state (CPU_Speed_Limit). See [`~/Projects/tachikoma-starter/docs/ARCHITECTURE.md`](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) § 6 for the full sensor metrics palette.

# PROXY — Telemetry + Polish

Loop history charts, success rate metrics, state machine visualization on work request detail pages, and all 7 BMO face expressions used consistently across both web UI and Ink TUI. The `big-bmo.txt` full-body render on the welcome/empty state.

## Goal

The PROXY dashboard is polished end-to-end: meaningful telemetry charts, a visual state machine diagram on each work request, all face expressions wired to real system states, and the full BMO body on the empty state.

## Files in scope

- `apps/web/src/app/telemetry/**`
- `apps/web/src/components/state-machine-diagram/**`
- `apps/web/src/components/proxy-face/**` (audit all usage)
- `apps/tui/src/faces/**` (audit all usage)
- `apps/web/public/faces/big-bmo.txt` (copy from ~/Desktop/bmo faces/set/big-bmo.txt)

## Files out of scope

- Core loop execution logic
- DB schema changes

## Stop condition

- [ ] Telemetry page at `/telemetry`: total runs (all time), success rate (last 30 days), average loop duration (minutes), runs per day bar chart (last 30 days)
- [ ] State machine diagram on work request detail page: all states as nodes, transitions as edges, current state highlighted, transition history listed below
- [ ] All 7 face expressions (`angry`, `content`, `disbelief`, `frustrated`, `neutral`, `out-of-wack`, `smile`) used in at least one meaningful context in the web UI
- [ ] All 7 face expressions available and used in Ink TUI
- [ ] `big-bmo.txt` rendered on the empty state of the dashboard (no work requests yet) and the welcome screen on first launch
- [ ] Face expressions are documented in a `FACES.md` in the repo: which state triggers which face in both web and TUI
- [ ] `npx tsc --noEmit` passes in both `apps/web` and `apps/tui`

## Feedback loops

- `npx tsc --noEmit` (both apps)
- Manual review: open dashboard, telemetry page, a work request detail page — verify all faces, charts, and state machine diagram render correctly

## Quality bar

production
