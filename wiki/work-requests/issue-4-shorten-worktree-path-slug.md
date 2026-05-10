---
status: done
target_repo: /Users/pioneer/Projects/personal-nix
github_issue: Pioneer18/personal-nix#4
failure_count: 0
last_updated: 2026-05-10
---

# tachikoma: shorten worktree path slug to avoid double repo-name prefix

Simplify the worktree slug format so the repo name and "tachikoma" don't appear twice in the path.

## Goal

Modify `skills/tachikoma/SKILL.md` so the worktree path slug drops the repo name from the slug portion (it's already in the parent directory name). Format: `<repo>-tachikoma-<issue-N>-<short-description>` where short-description is truncated to ~30 chars and the repo name is not repeated.

## Files in scope

- `skills/tachikoma/SKILL.md`

## Files out of scope

- `mcps/**`
- `wiki/work-requests/**`
- `skills/tachikoma/tachikoma.sh.tmpl`
- `skills/tachikoma/prompt.md.tmpl`
- `skills/tachikoma/AGENT-BRIEF.tmpl`

## Stop condition

- Worktree path never contains the repo name more than once
- "tachikoma" appears at most once in the path
- Slug is capped at a reasonable length (≤ 50 chars total after repo prefix)

## Feedback loops

- `grep -n "WORKTREE_PATH\|worktree.*slug\|slug.*worktree\|tachikoma-<slug" skills/tachikoma/SKILL.md | head -20`
- `cat skills/tachikoma/SKILL.md | wc -l`

## Quality bar

production
