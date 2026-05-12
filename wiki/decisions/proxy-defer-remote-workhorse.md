---
title: "PROXY: defer the dedicated remote workhorse until throughput justifies cost"
tags: [proxy, hetzner, remote, deferred, cost, architecture, fly, runpod]
last_updated: "2026-05-11"
status: accepted
---

# PROXY: defer the dedicated remote workhorse

**Status**: Accepted — 2026-05-11.

**Scope**: This decision applies to PROXY (the orchestrator being built in `~/Projects/tachikoma-starter`). It does *not* preclude Major running on a remote box separately — that's a parallel decision (see [Major ADR 022](~/Projects/major/docs/adr/022-shell-claim-admission-system-pressure-aware.md) for Major's own admission story).

## Context

During the 2026-05-11 redesign session for PROXY (see [`docs/ARCHITECTURE.md`](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) for the v2 plan), a major question was: where do PROXY loops run, and is a remote workhorse part of v1?

**Why remote was tabled:**
- Goal: run AI subscriptions hot, maximum throughput, with Major as the workhorse for an early-stage startup.
- Local Mac is memory-constrained (24 GB), and a host-side crash on 2026-05-10 + 2026-05-11 (Ghostty OOM-killed by macOS Jetsam) confirmed the substrate is fragile under load.
- Memory pressure is the dominant bottleneck even after planned local fixes (Docker bump 4 → 12 GB, OrbStack, reboot, etc).

**Strongest remote candidate considered**: **Hetzner AX42 dedicated server**.

| Spec | Value |
|---|---|
| CPU | Ryzen 7 7700 (8c / 16t) |
| RAM | 64 GB DDR5 |
| Disk | 2× 512 GB NVMe (RAID 1 typical) |
| Price | ~€50/mo (~$54 USD), monthly contract |
| Cold-start latency for a spillover loop | ~1-2s (image pre-warm; box always-on) |

**Other candidates considered:**

| Provider | Pricing model | When it wins | When it loses |
|---|---|---|---|
| **Hetzner Cloud CCX33** (8 vCPU / 32 GB) | ~€55/mo flat | Want managed VM API + instant scale-up/down | Half the RAM of AX42 for same money; pay slightly more for less compute |
| **Hetzner Cloud CCX43** (16 vCPU / 64 GB) | ~€110/mo flat | Want runway on busy days | 2× cost of AX42 dedicated, similar real performance for our shape |
| **Fly.io Machines** (shared-cpu-1x@1GB) | per-second; ~$0.01/hr | Spillover is bursty (under ~200 hrs/mo of compute) | Costs run away on heavy continuous use |
| **RunPod CPU pods** | per-second, GPU-tier pricing | If you also need GPU — none of our work does | Overpriced for our CPU-only workload |
| **Modal** | serverless functions, Python-decorator model | If PROXY were Python-first | Awkward to wrap Docker-image loop runner; loses local/remote parity |
| **DigitalOcean / Vultr / Linode** droplets | flat-monthly | Generic fallback if Hetzner verification stalls | Higher $/perf than Hetzner dedicated |
| **Own home server / Mac Mini idle** | $0 marginal | If hardware already owned | None owned currently; can't act on this |

## Decision

**Defer building any remote backend for PROXY v1.** Ship `LocalDockerBackend` only. Architect the `RunBackend` trait (see `ARCHITECTURE.md` § 10 — slice `proxy-04c-run-backend-trait-and-local-docker`) so that adding `RemoteDockerBackend` is purely additive when the time comes.

**Reasoning:**
- €50/mo (~$54) is real recurring money on top of Anthropic + GPT subscriptions.
- The throughput need is **anticipated, not yet measured**. Local mitigations (Docker bump, OrbStack, system manager closing Chrome, etc.) might be sufficient for current load.
- Once measured, the cost case becomes empirical: triggers below.
- The local + remote architecture is identical at the `RunBackend` boundary; the deferral risk is mostly the time-to-build of `RemoteDockerBackend`, which is small (a few days of engineering work) when the time comes.

## Triggers for promoting from deferred → implemented

This decision is revisited (with intent to provision the box and ship `RemoteDockerBackend`) when **any one of these is true**:

1. **Local admission rejection rate** — PROXY's admission rule rejects **≥ N jobs/week for ≥ M weeks**. Initial threshold: N=5, M=2. Adjust after first month of telemetry.
2. **Memory pressure recurrence** — Jetsam-class events (Ghostty or any process classed as `largestProcess` in `JetsamEvent-*.ips`) recur **≥ 2× per week** despite local mitigations.
3. **Scheduled-while-asleep gap** — Recurring scheduled jobs (e.g. nightly digest, weekly report) consistently miss their `run_at` by > 4 hours because the Mac was asleep. Indicates need for 24/7 reachable host.
4. **Startup workload growth** — Major's workload (driven by RelyMD's startup-phase pace) hits a sustained ≥ 3 concurrent active Tachikomas, exhausting local Docker VM regardless of fixes.

