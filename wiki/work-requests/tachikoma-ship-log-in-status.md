---
status: open
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# Tachikoma: Show ship log in /tachikoma status

If auto-ship fails, the user has no way to see why without manually `cat`-ing `.tachikoma/ship.log`. The status subcommand should surface this automatically.

## Goal

Tachikoma is done when `/tachikoma status <slug>` shows a "Last ship attempt" section (tail of `ship.log`) when `ship.log` exists in the worktree.

## Files in scope

skills/tachikoma/SKILL.md

## Files out of scope

skills/tachikoma/tachikoma.sh.tmpl
skills/tachikoma/ship.md.tmpl

## Stop condition

- [ ] SKILL.md status subcommand (single tachikoma detail view) checks for `.tachikoma/ship.log`
- [ ] If `ship.log` exists, a "Last ship attempt" section appears in the status output showing the last 15 lines
- [ ] If `ship.log` does not exist, the section is omitted entirely (no empty placeholder)
- [ ] The status output still fits under ~40 lines when ship.log is present

## Feedback loops

No automated tests — verify by reading the updated SKILL.md status section for consistency.

## Quality bar

production
