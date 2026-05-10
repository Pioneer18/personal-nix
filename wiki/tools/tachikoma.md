---
title: "Tachikoma — autonomous AI coding loop"
tags: [skill, agent, afk, tachikoma, claude-code, github, worktree, concurrent]
last_updated: "2026-05-10"
summary: "Pocock's Tachikoma Wiggum loop, adapted for this machine. `/tachikoma` grills, creates a sibling git worktree, runs a capped `claude -p` loop, then walks you through merge/PR/issue-close. Multiple tachikomas can run concurrently in the same repo. Three task sources, full crash-recovery."
category: agent-dev
link: "~/projects/personal-nix/skills/tachikoma/README.md"
user_guide: "~/projects/personal-nix/skills/tachikoma/USER-GUIDE.md"
---

Autonomous AFK coding on any git repo. See the [user guide](../../skills/tachikoma/USER-GUIDE.md) for plain-English feature walkthrough, or the [canonical README](../../skills/tachikoma/README.md) for design decisions, file layout, and known gaps.

**Three task-source modes**:
- `/tachikoma` — local PRD (`plans/prd.json`)
- `/tachikoma --remote` — greenfield, publishes PRD as GitHub issues via `to-prd` + `to-issues`
- `/tachikoma --issue <ref>` — uses an existing GitHub issue body as the PRD

**Queue modes**:
- `/tachikoma queue` — drain local work-request queue sequentially (full Phases 1–6 per item, batch prefs set once)
- `/tachikoma queue <repo>` — GitHub-sourced drain: fetches `ready-for-agent AND NOT agent-running` issues from `<repo>` (`org/repo`), auto-creates linked work_requests for any without one, then runs normal drain. Fires a macOS HITL notification + terminal summary when no `ready-for-agent` issues remain.

**GitHub label lifecycle** (issue-linked runs only):
- **Phase 2.5** (before worktree scaffolding): applies `agent-running`, removes `ready-for-agent` — optimistic distributed claim. Verifies the label stuck before proceeding (concurrent-agent guard).
- **Phase 6** (after PR/completion): applies `ready-for-review`, removes `agent-running` — whether or not a PR was opened.
- **Failure**: removes `agent-running`, restores `ready-for-agent` (< 2 failures) or applies `needs-triage` (≥ 2). Deliberate stop also reverts to `ready-for-agent` without bumping `failure_count`.

**Worktree model**: Every `/tachikoma` creates a sibling git worktree at `<main-parent>/<repo>-tachikoma-<slug>/` and works inside it. Lets multiple tachikomas run on the same codebase in parallel — each in its own branch, working directory, and `.tachikoma/` state. Main repo can stay dirty during runs. Discovery is per-repo via `git worktree list`; no global registry.

**Run lifecycle**:
1. **Grill** for goal, files in/out of scope, quality bar, mode/cap, feedback loops. Output includes the worktree path for approval before creation.
2. **Scaffold** — `git worktree add <wt-path> -b tachikoma/<slug> <base-branch>`; render `<wt>/.tachikoma/tachikoma.sh` + `prompt.md`; write `<wt>/.tachikoma/base_branch` for Phase 6 to read.
3. **Approve** the rendered prompt (mandatory review before launch).
4. **Loop** runs in the worktree (`--once` foreground or `--afk N` backgrounded via `nohup`/`disown`). Per-iteration milestone banners stream to log.
5. **Phase 6** auto-runs at sentinel: locates the base-worktree, refuses if dirty, squash-merges via `git -C <base-wt>`, single combined cleanup prompt for worktree+branch, optional PR, optional issue close.
6. **Phase R** recovers interrupted runs: `/tachikoma` (or `/tachikoma resume`) detects recoverable worktrees and offers Resume / Review / Restart per worktree.

**Lifecycle subcommands** (gain picker semantics when >1 loop is in play):
- `/tachikoma done` (`<slug>`?) — manually trigger Phase 6; picker if >1 complete
- `/tachikoma resume` (`<slug>`?) — manually trigger Phase R; picker if >1 recoverable
- `/tachikoma status` (`/tachikoma t`, `<slug>`?) — read-only. No args: compact summary table across all tachikoma worktrees in the repo. With slug: drill into one.
- `/tachikoma stop` (`<slug>`? or `--all`) — SIGTERM. Cwd-implicit if cwd is a tachikoma worktree; picker if >1 running.

**What's enforced in every iteration**:
- Tests must exist for new behavior (write one if missing before commit)
- Feedback loops (typecheck/test/lint) must pass before commit
- Single-feature-per-iteration constraint
- Append-only `progress.txt`, atomic git commit per task
- Per-iteration `✓ MILESTONE` banner streamed to `.tachikoma/run.log` (visible glance progress markers)
