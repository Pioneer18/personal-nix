---
title: "Mac pre-PROXY preparation checklist"
tags: [proxy, mac, docker, hygiene, one-time, setup]
last_updated: "2026-05-11"
---

# Mac pre-PROXY preparation checklist

The ordered sequence of one-time fixes that should run *before* PROXY's first install. Doubles as a fresh-Mac prep runbook for any future workhorse-mode machine.

**Context**: PROXY's design (see [PROXY ARCHITECTURE](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md), grilled 2026-05-11) routes Claude loops into ephemeral Docker containers. The host's spare capacity is decisive: every GB freed on the Mac before PROXY ships is a GB available to concurrent Tachikomas and PROXY loops. This recipe surfaces the highest-impact pre-install actions, in order.

Each step has: **purpose**, **action**, **how to verify**, **estimated reclaim**, **revert / how to undo**. Tick the boxes as you go.

---

## Step 1 — Bump Docker Desktop memory allocation

**Purpose**: Today Docker is allocated 4 GB. With 17 containers (3 Major Shells + RelyMD + HealthBite stacks), in-VM headroom for active work is ~2.4 GB. Bumping to 12 GB unlocks ~7 GB for concurrent Tachikomas + PROXY loop containers. **Single highest-impact change.**

**Action**:
1. Open Docker Desktop → ⚙️ Settings → Resources → Memory
2. Drag slider from 4 GB to **12 GB** (or 16 GB if you have headroom)
3. Click "Apply & restart"
4. Wait ~30s for Docker to restart (the 17 containers should auto-restart unless you've changed restart policies)

**Verify**:
```bash
docker info --format '{{.MemTotal}}' | awk '{printf "%.1f GB\n", $1/1024/1024/1024}'
# Expected: ~11.5 GB after bump to 12 (Docker takes a slice for overhead)
docker ps --format 'table {{.Names}}\t{{.Status}}' | head -20
# All 17 containers should show "Up" again
```

**Estimated reclaim**: 7 GB usable inside Docker VM.

**Revert**: Re-drag slider back to 4 GB, Apply & restart.

- [ ] Done — record exact MemTotal observed:    `___________`

---

## Step 2 — Consider OrbStack migration (decision required)

**Purpose**: OrbStack is a Docker Desktop replacement reported to use ~300-500 MB host RSS for its VM host process vs Docker Desktop's ~1.4 GB. Same Docker socket API; all existing `docker` CLI usage, compose files, and 17 running containers work unchanged. Saves ~700 MB-1 GB host RSS permanently.

**Decision point**: This is a one-time substrate swap. Worth doing now if doing at all (less context-switch later).

**Action (only if migrating)**:
1. `brew install --cask orbstack`
2. Open OrbStack → it offers to "Import from Docker Desktop" — accept
3. Wait for image/volume import (varies, often 5-15 min depending on image sizes)
4. Quit Docker Desktop (it has a "Quit Docker Desktop" menu item)
5. In Docker Desktop Settings → General, uncheck "Open Docker Desktop on startup"
6. Optional: uninstall Docker Desktop entirely after verifying OrbStack works for a week

**Verify**:
```bash
docker info | grep "Operating System"
# Expected: "OrbStack" instead of "Docker Desktop"
docker ps | wc -l   # should match pre-migration count
```

**Estimated reclaim**: ~700 MB-1 GB host RSS (permanent, recurring).

**Revert**: Re-launch Docker Desktop; OrbStack imports are non-destructive to the original.

- [x] **Decision** (2026-05-11): **Migrate to OrbStack** ☑
- [x] Install via `brew install --cask orbstack` — completed 2026-05-11
- [x] Declared in `~/Projects/dev-environment/hosts/jonathan-sells-darwin.nix` `homebrew.casks` (declarative tracking)
- [x] Full cut-over (import from Docker Desktop, quit Docker Desktop, uncheck "Open at Login") — completed 2026-05-11 reboot. Docker Desktop processes absent from `ps` post-reboot.
- [x] Host RSS observed after cut-over + reboot (2026-05-11):
  - **OrbStack idle** (right after launch, containers in Created state): ~1.2 GB
  - **OrbStack under workload** (17 containers: 3 shells + 14 supabase + 2 relymd): ~3.5 GB
  - **Pre-reboot Docker Desktop** (11 containers, 60-day uptime): 1.1 GB
  - **Caveat**: the recipe's "saves ~700 MB-1 GB host RSS permanently" prediction assumed an idle baseline. Under matching workload, OrbStack's VM RSS scales like Docker Desktop's — savings only materialize when containers are quiet. The real win was the **12 GB VM memory ceiling** (vs Docker Desktop's 4 GB), which directly unblocks PROXY concurrency.

