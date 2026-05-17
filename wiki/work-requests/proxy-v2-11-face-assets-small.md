---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: [proxy-v2-09-cli-runtime-verbs]
quality_bar: production
---

# PROXY v2 — face assets: small kaomoji (MV4.11)

Create the small (kaomoji-style) face asset set: 4 callsigns × 5 expressions + 3 shared universal expressions. Used in the grid view and inline status surfaces (CLI, TUI, Web).

## Goal

Each callsign has 5 kaomoji-style face files capturing its expression for the lifecycle states it cares about. Plus 3 universal shared face files for callsign-agnostic terminal states.

## Per-callsign expressions (5 each)

- `resting` — idle, no live infil
- `working` — LIVE, default comms mode (e.g., Quill's quiet)
- `working_override` — LIVE, comms-overridden (e.g., Quill forced loud)
- `standby` — paused awaiting handler
- `exfil_ready` — work complete, awaiting handler approval

## Shared universal expressions (3)

- `burned` — failed in field
- `recalled` — handler aborted
- `dark` — heartbeat stale

## Suggested kaomoji starting points (refine in slice)

- Tracer: `>_<` (working), shifts on state
- Quill: `o_o` (resting), `^_^` (exfil_ready), `O_O` (working_override loud)
- Phantom: `-_-` (resting), `=_=` (working_override loud)
- Echo: `◕‿◕` (resting), `o_O` (standby), `>_<` (exfil_ready)
- Universal burned: `x_x`
- Universal recalled: `T_T`
- Universal dark: `?_?` or `._.`

## Files in scope

- `apps/tui/src/faces/<callsign>/<expression>.txt` (5 per callsign × 4 = 20 files)
- `apps/tui/src/faces/_universal/<expression>.txt` (3 files)
- `apps/web/public/faces/small/<callsign>/<expression>.txt` (same shape for web)
- `apps/web/public/faces/small/_universal/<expression>.txt`
- `FACES.md` — rewrite to v2 face system documentation

## Files out of scope

- Big-art assets (proxy-v2-12)
- Face rendering components (proxy-v2-13)
- Old BMO assets — those are retired; move to `_archive/bmo-faces-v1/`

## Stop condition

- [ ] 20 callsign-specific small face files exist (4 × 5)
- [ ] 3 universal small face files exist
- [ ] All files are single-line kaomoji (no multi-line ASCII art)
- [ ] FACES.md rewritten with v2 face inventory + when-to-use table
- [ ] BMO v1 assets archived to `_archive/bmo-faces-v1/` (not deleted, in case of revival)

## Feedback loops

- Visual review of each kaomoji (does it match the expression?)
- Confirm files render correctly in a terminal with various fonts (some kaomoji glyphs render oddly in monospace)

## Quality bar

production (art is a craft pass; iterate)
