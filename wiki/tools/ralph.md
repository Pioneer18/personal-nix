---
title: "Ralph — autonomous AI coding loop"
tags: [skill, agent, afk, ralph, claude-code, github]
last_updated: "2026-05-10"
summary: "Pocock's Ralph Wiggum loop, adapted for this machine. `/ralph` grills, scaffolds, runs a capped `claude -p` loop, then walks you through merge/PR/issue-close. Three task sources, full crash-recovery."
category: agent-dev
link: "~/projects/personal-nix/skills/ralph/README.md"
---

Autonomous AFK coding on any git repo. See the [canonical README](../../skills/ralph/README.md) for invocation reference, design decisions, file layout, and known gaps.

**Three modes**:
- `/ralph <goal>` — local PRD (`plans/prd.json`)
- `/ralph --remote <goal>` — greenfield, publishes PRD as GitHub issues via `to-prd` + `to-issues`
- `/ralph --issue <ref>` — uses an existing GitHub issue body as the PRD

**Run lifecycle**:
1. **Grill** for goal, files in/out of scope, quality bar, mode/cap, feedback loops
2. **Scaffold** branch `ralph/<slug>` off HEAD, `.ralph/` runtime dir, rendered `ralph.sh` + `prompt.md`
3. **Approve** the rendered prompt (mandatory review before launch)
4. **Loop** runs (`--once` foreground or `--afk N` backgrounded via `nohup`/`disown`). Per-iteration milestone banners stream to log.
5. **Phase 6** auto-runs at sentinel: walks you through squash-merge → branch delete → optional PR → optional issue close (each step asks first)
6. **Phase R** recovers interrupted runs: `/ralph` in a repo with partial state offers Resume / Review / Restart

**Lifecycle subcommands**:
- `/ralph done` — manually trigger Phase 6
- `/ralph resume` — manually trigger Phase R
- `/ralph status` (`/ralph t`) — read-only telemetry on a running/finished loop
- `/ralph stop` — SIGTERM the running loop

**What's enforced in every iteration**:
- Tests must exist for new behavior (write one if missing before commit)
- Feedback loops (typecheck/test/lint) must pass before commit
- Single-feature-per-iteration constraint
- Append-only `progress.txt`, atomic git commit per task
- Per-iteration `✓ MILESTONE` banner streamed to `.ralph/run.log` (visible glance progress markers)
