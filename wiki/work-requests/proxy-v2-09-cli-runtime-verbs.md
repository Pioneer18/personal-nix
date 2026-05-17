---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: [proxy-v2-08-cli-dossier-verbs]
quality_bar: production
---

# PROXY v2 — CLI verbs: status / comms / grant / deny (MV3.09)

Runtime CLI verbs for observing and resolving live infils. `status` is the section grid view; `comms` tails a specific infil's output; `grant` and `deny` resolve STANDBY requests.

## Goal

Handler can see the section grid (`proxy status`), drill into a callsign or specific infil, tail comms in real-time, and respond to STANDBY requests with grant or deny.

## Verbs

### `proxy status [callsign]`

No-arg: render the 4-callsign grid. Each card: callsign, current face, counts (`n live · n on-deck · n burned`), oldest live infil age.

With callsign arg: drill into that callsign — list its infils (one row per infil) with face, dossier, state, elapsed, comms tail (last 3 lines).

Flags: `--json` for machine-readable; `--watch` for live-refreshing (polls daemon every 2s).

### `proxy comms <ref>`

Tails `comms_events` for the specified infil. Streams new events via SSE or polling. `<ref>` = callsign alone (if unambiguous) or `callsign@dossier`.

Flags: `--from-start` to replay from infil start; `--limit N` for non-streaming.

### `proxy grant <ref>`

Resolves the current open standby_request for the infil. Optionally grants new clearance.

Flags: `--clearance <lvl>` to elevate clearance on resume; `--reason "..."` for audit log.

### `proxy deny <ref>`

Denies the current open standby_request. Infil transitions to RECALLED. Same `<ref>` resolution as grant.

Flags: `--reason "..."`.

## Files in scope

- `daemon/src/cli/status.rs` (renders grid; reads from daemon API)
- `daemon/src/cli/comms.rs` (streams from daemon API)
- `daemon/src/cli/grant.rs`, `cli/deny.rs`
- `daemon/src/cli/grid_render.rs` (text-mode grid rendering)

## Files out of scope

- Terminal CLI verbs (proxy-v2-10)
- TUI ink rendering (proxy-v2-16)
- Web rendering (proxy-v2-17)

## Stop condition

- [ ] `proxy status` renders the grid with 4 cards including counts
- [ ] Card face matches worst-state face among that callsign's live infils
- [ ] `proxy status quill` shows per-infil detail
- [ ] `proxy status --watch` refreshes live
- [ ] `proxy comms quill@PLRM-1222` streams events as they arrive
- [ ] `proxy grant quill@PLRM-1222 --clearance commit` resolves standby, infil resumes
- [ ] `proxy deny quill@PLRM-1222` resolves standby, infil transitions to RECALLED
- [ ] `proxy --help` lists these verbs

## Feedback loops

- `cargo build`
- E2E: infil Quill with patch clearance on a commit-requiring dossier → observe STANDBY in status → grant via CLI → resume

## Quality bar

production
