---
status: done
target_repo: /Users/pioneer/Projects/personal-nix
github_issue: Pioneer18/personal-nix#2
failure_count: 0
last_updated: 2026-05-10
---

# tachikoma: merge plan summary and prompt review into one confirmation

Combine the two-step approval flow (plan summary "Proceed?" + prompt review "Launch?") into a single combined view and single approval prompt.

## Goal

Modify `skills/tachikoma/SKILL.md` so that Phase 1 grill summary and Phase 4 prompt review are collapsed into a single combined confirmation. One approval instead of two.

## Files in scope

- `skills/tachikoma/SKILL.md`

## Files out of scope

- `mcps/**`
- `wiki/work-requests/**`
- `skills/tachikoma/tachikoma.sh.tmpl`
- `skills/tachikoma/prompt.md.tmpl`
- `skills/tachikoma/AGENT-BRIEF.tmpl`

## Stop condition

- User sees one combined view: goal, quality bar, scope, stop condition, iteration mode, and key prompt sections
- Single approval prompt: "Launch the AFK loop (cap N)?" or "Launch foreground loop?"
- No separate "Proceed with this plan?" step

## Feedback loops

- `grep -n "Approved\|Launch\|prompt review\|Phase 4\|Phase 1" skills/tachikoma/SKILL.md | head -20`
- `cat skills/tachikoma/SKILL.md | wc -l`

## Quality bar

production
