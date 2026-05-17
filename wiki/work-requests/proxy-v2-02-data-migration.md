---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-16
depends_on: [proxy-v2-01-schema-migration]
quality_bar: production
---

# PROXY v2 — v1→v2 data migration script (MV1.02)

Transform v1 DB rows into v2 shape. After successful transform, drop v1 tables. Idempotent — safe to re-run.

## Goal

All live v1 DB data exists in v2 shape post-migration. v1 tables (`work_requests`, `runs`, `feed_items`, `pending_approvals`) dropped. Counts verified.

## State mapping

| v1 `work_requests.status` | v2 `dossiers.state` | v2 `dossiers.failure_count` | v2 active infil |
|---|---|---|---|
| `open` | `BRIEFED` | `0` | none |
| `grabbed` | `BRIEFED` | `0` | none — reaper backstops anything that slips through with a stale lease within 30s after migration |
| `done` | `ARCHIVED`, `completed_at` set | `0` | EXFIL_D row (one per dossier, historical) |
| `needs-triage` | `BURNED` | `2` | BURNED row (one per dossier, historical) |

Old `runs` rows merge into the corresponding `infils` (one run per work_request in v1, one infil per dossier in v2 for the migrated data).

`feed_items` → `comms_events` with infil_id resolved by run lineage.

`pending_approvals` → `standby_requests` linked to corresponding infils.

**Pre-migration cleanup (one-time, before this slice runs):** any v1 `work_requests.status='grabbed'` rows with no live process are stale and should be resolved manually before migration. Handler decides each row's true outcome (shipped → `done`, never-ran → `open`, irrecoverable → `needs-triage`). This keeps the mapping table above heuristic-free. As of 2026-05-15 two such rows were resolved by direct SQL (`proxy-work-request-dispatch-button` → `done` after PR #56 shipped; `proxy-29b-tachikoma-queue-no-arg-wiring` → `open` as no work was actually done).

## Files in scope

- `daemon/migrations/<timestamp>_v2_data_transform.sql` (new — SQL-only if possible)
- `daemon/src/migrations/v2_data_transform.rs` (optional helper if SQL alone insufficient)

## Files out of scope

- File-based wiki/work-requests import (proxy-v2-03)
- Application code (MV2+)

## Stop condition

- [ ] All v1 `work_requests` rows transformed into `dossiers` (+ `infils` per state map)
- [ ] All v1 `runs` rows reconciled (merged into matching infils)
- [ ] All v1 `feed_items` transformed into `comms_events`
- [ ] All v1 `pending_approvals` transformed into `standby_requests`
- [ ] v1 tables dropped after transform: work_requests, runs, feed_items, pending_approvals
- [ ] Idempotent: re-running on already-migrated DB is no-op or clean error
- [ ] Pre/post row count comparison logged

## Feedback loops

- `pg_dump` dev DB before running
- `sqlx migrate run`
- `psql -c "select count(*) from dossiers; select count(*) from infils; select count(*) from comms_events;"` — compare to pre-migration v1 counts

## Quality bar

production
