---
status: open
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# PROXY — Mac pre-PROXY preparation recipe (slice 00)

A documentation-only slice that creates the canonical Mac pre-install action checklist. Before any v2 code lands, the host's resource state needs to be brought to "ready for PROXY" — Docker memory bumped, OrbStack considered, system rebooted, Apple Intelligence audited, Chrome Memory Saver enabled, idle simulators shut down, login items audited.

This work-request is a meta-slice: it produces a recipe document, not application code. It exists so the prep work has a tracked entry in the queue.

## Goal

A markdown checklist at `~/projects/personal-nix/wiki/recipes/mac-pre-proxy-prep.md` exists with ordered steps, each step listing: purpose, action, verification command, estimated reclaim, revert path. The checklist is re-runnable on a fresh Mac (idempotent) and is referenced from `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` and `~/Projects/tachikoma-starter/CLAUDE.md`.

## Files in scope

- `~/projects/personal-nix/wiki/recipes/mac-pre-proxy-prep.md` (the recipe)
- Cross-links updated in:
  - `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md`
  - `~/Projects/tachikoma-starter/CLAUDE.md`

## Files out of scope

- Any application code in `~/Projects/tachikoma-starter/`

## Stop condition

- [x] Recipe file exists with 9+ steps (Docker bump, OrbStack decision, reboot, Apple Intelligence, Chrome Memory Saver, idle sims, Docker prune, login items audit, verify)
- [x] Each step has: purpose, action, verify command, estimated reclaim, revert
- [x] Checkboxes in markdown for the user to tick off during execution
- [x] Referenced from `docs/ARCHITECTURE.md` § 12

## Feedback loops

- Manually walk through the checklist on this Mac on 2026-05-11; capture observations and gotchas in the recipe's "Notes / gotchas" section as they emerge.

## Quality bar

prototype (it's a doc, gets better with use)

## v2 context

This slice is the first thing any v2 implementation depends on. The Mac substrate has to be ready before the Rust daemon, the Docker container loop runner, or any other v2 work goes in. See `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` § 1 (Motivation) and § 11 (References).
