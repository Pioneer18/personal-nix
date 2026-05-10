---
title: "Ralph — autonomous AI coding loop"
tags: [skill, agent, afk, ralph, claude-code, github, worktree, concurrent]
last_updated: "2026-05-10"
summary: "Pocock's Ralph Wiggum loop, adapted for this machine. `/ralph` grills, creates a sibling git worktree, runs a capped `claude -p` loop, then walks you through merge/PR/issue-close. Multiple ralphs can run concurrently in the same repo. Three task sources, full crash-recovery."
category: agent-dev
link: "~/projects/personal-nix/skills/ralph/README.md"
---

Autonomous AFK coding on any git repo. See the [canonical README](../../skills/ralph/README.md) for invocation reference, design decisions, file layout, and known gaps.

**Three modes**:
- `/ralph <goal>` — local PRD (`plans/prd.json`)
- `/ralph --remote <goal>` — greenfield, publishes PRD as GitHub issues via `to-prd` + `to-issues`
- `/ralph --issue <ref>` — uses an existing GitHub issue body as the PRD

**Worktree model**: Every `/ralph` creates a sibling git worktree at `<main-parent>/<repo>-ralph-<slug>/` and works inside it. Lets multiple ralphs run on the same codebase in parallel — each in its own branch, working directory, and `.ralph/` state. Main repo can stay dirty during runs. Discovery is per-repo via `git worktree list`; no global registry.

**Run lifecycle**:
1. **Grill** for goal, files in/out of scope, quality bar, mode/cap, feedback loops. Output includes the worktree path for approval before creation.
2. **Scaffold** — `git worktree add <wt-path> -b ralph/<slug> <base-branch>`; render `<wt>/.ralph/ralph.sh` + `prompt.md`; write `<wt>/.ralph/base_branch` for Phase 6 to read.
3. **Approve** the rendered prompt (mandatory review before launch).
4. **Loop** runs in the worktree (`--once` foreground or `--afk N` backgrounded via `nohup`/`disown`). Per-iteration milestone banners stream to log.
5. **Phase 6** auto-runs at sentinel: locates the base-worktree, refuses if dirty, squash-merges via `git -C <base-wt>`, single combined cleanup prompt for worktree+branch, optional PR, optional issue close.
6. **Phase R** recovers interrupted runs: `/ralph` (or `/ralph resume`) detects recoverable worktrees and offers Resume / Review / Restart per worktree.

**Lifecycle subcommands** (gain picker semantics when >1 loop is in play):
- `/ralph done` (`<slug>`?) — manually trigger Phase 6; picker if >1 complete
- `/ralph resume` (`<slug>`?) — manually trigger Phase R; picker if >1 recoverable
- `/ralph status` (`/ralph t`, `<slug>`?) — read-only. No args: compact summary table across all ralph worktrees in the repo. With slug: drill into one.
- `/ralph stop` (`<slug>`? or `--all`) — SIGTERM. Cwd-implicit if cwd is a ralph worktree; picker if >1 running.

**What's enforced in every iteration**:
- Tests must exist for new behavior (write one if missing before commit)
- Feedback loops (typecheck/test/lint) must pass before commit
- Single-feature-per-iteration constraint
- Append-only `progress.txt`, atomic git commit per task
- Per-iteration `✓ MILESTONE` banner streamed to `.ralph/run.log` (visible glance progress markers)
