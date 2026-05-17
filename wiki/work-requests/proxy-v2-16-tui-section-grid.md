---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: [proxy-v2-13-face-rendering]
quality_bar: production
---

# PROXY v2 — TUI section grid dashboard (MV6.16)

Rewrite the Ink TUI dashboard for v2. Replace the single-BMO-face + queue-list layout with the 4-callsign section grid + briefed dossier list + comms tail.

## Goal

`proxy-tui` (Ink) shows the v2 dashboard: top section = 4 callsign cards in a 2×2 or 1×4 layout, middle = briefed dossier list, bottom = recent comms tail. Updates live as daemon state changes.

## Layout sketch

```
┌──────────────────────────────────────────────────────────┐
│   >_<   Tracer       o_o   Quill                         │
│         0 live · 0 ready    2 live · 1 standby           │
│                                                          │
│   -_-   Phantom      ◕‿◕  Echo                          │
│         1 live · drops!     0 live · 0 ready             │
├──────────────────────────────────────────────────────────┤
│ Briefed (3)                                              │
│   • PLRM-1222 — edit feature                             │
│   • shell-cleanshot — cleanshot integration              │
│   • proxy-v2-05 — runner branching                       │
├──────────────────────────────────────────────────────────┤
│ Comms (live)                                             │
│   [quill@PLRM-1222 0:08] 3 call sites identified         │
│   [phantom@shell-08 4:20] going quiet for patch work     │
│   [echo@PLRM-1300 0:02] standby — needs commit clearance │
└──────────────────────────────────────────────────────────┘
```

Keys: arrow keys navigate cards; enter drills into a callsign; `b` opens brief flow; `s` opens status detail; `q` quits.

## Files in scope

- `apps/tui/src/dashboard.tsx` (rewrite)
- `apps/tui/src/components/SectionGrid.tsx` (new)
- `apps/tui/src/components/CallsignCard.tsx` (new)
- `apps/tui/src/components/DossierList.tsx` (new)
- `apps/tui/src/components/CommsTail.tsx` (new)
- `apps/tui/src/lib/face.ts` (rewrite to use shared/ face picker)
- Delete or archive: BMO-specific components

## Files out of scope

- Face assets (proxy-v2-11, 12)
- Web surface (proxy-v2-17)
- CLI text-mode grid (already in proxy-v2-09)

## Stop condition

- [ ] Dashboard renders 4 callsign cards with current state
- [ ] Each card shows face + callsign + counts
- [ ] Cards update live as state changes (polls daemon every 2s)
- [ ] Briefed dossier list visible and live-updating
- [ ] Comms tail shows last N events with timestamp + ref + message
- [ ] Keyboard nav: arrows, enter, `b`, `s`, `q`
- [ ] BMO components removed; v1 dashboard layout retired
- [ ] `npx tsc --noEmit` passes

## Feedback loops

- `cd apps/tui && npm run dev`
- Manual: run proxy with active infils in various states; observe TUI

## Quality bar

production
