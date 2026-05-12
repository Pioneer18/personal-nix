# The Engineer's Guide to Maintaining a Mac M4 Pro

**Target system:** MacBook Pro / Mac mini with M4 Pro (10P + 4E cores, 24 GB unified memory)
**Target OS:** macOS Tahoe 26.x
**Audience:** Senior software developers running Xcode, Expo / React Native, Node, Docker, etc.

This guide skips beginner advice, marketing fluff, and obsolete maintenance rituals. It assumes you understand the shell, basic systems programming, and that "free RAM is wasted RAM."

---

## 1. Mental Model: How This Machine Actually Works

Before optimizing anything, internalize how the system differs from a traditional PC.

### 1.1 SoC architecture
M4 Pro is a System-on-Chip. CPU, GPU, Neural Engine, memory controller, SSD controller, Secure Enclave, and media engines all sit on one die or package. You have:

- **10 Performance cores** (high IPC, high power, run at higher voltage/frequency).
- **4 Efficiency cores** (lower IPC, optimized for perf/W). Background work, daemons, low-priority threads land here.
- **Apple Neural Engine (ANE)** — 16-core, used by CoreML, Vision, Speech, Apple Intelligence.
- **Media engines** for ProRes / H.264 / H.265 / AV1 decode (M4 added AV1 decode).
- **GPU** — varies by config.
- **Unified Memory Architecture (UMA)** — there is no discrete VRAM. The CPU, GPU, and ANE all address the same physical memory. This is why a 24 GB Mac outperforms many discrete-GPU machines on ML workloads: zero-copy between accelerators.

Practical implications:
- "GPU memory" is just memory. A Metal app allocating 8 GB takes 8 GB from your pool.
- Memory bandwidth is shared. A GPU-heavy task contends with CPU.
- You cannot upgrade RAM or SSD. Treat them as fixed and manage accordingly.

### 1.2 Scheduler awareness (QoS)
macOS uses **Quality of Service (QoS) classes** to route work to P vs E cores:

| QoS | Typical use | Lands on |
|---|---|---|
| `USER_INTERACTIVE` | UI thread | P |
| `USER_INITIATED` | Active app work | P |
| `DEFAULT` | Unclassified | P (mostly) |
| `UTILITY` | Progress-visible background work | Mixed |
| `BACKGROUND` | Indexing, backups, cleanup | E |

You can observe this with `taskpolicy` and `powermetrics`. Code you write should set appropriate QoS via GCD / `Task(priority:)` — wrong QoS = work on the wrong cluster = either wasted battery or visible jank.

### 1.3 What "SMC reset" and "NVRAM reset" mean on Apple Silicon
**They don't, really.** Apple Silicon has no SMC. NVRAM exists but `nvram` is rarely the answer. The only documented recovery rituals are:

- **Restart** — resets most transient state, including NVRAM-like cached values.
- **Shutdown and wait 30s** — flushes hardware state.
- **DFU restore via Apple Configurator** — the nuclear option, equivalent to firmware reflash.

Stop searching for "M4 SMC reset" — it doesn't exist.

### 1.4 Sealed System Volume (SSV)
The system volume is a read-only APFS volume sealed with a cryptographic hash (the "Signed System Volume"). You cannot modify `/System/*` even as root. This is why kernel extensions are dead and System Extensions (DriverKit, EndpointSecurity, NetworkExtension) are the supported model. Tools that promise to "tune /System" are either lying or running on an unsealed (compromised) system.

---

## 2. Diagnostics & Monitoring — The Real Toolset

Forget the GUI optimizer apps. The actual instrumentation Apple ships is excellent.

### 2.1 Command-line tools (all built in)

