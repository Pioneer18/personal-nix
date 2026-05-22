---
title: tachikoma loops invisible in PROXY dashboard — missing dossier/infil rows
date: 2026-05-21
tags: [proxy, tachikoma, dashboard, v2, registration]
---

# Tachikoma loops invisible in PROXY dashboard

## Symptom

`/tachikoma status` shows N loops RUNNING in their worktrees, but the v2 web dashboard (`localhost:3737`) and TUI section grid show 0 LIVE for the corresponding callsign card. The "Runs in Flight" tile also undercounts.

## Root cause

The orchestrator skipped Step 2.e of the `/tachikoma queue` flow — the explicit `lib/spawn-v2.sh <slug> <wr-path>` call that registers a dossier + infil row in the v2 schema. Observed when `/tachikoma queue <repo>` (GitHub-sourced drain) auto-creates work-request `.md` files and launches worktrees in parallel without per-item registration. The dashboard reads only from the `infils` table; loops that never get a row are invisible.

Side note: `proxy queue grab` works against the v1 `work_requests` table; v2 `dossiers` is a separate table populated by `proxy brief`. The promotion happens inside `spawn-v2.sh`.

## Detection

```bash
# Worktrees with active PIDs:
ls ~/Projects/*-tachikoma-*/.tachikoma/run.pid | while read p; do
  pid=$(cat "$p"); kill -0 "$pid" 2>/dev/null && echo "ALIVE $p"
done

# Dossiers + infils registered in v2 DB:
docker exec proxy-postgres psql -U proxy -d proxy -c \
  "SELECT d.slug, i.callsign, i.state FROM infils i \
   JOIN dossiers d ON i.dossier_id = d.id ORDER BY i.started_at DESC;"
```

If worktree-alive count > infils-row count for the relevant slugs, you're hitting this.

## Fix (backfill)

For each affected slug, register the dossier + infil. If the loop is already complete (worktree has `.tachikoma/outcome=complete`), insert the infil row in `EXFIL_RDY` state directly so it surfaces as "package ready for review":

```bash
proxy brief <slug> --from-file ~/projects/personal-nix/wiki/work-requests/<slug>.md

docker exec -i proxy-postgres psql -U proxy -d proxy <<SQL
INSERT INTO infils (dossier_id, callsign, clearance, comms, state, started_at, ended_at, last_heartbeat_at)
SELECT d.id, 'phantom', 'push', 'quiet', 'EXFIL_RDY'::infil_state, NOW(), NOW(), NOW()
FROM dossiers d
WHERE d.slug = '<slug>'
  AND NOT EXISTS (SELECT 1 FROM infils i WHERE i.dossier_id = d.id AND i.state != 'BURNED'::infil_state);
SQL
```

Skip the manual SQL and use `proxy infil phantom --dossier <slug>` instead if the loop is still LIVE — it inserts a LIVE row and tries to start a Docker container (the Docker spawn will fail for native tachikoma loops, but the row sticks).

## Prevention (landed 2026-05-21)

`tachikoma.sh.tmpl` now closes the loop end-to-end:

1. **Start-of-run self-register (LIVE).** Derived from the branch name (`tachikoma/<slug>`) and the canonical wiki path:

   ```bash
   proxy brief "$reg_slug" --from-file "$reg_wr"
   proxy infil phantom --dossier "$reg_slug"
   ```

   Idempotent — `proxy brief` tolerates already-exists; the LIVE-per-dossier unique index turns a duplicate infil into a silent skip. The orchestrator's explicit `spawn-v2.sh` call is still primary; this is defense-in-depth.

2. **On `outcome=complete` (LIVE → EXFIL_RDY).** The `cleanup()` trap issues a direct `docker exec proxy-postgres psql` UPDATE inside a transaction with an `infil_state_transitions` audit row (`actor=tachikoma-loop`). Bypasses the daemon CLI because the v2-08 runner orchestrator that *would* have observed the sentinel is unimplemented — and tachikoma loops run natively (not in Docker), so even a built runner wouldn't see them.

3. **Phase 6 squash-merge (EXFIL_RDY → EXFIL'D).** `/tachikoma done` now auto-runs `proxy exfil phantom@<slug> --note "..."` immediately after the merge commit succeeds. Same path for `/tachikoma queue` drain-mode Phase 6 (the abbreviated ship phase).

All three steps are best-effort — failures log but don't abort merge / loop / shipping. Observability isn't worth blocking real work for.

## First observed

2026-05-21, after `/tachikoma queue MioMarker/healthbite` dispatched 9 `hb-tests-*` slices in parallel. All 9 completed normally but never appeared on the dashboard — the Phantom card showed 0 LIVE / 1 DARK instead of 9 LIVE / 1 DARK (then 9 EXFIL_RDY after completion). Backfilled the 9 rows, then patched the template.
