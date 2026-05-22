---
title: "PROXY architectural reflection — 2026-05-14"
tags: [proxy, architecture, reflection, gaps, weak-points, doc-drift, post-v1.0]
last_updated: "2026-05-14"
---

# PROXY architectural reflection — 2026-05-14

**Purpose**: snapshot of an architectural reflection on PROXY, the day after v1.0 shipped (2026-05-13). Surfaces 11 findings (ordered by severity), an honest "is there a better overall design?" answer, and 7 prioritized next steps.

This is a **frozen-in-time snapshot**, not an ADR. It will go stale; the queued re-grill work-request (`wiki/work-requests/regrill-architectural-reflection.md`) is the mechanism for refreshing it.

## Re-grill deltas — 2026-05-22

**7 confirmed · 4 refined · 0 refuted · 0 outdated · 1 new (S12).** Each finding now carries an inline `**CONFIRMED**` / `**REFINED**` / `**NEW**` tag with the 2026-05-22 verification + paired follow-up.

- **S1 — REFINED.** Drizzle counts updated (40 imports/39 files, was 78/14+). BMO faces sub-claim removed (v2 face system shipped). ElevenLabs + Runs/Notifications stub-page claims still hold.
- **S2 — CONFIRMED + REFINED.** Schema counts updated (daemon 44 / drizzle 11, was 16/10). Trajectory note added — net direction is right (new schema work goes sqlx-side), but Drizzle ergonomics still actively pull new-feature work; bit me writing the /infils page.
- **S3 — CONFIRMED + REFINED with a worse sub-finding.** The `shell_pool_state.paused` write-back PROXY was supposed to drive on host pressure is **doc-only — never implemented**. Three docs (CLAUDE.md #16, ARCHITECTURE.md § 9, § 6 diagram) describe it as load-bearing v1 coordination; grep finds zero refs in daemon/src/. ADR 022 amendment landed; ARCHITECTURE.md § 9 qualifier landed.
- **S4 — CONFIRMED.** Daemon RSS spot-check (12.9 MB) is leaner than ~50 MB target, but no benchmark / baseline assertion / self-telemetry. Next-Step #5 still right.
- **S5 — REFINED.** Wispr Flow handoff has shipped (`voice/src/modes/wispr.rs`, fully wired) — that bullet is outdated. ElevenLabs stub + 4-path atomicity test gap still confirmed.
- **S6 — REFINED.** `Pioneer18` + `jonathan` cleaned up. Only lowercase `pioneer` username remains in example paths + ADR 004 `db_url`. Underlying lint-rule gap unchanged.
- **S7 — REFINED.** TODO count corrected (8 → 2 — six TODOs got resolved between 2026-05-14 and 2026-05-22). Core compliance posture finding intact.
- **S8 — CONFIRMED.** No runbook for cap-without-sentinel / Cargo.toml union-merge / cargo-PATH. Runbook entry still needed.
- **S9 — CONFIRMED.** Seeds dir still populated; importer still unbuilt.
- **S10 — CONFIRMED.** Cost cap still doc-only; expected for v2.0 feature.
- **S11 — CONFIRMED.** `consider-remote-workhorse` recommendation kind still not emitted by daemon manager.
- **S12 — NEW.** ADR 005 number collision: two files share the 005 slot. Mechanical fix via slice `proxy-v2-21`.

Artifacts landed during the regrill:
- ADR 022 amendment ("interim coordination is observe-only in practice") in `~/Projects/major/docs/adr/022-shell-claim-admission-system-pressure-aware.md`.
- ARCHITECTURE.md § 9 qualifier in `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md`.
- Inline updates to this note for every S1-S12 finding.

---

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

## S1. Doc-vs-code drift (HIGH — actively misleading) — **REFINED 2026-05-21**

Places where the docs oversell. A future contributor (or Tachikoma) reading the docs gets a wrong mental model. Specifics re-verified during regrill against live code; updated row-by-row.

| Doc claim | Reality |
|---|---|
| ADR 004: "Drizzle is dropped; `apps/web` reads via daemon API" | **40 `drizzle-orm` imports remain** across 39 files in `apps/web/` (state-machine, runner, runs-db, jira/github/gmail sync, integrations page, scheduled-jobs API). `drizzle.config.ts` + `drizzle/` migrations dir + `drizzle-kit` in `package.json` all still live. *(Original 78/14+ count was off; counts updated 2026-05-21.)* |
| ADR 002: "vendor Picovoice Porcupine v3.0 into `voice/vendor/porcupine/`" | Code uses `livekit-wakeword` (ONNX) in `voice/src/wake/livekit.rs`. ADR 002 was amended 2026-05-12 acknowledging Picovoice's Rust SDK abandonment, but the **amendment doesn't name LiveKit as the headline replacement** — it's contextually implied only. Next-Step #2 still pending. |
| ARCHITECTURE.md § 22: "Runs has only `[id]` detail (no listing); Notifications has only `permission/` subpage (no listing); ElevenLabs TTS is a TODO stub that logs the chunk but never plays it" | All three still hold as of 2026-05-21. *(BMO faces sub-claim removed — v2 face system supplanted entirely; `apps/web/public/faces/small/` + `ProxyFace` component shipped via proxy-v2-11/12/13.)* |

**Why this matters**: ADR 004 is the contract a Tachikoma reads when claiming a `daemon/` or `apps/web` slice. If a Tachikoma trusts "Drizzle is dropped" while existing code still uses it, you get the worst-of-both — two ORMs, drift in derived types, doubled migration surface.

## S2. Schema source-of-truth split (HIGH — structural consequence of S1) — **CONFIRMED + REFINED 2026-05-22**

Right now you have:
- `daemon/migrations/` (sqlx) — **44 SQL files** (was 16 on 2026-05-14; +28 added in a week — all v2 5ECH schema + email + drops + state transitions landed here, consistent with sqlx-as-canonical)
- `apps/web/drizzle/` — **11 SQL files** (was 10; +1 only — `0010_notebook_archived.sql`)
- They cover overlapping but non-identical tables (`work_requests`, `runs`, `feed_items`, `scheduled_jobs` exist in both)

**Trajectory note (added 2026-05-22):** net direction is right — schema work clearly went via sqlx, Drizzle stayed near-frozen. But the middle position S2 calls out still bites: 39 files in `apps/web/` still import `drizzle-orm`, including `getDb()` — which is the path the new `/infils` page (shipped 2026-05-21, PR #196 + commit `2bda485`) used to query infils + dossiers server-side. If "Drizzle is dropped" had been reality, that page would consume a `GET /api/infils?callsign=...` daemon endpoint instead. So the doc-vs-code gap is actively pulling new-feature ergonomics toward Drizzle.

This is exactly the failure mode ADR 004 was written to prevent. Until the migration finishes (or the rollback decision is made explicit), every new web feature has to choose Drizzle (legacy) or daemon HTTP API (canonical). The middle position you're in today is the worst place to live.

## S3. Memory coordination is load-bearing and still soft (HIGH — risk-accepted but worth re-examining) — **CONFIRMED + REFINED 2026-05-22**

The whole memory-awareness story rests on: PROXY's sensor → admission rule → never-kill loops, plus PROXY writes `shell_pool_state.paused` → Major's Shells stop claiming. But:

- **2-5s sensor cadence** = a sub-second pressure spike can still kill a newly-spawned loop mid-API-call before admission catches up. (Confirmed: `host_tick: from_secs(2)`, `docker_tick: from_secs(5)` in `daemon/src/sensor/mod.rs`.)
- **Major ADR 022 is still `Proposed`**, not Accepted. Major's memory safety is provided externally by PROXY today. If PROXY is paused/killed/rebuilding, Major regresses to the pre-2026-05-11 crash-prone state. (Confirmed: ADR 022 header still says `Proposed`, date 2026-05-11, unchanged.)
- **Sensor has silent degradation paths**: `read_page_size_bytes().unwrap_or(16_384)` and a cascade of `.unwrap_or()` chains in `daemon/src/sensor/mach.rs`. If macOS releases a `vm_stat` format change, the sensor's memory math drifts 5-10% off without telling anyone. (Confirmed: line 43 `read_page_size_bytes().unwrap_or(16_384)`, lines 202 + 218 additional `unwrap_or` chains.)
- **NEW 2026-05-22 — the `shell_pool_state.paused` mechanism is doc-only.** Zero hits for `shell_pool_state` in `daemon/src/` or `daemon/migrations/`. CLAUDE.md (#16) + ARCHITECTURE.md § 9 (Decision 9) + § 6 (component diagram) all document it as v1 coordination, but the write-back path doesn't exist. Today's actual Major coordination is **observe-only via Docker stats** — no write-back, no pause signal to Major. Major's memory safety today doesn't depend on PROXY being paused/killed — it depends on PROXY having *never written* the coordination flag in the first place. This is worse than the original "soft" finding: it's not soft, it's not wired. Paired follow-up: ADR 022 amendment + ARCHITECTURE.md § 9 qualification, both applied 2026-05-22.

## S4. "Memory-lean baseline" is theoretical (MEDIUM) — **CONFIRMED 2026-05-22**

CLAUDE.md says "Total persistent host RSS added by PROXY (idle): ~50 MB." Static estimate, never measured under load (5+ concurrent loops + daemon + Next.js + Postgres + Major's stack). No startup memory-baseline assertion, no `cargo bench` for the daemon under load, no telemetry tracking the daemon's own RSS over time. The kind of thing that bites silently after months of feature creep.

*(Spot-check 2026-05-22: dev daemon RSS = 12.9 MB — leaner than the ~50 MB target, but no `daemon/benches/`, no baseline assertion in `daemon/tests/`, and the `rss_kb` references in `daemon/src/admission/` are for gating loop spawns against external memory, not for self-monitoring. Observability gap unchanged. Paired follow-up: Next-Step #5 already names "Add daemon-RSS telemetry + baseline assertion in `daemon/tests/`" — keep as-is.)*

## S5. Voice handoff state machine is unspecified in code (MEDIUM) — **REFINED 2026-05-22**

ADR 002 specifies mode-aware mic ownership, but:
- `voice/src/tts/elevenlabs.rs` is a TODO stub — synthesis logs the chunk, never plays it. *(Still confirmed 2026-05-22 — 112 lines, `TODO(shell-09): wire to ElevenLabs MCP`.)*
- ~~Wispr Flow handoff is slated for `shell-06` in M5, not implemented. The mic-grab/release coordination is a comment in an ADR, not a state machine in code.~~ **Outdated 2026-05-22 — implementation landed at `voice/src/modes/wispr.rs` (13 KB, fully wired): `WisprMode` enforces a `daemon_holds_mic: AtomicBool` invariant, `activate()`/`deactivate()` hooks coordinate the supervisor handoff, session-start/end events persist to `proxy_voice_events` without logging transcript content.**
- Mode-switching writes `proxy_voice_state` and emits `LISTEN/NOTIFY voice_mode_changed`, but no test asserts all 4 paths (voice cmd / hotkey / CLI / TUI dropdown) converge atomically to the same DB write. *(Still confirmed 2026-05-22 — `voice/tests/` has `cli_to_store.rs` (CLI), `hey_mode.rs` (hey FSM), `open_mode.rs` (open mode), but no atomicity test across all 4 sources.)*

## S6. 4-tier state boundary leaks personal data into Tier 0 (LOW — minor) — **REFINED 2026-05-22**

~~Grep finds `Pioneer18`, `pioneer`, `jonathan` in `tachikoma-starter`~~ **Re-grep 2026-05-22: `Pioneer18` and `jonathan` are gone (someone cleaned them up since 2026-05-14).** What remains is the lowercase `pioneer` username in example absolute paths inside `docs/v2-5ech-user-guide.md`, `slices/proxy-33-DONE.md`, `skills/tachikoma/SKILL.md`, plus ADR 004's example `db_url = "postgres://pioneer@localhost:5432/proxy"`. Most of these are load-bearing example paths a contributor would translate to their own setup. No secrets, no IP — just usernames.

The 4-tier model is supposed to mechanically prevent this; right now it's documented-only, no lint rule. If the substrate is ever shared with a contractor, the docs still surface the personal-layer owner. *(Severity: residual — mostly resolved by the 2026-05-14→2026-05-21 cleanup; only the lint-rule gap remains.)*

## S7. Email vertical compliance debt is real and inherited (MEDIUM — already accepted) — **REFINED 2026-05-22**

ADR 005 ships in two phases — structural (metadata only, ~60-70% value) v1, body-mode v2 gated on Anthropic BAA (1-4 wk to 2-3 mo timeline). Even structural mode sends `Subject: ...` to Claude, which can leak PHI in subject lines for clinician escalation emails. Risk-accepted in `decisions/relymd-work-data-pragmatic-compliance.md` with **2 tracked TODOs** *(updated 2026-05-22 — was 8 in original reflection; 6 resolved since 2026-05-14. Remaining 2: Deep PHI detector phase-2 implementation + body-flag flip checklist recipe doc)*. Not a PROXY architecture flaw — RelyMD's compliance posture inherited into PROXY's surface. The "deep PHI detector — phase 2" gate is currently TODO-only.

## S8. Slice-plan auto-build edge cases (LOW — already learned) — **CONFIRMED 2026-05-22**

Overnight log documents: cap-without-sentinel pattern (manual ship needed), Cargo.toml union-merge with manual dedupe, "I can't run `cargo` (not on PATH)" toolchain blind spot. Operational issues, not architectural. Already learned. Worth a runbook entry if not present.

*(Re-checked 2026-05-22: zero runbook in `~/projects/personal-nix/wiki/runbooks/` mentions any of the three patterns. The three are still living only in the overnight log, not in a discoverable runbook. **Paired follow-up: write `tachikoma-cap-without-sentinel.md` + extend an existing runbook to cover the Cargo.toml union-merge + cargo-PATH cases.**)*

## S9. Seed → Notebook importer unbuilt (LOW) — **CONFIRMED 2026-05-22**

`wiki/seeds/` is interim per `decisions/seeds-folder.md` — to be migrated by a one-shot importer in M6. M6 is mid-flight (notebook UI shipped, importer not yet). If the importer ships broken or skipped, seeds get orphaned. Mitigation is unimplemented code.

*(Re-checked 2026-05-22: `~/projects/personal-nix/wiki/seeds/` still populated (auto-tachi-pressure-management.PROMOTED.md + ~10 more); zero importer code in `daemon/src/` or `apps/web/src/`. No movement. **Paired follow-up: existing M6 importer slice — keep as planned.**)*

## S10. Computer-use cost-cap layer has no teeth (LOW — v2.0 issue) — **CONFIRMED 2026-05-22**

ADR 003's 8th gate is "cost cap." Default $5/day, $1/intent soft. Enforcement mechanism is unspecified — no DB table, no API hook, no daemon path that pauses on breach. Fine because computer use is v2.0, but the gate is currently documented-only.

*(Re-checked 2026-05-22: ADR 003 still describes the gate at the same line (56). Zero `cost_cap` / `daily_cap` / `cost_limit` references in `daemon/src/`. Computer use itself is still v2.0+, not shipped, so this remains documented-only as expected. **Paired follow-up: noted, no action — gate becomes load-bearing only when computer use slice lands.**)*

## S11. Remote-workhorse promotion triggers are qualitative (LOW — already accepted) — **CONFIRMED 2026-05-22**

`decisions/proxy-defer-remote-workhorse.md` lists 4 triggers. Telemetry to detect them exists in plan but not in code. The `consider-remote-workhorse` recommendation kind isn't yet emitted by `daemon/src/manager/`. A trigger could fire in production and PROXY wouldn't say so.

*(Re-checked 2026-05-22: decision doc still references the recommendation kind; zero hits in `daemon/src/manager/` for `consider-remote-workhorse`. Unchanged since 2026-05-14. **Paired follow-up: existing decision doc names this; promote to a slice when remote becomes a real option.**)*

---

## S12. ADR 005 number collision (LOW — doc hygiene) — **NEW 2026-05-22**

`docs/adr/005-email-management-vertical.md` AND `docs/adr/005-proxy-v2-5ech-theme-overhaul.md` both exist with the same ADR number. Per `CLAUDE.md` ("pre-v2 the ADR-005 slot held the email-vertical ADR; that doc is renumbered by `proxy-v2-21`"), slice `proxy-v2-21` was supposed to renumber the email-vertical ADR. The rename hasn't shipped — both files still claim ADR 005. Pure doc-hygiene drift, no code impact, but two ADRs sharing a number is the kind of thing that confuses future readers + deep-dive agents (both files will be loaded as "ADR 005").

**Paired follow-up: complete slice `proxy-v2-21` (renumber email-vertical ADR to a free number, update CLAUDE.md cross-references). Trivial mechanical edit.**

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
