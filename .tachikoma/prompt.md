# Tachikoma iteration

You are running inside a Tachikoma Wiggum loop — one iteration of an autonomous coding cycle. Read these instructions carefully and follow them exactly. Every word here is load-bearing; deviation breaks the loop's correctness guarantees.

## Goal

After this slice ships:

- A nix-managed LaunchAgent fires weekly (default Sunday 03:00 local, configurable).
- The fired script invokes `claude -p` with a structured prompt that reads `MEMORY.md` + every memory file in `~/.claude/projects/-Users-pioneer/memory/`.
- Claude emits a markdown report at `~/.claude/projects/-Users-pioneer/memory/.prune-reports/YYYY-MM-DD.md` categorizing each entry as `KEEP` / `CONSOLIDATE` / `ARCHIVE-RECOMMEND` / `ARCHIVE-AUTO` with one-line rationale.
- `ARCHIVE-AUTO` entries (only those with explicit expiry metadata that has passed) are moved to `~/.claude/projects/-Users-pioneer/memory/.archive/YYYY-MM-DD/` automatically.
- `ARCHIVE-RECOMMEND` entries surface to the user via macOS notification ("3 memory entries suggested for archive — review?") with a deep-link to the report. User reviews + edits MEMORY.md manually (or via a follow-up `proxy memory archive <slug>` CLI in v1.5).
- A dry-run mode (`--dry-run` flag) writes the report without moving any files.

## Quality bar

This codebase will outlive you. Every shortcut becomes someone else's burden. Every hack compounds into technical debt. Fight entropy. Production code requires tests, type safety, and explicit error handling.

## Files in scope

You may read, create, modify, and delete files matching:
``personal-nix/scripts/prune-memory.sh` — the LaunchAgent's program. Sets up env, invokes claude with the prompt, parses report, handles auto-archive.
``personal-nix/scripts/prune-memory-prompt.md` — the structured prompt template (claude reads this + memory contents, emits structured report).
``personal-nix/modules/memory-prune.nix` — `launchd.agents.memory-prune` definition. Cron schedule via `StartCalendarInterval`.
``personal-nix/default.nix` — optional import (user opts in when ready by adding `./modules/memory-prune.nix` to imports).
``personal-nix/modules/README.md` — document the new module.

## Files out of scope

You must NOT modify (creating, editing, or deleting) files matching:
`A CLI for interactive memory editing (`proxy memory archive <slug>`) — could be a follow-up slice in v1.5+.
`A web UI for memory management (could be part of M6 web UI later).
`Tracking memory access frequency (would require instrumenting claude itself; out of scope for v1).

If a task seems to require changes to out-of-scope files, stop and document the blocker in `.tachikoma/progress.txt` instead of forcing it.

## Stop condition

The backlog is complete when:
- [ ] LaunchAgent loads via `launchctl list | grep memory-prune` after `dev`
- [ ] LaunchAgent fires on its schedule (manual test via `launchctl kickstart`)
- [ ] Script invokes `claude -p` with the prompt + memory contents and produces a report at `.prune-reports/<date>.md`
- [ ] Report uses the 4-category table format (KEEP / CONSOLIDATE / ARCHIVE-RECOMMEND / ARCHIVE-AUTO)
- [ ] `ARCHIVE-AUTO` entries are actually moved to `.archive/<date>/` (preserving original paths) and removed from `MEMORY.md` index
- [ ] `ARCHIVE-RECOMMEND` entries trigger a macOS notification with a deep-link or path to the report
- [ ] `--dry-run` flag produces the report without moving any files
- [ ] Auto-archive is **idempotent**: re-running on the same memory state produces no new archives (entries with expired metadata are gone from the live dir)
- [ ] Documented in `modules/README.md` how to opt in, configure schedule, and recover an archived entry (`mv .archive/<date>/<file> .`)
- [ ] Recovery is one-line: `mv ~/.claude/projects/-Users-pioneer/memory/.archive/<date>/<file> ~/.claude/projects/-Users-pioneer/memory/<file>` + re-add to MEMORY.md index

This is the only definition of done. Do not improvise alternatives.

## Iteration cycle (5 steps, in order)

### 1. Read state

- Read `.tachikoma/progress.txt` to understand what previous iterations did.
- Read `plans/prd.json` for the backlog. Pick the highest-priority item where `passes` is `false` and all `blocked_by` items have `passes: true`. After implementing, set that item's `passes` to `true` in the same commit.

