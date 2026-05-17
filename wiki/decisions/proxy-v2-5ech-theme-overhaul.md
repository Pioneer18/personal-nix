---
title: PROXY v2 — 5ECH operative-model theme overhaul
date: 2026-05-14
status: accepted
tags: [proxy, v2, theme, architecture]
---

# PROXY v2 — 5ECH operative-model theme overhaul

**Context.** v1.0 shipped 2026-05-12 with BMO-themed work-orchestrator: single-loop-runner, work-request vocabulary, 7 BMO faces tied to whole-system state. The vocabulary was engineering-internal; the four named operatives metaphor (Tracer / Quill / Phantom / Echo) offered narrative + behavioral coherence.

**Decision (21 lockdowns).**

1. 4 callsigns on a 2×2 matrix: Comms (loud/quiet) × Trust (runs/asks). Tracer (Loud×Runs), Echo (Loud×Asks), Phantom (Quiet×Runs), Quill (Quiet×Asks)
2. Scope + clearance are infil flags (orthogonal to callsign)
3. Multi-instance: callsign is a tag, many concurrent infils; addressed `callsign@dossier`
4. Section view = grid of 4 always-present callsign cards
5. Runner branches data-driven on 3 callsign knobs: prompt addendum + pause_on + emit_cadence
6. pause_on triggers STANDBY: all on impasse; Quill+Echo on clearance_boundary; Echo only on irreversible
7. Irreversible = strict core (push-to-protected, force-push, gh pr merge, deploys, prod migrations, destructive ops outside working tree)
8. In-branch commits flow freely; PR create is exfil-controlled
9. Echo's pre-commit announce-intent is comms behavior, not STANDBY
10. 5-level clearance: `read` → `patch` → `commit` → `push` → `execute`
11. Default ceilings: Tracer=read, Quill=commit, Phantom=push, Echo=commit (overridable down at infil)
12. External writes via `--allow-*` infil flags, not the linear axis
13. 7 stored lifecycle states (BRIEFED, LIVE, STANDBY, EXFIL_RDY, EXFIL'D, BURNED, RECALLED); DARK computed from heartbeat freshness
14. State split: BRIEFED on dossier; running states on infil
15. Full vocab swap top-to-bottom: `work_requests`→`dossiers`, `runs`→`infils`, `feed_items`→`comms_events`, `pending_approvals`→`standby_requests`. `loop` (Docker) stays internal. "5ECH" is UI branding; `proxy-daemon` binary unchanged
16. DB-canonical dossiers; transient markdown brief at `proxy brief`; advisory recommendation fields (callsign / clearance / comms)
17. 12-verb CLI: brief, dossiers, infil, status, comms, grant, deny, exfil, recall, burn, drops, archive
18. Typed package (`pr` / `report` / `patch` / `mixed`); untyped dead drops at `~/.proxy/drops/<infil_id>/`, auto-purge on terminate
19. Keep "Hey PROXY" wake-word; add command-mode (voice→CLI); per-proxy TTS voices using macOS built-in
20. Hybrid face system: kaomoji for grid (5 per-callsign + 3 shared universal) + signature big-ASCII-art per callsign for splash/detail
21. Clean cutover + light data import: open work-requests → dossiers; closed archived; seeds unchanged; skills update in cutover

**Alternatives considered.**

- Pure theme skin (no behavioral teeth) — rejected (hollow synergy)
- Singleton-per-callsign — rejected (caps concurrency at 4, awkward callsign-shopping)
- Reskin-only schema with translation layer — rejected (permanent divergence between UI labels and code)
- Greenfield rebuild — rejected (premature given v1.0 just shipped)
- Use-case-based identities without underlying axes — rejected (overlap on verbosity + scope)

**Consequences.**

Positive:
- Coherent vocabulary across CLI / voice / UI / docs
- Behavioral teeth via pause_on + emit_cadence make the proxies meaningfully distinct
- 5-level clearance gives finer authority granularity than v1's binary auto/manual
- Typed packages support both code work (PR) and audit work (report) cleanly
- Per-proxy TTS voices give audio-identity channel for handler without looking at the screen

Negative:
- ~1 week refactor effort (Rust + TS + SQL + docs + skills)
- v1 BMO art retired (archived to `_archive/bmo-faces-v1/`)
- Existing v1 work-requests need import (mechanical, low-risk)
- Higher initial vocab load for new contributors

**Followups (deferred):**
- Per-proxy TTS voice picks may need iteration based on listening tests (slice proxy-v2-15)
- pause_on "irreversible" set may need adjustment as edge cases surface
- 5th "recurring/scheduled" callsign — defer; assess after v2.0 ships

**References.**

- Epic: [`~/projects/personal-nix/wiki/work-requests/proxy-v2-5ech-epic.md`](../work-requests/proxy-v2-5ech-epic.md)
- Slices: `~/projects/personal-nix/wiki/work-requests/proxy-v2-{01..21}-*.md` (21 child work-requests, dependency-ordered MV1→MV7)
- ADR 005 (forthcoming, slice proxy-v2-21): `~/Projects/tachikoma-starter/docs/adr/005-proxy-v2-5ech-theme-overhaul.md`
- ARCHITECTURE.md v4 Part III (slice proxy-v2-19): full canonical detail
- Computer use (formerly planned as v2.0 per [ADR 003](~/Projects/tachikoma-starter/docs/adr/003-computer-use-and-8-layer-gating.md)) renumbered to v3.0 — no code yet, design intact
- Grilling session: 2026-05-14
