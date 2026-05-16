---
status: open
priority: 3
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-15
---

# Fix tachikoma dispatch + finalize bugs

> Seeded from `wiki/seeds/fix-tachikoma-dispatch-bugs.md`. Body below is the original seed; treat as
> rough — needs grilling + scope refinement before tachikoma dispatch.

Two bugs surfaced while attempting to dispatch `proxy-27-queue-epic-core` via Tachikoma on 2026-05-14. Both have workarounds but cause real friction.

## Bug 1 — MCP `tachikoma_dispatch` doesn't accept slug

**Symptom**: `mcp__tachikoma__tachikoma_dispatch` only picks "next open + ready" work-request from `~/projects/personal-nix/wiki/work-requests/`. No way to specify a target slug. When called intending to grab `proxy-27`, it grabbed `auto-memory-pruner` instead.

**Reproduce**:
```
mcp__tachikoma__tachikoma_dispatch()
→ returns: {"slug":"auto-memory-pruner", ...}  // not the one we wanted
```

**Workaround**: Call REST endpoint directly:
```bash
curl -X POST http://127.0.0.1:4321/api/dispatch \
  -H "Content-Type: application/json" \
  -d '{"work_request_slug":"<slug>","target_repo":"<absolute-path>"}'
```

**Fix**: Add optional `slug` parameter to MCP tool signature. When provided, pass through to daemon's `/api/dispatch` endpoint with the right field name (`work_request_slug`). Also add optional `target_repo` parameter — currently required by REST but defaulted/inferred in MCP.

**Source**: MCP definition lives at `~/projects/personal-nix/mcps/tachikoma/` (verify during fix; might be in tachikoma-starter daemon).

## Bug 2 — Daemon `/api/dispatch` errors after scaffold

**Symptom**: REST call to `POST http://127.0.0.1:4321/api/dispatch` with valid `work_request_slug` + `target_repo` returns:

```json
{"error":"git commit -m chore: scaffold tachikoma loop for proxy-27-queue-epic-core (cwd=\"/Users/pioneer/Projects/tachikoma-starter-tachikoma-proxy-27-queue-epic-core\") failed: "}
```

Worktree IS scaffolded correctly: `.tachikoma/` dir created with `tachikoma.sh`, `prompt.md`, `ship.md`, `ship_body.txt`, `base_branch`, `pr_target_branch`. `git status` in the worktree shows clean (everything committed). But the daemon considers dispatch failed, so the AFK loop is **never auto-launched**.

**Hypothesis**: After scaffolding the `.tachikoma/` files + an initial commit, the daemon attempts a second `git commit` (perhaps for a marker file, or as a redundant safeguard). When there's nothing new to commit, `git commit` exits with non-zero + empty stderr. The daemon bubbles this empty-stderr error up as fatal dispatch failure.

**Reproduce**: dispatch any well-formed work-request via REST; observe the error response despite scaffold success.

**Workaround**: After REST call errors, manually launch the AFK loop:
```bash
cd /Users/pioneer/Projects/tachikoma-starter-tachikoma-<slug>
nohup ./.tachikoma/tachikoma.sh --afk 5 > /tmp/<slug>.out 2>&1 &
```
Worked for `proxy-27-queue-epic-core` (pid 15291, iter 1/5 started cleanly).

**Fix**: One of:
- Make the second commit optional / skip if nothing to commit (check `git status --porcelain` first)
- Catch empty-index error from `git commit` (exit code 1 + empty stderr matching "nothing to commit") and treat as success
- Investigate whether there's a commit hook / signing config producing empty stderr in this dev environment

**Source**: `daemon/src/dispatch/` — full file path TBD during impl. Original spec at `~/projects/personal-nix/wiki/work-requests/proxy-fast-dispatch-mode.md`.

## Bug 3 — Iter-start dirty-tree check kills loop on untracked side-effects (finalize-time)

**Symptom**: `tachikoma_status` reports a run as `status: error`, `iter: 2/12`, `lastProgress: "Sentinel: COMPLETE."` — but the work IS committed on the tachikoma branch, just never auto-shipped (no PR). Confirmed on 2026-05-15 with `proxy-work-request-dispatch-button` — the dispatch slice's feat commit (`379bc76`) was sound, ultimately merged via PR #56 after a manual push.

