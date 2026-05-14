---
title: "PROXY architectural reflection — 2026-05-14"
tags: [proxy, architecture, reflection, gaps, weak-points, doc-drift, post-v1.0]
last_updated: "2026-05-14"
---

# PROXY architectural reflection — 2026-05-14

**Purpose**: snapshot of an architectural reflection on PROXY, the day after v1.0 shipped (2026-05-13). Surfaces 11 findings (ordered by severity), an honest "is there a better overall design?" answer, and 7 prioritized next steps.

This is a **frozen-in-time snapshot**, not an ADR. It will go stale; the queued re-grill work-request (`wiki/work-requests/regrill-architectural-reflection.md`) is the mechanism for refreshing it.

## Method

Loaded into context:
- Full PROXY deep-dive (CLAUDE.md, ARCHITECTURE.md Parts I+II, ADRs 001-004, `decisions/agentic-shell-4-tier-state`, `decisions/proxy-defer-remote-workhorse`, Major ADR 022, `recipes/agentic-shell-v1-slice-plan`)
- 2 NEW untracked ADRs not in the deep-dive: **005 (email vertical)**, **006 (epic queue)**
- Build-state notes (`agentic-shell-build-state.md`, `agentic-shell-overnight-2026-05-12.md`)
- All wiki runbooks + decisions
- Spot-check of actual code in `daemon/`, `voice/`, `apps/web`, `apps/tui` against doc claims
- Targeted verification of ADR 004's Drizzle-removal claim

3 parallel Explore agents covered: latest decisions / code-reality / known-tensions. 1 spot verification on Drizzle.

---

## S1. Doc-vs-code drift (HIGH — actively misleading)

Three places where the docs oversell. A future contributor (or Tachikoma) reading the docs gets a wrong mental model.

| Doc claim | Reality |
|---|---|
| ADR 004: "Drizzle is dropped; `apps/web` reads via daemon API" | PR #42 only migrated 4 modules. **78 `drizzle-orm` imports remain** across 14+ files (state-machine, runner, runs-db, jira/github/gmail sync, integrations page, scheduled-jobs API). `drizzle.config.ts` + `drizzle/` migrations dir + `drizzle-kit` package all still live. |
| ADR 002: "vendor Picovoice Porcupine v3.0 into `voice/vendor/porcupine/`" | Code uses `livekit-wakeword` (ONNX) instead. The Picovoice abandonment is in the amendment but the LiveKit pivot isn't recorded in the ADR. |
| ARCHITECTURE.md § 22: "all 7 BMO faces wired" + "5 web pages shipped" | TUI has 7 faces; **web only renders `big-bmo.txt`**. Runs has only `[id]` detail (no listing). Notifications has only `permission/` subpage (no listing). ElevenLabs TTS is a TODO stub that logs the chunk but never plays it. |

**Why this matters**: ADR 004 is the contract a Tachikoma reads when claiming a `daemon/` or `apps/web` slice. If a Tachikoma trusts "Drizzle is dropped" while existing code still uses it, you get the worst-of-both — two ORMs, drift in derived types, doubled migration surface.

## S2. Schema source-of-truth split (HIGH — structural consequence of S1)

Right now you have:
- `daemon/migrations/` (sqlx) — 16 SQL files, owned by Rust daemon
- `apps/web/drizzle/` — 10 SQL files, owned by Next.js
- They cover overlapping but non-identical tables

This is exactly the failure mode ADR 004 was written to prevent. Until the migration finishes (or the rollback decision is made explicit), every new web feature has to choose Drizzle (legacy) or daemon HTTP API (canonical). The middle position you're in today is the worst place to live.

## S3. Memory coordination is load-bearing and still soft (HIGH — risk-accepted but worth re-examining)

The whole memory-awareness story rests on: PROXY's sensor → admission rule → never-kill loops, plus PROXY writes `shell_pool_state.paused` → Major's Shells stop claiming. But:

