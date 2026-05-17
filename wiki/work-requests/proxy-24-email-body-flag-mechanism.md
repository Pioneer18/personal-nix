---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-13
---

# PROXY — Body-to-Claude flag mechanism (slice 24, email vertical)

The compliance gate. A single `proxy.toml` flag (`[email] body_to_claude = false`) controls whether email body content can be sent to Claude API. Default OFF until BAA signed. Audit-defensible architecture: the flag is wired through the briefing engine (slice 20), iterative compose (slice 23), and any future LLM call against email content.

This slice owns the flag, the type-level guard preventing accidental bypass, the audit-log queries that prove compliance, and the pre-flip checklist.

**This is the most safety-critical slice in the email vertical.** Flag bypass = potential HIPAA breach.

## Goal

Single source of truth for whether bodies flow to Claude. Daemon, web app, and CLI all consult the same `proxy.toml` field. Flipping the flag from OFF → ON is a deliberate operational moment, not a casual config change — gated by a written 6-step checklist.

## Files in scope

- `daemon/src/email/flag.rs` — `BodyFlag` enum + accessor; reads from `proxy.toml`; type-level guard
- All slice 20 + 23 LLM call sites refactored to consume `BodyFlag` via the guard helper (verified by code review and the test below)
- `daemon/src/email/audit_query.rs` — query helpers proving no body went to Claude in structural mode
- `apps/web/src/app/settings/email/flag/page.tsx` — Settings UI: current flag state, BAA status indicator, "Flip flag" button gated by checklist
- `~/projects/personal-nix/wiki/recipes/email-body-flag-flip-checklist.md` — the 6-step pre-flip recipe
- `daemon/src/cli/email_flag.rs` — `proxy email flag {show|flip-to-on|flip-to-off}` subcommand

## Files out of scope

- Briefing engine logic (slice 20) — refactored to consume the guard, but engine logic doesn't change
- Compose logic (slice 23) — same
- BAA procurement (out-of-band, human task)
- Deep PHI detector (phase 2; prerequisite for flip but not implemented in this slice)

## Stop condition

- [ ] `BodyFlag::current()` reads `proxy.toml` `[email].body_to_claude`; returns `Off` or `On` enum variant
- [ ] **Type-level guard**: anywhere body content is sent to Claude must go through `ClaudeCallContext::with_body(body: String, flag: &BodyFlag) -> Result<ContextWithBody, FlagOffError>`. Direct body access in Claude calls is gated by the type system — caught at compile time, not runtime.
- [ ] All existing call sites in slice 20 + 23 audited and refactored to use the guard. Code review confirms zero raw body-string passing to Anthropic SDK.
- [ ] Audit-log query: `query::no_body_sent_since(timestamp: DateTime) -> bool` returns `true` iff no `email_audit_log` row has `body_included=true` since that timestamp. Usable for compliance defense / pre-flip dry-runs.
- [ ] Audit-log query: `query::body_inclusion_summary(from: DateTime, to: DateTime)` returns histogram of body-included calls (count, total token usage, per-sender breakdown)
- [ ] Settings UI shows:
  - Current flag state (red `OFF` / green `ON` chip)
  - BAA status field (manually edited via form — `not_in_place / requested / signed`)
  - Last flip timestamp
  - "Flip flag" button (disabled until 6 checklist items checked)
  - Checklist with 6 items linked to the recipe doc
- [ ] **Flip-to-ON gating**: button disabled until all 6 checklist items are confirmed:
  1. BAA signed (status field = `signed`)
  2. AUP confirmed permits 3rd-party AI on work email
  3. Audit log retention policy defined + storage configured
  4. Deep PHI detector active (Presidio / Comprehend Medical — phase 2)
  5. Dry-run on labeled corpus passed (50-email sample, no leaks)
  6. Revocation drill rehearsed (kill switch tested)
- [ ] Flip-to-ON action: writes `proxy.toml` body_to_claude=true, restarts daemon, runs sanity check that next briefing audit-logs `body_included=true` correctly
- [ ] Flip-to-OFF action: ALWAYS allowed (kill switch); writes flag, kills any in-flight LLM compose, sets all future briefings to heuristic only. No checklist needed.
- [ ] `proxy email flag show` returns JSON: `{state, baa_status, last_flip_at, body_included_count_7d, checklist_complete}`
- [ ] `proxy email flag flip-to-on` (CLI) requires `--confirm-checklist-complete` flag; otherwise returns error referencing the recipe doc
- [ ] `proxy email flag flip-to-off` runs immediately, returns confirmation
- [ ] Recipe doc landed at `~/projects/personal-nix/wiki/recipes/email-body-flag-flip-checklist.md` with the 6-step checklist + rationale for each
- [ ] `cargo test` covers:
  - Flag read / write round-trip
  - Audit query happy + sad paths
  - Type-level guard rejects unguarded body access at compile-time (compile-fail test)
  - Flip-to-on with incomplete checklist returns error
  - Flip-to-off always succeeds
- [ ] `cargo clippy --all-targets -- -D warnings`
- [ ] `npx tsc --noEmit` passes (Settings UI)

## Feedback loops

- `cargo test`
- `cargo clippy --all-targets -- -D warnings`
- `npx tsc --noEmit`
- Manual: flip flag both directions, verify next briefing audit log entry differs (body_included false → true after flip-on)

## Quality bar

production

## v3 context

- See ADR 005 § D1 for the body-gated decision rationale + § D5 for flip-checklist context
- See [`relymd-work-data-pragmatic-compliance`](~/projects/personal-nix/wiki/decisions/relymd-work-data-pragmatic-compliance.md) for broader compliance posture
- **Safety**: the type-level guard is the substantive defense; the Settings UI checklist is a UX defense. Both must hold.
- The kill switch (flip-to-off) is always-allowed by design — if any incident occurs, immediately flip off and investigate
