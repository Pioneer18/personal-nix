---
title: "Substrate: OrbStack over Docker Desktop for the local Docker VM"
tags: [orbstack, docker, mac, substrate, proxy, infrastructure]
last_updated: "2026-05-11"
status: accepted
---

# Substrate: OrbStack over Docker Desktop

**Status**: Accepted — 2026-05-11.

**Scope**: This decision applies to Pioneer18's MacBook-Pro-2 (Apple M4 Pro / 24 GB) as the Docker Compose substrate for PROXY, HealthBite supabase, RelyMD platform postgres/redis, and Major Shells. It does not affect any team-shared environment (RelyMD CI, others' machines).

## Context

During the 2026-05-11 PROXY v2 redesign and the parallel [mac-pre-PROXY prep recipe](../recipes/mac-pre-proxy-prep.md), the host MacBook had been hitting severe memory pressure: 60-day uptime, swap maxed at 34 GB of 35 GB, repeated Jetsam-class events killing Ghostty (and with it, every interactive `claude` session in PTYs). See [`runbooks/ghostty-jetsam-oom-kill.md`](../runbooks/ghostty-jetsam-oom-kill.md) for the crash anatomy.

Docker Desktop had been allocated only 4 GB of VM memory — far too small for 17 containers (3 Major Shells + RelyMD postgres/redis + HealthBite supabase stack). Bumping Docker Desktop to 12 GB was the single highest-impact host fix (recipe Step 1). But before doing so, the question arose: **stay on Docker Desktop, or switch to OrbStack?**

The decision was deferred during the grilling session and then made empirically during the post-reboot bring-up.

### Candidates compared

| Aspect | Docker Desktop | OrbStack |
|---|---|---|
| Host RSS (idle, no containers) | ~1.4 GB | ~300-500 MB |
| Host RSS (17 containers, our actual workload) | ~1.1 GB (pre-reboot, swapped state) | ~3.5 GB |
| VM memory allocation | Manual slider, default 4 GB | Auto-allocated, scales with available host RAM (gave 12.6 GB on 24 GB host) |
| CPU allocation | Manual slider | Auto, 14 cores on our 14-core M4 Pro |
| Docker socket API | Standard | Standard — drop-in compatible |
| Compose support | Yes | Yes |
| Volume management | Standard | Standard; imported existing volumes one-shot from Docker Desktop |
| GUI | Heavyweight Electron | Lightweight native (or none — runs headless) |
| Licensing | Free for personal/small business; commercial $5-$21/user/mo | Free for personal use, paid for commercial ($10/user/mo) |
| Update mechanism | Auto-update via Docker Desktop daemon | Auto-update via OrbStack helper |
| Available in nix-darwin | `homebrew.casks = [ "docker-desktop" ]` | `homebrew.casks = [ "orbstack" ]` (both declared via nix) |

## Decision

**Adopt OrbStack as the primary Docker Compose substrate on this machine.** Keep Docker Desktop installed for one week as a fallback, then uninstall (~22 GB disk reclaim). See the LaunchAgent reminder at `~/Library/LaunchAgents/com.pioneer.docker-desktop-uninstall-reminder.plist` scheduled for 2026-05-18.

**Reasoning:**
- The **12 GB VM memory ceiling** (vs Docker Desktop's 4 GB) is the decisive win. PROXY v2's whole admission rule assumes containerized loops can claim memory inside the VM — a 4 GB ceiling makes that math impossible. The 12.6 GB OrbStack ceiling gives PROXY real headroom for concurrent loop containers on top of the existing 17-container baseline.
- **Auto-allocation eliminates a manual tuning step.** Docker Desktop's slider would need adjustment as the workload grows; OrbStack scales without intervention.
- **Drop-in API compatibility.** Every `docker` / `docker compose` command, every volume, every container restart policy works unchanged. Migration was effectively a one-button import.
- **Lower idle host RSS.** When containers are quiet, OrbStack frees ~700 MB-1 GB host RSS vs Docker Desktop — directly reclaimed by Chrome, Major, or any other host workload. This benefit collapses under heavy container load (both VM hosts scale similarly with workload), but idle is the more common state.

## Triggers for revisiting

This decision is revisited (with intent to switch back to Docker Desktop or evaluate a third option) when **any one of these is true**:

1. **OrbStack instability** — More than one OrbStack-attributable container or volume corruption event per month. Definition: container state inconsistent with `docker inspect` output, or volume data unreadable on `docker run -v` mount.
2. **Performance regression** — Build, test, or daily-workflow latency increases by ≥ 20% vs Docker Desktop baseline on identical workloads. Measure via `relymd tests --int` wall-clock time (RelyMD platform integration tests are the dominant local workload).
3. **Licensing change** — OrbStack's free-for-personal-use terms change in a way that makes commercial use ambiguous. RelyMD work happens on this machine; if licensing flips, switch back to Docker Desktop (covered under RelyMD's existing subscription).
4. **Missing feature blocker** — A `docker compose` or `docker` feature we need (e.g. specific buildx flag, network mode, volume driver) is unsupported or behaves differently in OrbStack with no workaround.

