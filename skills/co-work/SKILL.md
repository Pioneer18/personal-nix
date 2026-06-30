---
name: co-work
description: Safely add a slice of work to a shared, long-lived branch that other Claude sessions may be editing concurrently in the same working directory, then extract just that slice into its own branch off develop for a PR — without disturbing other sessions' in-progress, uncommitted changes, and without creating a worktree for the ongoing work itself. Use when starting work on a branch another actor might also be on, when told to "be conscious you're on a shared branch", or when a completed slice needs to move from a shared root branch to a clean feature branch.
---

# Co-Work

A root branch (e.g. `patient-web-3-expansion`) is shared scratch space: several sessions edit it concurrently, uncommitted, in the *same* working directory. Nobody ever commits to it. Each session, when its slice is done, peels its own files off into a fresh branch off `develop` and leaves the root branch clean for the next session. This only works if each session stays scoped to its own files — never touch what you didn't create.

## Before you start editing

1. `git branch --show-current` — confirm you're on the shared root branch, not develop.
2. `git status` — note any *existing* uncommitted/untracked files. Those belong to other sessions. Do not edit, revert, or stage them.
3. If your task will require switching branches, rebasing, or any operation that rewrites the working tree (not just adding/editing files), stop and use a worktree instead (`EnterWorktree` / `git worktree add`) — this skill only covers the "edit files in place" case.
4. Start a running list of every file you create or modify this session. You need this list later — `git status` at extraction time will show everyone's changes mixed together, not just yours.

## While editing

- Touch only files relevant to your slice. If your task requires editing a file another session is also actively changing, stop and ask the user — that's the overlap case this whole pattern assumes won't happen.
- Never commit, stash (unscoped), `git checkout .`, `git clean`, or `git reset --hard` in this directory. Any of those can destroy another session's uncommitted work.

## When your slice is done: extract it

Work from your tracked file list (`$FILES`, space-separated paths).

```bash
# 1. Scope a stash to just your files (tracked + new), leaving everything else in the
#    working tree untouched. This both captures AND cleans up your changes in one step.
git stash push --include-untracked -m "co-work: <slice description>" -- $FILES

# 2. Fetch latest develop and create a disposable worktree off it — this worktree is
#    only a landing pad for the commit, not where you do future work.
git fetch origin develop
git worktree add ../co-work-tmp -b <type>/<ticket-id>-<short-description> origin/develop

# 3. Bring your stashed changes into the new branch (stash is shared across worktrees).
(cd ../co-work-tmp && git stash apply)

# 4. Review, commit, push from the worktree.
(cd ../co-work-tmp && git diff --stat && git add -A && git commit -m "<type>(scope): <description> [TICKET-ID]" && git push -u origin HEAD)

# 5. Remove the disposable worktree and drop the stash now that it's landed.
git worktree remove ../co-work-tmp
git stash drop
```

Open the PR from the new branch as usual. The root branch's working directory was never checked out to a different ref and never touched outside `$FILES` — other sessions' uncommitted work is exactly as they left it.

## If the scoped stash apply conflicts

This means develop has moved in a way that overlaps your files since you branched off mentally. Resolve conflicts in `../co-work-tmp` only — never resolve by touching the root branch's working directory. If it's messy, fall back to a manual patch: `git stash show -p > /tmp/co-work.patch` then `git apply` (or `git apply -3`) in the worktree.

## Safety rules

- Never run a pathspec-less `git stash`, `git checkout .`, `git clean -fd`, or `git reset --hard` in a shared root branch's directory.
- Never `git checkout`/`git switch` the shared directory to another branch — that rewrites every tracked file to match the target branch, wiping other sessions' in-progress edits.
- The disposable worktree is for *landing the commit*, not for doing the slice's actual work — if you find yourself wanting to develop there long-term, that's a sign this task needed its own worktree from the start.
