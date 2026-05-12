---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# PROXY — First-run wizard (slice 15b)

The first thing PROXY does on a fresh machine (or via `proxy recalibrate` on an existing one): detects current Docker VM size, host memory, uptime, Major's `shell_pool_size_hint`, and current PROXY settings; surfaces a curated set of one-time fixes (the same checklist as `~/projects/personal-nix/wiki/recipes/mac-pre-proxy-prep.md`); applies user-confirmed changes; then computes safe per-loop `memory_limit_mb` / per-repo `max_concurrent_per_repo` / `global_max_concurrent_loops` defaults and writes them to settings.

The wizard exists so PROXY's defaults are always grounded in real machine state, not hardcoded numbers that drift between machines (the user's Mac, eventually the remote box, eventually a coworker's machine).

## Goal

Run `proxy wizard` (or auto-trigger on first start when settings are empty). The wizard:
1. Inspects the machine (uptime, Docker VM size, free RAM, `shell_pool_size_hint`, Apple Intelligence state, idle sims, etc.)
2. Presents a TUI/dialog with each detected issue + recommended fix
3. For each fix, user can: Apply / Skip / Don't ask again
4. Applies confirmed fixes via the same action executors used in slice 12b
5. Computes safe concurrency defaults from observed post-fix state
6. Writes computed defaults to `proxy_settings`
7. Prints a "ready" summary

`proxy recalibrate` re-runs the wizard at any time, useful after migrating to a new Mac.

## Files in scope

- `daemon/src/wizard/mod.rs`
- `daemon/src/wizard/probes.rs` (re-uses sensor + adds one-time probes like Apple Intelligence detection, login items count)
- `daemon/src/wizard/defaults_calc.rs` (the safe-defaults formula from observed state)
- `apps/tui/src/wizard/**` (Ink TUI for the interactive flow) OR a CLI prompt-based fallback
- `apps/web/src/app/wizard/**` (web-based wizard for users who prefer browser)

## Files out of scope

- The recommendation engine (slice 12b) — wizard reuses its action executors but doesn't add new ones
- macOS notification bundled app (slice 15b)

## Stop condition

- [ ] `proxy wizard` runs to completion on a fresh machine
- [ ] Probes detect at minimum: Docker VM allocation, uptime, free pages, sim count, Apple Intelligence loaded, login items count, Chrome Memory Saver state
- [ ] User can apply or skip each suggested fix
- [ ] Defaults calculator: given `(docker_vm_mb, major_shell_count)`, returns `(memory_limit_mb, max_concurrent_per_repo, global_max_concurrent_loops)` that fit safely. Documented formula in code comments + ARCHITECTURE.md.
- [ ] Writes computed defaults to a `proxy_settings` table
- [ ] `proxy recalibrate` re-runs at any time; preserves user's manual overrides (don't blow away if user set custom values)
- [ ] Test: clear settings, run wizard, verify settings populated and reasonable

## Feedback loops

- `cargo test` (defaults_calc with synthetic inputs)
- Manual: run wizard on this Mac, verify suggestions match the prep recipe

## Quality bar

production

## v2 context

See `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` § 4 (decision 11 — adaptive first-run wizard). Depends on 01b (daemon), 04b (sensor for probes), 12b (action executors).