## Consequences

**Positive:**
- 12.6 GB Docker VM ceiling (vs 4 GB) — direct enabler for PROXY concurrency.
- ~700 MB-1 GB host RSS reclaimed at idle.
- Auto-scaling VM means no tuning step as workload grows.
- Native macOS GUI is lighter than Docker Desktop's Electron app.

**Negative:**
- One-time cut-over cost: ~15 min for import + a few rough edges (see "Gotchas observed" below).
- Smaller user base than Docker Desktop → fewer Stack Overflow answers, fewer team-shared troubleshooting docs.
- License terms differ from Docker Desktop — if work mix shifts more commercial, this needs re-evaluation.

## Gotchas observed during cut-over (2026-05-11)

These caught us during the actual switch — worth capturing for any future similar substrate swap:

1. **OrbStack did NOT auto-launch on first boot** despite the "Open at Login" toggle being on. Had to `open -a OrbStack` manually. Verify the login-item is actually firing if you expect zero-touch recovery on reboot.
2. **All imported containers came back in `Created` state, not `Up`.** Restart policies from Docker Desktop did not transfer. Had to manually `docker start shell-A shell-B shell-C` and re-run `supabase start` + `bin/relymd pg --start` + `bin/relymd redis --start`. The recipe pre-reboot snapshot incorrectly assumed Major Shells would auto-resume.
3. **Postgres major-version mismatch on supabase volume import.** The imported `supabase_db_healthbite` volume had PG 15 data; HealthBite's `supabase/config.toml` is at `major_version = 17`. `supabase start` failed in a tight init loop. Resolution: `npx supabase stop --no-backup` (note: `--no-backup` removes volumes), then `npx supabase start` to recreate cleanly from migrations + seed. Worth knowing for any future PG-major-version-bump scenario.
4. **`docker system prune -a` reclaim was less than advertised.** The recipe estimated ~26 GB reclaim post-cutover; actual was 7.92 GB. Many "reclaimable" images were still backing running containers — image tags were removed but SHA refs preserved on the running containers. Real reclaim of the full ~26 GB requires stopping containers first, which trades stability for disk.
5. **OrbStack VM RSS scales with workload.** The "~300-500 MB host RSS" benchmark in recipe Step 2 was for OrbStack idle. Under our actual workload (17 containers), OrbStack's `OrbStack Helper vmgr` process sat at ~3.5 GB — higher than Docker Desktop's ~1.1 GB at the same workload pre-reboot. The "saves ~700 MB-1 GB host RSS permanently" prediction only holds when the VM is largely idle.

## See also

- [`recipes/mac-pre-proxy-prep.md`](../recipes/mac-pre-proxy-prep.md) — the ordered pre-PROXY fixes; OrbStack adoption is recipe Step 2
- [`docs/ARCHITECTURE.md`](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) — PROXY v2 architecture; the 12 GB VM ceiling enables admission control
- [`runbooks/ghostty-jetsam-oom-kill.md`](../runbooks/ghostty-jetsam-oom-kill.md) — crash anatomy that motivated the substrate change
- [`decisions/proxy-defer-remote-workhorse.md`](./proxy-defer-remote-workhorse.md) — parallel decision: stay local for now
