---
status: grabbed
target_repo: ~/projects/personal-nix
last_updated: 2026-05-10
---

# Tachikoma — status reporting and lifecycle bugs

Four concrete bugs surfaced during a `/tachikoma done` session on 2026-05-10 (healthbite issue #139). All relate to how Tachikoma reports status and how it cleans up after itself.

## Context

A tachikoma ran AFK on `ralph/issue-139-extract-metric-normalizer` in the healthbite repo. It completed all 7 criteria and wrote the COMPLETE sentinel. When the user checked `/tachikoma status` (via the MCP tool), the run appeared as `running` rather than `complete`, and the tool showed heavily duplicated entries for other repos' worktrees. Phase 6 also had no `.tachikoma/outcome` or `.tachikoma/base_branch` files to work from.

## Goal

Tachikoma is done when all four bugs below are fixed, with manual verification for each.

## Files in scope

- `skills/tachikoma/tachikoma.sh.tmpl`
- `mcps/tachikoma-mcp/index.ts`

## Files out of scope

- `skills/tachikoma/prompt.md.tmpl`
- `skills/tachikoma/AGENT-BRIEF.tmpl`
- `wiki/`

## Stop condition

### Bug 1 — bash process lingers after COMPLETE sentinel

**Observed:** After the loop wrote `COMPLETE sentinel.` to progress.txt and exited the while loop, the bash process (PID 92724) remained alive with 0:00.01 CPU. `ps -p <pid>` showed `bash .tachikoma/tachikoma.sh --afk 3`. The MCP tool saw the PID alive and reported `status: running`.

**Fix:** After the sentinel check fires and the script finishes its completion block (write outcome, fire notification, etc.), it must `exit 0` explicitly and promptly. The script should not stay alive after the completion block runs. Verify with: after the COMPLETE sentinel fires, `ps -p <pid>` should return non-zero within 5 seconds.

---

### Bug 2 — `.tachikoma/outcome` file not written

**Observed:** `/Users/pioneer/Projects/healthbite/.tachikoma/outcome` did not exist after the run completed. Phase 6 of the skill reads this file to detect `complete` vs `cap` vs `error`. Without it, the skill can't auto-route to Phase 6.

**Fix:** In `tachikoma.sh.tmpl`, wherever the sentinel check fires, write `echo "complete" > "$OUTCOME_FILE"` before the completion notification block. Similarly, ensure `cap`, `error`, and `stopped` are written on their respective exit paths. The `OUTCOME_FILE` variable should be defined alongside `PID_FILE`, `LOG_FILE`, etc. (i.e., `OUTCOME_FILE="$TACHIKOMA_DIR/outcome"`). Verify: after a `--once` run with a sentinel, `cat .tachikoma/outcome` outputs `complete`.

---

### Bug 3 — `.tachikoma/base_branch` file not written

**Observed:** `/Users/pioneer/Projects/healthbite/.tachikoma/base_branch` did not exist. Phase 6 reads this to know the merge target. Without it, Phase 6 must ask the user (adds friction, error-prone for AFK runs that span sessions).

**Fix:** This file is supposed to be written during scaffold (Phase 3 of the skill), not by the bash script. However, the bash script can defensively detect and record it too. Primary fix: audit `SKILL.md` Phase 3 step 5 to confirm `base_branch` is written during `git worktree add` scaffold, and add a check — if the file is missing when Phase 6 runs, warn the user loudly rather than silently failing. Secondary fix: the bash script template can write `git -C "$REPO" rev-parse --abbrev-ref HEAD > "$TACHIKOMA_DIR/base_branch"` at startup as a belt-and-suspenders guard (only if the file doesn't already exist). Verify: after scaffold, `.tachikoma/base_branch` contains a single branch name with no trailing newline issues.

---

### Bug 4 — `ralph_status` MCP shows duplicate worktree entries

**Observed:** `ralph_status` returned 13 entries for what was effectively 4 unique ralph runs (1 healthbite + 3 personal-nix). Each personal-nix worktree appeared 4 times — once for each other personal-nix worktree's perspective. The MCP tool appears to be enumerating worktrees from each worktree's `.git` dir rather than deduplicating by canonical worktree path.

**Fix:** The MCP tool's `tachikoma_status` implementation needs to deduplicate by `worktree` path (the absolute path field) before returning results. Each unique worktree path should appear exactly once. This is a bug in the MCP server, not in `tachikoma.sh.tmpl` — fix it in the personal-nix MCP server source (wherever `tachikoma_status` is implemented).

---

## Quality bar

production — these are correctness bugs in the core lifecycle; no shortcuts.

## Feedback loops

- `bash -n skills/tachikoma/tachikoma.sh.tmpl` — syntax check the template
- Manual: render the template into a scratch repo, run `--once` with a fast-exiting sentinel, verify outcome file + process exit
