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
- [ ] Full cut-over (import from Docker Desktop, quit Docker Desktop, uncheck "Open at Login") — **pending** (waiting on Tachikoma to drain queue + reboot)
- [ ] Record host RSS reduction observed after cut-over + reboot:    `___________`

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

- [ ] Done — paste full post-fix snapshot here:

```
___________
```

---

## Step 10 — Capture session

When all above ticked, record summary at the bottom of this file (date, total reclaimed RAM, total reclaimed disk, total runtime). Then [PROXY ARCHITECTURE](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) implementation can begin.

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
