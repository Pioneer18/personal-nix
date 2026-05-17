---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-16
depends_on: [proxy-v2-01-schema-migration, proxy-v2-05-runner-branching]
quality_bar: production
---

# PROXY v2 — heartbeat endpoint + reaper + dossier escalation (MV2.05a)

Daemon-side liveness control plane for infils. Loop writes heartbeats; daemon reaps stale-lease LIVE infils; failure_count escalation transitions dossiers to BURNED after threshold. The keystone slice between runner-branching (proxy-v2-05) and standby-flow (proxy-v2-06) — STANDBY and EXFIL_RDY both assume liveness semantics already exist.

## Goal

LIVE infils heartbeat every 30s into the daemon; reaper sweeps every 30s and marks any LIVE infil whose `lease_expires_at < NOW()` as RECALLED (clean retry) or escalates to BURNED at the dossier threshold (`failure_count >= 2`). UI badge always reflects reality — the original "RUNNING badge while no tachikoma alive" failure mode (2026-05-15) becomes structurally impossible.

## Why now

Today's `work_requests` model conflates *dispatcher promised to launch* with *loop is alive right now*. A loop that dies between iterations (memory OOM, machine sleep, dirty-tree bail, unhandled crash) leaves the row in `grabbed` forever — no automated recovery, no signal to the handler that the work-request is stuck. The UI then shows "RUNNING" forever. Two such stuck rows were found on 2026-05-15 and manually unstuck via SQL.

This slice makes the failure mode self-healing: heartbeat + reaper means *the DB never lies about liveness for more than `lease_seconds`*. Combined with the verifier-gate (P1 from ADR 008) and handler-gated exfil (proxy-v2-07), this gives PROXY v2 a state machine that cannot get stuck silently — every terminal is reached deliberately, and the reaper is the backstop for *every* lifecycle gap the supervisor doesn't reach.

## Reaper semantics (conditional escalation)

| Trigger | Transition | Dossier side-effect |
|---|---|---|
| `state='LIVE' AND lease_expires_at < NOW()` AND `dossier.failure_count < 2` | `state → RECALLED, cancellation_reason='lease-expired', ended_at=NOW()` | `failure_count++` |
| Same, AND `dossier.failure_count >= 2` (escalation) | `state → BURNED, burn_reason='lease-expired-after-threshold', ended_at=NOW()` | `state → BURNED` |

Reaper runs every 30s as part of the daemon's existing recommendation-engine tick or its own dedicated task. STANDBY infils are NOT swept — STANDBY is a paused-but-alive state owned by the handler (proxy-v2-06).

## Endpoints

- `POST /api/infils/:id/heartbeat` — refreshes `heartbeat_at = NOW()` + `lease_expires_at = NOW() + lease_seconds`. Returns `200 { lease_expires_at }` if LIVE, `410 Gone { reason }` if state ≠ LIVE (signaling the loop to abort).
- `POST /api/infils/:id/standby` — body `{ reason, context }` — transitions LIVE → STANDBY, inserts a `standby_requests` row. (Endpoint shape; STANDBY semantics live in proxy-v2-06.)
- `GET /api/infils/:id/grant-status` — poll endpoint for sleeping loops. Returns `{ status: 'pending' | 'granted' | 'denied', resumed_at? }`. (Wiring for proxy-v2-06.)
- `POST /api/infils/:id/exfil-ready` — body `{ package_type, branch, ... }` — transitions LIVE → EXFIL_RDY after verifier-gate passes in the loop. (Wiring for proxy-v2-07.)

## Loop heartbeat writer (touches proxy-v2-05 runner-branching)

In `tachikoma.sh.tmpl` add at startup (after PID file write, before main loop):

```bash
(
  while sleep 30; do
    curl -sf -X POST -m 5 \
      "http://127.0.0.1:4321/api/infils/$INFIL_ID/heartbeat" \
      >/dev/null 2>&1 || true
  done
) &
HEARTBEAT_PID=$!
trap 'kill $HEARTBEAT_PID 2>/dev/null; cleanup' EXIT
```

Background thread fires every 30s regardless of iter-call duration. `trap` ensures it dies with the parent script — no orphan curl loops.

