---
status: open
target_repo: ~/Projects/major
last_updated: 2026-05-16
depends_on:
  - major-pr-155-stream-b
  - major-pr-156-stream-c
  - major-pr-154-stream-d
quality_bar: production
---

# Major — Plan 001 Stream E: test suites + CI gate

Implements Stream E of Major Plan 001 (`~/Projects/major/docs/plans/001-e2e-reliability-fixes.md`). Adds the test suites covering every P0 finding plus a CI workflow that gates merges to `dev`.

**Hard precondition:** PRs #154 (Stream D), #155 (Stream B), #156 (Stream C) MUST be merged before this work starts. Stream E tests are written against the merged surface; running it earlier means re-writing tests when those PRs land.

## Goal

Per Plan 001 § 3 Stream E, deliver:

1. **pgTAP suite** for the 4 RPCs — `claim_next_brief`, `finalize_run`, `apply_change_set`, `reaper_sweep`. Cover: empty queue / normal claim / race (two concurrent calls; only one wins) / idempotent retry (same `(shell_id, claim_idempotency_key)` returns same Run) / skip auto-triage / ownership mismatch on finalize / state-guard / transition-matrix violation / lease-expired sweep / no-op when nothing expired / idempotent re-run.
2. **Deno test** for `supabase/functions/_shared/path_blocker.ts` glob matcher + the aggregator that pulls paths from target Briefs on transition ops (Stream C's F-04 fix).
3. **Deno test** for `major-github-webhook` signature verification + handler smoke. Mocked GitHub `pull_request` payloads → assert derived facts land in `briefs.pr_derived_facts` per ADR 021.
4. **Vitest** for the Shell — abort-on-lease-loss, sandbox cleanup (`/work/.major/` removed), PR-exists detection (Stream D's F-10/14/16).
5. **One e2e integration test** walking: Brief create → triage finalize (auto-apply path) → simulated Shell claim → simulated finalize → simulated PR webhook → confirm QA → Brief `status='done'`. Disposable schema in dev project; otherwise local Postgres if introduced separately.
6. **CI hookup** — GitHub Actions workflow running all suites on every PR to `dev`. Block merge if red.

## Files in scope

- `tests/` — new top-level directory, with subdirs per runtime (`tests/pgtap/`, `tests/edge-deno/`, `tests/shell-vitest/`, `tests/e2e/`) per ADR 020.
- `.github/workflows/ci.yml` — new or amend.
- `package.json` — add `npm test` aggregator + `npm run e2e`.
- Possibly one new migration adding a `major_test` helper schema for pgTAP fixtures (optional; pgTAP usually colocates).

## Files out of scope

- RPC / edge function / Shell source code — owned by Streams B/C/D.
- F-21 (repair telemetry consumer) and F-22 (transition allowlist) coverage if those are deferred at landing time.

## Definition of done

- Every P0 finding from Plan 001 § 5 has at least one regression test. Minimum coverage:
  - F-03 (payload casing mismatch) — pgTAP `apply_change_set` op-payload tests
  - F-04 (path-blocker bypass on transitions) — Deno test for the aggregator
  - F-06 (claim idempotency) — pgTAP `claim_next_brief` retry test
  - F-10 (Shell heartbeat-loss abort) — Vitest
  - F-11 (finalize ownership guard) — pgTAP `finalize_run` ownership-mismatch test
  - F-17 (PR derived facts persistence) — Deno test for webhook handler
  - F-23 (no automated tests) — addressed by the suite existing + CI gate.
- pgTAP suite passes against a fresh DB after `sqlx migrate run` (or `supabase db push`).
- Deno test passes via `deno test` in each function directory.
- Vitest passes via `npm test` in `shell/`.
- The e2e walkthrough succeeds end-to-end without operator intervention (Plan 001 § 6).
- CI workflow merged on `dev`; PR check is required-status on the `dev` ruleset.
- Plan 001 § 5 findings catalogue updated in-place: each F-N marked `RESOLVED <sha>` or `DEFERRED <reason>`.
- Plan 001 file moves to `docs/plans/done/001-e2e-reliability-fixes.md` with archive header naming PRs + commits.

## Feedback loops

- `cd ~/Projects/major && deno test supabase/functions/`
- `cd ~/Projects/major/shell && npm test`
- `pg_prove tests/pgtap/` against dev DB
- CI workflow dry-run via `act` if available

## References

- Plan: `~/Projects/major/docs/plans/001-e2e-reliability-fixes.md` § 3 Stream E + § 5 findings catalogue + § 6 DoD
- Test framework split: `~/Projects/major/docs/adr/020-test-framework-split.md`
- PR derived facts shape: `~/Projects/major/docs/adr/021-pr-derived-facts-storage.md`
- SPEC: `~/Projects/major/SPEC.md` — lifecycle state machine, idempotency key shape, Single Active Run Rule
- AGENTS.md: PRs target `dev`, two-dev review required, author cannot self-approve

## Quality bar

production
