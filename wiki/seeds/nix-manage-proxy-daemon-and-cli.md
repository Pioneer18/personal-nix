---
title: "Nix-manage proxy-daemon + proxy CLI binaries"
tags: [seed, nix-darwin, proxy, daemon, cleanup, deployment]
type: cleanup
last_updated: 2026-05-14
discovered_during: "Building Epic + Queue infrastructure (proxy-27/28/29) — observed manual install dance"
priority: low
---

# Nix-manage proxy-daemon + proxy CLI binaries

The `proxy-daemon` LaunchAgent and (post-proxy-27) the `proxy` CLI are currently hand-installed:

- Binary lives at `~/.local/bin/proxy-daemon` (12 MB Mach-O arm64; built 2026-05-12)
- No nix-darwin / home-manager reference to it (`grep -r proxy-daemon personal-nix/*.nix` returns nothing)
- The `com.proxy.daemon` LaunchAgent plist is registered manually (likely via `launchctl bootstrap` during a prior dev session)

This means every time the daemon code changes (e.g. a Tachikoma ships proxy-27/28/29), the user has to manually:

```bash
cd ~/Projects/tachikoma-starter
cargo build --release
cp target/release/proxy-daemon ~/.local/bin/
cp target/release/proxy        ~/.local/bin/          # post-proxy-27
launchctl kickstart -k "gui/$(id -u)/com.proxy.daemon"
```

These steps are easy to forget — observed 2026-05-14 where proxy-27 + 28 + 29 shipped into `develop` but the running daemon was still on the May-12 binary, causing 404s on the new endpoints + missing `proxy` CLI on PATH.

## What success looks like

A single `dev` rebuild (nix-darwin activation) handles all of this:

- Builds `proxy-daemon` + `proxy` from the cargo workspace at `~/Projects/tachikoma-starter/`
- Installs the binaries into the user profile (or `~/.local/bin/` if that's the convention)
- Manages the `com.proxy.daemon` LaunchAgent plist via `launchd.user.agents.*`
- Restarts the daemon on rebuild when the binary hash changes
- Same treatment for `proxy-voice` (currently also hand-installed)

## Implementation considerations

- **Cargo workspace + nix**: use `crane` or `naersk` to build the workspace inside nix. Workspace path is `~/Projects/tachikoma-starter/` which is user-local, not a nix-store path. Either:
  - (a) reference the workspace by absolute path (requires the workspace to exist before rebuild; coupling)
  - (b) build from a flake input pointing at the GitHub repo (cleaner but requires push-to-rebuild loop)
  - Lean (a) for personal-nix since the workspace + nix config live on the same machine and are co-developed
- **LaunchAgent plist via nix-darwin**: currently `~/Library/LaunchAgents/com.proxy.daemon.plist` is manually placed. Move to `launchd.user.agents."com.proxy.daemon" = { ... };` in a nix module. Test the rebuild kickstart behavior.
- **Conflict with the daemon's own `install.sh`**: the `daemon/install.sh` script in tachikoma-starter does the manual dance. After nix-managing, the install.sh becomes dev-only or deprecated. Worth a note in `daemon/README.md`.
- **Path collision**: nix-darwin installs to `/run/current-system/sw/bin/` (or similar) by default. The hand-installed binary at `~/.local/bin/proxy-daemon` will shadow or be shadowed depending on PATH order. Need to either move all references to the nix-managed path, or remove the hand-installed binary as part of the migration.
- **Same treatment for `proxy-voice`** (`com.proxy.voice`, currently hand-installed too).

## Memory awareness gate

Per CLAUDE.md hard rule #1: memory awareness is load-bearing. `cargo build --release` of the full Rust workspace is CPU + memory heavy (~5-30 min, multi-GB during link). Triggering this during `dev` rebuilds means rebuilds become noticeably slower. Mitigations:

- `sccache` for incremental Rust builds (mentioned in ADR 004 § consequences)
- Build only when source hash changes (nix handles this)
- Don't rebuild during admission-pressure windows

## Scope

Probably one work-request slice (`proxy-XX-nix-manage-rust-daemons`). Includes:

- `daemon/` + `voice/` builds via nix
- `proxy-daemon` + `proxy-voice` + `proxy` CLI installs
- Two LaunchAgent plists via `launchd.user.agents.*`
- Remove hand-installed binaries + update PATH
- Update CLAUDE.md / ARCH.md references

Estimated ~2-4h once a nix-Rust pattern is chosen.

## Related

- ADR 004 — Cargo workspace + tech stack lock-in (workspace structure)
- `~/projects/personal-nix/wiki/recipes/using-the-queue-and-epics.md` — references the manual install dance
- `~/projects/personal-nix/wiki/seeds/fix-tachikoma-dispatch-bugs.md` — symptom of stale daemon (same root cause class: code shipped, services stale)
- `shell-01-boot-launchagent` (shipped M1) — example of LaunchAgent nix-managed via personal-nix; pattern to follow
