# Mac Filesystem Hygiene & Organization Guide — PROXY Edition (v2)

**Audience:** Pioneer18 / Jonathan, running PROXY as the boot surface on an Apple Silicon MacBook (Tahoe 26+).

**What this is:** Opinionated reference for filesystem hygiene in a PROXY-native environment. Designed as a knowledge base for a Claude skill that runs *inside* PROXY's chat pane — when Claude is asked "where should this live," "my disk is full," "what's safe to delete," or "clean up X," this is what it consults.

**What changed from v1:** v1 was generic-developer-Mac advice. v2 is rebuilt around PROXY's 4-tier state model, OrbStack instead of Docker Desktop, Nix-via-personal-nix instead of chezmoi, Cargo-workspace artifact reality, and the memory-pressure-is-a-first-class-concern framing born from the 2026-05-10/11 Jetsam incident.

**Governing principle (unchanged):** *The filesystem is durable infrastructure. The cost of disorganization compounds; the cost of organization is paid up front.*

**Governing principle (PROXY-specific):** *In a memory-pressured agentic environment, filesystem decisions are memory decisions. Free disk space is swap headroom; cache size is page-cache pressure; ephemeral container hygiene is admission-gate efficacy. Treat them as one system, not two.*

---

## 0. The 4-tier state model as filesystem ontology

Before any specific directory, the mental model. PROXY's 4-tier model is not just a sync strategy — it's the *primary* taxonomy for every file decision. "Where does this go?" reduces to "what tier is this?"

| Tier | What | Sync mechanism | Disk location | Recovery model |
|---|---|---|---|---|
| **0** — Team substrate (public) | Platform code, generic skills, voice daemon, shared tooling | Git (public remote) | `~/code/tachikoma-starter/` (or equivalent checkout) | `git clone` from public remote |
| **1** — Personal config + work (private, git-synced) | User skills, MCPs, wiki, work-requests, dotfiles, Nix flake | Git (private remote) | `~/code/personal-nix/` (or wherever the Nix flake lives) | `git clone` from private remote + `nix run` |
| **2** — Synced via Apple (iCloud + Keychain) | Memory exports, secrets, Shortcuts, anything Apple-native | iCloud Drive, Keychain | `~/Library/Mobile Documents/...`, Keychain | Login to Apple ID |
| **3** — Per-machine ephemeral | Chat history, queue runtime, sensor samples, build caches, ephemeral containers | None (local-only) | Local Postgres in OrbStack VM, `target/`, etc. | Cannot recover — rebuild or accept loss |

### The rules that fall out of this

**Rule 0a:** Every file you create answers to one tier. If you can't say which, it's Tier 3 by default (ephemeral, no backup). Better to acknowledge that than to pretend it's tier-mapped when it isn't.

**Rule 0b:** Tier 0 and Tier 1 are *the* sources of truth. A fresh Mac is `git clone tachikoma-starter && git clone personal-nix && nix run`. Nothing important should be unrecoverable from those two repos plus Apple sync.

**Rule 0c:** Tier 2 (iCloud) has a *narrow* legitimate scope. Use it for what it's good at — small files, cross-device availability, Apple-ecosystem state. Do not expand it to general document sync. Never put code in it.

**Rule 0d:** Tier 3 is acceptable but must be *named*. Chat history, queue state, sensor samples — these are knowingly per-machine. The error is *accidental* Tier 3 — files you thought were backed up but aren't.

**Rule 0e:** When in doubt, promote a file's tier. Tier 3 → Tier 1 means "I git-add this." Tier 1 → Tier 2 means "this needs cross-device access." Movements down (Tier 1 → Tier 3) almost never make sense.

---

## 1. Mental model: macOS layout under PROXY

In a normal Mac workflow, the filesystem is mostly invisible; Finder is the interface. In a PROXY workflow, the filesystem *is* the interface — every interaction with state happens through paths, daemons, and tmux panes. This changes what hygiene means.

**The boot surface is fullscreen Ghostty + tmux.** Finder, Desktop, Dock — all of these exist but you barely see them. The implications:

1. The Desktop is not a workspace. It is an artifact of macOS architecture that you rarely visit. Files on it serve no purpose.
2. Downloads is still a real inbox (browsers and AirDrop dump there) but triage happens via CLI, not Finder.
3. Spotlight matters less than `fd` / `rg` because you're already in a terminal.
4. `~/Library` invisibility is irrelevant; you'll `cd` there when you need to.

