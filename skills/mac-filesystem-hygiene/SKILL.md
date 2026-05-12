---
name: mac-filesystem-hygiene
description: Opinionated filesystem hygiene and organization for Pioneer18's PROXY-native Mac (Apple Silicon, OrbStack, Nix-via-personal-nix, Cargo workspaces). Covers the 4-tier state model (where files live), home-directory layout, Downloads/Desktop policy, OrbStack VM hygiene under the 12.6 GB ceiling, Cargo/Docker/RN/Xcode artifact pruning, version-control gitignore patterns, backups adapted to the 4-tier model, disk-space triage under memory pressure, and a maintenance cadence (weekly/monthly/quarterly/annual). Use when the user asks "where should this live", "my disk is full", "what's safe to delete", "clean up X", "I'm running out of space", asks about iCloud, Time Machine, OrbStack disk, Cargo `target/`, `node_modules`, Xcode DerivedData, `~/Library/`, LaunchAgents, or any filesystem-organization or cleanup question. Also use when planning where to put a new file, repo, or backup.
---

# Mac Filesystem Hygiene (PROXY edition)

## TL;DR — the 4-tier mental model

Every file answers to one tier. "Where should this go?" reduces to "what tier is this?"

| Tier | What | Where | Recovery |
|---|---|---|---|
| **0** Team substrate (public) | Platform code, generic skills | `~/Projects/tachikoma-starter/` | `git clone` public remote |
| **1** Personal config + work (private) | Skills, MCPs, wiki, work-requests, dotfiles, repos | `~/projects/personal-nix/`, `~/Projects/*` | `git clone` private + `dev` |
| **2** Apple-synced | Memory, Keychain secrets, Shortcuts | iCloud Drive + Keychain | Apple ID login |
| **3** Per-machine ephemeral | Chat history, Postgres queue, sensor samples, build artifacts | Local | Cannot recover — rebuild |

**Promotions go up only.** Tier 3 → Tier 1 = `git add` it. Tier 1 → Tier 2 = needs cross-device. Tier 1 → Tier 3 almost never makes sense.

## Routing — which REFERENCE.md section answers what

| User says... | Read REFERENCE.md § |
|---|---|
| "where should this file/repo go?" | 0 (tier model), 2 (home layout), 5 (project organization) |
| "my disk is full" / "running out of space" | 17 (disk triage), 11 (artifact hygiene), 10 (OrbStack) |
| "what's safe to delete?" | 11 (Cargo/Docker/RN/Xcode), 21 (command index) |
| "clean up Downloads / Desktop" | 3 (Downloads), 4 (Desktop) |
| "clean up Docker / OrbStack" | 10 (OrbStack), 11 (Docker section) |
| "back up X" / "what about Time Machine?" | 16 (backups), 10 (Postgres pg_dump) |
| "iCloud — should I sync this?" | 7 (iCloud scope) |
| Anything `~/Library/*` | 9 (Library tour), 13 (Nix symlinks) |
| ".gitignore for X" | 12 (version control) |
| "what should I prune weekly/monthly?" | 18 (maintenance cadence) |
| "is this a bad idea?" | 20 (anti-patterns) — check first |

Full content: [REFERENCE.md](REFERENCE.md).

## Hard rules (cite from REFERENCE.md § 20 when relevant)

1. **Never put `tachikoma-starter` or `personal-nix` in iCloud.** They go to git remotes.
2. **Never `docker system prune --volumes` without verifying Postgres is backed up first** (pg_dump → personal-nix/backups, see § 10).
3. **Never edit Nix-managed files in `~/.config/` directly** — they're symlinks to the read-only store. Edit source in personal-nix, run `dev`.
4. **Never add LaunchAgents directly to `~/Library/LaunchAgents/`** — should be Nix-managed. Manual plists are config that escaped the flake.
5. **Never back up Postgres via Time Machine of the OrbStack VM.** Use `pg_dump`. Raw volume copy of a running DB = corruption.
6. **Keep ≥ 15% SSD free.** Free disk is swap headroom; tight disk + memory pressure → Jetsam (the May 10/11 incident).
7. **Always `du -sh` before `rm -rf`.** Always.

## Investigation flow (when disk is tight)

```bash
df -h /                                          # confirm
du -sh ~/* | sort -h | tail                      # localize at home
du -sh ~/Library/* | sort -h | tail              # if Library is the culprit
ncdu ~                                            # interactive drill-down
```

Likely culprits in order: Cargo `target/` dirs → OrbStack VM (`~/.orbstack/`) → `~/.cargo/registry/` → `node_modules` → APFS snapshots → Xcode DerivedData → `~/Library/Caches/`.

## High-value one-liners (full set in REFERENCE.md § 21)

```bash
# Cargo: nuke all target/ dirs under ~/Projects (audit first)
find ~/Projects -type d -name target -prune -exec du -sh {} +
find ~/Projects -type d -name target -prune -exec rm -rf {} +
cargo cache --autoclean

# OrbStack: prune without volumes (safe; preserves Postgres)
docker system prune -a
docker builder prune -a
orb stop && orb start                            # forces VM disk compaction

# Downloads triage
find ~/Downloads -type f -mtime +30 -delete && find ~/Downloads -type d -empty -delete

# APFS snapshots
tmutil listlocalsnapshots /
tmutil thinlocalsnapshots / 999999999999 4

# Postgres backup (Tier 3 → Tier 1 promotion)
pg_dump -h localhost -p <port> -U proxy proxy_db \
  > ~/projects/personal-nix/backups/proxy-db-$(date -u +%Y-%m-%d).sql
```

## Posture

When the user reports a filesystem problem: investigate first (`df`, `du`, `ncdu`), name the tier of what you're proposing to touch, and confirm before any destructive action. Free disk and memory pressure are the same problem class — treat both as reasons to refuse new loops and recommend the same remediations.

**Governing principle:** *In a memory-pressured agentic environment, filesystem decisions are memory decisions. Disk space is swap headroom; cache size is page-cache pressure; ephemeral container hygiene is admission-gate efficacy.*
