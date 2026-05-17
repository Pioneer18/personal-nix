---
title: "Containers are explicit-opt-in, not background-default"
tags: [containers, docker, orbstack, memory, hygiene, agent-behavior, proxy]
last_updated: "2026-05-14"
status: accepted
---

# Containers are explicit-opt-in

**Status**: Accepted — 2026-05-14.

**Scope**: Pioneer18's MacBook-Pro-2 (24 GB M4 Pro). Applies to any agent or human bringing up Docker / OrbStack container stacks on this machine.

## Context

2026-05-14: while diagnosing OrbStack memory use (vmgr RSS at 3.07 GB), discovered host swap at 17.7 / 19.4 GB used and pages free at 232 MB — *while no immediate work needed most of the running containers*. The HealthBite supabase stack (~1.5 GB across 14 containers) and 3 Major Shells (~163 MiB combined) were running by default from the post-reboot bring-up documented in [`recipes/mac-pre-proxy-prep.md`](../recipes/mac-pre-proxy-prep.md). Same pressure regime that motivated PROXY ([`runbooks/ghostty-jetsam-oom-kill.md`](../runbooks/ghostty-jetsam-oom-kill.md)).

Per [`decisions/orbstack-over-docker-desktop.md`](./orbstack-over-docker-desktop.md) gotcha #5, OrbStack vmgr RSS approximately equals the sum of in-VM container memory. Idle-but-running containers cost real host RAM — not free.

## Decision

**Container stacks (Docker, OrbStack, supabase, RelyMD pg/redis, Major Shells, ad-hoc compose) are explicit-opt-in per work session.** They are not background defaults.

- Agents (Claude, automation) MUST NOT auto-start container stacks unless the user explicitly requests them for that session.
- After a reboot, the bring-up procedure does NOT auto-start supabase / Major Shells / etc. Bring them up only when needed for active work.
- When host pressure rises, stopping idle containers is the first move — propose to user, get approval, execute.
- `restart: unless-stopped` policies are tolerated only for PROXY's own substrate (proxy-postgres, proxy-redis, proxy-web). Everything else: no auto-restart on docker daemon up.

This is the local-host analogue of PROXY's hard rule #3 — *user confirmation for any host modification* ([`tachikoma-starter/CLAUDE.md`](~/Projects/tachikoma-starter/CLAUDE.md)).

## What stays running (PROXY substrate only)

- `proxy-postgres` — daemon's DB
- `proxy-redis` — daemon's cache
- `proxy-web` — daemon-managed Next.js (~80-150 MiB target)
- `proxy-daemon` — host process, not a container

## Substrate restart carve-out

Restart of an already-running PROXY substrate container (`proxy-postgres`, `proxy-redis`, `proxy-web`) does NOT require user ask. Same container, same semantic state — restart is just an RSS refresh. Agents may issue `docker restart <substrate>` when the container is bloated.

What still requires user ask:
- Starting a *stopped* substrate container (e.g. after `docker stop proxy-web`) — bringing it back up is a session-affecting action.
- Restarting a non-substrate container the user opted into this session (e.g. `supabase`, `shell-A`).
- Starting any non-substrate container from stopped (always).

### Daemon-side enforcement of the tachikoma half (2026-05-14)

The "stopping idle containers is the first move when pressure rises" bullet above is now backed by daemon-resident enforcement *for tachikomas specifically*: `proxy-daemon`'s admission sentinel (`daemon/src/admission/sentinel.rs`, shipped in the `auto-tachi-pressure-management` slice) ticks every 30 s and autonomously SIGTERM→grace→SIGKILLs the worst-RSS tachikoma when sustained RED with ≥ 2 live processes. New tachikoma launches go through `proxy admission check tachikoma` (exit 0/3) before the slug is claimed, so the bash-side gates in `queue-grab.sh` no longer drift across clients.

Non-tachikoma containers (idle dev servers, OrbStack stacks, etc.) remain user-disposed — the daemon does not touch them. See [`memory-tidy`](../../skills/memory-tidy/SKILL.md) for the user-invoked host-side prune flow.

## What requires explicit opt-in

- HealthBite supabase stack — `cd ~/Projects/healthbite && npx supabase start`
- RelyMD platform pg + redis — `cd ~/Projects/platform && bin/relymd pg --start && bin/relymd redis --start`
- Major Shells — `docker start shell-A shell-B shell-C`
- Any other dev compose stack

## Consequences

**Positive:**
- Baseline memory pressure stays low; Tachikomas + proxy loops have headroom by default.
- Memory math becomes predictable — what's running is what the user explicitly started this session.
- Aligns with PROXY's whole admission-control ethos.

**Negative:**
- One-time friction per session: start stacks before using them.
- Risk of forgetting and getting a confused error ("supabase down") — mitigation: agent should propose starting the stack when work that needs it begins.

## Triggers for revisiting

- A memory-aware boot orchestrator materializes (PROXY's first-run wizard slice `proxy-15b`, or `proxy-32` proactive engine surfacing "start X?" recommendations) — at that point this policy becomes its implementation, not a separate doc.
- Mac RAM upgrade renders the constraint moot (24 → 64 GB+).

## See also

- [`recipes/mac-pre-proxy-prep.md`](../recipes/mac-pre-proxy-prep.md) — post-reboot bring-up; "What's still pending post-reboot" items 1-3 should be read as opt-in, not auto
- [`decisions/orbstack-over-docker-desktop.md`](./orbstack-over-docker-desktop.md) — OrbStack vmgr RSS scaling behavior
- [`runbooks/ghostty-jetsam-oom-kill.md`](../runbooks/ghostty-jetsam-oom-kill.md) — crash anatomy that motivated PROXY
- [`~/Projects/tachikoma-starter/docs/ARCHITECTURE.md`](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) — PROXY admission control (hard rule #3)
