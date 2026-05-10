---
status: grabbed
target_repo: /Users/pioneer/Projects/personal-nix
github_issue: Pioneer18/personal-nix#1
failure_count: 0
last_updated: 2026-05-10
---

# tachikoma: extract quality bar from issue body before asking

Before asking about quality bar in the Phase 1 grill, scan the issue body for the keywords `prototype`, `production`, or `library`. If found, pre-fill the value and skip the question. Surface the extracted value in the plan summary so the user can override if wrong.

## Goal

Modify `skills/tachikoma/SKILL.md` so that when running `/tachikoma --issue N`, the Phase 1 grill scans the issue body for quality bar keywords before asking the question. If found, pre-fill and skip the question; show the value in the plan summary with an override note.

## Files in scope

- `skills/tachikoma/SKILL.md`

## Files out of scope

- `mcps/**`
- `wiki/work-requests/**`
- `skills/tachikoma/tachikoma.sh.tmpl`
- `skills/tachikoma/prompt.md.tmpl`
- `skills/tachikoma/AGENT-BRIEF.tmpl`

## Stop condition

- Running `/tachikoma --issue N` on an issue containing "production" skips the quality bar question and pre-fills `production`
- The pre-filled value appears in the plan summary with a note it was extracted from the issue
- User can still override by editing the plan summary

## Feedback loops

- `grep -n "quality.bar\|Quality bar\|quality_bar" skills/tachikoma/SKILL.md | head -20`
- `cat skills/tachikoma/SKILL.md | wc -l`

## Quality bar

production
