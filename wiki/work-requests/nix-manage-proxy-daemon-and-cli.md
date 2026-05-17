---
status: grabbed
priority: 3
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-16
---

# Nix-manage proxy-daemon + proxy CLI + proxy-voice binaries

> Grilled 2026-05-16. Decisions locked: absolute-path workspace, sccache enabled, all three binaries in one slice. Ready for tachikoma dispatch.

## Why now

The `proxy-daemon`, `proxy` CLI, and `proxy-voice` binaries are hand-installed at `~/.local/bin/`. Every time their code ships (e.g. proxy-27/28/29 on 2026-05-14), the user must manually `cargo build --release && cp ... && launchctl kickstart`. Skipped steps create the "stale daemon class" of bugs — observed 2026-05-14 when proxy-27/28/29 endpoints 404'd because the running daemon was still on the May-12 binary. Nix-managing the build + install + LaunchAgent restart eliminates this class.

## Goal

A single `dev` rebuild (nix-darwin activation) handles all of this:

- Builds `proxy-daemon`, `proxy` CLI, and `proxy-voice` from the cargo workspace at `~/Projects/tachikoma-starter/`
- Installs all three binaries into the user's nix profile
- Manages `com.proxy.daemon` and `com.proxy.voice` LaunchAgent plists via `launchd.user.agents.*`
- Restarts the daemons on rebuild when the binary hash changes
- Removes hand-installed binaries from `~/.local/bin/`

## Files in scope

- `~/projects/personal-nix/modules/proxy-rust-services.nix` (new) — module that imports the Rust workspace, declares the cargo packages, installs the binaries, and declares both LaunchAgent plists
- `~/projects/personal-nix/flake.nix` — add `crane` as a flake input; wire the new module into the home-manager config
- `~/projects/personal-nix/home.nix` (or wherever modules are aggregated) — import `proxy-rust-services.nix`
- The new module configures `RUSTC_WRAPPER=sccache` for the cargo build
- Update `~/projects/personal-nix/CLAUDE.md` (if it exists) — note the new module + that proxy binaries are now nix-managed
- Update `~/Projects/tachikoma-starter/daemon/README.md` — banner noting personal-nix is canonical install path; `daemon/install.sh` is dev-only fallback

## Files out of scope

- `~/Projects/tachikoma-starter/daemon/install.sh` itself — leave functional, just deprecate in README
- Major Shells (`shell-A/B/C`) — different beast, not nix-managed
- `notify-app/` Swift project — separate signing flow, deferred
- Cross-machine recipe — this slice targets MacBook-Pro-2 only; the pattern is portable but other-Mac rollout is a follow-on

## Stop condition

- [ ] New module `modules/proxy-rust-services.nix` exists; uses `crane` to build the cargo workspace at `~/Projects/tachikoma-starter/` by absolute path
- [ ] `proxy-daemon`, `proxy`, `proxy-voice` binaries appear in `~/.nix-profile/bin/` after `dev` rebuild
- [ ] `which proxy proxy-daemon proxy-voice` resolves to `~/.nix-profile/bin/` paths, not `~/.local/bin/`
- [ ] `~/.local/bin/proxy*` binaries removed as part of activation (or noted as user-cleanup step in run output)
- [ ] LaunchAgent plists for `com.proxy.daemon` and `com.proxy.voice` exist in `~/Library/LaunchAgents/`, written by nix-darwin, not hand-placed
- [ ] `launchctl list | grep com.proxy` shows both agents running with a PID after rebuild
- [ ] `sccache --show-stats` shows cache hits on the second `dev` rebuild (incremental works)
- [ ] After modifying Rust source in `~/Projects/tachikoma-starter/daemon/src/`, running `dev` rebuilds the binary and kickstarts the daemon (verify new binary is running via `proxy --version` or a smoke endpoint)
- [ ] `~/Projects/tachikoma-starter/daemon/README.md` has a banner noting personal-nix is the canonical install path
- [ ] PR opened against `master` of personal-nix with description summarizing the change

## Feedback loops

- `dev` — the nix-darwin rebuild; primary feedback loop. First success = build completes without error.
- `launchctl list | grep com.proxy` — confirms the LaunchAgents are active
- `proxy admission check tachikoma` — confirms daemon is alive and responding post-rebuild
- `proxy --version` — confirms the proxy CLI is on PATH from nix profile
- Manual end-to-end: edit a `println!` into `~/Projects/tachikoma-starter/daemon/src/main.rs`, run `dev`, tail daemon stderr (or log file), confirm the println fires → proves the rebuild→install→restart loop works

## Quality bar

production

## Design notes

- **crane over naersk** — crane has better support for workspaces with shared deps; naersk works but is more constrained. Both produce a single derivation per binary.
- **sccache path** — default is `~/Library/Caches/sccache/`. Don't override; standard location.
- **LaunchAgent restart behavior** — nix-darwin's `launchd.user.agents` block typically writes the plist and `launchctl bootstrap`s it. Restart-on-binary-change is handled by the activation script comparing the new plist's `ProgramArguments[0]` to the running one — if the binary path or hash changes, kickstart. Verify this behavior; if it doesn't kickstart automatically, add an `activation` snippet that does.
- **First rebuild will be slow** — full cargo workspace cold build is multi-GB and 5-30 min. Document this in the PR. Subsequent rebuilds with warm sccache are seconds.
- **Memory awareness** — per PROXY CLAUDE.md hard rule #1: cargo build is heavy. The nix activation will hold memory during link phase. If running on a pressured machine, defer the rebuild. This is a one-time cost (and incremental thereafter).

## Recommended Tachikoma cap

`--afk 12` — new nix module + flake input + 3 cargo packages + 2 LaunchAgent declarations + activation snippet + docs updates. First-time `crane` integration, so allow extra iterations for the user to verify the nix build pattern is correct.

## Related

- ADR 004 — Cargo workspace + tech stack lock-in (workspace structure)
- `~/projects/personal-nix/wiki/decisions/proxy-defer-remote-workhorse.md` — host context
- `shell-01-boot-launchagent` (shipped M1) — example of LaunchAgent nix-managed via personal-nix; pattern to follow