```bash
# Live system overview
top -o cpu           # sort by CPU; press ? for keys
htop                 # brew install htop; better TUI

# Memory
vm_stat 1            # paging stats every 1s; watch "Pageouts" and "Swapouts"
sysctl vm.swapusage  # current swap file size and usage
memory_pressure      # one-shot summary
zprint               # zone allocator stats (advanced)

# CPU / power / thermal
sudo powermetrics --samplers cpu_power,gpu_power,thermal -i 1000
# powermetrics is THE tool. Shows P/E cluster frequencies, residencies,
# package power, GPU power, thermal pressure, ANE power.

pmset -g              # current power management settings
pmset -g thermlog     # historical thermal events
pmset -g log | tail   # sleep/wake history

# Filesystem
sudo fs_usage -w -f filesys $(pgrep Xcode)   # which files a process touches
sudo opensnoop                                # similar, dtrace-based
df -h                                          # disk usage by mount
diskutil apfs list                            # APFS containers, volumes, snapshots
diskutil info disk3s1                         # detail on a volume
sudo tmutil listlocalsnapshots /              # Time Machine local snapshots
du -sh -d 1 ~ 2>/dev/null | sort -h           # what's eating your home dir

# Processes
sample <pid> 5                # 5s sampling profile of a hung process
spindump <pid> 10 -file /tmp/x.spindump  # deeper, kernel-level stacks
ps auxww | sort -rk 3 | head  # top CPU consumers
ps auxww | sort -rk 4 | head  # top memory consumers

# Background activity
launchctl list | grep -v com.apple   # third-party launch agents/daemons
launchctl print gui/$(id -u)         # everything loaded for your user
sudo launchctl print system          # everything loaded system-wide

# Unified logging (replaces syslog)
log stream --predicate 'eventMessage CONTAINS "thermal"' --info
log show --predicate 'subsystem == "com.apple.kernel"' --last 1h

# Network
nettop -P                # per-process network throughput
sudo lsof -i -P -n       # all listening sockets + their processes
sudo dtrace -n 'tcp:::send { @[execname] = sum(args[2]->ip_plength); }'
```

### 2.2 GUI: Activity Monitor done right
Activity Monitor is more capable than people give it credit for. Configure it:

- **View → All Processes, Hierarchically** to see process trees.
- **View → Columns** → add: `% GPU`, `GPU Time`, `Energy Impact`, `Real Memory`, `Compressed Mem`, `Sent Bytes`, `Disk Writes`.
- **Memory tab**: the **Memory Pressure** graph is the only memory metric that matters for "should I worry." Green = fine. Yellow = compressed/swapping but functional. Red = system thrashing.
- **Energy tab**: Energy Impact is *the* battery investigation column.

### 2.3 Instruments
Xcode ships Instruments. Free, signed, and the same tool Apple engineers use:
- **Time Profiler** for CPU
- **Allocations / Leaks** for memory
- **Metal System Trace** for GPU
- **System Trace** for kernel-level events
- **Energy Log** for power
- **Network**, **File Activity**, **Core Animation**, etc.

Launch via Xcode → Open Developer Tool → Instruments, or `instruments -t "Time Profiler" -D /tmp/out.trace -l 10000`.

### 2.4 Third-party diagnostics worth installing
- **Howard Oakley's utilities** (eclecticlight.co): `Mints`, `SilentKnight`, `Spundle`, `XProCheck`, `T2M2`. All free, all signed, all targeted single-purpose tools.
- **iStat Menus** — the only menubar monitor I trust (paid, ~$10).
- **stats** (github.com/exelban/stats) — open-source menubar monitor, free.
- **DaisyDisk** or **GrandPerspective** (free) — disk space visualization.
- **Asitop** (`pip install asitop`) — `powermetrics` wrapped in a TUI, Apple Silicon–specific.
- **Mactop** (`brew install mactop`) — similar, Go-based.

---

## 3. Memory and Swap

24 GB is comfortable for most dev work but tight when you run Xcode + simulator + Chrome + a VS Code extension host + a Docker VM + a Slack-Electron-thing all at once. Memory hygiene matters here.

### 3.1 What macOS actually does
- **Memory compression** (since Mavericks, far more aggressive in Tahoe). Inactive pages are LZ4-compressed in place. A compressed page typically reaches ~50% of original size with sub-microsecond decompress. The "Compressed" column in Activity Monitor is the size *after* compression.
- **Swap** to `/private/var/vm/swapfile*`. These files grow dynamically and shrink lazily. Swap on an SSD is fast but it wears the SSD and adds latency.
- **Jetsam** — the iOS-derived mechanism that kills processes when memory pressure becomes critical. On macOS it usually kills only sandboxed/background apps, but during severe pressure it will kill foreground apps too. This is the "Application Memory" out-of-memory dialog.
- **WindowServer leak** — Tahoe (like several recent macOS versions) has a slow WindowServer memory creep. The fix is a reboot every 1–2 weeks if you keep uptime high. Don't try to "fix" WindowServer.

