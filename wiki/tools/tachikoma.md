---
title: "Tachikoma — autonomous AI coding loop"
tags: [skill, agent, afk, tachikoma, claude-code, github, worktree, concurrent]
last_updated: "2026-05-11"
summary: "Pocock's Tachikoma Wiggum loop, adapted for this machine. Zero-friction: reads ~/.claude/tachikoma.conf, launches immediately, runs fully autonomously through squash-merge + PR. Only human touchpoint is reviewing the PR on GitHub."
category: agent-dev
link: "~/projects/personal-nix/skills/tachikoma/README.md"
user_guide: "~/projects/personal-nix/skills/tachikoma/USER-GUIDE.md"
---

Autonomous AFK coding on any git repo. `/tachikoma --issue 138` → PR on GitHub. That's it. See the [user guide](../../skills/tachikoma/USER-GUIDE.md) for details or the [README](../../skills/tachikoma/README.md) for design decisions.

**One-time setup**: create `~/.claude/tachikoma.conf` with your defaults (quality bar, cap, allowed tools). All runs inherit from it silently.

**Three task-source modes**:
- `/tachikoma` — local PRD (`plans/prd.json`)
- `/tachikoma --remote` — greenfield, publishes PRD as GitHub issues via `to-prd` + `to-issues`
- `/tachikoma --issue <ref>` — uses an existing GitHub issue body as the PRD

**Queue modes**:
- `/tachikoma queue` — drain local work-request queue sequentially (full Phases 1–6 per item, batch prefs set once)
- `/tachikoma queue <repo>` — GitHub-sourced drain: fetches `ready-for-agent AND NOT agent-running` issues from `<repo>` (`org/repo`), auto-creates linked work_requests for any without one, then runs normal drain. Fires a macOS HITL notification + terminal summary when no `ready-for-agent` issues remain.

**GitHub label lifecycle** (issue-linked runs only):
- **Phase 2.5** (before worktree scaffolding): applies `agent-running`, removes `ready-for-agent` — optimistic distributed claim.
- **Phase 6** (automatic): applies `ready-for-review`, removes `agent-running` — always runs after squash-merge.
- **Failure**: removes `agent-running`, restores `ready-for-agent` (< 2 failures) or applies `needs-triage` (≥ 2). Deliberate stop reverts to `ready-for-agent` without bumping `failure_count`.

**Worktree model**: Every `/tachikoma` creates a sibling git worktree at `<main-parent>/<repo>-tachikoma-<slug>/`. Multiple tachikomas can run concurrently on the same codebase — each in its own branch, working directory, and `.tachikoma/` state. Main repo can stay dirty during runs.

**Run lifecycle** (fully autonomous — no prompts after launch):
1. **Pre-flight** — reads `~/.claude/tachikoma.conf`, fetches issue (in `--issue` mode), auto-detects feedback loops, prints one-line launch summary.
2. **Scaffold** — creates worktree, renders `tachikoma.sh` + `prompt.md`, commits scaffolding.
3. **Loop** — `--once` (foreground) or `--afk N` (backgrounded). Errors auto-retry once; second failure pushes a draft PR.
4. **Phase 6 (automatic)** — squash-merge → delete worktree + branch → push → open PR → close issue. All decisions logged in PR body. Only stops for merge conflicts.

**Lifecycle subcommands**:
- `/tachikoma done` (`<slug>`?) — manually trigger Phase 6; picker if >1 complete
- `/tachikoma resume` (`<slug>`?) — manually trigger Phase R; picker if >1 recoverable
- `/tachikoma status` (`/tachikoma t`, `<slug>`?) — read-only telemetry
- `/tachikoma stop` (`<slug>`? or `--all`) — SIGTERM

**What's enforced in every iteration**:
- Tests must exist for new behavior
- Feedback loops (typecheck/test/lint) must pass before commit
- Single-feature-per-iteration constraint
- Append-only `progress.txt`, atomic git commit per task
- Per-iteration `✓ MILESTONE` banner streamed to `.tachikoma/run.log`