**APFS substrate** (same as v1, repeated because it's load-bearing):
- **Snapshots** — Time Machine uses these; `tmutil listlocalsnapshots /` lists them. They occupy "used" space until thinned.
- **Clones** — `cp -c` is instant + zero-space; useful when you want to snapshot a workspace before destructive ops.
- **Space sharing** — multiple volumes in one container share free space. Your boot volume and any data volumes draw from one pool.
- **Encryption** — FileVault is APFS-level, no perceptible overhead on M-series.

**SIP-protected domains** — `/System`, much of `/usr`. Never write. Even `sudo` won't let you on Apple Silicon without disabling SIP, which you should not do.

**Local domain** — `/Applications` (drag-installed apps), `/Library` (system-wide config), `/opt/homebrew` (Homebrew root). Writable with admin, but mostly managed by installers and Nix.

**User domain** — `~`. Where PROXY lives. Where 95% of decisions matter.

**Special paths to know:**
- `/Volumes` — every mount point. External drives, DMGs, network shares.
- `~/.orbstack/` — OrbStack VM data, including the Docker engine state and all volumes.
- `~/Library/Application Support/` and `~/.config/` — application state split between Apple-style and XDG-style locations.

---

## 2. The home directory (`~`) — PROXY layout

Apple's home-folder defaults (`~/Documents`, `~/Desktop`, etc.) still exist but are largely unused. The actual PROXY home directory has a different shape.

### Recommended top-level layout

```
~/code/                          — all source-controlled work (Tier 0 + Tier 1 + downstream)
├── tachikoma-starter/           — Tier 0: team substrate
├── personal-nix/                — Tier 1: personal config + work
├── proxy/                       — Tier 0 or 1: PROXY itself (Cargo workspace)
├── work/                        — RelyMD / employer repos
│   ├── relymd-insight/
│   ├── relymd-platform/
│   └── ...
├── personal/                    — your own projects
│   ├── healthbite/
│   └── ...
├── oss/                         — contributions to others' projects
├── scratch/                     — Tier 3: throwaway by policy
└── archive/                     — completed work, retained for reference

~/.config/                       — XDG-style config (Nix manages most of this)
~/.orbstack/                     — OrbStack VM + Docker engine state
~/.cargo/                        — Cargo registry, git cache, binaries
~/Library/                       — macOS-mandated app state (mostly Nix-untouchable)
~/Downloads/                     — browser/AirDrop inbox, triage weekly
~/Documents/, ~/Desktop/         — vestigial; aspire to empty
```

### Why this shape

- **`~/code/` at the home root, not inside `~/Documents/`** — iCloud-immune even if Documents sync is on. PROXY's tachikoma-starter and personal-nix repos must be safe from iCloud's "Optimize Mac Storage" file eviction.
- **`tachikoma-starter` and `personal-nix` live next to other repos** — they are repos. Treating them as special and stashing them in `~/.config/` or `~/Library/` would hide them from `fd`, `rg`, and your existing repo workflows.
- **`scratch/` is sacred (Tier 3 by policy)** — anything you'd otherwise create on Desktop or in `/tmp/` goes here. Promotion is the explicit act of `mv scratch/idea code/personal/idea && cd code/personal/idea && git init`.

### The Apple folders, deprecated

| Folder | Real role under PROXY |
|---|---|
| `~/Desktop` | Vestigial. Cmd+Shift+. visible but never used. Aspire to zero items. |
| `~/Documents` | Vestigial. Don't put real work here; iCloud sync risk. |
| `~/Movies`, `~/Music`, `~/Pictures` | Used by Photos, Music apps. Leave them; don't put work there. |
| `~/Public` | Unused. |
| `~/Applications` | Optional per-user apps. Usually empty under Nix-managed setups. |

---

## 3. The Downloads inbox

Still real — browsers and AirDrop dump here, and there's no escaping that. But triage is CLI-driven, not Finder-driven, in a PROXY workflow.

**The contract:** Downloads is an inbox, not a destination. Two acceptable states: "empty" or "things from the last few days awaiting triage."

**Automated triage** (works well as a proxy-daemon Skill, or as a launchd job):

```bash
# Delete files older than 30 days
find ~/Downloads -type f -mtime +30 -delete
# Remove empty directories left behind
find ~/Downloads -type d -empty -delete
```

As a Skill, the daemon can run this on a schedule and surface a notification: "Cleaned 3.2 GB from Downloads, 47 files older than 30 days."

**Manual triage** at the chat pane:

```bash
ls -lt ~/Downloads | head -30          # most recent first
du -sh ~/Downloads/* | sort -h | tail  # biggest items
```

**What never goes to Downloads as a destination:**
- Code you'll edit (clone to `~/code/scratch/` first).
- Long-term reference docs (move to `~/code/personal-nix/wiki/` or appropriate Tier 1 location).
- Anything you intend to keep beyond this week.

---

## 4. Desktop

In PROXY, the Desktop is invisible 99% of the time — it sits behind fullscreen Ghostty. It serves no daily purpose. Keep it empty. The only reason to ever touch it is to satisfy an app that dumps a file there by default (some screenshot configs, drag-out exports from certain GUI apps); in those cases, move the file immediately to its real home.

If you must change Desktop behavior:
```bash
# Screenshots: move default location away from Desktop
defaults write com.apple.screencapture location ~/Pictures/Screenshots
killall SystemUIServer
```

This is one of the few `defaults write` tweaks worth doing on a PROXY machine — Desktop pollution from `Shift+Cmd+4` is the most common case of accidental Desktop accumulation.

---

## 5. Project and code organization

### The `~/code/` structure

Already shown above. Repeated here with the rationale:

- **One level of categorical grouping** (work / personal / oss / scratch / archive). Not two. Deeper nesting is friction every time you `cd`.
- **`tachikoma-starter`, `personal-nix`, `proxy` at top level** — these are foundational, not sub-categorized. Treat them as siblings of work/personal/oss, not as children of any of them.
- **Repo names lowercase-hyphenated**, matching their remote names.
- **No language-based grouping** — language is a property of a project, not an organizational axis.

### PROXY repo specifics

The PROXY repo is a Cargo workspace monorepo. Its on-disk shape will look roughly like:

```
~/code/proxy/
├── Cargo.toml                   — workspace root
├── Cargo.lock                   — workspace lockfile
├── crates/
│   ├── proxy-daemon/
│   ├── proxy-voice/
│   ├── proxy-cli/
│   └── ...
├── notify-app/                  — signed Swift notification app
├── ui/                          — Next.js dashboard
├── tui/                         — Ink TUI
├── migrations/                  — sqlx migrations
├── docker/                      — Dockerfiles for loop containers
├── target/                      — Cargo build output (gitignored, can be 5-20 GB)
└── ...
```

The `target/` directory at workspace root is the single biggest local artifact. Cargo workspaces share one `target/` across all crates, which is good — but it grows fast under heavy iteration. See Section 11 for management.

### The Tachikoma loop workspace pattern

When proxy-daemon admits a loop, it spawns an ephemeral Docker container that mounts a target repo. The mount strategy matters for filesystem hygiene:

- **Read-write bind mount of the target repo** — the container can write to your local repo. Loops commit to a branch and push; the host never sees uncommitted churn.
- **Container-internal scratch space is ephemeral** — anything written outside the mounted repo dies with the container. Loops should never write important state outside the repo.
- **Output that needs to survive the loop** goes through the Postgres queue (loop result row) or is committed to the repo, not written to host filesystem out-of-band.

This means: **the only filesystem footprint a loop leaves on the host is the commits it makes to your repo branch.** No log files outside the repo, no scratch directories, no temp files in `/tmp/`. If a loop appears to be leaving cruft on the host, something is wrong with how it's containerized.

---

## 6. Naming conventions

Same as v1, repeated for completeness:

- **Files and directories: lowercase-hyphenated.** `my-thing/`, not `MyThing/` or `my_thing/`.
- **Dates: ISO 8601 (`YYYY-MM-DD`).** Always. Sorts lexically, internationally unambiguous, machine-parseable.
- **No version suffixes (`-v2`, `-final`, `-FINAL`).** Use git for code; use dated filenames for one-off exports.
- **No spaces** in anything a CLI tool will touch. The PROXY surface is CLI-driven, so this is effectively "no spaces in anything."
- **Personal notes:** `YYYY-MM-DD-topic.md` — `2026-05-12-vera-deeplink-error.md`. Date-prefixed makes ls-by-default-chronological useful.

---

## 7. iCloud Drive — Tier 2's legitimate scope

iCloud is part of PROXY's architecture. The Tier 2 use is real. Don't fight it; constrain it.

**What goes in iCloud (Tier 2):**
- Memory exports (per PROXY's memory architecture).
- Shortcuts (Apple's sync is the only mechanism).
- Small reference docs you genuinely want on iPhone/iPad.
- Notes, Reminders (these are app-specific iCloud, fine).

**What never goes in iCloud:**
- Code. Any repo. Including `tachikoma-starter` and `personal-nix` — they go to git remotes, not iCloud.
- `node_modules`, `target/`, any build artifact.
- Large media (use a media-specific solution; iCloud Photos is fine, iCloud Drive for video files is not).
- Anything frequently modified by tools (sync conflicts inside repos are a real failure mode).

**The "Desktop & Documents" sync feature: stays off.** If you ever turn it on, your `~/Documents/` and `~/Desktop/` move into iCloud. File eviction breaks any tool that expects local files. For a PROXY user this is pure downside — code is in `~/code/` (immune), and the rest is small enough that the convenience isn't worth the risk.

**Keychain (also Tier 2):** for secrets. Use `security` CLI to script access. Never check secrets into Tier 0 or Tier 1 repos.

---

## 8. Dotfiles and config — managed by Nix via personal-nix

Nix supersedes the dotfile-manager category entirely. chezmoi, stow, yadm, bare-git-repo — all of them are solving a smaller version of what Nix solves.

### What Nix gives you that chezmoi doesn't

- **System-wide configuration** (LaunchAgents, system fonts, login items) via `nix-darwin`.
- **Package management** integrated with config (declaring `pkgs.ripgrep` installs it).
- **Reproducible builds** — a Nix flake with a lock file produces bit-identical configs across machines.
- **Per-host configuration** via flake outputs without templating hacks.
- **Atomic upgrades and rollbacks** — every config change is a generation you can revert to.

### personal-nix repo conventions

The personal-nix repo is Tier 1. It contains:

```
personal-nix/
├── flake.nix                    — entry point
├── flake.lock                   — locked input versions
├── hosts/                       — per-host configs
│   ├── work-mbp/
│   └── ...
├── home/                        — home-manager modules
│   ├── shell.nix                — zsh, starship, etc.
│   ├── git.nix                  — gitconfig + global gitignore
│   ├── editors.nix              — neovim, etc.
│   └── ...
├── modules/                     — reusable nix modules
├── skills/                      — user skills (Tier 1 content)
├── mcps/                        — MCP server configs
├── wiki/                        — personal knowledge base
└── work-requests/               — work intake artifacts
```

### What goes in personal-nix vs tachikoma-starter

- **personal-nix (Tier 1):** anything specific to you — your aliases, your git identity, your wiki, your work-requests, your custom skills. Private remote.
- **tachikoma-starter (Tier 0):** the substrate everyone using the system gets — platform code, generic skills, the voice daemon. Public remote.

If a skill is useful to others, it lives in tachikoma-starter. If it's about your specific projects (RelyMD, healthbite), it lives in personal-nix.

### Secrets in dotfiles

Never in plaintext, never in the Nix store. Options:

- **sops-nix** — secrets encrypted in the repo, decrypted at build time using a key from `~/.config/sops/age/keys.txt`.
- **agenix** — similar, age-based.
- **Keychain** — for runtime-only secrets (API keys used by daemons). Nix can configure tools to read from Keychain.

The Keychain key for sops/age itself is Tier 2 (synced via iCloud Keychain, or recovered via `security` CLI export to a Yubikey).

### The Apple `~/Library/` directories under Nix

Nix-darwin can manage some `~/Library/` content (LaunchAgents in particular), but many Apple-managed directories (`~/Library/Application Support/`, `~/Library/Containers/`) are owned by the apps themselves. Don't try to put those under Nix — let apps own them.

---

## 9. `~/Library` — the PROXY-relevant tour

Hidden by default. `Cmd+Shift+.` in Finder; just `cd` in terminal.

| Path | What's there | PROXY-specific note |
|---|---|---|
| `Application Support/` | Per-app state (Slack, Signal, Discord, Ghostty, etc.) | Ghostty config is here unless Nix-managed |
| `Caches/` | Regenerable caches | Audit quarterly; safe to delete contents per-app |
| `Containers/` | Sandboxed app data (Mac App Store apps) | Don't touch directly |
| `Group Containers/` | Shared sandboxed data | Don't touch |
| `Preferences/` | `.plist` config files | Some are Nix-managed; rest leave alone |
| **`LaunchAgents/`** | **User-level background processes** | **proxy-daemon and proxy-voice live here. Audit before adding anything else.** |
| `Logs/` | App and system logs | Console.app reads these; auto-rotated |
| `Mobile Documents/` | iCloud Drive storage backend | Tier 2 lives here under the hood |
| `Developer/` | Xcode, simulators, DerivedData | The biggest dev space hog if you do iOS work |

### LaunchAgents under PROXY

`~/Library/LaunchAgents/` should contain *very few* entries on a PROXY machine. Specifically:

- `com.pioneer18.proxy-daemon.plist` (or similar) — proxy-daemon
- `com.pioneer18.proxy-voice.plist` — proxy-voice
- The Ghostty + tmux boot LaunchAgent
- Apple-managed entries (com.apple.*)

That's it. Anything else is an artifact of an app you may have uninstalled. Audit:

```bash
ls -la ~/Library/LaunchAgents/
launchctl list | grep -v com.apple
```

For each unfamiliar entry: identify the source, decide if you still want it, `launchctl unload` and remove the plist if not.

### Ghostty specifically

Ghostty config: `~/.config/ghostty/config` (XDG-style, ideal for Nix management).
Ghostty state: `~/Library/Application Support/com.mitchellh.ghostty/` (don't touch; managed by Ghostty).

If Nix manages Ghostty config (recommended), the `~/.config/ghostty/config` is a symlink to the Nix store. Editing it directly will be overwritten on next `nix run`; edit the source in personal-nix instead.

---

## 10. OrbStack — the loop substrate

You use **OrbStack**, not Docker Desktop. Behavior differs in ways that matter for hygiene.

### OrbStack vs. Docker Desktop on-disk

| Aspect | Docker Desktop | OrbStack |
|---|---|---|
| VM disk image | `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` | `~/.orbstack/data/` |
| Disk growth | Monotonic, never shrinks without manual reset | Trims automatically; uses thin provisioning |
| VM ceiling | User-configured, often 64+ GB | **12.6 GB ceiling in your config** |
| File-sharing | gRPC FUSE (slow) | Native filesystem proxy (fast) |
| Resource usage | 1-3 GB resident always | ~200 MB resident when idle |

### What OrbStack's 12.6 GB ceiling means for hygiene

This is a hard constraint, not a recommendation. Everything inside the VM — Docker images, containers, volumes (including Postgres data), ephemeral loop containers — competes for 12.6 GB.

**Implications:**
- Postgres volume size matters. It's the most important persistent thing in the VM.
- Old loop container images accumulate fast. Prune aggressively.
- A bloated VM doesn't fail gracefully — it hits the ceiling and refuses to admit new containers, which means PROXY's admission gate rejects loops even when host memory is fine.

### OrbStack hygiene commands

```bash
# Check VM disk usage
orb info
docker system df

# Prune everything not actively used
docker system prune -a --volumes
# Read carefully before running with --volumes — that deletes named volumes too.
# Use without --volumes if you have data you care about in named volumes (e.g., Postgres).

# Prune just stopped containers + dangling images
docker container prune
docker image prune

# Prune build cache (BuildKit)
docker builder prune -a

# Force OrbStack to compact its disk image
orb stop
orb start
# (Compaction happens automatically on stop/start cycles.)
```

### Postgres volume specifically

PROXY's Postgres lives in a Docker volume in the OrbStack VM. This is **Tier 3** by default — chat history, queue state, sensor samples. Some of it is genuinely ephemeral (sensor samples); some you might want to preserve across machines (chat history, in the limit).

Volume location inside the OrbStack VM:
```bash
docker volume ls
docker volume inspect <proxy-postgres-volume-name>
```

Backup strategy:
```bash
# pg_dump from host, point at OrbStack-exposed port
pg_dump -h localhost -p <port> -U proxy proxy_db > ~/code/personal-nix/backups/proxy-db-$(date -u +%Y-%m-%d).sql
```

This makes the Postgres backup Tier 1 (commits to personal-nix backups directory, syncs to private git remote). Treat it as you would a code change: periodic, intentional.

**Anti-pattern:** trying to back up the raw Docker volume contents. Postgres volumes shouldn't be copied while running, and the file format is internal. Always go through `pg_dump`.

---

## 11. Developer artifact hygiene — Cargo / OrbStack / RN / Xcode

PROXY's dev workload is dominated by:
1. Rust (PROXY itself, Cargo workspace).
2. Docker images (loop containers, in the OrbStack VM).
3. React Native / Expo (RelyMD Insight, healthbite — Tier 1+ work projects).
4. Occasional Xcode work.

Each has distinct space behaviors.

### Cargo — the biggest local space sink

**Two locations matter:**

```
~/.cargo/registry/              — downloaded source crates, can be 5-15 GB
~/.cargo/git/                   — git-fetched dependencies
<project>/target/               — build artifacts per workspace, 1-15 GB each
```

`target/` directories are the worst offenders. A PROXY workspace `target/` after a few weeks of active dev can be 10+ GB. Multiply across other Rust projects and you can lose 30-50 GB to Cargo without noticing.

**Pruning:**

```bash
# Per-project: clean target/
cd ~/code/proxy
cargo clean

# Across all Rust projects under ~/code/
find ~/code -type d -name target -prune | xargs -I {} du -sh {}
# Review the list, then:
find ~/code -type d -name target -prune -exec rm -rf {} +

# Global Cargo cache cleanup (cargo doesn't auto-prune)
cargo install cargo-cache
cargo cache --autoclean        # removes old versions, keeps recent
cargo cache --autoclean-expensive   # more aggressive
```

**`sccache` is worth installing** for a heavy Rust workflow — caches compilation across projects. `brew install sccache`, set `RUSTC_WRAPPER=sccache` in your shell env (or Nix-managed).

### Docker images — in the OrbStack VM

Covered in Section 10. The 12.6 GB ceiling forces discipline here that you wouldn't otherwise have.

**Image hygiene specifically:**
```bash
# See what's taking space
docker system df -v

# Remove images not used by any container
docker image prune -a

# Remove all unused images, containers, networks, build cache (NOT volumes)
docker system prune -a

# Loop-container-specific: prune after each loop run if the image isn't reused
# This is a proxy-daemon concern — the daemon should `docker rm` finished containers.
```

### React Native / Expo

Same as v1 but worth repeating because RelyMD Insight and healthbite are active:

```bash
# Per-project, in the project root:
rm -rf ios/build android/build android/.gradle ios/Pods node_modules

# Regenerate from app config
npx expo prebuild --clean

# Metro cache
rm -rf $TMPDIR/metro-*

# Watchman
watchman watch-del-all
```

For finding node_modules across ~/code:
```bash
find ~/code -type d -name node_modules -prune | xargs du -sh | sort -h
```

### Xcode

```bash
# DerivedData — safe to nuke, regenerates on build
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# Old simulator runtimes
xcrun simctl delete unavailable

# CocoaPods cache
pod cache clean --all
```

### The "what to prune when" decision tree

When disk fills:

1. `df -h /` to confirm
2. `du -sh ~/* | sort -h | tail` to localize
3. `du -sh ~/Library/* | sort -h | tail` if Library is the culprit
4. Likely culprits in order: `target/` directories, OrbStack VM, `~/.cargo/`, node_modules, DerivedData, simulator runtimes

**Always `du -sh` before `rm -rf`.** Always.

---

## 12. Version control hygiene

### Global gitignore (Nix-managed via personal-nix)

`~/.gitignore_global` should be a Nix-generated file. The contents:

```gitignore
# macOS
.DS_Store
.AppleDouble
.LSOverride
Icon
._*
.Spotlight-V100
.Trashes
.fseventsd

# Editors
.vscode/
.idea/
*.swp
*.swo
.cursor/

# Rust workspace artifacts (also belongs in per-repo .gitignore, but defense in depth)
target/

# Local env
.env.local
.envrc
.direnv/

# Per-repo scratch
/.scratch/
```

Set with: `git config --global core.excludesfile ~/.gitignore_global` (Nix-managed via home-manager `programs.git.ignores`).

### Per-repo `.gitignore`

Every repo needs one tuned to its stack. github.com/github/gitignore has canonical templates.

For Cargo workspaces:
```
target/
**/*.rs.bk
Cargo.lock           # debatable — keep for binaries, remove for libraries
```

For Expo / React Native:
```
node_modules/
.expo/
.expo-shared/
ios/Pods/
ios/build/
android/build/
android/.gradle/
android/app/build/
*.jks
*.p8
*.p12
*.key
*.mobileprovision
```

### What never goes in any repo

- **Secrets.** API keys, tokens, certificates, mobile provisioning profiles (unless encrypted via sops/agenix).
- **Large binaries** (>10 MB). Use Git LFS or out-of-band storage.
- **Generated files.** Build outputs, compiled assets.
- **OS/editor cruft.** Hence the global gitignore.

### If a secret leaks

1. **Rotate the secret first.** The history is the leak; rewriting won't unleak.
2. Then rewrite history (`git filter-repo` or BFG).
3. Force push, notify collaborators.
4. Audit logs for unauthorized use of the leaked credential.

---

## 13. Symlinks, aliases, hard links

Same as v1, with one PROXY-specific note: **Nix uses symlinks everywhere.** `~/.config/<tool>` entries are often symlinks into `/nix/store/...`. Don't edit through the symlink — edit the source in personal-nix and rebuild. Editing the store target is either denied (read-only store) or gets overwritten on next generation.

```bash
readlink ~/.config/ghostty/config
# → /nix/store/abc123-ghostty-config/config
# To edit: find this in personal-nix and rebuild
```

---

## 14. File metadata

Same as v1; nothing PROXY-specific changes here. Key points:
- `xattr -dr com.apple.quarantine /path/` strips Gatekeeper flags on downloaded binaries that won't run.
- `tag` CLI (`brew install tag`) for Finder tag management from the terminal.
- `mdls file` shows Spotlight metadata.

---

## 15. Search workflows

In a PROXY workflow, you're almost always at a CLI. The hierarchy:

- **`fd` for filenames** — `brew install fd`, respects `.gitignore`, fast.
- **`rg` for content** — `brew install ripgrep`, respects `.gitignore`, fast.
- **`mdfind` for system-wide metadata search** — when you don't know which project a file is in.
- **`find`** only when you need `-exec` for batch operations.

For PROXY specifically — Claude can run any of these in the chat pane. The Skill should prefer `fd` and `rg` over Spotlight because the user's mental model is repo-relative, not Mac-relative.

---

## 16. Backups — adapted to the 4-tier model

The 4-tier model already does much of what backups traditionally do. Time Machine is *additional defense*, not the primary recovery story.

### Tier-by-tier recovery story

| Tier | If your Mac dies tomorrow, you recover by... |
|---|---|
| **0** | `git clone tachikoma-starter` from the public remote |
| **1** | `git clone personal-nix` from the private remote, `nix run` |
| **2** | Log in to Apple ID, iCloud Drive + Keychain restore |
| **3** | Accept the loss; rebuild from current state |

**The implication:** Time Machine's job is to (a) protect Tier 3, and (b) provide a faster recovery path than the Tier 0/1/2 rebuild.

### Time Machine — what to back up

- **Yes:** `~/code/` (all of it; redundant for Tier 0/1 but cheap, and catches uncommitted in-progress work).
- **Yes:** `~/Library/` (selective — most app state, but exclude caches and dev artifacts).
- **No (exclude):** `~/.orbstack/` (Postgres backup via pg_dump separately; Docker images rebuild from registry).
- **No (exclude):** `target/` directories everywhere.
- **No (exclude):** `node_modules/` directories.
- **No (exclude):** `~/Library/Developer/Xcode/DerivedData/`.
- **No (exclude):** `~/Library/Caches/` (Time Machine excludes this by default).

Add exclusions:
```bash
sudo tmutil addexclusion -p ~/.orbstack
sudo tmutil addexclusion -p ~/Library/Developer/Xcode/DerivedData
# For each Rust project:
sudo tmutil addexclusion -p ~/code/proxy/target
sudo tmutil addexclusion -p ~/code/personal/healthbite/node_modules
# ... or scripted across all of ~/code
```

A proxy-daemon Skill can enforce this declaratively: walk `~/code/`, find every `target/` and `node_modules/`, ensure each is a Time Machine exclusion. Run weekly.

### Off-site backup

Time Machine alone fails to fire, drive, or theft. The off-site layer:

- **Backblaze Personal** ($9/mo) — set-and-forget, unlimited, the default.
- **Arq + B2/S3** — more control, encrypted client-side.
- **iCloud is not a backup** — it's sync. Deleting on one device deletes everywhere.

Backblaze can be configured to exclude the same patterns as Time Machine.

### Postgres backup (Tier 3 → Tier 1 promotion)

Anything in the Postgres DB that you want to *not* lose on machine death needs to be exported to a Tier 1 location:

```bash
# Scheduled via launchd, e.g., weekly
pg_dump -h localhost -p <orbstack-port> -U proxy proxy_db \
  > ~/code/personal-nix/backups/proxy-db-$(date -u +%Y-%m-%d).sql
cd ~/code/personal-nix && git add backups/ && git commit -m "weekly proxy-db snapshot" && git push
```

This is the canonical "promote Tier 3 to Tier 1" pattern: a periodic export to a committed location.

### Verify by restoring

Quarterly:
1. Restore one file from Time Machine that's > 30 days old.
2. Restore one file from Backblaze that's > 30 days old.
3. Restore the most recent Postgres dump to a scratch database, verify it parses.

An untested backup is a hope, not a backup.

---

## 17. Disk space management — under memory pressure

### The 15% rule

Keep at least 15% of your SSD free. Under PROXY this is non-negotiable: swap pressure compounds memory pressure, and memory pressure is what caused the May 10/11 incident.

`df -h /` shows current free %.

### Where space actually goes — investigate top-down

```bash
df -h /
ncdu ~                    # interactive, navigable
du -sh ~/* | sort -h      # one-shot summary
du -sh ~/Library/* | sort -h | tail
du -sh ~/code/* | sort -h
```

### The PROXY-specific suspects, in order

1. **Cargo `target/` directories** — the silent biggest offender. Workspace `target/` plus per-project ones.
2. **`~/.orbstack/`** — bounded by 12.6 GB ceiling but still material.
3. **`~/.cargo/registry/`** — accumulates without auto-prune.
4. **node_modules across RN/Expo projects.**
5. **APFS local snapshots** — `tmutil listlocalsnapshots /` to see; auto-thinned but can be > 10 GB.
6. **`~/Library/Developer/Xcode/DerivedData/`** if you've done Xcode work.
7. **`~/Library/Caches/`** — quarterly audit (Slack, browsers, Spotify, Adobe are typical bad actors).

### Memory–disk coupling

Free disk space *is* swap headroom. When memory pressure rises, macOS swaps to SSD. If SSD is also tight, you get the worst of both: memory pressure that can't be relieved by swap, leading to Jetsam — the exact failure mode that motivated PROXY's admission gate.

**The Skill should treat low disk and high memory pressure as the same problem class.** Both are reasons to refuse new loops, both are reasons to recommend the same remediations (close Chrome, prune Docker, clean target/).

---

## 18. Maintenance cadence

PROXY's admission gate already does some health checking continuously (memory pressure sampling, load average). Filesystem hygiene fills in what the admission gate doesn't see (disk space *trends*, accumulating artifacts).

### Daily

Nothing. The admission gate handles the moment-to-moment.

### Weekly

- Triage `~/Downloads/` (CLI one-liner, or proxy-daemon Skill).
- `df -h /` glance — alert if free drops below 25%.
- Postgres pg_dump → personal-nix backups commit (can be a proxy-daemon scheduled job).

### Monthly

- Audit `~/Library/Caches/` size. Delete known offenders.
- Audit `~/Library/LaunchAgents/` for entries that don't belong.
- `cargo cache --autoclean` (and per-project `cargo clean` for projects you haven't touched in 30 days).
- `docker system prune -a` in OrbStack (without `--volumes` unless you've verified Postgres is backed up first).
- `brew cleanup --prune=all && brew autoremove`.
- Review `~/code/scratch/` — promote what became real, delete the rest.

### Quarterly

- Full `ncdu ~` audit. Investigate every directory > 5 GB.
- Restore-test: pull one file each from Time Machine, Backblaze, and Postgres backup.
- Audit installed apps. Uninstall what you haven't opened in 90 days (AppCleaner for leftovers).

### Annually

- Major macOS upgrade decision (wait for `.2` or `.3` of a new release; verify Nix-darwin compatibility first).
- Archive completed projects from `~/code/work/` and `~/code/personal/` to `~/code/archive/` with year prefix.
- Refresh dotfiles repo from current machine state (rare under Nix — most config drift is captured in flake commits).

---

## 19. Archiving

Same as v1:
- Completed projects: `mv ~/code/work/relymd/old-thing ~/code/archive/2026-relymd-old-thing` — year-prefixed.
- Truly-done projects can be tarballed and moved to cold storage (external SSD, Backblaze B2).
- Keep a manifest somewhere in personal-nix: `wiki/archive-index.md`.

The act of archiving is the act of declaring "I am done with this." Resist archiving things you're actually still iterating on.

---

## 20. Anti-patterns under PROXY

The v1 anti-patterns plus PROXY-specific ones:

- **Putting tachikoma-starter or personal-nix in iCloud.** They go in `~/code/` and to git remotes.
- **Treating Tier 3 (per-machine) state as durable.** Chat history, sensor samples — these die with the machine unless you've explicitly promoted them.
- **Trying to manage `~/.orbstack/` manually.** Use `orb`, `docker`, and the admission gate. Direct manipulation of OrbStack VM internals is unsupported and unstable.
- **Spawning claude subprocesses on the host outside PROXY.** This is the exact pattern that caused the May 10/11 Jetsam. Everything goes through the admission gate.
- **Backing up Postgres via Time Machine of the OrbStack VM.** Use pg_dump. Volume-level backup of running databases is corruption-prone and unhelpful.
- **Editing Nix-managed files in `~/.config/` directly.** They're symlinks; edits to the target are read-only or get clobbered. Edit the source in personal-nix and rebuild.
- **Adding new LaunchAgents directly to `~/Library/LaunchAgents/`.** Should be Nix-managed (nix-darwin or home-manager). Manual plists are config that didn't make it into a flake.
- **`docker system prune --volumes` without verifying Postgres is backed up.** Will silently nuke your queue history.
- **Letting `target/` accumulate across every workspace.** Cargo doesn't auto-prune; you have to.

---

## 21. Quick-reference command index

```bash
# Disk
df -h /
du -sh ~/* | sort -h
ncdu ~
tmutil listlocalsnapshots /
tmutil thinlocalsnapshots / 999999999999 4

# Cargo / Rust
cargo clean                                       # in a project
find ~/code -type d -name target -prune -exec du -sh {} +
cargo cache --autoclean

# OrbStack / Docker
orb info
docker system df -v
docker system prune -a                            # NOT --volumes unless Postgres backed up
docker image prune -a
docker builder prune -a
orb stop && orb start                             # forces VM disk compaction

# Postgres
pg_dump -h localhost -p <port> -U proxy proxy_db > ~/code/personal-nix/backups/proxy-db-$(date -u +%Y-%m-%d).sql

# React Native / Expo
rm -rf ios/build android/build android/.gradle ios/Pods node_modules
npx expo prebuild --clean
watchman watch-del-all
rm -rf $TMPDIR/metro-*

# Xcode
rm -rf ~/Library/Developer/Xcode/DerivedData/*
xcrun simctl delete unavailable
pod cache clean --all

# Homebrew (most things are Nix-managed but some aren't)
brew cleanup --prune=all
brew autoremove

# Metadata
xattr -l file
xattr -dr com.apple.quarantine /path/
tag --add Important file.pdf
mdls file

# Search
fd pattern
rg "pattern" .
mdfind "kind:pdf modified:today"
mdfind -onlyin ~/code "pattern"

# Launchd
launchctl list | grep -v com.apple
ls -la ~/Library/LaunchAgents/

# Time Machine exclusions
sudo tmutil addexclusion -p /path/to/exclude
tmutil status
tmutil latestbackup

# Spotlight
sudo mdutil -E /
sudo mdutil -i on /
```

---

## 22. References

**Trusted technical sources:**
- **eclecticlight.co** — Howard Oakley's blog. Best single resource for macOS internals.
- **Apple File System Reference** — `developer.apple.com/documentation/apple_file_system`.
- **OrbStack docs** — orbstack.dev/docs.
- **`man` pages**: `tmutil`, `launchctl`, `mdfind`, `xattr`, `apfs.util`, `diskutil`.

**Tools (most installed via Nix):**
- **Nix + nix-darwin + home-manager** — config management.
- **OrbStack** — Docker/Linux VM substrate.
- **`fd`, `ripgrep`, `ncdu`, `tag`, `cargo-cache`, `sccache`** — all `nix-shell -p <name>` or in your home-manager packages.
- **AppCleaner** — for uninstall-with-leftovers.
- **Backblaze Personal** — off-site backup.

**PROXY-internal references:**
- `tachikoma-starter` — Tier 0 substrate, public.
- `personal-nix` — Tier 1 personal config, private.
- PROXY ADRs — particularly ADR 022 (sibling system Major's pressure-gate commitment).

---

*Two principles, restated:*

*The filesystem rewards discipline applied early and compounds the cost of disorder. Most "filesystem problems" are organizational problems wearing a technical mask.*

*In a memory-pressured agentic environment, filesystem decisions are memory decisions. Disk space is swap headroom; cache size is page-cache pressure; ephemeral container hygiene is admission-gate efficacy. PROXY treats memory as a first-class architectural concern because the alternative crashed the Mac. Filesystem hygiene under PROXY is the same concern at a slower timescale.*