### 3.2 Diagnosing real pressure
```bash
# Are you actually swapping?
sysctl vm.swapusage
# vm.swapusage: total = 4096.00M  used = 1843.21M  free = 2252.79M  (encrypted)

# Compression ratio
vm_stat | grep -E "compress|page"
# Compute: (Pages stored in compressor * 100) / (Pages occupied by compressor)
# > 200% = OS is reclaiming significant memory through compression
```

If `Pageouts` and `Swapins` per second stay near zero, you're fine regardless of how much swap exists. Swap *existing* is normal; swap *churning* is the problem.

### 3.3 The big offenders on a 24 GB machine
| Process | Typical resident | Notes |
|---|---|---|
| `Xcode` | 4–10 GB | Per project. Indexing makes it worse. |
| `com.apple.dt.Xcode.sourcekit-lsp` / `SourceKitService` | 1–4 GB | One per project. Restart Xcode if it pins. |
| iOS Simulator | 2–4 GB per device | Each booted device. Shut down unused ones. |
| Chrome / Brave / Arc | 0.5–2 GB + 100–300 MB per active tab | Use tab discarding extensions. |
| Slack | 1–2 GB | Use the web app if you can stomach it. |
| Docker Desktop | Whatever you allocated to the VM (default 8 GB) | Lower in Settings → Resources. |
| Node language servers (TS, ESLint, Volar) | 0.5–1.5 GB each | One per VS Code window. |
| `mds` / `mds_stores` | 0.5–2 GB during reindex | Spotlight. Normal. Don't disable. |

### 3.4 Practical memory tactics
- Shut down unused simulator devices: `xcrun simctl shutdown all` (then boot only what you need).
- Reduce Docker memory if you're not running heavy containers: Docker Desktop → Settings → Resources → Memory → 4 GB is plenty for most Node/Postgres setups.
- In VS Code: `"typescript.tsserver.maxTsServerMemory": 4096` and close windows you aren't actively using.
- Restart Xcode after long indexing sessions; SourceKit doesn't always release.
- **Don't** install RAM cleaner / "memory freer" apps. They call `purge` (a developer tool that drops file caches), which forces re-reads from disk and slows everything down.

### 3.5 Tahoe specifics
- Memory compression is more aggressive — expect higher "Compressed" numbers as normal.
- Apple Intelligence (`AppleIntelligencePlatform`, `GenerativeExperiencesSafetyInferenceProvider`) loads models into memory. If you don't use it, turn it off in System Settings → Apple Intelligence & Siri. This reclaims 1–3 GB.
- Several reports of `WindowServer` and `Mail` memory leaks on Tahoe early releases. Stay current with point releases.

---

## 4. Storage and APFS

Your SSD is soldered. Treat it like a finite, wearable resource.

### 4.1 APFS realities
- **Copy-on-write**: file modifications write new blocks, then update pointers. There is no fragmentation in the traditional sense; defragmenters are pointless and harmful.
- **Snapshots**: Time Machine creates *local* snapshots every hour, stored on the same volume. They appear as "Purgeable" space — macOS reclaims them automatically as needed but they can mask real free space.
- **Sparse files** and **clones**: `cp -c` makes instant clones (shared blocks) on APFS. Useful when copying large project trees.
- **Containers and volumes**: one container, many volumes, shared free space. `Data`, `System`, `Preboot`, `Recovery`, `VM` are all separate volumes.

