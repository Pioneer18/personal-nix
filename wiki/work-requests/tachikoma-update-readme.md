---
status: open
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# Tachikoma: Audit and update README.md

README.md likely references old behavior (grill-based flow, Phase 6 naming, old done flow). Needs an audit against current SKILL.md and updates where stale.

## Goal

Tachikoma is done when README.md accurately reflects current behavior with no references to the old grill, old phase names, or outdated command flows.

## Files in scope

skills/tachikoma/README.md
skills/tachikoma/SKILL.md

## Files out of scope

skills/tachikoma/USER-GUIDE.md
skills/tachikoma/tachikoma.sh.tmpl

## Stop condition

- [ ] README.md has been read and compared against current SKILL.md invocation table and phase names
- [ ] Any references to the old 7-question grill are removed or updated
- [ ] Any references to "Phase 6" are updated to "ship"
- [ ] Any references to `/tachikoma done` as the primary merge trigger are updated
- [ ] `~/.claude/tachikoma.conf` and first-run onboarding are mentioned if README covers configuration
- [ ] Auto-ship behavior is described if README covers the AFK flow

## Feedback loops

No automated tests — cross-reference README.md against SKILL.md for consistency.

## Quality bar

production
