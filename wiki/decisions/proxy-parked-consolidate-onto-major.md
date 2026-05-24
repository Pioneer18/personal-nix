---
title: "PROXY parked — consolidate onto Major"
tags: [proxy, major, scope, decision, agentic-shell, ralph-loop, admission]
last_updated: "2026-05-24"
status: accepted
---

# PROXY parked — consolidate onto Major

**Status**: Accepted — 2026-05-24.

**Scope**: Decides to stop work on PROXY (`~/Projects/tachikoma-starter`), archive its GitHub
repo, and consolidate the "reliable loop agent" goal onto Major (`~/Projects/major`). Local
working copies of both repos are retained. Full restart spec lives in the PROXY repo at
`~/Projects/tachikoma-starter/RESTART.md` (re-read that first if reviving).

## Context

PROXY's real goal was always **a reliable RALPH-style loop agent**: a work request goes in, an
ephemeral container running `claude -p` does the work under memory-pressure admission control, a
PR comes out. The v1.0 substrate shipped 2026-05-12 and the core loop works.

After v1.0 the design sprawled — see [proxy-v2-5ech-theme-overhaul](proxy-v2-5ech-theme-overhaul.md)
and the v2 epic. A 2026-05-24 honest design review concluded PROXY had become ~30% core loop and
~70% peripheral surface (5ECH vocab/theme, voice daemon + boot, face/kaomoji system, email
vertical, operations/objectives substrate, provider abstraction) — most of it unshipped or
cosmetic, none of it improving loop reliability.

The pivotal observation: **PROXY and Major are the same product built twice.** Both ingest a unit
of work, dispatch an ephemeral Claude subprocess, produce a PR, and gate acceptance on a human.
The differences favor Major decisively:

| | PROXY | Major |
|---|---|---|
| Branch hygiene | `master`/`develop` diverged, hand-merge conflicts in recent log | clean `dev`, in sync with origin |
| Scope | core loop + 5 peripheral verticals | Brief lifecycle, nothing else |
| Maturity | v1 substrate then ~70% creep, nothing past substrate shipped clean | Plan 001 e2e-hardening all 5 streams merged |
| Targets | itself (personal-nix, tachikoma-starter) | **HealthBite + Healix — the real RelyMD work repos** |

"Get work requests done" means the RelyMD repos where the actual job lives. Major already points
there; PROXY points at itself.

## Options considered

1. **Keep grinding PROXY's 22-slice v2 epic** — rejected. Pours effort into vocab/theme/voice/faces
   that don't move loop reliability. The plot was already lost.
2. **Run both** — rejected. Two half-built versions of the same product splits attention and the
   memory budget (both schedule Docker loops on the same OrbStack VM; see
   [orbstack-over-docker-desktop](orbstack-over-docker-desktop.md)).
3. **Hard-delete PROXY** — rejected. The admission/sensor design and ADR 008 are worth keeping;
   deletion is unrecoverable.
4. **Park PROXY (archive, retain), harvest its one keeper into Major, focus on Major** — chosen.

## Decision

- **Archive PROXY's GitHub repo** (read-only); retain the local working copy; tag
  `proxy/parked-2026-05-24`.
- **Harvest the one keeper — pressure-aware admission** — into Major via Major ADR 022
  (`~/Projects/major/docs/adr/022-shell-claim-admission-system-pressure-aware.md`). PROXY's
  `admit()` rule (4 hard gates + thermal/LPM bonus gates, pure function fed by a sensor) is the
  authoritative design. Full gate spec + thresholds + the macOS-host-vs-Linux-container probe fork
  are documented in PROXY's `RESTART.md`.
- **Do not rebuild the scope creep.** The "DO NOT REBUILD" table in `RESTART.md` is the canonical
  list. Exceptions worth lifting cheaply if ever relevant: per-callsign runner knobs and
  provider fallback.
- **Bring Major to a green end-to-end** (close/bypass the triage stub F-01, run the manual
  walkthrough, deploy, stand up a Shell).

## Consequences

**Positive**: one focused product; effort goes to loop reliability (ADR 008) instead of theme;
Major gains pressure-aware admission it lacked; the RelyMD work repos get an actual agent.

**Negative**: the local-ephemeral-per-loop execution model (stronger blast-radius isolation than
Major's persistent Shell) goes dormant — noted as a revival trigger in `RESTART.md` if Major shows
cross-Brief contamination. The 5ECH design work is sunk; accepted as a sunk cost.

**Revival triggers** (from `RESTART.md`): Major proves structurally unable to serve the goal —
persistent-Shell cross-Brief contamination that's non-trivial to fix, a need to run loops where
Supabase-orchestrated Major can't, or Major's cloud dependency becoming a hard liability.
Cosmetic dissatisfaction is not a trigger.

## Related

- `~/Projects/tachikoma-starter/RESTART.md` — full restart spec (authoritative)
- `~/Projects/major/docs/adr/022-shell-claim-admission-system-pressure-aware.md` — where admission lands
- `~/Projects/tachikoma-starter/docs/adr/008-agent-design-principles.md` — the reusable loop-reliability principles
- [proxy-defer-remote-workhorse](proxy-defer-remote-workhorse.md) — the remote-workhorse deferral (still parked)
- [orbstack-over-docker-desktop](orbstack-over-docker-desktop.md) — shared substrate both systems used