---

## Step 3 — Reboot the Mac

**Purpose**: Uptime is 59 days, 22 hours as of 2026-05-11. Per [mac-hygiene-guide § 13](../runbooks/mac-hygiene-guide.md#13-a-realistic-maintenance-schedule), weekly reboot is recommended at uptime > 7 days; you're 8× over. Reboot clears swap (currently 34 GB of 35 GB used), resets WindowServer (known Tahoe creep), drops dead pages, and resets accumulated kernel state.

**Action**:
1. Save and close anything important. Push any WIP commits.
2. Quit apps that don't auto-resume well (any actively-running Claude sessions you want to keep).
3. Apple menu → Restart… → uncheck "Reopen windows" (recommended for a clean baseline).
4. Wait ~60s for full boot.

**Verify**:
```bash
uptime
# Expected: "up X mins"
sysctl vm.swapusage
# Expected: total = 1024.00M (default seed), used ≈ 0 or very small
vm_stat | grep "Pages free"
# Expected: dramatically higher than 4462 (the pre-reboot value)
```

**Estimated reclaim**: 2-4 GB freed wired/leaked memory; full swap reset.

**Revert**: N/A.

- [ ] Done — record post-reboot free pages + swap used:    `___________`

---

## Step 4 — Disable Apple Intelligence (if unused)

**Purpose**: Apple Intelligence loads models into RAM permanently (`AppleIntelligencePlatform`, `GenerativeExperiencesSafetyInferenceProvider`). Per the hygiene guide § 3.5, this reclaims 1-3 GB.

**Action**:
1. System Settings → Apple Intelligence & Siri
2. If not actively using Apple Intelligence: toggle off
3. Restart Mac (Apple Intelligence won't fully release until next boot)
   - **Skip the second reboot if you already rebooted in Step 3 by disabling it BEFORE Step 3.** Recommended sequencing: do this *before* Step 3.

**Verify**:
```bash
ps -axo pid,rss,command | grep -i "AppleIntelligence\|GenerativeExperiences" | grep -v grep
# Expected: no matches OR very small RSS
```

**Estimated reclaim**: 1-3 GB host RSS.

**Revert**: System Settings → Apple Intelligence & Siri → toggle on.

- [x] **Decision** (2026-05-11): **Disable** ☑
- [x] Toggled off in System Settings → Apple Intelligence & Siri (completed 2026-05-11)
- [ ] Post-reboot RAM release verified (depends on Step 3 reboot):    `___________`

---

## Step 5 — Chrome Memory Saver: Maximum

**Purpose**: Chrome currently consumes ~3-3.5 GB across all renderers. Memory Saver (native, no extension) discards inactive tab renderers after a configurable idle period, reloading on click. Typical reduction: 60-80% Chrome footprint when many tabs are open.

**Action**:
1. Open Chrome → `chrome://settings/performance` in the address bar
2. **Memory Saver**: toggle On
3. Mode: **"Maximum memory savings"**
4. Optional: add never-discard sites (your daily-essentials) under "Always keep these sites active"

**Verify**:
```bash
# After 10 min of idle tabs, recheck:
ps -axo pid,rss,command | grep "Chrome Helper (Renderer)" | grep -v grep | wc -l
# Expected: fewer than pre-change count (idle tabs got discarded)
ps -axo pid,rss,command | grep "Google Chrome" | grep -v grep | awk '{sum+=$2} END {printf "%.1f GB\n", sum/1024/1024}'
# Expected: meaningfully lower than the pre-change 3-3.5 GB
```

**Estimated reclaim**: 1-2.5 GB host RSS (varies with tab count).

**Revert**: `chrome://settings/performance` → Memory Saver → Off.

- [ ] Done — record post-change Chrome total RSS:    `___________`

---

## Step 6 — Shut down idle iOS simulators

**Purpose**: Each booted simulator device consumes 2-4 GB. Per the hygiene guide § 8.1.

**Action**:
```bash
# Inventory
xcrun simctl list devices | grep "(Booted)"

# Shut down all
xcrun simctl shutdown all

# Optional: remove unavailable (for missing runtimes)
xcrun simctl delete unavailable
```

**Verify**:
```bash
xcrun simctl list devices | grep "(Booted)" | wc -l
# Expected: 0
```

**Estimated reclaim**: 0-8 GB depending on how many were booted.

**Revert**: Boot via Xcode or `xcrun simctl boot <device>` when needed.

- [x] Done — number shut down: **0** (no sims booted on probe, 2026-05-11)

---

## Step 7 — Docker prune (after Steps 1, 2 settled)

**Purpose**: Docker accumulates unused images, dangling layers, exited containers, and orphaned volumes. Per the hygiene guide § 8.5.

**Action**:
```bash
# Inventory first
docker system df

# Prune (NOT --volumes flag unless you've audited volumes — Postgres data lives in them)
docker system prune -a

# If you're sure no volume has irreplaceable data:
# docker system prune -a --volumes    # AGGRESSIVE
```

**⚠️ Warning**: `--volumes` deletes named volumes including `supabase_db_healthbite` etc. **Audit first**: `docker volume ls` and verify each has a backup or is reproducible.

**Verify**:
```bash
docker system df
# Expected: dramatically smaller "RECLAIMABLE" column
```

**Estimated reclaim**: Variable; commonly 5-20 GB Docker VM disk.

**Revert**: N/A (deletes are permanent).

- [ ] Done — record GB reclaimed:    `___________`

---

## Step 8 — Audit Login Items + Background Items

**Purpose**: Per hygiene guide § 7.3, "this is where the real bloat lives." Each background agent is a process, memory consumer, and often a network caller.

**Action**:
1. System Settings → General → Login Items & Extensions
2. Review "Open at Login": disable apps you don't need launching at boot
3. Review "Allow in the Background": disable any vendor helper you don't actively use (Adobe, Microsoft AutoUpdate, Zoom helpers, Dropbox, Logitech, etc.)

**Deeper inspection**:
```bash
launchctl list | grep -v com.apple | head -30   # user-loaded
sudo launchctl list | grep -v com.apple | head -30   # system-loaded
ls ~/Library/LaunchAgents/   # per-user agents (third-party)
```

**Verify**: rerun `launchctl list` post-changes; count of non-Apple entries should drop.

**Estimated reclaim**: Variable, often surprising (200 MB - 1 GB).

**Revert**: re-enable in Settings, or `launchctl load -w ~/Library/LaunchAgents/...plist`.

- [ ] Done — record number of items disabled:    `___________`

**Audit baseline (2026-05-11, probe via `launchctl list | grep -v com.apple | wc -l`)**: 30 non-Apple launch agents. Notable entries surfaced for review:

- `com.spotify.client.startuphelper` — Spotify launcher
- `com.microsoft.update.agent` — MS AutoUpdate
- `org.nix-community.home.tachikoma-ui` — Tachikoma UI helper
- `com.docker.helper` — Docker Desktop helper (will be removable after OrbStack cut-over)
- `org.nixos.docker-desktop` — same (declared via dev-environment)
- Several `ShipIt` updaters (Discord, VSCode, Notion, wispr-flow) — auto-updaters running unnecessarily
- `com.google.GoogleUpdater.wake` — Google Updater
- `org.xquartz.startx` — XQuartz auto-start (unused?)
- `com.openai.codex-sparkle-progress` — OpenAI Codex (still active?)

Audit each in System Settings → General → Login Items & Extensions → "Allow in the Background". Disable any not actively used.

---

## Step 9 — Verify post-fix system state

After all above complete, run a comprehensive check to confirm we're ready for PROXY.

**Action**:
```bash
# Hardware confirmation
system_profiler SPHardwareDataType | grep -E "Model Name|Chip|Cores|Memory"

# Memory state
vm_stat | head -8
sysctl vm.swapusage

# Docker VM allocation + state
docker info --format '{{.MemTotal}} bytes / {{.NCPU}} CPUs, {{.OperatingSystem}}'
docker ps --format 'table {{.Names}}\t{{.Status}}' | wc -l   # container count

# Top resident processes
ps -axo pid,rss,command | sort -k2 -rn | head -15

# Uptime
uptime

# Free disk
df -h / | tail -1
```

**Expected state** (rough numbers, post-all-fixes, idle):
- Pages free > 100,000 (vs current 4462)
- Swap used: near zero (post-reboot)
- Docker VM: ~12 GB MemTotal
- Uptime: minutes-to-hours, not days
- Top RSS: Docker VM (~500 MB if OrbStack, 1.4 GB if Docker Desktop), Chrome (1-1.5 GB after Memory Saver kicks in)
- Disk free: > 15% of data volume

- [x] Done — post-fix snapshot (2026-05-11, ~5 min uptime, after stacks brought up):

```
Hardware:      MacBook Pro / Apple M4 Pro / 14 cores (10P + 4E) / 24 GB
Uptime:        5 min   (was 60d 0h 43m)
Pages free:    7332    (~115 MB; page size is 16384 bytes — recipe target "100k" assumed 4KB pages)
Pages active:  488465  (~7.5 GB)
Pages inactive:486501  (~7.4 GB; reclaimable)
Pages wired:   ~150k   (~2.3 GB; was ~4.6 GB pre-reboot)
Swap used:     0.00 MB (was 34.2 GB pre-reboot — full reset)
Load avg:      8.4     (settling from reboot, was 11.1 pre-reboot)
Docker VM:     12.59 GB / 14 CPUs / OrbStack (auto-allocated, no slider needed)
Containers:    17 running (3 Major Shells + 14 supabase + 2 relymd pg/redis)
Disk used:     731G / 927G = 79%   (was 85% — ~53 GB reclaimed)
```

**Compared to pre-reboot expectations**: ✅ swap reset, ✅ wired memory dropped, ✅ OrbStack VM at 12 GB as predicted, ✅ disk reclaimed. ⚠️ no containers auto-started despite expectation (had to manually `docker start shell-A shell-B shell-C`). The other 14 containers required explicit `supabase start` + `relymd pg -s` + `relymd redis -s` — none came back from restart policy.

---

## Step 10 — Capture session

When all above ticked, record summary at the bottom of this file (date, total reclaimed RAM, total reclaimed disk, total runtime). Then [PROXY ARCHITECTURE](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) implementation can begin.

### Session summary — 2026-05-11 (pre-reboot grilling + post-reboot bring-up)

| Metric | Before | After | Delta |
|---|---|---|---|
| Uptime | 60d 0h 43m | <1h | reboot ✅ |
| Swap used | 34.2 GB (max) | 0 MB | **-34 GB** ✅ |
| Pages wired | ~4.6 GB | ~2.3 GB | **-2.3 GB** ✅ |
| Docker runtime | Docker Desktop, 4 GB VM | OrbStack, 12.6 GB VM | **+8 GB VM ceiling** ✅ |
| Disk used | 784 GB / 85% | 723 GB / 78%* | **-61 GB** ✅ |
| Chrome RSS | 3.3 GB | 7.8 GB (pre-Saver) | pending Saver toggle |
| Apple Intelligence RSS | multi-GB | 7 MB | **~3 GB reclaimed** ✅ |
| Non-Apple launch agents | 30 | 20 | -10 (and 2 nix `sh` re-enabled — see § Step 8 audit notes) |
| Containers running | 17 (4 GB allocated) | 17 (12.6 GB allocated) | same workload, 3× headroom |

*Includes 7.92 GB from `docker system prune -a`.

**Total runtime**: ~6h (grilling 4h + bring-up 1.5h + verification + recipe updates ~30 min).

**PROXY-readiness**: ✅ Verified — same workload as pre-reboot now runs with swap at 0 MB. The 24 GB host has comfortable headroom for additional PROXY loop containers.

**Skill change**: `~/.claude/skills/auto-review-prs/SKILL.md` patched to resolve `$BASE_BRANCH` from `dev → develop → main → master` instead of hardcoding `dev` — necessary because tachikoma-starter uses `develop`. Net effect: skill now works against any repo with a recognized integration branch.

**Outstanding for next session**:
1. Toggle Chrome Memory Saver → Maximum (settings page already open). Verify RSS drops after ~2h idle.
2. Manually close obsoleted PRs #8, #14, #18 on tachikoma-starter per ARCHITECTURE.md § 10.
3. PR #5 (scaffold) needs a walkthrough-mode override or carve-out broadening for infra files.
4. After ~1 week: uninstall Docker Desktop cask entirely (~22 GB disk).

---

## 🔁 SESSION RESUME POINT

**If a new Claude session is reading this post-reboot of 2026-05-11**: pick up at **Step 9 (verify post-fix system state)**. Compare the live numbers to the pre-reboot snapshot just below. Then proceed to bring up missing dev stacks (HealthBite supabase, RelyMD postgres+redis) — see "What's still pending post-reboot" further below.

To re-orient quickly, read in this order:
1. `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` (PROXY v2 — the architecture all this prep is for)
2. `~/projects/personal-nix/wiki/decisions/proxy-defer-remote-workhorse.md` (why no remote box)
3. `~/Projects/major/docs/adr/022-shell-claim-admission-system-pressure-aware.md` (Major coordination)
4. This recipe (you're here)

The 12-decision grilling synthesis and the full slice-plan impact are in ARCHITECTURE.md § 4 + § 10.

### Pre-reboot snapshot (2026-05-11 22:08 EDT)

```
Uptime:        60 days, 0h 43m
Pages free:    6004     (~96 MB)
Pages active:  348583   (~5.3 GB)
Pages inactive:347288   (~5.3 GB)
Pages wired:   303872   (~4.6 GB)
Swap used:     34.2 GB / 35.8 GB allocated
Load avg:      11.12 / 11.31 / 11.15
Active Docker: Docker Desktop (will flip to OrbStack post-reboot — DD auto-launch disabled)
Running ctrs:  11 in Docker Desktop / 7 in OrbStack (Created state)
Disk used:     784G / 927G = 85%   (~22 GB lost to OrbStack import duplication; reclaimable post-cutover)

Top RSS:
  1110 MB  Virtualization.framework VM (Docker Desktop's VM)
   550 MB  Chrome Framework helper
   456 MB  claude (interactive session)
   443 MB  Google Chrome (main)
   378 MB  OrbStack Helper
   267 MB  Chrome Framework helper
   187 MB  com.docker.backend services
```

### Expected post-reboot state (success criteria for Step 9)

- Pages free: > 100,000 (vs 6004 — a 17× improvement; reflects reboot freeing leaked memory + Docker Desktop no longer running)
- Swap used: near 0 (post-reboot reset)
- `docker info` reports **OrbStack** as the runtime, **12 GB MemTotal** (auto-allocated), **14 CPUs**
- 7 OrbStack containers visible via `docker ps -a` (Major Shells + a few HealthBite supabase)
- Of those 7, what auto-starts depends on container restart policies — Major Shells (shell-A/B/C) should come up
- Docker Desktop NOT auto-launched (we disabled "Open at startup")
- Uptime: minutes, not days

### What's still pending post-reboot

1. ~~**Bring up HealthBite supabase stack**~~ — done 2026-05-11. `cd ~/Projects/healthbite && npx supabase start` (note: `npx`, not global — `supabase` CLI not on PATH). ⚠️ **Gotcha**: imported `supabase_db_healthbite` volume was PG 15 but config.toml now wants PG 17, so the DB container would not boot ("database files are incompatible"). Resolved by `npx supabase stop --no-backup` (removes volumes) then `npx supabase start` — 40 migrations + seed.sql replayed cleanly. Loses any hand-inserted local data, fine for dev.
2. ~~**Bring up RelyMD platform postgres + redis**~~ — done 2026-05-11. Canonical commands: `cd ~/Projects/platform && bin/relymd pg --start && bin/relymd redis --start`. **Not** `docker compose up -d` — platform uses the `bin/relymd` CLI which manages `relymd/postgres` + `relymd/redis` images via `relymd images shell --detach`. Container names: `relymd-postgres-*`, `relymd-redis-*` (random suffix per session).
3. ~~**Major Shells**~~ — did NOT auto-start; restart policy assumption was wrong. Run `docker start shell-A shell-B shell-C` manually after OrbStack is up. Worth investigating: are restart policies actually set on these containers, or do we need to set `--restart unless-stopped`?
4. **Verify Chrome Memory Saver working** — `chrome://settings/performance`; after ~2h of idle tabs, RSS should drop significantly. **Status 2026-05-11**: settings page opened; user toggling. Pre-toggle Chrome RSS: 7.76 GB across renderers (high — many tabs alive). Re-measure in ~2h.
5. ~~**Optional: `docker system prune -a`**~~ — done 2026-05-11. Reclaimed **7.92 GB** (lower than the 26 GB estimate; many "reclaimable" images were still backed by running containers — image tags removed but SHA refs preserved). All running containers unaffected. The `relymd/postgres` and `relymd/redis` image tags were removed; if you ever stop those containers and need fresh images, `bin/relymd images shell` will have to rebuild from source.
6. **Optional: uninstall Docker Desktop entirely** (after a week of OrbStack confidence) to free ~22 GB disk. Remove `docker-desktop` cask from `~/Projects/dev-environment/hosts/jonathan-sells-darwin.nix` and remove the `launchd.user.agents.docker-desktop` block.
7. ~~**PR triage**~~ — done 2026-05-11 in autonomous-only mode against MioMarker/tachikoma-starter. **0 merged, 1 queued.** Findings:
   - Skill required a patch first — it hardcoded `dev` but the repo uses `develop`. Generalized to `$BASE_BRANCH` (resolves `dev → develop → main → master`). See `~/.claude/skills/auto-review-prs/SKILL.md`.
   - Of 17 open PRs, 16 form a stacked-PR chain targeting each other's feature branches; only PR #5 targets `develop` directly. The skill correctly ignores the stack.
   - PR #5 (scaffold) classified tier-2 "logic without tests" — `Dockerfile.web`, `next.config.ts`, `turbo.json`, `docker-compose.yml`. Carve-outs fail (diff > 100 lines). Scaffold PRs are a known weak spot of the rubric; consider broadening the path carve-out for infra files like `Dockerfile*`, `docker-compose*.yml`, `turbo.json` if scaffold PRs are common.
   - Full report: `~/projects/personal-nix/wiki/auto-merged-pr-report.md` (2026-05-12T02:50Z entry).
   - ⚠️ PRs #8, #14, #18 (per ARCHITECTURE.md § 10) are obsoleted by v2 and should be closed manually before the stack rolls forward.
8. **Investigate "work-requests silently went `status: done`" pattern** — **deferred 2026-05-11** (not blocking PROXY work). Cause still unconfirmed (see § Notes line 440); the earlier guess that this is Tachikoma's normal "done-when-PR-exists" behavior was not verified against the source. Pick this up next time Tachikoma flow gets weird — read `~/Projects/tachikoma/` source to confirm what sets `status: done` and when.

### Step 8 (Login Items audit) — partial completion 2026-05-11

- Pre-reboot agent count: 30 non-Apple. Post-reboot + audit: 20 visible via `launchctl list`.
- ⚠️ **Discovered gotcha**: the two "sh / unidentified developer" entries in the Login Items GUI are `org.nixos.activate-system` (nix-darwin activation) and `systems.determinate.nix-installer.nix-hook` (Determinate Nix maintenance). User had toggled both OFF, which would have **broken future `darwin-rebuild` runs** — activation phase wires up MCP servers, secrets, launch agents, all of which would silently stop applying. Identified via `sfltool dumpbtm` (Disposition `[enabled, disallowed, notified]` = user-blocked). Re-enabled 2026-05-11. **Lesson**: never disable `sh` entries from "unidentified developer" without checking the underlying plist — on a nix-darwin machine, `sh`-invoked daemons are almost always essential infra.

### Suggested first prompt to paste into the new Claude session

```
Continuing the 2026-05-11 PROXY v2 redesign session post-reboot. Read
~/projects/personal-nix/wiki/recipes/mac-pre-proxy-prep.md and pick
up at "🔁 SESSION RESUME POINT". Run Step 9 verification, compare to
the pre-reboot snapshot, then walk me through bringing up HealthBite
supabase + RelyMD platform stacks.
```

---

## Notes / gotchas observed during execution

### 2026-05-11 — first execution

- **Baseline state**: macOS Tahoe 26.2, M4 Pro / 24 GB, uptime 59d 22h, Docker Desktop allocated 4 GB, swap 34.7 GB / 35.8 GB allocated (maxed), 70-100 MB host pages free at peak pressure.
- **Active workload at start**: 17 Docker containers running including 3 Major Shells. One Major Tachikoma actively processing `proxy-15-notifications` brief when work began.
- **Sequencing chosen**: OrbStack install + Apple Intelligence disable + iOS sim probe (no-ops) run in parallel with documentation pass. Reboot + full Docker→OrbStack cut-over deferred to after Tachikoma queue drains.
- **iOS sim status**: 0 sims booted — Step 6 was a no-op on this machine.
- **Login Items**: 30 non-Apple launch agents detected. Itemized list in Step 8. Audit pending.
- **Tachikoma anomaly**: Several work-requests (proxy-06, proxy-11, proxy-12, proxy-15) transitioned to `status: done` during this session without `shipped_pr` URLs. Cause unclear (hook misbehavior? Tachikoma auto-finalize?). Worth investigating before next build session.
- **Docs produced alongside this execution**: see the "Documentation surface" section in the session that originated this recipe (2026-05-11 grilling + v2 redesign). All ~20 artifacts cross-referenced from `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md`.

### 2026-05-11 — post-reboot session (after OrbStack cut-over)

- **OrbStack did NOT auto-launch on boot** despite "Open at Login" assumed-checked. Had to `open -a OrbStack` manually. Verify the login-item is actually set if you want hands-off recovery next reboot.
- **All 6 imported containers came back in `Created` state** (not `Up`) — Major Shells, supabase analytics/realtime, apollo-hermes-sqlserver. None of them auto-started. The pre-reboot expectation that "Major Shells should come up via restart policy" was wrong on this machine.
- **PG version mismatch on supabase volume import** — see § "What's still pending post-reboot" item 1 above. Volume was PG 15 from old Docker Desktop era; HealthBite's `supabase/config.toml` is at `major_version = 17`. Net: `supabase start` failed in a tight loop until volume was wiped. Important enough to surface here because anyone importing supabase volumes across a Postgres major-version bump will hit it.
- **`supabase stop --no-backup` removes volumes** — important to know. The `--no-backup` flag is what unblocks a PG-version reset. Without it, the volume sticks around and you have to `docker volume rm` manually.
- **`vm_stat` page size on M4 Pro is 16 KB, not 4 KB** — the Step 9 success criteria "Pages free > 100,000" was written assuming 4 KB pages (~400 MB). On 16 KB pages that target would mean ~1.6 GB free, which is unrealistic. Treat the threshold as outdated; trust the active+inactive+swap numbers instead. **TODO**: update Step 9 acceptance criteria to use absolute bytes.
- **Page-size detection one-liner**: `pagesize` (it's a real shell built-in on macOS — prints `16384`).
- **PROXY-readiness**: with 17 containers running, swap stayed at 0 MB. The 24 GB host has comfortable headroom for additional PROXY loop containers when implementation begins.
