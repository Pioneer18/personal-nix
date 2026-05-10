---
status: done
target_repo: /Users/pioneer/Projects/personal-nix
github_issue: Pioneer18/personal-nix#5
failure_count: 0
last_updated: 2026-05-10
---

# tachikoma: handle missing label vocab gracefully on fresh repos

Move label vocab setup to the very start of the run (before Phase 1 grill) so it never interrupts the flow mid-run.

## Goal

Modify `skills/tachikoma/SKILL.md` so that the label existence check and silent creation happens as the first step before Phase 1, not mid-run. Missing labels are created silently with a single log line.

## Files in scope

- `skills/tachikoma/SKILL.md`

## Files out of scope

- `mcps/**`
- `wiki/work-requests/**`
- `skills/tachikoma/tachikoma.sh.tmpl`
- `skills/tachikoma/prompt.md.tmpl`
- `skills/tachikoma/AGENT-BRIEF.tmpl`

## Stop condition

- Label check and creation happens before Phase 1, not mid-run
- Missing labels are created silently with a single log line
- No confirmation prompt for label creation
- If all labels already exist, no output

## Feedback loops

- `grep -n "label.*vocab\|ready-for-agent\|agent-running\|precondition.*label\|label.*check" skills/tachikoma/SKILL.md | head -20`
- `cat skills/tachikoma/SKILL.md | wc -l`

## Quality bar

production
