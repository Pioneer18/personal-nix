---
title: "PROXY v2 — liveness model + state machine + reaper design (12-Q grilling)"
date: 2026-05-16
status: accepted
tags: [proxy, v2, 5ech, liveness, state-machine, reaper, heartbeat]
---

# PROXY v2 — liveness model + state machine + reaper (12-question grilling)

**Status**: Accepted — 2026-05-16.

**Scope**: Design decisions reached during a 2026-05-16 grilling session about the PROXY v2 liveness/state model. Motivated by a live bug — `proxy-29b-tachikoma-queue-no-arg-wiring` was rendering as "RUNNING" in the web UI despite no tachikoma actually being alive on disk. The grill walked 12 branching design decisions to design a state model where that failure mode is *structurally* impossible.

Outputs of this decision doc are realized in:
- Slice `proxy-v2-05a-liveness-and-reaper.md` (the keystone slice that lives between proxy-v2-05 and proxy-v2-06)
- Updates to slices 01 (schema), 02 (migration mapping), 07 (exfil-flow), 17 (web grid)
- Epic doc updates (slice list, dependency graph, DoD bumped 21→22)

## Context

Today's PROXY v1 model conflates *dispatcher promised to launch* with *loop is alive right now*. A loop that dies between iterations (memory OOM, machine sleep, dirty-tree bail, unhandled crash) leaves the `work_requests` row in `grabbed` forever. The web UI's `DispatchButton` keys off `status === 'grabbed'` to render a yellow "Running" chip — but `grabbed` is just a row in the DB; nothing verifies the process is alive. Once stuck, the only recovery is manual SQL.

The 5ECH epic (decision doc `proxy-v2-5ech-theme-overhaul.md`) added 7 state-machine values + the `infils` table (renamed from `runs` for theme coherence; see `infil-vs-insert-renaming` note in lock 15) but didn't specify *how liveness gets into the DB*, *who reaps stale rows*, or *how the UI badge composes when multiple infils exist on one dossier*. This grilling fills those gaps.

## Decisions

Twelve questions, walked in dependency order. Each has 2-4 options; the picked option is bold + has a one-line rationale.

### Q1 — What does "running" *mean*?

| Option | Definition |
|---|---|
| **A — OS process exists and is alive** | True liveness is a real-world fact. DB is a cache of the most recent observation. |
| B — Dispatcher last committed an admit tx | DB is authoritative; no liveness check. Today's behavior. |
| C — Unfinalized state exists somewhere | Mixed sources (worktree + DB + GitHub). Multi-source reconciliation. |

**Picked A**. Rationale: every undeterminable failure under B leaks into permanent stuck-grabbed (which is exactly the original bug). C has too many sources of truth.

### Q2 — How is liveness *observed*?

| Option | Mechanism |
|---|---|
| **A — Heartbeat (push)** | Loop POSTs to daemon every 30s. DB row gets `last_heartbeat_at` + `lease_expires_at` updates. |
| B — Probe (pull) | Daemon walks `infils WHERE state='LIVE'` and `kill -0`s each PID. |
| C — Both | Hybrid; belt-and-suspenders. |

**Picked A**. Rationale: backend-agnostic (works identically for future containerized or remote backends, not just host PIDs). Major already uses this pattern (ADR 019: 300s/30s).

### Q3 — Schema shape?

| Option | Plan |
|---|---|
| **A — Separate `infils` table** | First-class run-attempt rows; partial unique index `UNIQUE(dossier_id) WHERE state='LIVE'`. |
| B — Heartbeat columns on `dossiers` | Lighter schema; one row per dossier. No retry history. |

