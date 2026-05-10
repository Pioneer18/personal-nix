---
status: done
target_repo: /Users/pioneer/Projects/personal-nix
github_issue: Pioneer18/personal-nix#3
failure_count: 0
last_updated: 2026-05-10
---

# tachikoma: pre-authorize nohup/disown for afk launch or guide user to do so upfront

Two complementary fixes for the blocked nohup launch problem in AFK mode: immediate guidance when blocked + proactive check before launch attempt.

## Goal

Modify `skills/tachikoma/SKILL.md` so that: (1) when a nohup AFK launch is blocked, Tachikoma immediately offers to add the permission and prints the exact `!` command; (2) before the launch attempt, Tachikoma proactively checks `.claude/settings.json` for nohup permission and warns if missing.

## Files in scope

- `skills/tachikoma/SKILL.md`

## Files out of scope

- `mcps/**`
- `wiki/work-requests/**`
- `skills/tachikoma/tachikoma.sh.tmpl`
- `skills/tachikoma/prompt.md.tmpl`
- `skills/tachikoma/AGENT-BRIEF.tmpl`

## Stop condition

- User is never surprised by a blocked launch without a clear next step
- The `!` fallback command is always printed when blocked
- Proactive permission check surfaces the issue before the launch attempt

## Feedback loops

- `grep -n "nohup\|disown\|permission\|update-config\|caffeinate" skills/tachikoma/SKILL.md | head -20`
- `cat skills/tachikoma/SKILL.md | wc -l`

## Quality bar

production
