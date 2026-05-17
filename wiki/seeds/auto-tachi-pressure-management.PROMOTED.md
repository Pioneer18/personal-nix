---
title: "PROXY auto-manages Tachikoma count based on system metrics"
tags: [proxy, tachikoma, admission, memory, safety, system-manager, daemon]
last_updated: "2026-05-14"
target_repo: "~/Projects/tachikoma-starter"
status: open
---

Move the memory-pressure safety monitor from a manual Claude-driven loop into the `proxy-daemon`. Today a live Claude session polls `vm_stat` / swap / `tachikoma-status` on a self-paced loop and warns / kills under thresholds. This should be daemon-resident: always-on, no chat surface needed, integrated with the existing admission rule.

## Current manual implementation (interim — retire when this ships)

- [`~/projects/personal-nix/wiki/recipes/claude-memory-safety-monitor.md`](../recipes/claude-memory-safety-monitor.md) — behavioral spec for a Claude monitor
- [`~/projects/personal-nix/skills/memory-tidy/SKILL.md`](../../skills/memory-tidy/SKILL.md) — user-invoked counterpart
- [`~/projects/personal-nix/wiki/decisions/container-explicit-opt-in.md`](../decisions/container-explicit-opt-in.md) — policy

These work but require a live Claude session to be actively polling. They are the bridge until this lands.

## Gap analysis vs existing PROXY architecture

PROXY's admission rule (ARCHITECTURE.md § 7) already gates **new Docker loops** on 4 gates (pressure level, VM-reserved-budget, host headroom, load5). But today's Tachikomas run as **host processes** (`claude -p` subprocesses in git worktrees), NOT as the Docker loops the admission rule was designed for. So they bypass PROXY's gates entirely. Two pieces missing:

1. **Admission**: `/tachikoma` (the launcher skill in `~/.claude/skills/tachikoma/`) should consult PROXY's sensor + admission rule before spawning the worktree's `claude -p` process. Today it spawns unconditionally.
2. **Runtime termination**: a sentinel inside `proxy-daemon` that enumerates running Tachikomas (pid-based, since they're host processes), applies an escalating rubric (~the recipe's GREEN/YELLOW/RED), and kills the highest-RSS tachi when pressure is sustained Red. Needs audit row + user-configurable thresholds in `proxy.toml`.

## Capabilities (likely scope)

- **CLI**: `proxy tachi admit <run-id>` returns admit/reject based on current sensor state; surfaceable to `/tachikoma` skill
- **Daemon sentinel**: 30-60s tick that reads sensor + enumerates running tachikoma pids (parse `~/Projects/*-tachikoma-*/.tachikoma/run.pid` files + verify liveness); enforces termination on sustained Red
- **`proxy.toml` knobs**:
  - `tachi.max_concurrent` (e.g. 3 sustained, 5 burst)
  - `tachi.pressure_red_swapouts_per_sec` (e.g. 500)
  - `tachi.pressure_red_sustained_samples` (e.g. 3 consecutive)
  - `tachi.termination_grace_seconds` (e.g. 30s before SIGKILL)
  - `tachi.protect_interactive_pids` (allowlist for "this is my own active session")
- **`system_recommendations` integration**: emit row when tachi termination fires (audit + UI surface per ARCHITECTURE § 8)
- **Tachikoma client side**: `~/.claude/skills/tachikoma/lib/queue-grab.sh` already reads sensor; extend to honor admission verdict before fork

## Relation to existing queue items

Overlaps with — but is more specific than — `proxy-12b-recommendations-engine` (proposes actions) and `proxy-32-operations-proactive-engine` (drafts). Those two *propose*; this one *acts* within a configured threshold envelope. Decision needed during grilling: fold into 12b or stand alone? Recommend stand alone — different trust boundary (autonomous termination vs draft-only).

The existing PROXY admission rule (ARCHITECTURE § 7) is the substrate. This work makes it consulted by the right code paths (Tachikoma startup) and adds the runtime-termination half.

## Open questions to resolve during grilling

- Termination authority — daemon-resident autonomous (no human in loop, audit-only) or always-propose-then-confirm? Recipe today does autonomous *only* when 2+ tachis live and Red is sustained. Carry that forward, or tighten?
- How to distinguish "user is actively working in this Tachikoma worktree" from "autonomous bg work"? Currently every tachikoma run is autonomous bg work, so this might not be a real problem yet — but the day a user wants to *be* in a tachikoma worktree, the sentinel must not nuke it.
- Threshold defaults — calibrate "sustained Red" from real data. Initial guess: 3 consecutive 60s samples with swapouts/sec > 500 AND effective_free < 1.5 GB.
- Audit retention — `system_recommendations` lifecycle already prunes after action; do termination events need longer-term retention (90 days)?
- `proxy.toml` first-run wizard (slice `proxy-15b`) — derives defaults from observed post-bring-up state. This is a follow-on knob set; should slot in cleanly.

## Acceptance criteria

- Running 7+ Tachikomas under load reliably triggers termination of the highest-RSS one, with audit row in `system_recommendations`
- New Tachikoma launches refused (or queued) when pressure level = Warn or Critical
- `proxy.toml` thresholds documented + first-run wizard sets sensible defaults
- The interim recipe + skill marked deprecated; cross-references updated to point at the daemon feature

## Sunset of the interim layer

When this ships, append a "Retired" note to:

- `recipes/claude-memory-safety-monitor.md`
- `skills/memory-tidy/SKILL.md` description
- `decisions/container-explicit-opt-in.md` substrate carve-out section
