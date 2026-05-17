---
title: "Fix tachikoma dispatch bugs (MCP slug arg + REST commit-failure)"
tags: [seed, bug, tachikoma, proxy, dispatch, fast-dispatch]
type: bug
last_updated: 2026-05-14
discovered_during: "Dispatching proxy-27-queue-epic-core via Tachikoma 2026-05-14"
priority: medium
---

# Fix tachikoma dispatch bugs

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

## Priority

Medium — friction during dispatch but workaround exists. Should fix before queue-infrastructure-v1 ships (proxy-27/28/29 are testing this path live; broken dispatch will compound across more slices).

## Suggested scope

Both bugs in one work-request slice (`proxy-XX-fix-dispatch-bugs`). Tightly related, single source-of-change area. Tachikoma-grabbable; ~1-2h of work including tests.

## Related

- `proxy-fast-dispatch-mode` — original slice that delivered the dispatch CLI + REST endpoint (shipped M3 2026-05-12)
- `proxy-27-queue-epic-core` — first slice that exposed Bug 2 in practice
- `auto-memory-pruner` — work-request that got incorrectly grabbed instead of `proxy-27` due to Bug 1; also errored on its own loop, needs a separate diagnose pass

## Next step

Promote this seed to a work-request slice (e.g. `proxy-XX-fix-dispatch-bugs.md`) and queue it. Could go in queue-infrastructure-v1 Epic as a hardening item, or as standalone immediately after 27/28/29 ship.
