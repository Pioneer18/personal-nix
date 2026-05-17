---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: [proxy-v2-05-runner-branching]
quality_bar: production
---

# PROXY v2 — STANDBY flow + grant/deny endpoints (MV2.06)

Implement the STANDBY state transition triggered by tool-gate pause_on, plus the API endpoints handler uses to grant (resume, optionally with new clearance) or deny (recall) a standby request.

## Goal

When an infil hits a pause_on trigger, it transitions to STANDBY, writes a `standby_request` row describing what's needed, and blocks. Handler calls `proxy grant <ref>` or `proxy deny <ref>` (via CLI or web), daemon resolves the standby and either resumes the loop (with new clearance if provided) or transitions to RECALLED.

## Endpoints

- `POST /api/infils/{id}/grant` — body `{ clearance?: <level> }`. Resolves the current standby_request, writes resolution row, transitions infil STATE=LIVE (with updated clearance if provided), unblocks the container.
- `POST /api/infils/{id}/deny` — body `{ reason?: string }`. Transitions infil STATE=RECALLED, terminates the container, marks standby_request resolved.
- `GET /api/infils/{id}/standby` — returns the current open standby_request, if any.

## Files in scope

- `daemon/src/api/infils/standby.rs` (new endpoints)
- `daemon/src/runner/tool_gate.rs` (block-and-wait mechanism)
- `daemon/src/state_machine.rs` (LIVE↔STANDBY, STANDBY→RECALLED transitions)

## Files out of scope

- CLI verbs for grant/deny (proxy-v2-09)
- Web UI surface (proxy-v2-17)
- TUI surface (proxy-v2-16)

## Stop condition

- [ ] STANDBY state can be entered from LIVE via pause_on trigger
- [ ] standby_request row written with `trigger` (impasse / clearance_boundary / irreversible), `requested_clearance` (if applicable), `context` jsonb
- [ ] `POST /api/infils/{id}/grant` resolves the standby and resumes the loop
- [ ] Granting with new clearance updates `infils.clearance` before resume
- [ ] `POST /api/infils/{id}/deny` transitions to RECALLED, kills container
- [ ] Tool gate inside the container respects the resumed clearance
- [ ] State transitions logged via existing `state_transitions` audit (or v2-equivalent)
- [ ] Integration test: infil with patch clearance hits commit boundary → STANDBY → grant with commit clearance → resumes successfully

## Feedback loops

- `cargo test infils::standby`
- Manual: infil Quill with patch clearance on a dossier requiring commit; observe STANDBY; curl grant endpoint; verify resume

## Quality bar

production
