---
status: open
priority: 3
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-16
---

# PROXY — cron-style scheduler with catch-up semantics

> Grilled 2026-05-16. Decisions locked: in-PROXY scheduler (extend `scheduled_jobs`), headless `claude -p` invocation, 24h catch-up window, skip-on-overlap, independent from `/schedule` skill. Ready for tachikoma dispatch.

## Why now

`/reorient` (just shipped) is designed to run nightly at 4am for unattended memory refresh, but there's no scheduler in PROXY that handles cron-style cadences with catch-up semantics. macOS `launchd` doesn't catch up missed `StartCalendarInterval` fires by default. And PROXY's existing `scheduled_jobs` table is `run_at`-driven (one-shot timestamps), not cron-style recurrence. Need a small extension that lets `/reorient` (and future scheduled skills) declare `0 4 * * *` and have PROXY fire it reliably — including catch-up when the Mac was asleep.

## Goal

A daemon-resident cron scheduler that:

- Accepts cron expressions (5-field standard cron syntax: minute hour dom month dow)
- Persists schedules in Postgres (`cron_jobs` table or extension of existing `scheduled_jobs`)
- Fires headless `claude -p "<command>"` subprocesses at scheduled slots
- Catches up missed fires within a 24-hour window (Mac was asleep at slot → fire on wake if still <24h late; otherwise skip to next slot)
- Skips concurrent fires (if previous run still active, log a `cron_skipped_overlap` recommendation and don't fire)
- Surfaces via CLI (`proxy cron add/list/remove/run`) and the existing inbox/feed for failure recommendations
- First consumer: `/reorient --unattended` at `0 4 * * *`

## Files in scope

- `daemon/migrations/<YYYYMMDDHHMMSS>_cron_jobs.sql` — new table or `scheduled_jobs` extension:
  ```sql
  CREATE TABLE cron_jobs (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name          text NOT NULL UNIQUE,
    cron_expr     text NOT NULL,
    command       text NOT NULL,           -- e.g. "claude -p '/reorient --unattended'"
    mode          text NOT NULL DEFAULT 'foreground',  -- foreground | background
    enabled       boolean NOT NULL DEFAULT true,
    catch_up_window_hours integer NOT NULL DEFAULT 24,
    last_fired_at timestamptz,
    last_fired_outcome text,                -- success | failure | skipped_overlap | caught_up
    created_at    timestamptz NOT NULL DEFAULT now()
  );
  CREATE TABLE cron_job_runs (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    cron_job_id   uuid NOT NULL REFERENCES cron_jobs(id) ON DELETE CASCADE,
    scheduled_for timestamptz NOT NULL,
    fired_at      timestamptz NOT NULL DEFAULT now(),
    completed_at  timestamptz,
    outcome       text,                     -- success | failure | skipped_overlap | caught_up
    stdout_path   text,                     -- log file path
    stderr_path   text,
    exit_code     integer
  );
  ```
- `daemon/src/cron/mod.rs` (new) — cron expression parser (use the `cron` crate); scheduler tick logic; catch-up evaluation
- `daemon/src/cron/runner.rs` — spawns headless `claude -p` subprocess; captures stdout/stderr to log files under `~/.local/share/proxy/cron-runs/<job-name>/<timestamp>.{out,err}`; writes `cron_job_runs` row
- `daemon/src/main.rs` — wire cron scheduler into the daemon's tick loop (sibling of sensor sampling); evaluate every minute on the minute (aligned to clock boundary)
- `daemon/src/cli/cron.rs` (new) — new subcommand group:
  - `proxy cron add <name> --cron "<expr>" --command "<cmd>"` — register
  - `proxy cron list` — show all jobs with next-fire timestamps
  - `proxy cron remove <name>` — delete
  - `proxy cron run <name>` — manual fire (testing / catch-up trigger)
  - `proxy cron history <name> [--limit N]` — show recent runs
- `daemon/src/main.rs` — register the cron CLI handler
- `~/.claude/skills/reorient/SKILL.md` — already documents `--unattended` mode; verify it's truly idempotent + log-only-on-failure (per skill design)

## Files out of scope

- TUI surface (`proxy-tui` cron page) — defer; CLI is sufficient for v1
- Web UI surface (`apps/web` cron management) — defer
- Per-job concurrency limits beyond skip-on-overlap (e.g. "max 3 parallel fires of this job") — overkill for v1
- Email/SMS notifications on failure — out of scope; PROXY's recommendation engine + existing notification pipeline handles surface
- Distributed scheduling across multiple Macs — single-machine only
- Cron expression aliases (`@daily`, `@hourly`) — v1 uses 5-field standard syntax only; aliases are sugar
- Backfill of historical missed fires beyond the 24h catch-up window — by design, just skip to next slot

## Stop condition

- [ ] DB migration creates `cron_jobs` + `cron_job_runs` tables; both nullable in existing rows
- [ ] Cron expression parser (use the `cron` crate from crates.io) — parse + compute next-fire timestamps
- [ ] Daemon tick fires every minute (aligned to clock-minute boundary) and evaluates pending cron jobs
- [ ] For each enabled cron job: compute the most-recent scheduled slot in the past; compare to `last_fired_at`
  - If never fired and slot is in catch-up window → fire (mark `outcome='caught_up'`)
  - If `last_fired_at >= slot` → no-op (already fired)
  - If `last_fired_at < slot` and slot is in catch-up window → fire (mark `outcome='caught_up'` if >5min late, else `outcome='success'`)
  - If `last_fired_at < slot` and slot is OUTSIDE catch-up window → mark as skipped, advance to next slot
- [ ] Overlap detection: before firing, check if there's an in-flight `cron_job_runs` row for this job (`completed_at IS NULL`); if so, skip + write a `cron_skipped_overlap` row in `system_recommendations`
- [ ] Runner spawns `sh -c "<command>"` as subprocess; redirects stdout/stderr to log files at `~/.local/share/proxy/cron-runs/<job-name>/<scheduled_for_iso>.{out,err}`
- [ ] On subprocess exit: write `completed_at`, `outcome`, `exit_code` to `cron_job_runs`
- [ ] CLI `proxy cron add reorient --cron "0 4 * * *" --command "claude -p '/reorient --unattended'"` registers the job; appears in `proxy cron list`
- [ ] CLI `proxy cron list` shows: name, cron_expr, next_fire (computed), last_fired_at, last_fired_outcome
- [ ] CLI `proxy cron run <name>` fires the job manually (records as `outcome='manual'`)
- [ ] CLI `proxy cron history <name>` shows recent runs with timestamps + outcomes
- [ ] `cargo test` covers: cron parse, catch-up window logic (in-window, out-of-window, exactly at boundary), overlap skip, subprocess spawn + capture, log file write
- [ ] `cargo clippy --all-targets -- -D warnings` clean
- [ ] After this lands, register `/reorient` at `0 4 * * *` and let it run for at least 2 nights to validate

## Feedback loops

- `cargo test` (unit tests for cron logic)
- `cargo clippy --all-targets -- -D warnings`
- Manual: register a `* * * * *` job that `echo $(date) > /tmp/cron-smoke.log`; wait 2 min; verify the log file has 2 timestamps
- Manual catch-up: register a `0 4 * * *` job; let the Mac sleep through 4am; on wake, verify the job fires within the daemon's next tick and `outcome='caught_up'`
- Manual overlap: register a job that `sleep 120` runs every minute; verify only one fires at a time; verify `cron_skipped_overlap` rows appear in `system_recommendations`

## Quality bar

production

## Design notes

- **In-daemon, Postgres-backed.** Don't use `launchd` `StartCalendarInterval` — it doesn't catch up missed fires reliably, and we'd lose the ability to coordinate with PROXY's admission rule. Better: daemon owns the schedule. This matches the existing pattern (in-daemon Postgres scheduler replaces BullMQ).
- **Headless `claude -p` is the v1 invocation form.** Reliability decisively beats the chat-tab tmux-injection approach for cron specifically: works through Mac sleep, chat-tab crashes, user-mid-conversation. Trade-off (quota cost per fire) is small at typical cadences. See grilling 2026-05-16.
- **Catch-up window = 24h.** Hardcoded for v1; per-job override via `catch_up_window_hours` column is future-friendly but not used.
- **No retry on failure.** A failed fire is logged; user sees a recommendation. They can manually re-fire via `proxy cron run <name>`. Auto-retry is dangerous for stateful jobs like `/reorient`.
- **Tick cadence = 1 min.** Daemon's main loop already ticks at 2-5s for sensor; cron needs 60s. Use a separate tick channel aligned to clock-minute boundaries (compute `Instant::now() + remainder_until_next_minute_start` for first tick, then 60s thereafter).
- **Cron expression validation.** Reject malformed expressions at `add` time, not at fire time. Use the `cron` crate's parser.
- **Time zone.** All cron expressions interpreted in machine-local time (per the daemon's process timezone). Document this explicitly in `proxy cron --help`.
- **Independent from `/schedule` skill.** That skill manages remote routines on a different substrate. v1 cron-system is PROXY-local. Consider unifying in v2 if patterns converge.
- **Memory awareness.** Each cron fire is a fresh `claude -p` process — counts against PROXY's admission rule via the standard subprocess RSS. The cron runner should call `proxy admission check tachikoma` before firing to be a good citizen; if admission denies, mark `outcome='deferred_pressure'` and retry on next tick.

## Recommended Tachikoma cap

`--afk 15` — new tables, new module, new CLI subcommand group, parser integration, subprocess + log capture, multiple test paths. Largest of the queue-draining batch.

## Related

- `~/.claude/skills/reorient/SKILL.md` — the first consumer (`0 4 * * *`)
- `~/projects/personal-nix/wiki/work-requests/proxy-timer-system.md` — sibling work-request (one-shot timers vs recurring cron; related notification surface)
- ADR (M3): in-daemon Postgres scheduler — extends this; cron is sugar on top of timer/schedule primitives
- `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` § 7 — admission rule (cron should be a good admission citizen)
