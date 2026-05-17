---
title: "Claude memory-pressure safety monitor for Tachikomas"
tags: [tachikoma, memory, claude, safety, monitor, loop, proxy, interim, retired]
last_updated: "2026-05-14"
status: retired
retired_by: "auto-tachi-pressure-management (daemon-resident admission + sentinel slice)"
retired_on: "2026-05-14"
---

> **Retired 2026-05-14.** Replaced by the daemon-resident
> [auto-tachi-pressure-management](../work-requests/auto-tachi-pressure-management.md)
> slice: the field-calibrated rubric below now lives in
> `daemon/src/admission/tachi.rs`, the kill path in
> `daemon/src/admission/sentinel.rs`, and the CLI verdict
> (`proxy admission check tachikoma`, exit 0/3) is what
> `~/.claude/skills/tachikoma/lib/queue-grab.sh` consults. No
> session-scoped `/loop` monitor is required anymore — the daemon ticks
> every 30 s and autonomously SIGTERMs the worst-RSS tachi when
> sustained RED with ≥ 2 live processes. Keep this document for
> historical context only; do not run the loop instruction.

# Claude memory-pressure safety monitor

Behavioral spec for any Claude session acting as the memory-pressure safety monitor while Tachikomas run on Pioneer18's MacBook-Pro-2 (24 GB M4 Pro). **Retired** — the durable PROXY-daemon-resident version landed in the `auto-tachi-pressure-management` slice (2026-05-14); see [`daemon/src/admission/`](../../../Projects/tachikoma-starter/daemon/src/admission/) in the repo for the canonical implementation.

## Trigger

User says any of: `be my safety monitor`, `loop and watch memory pressure`, or `/loop <monitor instruction>`.

**Kill-authority does NOT transfer across sessions.** User must explicitly grant it ("you have authority to stop a Tachikoma on Red") each session. Default = warn only.

## Loop instruction (paste verbatim into /loop)

```
Memory pressure safety monitor for Tachikomas. Self-paced. Each iteration: vm_stat (compute effective_free = pages_free + pages_inactive, compute swapouts/sec rate vs /tmp/safety-mon-state.swapouts prev value diffed against /tmp/safety-mon-state.tstamp), sysctl vm.swapusage, mcp__tachikoma__tachikoma_status, OrbStack vmgr RSS via ps. Apply rubric using effective_free (NOT raw pages_free — inactive is reclaimable on macOS): GREEN (effective_free > 4 GB AND swapouts/sec < 100) → silent, ScheduleWakeup 90s. YELLOW (effective_free 2-4 GB OR swapouts/sec > 500 sustained across iterations OR rapid drop > 1 GB since last sample) → report concisely with the numbers, ScheduleWakeup 60s. RED (effective_free < 1.5 GB AND swapouts/sec spiking, OR multi-iteration sustained pressure) → if 2+ Tachikomas running (live pid), autonomously docker stop the container with highest in-VM RSS (use docker stats --no-stream) and report; if 1 Tachikoma running, warn user loudly with full data (do not kill without explicit ask); if 0 Tachikomas running, warn user that pressure is host-side and cite top RSS culprits + propose /memory-tidy actions.
```

## Iteration script (run each tick)

```bash
STATE=/tmp/safety-mon-state
NOW=$(date +%s)
PREV_TS=$(cat "$STATE.tstamp" 2>/dev/null || echo 0)
PREV_SO=$(cat "$STATE.swapouts" 2>/dev/null || echo 0)

PAGES_FREE=$(vm_stat | awk '/Pages free/ {print $NF}' | tr -d '.')
PAGES_INACTIVE=$(vm_stat | awk '/Pages inactive/ {print $NF}' | tr -d '.')
CUR_SO=$(vm_stat | awk '/Swapouts/ {print $NF}' | tr -d '.')

EFFECTIVE_FREE_K=$((PAGES_FREE + PAGES_INACTIVE))
EFFECTIVE_FREE_GB=$(echo "scale=2; $EFFECTIVE_FREE_K * 16 / 1024 / 1024" | bc)
DELTA_TS=$((NOW - PREV_TS))
DELTA_SO=$((CUR_SO - PREV_SO))
[ "$DELTA_TS" -gt 0 ] && SO_RATE=$((DELTA_SO / DELTA_TS)) || SO_RATE=0
VMGR_RSS_GB=$(ps -axo rss,command | awk '/vmgr/ && !/grep/ {printf "%.2f", $1/1024/1024; exit}')

echo "$NOW" > "$STATE.tstamp"; echo "$CUR_SO" > "$STATE.swapouts"; echo "$PAGES_FREE" > "$STATE.pages_free"

echo "free=${PAGES_FREE}p inactive=${PAGES_INACTIVE}p eff_free=${EFFECTIVE_FREE_GB}GB swapouts_rate=${SO_RATE}/s vmgr=${VMGR_RSS_GB}GB"
```

