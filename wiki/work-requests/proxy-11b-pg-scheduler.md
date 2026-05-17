---
status: grabbed
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# PROXY — Postgres-driven scheduler (slice 11b, replaces 11)

Replaces the original slice 11's "BullMQ + Redis" plan with an in-daemon, Postgres-backed scheduler. Cron-style scheduled jobs are rows in a `scheduled_jobs` table with `run_at` timestamps; the daemon does a `SELECT … WHERE run_at <= now() ORDER BY run_at LIMIT 1` per tick and fires due jobs. `LISTEN job_enqueued` provides instant wake-up for ad-hoc work. No Redis, no BullMQ JS dependency.

## Goal

Scheduled jobs can be created via the UI/CLI with cron expressions; the daemon fires them at the correct `run_at`. Job types include `coding_loop`, `data_ingestion`, `notification`, `jira_sync` (stubs OK for types not yet implemented). Jobs survive daemon restart (state is in PG). `last_run_at` and `next_run_at` columns track history. Run-at-startup any past-due missed jobs (with stale-warning telemetry).

## Files in scope

- `daemon/src/scheduler/mod.rs`
- `daemon/src/scheduler/cron_evaluator.rs` (parse cron strings, compute next_run_at)
- `daemon/src/jobs.rs` (job type registry, dispatch)
- Migration: `apps/web/drizzle/NNN_scheduled_jobs.sql` — `scheduled_jobs(id uuid, name text, job_type text, cron text, config jsonb, enabled bool, last_run_at timestamptz, next_run_at timestamptz, created_at timestamptz)`
- Migration removes the slice-11 `BullMQ`-related schema if any was created
- `apps/web/src/app/api/scheduled-jobs/**` — CRUD routes calling daemon (or directly to PG; daemon picks them up via LISTEN)
- `apps/web/src/app/settings/scheduled-jobs/**` — UI

## Files out of scope

- Concrete worker implementations for each job type (those are owned by their respective slices: 13 email, 15 notifications, 9 jira, 04c coding loops)
- Redis (explicitly NOT installed; remove from docker-compose if present)

## Stop condition

- [ ] BullMQ + Redis fully removed from docker-compose.yml, package.json, env.example
- [ ] `scheduled_jobs` table created via migration
- [ ] Daemon evaluates cron strings → `next_run_at`
- [ ] Daemon scheduler tick fires jobs whose `run_at` ≤ now(); writes `last_run_at`
- [ ] Job dispatch invokes the right worker (coding_loop → 04c backend, etc.)
- [ ] `proxy schedule list` CLI returns active jobs with next_run_at
- [ ] On startup: scheduler scans for past-due jobs and fires them serially (with a "late by Xs" log line)
- [ ] Settings → Scheduled Jobs UI: create/edit/delete
- [ ] Manual test: create a `coding_loop` job with cron `* * * * *`, verify it fires within 60s

## Feedback loops

- `cargo test` (cron evaluation, scheduler logic)
- Manual end-to-end test

## Quality bar

production

## v2 context

See `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` § 4 (decision 3 — state store), § 3 (architecture diagram). **Replaces slice 11.** Depends on 01b (daemon), 04c (for `coding_loop` dispatch).

## Related

- [`proxy-11-bullmq-scheduler.md`](proxy-11-bullmq-scheduler.md) — superseded predecessor (kept for history)
