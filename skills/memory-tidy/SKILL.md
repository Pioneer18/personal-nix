---
name: memory-tidy
description: Diagnose host + Docker VM memory pressure on this Mac and propose targeted prunes (idle dev servers, long-running apps, idle containers, OrbStack VM restart, sudo purge). Read-only inventory + propose, never silent-action — complements PROXY's daemon-resident `auto-tachi-pressure-management` (which owns tachikoma admission + autonomous termination) by handling the broader host-side hygiene side. Use when memory feels tight, before launching parallel Tachikomas, when swap is high, or on `/memory-tidy`.
---

# Memory Tidy

Memory-steward for Pioneer18's MacBook-Pro-2 (24 GB M4 Pro). Inventories host + VM state, applies a rule catalog, returns a ranked list of proposed actions with concrete commands and approximate frees. User picks; skill executes approved subset.

**Scope boundary (post-`auto-tachi-pressure-management`, 2026-05-14):** the tachikoma-admission half is now owned by `proxy-daemon` — `daemon/src/admission/` evaluates the field-calibrated rubric and autonomously terminates the worst-RSS tachi under sustained RED. This skill complements that by covering the host-side prunes the daemon explicitly does NOT touch (idle dev servers, long-running app RSS, OrbStack VM restart, `sudo purge`). Treat this skill as user-invoked hygiene, not an automated guard.

## Always do (inventory)

Run these probes first; read into context before proposing anything:

```bash
# Host
vm_stat | head -8
sysctl vm.swapusage
uptime
memory_pressure 2>/dev/null | head -10 || echo "(memory_pressure unavailable)"

# Top host RSS (15 biggest)
ps -axo pid,etime,rss,command | grep -v "grep\|ps -axo" | sort -k3 -rn | head -15

# OrbStack vmgr + helper
ps -axo pid,rss,command | grep -E "vmgr|OrbStack" | grep -v grep | head -3

# Docker VM ceiling + in-VM container state
docker info --format '{{.MemTotal}}' 2>/dev/null
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}"
docker ps -a --filter "status=exited" --format "{{.Names}}"

# Tachikoma state
# (use mcp__tachikoma__tachikoma_status — never shell)
```

## Rule catalog

Surface only the rows that trigger. Each → one proposal with command + approximate free.

| Probe | Threshold | Proposed action | Notes |
|---|---|---|---|
| Microsoft Teams | etime > 8h | `osascript -e 'tell application "Microsoft Teams" to quit'` | ~400-500 MB. Don't probe for active calls — fragile. User can decline if mid-call. |
| Idle node dev server (`node start.js`, `next-server`, etc.) | RSS > 400 MB AND last HTTP request > 30 min | Kill + restart per dev-cycle convention (e.g. `mcp__relymd-devtools__restart_server` for RelyMD apps) | ~200-400 MB. Use `lsof -i :PORT` to find recent connections. |
| Multiple concurrent claude sessions | total active claude PIDs > 2 | List by etime; propose closing oldest non-current | ~200-400 MB each. Never auto-kill — sessions hold work-in-progress context. |
| Chrome aggregate RSS | sum of Chrome processes > 1.5 GB | Open `chrome://settings/performance` to maximise Memory Saver; OR quit + reopen pinned tabs only | ~600 MB-1.5 GB. Per-tab state is the risk. |
| Exited Docker containers cluttering | `docker ps -a --filter status=exited` non-empty | `docker container prune` | Disk + bookkeeping. Safe. |
| Idle Docker container (CPU < 0.1% for > 1h) NOT in PROXY substrate | always | `docker stop <name>` | Per Container Hygiene rule. Don't propose for `proxy-postgres`/`proxy-redis`/`proxy-web`. |
| OrbStack vmgr RSS large, no proxy work | vmgr > 2 GB AND `mcp__tachikoma__tachikoma_status` returns zero running | `orb stop && orb start` (VM restart, releases held pages) ⚠ stops all containers; user must restart any they need | ~1-3 GB. Nuclear — only when truly idle. |
| Swap pressure | swap used > 12 GB AND host pages free < 60K (16 KB pages = < 1 GB) | `sudo purge` AFTER tidying other items | Frees compressed cache. Slow (5-30 sec). |
| Uptime | > 7 days | Propose reboot at convenient point | Per `mac-hygiene-guide.md`. |
| Apple Intelligence loaded | `AppleIntelligencePlatform` RSS > 500 MB | System Settings → Apple Intelligence & Siri → toggle off | One-time; persistent across reboots. |
| Bloated `proxy-web` | RSS > 300 MB | `docker restart proxy-web` | Substrate exception: NO ASK needed (same-container restart). |

## Hard rules

- **Read-only by default**. Inventory + propose. Never act without an explicit user yes per item.
- **Substrate restart exception**. Restarting `proxy-postgres`, `proxy-redis`, `proxy-web` does NOT require ask — same container, no semantic change. Starting them from stopped DOES require ask (Container Hygiene rule).
- **One-prompt batch**. Surface ALL applicable proposals at once with single y/n per item — don't drip-feed across messages.
- **Cite numbers**. Every proposal must state approximate free ("~600 MB", "~3 GB if no loops running") so the user can prioritize triage.
- **Respect Container Hygiene**. Starting a stopped non-substrate container (supabase, Major Shells, RelyMD pg/redis) is OUT OF SCOPE for this skill — those require explicit user-initiated session ask. See `~/projects/personal-nix/wiki/decisions/container-explicit-opt-in.md`.
- **Never `sudo purge` first**. It's the last-resort cleanup AFTER user has approved other tidies; running it first wastes the cycle.
- **Never `orb stop && orb start` while Tachikomas are running**. Always check `mcp__tachikoma__tachikoma_status` first. Refuse if any are running, regardless of memory state.

## Output format

```
Memory state:
  pages free: ~<MB>     swap used: <X> / <Y> GB   uptime: <d/h>
  vmgr RSS:   <X> GB    Tachikomas running: <N>

Top offenders (filtered > threshold):
  <process>   <RSS>   <etime>
  ...

Proposed actions (total estimated free: ~<X> GB):
  [1] Quit Teams (etime 2d, ~452 MB)             → osascript ... quit
  [2] Restart `node start.js` api (533 MB, idle) → <exact restart cmd>
  [3] Restart OrbStack VM (vmgr 2.5 GB, 0 Tks)   → orb stop && orb start   ⚠ stops all containers
  [4] Discard idle Chrome tabs (~600 MB)         → open chrome://settings/performance
  [5] sudo purge (frees compressed cache)        → sudo purge   ⚠ run LAST

Reply: numbers to apply (e.g. "1,2,3"), "all", or "none".
```

## Open follow-ups (defer to a later iteration)

- Add a launchd plist that runs `vm_stat` + `sysctl vm.swapusage` every 15 min and emits a macOS notification on pressure-level transitions (Normal → Warn → Critical). Notification body: "Pressure rising — run /memory-tidy". Plist lives in `personal-nix/launchd/` and is nix-declared.
- Migrate the rule catalog into `apps_registry` + `system_recommendations` rows when `proxy-12b-recommendations-engine` slice lands. Retire this skill at that point.
- Add a probe for HTTP-server idle detection (parse access logs of well-known dev-server log paths) to make the "idle dev server" rule more reliable than the current "etime + RSS" heuristic.
