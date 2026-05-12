---
status: grabbed
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# PROXY — Rust daemon scaffold (slice 01b)

The persistent scheduling/admission brain of PROXY v2. A small Rust binary that runs as a macOS LaunchAgent, owns Postgres LISTEN/NOTIFY, hosts the sensor (added in slice 04b), enforces the admission rule (added in slice 04b), drives the container lifecycle (added in slice 04c), and provides a CLI (`proxy ...`) for queue inspection and overrides.

This slice scaffolds the project: cargo workspace, launchd plist, Postgres connection, basic CLI subcommands, signal handling, structured logging. No sensor yet, no admission yet, no container spawning yet — those land in subsequent slices.

## Goal

A `proxy-daemon` Rust crate exists under `~/Projects/tachikoma-starter/daemon/`. Built with `cargo build --release` to produce a single static binary at `daemon/target/release/proxy-daemon`. A LaunchAgent plist installs it as `~/Library/LaunchAgents/com.proxy.daemon.plist`. The daemon connects to Postgres on startup, runs a `LISTEN test_channel` heartbeat to prove connectivity, and exposes a `proxy --version` CLI subcommand.

## Files in scope

- `daemon/Cargo.toml`
- `daemon/Cargo.lock`
- `daemon/src/main.rs` (entry point + signal handling)
- `daemon/src/cli.rs` (CLI parsing via `clap`)
- `daemon/src/db.rs` (Postgres connection via `tokio-postgres` or `sqlx`)
- `daemon/src/log.rs` (structured logging via `tracing`)
- `daemon/com.proxy.daemon.plist` (LaunchAgent definition)
- `daemon/install.sh` (script to install plist into ~/Library/LaunchAgents/ and load via launchctl)
- `daemon/uninstall.sh` (unload + remove plist)
- Top-level `turbo.json` updated to include `daemon` workspace (if Turborepo orchestration is desired) — optional
- `README.md` updated with daemon build/install instructions

## Files out of scope

- Sensor implementation (slice 04b)
- Admission rule (slice 04b)
- Backend trait + container spawning (slice 04c)
- Scheduler (slice 11b)
- System manager (slice 12b)

## Stop condition

- [ ] `cargo build --release` produces a static binary < 15 MB
- [ ] `proxy-daemon --version` prints version
- [ ] `proxy queue list` (stub) returns empty JSON from PG
- [ ] LaunchAgent plist loads via `launchctl load -w ~/Library/LaunchAgents/com.proxy.daemon.plist`
- [ ] Daemon connects to PG, runs `LISTEN _heartbeat`, logs every 30s
- [ ] Graceful shutdown on SIGTERM (close PG, flush logs, exit 0)
- [ ] `install.sh` is idempotent (safe to re-run)
- [ ] `uninstall.sh` cleanly removes the LaunchAgent
- [ ] README updated with usage

## Feedback loops

- `cargo build --release` (must compile)
- `cargo test` (unit tests for CLI parsing, db connection retry)
- Manual test: install, observe logs in `~/Library/Logs/proxy-daemon.log` (path TBD), `kill -TERM <pid>`, verify graceful exit

## Quality bar

production

## v2 context

This is the cornerstone of the v2 architecture — see `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` § 3-5. It replaces the slice-01 plan of "scheduler inside Next.js." The daemon language is Rust (final pending — see ARCHITECTURE.md Appendix B); if Go is chosen instead, the slice scope is unchanged but Cargo.toml becomes go.mod, etc.

Dependencies for subsequent slices: 04b adds sensor; 04c adds backend trait + LocalDocker; 11b adds scheduler. This slice must be merged before any of them.
