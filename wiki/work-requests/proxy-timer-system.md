---
status: open
priority: 3
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-16
---

# PROXY — timer system + timer skill

> Grilled 2026-05-16. Decisions locked: PROXY-native primitive + thin skill wrapper; voice + notification default; multiple concurrent timers; Pomodoro 25/5 with CLI overrides. Ready for tachikoma dispatch.

## Why now

Working sessions and break reminders are unavoidable. Currently no PROXY-resident timer surface — user falls back to macOS Reminders, Siri, or scattered terminal `sleep N && say done` one-liners. Adding a first-class timer primitive completes the "scheduled actions" trio (one-shot scheduler → cron → timer) and gives `/reorient` a sibling skill family. Voice + notification integration is mostly wiring against existing proxy-voice + notify-app paths.

## Goal

A daemon-resident timer system that:

- Supports one-shot timers (`set a 10-minute timer`) and Pomodoro loops (25min focus / 5min break, 4 cycles, then 15min long break)
- Persists timer state in Postgres (survives daemon restart; resumes from `fire_at`)
- Fires both TTS-voice (via `proxy-voice` or `say`) and macOS notification by default; per-timer opt-out flags
- Supports multiple concurrent timers (named); each ticks independently
- Cancel / pause / resume via CLI + API
- Surfaces via a thin `/timer` skill for natural-language invocation
- CLI verbs: `proxy timer add`, `proxy timer list`, `proxy timer cancel`, `proxy timer pomodoro`

## Files in scope

- `daemon/migrations/<YYYYMMDDHHMMSS>_timers.sql` — new tables:
  ```sql
  CREATE TYPE timer_mode AS ENUM ('oneshot', 'pomodoro');
  CREATE TYPE timer_phase AS ENUM ('running', 'paused', 'completed', 'cancelled');
  CREATE TYPE pomodoro_phase AS ENUM ('focus', 'short_break', 'long_break');

  CREATE TABLE timers (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name            text NOT NULL,
    mode            timer_mode NOT NULL,
    phase           timer_phase NOT NULL DEFAULT 'running',
    duration_sec    integer NOT NULL,            -- current segment's duration
    started_at      timestamptz NOT NULL DEFAULT now(),
    fire_at         timestamptz NOT NULL,         -- absolute target time for current segment
    paused_at       timestamptz,                  -- if phase = 'paused'
    elapsed_at_pause integer,                     -- elapsed seconds when paused
    alert_voice     boolean NOT NULL DEFAULT true,
    alert_notification boolean NOT NULL DEFAULT true,
    custom_message  text,                          -- optional voice/notification text
    -- pomodoro-specific
    pomodoro_phase  pomodoro_phase,
    pomodoro_cycle  integer NOT NULL DEFAULT 0,    -- 1-indexed cycle counter
    focus_sec       integer,                       -- pomodoro override; default 25*60
    short_break_sec integer,                       -- default 5*60
    long_break_sec  integer,                       -- default 15*60
    total_cycles    integer,                       -- pomodoro stops after N cycles (default 4)
    created_at      timestamptz NOT NULL DEFAULT now()
  );
  ```
- `daemon/src/timers/mod.rs` (new) — tick logic, fire evaluation, pomodoro transitions
- `daemon/src/timers/alert.rs` (new) — alert dispatch:
  - Voice: invoke `proxy-voice` IPC if running; fall back to `say "<message>"` subprocess
  - Notification: invoke the bundled notify-app (M5) or `osascript -e 'display notification ...'` as v1 fallback
- `daemon/src/cli/timer.rs` (new) — CLI subcommand group:
  - `proxy timer add <name> --duration <Ns/Nm/Nh> [--message "<text>"] [--no-voice] [--no-notification]`
  - `proxy timer list` — show all running/paused timers with remaining time
  - `proxy timer cancel <name>` — cancel a timer
  - `proxy timer pause <name>` — pause (preserves elapsed)
  - `proxy timer resume <name>` — resume from pause
  - `proxy timer pomodoro <name> [--focus 25] [--break 5] [--long-break 15] [--cycles 4]` — start a pomodoro loop
  - `proxy timer history [--limit N]` — show recently-completed timers
- `daemon/src/main.rs` — wire timer tick into daemon's loop (1s cadence; precise enough for user-facing "I said 10 minutes")
- `~/projects/personal-nix/skills/timer/SKILL.md` (new) — natural-language wrapper:
  - Triggers: `/timer 10m`, `/timer 25min focus`, `/timer pomodoro`, "set a 5 minute timer", "start a pomodoro"
  - Parses duration + intent; calls `proxy timer add` / `proxy timer pomodoro`
- `~/.claude/skills/timer/` — symlink to personal-nix skill

## Files out of scope

- Persistence beyond daemon restart of pomodoro mid-cycle behavior: for v1, a daemon restart mid-pomodoro resumes from `fire_at` (absolute time); if `fire_at` is in the past, fire immediately and advance to next phase. Don't over-engineer recovery.
- Cross-machine timer sync (iCloud) — out of scope
- TUI surface for timer management — defer; CLI + skill is sufficient
- Web UI — defer
- Timer-fired arbitrary command execution (`--exec "<cmd>"`) — defer; v1 alerts only (voice + notification)
- Pomodoro long-break customization beyond cycle count — covered via `--long-break N` flag
- Sound effects beyond voice/notification — defer

