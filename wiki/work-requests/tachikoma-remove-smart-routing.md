---
status: open
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# Tachikoma: Remove smart routing from bare /tachikoma

Bare `/tachikoma` (no args) currently routes to the ship or recover phase when completed/interrupted worktrees exist. This is confusing — users expect `/tachikoma` to always start a new task. `/tachikoma done` and `/tachikoma resume` are the explicit entry points for those flows.

## Goal

Tachikoma is done when bare `/tachikoma` with no args always starts a new task regardless of existing worktree state, and the invocation table + precondition 10 routing logic reflect this.

## Files in scope

skills/tachikoma/SKILL.md

## Files out of scope

skills/tachikoma/tachikoma.sh.tmpl
skills/tachikoma/ship.md.tmpl
skills/tachikoma/USER-GUIDE.md

## Stop condition

- [ ] Invocation table entry for bare `/tachikoma` says "always starts a new task"
- [ ] Precondition 10 routing table has no rows that route bare `/tachikoma` to ship or recover phase
- [ ] The routing rows for ship/recover are removed or moved to `/tachikoma done` and `/tachikoma resume` entries
- [ ] No other place in SKILL.md suggests running bare `/tachikoma` to trigger ship/recover

## Feedback loops

No automated tests — verify by reading the updated SKILL.md for consistency.

## Quality bar

production