### 4.2 Where space actually goes
```bash
# Top-level breakdown
df -h /

# Purgeable / snapshot space
diskutil info / | grep -E "Free|Available"
# "Available (Free) Total Including Purgeable" vs "Free" tells you snapshot size

# Local Time Machine snapshots
tmutil listlocalsnapshots /
# If you really need the space now (rare):
tmutil thinlocalsnapshots / 10000000000 4   # frees up to 10GB at urgency 4

# Hidden caches and logs
du -sh ~/Library/Caches/* 2>/dev/null | sort -h | tail -20
du -sh ~/Library/Logs/* 2>/dev/null | sort -h | tail -20
du -sh /private/var/log/* 2>/dev/null | sort -h | tail -20

# System Data category (in About This Mac)
# Mostly: caches, snapshots, logs, swap, sleepimage, language packs, model assets
```

### 4.3 Maintenance you actually need
```bash
# Verify volume health (works on mounted volumes since High Sierra)
diskutil verifyVolume /
diskutil verifyVolume /System/Volumes/Data
# First Aid via GUI: Disk Utility → View → Show All Devices → Container disk3 → First Aid

# Trim is automatic on Apple SSDs. Don't run trimforce. Period.

# Spotlight index issues
sudo mdutil -s /                    # status
sudo mdutil -E /                    # erase and rebuild (slow but fixes corruption)
sudo mdutil -i off / && sudo mdutil -i on /   # toggle indexing

# Optimize storage offload (iCloud-tied, optional)
# System Settings → General → Storage → Recommendations
```

### 4.4 SSD wear
The internal SSD reports SMART-like data through `system_profiler SPNVMeDataType`:

```bash
system_profiler SPNVMeDataType | grep -A 2 "Data Written\|Data Read\|Percentage"
```

`Percentage Used` is the wear indicator (0% new, 100% rated wear consumed). On a 1+ TB drive with normal dev use, expect 1–3% per year. If you're seeing 10%+/year, you're probably swapping heavily or running a database with high write amplification — investigate the workload, don't blame the drive.

### 4.5 Free-space target
Keep at least **15% of the data volume free** at all times. APFS metadata, snapshots, and swap need headroom. Going under 10% degrades performance and risks failed updates.

---

## 5. CPU, Thermal, and Power

### 5.1 What "thermal pressure" means
M-series chips throttle gracefully under sustained load. macOS reports thermal state as:

```bash
pmset -g therm
# CPU_Scheduler_Limit: percent of max scheduler slots available
# CPU_Speed_Limit: percent of max frequency available
# CPU_Available_CPUs: how many cores are usable
```

Under thermal pressure on a MacBook, expect P-core frequency to drop and E-cores to take more load. A MacBook Pro with the active cooler (M4 Pro / Max) handles sustained loads better than a MacBook Air (passive). A Mac mini sits between.

### 5.2 Power modes
System Settings → Battery → Energy Mode:
- **Automatic**
- **Low Power** — caps P-core frequencies, reduces display refresh, slows background.
- **High Power** (Pro / Max chips on AC only) — removes thermal headroom limits, allows sustained max boost.

For sustained compile / render work on AC, **High Power** is meaningful — roughly 10–15% throughput improvement on long jobs. For battery, Low Power can easily double runtime on light loads.

```bash
sudo pmset -a powermode 0   # normal
sudo pmset -a powermode 1   # low power
sudo pmset -a powermode 2   # high power (Pro/Max, AC only)
```

### 5.3 Background CPU offenders
The usual suspects on a dev machine:
- `mds_stores` after large file operations (re-indexing). Wait it out.
- `photoanalysisd`, `mediaanalysisd` — Photos library scanning. Heavy first run.
- `bird` — iCloud Drive sync.
- `cloudd` — generic iCloud daemon.
- `corespotlightd`, `knowledge-agent`, `mdworker_shared` — search/indexing.
- `XProtectRemediatorService`, `XProtectBehaviorService` — anti-malware sweeps. Don't disable.
- Apple Intelligence model downloads/inference.
- Third-party: Dropbox, OneDrive, Backblaze, Zoom helpers, Adobe daemons, MS AutoUpdate.

Investigate with:
```bash
# Apps with recent significant CPU use
log show --predicate 'subsystem == "com.apple.duetactivityscheduler"' --last 30m
```

---

## 6. Security Stack (and Why You Shouldn't Disable It)

