---
status: superseded
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
superseded_by: proxy-11b-pg-scheduler
v2_note: "BullMQ + Redis are dropped in v2 in favor of in-daemon Postgres-driven scheduler (LISTEN/NOTIFY for new work; run_at column for scheduled jobs). See docs/ARCHITECTURE.md § 4 (decision 3 — state store)."
---

> **⚠️ SUPERSEDED (2026-05-11)**: PROXY v2 drops BullMQ + Redis. The scheduler moves into the Rust daemon and uses Postgres `LISTEN/NOTIFY` + a `run_at` column on the `jobs` table for time-based firing. See [`proxy-11b-pg-scheduler.md`](proxy-11b-pg-scheduler.md) for the replacement slice and [`~/Projects/tachikoma-starter/docs/ARCHITECTURE.md`](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) § 4 for the rationale.

# PROXY — BullMQ Scheduler (superseded)

Set up BullMQ with Redis for durable job scheduling. Define job types: `coding_loop`, `data_ingestion`, `notification`, `jira_sync`. Build UI to create and manage scheduled jobs with cron expressions.

## Goal

User can schedule any job type with a cron expression in the Settings UI. Jobs are durable — they survive server restarts. Scheduled jobs fire reliably according to their cron schedule.

## Files in scope

- `apps/web/src/lib/workers/**`
- `apps/web/src/app/api/scheduled-jobs/**`
- `apps/web/src/app/settings/scheduled-jobs/**`
- DB migration for `scheduled_jobs` table

## Files out of scope

- Email ingestion worker implementation (Slice 13)
- Notification delivery implementation (Slice 15)

## Stop condition

- [ ] BullMQ connected to Redis from Docker Compose
- [ ] `scheduled_jobs` table: id, name, job_type (enum), cron (string), config (JSONB), enabled (bool), last_run_at (nullable), next_run_at (nullable), created_at
- [ ] Workers registered for: `coding_loop`, `data_ingestion`, `notification`, `jira_sync` (stubs OK for types not yet implemented)
- [ ] `GET /api/scheduled-jobs` lists all jobs
- [ ] `POST /api/scheduled-jobs` creates a new scheduled job
- [ ] `PATCH /api/scheduled-jobs/[id]` updates cron/config/enabled
- [ ] `DELETE /api/scheduled-jobs/[id]` removes job and cancels it in BullMQ
- [ ] Settings > Scheduled Jobs page: list jobs with next_run_at, toggle enabled, add new, delete
- [ ] Jobs survive server restart (BullMQ repeatable jobs in Redis)
- [ ] `npx tsc --noEmit` passes

## Feedback loops

- `npx tsc --noEmit`
- Manual test: create a job with cron `* * * * *` (every minute), wait 60 seconds, verify `last_run_at` updates

## Quality bar

production
