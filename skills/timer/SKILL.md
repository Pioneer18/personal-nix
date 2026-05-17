---
name: timer
description: Daemon-resident timers via PROXY. One-shot timers and Pomodoro loops with voice + macOS notification alerts. Triggers — `/timer 10m`, `/timer pomodoro`, "set a 5 minute timer", "start a pomodoro", "cancel my coffee timer", "what timers are running?", or any natural-language timer ask. Wraps the `proxy-daemon timer` CLI; PROXY daemon must be running.
---

# Timer

Thin natural-language wrapper over `proxy-daemon timer` (see work-request `proxy-timer-system`). Parses the user's intent + duration, dispatches the right verb, prints a short confirmation. Execution + alerting happen inside the daemon's tick loop — this skill never blocks waiting for a timer to fire.

## Prerequisite

The PROXY daemon must be running. If `proxy-daemon timer list` returns a non-zero exit code, refuse with:

```
✗ PROXY daemon unreachable — `proxy-daemon timer list` failed.
  → Start it: cd ~/Projects/tachikoma-starter && cargo run --bin proxy-daemon
```

Do not fall back to `sleep N && say`.

## Verbs

| User intent | CLI |
|---|---|
| "set a 10 minute timer" / `/timer 10m` | `proxy-daemon timer add <auto-name> --duration 10m` |
| "5 minute coffee timer" / `/timer 5m coffee` | `proxy-daemon timer add coffee --duration 5m` |
| "1h30m timer to call mom, say 'call mom'" | `proxy-daemon timer add <auto-name> --duration 1h30m --message "call mom"` |
| "silent 5 minute timer" | `proxy-daemon timer add <auto-name> --duration 5m --no-voice --no-notification` |
| "start a pomodoro" / `/timer pomodoro` | `proxy-daemon timer pomodoro <auto-name>` |
| "pomodoro for 50 min focus blocks" | `proxy-daemon timer pomodoro <auto-name> --focus 50` |
| "deep work pomodoro 90/15, 2 cycles" | `proxy-daemon timer pomodoro <auto-name> --focus 90 --break 15 --cycles 2` |
| "what timers are running?" / `/timer list` | `proxy-daemon timer list` |
| "cancel my coffee timer" | `proxy-daemon timer cancel coffee` |
| "pause my focus timer" | `proxy-daemon timer pause focus` |
| "resume my focus timer" | `proxy-daemon timer resume focus` |
| "show recent timers" / `/timer history` | `proxy-daemon timer history` |

## Parsing rules

### Duration

Accept the canonical `proxy-daemon` grammar — `10s`, `5m`, `2h`, `1h30m`, `90s` — and normalise common natural-language phrasings into it:

- "10 seconds" → `10s`
- "5 minutes" / "five min" / "5min" → `5m`
- "2 hours" → `2h`
- "1 hour 30 min" / "an hour and a half" → `1h30m`
- "90 sec" / "ninety seconds" → `90s`

If you can't parse a duration unambiguously, ask the user to restate as a `Xh/Xm/Xs` string. Do **not** guess.

### Name

If the user supplies a name explicitly ("coffee timer", "timer called focus"), use it. Otherwise auto-generate kebab-case from the duration + intent — e.g. `timer-10m-1734567890` (suffix = current Unix timestamp) — so multiple anonymous timers don't collide on the partial unique index. Names are case-sensitive; cap at 128 chars.

### Pomodoro flags

All in **minutes** (matching `--help`): `--focus N`, `--break N`, `--long-break N`. `--cycles N` is an integer. Defaults: 25 / 5 / 15 / 4. Don't translate user-stated seconds — if the user says "30 second focus" that's not Pomodoro, that's a oneshot.

## Output

After running a CLI verb, show the CLI's stdout verbatim — it's already short and human-readable. Don't re-summarise.

For `list` and `history` (which emit JSON), render as a small table:

```
NAME          MODE      PHASE    REMAINING   PHASE-DETAIL
coffee        oneshot   running  3m12s       —
work          pomodoro  running  18m05s      focus 2/4
break-then    oneshot   paused   2m00s       —
```

Compute `REMAINING` as `mm:ss` (or `Xh Xm Xs` if ≥ 1h) from the `remaining_sec` field — do **not** recompute from `fire_at` (the daemon already did the math at print time). `PHASE-DETAIL` shows `<pomodoro_phase> <pomodoro_cycle>/<total_cycles>` for pomodoros, `—` for oneshots.

When `list` returns `[]`, say "No active timers." When `history` returns `[]`, say "No timer history."

## Errors

The CLI exits non-zero with a human-readable message on stderr. Surface it verbatim — don't translate. Common cases:

- `timer name must not be empty` — re-prompt for the name.
- `no active timer named "X"` — list active timers and ask which one the user meant.
- `timer name "X" already in use by a running or paused timer` — ask whether to cancel the existing one first or pick a different name.
- `--duration "X": duration ...` — re-prompt for a valid duration string.

## What this skill does **not** do

- Doesn't execute timers itself (the daemon owns ticking).
- Doesn't run arbitrary commands at fire time (`--exec` is deferred to v2).
- Doesn't sync timers across machines.
- Doesn't manage TUI / web UI surfaces (defer to those skills when they ship).
- Doesn't replace `at`/`cron` for scheduled jobs (use `proxy-daemon scheduler` for cron-style jobs).
