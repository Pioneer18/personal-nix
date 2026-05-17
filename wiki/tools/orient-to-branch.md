---
title: "orient-to-branch"
summary: "One-pass orientation to the current git branch — commits, PR, linked GitHub issue, PROXY work request, Jira ticket, AGENTS/CLAUDE/ADR docs, code under the diff"
category: "skill"
tags: [git, branch, orientation, claude-skill, pr, github, proxy, jira]
link: "~/projects/personal-nix/skills/orient-to-branch/SKILL.md"
last_updated: "2026-05-13"
---

Front-loads everything you need to know about an unfamiliar (or paused) branch before writing code. Parallel reads across 8 sources:

1. branch name + `git status` (parses Jira key, GitHub issue ref, or kebab slug)
2. commits since base branch (`dev → develop → main → master`, first that exists)
3. PR via `gh pr view` (description, recent reviews, failing checks)
4. linked GitHub issue via `gh issue view`
5. Jira ticket via Atlassian MCP (if available; otherwise notes the key)
6. PROXY work request matched by slug or `githubIssue` (skips cleanly if PROXY isn't running)
7. AGENTS.md / CLAUDE.md / docs/ARCHITECTURE.md / docs/adr/ at repo root and package level
8. files in the diff (full read, one level of import/caller context)

**Output:** 4-line synthesis — Purpose / Status / Blockers / Next — then offers to dive in.

**Invocation:** `/orient-to-branch`, or natural-language ("orient to this branch", "catch me up", "what's going on with this branch").

**Anti-patterns:** no fabrication when a tool's unavailable; no full-repo reads; no proposed changes during orientation (read-only by design).