### 6.1 Layers, top to bottom
1. **Gatekeeper** — checks code signing and notarization on first launch.
2. **XProtect / XProtect Remediator** — Apple's malware scanner. Updates silently via `XProtectUpdates`. Verify with Howard Oakley's `SilentKnight` or `XProCheck`.
3. **MRT** (Malware Removal Tool) — being replaced by XProtect Remediator.
4. **TCC** (Transparency, Consent, and Control) — the permission system behind every "wants to access" prompt. State lives in `~/Library/Application Support/com.apple.TCC/TCC.db` and `/Library/Application Support/com.apple.TCC/TCC.db` (SIP-protected). Reset a single app: `tccutil reset Microphone com.example.app`.
5. **SIP** (System Integrity Protection) — restricts root from modifying system files, kexts, runtime attach. Check with `csrutil status`. **Leave it on.**
6. **Sealed System Volume** — cryptographic verification of `/System`.
7. **Secure Enclave** — separate coprocessor for keys, Touch ID, FileVault keys.
8. **FileVault** — full-disk encryption. Should be on. Check with `fdesetup status`.
9. **Activation Lock / Find My** — anti-theft.

### 6.2 What to actually do
- Keep FileVault on.
- Keep SIP on.
- Don't grant Full Disk Access to anything you don't need to. Audit periodically: System Settings → Privacy & Security → Full Disk Access.
- Audit Login Items and Background Items regularly (Section 7.3).
- Periodically check XProtect/MRT versions are current via `SilentKnight`.

### 6.3 Code signing for your own dev work
- Use `codesign -dv --verbose=4 /path/to/binary` to inspect signatures.
- For local binaries you build, ad-hoc signing (`codesign -s -`) is enough for most tools.
- `spctl --assess --verbose /Applications/Foo.app` checks Gatekeeper acceptance.

---

## 7. Periodic Maintenance: What macOS Does and What You Should Do

### 7.1 Built-in periodic scripts
macOS ships with `/etc/periodic/{daily,weekly,monthly}` — old BSD-era maintenance jobs run by `com.apple.periodic-*` launch daemons. They rotate logs, clean tmp, etc. They're scheduled around 3 AM. **If your Mac is asleep at 3 AM, they run on next wake.**

```bash
# See when they last ran
ls -lT /var/log/{daily,weekly,monthly}.out

# Force-run manually (rarely needed)
sudo periodic daily
sudo periodic weekly
sudo periodic monthly
```

Howard Oakley's **Mints** is a clean GUI for this plus log/cache management.

### 7.2 What's actually safe to clean
Almost nothing. Modern macOS manages its own caches well. But these are safe and sometimes useful:

```bash
# User caches (apps will rebuild)
rm -rf ~/Library/Caches/*    # NOT ~/Library/Caches itself

# Quicklook thumbnails
qlmanage -r cache

# Font cache (if fonts behave weirdly)
sudo atsutil databases -remove

# DNS cache
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder

# Recent items / jump lists
# System Settings → General → Recent Items → None (per-document type)
```

