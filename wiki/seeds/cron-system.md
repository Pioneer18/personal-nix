---
title: "Cron system for PROXY (with sleep catch-up)"
tags: [proxy, cron, scheduling, automation, launchd]
last_updated: "2026-05-13"
target_repo: "~/Projects/tachikoma-starter"
status: open
---

A scheduling system in PROXY that can run skills/jobs on cron-style schedules, with **catch-up semantics** for when the Mac was asleep or off.

**First consumer:** [[reorient-skill]] runs at **4am every morning**.

**Catch-up requirement:**
- If the Mac was off / asleep at the scheduled time and is now past that time, **run immediately in the background** (don't skip to the next day's slot).
- Should not double-fire if the Mac was on at 4am and ran normally.

**Capabilities (likely scope):**
- Register a job: `(cron-expr, skill-or-command, mode: foreground|background)`
- List scheduled jobs
- Manual trigger / dry-run
- History/log of past runs (success, failure, skipped, caught-up)

**Open questions to resolve during grilling:**
- Substrate: launchd (native catch-up via `StartCalendarInterval` + missed-trigger semantics), an in-PROXY scheduler daemon, or PROXY API + launchd shim?
- How does a cron-fired job invoke a Claude Code skill? (headless `claude -p`? PROXY internal task runner?)
- Concurrency — what if a previous run hasn't finished when next slot fires?
- User-facing surface: PROXY API endpoint, CLI, both?
- Relation to existing `schedule` skill (which manages remote routines on a different substrate)? Local-only vs. unified?
- Notification on completion — voice mode? notification banner? silent unless failure? (Pairs with [[proxy-timer-system]] alert modes.)
- Failure backoff / retry policy.