Then call `mcp__tachikoma__tachikoma_status` and count live Tachikomas (`status: running` AND `pid` not null).

## Rubric

Use **`effective_free` = `pages_free + pages_inactive`** — raw `pages_free` is misleading on macOS; inactive is reclaimable on demand.

| Severity | Effective free | Swapouts/sec | Action |
|---|---|---|---|
| 🟢 GREEN | > 4 GB | < 100 | One-line heartbeat. ScheduleWakeup 90s. |
| 🟡 YELLOW | 2-4 GB OR rate > 500 sustained OR drop > 1 GB | one of | Report inline with numbers. ScheduleWakeup 60s. |
| 🔴 RED | < 1.5 GB AND rate spiking, OR multi-iter sustained | both | See action matrix below. ScheduleWakeup 30-60s. |

**RED action matrix** (severity scales with Tachikoma count):

| Live Tachikomas | Action |
|---|---|
| 0 | Warn user; pressure is host-side. Cite top RSS culprits + propose `/memory-tidy` actions. Don't touch Tachikoma layer. |
| 1 | Warn loudly with full data. **Do NOT kill without explicit user yes** — they may be mid-task. |
| 2+ | Autonomously `docker stop <name>` on the container with highest in-VM RSS (`docker stats --no-stream`). Report after the fact. |

## Hard rules

- **Silent on Green**: one short line max ("🟢 eff_free=X GB · swapouts=N/s · vmgr=Y GB · N live"). Don't burn tokens with paragraphs.
- **Never kill on Yellow**: premature. User gets warning + tighter cadence instead.
- **"Live" = `status: running` AND non-null `pid`**. `status: unknown` with null pid does NOT count.
- **One-shot spikes ≠ sustained**: 800/s for one iteration is normal macOS reshuffle (background compaction, pre-emptive paging). Sustained = ≥ 2 consecutive iterations.
- **Always persist state files** — rate math requires diff vs prev iteration.
- **`orb stop && orb start` is reserved for /memory-tidy** when zero Tachikomas live. NEVER restart the VM while any Tachikoma is running — kills work in progress.
- **Restart of running PROXY substrate** (`proxy-postgres`, `proxy-redis`, `proxy-web`) is allowed without ask per `decisions/container-explicit-opt-in.md` carve-out. Don't `docker stop` them.

## State files (durable across iterations + agents)

| File | Content |
|---|---|
| `/tmp/safety-mon-state.tstamp` | Unix timestamp of last iteration |
| `/tmp/safety-mon-state.swapouts` | Cumulative Swapouts count at last iteration |
| `/tmp/safety-mon-state.pages_free` | Pages free at last iteration |

A handing-off Claude reads these to continue diff math without losing rate continuity.

## Resuming mid-loop (cold pickup)

1. Read this recipe → load rubric.
2. Read `/tmp/safety-mon-state.*` → get prev sample for rate calculation.
3. Run iteration script.
4. Apply rubric.
5. ScheduleWakeup with the verbatim `/loop <instruction>` prompt above.
6. **Confirm with user** that they want to re-grant kill-authority (don't assume).

## Cadence guidance

- 90s on Green: stays within 5-min prompt cache TTL; active polling cadence
- 60s on Yellow: tighter to catch sustained pressure
- 30s on active Red intervention: close to the action
- Don't pick 300s — worst-of-both per `ScheduleWakeup` cache guidance

## Sunset

Retire when `proxy-12b-recommendations-engine` ships (PROXY's native system-manager). Rule catalog migrates to `apps_registry` + `system_recommendations` DB rows; surfacing routes through `notify-app` + Ink TUI + Web UI per `ARCHITECTURE.md` § 8 + Q12 decision. This recipe + `/memory-tidy` are the interim bridge.

## See also

- [`decisions/container-explicit-opt-in.md`](../decisions/container-explicit-opt-in.md) — containers are explicit-opt-in; substrate-restart carve-out
- [`~/projects/personal-nix/skills/memory-tidy/SKILL.md`](../../skills/memory-tidy/SKILL.md) — interim memory-steward skill (user-invoked counterpart)
- [`~/Projects/tachikoma-starter/docs/ARCHITECTURE.md`](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) § 6-8 — sensor + admission + system-manager design
