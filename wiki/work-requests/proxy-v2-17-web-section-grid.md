---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-16
depends_on: [proxy-v2-13-face-rendering, proxy-v2-05a-liveness-and-reaper]
quality_bar: production
---

# PROXY v2 — web section grid + supporting pages (MV6.17)

Rewrite the Next.js web UI for v2. Section grid as the home page; dossiers page; infil detail page; drops view; archive view. Replace v1's kanban + BMO faces.

## Goal

`apps/web` renders v2 dashboard at `/`. Supporting pages at `/dossiers`, `/infils/[id]`, `/drops`, `/archive`. All read from daemon API; live-update via SSE or polling.

## Pages

- `/` — section grid (4 callsign cards, big-art on splash if zero active)
- `/dossiers` — list of briefed dossiers, with detail drawer and "infil" CTA
- `/dossiers/[slug]` — dossier detail + infil history
- `/infils/[id]` — single infil detail: face, state, dossier, clearance, comms tail, drops, standby resolution buttons
- `/drops` — all current dead drops across live infils
- `/archive` — terminal-state browser with filters
- `/settings` — proxy.toml editor (already exists from v1)

## Behavior

- Real-time updates via SSE from daemon
- Card click → `/infils?callsign=quill` filtered list
- Standby card prominent with "Grant / Deny" buttons that hit the daemon API
- Exfil-ready infils show "Review & Approve" CTA → preview package modal

## Dossier badge composition (two-tier)

On `/dossiers/[slug]` (and any dossier-row display): use a **primary badge + optional secondary chip** layout. Primary reflects the *stored* `dossiers.state` verbatim and cannot lie; secondary reflects the worst-state of any associated *live* infils and is the glance-utility indicator. They describe different facts and cannot disagree.

| Primary badge text | Source | Color |
|---|---|---|
| `BRIEFED` | `dossiers.state = 'BRIEFED'` | green outline (matches v1 `open`) |
| `BURNED` | `dossiers.state = 'BURNED'` | red outline |
| `ARCHIVED` | `dossiers.state = 'ARCHIVED'` | grey outline (often hidden by default in list views) |

| Secondary chip text | Trigger | Color |
|---|---|---|
| `LIVE` | any infil with `state = 'LIVE'` AND fresh heartbeat | yellow chip |
| `DARK` | any infil with `state = 'LIVE'` AND `NOW() - heartbeat_at > lease_seconds` (computed at serialize time per proxy-v2-05a) | yellow chip with strike-through or dimmed yellow |
| `STANDBY` | any infil with `state = 'STANDBY'` | orange chip |
| `EXFIL_RDY` | any infil with `state = 'EXFIL_RDY'` | blue chip |
| (hidden) | no infils in any of the above states | — |

If multiple live infils exist (multi-instance per lock 3), the secondary chip shows the **worst-state aggregation** using priority: `STANDBY > EXFIL_RDY > LIVE > DARK`. The same aggregation logic is reused from the section-view callsign-card "worst-state face" (lock 4).

**Critical: the two badges are sourced from different tables** — primary reads `dossiers.state` directly (single column, atomic with dossier transitions); secondary derives from `infils WHERE dossier_id = X AND state IN ('LIVE', 'STANDBY', 'EXFIL_RDY')`. A bug in the derivation logic cannot poison the primary. This is the structural fix for the 2026-05-15 "RUNNING badge while no tachikoma alive" failure mode.

The dossier-row click-through navigates to `/dossiers/[slug]`. Below the header, render a per-infil list — each row shows `<callsign>@<dossier-slug>` — `<state>` — `<heartbeat-age>` — `<pid>` — `<worktree-path>` — for full debug visibility when needed.

## Files in scope

- `apps/web/src/app/page.tsx` (home — section grid)
- `apps/web/src/app/dossiers/**` (list + detail)
- `apps/web/src/app/infils/**` (list + detail)
- `apps/web/src/app/drops/**`
- `apps/web/src/app/archive/**`
- `apps/web/src/components/section-grid/` (new)
- `apps/web/src/components/callsign-card/` (new)
- `apps/web/src/components/comms-tail/` (new)
- `apps/web/src/components/package-preview/` (new)
- Remove: BMO-specific components, v1 kanban (or archive them)

## Files out of scope

- Face assets (proxy-v2-11, 12)
- TUI (proxy-v2-16)
- daemon API endpoints (already in MV2)

## Stop condition

- [ ] `/` renders 4-card section grid with live state
- [ ] `/dossiers` lists briefed dossiers; clicking opens detail; "infil" CTA opens flow
- [ ] `/infils/[id]` renders infil detail with face, state, comms tail
- [ ] Standby infils have grant/deny buttons that call the API
- [ ] `/drops` lists current dead drops with peek button (modal previews content)
- [ ] `/archive` browser with filters works
- [ ] BMO/kanban components archived from v1 layout
- [ ] `npx tsc --noEmit` passes
- [ ] Lighthouse / basic perf check (page loads < 2s on dev)

## Feedback loops

- `cd apps/web && npm run dev`
- Manual e2e: run all the flows; verify against TUI for parity

## Quality bar

production