**Do not** delete:
- `~/Library/Application Support/*` (this is data, not cache)
- `/private/var/db/*`
- Anything under `/System` (you can't anyway)
- `/Library/Caches/*` without knowing what owns it

### 7.3 Login items and background agents — the highest-ROI cleanup
This is where the real bloat lives. System Settings → General → Login Items & Extensions. Audit:
- **Open at Login** — apps that launch when you log in.
- **Allow in the Background** — agents and daemons (Adobe, Microsoft, Zoom, Dropbox, Logitech, etc.).

Disable everything you don't actively need. Each background agent is a process, memory consumer, and often a network caller. Most installer "helpers" are useless 99% of the time.

For deeper inspection:
```bash
launchctl list | grep -v com.apple                    # user-loaded
sudo launchctl list | grep -v com.apple               # system-loaded

ls ~/Library/LaunchAgents/                            # per-user agents
ls /Library/LaunchAgents/                             # per-machine agents
ls /Library/LaunchDaemons/                            # system daemons
```

To disable without uninstalling:
```bash
launchctl unload -w ~/Library/LaunchAgents/com.example.helper.plist
```

---

## 8. Developer-Specific Hygiene

This is where most of your reclaimable space and performance lives.

### 8.1 Xcode and friends
```bash
# Derived Data — safe to nuke. Recompile cost on next build.
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# Archives — keep ones for shipped builds; delete others.
open ~/Library/Developer/Xcode/Archives

# iOS device support symbols — for old OS versions you no longer debug.
ls ~/Library/Developer/Xcode/iOS\ DeviceSupport
ls ~/Library/Developer/Xcode/watchOS\ DeviceSupport

# Simulator devices and runtimes
xcrun simctl list devices
xcrun simctl delete unavailable           # remove devices for missing runtimes
xcrun simctl list runtimes
xcodebuild -downloadAllPlatforms          # if you want everything; otherwise manage manually

# Old simulator data (per-device caches)
xcrun simctl shutdown all
xcrun simctl erase all                    # nukes app data on every simulator

# Unused Xcode versions — keep Xcode-beta or stable, not both, if you can.
# Xcode itself is ~30 GB.

# CocoaPods caches
rm -rf ~/Library/Caches/CocoaPods
rm -rf ~/.cocoapods/repos                  # forces spec repo re-fetch on next pod install
```

For React Native / Expo specifically:
```bash
# Metro bundler cache
watchman watch-del-all
rm -rf $TMPDIR/metro-*

# Expo prebuild artifacts (per project)
rm -rf ios android        # if you're not customizing native code

# Old EAS build artifacts
eas build:list             # then prune via dashboard
```

### 8.2 Homebrew
```bash
brew update
brew upgrade
brew cleanup --prune=all      # remove old versions, downloads, logs
brew autoremove               # remove orphan dependencies
brew doctor                   # surface common problems

# What's installed and why
brew leaves                   # top-level installs (you asked for these)
brew deps --tree --installed  # full tree
brew list --cask              # GUI apps installed via brew

# Caches
ls -la $(brew --cache)
rm -rf $(brew --cache)/*      # if you really need the space
```

### 8.3 Node ecosystems
```bash
# node_modules graveyards across projects
npx npkill                    # interactive cleanup
# or, brute force:
find ~ -name "node_modules" -type d -prune -print 2>/dev/null | xargs du -sh

# Package manager caches
npm cache clean --force       # ~/.npm
yarn cache clean              # ~/Library/Caches/Yarn
pnpm store prune              # ~/Library/pnpm/store

# Volta / nvm / fnm — unused Node versions
nvm ls                        # then nvm uninstall vX.Y.Z
volta list                    # then volta uninstall node@X.Y.Z
```

### 8.4 Python
```bash
# pip cache
pip cache purge
du -sh ~/Library/Caches/pip

# pyenv / uv versions
pyenv versions
uv python list

# Conda — if you must. Conda envs eat tens of GB silently.
conda env list
conda clean -a
```

### 8.5 Docker
```bash
docker system df              # what's using space
docker system prune -a --volumes   # nuke unused images, containers, volumes
docker builder prune -a       # build cache

# Resize Docker VM disk: Docker Desktop → Settings → Resources → Disk image size
# Then "Apply & restart". The VM image lives at:
#   ~/Library/Containers/com.docker.docker/Data/vms/
```

If you use **OrbStack** or **Colima** instead of Docker Desktop on Apple Silicon, both are markedly more memory-efficient. Worth evaluating.

### 8.6 Other dev caches
```bash
# Gradle (Android)
rm -rf ~/.gradle/caches

# Maven
rm -rf ~/.m2/repository       # will re-download on next build

# Rust
cargo cache --autoclean       # cargo install cargo-cache

# Go
go clean -modcache

# Ruby / Bundler
gem cleanup
rm -rf ~/.bundle/cache

# JetBrains caches (if you use IntelliJ / WebStorm / etc.)
rm -rf ~/Library/Caches/JetBrains/*
rm -rf ~/Library/Logs/JetBrains/*
```

### 8.7 VS Code
```bash
# Extension host crashes / TS server bloat — restart VS Code
# Don't keep 20 windows open simultaneously; each runs its own extension host.

# Disable in settings:
# "telemetry.telemetryLevel": "off"
# "files.watcherExclude": { "**/node_modules/**": true, "**/.git/objects/**": true }
# "search.exclude": same

# Cache
du -sh ~/Library/Application\ Support/Code/
# Cache/ and CachedData/ are safe to clear if pathological
```

---

## 9. Network Hygiene

### 9.1 Visibility
```bash
# Per-process throughput
nettop -P -m route

# Open ports / listening processes
sudo lsof -i -P -n | grep LISTEN

# DNS resolution diagnostics
scutil --dns                              # DNS config in detail
dscacheutil -q host -a name example.com   # local resolver test
dig +short example.com @8.8.8.8           # bypass local resolver

# Wi-Fi diagnostics
sudo wdutil info                          # current Wi-Fi state, signal, channel
sudo /System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport -I
# (deprecated but still works on Tahoe; use wdutil going forward)
```

### 9.2 Firewall and filtering
- macOS application firewall: System Settings → Network → Firewall. Useful but limited.
- **Little Snitch** ($) or **LuLu** (free, github.com/objective-see/LuLu) for outbound monitoring. LuLu is from Patrick Wardle and is trustworthy.
- **NextDNS** or **AdGuard Home** at the DNS layer for tracker/malware blocking.

### 9.3 VPN / Network Extensions
Each VPN client installs a Network Extension that filters all traffic. Removing a defunct VPN client requires more than dragging the app to trash — use the vendor's uninstaller or:
```bash
systemextensionsctl list
sudo systemextensionsctl uninstall <teamID> <bundleID>
```

---

## 10. Backups (Non-Negotiable)

The 3-2-1 rule: **3** copies, **2** different media, **1** off-site.

### 10.1 Time Machine
- One external SSD, APFS-formatted, dedicated. (Don't share the drive with other data.)
- Time Machine on Tahoe writes APFS snapshots, both local (on internal) and remote (on backup drive). It's faster and more space-efficient than the old HFS+ scheme.
- Verify periodically: `tmutil status`, `tmutil latestbackup`.

### 10.2 Off-site
- **Backblaze** (~$9/mo) — unlimited, runs in background, well-supported on macOS.
- **Arq** (one-time license) — backs up to S3 / B2 / Wasabi / etc., end-to-end encrypted. Better for engineers who want control.
- **iCloud Drive** is not a backup. It syncs deletes.

### 10.3 Bootable clone (optional)
On Apple Silicon, "bootable clones" are no longer fully bootable in the old sense — you can clone the Data volume but the System volume must come from Apple. **Carbon Copy Cloner** handles this correctly and remains useful for fast restore.

### 10.4 Source code
Push to a remote (GitHub / GitLab / self-hosted) at end of day. `git stash` + push, even of WIP branches. Local-only commits are not backed up by Time Machine in a way you want to rely on.

---

## 11. Curated Tooling

A short, opinionated list. All currently maintained, all signed.

### Diagnostic / monitoring
- **iStat Menus** — menubar metrics
- **stats** — open-source menubar metrics
- **asitop** / **mactop** — Apple Silicon TUI dashboards
- **Howard Oakley's apps** — Mints, SilentKnight, XProCheck, Spundle, T2M2

### Storage
- **DaisyDisk** or **GrandPerspective** — what's eating disk
- **OmniDiskSweeper** — free CLI-like enumeration
- **AppCleaner** (FreeMacSoft) — uninstall apps with their support files

### Security / privacy
- **LuLu** — outbound firewall
- **KnockKnock** — what persists across reboots
- **BlockBlock** — alerts on new persistence installation
- **DoNotDisturb** — physical access detection (laptop)
- (All four are from Objective-See / Patrick Wardle, all free.)

### Quality-of-life
- **Raycast** or **Alfred** — launchers (much faster than Spotlight)
- **Rectangle** or **Rectangle Pro** — window management
- **Karabiner-Elements** — keyboard remapping
- **Hidden Bar** / **Bartender 5** — menubar management
- **MonitorControl** — software brightness/volume for external displays

### Developer
- **OrbStack** — Docker replacement, faster and lighter than Docker Desktop
- **Tower** / **Fork** / **lazygit** — git UI/TUI
- **Charles** or **Proxyman** — HTTP debugging
- **TablePlus** — DB GUI

---

## 12. Anti-Patterns (Do Not Do These)

- **CleanMyMac, MacKeeper, Onyx-as-daily-driver, MacBooster**, etc. — at best unnecessary, at worst destructive. The few useful operations they do (run periodic, clear caches) you can do in one line of shell.
- **"Repair Permissions"** — not a thing since El Capitan. The System Volume is read-only and the Data volume's permissions are managed by APFS.
- **`trimforce enable`** — only meaningful for third-party SSDs in older Macs. Your soldered SSD already has TRIM.
- **Disabling Spotlight** — kneecaps system search, Mail search, file open dialogs. Don't do it. If indexing is pathological, rebuild it (`mdutil -E`).
- **Disabling SIP** — removes the strongest defense against rootkits and malware persistence. The only legitimate reasons are kernel development and specific debugging; turn it back on immediately after.
- **"Free memory" apps** — they call `purge`, which drops the file system cache and forces slow re-reads. Counterproductive.
- **Defragmenters** — pointless on APFS, harmful to SSD wear.
- **Aggressive cache deletion via cron** — caches exist because rebuilding them is expensive. Let macOS manage them.
- **Login Item bloat** — every "helper" agent is a tax on boot, memory, and battery. Audit every quarter.
- **Manually deleting language packs / "Monolingual"-style tools** — saves negligible space, breaks system updates.
- **Letting the SSD fill past 90%** — performance degrades, snapshots can't take, updates can fail.

---

## 13. A Realistic Maintenance Schedule

### Daily (automatic, mostly)
- Push WIP code to remote.
- Time Machine backup runs hourly when drive is connected.

### Weekly (5 minutes)
- Reboot if uptime > 7 days (resets WindowServer, kernel caches, periodic-script backlog).
- Glance at Activity Monitor → Memory tab. Anything unexpected resident at the top?
- `brew update && brew upgrade && brew cleanup`.

### Monthly (15–30 minutes)
- `df -h` — check free space, address if < 20% free.
- Clean Xcode DerivedData and unused simulator runtimes if you've been building.
- `docker system prune -a --volumes` if you use Docker.
- `npx npkill` over your code directories.
- Audit Login Items and Background Items.
- Run `SilentKnight` to verify XProtect / MRT / TCC / firmware are current.
- Verify Time Machine backup is recent (`tmutil latestbackup`).

### Quarterly
- Run Disk Utility First Aid on the container.
- Audit Full Disk Access, Accessibility, Screen Recording, Input Monitoring permissions in System Settings → Privacy & Security. Remove anything you no longer use.
- Check SSD wear: `system_profiler SPNVMeDataType | grep -A 2 "Percentage"`.
- Update all manually-installed apps (those not in the App Store or Homebrew).
- Review installed apps; uninstall what you haven't used in 90 days. AppCleaner removes leftovers.

### Annually
- Major macOS upgrade: wait for `.2` or `.3` of a new major release. Have two current backups before upgrading.
- Audit your subscriptions and licenses.
- Test a restore from your off-site backup. An untested backup is a hope, not a backup.

---

## 14. References

- **eclecticlight.co** — Howard Oakley's blog. The single best technical macOS resource.
- **Apple Platform Security Guide** — current PDF on apple.com/business/docs.
- **Apple Developer Documentation** — for QoS, GCD, system extensions.
- **`man powermetrics`**, **`man pmset`**, **`man launchctl`**, **`man tmutil`** — most macOS tools have surprisingly thorough man pages.
- **Joe Kissell's "Take Control of Maintaining Your Mac"** — practical, frequently updated.
- **Patrick Wardle / Objective-See** — Mac security tooling and research.
- **macOS Internals** by Jonathan Levin (newosxbook.com) — the deep-dive reference if you want kernel-level understanding.

---

*The principle running through all of this: macOS does a good job of managing itself. Most maintenance is observation, not intervention. The exceptions are the things you uniquely create — dev caches, background agents, projects, snapshots — and those are exactly where this guide focuses.*
