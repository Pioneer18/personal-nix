---
status: open
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# Tachikoma: Fix PR body shell injection in scaffold

The ship.md.tmpl uses a `{{PR_BODY_ESCAPED}}` placeholder that requires the orchestrator to shell-escape a multi-line PR body string before embedding it in ship.md. This is fragile and a shell injection risk.

## Goal

Tachikoma is done when the scaffold phase writes the PR body to a temp file (`ship_body.txt`) inside `.tachikoma/` and ship.md.tmpl references it via `gh pr create --body-file .tachikoma/ship_body.txt` instead of an inline escaped string.

## Files in scope

skills/tachikoma/SKILL.md
skills/tachikoma/ship.md.tmpl

## Files out of scope

skills/tachikoma/tachikoma.sh.tmpl
skills/tachikoma/prompt.md.tmpl
skills/tachikoma/AGENT-BRIEF.tmpl

## Stop condition

- [ ] `{{PR_BODY_ESCAPED}}` placeholder is removed from ship.md.tmpl
- [ ] ship.md.tmpl uses `--body-file .tachikoma/ship_body.txt`
- [ ] SKILL.md scaffold phase renders `ship_body.txt` (not an escaped inline string)
- [ ] SKILL.md scaffold phase lists `ship_body.txt` in the `.tachikoma/` files written

## Feedback loops

No automated tests — verify by reading the updated files for consistency.

## Quality bar

production