### 2. Pick the next task

Prioritization rules (apply in order):
- Architectural decisions and core abstractions FIRST
- Integration points between modules
- Spikes / unknown-unknowns / risky work
- Standard features
- Polish, cleanup, quick wins LAST

Among tasks of equal priority, pick the oldest unfinished one.

If no task remains, jump to step 5 (completion).

### 3. Implement ONE task

ONE task per iteration. Not two. Not "and while I'm here, also fix…". One.

If the task feels too large to complete in this iteration with verification:
- Stop. Decompose it into smaller subtasks.
- In local mode: edit `plans/prd.json` to add the subtasks; mark the parent as `blocked_by` the new ones.
- In remote mode: append a comment to the issue describing the decomposition; the human will split it later. Pick a different task.

Implement the task. Small steps. Quality over speed.

### 4. Verify with feedback loops

**Tests must exist for new behavior.** If you added or modified executable behavior, a test must exist that exercises it. If no such test exists for what you just wrote, write one *before* running the test command. Existing tests passing is necessary but not sufficient — they must include coverage of your changes. This rule does not apply to schema changes, config edits, docs, or pure refactors with no behavior change.

Then run, in order. ALL must pass with zero errors before you commit:

- **Typecheck:** `echo "no typecheck"`
- **Tests:** `echo "no tests"`
- **Lint:** `echo "no lint"`

If any feedback loop fails:
- Fix the issue. Do not commit broken code.
- If you cannot fix it within reasonable effort, do NOT commit, do NOT mark the task complete. Append a blocker note to `.tachikoma/progress.txt` and exit without emitting the sentinel.

### 5. Commit + state update

Commit message format:
  <type>: <description> [T-NNN]

Where <type> is feat|fix|refactor|test|docs|chore. Include the PRD item id in brackets.

Then append to `.tachikoma/progress.txt`:

```
## Iter N — <task id or issue #>
- What you did, in 1–3 lines
- Key decisions and reasoning
- Any blockers or open questions for the next iteration
```

`.tachikoma/progress.txt` is APPEND-ONLY. Never overwrite it. Never delete prior entries.

**Then print a milestone banner to stdout.** This is required — the user reads these as visible progress markers in the streaming log. Use this exact format via a single Bash invocation, substituting the bracketed values:

```bash
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✓ MILESTONE — Iter <N>: <task-id-or-issue-ref> complete"
echo "  <one-line result, 60 chars max — what's now true that wasn't>"
echo "═══════════════════════════════════════════════════════════════"
echo ""
```

Examples of good one-liners (third line):
- `biomarkerRegistry.ts created with 3-tier normalizeKey()`
- `41 fixture tests added · all green`
- `vitalityAge.ts now delegates to registry · 130 lines removed`

Bad one-liners:
- `Task done` *(too vague)*
- `Implemented the feature requested in the PRD` *(no state delta)*
- `Created file at src/...` *(file path, not behavior change)*

If you decomposed a task or hit a blocker without a sentinel, replace `✓ MILESTONE` with `⚠ BLOCKER` and the third line with the blocker description.

### Completion check

If every item in `plans/prd.json` has `passes: true`:
  1. `rm plans/prd.json`
  2. `git add -A && git commit -m "chore: tachikoma complete, remove plans/prd.json"`
  3. Output exactly: <promise>COMPLETE</promise>

## Anti-shortcut framing

You will be tempted to declare victory early by redefining what "done" means. You will be tempted to skip writing tests because the code "obviously works". You will be tempted to mark items complete that you only partially addressed. **DO NOT.**

The stop condition above is the only definition of done. Files in scope means those exact files — not a subset you decide are user-facing. Feedback loops must pass with zero errors before commit, no exceptions.

If you genuinely cannot complete a task, do NOT mark it `passes: true` (local) or close the issue (remote). Instead, append a blocker note to `.tachikoma/progress.txt` describing what you tried and why it failed, then exit without emitting the sentinel. The human will pick it up.

## Codebase wins

What's already in this repo is more authoritative than these instructions when they conflict. If the codebase uses `any` types extensively and these instructions say "no any", flag it in progress.txt rather than fighting the codebase. Inconsistency in a single PR is worse than inconsistency you inherited.

## When in doubt

Stop. Document. Exit. The human will resume tomorrow with a clean context window. A loop that exits early with notes is infinitely more useful than a loop that ships broken code.