**Reproduce**: Dispatch any tachikoma against a Next.js repo, cap > 1. After iter 1 commits, `touch <worktree>/apps/web/pnpm-lock.yaml`. Iter 2 bails immediately.

**Root cause**: `~/.claude/skills/tachikoma/tachikoma.sh.tmpl` lines 231-235 — iter-start dirty-tree check treats `git status --porcelain` output as fatal, but that output includes untracked (`??`) entries. Any stray side-effect file from the previous iteration's claude session (orphan lockfiles, `.next/` artifacts, etc.) kills the loop before the current iter's claude even runs and before the ship phase ever fires. The `lastProgress` field is narrative text from `.tachikoma/progress.txt`, not the actual sentinel match — so it can read "Sentinel: COMPLETE." even when the literal `$SENTINEL` sigil never matched.

**Workaround**: After the symptom triggers, `cd` into the worktree, inventory + clean untracked files manually, push the branch, `gh pr create` by hand, then `git worktree remove --force` + delete the local tachikoma branch + flip the work-request frontmatter to `done` with `shipped_pr` URL.

**Fix**: Two independent improvements (do both):

1. **Script side** — in `tachikoma.sh.tmpl`, split the dirty-tree check: tracked-modified is fatal (current behavior), untracked-only is a warning + continue. Belt-and-suspenders: if `.tachikoma/progress.txt` last line contains the literal `$SENTINEL` string, fire the ship phase before bailing.
2. **Prompt side** — in `prompt.md.tmpl`, add a hard rule: "Never invoke a package manager (`npm/pnpm/yarn/bundle install`, etc.) unless the work-request explicitly says to. If you must, use the manager declared in root `package.json`'s `packageManager` field (or equivalent). Stray lockfiles from the wrong manager will trip the iter-start dirty-tree check."

**Source**: `~/.claude/skills/tachikoma/tachikoma.sh.tmpl` (script fix), `~/.claude/skills/tachikoma/prompt.md.tmpl` (prompt fix). Full failure-mode analysis: `~/projects/personal-nix/wiki/runbooks/tachikoma-finalize-dirty-tree-bail.md`.

## Priority

Medium — friction during dispatch AND finalize but workarounds exist for all three. Should fix before queue-infrastructure-v1 ships (proxy-27/28/29 are testing this path live; broken dispatch or finalize will compound across more slices).

## Suggested scope

All three bugs in one work-request slice (`proxy-XX-fix-tachikoma-loop-bugs`). Bugs 1 + 2 are tightly related (dispatch entry path, single daemon source-of-change area); Bug 3 lives in the skill templates (`~/.claude/skills/tachikoma/{tachikoma.sh,prompt.md}.tmpl`) and the runbook. Tachikoma-grabbable; ~2-3h of work including tests across both surfaces.

## Related

- `proxy-fast-dispatch-mode` — original slice that delivered the dispatch CLI + REST endpoint (shipped M3 2026-05-12)
- `proxy-27-queue-epic-core` — first slice that exposed Bug 2 in practice
- `proxy-work-request-dispatch-button` — slice that exposed Bug 3 in practice (shipped manually as PR #56 on 2026-05-15 after the auto-ship failed)
- `auto-memory-pruner` — work-request that got incorrectly grabbed instead of `proxy-27` due to Bug 1; also errored on its own loop, needs a separate diagnose pass
- `~/projects/personal-nix/wiki/runbooks/tachikoma-finalize-dirty-tree-bail.md` — Bug 3 full failure-mode analysis + workaround steps

## Next step

Promote this seed to a work-request slice (e.g. `proxy-XX-fix-tachikoma-loop-bugs.md`) and queue it. Could go in queue-infrastructure-v1 Epic as a hardening item, or as standalone immediately after 27/28/29 ship. Bug 3's script + prompt fixes can ship independently of Bug 1/2 if scope-splitting is preferred.
