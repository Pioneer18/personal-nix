---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: [proxy-v2-04-presets-seed]
quality_bar: production
---

# PROXY v2 — runner branches on callsign (MV2.05)

Modify the loop runner so it reads the preset for the infil's callsign and injects three behaviors: prompt addendum into the `claude -p` system prompt, pause_on enforcement at the tool gate, emit_cadence filter on comms_event emission. Runner stays one engine — the branching is data-driven.

## Goal

When `proxy infil quill --dossier X --clearance commit` is run, the spawned loop runs Claude with Quill's prompt addendum + Quill's pause_on enforcement + Quill's emit_cadence. Same for Tracer, Phantom, Echo. No four parallel codepaths — one runner, four config-driven behaviors.

## Behavior

Before container spawn, runner:
1. `SELECT * FROM proxy_presets WHERE callsign = $infil.callsign`
2. Compose system prompt = base + preset.prompt_addendum + dossier.acceptance_criteria
3. Pass pause_on list as env var into the container (e.g., `PROXY_PAUSE_ON=impasse,clearance_boundary`)
4. Pass emit_cadence into container (e.g., `PROXY_EMIT_CADENCE=milestone`)

Tool gate (the daemon endpoint Claude calls back to for tool-use events) checks:
- Is this event in `pause_on`? Yes → write `standby_request`, transition infil STATE=STANDBY, block until handler grant/deny
- Else → execute the tool

Event emitter:
- Every tool-use, decision, finding generates a candidate comms_event
- emit_cadence filter: `step` lets all through; `milestone` lets only start, completion, error, blocker through

## Files in scope

- `daemon/src/runner/mod.rs` (read preset, compose prompt, spawn container with env)
- `daemon/src/runner/tool_gate.rs` (new or existing — enforce pause_on)
- `daemon/src/runner/comms.rs` (emit_cadence filter)

## Files out of scope

- STANDBY resolution endpoints (proxy-v2-06)
- EXFIL flow (proxy-v2-07)
- CLI verbs (MV3)

## Stop condition

- [ ] Runner reads preset row at infil start
- [ ] Prompt addendum injected into Claude system prompt (verifiable via container env or claude -p output)
- [ ] PROXY_PAUSE_ON env var present in container
- [ ] Tool gate checks pause_on list; writes standby_request and transitions state on match
- [ ] emit_cadence=milestone filters out step-level events; emit_cadence=step lets all through
- [ ] Existing tests pass; new unit tests for preset application
- [ ] `cargo build` passes; integration test with mock claude run

## Feedback loops

- `cargo build`
- `cargo test runner::`
- End-to-end: create a dossier, infil quill, observe Claude prompt in container (`docker logs`), verify pause behavior on impasse

## Quality bar

production