- **2-5s sensor cadence** = a sub-second pressure spike can still kill a newly-spawned loop mid-API-call before admission catches up.
- **Major ADR 022 is still `Proposed`**, not Accepted. Major's memory safety is provided externally by PROXY today. If PROXY is paused/killed/rebuilding, Major regresses to the pre-2026-05-11 crash-prone state.
- **Sensor has silent degradation paths**: `read_page_size_bytes().unwrap_or(16_384)` and a cascade of `.unwrap_or()` chains in `daemon/src/sensor/mach.rs`. If macOS releases a `vm_stat` format change, the sensor's memory math drifts 5-10% off without telling anyone.

## S4. "Memory-lean baseline" is theoretical (MEDIUM)

CLAUDE.md says "Total persistent host RSS added by PROXY (idle): ~50 MB." Static estimate, never measured under load (5+ concurrent loops + daemon + Next.js + Postgres + Major's stack). No startup memory-baseline assertion, no `cargo bench` for the daemon under load, no telemetry tracking the daemon's own RSS over time. The kind of thing that bites silently after months of feature creep.

## S5. Voice handoff state machine is unspecified in code (MEDIUM)

ADR 002 specifies mode-aware mic ownership, but:
- `voice/src/tts/elevenlabs.rs` is a TODO stub — synthesis logs the chunk, never plays it.
- Wispr Flow handoff is slated for `shell-06` in M5, not implemented. The mic-grab/release coordination is a comment in an ADR, not a state machine in code.
- Mode-switching writes `proxy_voice_state` and emits `LISTEN/NOTIFY voice_mode_changed`, but no test asserts all 4 paths (voice cmd / hotkey / CLI / TUI dropdown) converge atomically to the same DB write.

## S6. 4-tier state boundary leaks personal data into Tier 0 (LOW — minor)

Grep finds `Pioneer18`, `pioneer`, `jonathan` in `tachikoma-starter` (ARCHITECTURE.md, ADR 004 example `db_url = "postgres://pioneer@..."`, `skills/wiki/SKILL.md`). No secrets, no IP — just names. The 4-tier model is supposed to mechanically prevent this; right now it's documented-only, no lint rule. If the substrate is ever shared with a contractor, the docs are a roadmap to the personal layer's owner.

## S7. Email vertical compliance debt is real and inherited (MEDIUM — already accepted)

ADR 005 ships in two phases — structural (metadata only, ~60-70% value) v1, body-mode v2 gated on Anthropic BAA (1-4 wk to 2-3 mo timeline). Even structural mode sends `Subject: ...` to Claude, which can leak PHI in subject lines for clinician escalation emails. Risk-accepted in `decisions/relymd-work-data-pragmatic-compliance.md` with 8 tracked TODOs. Not a PROXY architecture flaw — RelyMD's compliance posture inherited into PROXY's surface. The "deep PHI detector — phase 2" gate is currently TODO-only.

## S8. Slice-plan auto-build edge cases (LOW — already learned)

Overnight log documents: cap-without-sentinel pattern (manual ship needed), Cargo.toml union-merge with manual dedupe, "I can't run `cargo` (not on PATH)" toolchain blind spot. Operational issues, not architectural. Already learned. Worth a runbook entry if not present.

## S9. Seed → Notebook importer unbuilt (LOW)

`wiki/seeds/` is interim per `decisions/seeds-folder.md` — to be migrated by a one-shot importer in M6. M6 is mid-flight (notebook UI shipped, importer not yet). If the importer ships broken or skipped, seeds get orphaned. Mitigation is unimplemented code.

## S10. Computer-use cost-cap layer has no teeth (LOW — v2.0 issue)

ADR 003's 8th gate is "cost cap." Default $5/day, $1/intent soft. Enforcement mechanism is unspecified — no DB table, no API hook, no daemon path that pauses on breach. Fine because computer use is v2.0, but the gate is currently documented-only.

## S11. Remote-workhorse promotion triggers are qualitative (LOW — already accepted)

`decisions/proxy-defer-remote-workhorse.md` lists 4 triggers. Telemetry to detect them exists in plan but not in code. The `consider-remote-workhorse` recommendation kind isn't yet emitted by `daemon/src/manager/`. A trigger could fire in production and PROXY wouldn't say so.

---

## Is there a better overall design?

**No — the v3 substrate is structurally sound. The pain is execution debt, not design errors.**

The hard rules hold: memory-aware admission, containerized loops, single coordinating daemon + sibling voice daemon, 4-tier state, `RunBackend` trait. v3 absorbed the email vertical (ADR 005) + epic-queue restructure (ADR 006) without conceptual breakage.

**What I'd actually re-examine if you wanted to redesign:**

1. **The web app's role.** "Always-on Next.js, daemon-managed, pauses on Critical pressure" — but if half the web work is happening directly via Drizzle against PG instead of via the daemon API, the daemon-API contract isn't paying its way. Pick a side: finish the migration OR amend ADR 004 to accept dual-stack as permanent. Don't live in the middle.

2. **Single-daemon-vs-microservices.** `proxy-daemon` owns scheduling + admission + sensor + recommendations + manager + dispatch + tool-catalog + wizard + API + run lifecycle. That's a lot in one Rust binary. Voice is correctly split out. As verticals expand, consider whether the manager subsystem (recommendations engine) wants to be a sibling daemon for the same crash-isolation reason voice was. Not urgent — flag for next architectural inflection.

3. **Major coordination is now ~3 days old in production.** Major ADR 022's promotion trigger is "30 days of interim coordination running." If interim works, fine. If it exposes a hole (e.g., race between PROXY clearing `paused` and Major polling), promote sooner with discovered learnings.

4. **No formal "doc=code" gate.** Today, docs and code drift quietly (Drizzle, Porcupine, faces, page counts). A weekly `doc-reality-check` agent run (or CI lint on ADR claims that contain testable predicates) would catch these earlier. Not every doc needs to be machine-checkable, but ADRs that claim "X is removed" or "Y is wired" probably do.

---

## Recommended next steps (priority order)

Pick whichever to act on; nothing committed yet.

1. **Update or amend ADR 004** to reflect actual Drizzle migration state. (`docs/adr/004-*.md`, `apps/web/package.json`, `apps/web/drizzle/`, `daemon/migrations/`)
2. **Amend ADR 002** to name LiveKit as the chosen wake-word replacement. (`docs/adr/002-*.md`, `voice/src/wake/livekit.rs`)
3. **Tighten ARCHITECTURE.md § 22** v1.0 Done claims — split shipped-and-working from shipped-as-stub from not-yet. (`docs/ARCHITECTURE.md`, `apps/web/app/`)
4. **Commit the 2 new ADRs + modified CLAUDE.md** — they're untracked, so the deep-dive skill is loading stale info. (`docs/adr/005-*.md`, `006-*.md`, `CLAUDE.md`)
5. **Add daemon-RSS telemetry** + baseline assertion in `daemon/tests/` so memory creep is observable. (`daemon/src/sensor/`, `daemon/tests/`)
6. **Promote Major ADR 022** if 30-day interim window proves stable, OR document the exact interim → owned migration plan with a date. (`~/Projects/major/docs/adr/022-*.md`)
7. **Wire a `doc-reality-check` skill** that re-runs the spot-check we just did, weekly, and flags drift. (new skill at `personal-nix/skills/doc-reality-check/`)

---

## Provenance

- Session: 2026-05-14, MacBook-Pro-2, opus-4-7
- Triggered by: user invocation of `/proxy-deep-dive` + `/orient-to-machine`, followed by "reflect on the architecture, look for gaps, weak points, assess if there's a better overall design"
- Tried to refine via Ultraplan; 403 (transient or unrelated to access — claude.ai/code is reachable). Skipped to direct wiki persistence.
- Re-grill queued at `wiki/work-requests/regrill-architectural-reflection.md`
