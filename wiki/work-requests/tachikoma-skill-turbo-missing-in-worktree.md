---
status: open
target_repo: ~/projects/personal-nix
last_updated: 2026-05-20
quality_bar: production
---

# Tachikoma — `turbo` missing in worktree breaks TS feedback loop

For TS slices in tachikoma-starter, work-requests typically declare feedback loops like `pnpm exec tsc --noEmit`, `pnpm test`, `pnpm lint`. These run through `turbo` because the repo is a turbo-fronted workspace. Inside a tachikoma worktree, `turbo` is not on PATH (no `node_modules` symlink, no shared toolchain wiring), so the feedback loop fails before the inner Claude can use it.

Observed 2026-05-20 on `proxy-v2-27-chat-tab-bilingual`:
> *"The npm typecheck/test/lint loop couldn't run — `turbo` isn't on PATH in this worktree (no `node_modules`). Since T-002 touched only Rust + a TOML doc, the Rust feedback loop is the binding one. Logged in progress.txt."*

The agent silently downgraded to "Rust-only feedback" without flagging the gap. Future TS-touching slices would either fail their gate or skip TS verification entirely.

## Goal

A tachikoma worktree scaffolded for a TS-touching slice has a working `pnpm exec tsc` / `pnpm test` / `pnpm lint` chain — either via `pnpm install` at scaffold time, or by sharing the parent repo's `node_modules` symlink, or by injecting the turbo binary into PATH.

## Files in scope

- `skills/tachikoma/tachikoma.sh.tmpl` — scaffold step that creates the worktree (the natural place to add `pnpm install` or symlink `node_modules`)
- `skills/tachikoma/lib/scaffold.sh` (if separate)
- `skills/tachikoma/SKILL.md` — document the toolchain bootstrap step
- Possibly: a per-repo hook so the scaffold can defer to repo-specific bootstrap (`tachikoma-starter` uses pnpm + turbo; other repos may use cargo, plain npm, etc.)

## Files out of scope

- Rewriting the work-request feedback loops to not use turbo (turbo is the project's choice; the skill should accommodate it)
- The MCP `tachikoma_dispatch` tool itself (this is about the inner scaffold, not the dispatcher)

## Stop condition

- [ ] A fresh scaffold against a turbo-fronted repo (e.g. `tachikoma-starter`) leaves the worktree able to run `pnpm exec tsc --noEmit` from `apps/web/` (or equivalent) without `command not found: turbo`
- [ ] The bootstrap step is idempotent and fast (re-scaffolding doesn't re-`pnpm install` the entire workspace if node_modules can be safely shared)
- [ ] If the bootstrap fails (e.g. lockfile mismatch), the loop logs a clear error and the verifier gate doesn't falsely pass on missing TS verification
- [ ] Regression test: scaffold against a fixture turbo repo, assert `turbo --version` succeeds in the worktree

## Feedback loops

- `bash skills/tachikoma/tests/*.sh`
- Manual: re-dispatch a TS-touching slice (e.g. `proxy-v2-infil-cli-completion` once that ships, or any of the open erv2 slices) and confirm `pnpm exec tsc` works in the worktree

## Quality bar

production
