---
title: "Tachikoma errors at iter N start despite iter N-1 work being committed"
tags: [tachikoma, runbook, dispatch, finalize, dirty-tree, gotcha]
last_updated: "2026-05-15"
---

# Tachikoma errors at iter N start despite iter N-1 work being committed

## Symptom

`mcp__tachikoma__tachikoma_status` reports a tachikoma as:

```json
{
  "status": "error",
  "pid": null,
  "iter": "2/12",
  "lastProgress": "Sentinel: COMPLETE."
}
```

Hallmarks:

- `status: error` but `lastProgress` indicates work near or at completion.
- Iter counter shows a low value (typically 2-3 of cap).
- Worktree contains a commit with the substantive work (e.g. the slice's feat commit).
- **No PR was opened** — the wrapper never reached the ship phase.
- One or more **untracked** files in the worktree (`git status` shows `??` rows) that look like side-effects rather than declared scope (orphan `pnpm-lock.yaml` in an npm-only repo, generated `.next/` artifacts, etc.).

Confirmed on 2026-05-15 with `proxy-work-request-dispatch-button` — the dispatch code committed at `379bc76` was sound and ultimately merged as PR #56, but the tachikoma never auto-shipped it.

## Root cause

`~/.claude/skills/tachikoma/tachikoma.sh.tmpl` lines 231-235:

```bash
# Bail if working tree is dirty at iteration start.
if [ -n "$(git status --porcelain)" ]; then
  echo "[tachikoma] working tree dirty at start of iter $ITER. Bailing — manual cleanup required." | tee -a "$LOG_FILE" >&2
  OUTCOME="error"
  exit 1
fi
```

`git status --porcelain` includes untracked files (`??` prefix) in its output. Any stray file left behind by a previous iteration's claude session — even one that has nothing to do with the actual scope — trips this check and the loop exits with `OUTCOME="error"` before:

1. The current iteration's `claude -p` even runs.
2. The sentinel string from the *previous* iteration's progress is re-evaluated.
3. The ship phase (lines 266-296) ever fires.

The `lastProgress: "Sentinel: COMPLETE."` value is narrative text written by the previous iteration's claude into `.tachikoma/progress.txt` — *not* the actual sentinel match. The literal sentinel string is template-substituted into `tachikoma.sh` at scaffold time (`{{SENTINEL}}` on line 9); claude's progress narrative happens to contain the word "Sentinel" without matching the real sigil.

## Reproduce

1. Dispatch any tachikoma against a target repo where claude's session is likely to invoke a package manager (anything with `apps/web/` and Next.js works well).
2. Set the cap > 1.
3. After iter 1 completes its commit, manually `touch <worktree>/apps/web/pnpm-lock.yaml`.
4. Wait for iter 2 to start — it will bail immediately with `OUTCOME="error"`.

## Fix (script side)

Two independent improvements to `tachikoma.sh.tmpl`:

1. **Distinguish dirty-modified-tracked (fatal) from dirty-untracked-only (warn)** at the iter-start check. Untracked files from a previous iter's side-effects should not kill the loop; modified-but-uncommitted tracked files indicate real corruption and should still bail.

   ```bash
   DIRTY="$(git status --porcelain)"
   if [ -n "$DIRTY" ]; then
     TRACKED_DIRTY="$(echo "$DIRTY" | grep -v '^??' || true)"
     if [ -n "$TRACKED_DIRTY" ]; then
       echo "[tachikoma] tracked files dirty at start of iter $ITER. Bailing." | tee -a "$LOG_FILE" >&2
       OUTCOME="error"; exit 1
     fi
     echo "[tachikoma] untracked stray files at start of iter $ITER (warning):" | tee -a "$LOG_FILE" >&2
     echo "$DIRTY" | tee -a "$LOG_FILE" >&2
   fi
   ```

2. **Sentinel-aware bail handling**. If `.tachikoma/progress.txt` last line contains the actual `$SENTINEL` string, treat the dirty state as "iter completed work, just had cleanup debris" — fire the ship phase before bailing. (Belt-and-suspenders against false `lastProgress` values.)

## Fix (prompt / skill side)

Add a hard rule to `prompt.md.tmpl`:

> Never invoke a package manager (`npm install`, `pnpm install`, `yarn install`, `bundle install`, etc.) unless the work-request explicitly says to. If you must, use the manager declared in the root `package.json`'s `packageManager` field (or the equivalent for non-Node ecosystems) — never a different one. Stray lockfiles from the wrong manager will trip the iter-start dirty-tree check and the loop will error.

This addresses the *generation* of the stray file, not just the symptom.

## Workaround until fixed

After the symptom triggers:

1. `cd` into the worktree.
2. `git status` to inventory the stray untracked files.
3. Decide per file: `rm` if it's clearly a side-effect (orphan lockfile, build artifact), `git add` + amend if it's legitimate output.
4. Manually run the ship phase: `nohup ./.tachikoma/tachikoma.sh --once > /tmp/<slug>.ship.log 2>&1 &` (won't quite work because the loop expects to be entering iter 1, not iter N; easier is just `gh pr create` by hand).
5. After the PR is merged: remove the worktree (`git worktree remove --force <path>`), delete the local tachikoma branch, flip the work-request frontmatter `status: open` → `status: done` and add the `shipped_pr` URL.

This was the path taken for `proxy-work-request-dispatch-button` on 2026-05-15.

## See also

- `~/projects/personal-nix/wiki/work-requests/fix-tachikoma-dispatch-bugs.md` — work-request tracking this fix (Bug 3 is this runbook's subject)
- `~/.claude/skills/tachikoma/tachikoma.sh.tmpl` — the script template that gets dropped into each worktree as `.tachikoma/tachikoma.sh`
- `~/.claude/skills/tachikoma/prompt.md.tmpl` — the prompt template; the package-manager hard rule lands here