## Stop condition

- [ ] DB migration creates `timers` table + enum types
- [ ] `proxy timer add my-timer --duration 10m` creates a timer; `proxy timer list` shows it counting down
- [ ] Duration parser accepts `10s`, `5m`, `2h`, `1h30m`, `90s` formats; reject malformed input at CLI
- [ ] When `fire_at` passes, alert fires: voice (via `proxy-voice` or `say` fallback) AND notification (via `osascript` v1 fallback or bundled notify-app post-M5)
- [ ] `--no-voice` flag disables voice; `--no-notification` disables notification; both can be set simultaneously (silent timer)
- [ ] `--message "<text>"` customizes the spoken/displayed alert
- [ ] Multiple concurrent timers: create 3 timers, all tick independently, each fires its own alert at the right moment
- [ ] `proxy timer cancel <name>` — phase → 'cancelled'; no alert fires
- [ ] `proxy timer pause <name>` — phase → 'paused'; remaining-on-pause stored
- [ ] `proxy timer resume <name>` — phase → 'running'; `fire_at` recomputed from now + remaining
- [ ] `proxy timer pomodoro work --focus 25 --break 5 --cycles 4` starts a pomodoro:
  - Phase 1: 25min focus → alert "focus done, take a break"
  - Phase 2: 5min break → alert "break done, back to focus"
  - … repeat for 4 cycles
  - After 4th focus: 15min long break → alert "long break done"
  - All phases share the same `name` and increment `pomodoro_cycle`
- [ ] Pomodoro phase transitions happen automatically without user intervention
- [ ] Daemon restart during a running timer: on boot, daemon reads timers WHERE phase='running'; for each, if `fire_at` is in the past, fire immediately + advance; if future, schedule normally
- [ ] `proxy timer history` shows recent completed/cancelled timers with timestamps + outcome
- [ ] `/timer` skill at `~/.claude/skills/timer/SKILL.md`:
  - Natural-language parse: "set a 10 minute timer" → `proxy timer add <auto-name> --duration 10m`
  - "start a pomodoro for 50 min focus blocks" → `proxy timer pomodoro <auto-name> --focus 50`
  - "cancel my coffee timer" → `proxy timer cancel coffee`
- [ ] `cargo test` covers: duration parsing, pomodoro state transitions, pause/resume math, daemon-restart resumption, alert dispatch (mock voice + notification)
- [ ] `cargo clippy --all-targets -- -D warnings` clean

## Feedback loops

- `cargo test`
- `cargo clippy --all-targets -- -D warnings`
- Manual: `proxy timer add coffee --duration 5s`; wait 5s; verify voice + notification fire with default message
- Manual: `proxy timer add quiet --duration 5s --no-voice`; verify only notification fires
- Manual: `proxy timer pomodoro test --focus 30s --break 10s --cycles 2`; verify the full focus/break/focus/break/long-break sequence runs end-to-end (~80s)
- Manual: start a 60s timer; `launchctl kickstart -k gui/$(id -u)/com.proxy.daemon` to restart daemon mid-tick; verify timer resumes correctly and fires at right moment
- Manual: `/timer 10m` from chat tab — skill parses and calls daemon successfully

## Quality bar

production

## Design notes

- **Tick at 1s, not 60s.** Timers are user-facing latency — "I said 10 minutes" should fire within 1s of the 10-minute mark. cron-system can tick at 60s because cron expressions are inherently minute-granular. Don't share tick cadence.
- **Absolute `fire_at`, not relative.** Persisting absolute timestamps means daemon restart math just compares to `now()`. No need to track "elapsed since started." Pause is the exception: store `elapsed_at_pause`, recompute `fire_at` on resume.
- **Voice IPC vs subprocess fallback.** Prefer the proxy-voice daemon's IPC channel (when running). Fall back to `sh -c "say '<message>'"` if proxy-voice isn't responsive. Test both paths.
- **Notification path: notify-app vs osascript.** notify-app (M5, bundled signed app) provides action-button notifications. osascript `display notification` is the v1 fallback — no buttons but reliable, no signing required.
- **Pomodoro state machine.** `focus → short_break → focus → short_break → ... → focus → long_break → DONE`. Track `pomodoro_cycle` (1-indexed); on cycle reaching `total_cycles` AND phase being `short_break`, transition to `long_break` instead. After `long_break`, phase → 'completed', timer ends.
- **Naming conflicts.** Two timers can't share a name (UNIQUE constraint on `name WHERE phase IN ('running', 'paused')`). Completed/cancelled timers free up the name.
- **Memory + admission considerations.** A running timer is just a Postgres row and a tick check; near-zero RSS. No admission gate needed. Multiple concurrent timers don't change this.

## Recommended Tachikoma cap

`--afk 12` — new table + enums, new module with tick logic, pomodoro state machine, CLI subcommand group with 6 verbs, alert dispatch with two paths each, duration parser, daemon-restart resumption, new skill. Medium scope.

## Related

- `~/projects/personal-nix/wiki/work-requests/cron-system.md` — sibling work-request (recurring schedules vs one-shot timers; both daemon-resident)
- `~/Projects/tachikoma-starter/docs/adr/002-voice-daemon-proxy-voice.md` — proxy-voice IPC surface this hooks into
- `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` § 15 — notify-app + osascript fallback paths
