---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: [proxy-v2-11-face-assets-small, proxy-v2-12-face-assets-big]
quality_bar: production
---

# PROXY v2 — face rendering components (MV4.13)

Implement face-selection logic that picks the right face file based on (callsign, infil state, comms override, terminal state). Wire into CLI grid renderer, TUI Ink Face component, and Web React Face component.

## Goal

Single face-selection function `pickFace(callsign, state, comms?, terminal?)` returns the path of the correct face file. Three renderers (CLI text, Ink, React) read from `proxy_presets.face_set_path` + the selection function and display correctly.

## Selection logic

```
pickFace(callsign, state, comms_override?, terminal?) -> face_path

if terminal in [BURNED, RECALLED, DARK]:
  return universal[terminal]  // shared face

# else per-callsign
if state == BRIEFED or no live infil:
  return callsign/resting

if state == LIVE:
  return comms_override == 'loud' && preset.default_comms == 'quiet'
    ? callsign/working_override
    : callsign/working

if state == STANDBY:
  return callsign/standby

if state == EXFIL_RDY:
  return callsign/exfil_ready

# fallback
return callsign/resting
```

For card aggregation (grid view, many infils of one callsign):
- Pick the "worst-state" face: BURNED > RECALLED > DARK > STANDBY > EXFIL_RDY > LIVE > BRIEFED
- Card shows that face + counts

## Files in scope

- `shared/src/faces.ts` (selection logic, exported types) — assumes a shared/ TS package exists
- `apps/tui/src/components/Face.tsx` (Ink component)
- `apps/web/src/components/proxy-face/Face.tsx` (Next.js server component)
- `daemon/src/cli/face_picker.rs` (Rust version for CLI text-mode)

## Files out of scope

- Face assets (proxy-v2-11, 12)
- TUI dashboard layout (proxy-v2-16)
- Web dashboard layout (proxy-v2-17)

## Stop condition

- [ ] `pickFace` function exists in TS shared/ (single source of truth)
- [ ] Rust port in daemon/cli for terminal renderer
- [ ] Ink Face component renders the correct face for any (callsign, state) combo
- [ ] React Face component does the same
- [ ] Card-aggregation logic picks worst-state correctly
- [ ] Unit tests cover all 4 callsigns × 7 states + universal states
- [ ] Visual smoke test: render all 28+ combinations and eyeball

## Feedback loops

- `cd apps/web && npx tsc --noEmit`
- `cd apps/tui && npx tsc --noEmit`
- `cd daemon && cargo build`
- Manual: `proxy status` shows correct faces for known states

## Quality bar

production