## Lease + heartbeat numbers

- `lease_seconds` = 300 (5 min, matches Major ADR 019)
- Heartbeat cadence = 30s (matches Major)
- Reaper interval = 30s (one-pass per tick)
- ~9 missed-heartbeat margin per Major's calibration

## DARK computation

`DARK` is a *computed* state, not stored. The API serializer should mark any `LIVE` infil with stale heartbeat (`NOW() - heartbeat_at > lease_seconds`) as `DARK` in the response payload, so UI can visually distinguish "live but unresponsive" from "alive and heartbeating" during the brief window before the reaper's next tick.

## Files in scope

- `daemon/src/api/infils/heartbeat.rs` (new) — POST endpoint
- `daemon/src/api/infils/standby.rs` (new — endpoint stub; semantics in proxy-v2-06)
- `daemon/src/api/infils/grant_status.rs` (new — endpoint stub; semantics in proxy-v2-06)
- `daemon/src/api/infils/exfil_ready.rs` (new — endpoint stub; semantics in proxy-v2-07)
- `daemon/src/api/infils/mod.rs` (router wiring)
- `daemon/src/reaper.rs` (new — periodic sweep task)
- `daemon/src/main.rs` (spawn reaper task at boot)
- `daemon/src/api/dossiers/serializer.rs` (DARK computation for response payload)
- `daemon/src/state_machine.rs` (LIVE→RECALLED, LIVE→BURNED transition functions called by reaper; conditional based on dossier.failure_count)
- `~/projects/personal-nix/skills/tachikoma/tachikoma.sh.tmpl` (add background heartbeat thread; release into proxy-v2-05's scope when both ship together)

## Files out of scope

- STANDBY pause-poll mechanic on loop side (proxy-v2-06)
- STANDBY grant/deny UI + CLI (proxy-v2-06)
- EXFIL_RDY → EXFIL_D transition logic (proxy-v2-07)
- Web badge component composition (proxy-v2-17)
- TUI badge composition (proxy-v2-16)
- Dossier ARCHIVE transition (proxy-v2-10 cli `archive` verb)

## Stop condition

- [ ] `POST /api/infils/:id/heartbeat` exists; returns 200 with new lease when LIVE, 410 Gone otherwise
- [ ] Reaper task runs every 30s as part of daemon's main loop
- [ ] Reaper transaction is atomic: `UPDATE infils ... RETURNING dossier_id` joined to `UPDATE dossiers ... WHERE id = $1`
- [ ] First N expiries on a dossier → RECALLED (`failure_count++`); N+1 → BURNED at infil + BURNED at dossier
- [ ] `lease_seconds` defaulted to 300, `compaction_interval` style config key in `~/.config/proxy/proxy.toml`
- [ ] `tachikoma.sh.tmpl` spawns background heartbeat thread that survives iter duration; trap kills on parent exit
- [ ] Background thread does not break existing iter execution (`set -e` discipline, error swallowing)
- [ ] DARK computation in API: `state='LIVE' AND NOW() - heartbeat_at > 300` returns `state='DARK'` in serialized payload
- [ ] Endpoint stubs in place for `/standby`, `/grant-status`, `/exfil-ready` (returning 501 or wiring through to in-scope state writes); full semantics deferred to proxy-v2-06 and proxy-v2-07
- [ ] Unit tests cover: reaper picks up exactly the lease-expired LIVE rows; conditional escalation respects failure_count threshold; STANDBY rows are NOT swept; idempotent (reaper running twice produces same end state)
- [ ] Integration test: stale-lease LIVE infil → reaper sweep → state RECALLED + dossier failure_count incremented; repeat → second sweep → BURNED
- [ ] Manual e2e: launch a real infil, kill `tachikoma.sh` with SIGKILL (no heartbeat trap fires), wait 5 min, observe reaper marks RECALLED + dossier shows failure_count=1

## Feedback loops

- `cargo test reaper`
- `cargo test heartbeat`
- `cargo clippy --workspace --all-targets -- -D warnings`
- Manual: spawn an infil, observe heartbeat in logs every 30s; SIGKILL the loop; observe reaper transition within 5-6 min

## Quality bar

production
