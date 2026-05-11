---
status: done
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# Tachikoma: Rewrite USER-GUIDE.md

USER-GUIDE.md is completely stale. It references the old 7-question grill, old Phase 6 naming, and old `/tachikoma done` as the primary merge flow. None of that matches the current design.

## Goal

Tachikoma is done when USER-GUIDE.md accurately describes current behavior: zero-grill preflight with `~/.claude/tachikoma.conf`, auto-ship on completion, new phase names (preflight/scaffold/launch/ship/recover), and `/tachikoma done` as a fallback for failed auto-ship.

## Files in scope

skills/tachikoma/USER-GUIDE.md
skills/tachikoma/SKILL.md

## Files out of scope

skills/tachikoma/tachikoma.sh.tmpl
skills/tachikoma/ship.md.tmpl
skills/tachikoma/README.md

## Stop condition

- [ ] USER-GUIDE.md has no references to the old grill (7 questions, "Takes ~2 minutes")
- [ ] USER-GUIDE.md uses new phase names throughout (preflight, scaffold, launch, ship, recover)
- [ ] USER-GUIDE.md documents `~/.claude/tachikoma.conf` and first-run onboarding
- [ ] USER-GUIDE.md describes auto-ship: AFK runs ship automatically, `/tachikoma done` is the fallback
- [ ] USER-GUIDE.md documents `/tachikoma done` and `/tachikoma resume` as explicit entry points (not bare `/tachikoma`)
- [ ] All command examples in USER-GUIDE.md match current invocation forms in SKILL.md

## Feedback loops

No automated tests — cross-reference USER-GUIDE.md against SKILL.md invocation table for consistency.

## Quality bar

production
