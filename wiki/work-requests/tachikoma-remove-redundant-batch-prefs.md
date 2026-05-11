---
status: open
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# Tachikoma: Remove redundant batch preferences from queue drain

The queue drain batch preferences prompt asks `Auto-open PRs? [yes]` and `Auto-clean worktrees? [yes]`. Both are now implicit in auto-ship — every completed run opens a PR and cleans up automatically. These questions are confusing and redundant.

## Goal

Tachikoma is done when the queue drain batch preferences prompt no longer asks about auto-open PRs or auto-clean worktrees, and all references to `auto-open` and `auto-clean` batch preferences are removed from the queue drain section.

## Files in scope

skills/tachikoma/SKILL.md

## Files out of scope

skills/tachikoma/tachikoma.sh.tmpl
skills/tachikoma/ship.md.tmpl

## Stop condition

- [ ] Queue drain Step 1 batch preferences prompt has no `Auto-open PRs?` question
- [ ] Queue drain Step 1 batch preferences prompt has no `Auto-clean worktrees?` question
- [ ] Queue drain Step 2h (abbreviated ship phase) no longer references `auto-open=yes` or `auto-clean=yes` flags
- [ ] No other references to these two batch preferences remain in SKILL.md

## Feedback loops

No automated tests — verify by reading the updated queue drain section for consistency.

## Quality bar

production
