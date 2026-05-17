---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-16
depends_on: []
quality_bar: production
---

# PROXY v2 — sqlx migration: new tables + state enum (MV1.01)

Add the v2 schema as a forward-only sqlx migration. Creates `dossiers`, `infils`, `comms_events`, `standby_requests`, `proxy_presets` tables and the 7-value `infil_state` enum. v1 tables stay in place — they're transformed and dropped in proxy-v2-02.

## Goal

Fresh `sqlx migrate run` against an empty DB creates all v2 tables alongside v1 tables. Rust structs derive `sqlx::FromRow` for each new entity. `cargo build` passes.

## Files in scope

- `daemon/migrations/<timestamp>_v2_5ech_schema.sql` (new)
- `daemon/src/db/types.rs` (add Dossier, Infil, CommsEvent, StandbyRequest, ProxyPreset)
- `daemon/src/db/mod.rs` (export new types)

## Files out of scope

- v1 table drops (handled in proxy-v2-02)
- Application code using these tables (MV2+)
- TS types for web/TUI (separate concern; generate or hand-write later)

## Stop condition

- [ ] New tables exist: `dossiers`, `infils`, `comms_events`, `standby_requests`, `proxy_presets`
- [ ] Enum `infil_state` with 7 values (BRIEFED, LIVE, STANDBY, EXFIL_RDY, EXFIL_D, BURNED, RECALLED)
- [ ] Enum `dossier_state` with 3 values (BRIEFED, BURNED, ARCHIVED)
- [ ] FKs: infils.dossier_id → dossiers.id; comms_events.infil_id → infils.id; standby_requests.infil_id → infils.id
- [ ] Indexes: infils(state), infils(dossier_id), comms_events(infil_id, created_at desc), **infils(lease_expires_at) WHERE state='LIVE'** (reaper sweep)
- [ ] **Partial unique index: `UNIQUE(dossier_id) WHERE state='LIVE'` on infils** (single-active-infil rule)
- [ ] Dossiers columns: id, title, body, target_repo, files_in_scope jsonb, files_out_of_scope jsonb, recommended_callsign nullable, recommended_clearance nullable, recommended_comms nullable, acceptance_criteria, feedback_loops jsonb, linked_issues jsonb, briefed_at, completed_at nullable, briefed_by, **state dossier_state not null default 'BRIEFED'**, **failure_count int not null default 0**
- [ ] Infils columns: id, dossier_id, callsign, clearance, comms, state, pending_event jsonb nullable, started_at, ended_at nullable, last_heartbeat_at, **lease_expires_at timestamptz nullable**, **cancellation_reason text nullable** (e.g. `'lease-expired'`, `'handler-recalled'`), **burn_reason text nullable** (e.g. `'lease-expired-after-threshold'`, `'handler-aborted-exfil'`, `'irreversible-denied'`)
- [ ] Proxy_presets columns: callsign PK, prompt_addendum, pause_on jsonb, emit_cadence, default_clearance_ceiling, default_comms, face_set_path, tts_voice
- [ ] Rust structs derive Serialize/Deserialize/sqlx::FromRow
- [ ] `cargo build` passes in `daemon/`

## Feedback loops

- `cd daemon && cargo build`
- `cd daemon && sqlx migrate run` against fresh test DB
- `psql -c "\dt"` to verify tables exist

## Quality bar

production
