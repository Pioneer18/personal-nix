---
status: open
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# Tachikoma: Add /tachikoma sitrep for mid-queue-drain status

During a long `/tachikoma queue` drain there's no way to ask "where are we?" from another session — `/tachikoma status` is per-worktree telemetry and `.last-queue-run.md` only exists after the drain finishes. Add a `sitrep` subcommand backed by a state file the driver writes at each phase boundary.

## Goal

Tachikoma is done when `/tachikoma queue` writes `~/.tachikoma/queue-drain.state` (atomic write, frontmatter + body schema per spec) at each phase boundary during a drain, removes it on clean exit, and `/tachikoma sitrep` (callable from any cwd and any session) renders a narrative status report from that file augmented with PID liveness, current worktree dirty state, and a tail of the current item's `.tachikoma/log`. When no state file exists, sitrep reports "no active queue drain" with a pointer to the last-run summary.

## Files in scope

skills/tachikoma/SKILL.md

## Files out of scope

skills/tachikoma/tachikoma.sh.tmpl
skills/tachikoma/ship.md.tmpl
skills/tachikoma/prompt.md.tmpl
skills/tachikoma/AGENT-BRIEF.tmpl
skills/work-queue/SKILL.md

## Stop condition

- [ ] SKILL.md documents the `~/.tachikoma/queue-drain.state` schema (frontmatter fields: session_pid, started_at, caffeinated, totals, current_slug, current_position, current_phase, current_worktree, phase_started_at, last_pr; body sections: Upcoming, Notes)
- [ ] SKILL.md specifies atomic write (write-temp + rename) and that the file is removed on clean exit of queue drain
- [ ] SKILL.md threads state-file writes into queue drain Step 2 at each phase boundary (a print-header, d status-flip, e scaffold, f launch, h ship sub-steps, i mark-done)
- [ ] SKILL.md adds a `/tachikoma sitrep` subcommand section with: read state file → check session_pid liveness → git status --porcelain on current_worktree → tail of current worktree's .tachikoma/log → render narrative report
- [ ] sitrep section specifies the "no active queue drain" path when state file is missing, with pointer to .last-queue-run.md
- [ ] sitrep section specifies the "orchestrator crashed" path when session_pid is dead while state file exists
- [ ] sitrep section states the subcommand is callable from any cwd and any session
- [ ] SKILL.md frontmatter description, invocation table (line 36-area), and any trigger lists are updated to include `sitrep`

## Feedback loops

No automated tests — verify by re-reading SKILL.md and confirming: (1) the state-file schema is internally consistent, (2) every queue-drain step that should write is wired, (3) the sitrep section is self-contained and could be executed by a fresh Claude session without re-reading queue-drain context, (4) all trigger/invocation references list `sitrep`.

## Quality bar

production
