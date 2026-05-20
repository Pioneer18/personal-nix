---
status: open
target_repo: ~/projects/personal-nix
last_updated: 2026-05-20
quality_bar: production
---

# Tachikoma — `ship.md` template never rendered, auto-ship always skipped on COMPLETE

When a tachikoma loop emits `<promise>COMPLETE</promise>`, `tachikoma.sh` checks `$REPO/.tachikoma/ship.md` and runs an auto-ship subprocess if present. But `ship.md.tmpl` (which exists at `skills/tachikoma/ship.md.tmpl`) is never templated into the worktree's `.tachikoma/ship.md` — so the path check at `tachikoma.sh.tmpl:407` always falls into the `else` branch:

```
[ship] ship.md not found — skipping auto-ship. Run /tachikoma done manually.
```

This means **every COMPLETE-sentinel run is short-circuited** before push/PR. Observed 2026-05-20 on `proxy-v2-26-admission-gate-5` (slice already shipped on base, emitted COMPLETE cleanly, then failed to auto-ship).

## Goal

A tachikoma loop that emits `<promise>COMPLETE</promise>` auto-pushes its branch + opens a draft PR (or whatever the templated `ship.md` instructs the inner `claude -p` to do) without manual intervention. The `.tachikoma/ship.md` file must exist at scaffold time so the runtime path at `tachikoma.sh.tmpl:391` actually fires.

## Files in scope

- `skills/tachikoma/tachikoma.sh.tmpl` — add the `ship.md.tmpl` → `.tachikoma/ship.md` rendering step at scaffold time (next to where `prompt.md` is rendered)
- `skills/tachikoma/lib/scaffold.sh` (if separate) — same place that templates `prompt.md`
- `skills/tachikoma/SKILL.md` — note the scaffold step in the skill's flow

## Files out of scope

- Changing what `ship.md` actually instructs the inner Claude to do (the current content is fine; only the rendering is missing)
- Reworking the COMPLETE sentinel detection itself

## Stop condition

- [ ] A fresh `tachikoma_dispatch` scaffold leaves a rendered `$WORKTREE/.tachikoma/ship.md` on disk before the loop starts
- [ ] Any placeholders in `ship.md.tmpl` (e.g. `{{BRANCH}}`, `{{SLUG}}`) are substituted using the same template engine that handles `prompt.md.tmpl`
- [ ] A tachikoma that hits `<promise>COMPLETE</promise>` no longer prints `[ship] ship.md not found` — auto-ship attempts to run
- [ ] Regression test: `bash skills/tachikoma/tests/test-scaffold.sh` (or new test) asserts `.tachikoma/ship.md` exists post-scaffold
- [ ] Manual verification — re-run a tachikoma that previously hit this bug and confirm auto-ship fires

## Feedback loops

- `bash skills/tachikoma/tests/*.sh` (existing test harness)
- Manual: `mcp__tachikoma__tachikoma_dispatch` against any slug, then `ls $WORKTREE/.tachikoma/ship.md`

## Quality bar

production