Telemetry to support trigger detection:
- `system_recommendations` table tracks admission rejections (kind=`close-app` or any `close-*`) — count rejections/week.
- macOS Jetsam events scraped via daemon's uptime watcher (`ls -lt /Library/Logs/DiagnosticReports/JetsamEvent-*.ips` parsing).
- Scheduled job late-fire telemetry: log `late_by_seconds = fired_at - scheduled_run_at` per scheduled execution.

The daemon's recommendation engine emits a `consider-remote-workhorse` recommendation when any trigger fires.

## Cost math at decision time (2026-05-11)

| Scenario | Local-only cost | Hetzner AX42 cost | Fly.io cost (rough) | Best choice |
|---|---|---|---|---|
| Light spillover (10 hrs/mo) | $0 + crashes | €50/mo | ~$0.10/mo | **Fly** if any remote needed; local-only otherwise |
| Moderate (100 hrs/mo) | $0 + crashes + lost productivity | €50/mo | ~$1/mo | Fly |
| Heavy (500 hrs/mo) | Can't, local capacity exhausted | €50/mo | ~$5/mo | Fly still cheaper at this point |
| Always-on (2000 hrs/mo = 24/7) | N/A | €50/mo | ~$20/mo | Either; Hetzner gives more RAM/CPU |
| Always-on + 4 concurrent loops | N/A | €50/mo (covered) | ~$80/mo | **Hetzner wins decisively** |

Crossover is at ~200 compute-hrs/mo for AX42 vs Fly. Above this, Hetzner wins by a wide margin. **If we hit triggers above, we'll almost certainly be in the >200 hrs/mo regime** (because the triggers fire from sustained load, not occasional bursts).

## Consequences

**Positive:**
- Zero marginal $ until throughput is empirically demonstrated.
- v1 ships faster (no remote auth, no SSH/Tailscale setup, no `RemoteDockerBackend` slice).
- The `RunBackend` trait still exists in v1 — adding the remote impl later is a pure addition, not a rewrite.

**Negative:**
- Local capacity ceiling remains. If triggers fire mid-week, user has to do the Hetzner setup + auth + provisioning before throughput unblocks.
- Scheduled work during Mac sleep won't fire reliably. Caffeinate toggle helps but does not override lid-close (modern MacBook caveat). Until remote lands, "I want this job to run while I sleep" is best-effort.

**Mitigations:**
- The first-run wizard (slice `proxy-15b-first-run-wizard`) tells the user explicitly that remote is deferred and what the triggers are. No surprise.
- The recommendation engine emits `consider-remote-workhorse` rec when triggers fire — user sees the decision-point clearly.
- If a trigger fires unexpectedly fast, ~1 day of work + Hetzner verification gets us provisioned. Not a catastrophic time-to-recovery.

## Setup outline (when promoted)

(Quick reference; full recipe will be written when we promote.)

1. Hetzner account + KYC verification (~hours to ~48h)
2. Order AX42 via Server Auction (faster, pre-owned hardware) or new (1-24h provisioning)
3. First-login hardening (15 min, scriptable):
   - Create `proxy` user, add to `docker` group, install SSH public key, disable password auth
   - `ufw allow OpenSSH; ufw enable` (or Hetzner Cloud Firewall)
   - `apt install unattended-upgrades`
   - Install Tailscale, join the tailnet (private network, no public SSH)
4. Install Docker (`curl -fsSL https://get.docker.com | sh`), add `proxy` user to docker group
5. Test from Mac: `DOCKER_HOST=ssh://proxy@box docker info`
6. Implement `RemoteDockerBackend` in the daemon (one new struct impl'ing the `RunBackend` trait)
7. Add `backend = "remote"` option to per-repo config
8. Migrate Major Shells to box (optional but aligns with workhorse design)

## See also

- [`docs/ARCHITECTURE.md`](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) — PROXY v2 architecture
- [`runbooks/ghostty-jetsam-oom-kill.md`](../runbooks/ghostty-jetsam-oom-kill.md) — crash anatomy that motivated v2
- [Major ADR 022](~/Projects/major/docs/adr/022-shell-claim-admission-system-pressure-aware.md) — Major's parallel commitment
- [`recipes/mac-pre-proxy-prep.md`](../recipes/mac-pre-proxy-prep.md) — local fixes to run first