**Picked A**. Rationale: retries become representable (today's stuck-grabbed bug becomes recoverable — reaper marks attempt 1 RECALLED, dossier flips back to BRIEFED, next dispatch creates attempt 2 with full history). Mirrors Major's `runs` table exactly.

### Q4 — State enum + UI badge wiring?

| Option | Plan |
|---|---|
| **A — Major-mirror** | Stored state updated atomically with infil transitions; badge displays stored state directly. Status fields cannot lie because dual-write is transactional. |
| B — UI derives state at read time | API serializer joins tables on every read. |
| C — Magic "effective state" computed in API | Mixed. |

**Picked A**. Rationale: invariant that `dossier.state = X ⇔ (corresponding infils row exists with state Y)` is structurally enforced by the partial unique index + atomic dual-write. Reads stay flat.

### Q5 — Reaper transition for lease-expired LIVE infil?

| Option | Plan |
|---|---|
| A — Always RECALLED | Treat every expiry as a clean transient. |
| B — Always BURNED | Treat every expiry as a failure. |
| **C — Conditional escalation** | First N expiries → RECALLED (auto-retry). At `failure_count >= 2` → escalate to BURNED. Matches existing PROXY retry semantics. |

**Picked C**. Rationale: most expiries are transient (machine sleep, network burp, OOM mid-iter); auto-treating them as failures spams human attention. Threshold prevents infinite-retry on genuinely-broken dossiers.

### Q6 — Heartbeat cadence + lease duration?

| Option | Plan |
|---|---|
| **A — 30s heartbeat / 300s lease, bg bash thread** | Matches Major ADR 019. Background `(while sleep 30; do curl ...; done) &` decoupled from iter execution. |
| B — Iter-boundary only | Lease must exceed longest iter (~10 min). Iters that go long lose lease. |
| C — Hybrid | Both. |

**Picked A**. Rationale: claude iters can run 2-10 min legitimately; coupling heartbeat to iter boundaries makes long iters lose lease. Bg thread is ~10 lines of bash.

### Q7 — STANDBY heartbeat behavior?

| Option | Plan |
|---|---|
| **A — Loop survives + heartbeats continue** | `tachikoma.sh` POSTs `/standby`, claude exits, bash polls `/grant-status` every 10s. Reaper ignores STANDBY entirely. |
| B — Loop exits, daemon respawns on grant | Re-hydration cost; separate stale-standby timer. |
| C — Hybrid | Exit after N minutes of pending standby. |

**Picked A**. Rationale: matches Major's pattern (Shells heartbeat throughout while Tachikomas pause). Reaper logic stays one-rule (`LIVE + stale lease`). Resource cost (idle bash + curl) is ~10 MB.

### Q8 — `LIVE → EXFIL_RDY → EXFIL'D` mechanics?

| Option | Plan |
|---|---|
| A — Loop auto-exfils | Today's flow; EXFIL_RDY is transient milliseconds. |
| **B — Strict handler-gated** | Loop POSTs `/exfil-ready` with package metadata, exits. Handler runs `proxy exfil <ref>` explicitly; daemon performs the typed-package action. |
| C — Callsign-config gated | Per-callsign `auto_exfil: true/false`. |

**Picked B**. Rationale: matches lock 8 ("PR create is exfil-controlled") literally. Matches the operative metaphor (Sam Fisher calls Lambert for extraction). Recovery is cleaner — handler retries via CLI, no half-dead loop process to debug. Eliminates `ship.md` from the loop entirely; daemon owns `gh pr create`.

### Q9 — Dossier-level state machine?

| Option | Plan |
|---|---|
| **A — `BRIEFED \| BURNED \| ARCHIVED`** | 3 states. BURNED for repeat-failure escalation. ARCHIVED for handler-hide. EXFIL'D infil leaves dossier at BRIEFED. |
| B — Mirror-latest (`BRIEFED \| EXFIL'D \| BURNED \| ARCHIVED`) | Dossier mirrors latest infil's terminal. |
| C — Single state, derived | Computed at read time. |

**Picked A**. Rationale: honors lock 13's "7 stored states" without reusing values across two enums. Dossier represents a *task*, not a *single attempt* — first EXFIL'D doesn't auto-close it (handler may want a v2 or repair). Badge label = stored state verbatim (no API-layer magic).

### Q10 — Composite badge when dossier has multiple live infils?

| Option | Plan |
|---|---|
| A — Single verbatim badge | `BRIEFED/BURNED/ARCHIVED` only. Per-infil details in a list below. Most accurate, least glance-utility. |
| B — Composite (worst-state aggregation) | One badge derived across dossier + infils. Glance-friendly; brittle. |
| **C — Two-tier** | Primary badge = `dossier.state` verbatim. Adjacent secondary chip = worst-state among `LIVE/STANDBY/EXFIL_RDY` infils (hidden when none). Hybrid: reliability of A + glance-utility of B. |

**Picked C**. Rationale: matches GitHub PR pattern (Open/Merged + Checks running). The two badges describe different facts from different tables and can never disagree. `DARK` is a computed state of the secondary chip (LIVE + stale heartbeat); reaper sweeps clean it within 30s.

### Q11 — Slicing strategy?

| Option | Plan |
|---|---|
| A — Fold into existing 5ECH slices | No new slices; 05 absorbs heartbeat + reaper. |
| **B — Add `proxy-v2-05a-liveness-and-reaper`** | Keystone slice between 05 and 06. Heartbeat endpoint + reaper + dossier failure_count escalation + DARK computation. ~1-2 days of work. |
| C — Pull heartbeat+reaper out of v2 epic, ship as v1 hotfix now | Throwaway; v2 epic supersedes. |

**Picked B**. Rationale: reaper is non-trivial daemon logic worth its own slice; sits cleanly in the dependency order (05 → 05a → 06+07). No v1 throwaway.

### Q12 — Stuck-row cleanup + v1→v2 mapping?

| Option | Plan |
|---|---|
| **A — Manual SQL today + simple 4-row mapping** | Two specific rows resolved by SQL UPDATE now. Migration mapping stays heuristic-free: `open → BRIEFED`, `grabbed → BRIEFED`, `done → ARCHIVED`, `needs-triage → BURNED`. |
| B — Let migration script handle | Add heuristics. |
| C — Hybrid | Some manual, some heuristic. |

**Picked A**. Rationale: only 2 stuck rows; manual SQL is faster than designing migration heuristics. Reaper backstops anything that slips through.

## Consequences

**Positive:**
- The "RUNNING badge while no tachikoma alive" failure mode (2026-05-15) is structurally impossible under this design. DB never lies about liveness for more than `lease_seconds`.
- Multi-infil per dossier becomes a first-class concept (lock 3 already allowed it; this design renders it correctly).
- Mirrors Major's runs/lease pattern, so PROXY ↔ Major coordination uses one shared primitive.

**Negative:**
- One new slice (05a) bumps the epic from 21 → 22 child slices.
- Loop now writes to the daemon (heartbeat endpoint) every 30s — small operational dependency; if daemon is down, healthy loops appear DARK then RECALLED. Mitigated by daemon being a LaunchAgent with `KeepAlive`.
- EXFIL_RDY persists indefinitely until handler acts. Defensible (handler-gating means handler-on-their-own-time) but a stale-EXFIL_RDY notification is a v2.5 hardening opportunity.

**Post-grill follow-up (P6 revert):**
- ADR 008 P6 originally proposed automatic post-ship CI feedback ingestion. Same-day reverted because zero observed firings — see [`tachikoma-skill-hardening-2026-05-16.md`](tachikoma-skill-hardening-2026-05-16.md) § Reverted same-day. Q13 (which would have been "where does CI-poll live under handler-gated exfil") dissolved as a result. Slice 05a stays small.

## See also

- [PROXY v2 5ECH theme overhaul](proxy-v2-5ech-theme-overhaul.md) — the 21 locks this grilling builds on
- [Slice `proxy-v2-05a-liveness-and-reaper`](../work-requests/proxy-v2-05a-liveness-and-reaper.md) — the implementation
- [Tachikoma skill hardening](tachikoma-skill-hardening-2026-05-16.md) — P6 revert context
- [PROXY ADR 008](~/Projects/tachikoma-starter/docs/adr/008-agent-design-principles.md) — agent design principles this grilling sits on top of
- [Major ADR 019](~/Projects/major/docs/adr/019-heartbeat-lease-length.md) — 300s/30s calibration we mirror
