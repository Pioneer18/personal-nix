---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: [proxy-v2-01-schema-migration]
quality_bar: production
---

# PROXY v2 — proxy_presets seed for 4 callsigns (MV2.04)

Seed the `proxy_presets` table with one row per callsign (Tracer / Quill / Phantom / Echo). Each row encodes the 3 runner knobs (prompt addendum, pause_on event list, emit_cadence) plus defaults (clearance ceiling, comms, face_set path, TTS voice).

## Goal

`proxy_presets` populated with 4 rows. Runner can `SELECT * FROM proxy_presets WHERE callsign = $1` and get a complete behavioral profile.

## Preset values

| Callsign | Comms axis | Trust axis | pause_on | emit_cadence | default_clearance | tts_voice |
|---|---|---|---|---|---|---|
| Tracer | Loud | Runs | [impasse] | step | read | Daniel (or chosen) |
| Quill | Quiet | Asks | [impasse, clearance_boundary] | milestone | commit | Karen (or chosen) |
| Phantom | Quiet | Runs | [impasse] | milestone | push | Alex (or chosen) |
| Echo | Loud | Asks | [impasse, clearance_boundary, irreversible] | step | commit | Samantha (or chosen) |

Prompt addenda (full text in seed file): each ~3-8 sentences shaping comms style + decision posture per the 2×2 matrix.

## Files in scope

- `daemon/migrations/<timestamp>_v2_presets_seed.sql` (new — INSERT rows)
- `daemon/src/runner/presets.rs` (new — Rust constants for prompt addenda, easier to edit + version)
- The seed SQL reads addenda from a known file or has them inlined

## Files out of scope

- Runner code that consumes presets (proxy-v2-05)
- Face assets referenced by face_set_path (proxy-v2-11/12)
- TTS routing that consumes tts_voice (proxy-v2-15)

## Stop condition

- [ ] 4 rows in `proxy_presets` after migration
- [ ] Each row has all fields populated (no nulls in required cols)
- [ ] Prompt addenda are clear, ≤ 8 sentences, anchored on the 2×2 matrix point
- [ ] pause_on jsonb arrays match the table above exactly
- [ ] face_set_path values are valid relative paths (assets land in proxy-v2-11/12)
- [ ] tts_voice values are valid macOS voice names verifiable via `say -v ?`

## Feedback loops

- `sqlx migrate run`
- `psql -c "select callsign, pause_on, emit_cadence from proxy_presets;"`
- `say -v <voice> "test"` for each tts_voice value

## Quality bar

production
