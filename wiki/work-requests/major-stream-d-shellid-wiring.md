---
status: open
target_repo: ~/Projects/major
last_updated: 2026-05-16
depends_on: []
quality_bar: production
---

# Major — Wire shellId into callFinalizeRun (F-11 ownership guard completion)

Small Stream D follow-up. After Plan 001 Streams B + D both merged (PRs #155 + #154 on 2026-05-16), the `finalize_run` RPC has a new `p_caller_shell_id` parameter (default `null`) that enables the F-11 ownership guard. The Shell does NOT yet pass this argument — `callFinalizeRun` in `shell/main.ts` omits `caller_shell_id` from the request body, so the guard is bypassed and F-11 stays effectively unclosed even though both PRs landed.

This work-request closes that gap.

## Goal

`major-finalize-run` edge function forwards `caller_shell_id` from the request body into the `finalize_run` RPC call; the Shell sends its `shellId` on every finalize request. F-11's ownership guard fires when a slow Shell tries to finalize a Run that's been re-claimed.

## Files in scope

- `shell/main.ts` — `callFinalizeRun` builds the body; add `caller_shell_id: env.shellId` (or equivalent).
- `supabase/functions/major-finalize-run/index.ts` — read `caller_shell_id` from the request body, pass to the RPC.
- One or two test cases in `shell/main.ts`-adjacent tests (if Stream E lands tests for finalize, this becomes a regression test).

## Files out of scope

- The RPC itself — already shipped in `supabase/migrations/20260512000001_rpc_v2_stream_b.sql` with `p_caller_shell_id` defaulting to null. No SQL changes needed.

## Stop condition

- [ ] `callFinalizeRun` request body includes the Shell's id
- [ ] Edge function forwards it to the RPC as `p_caller_shell_id`
- [ ] Manual or automated test: a deliberate ownership-mismatch finalize request raises the RPC's ownership exception with a clear message
- [ ] `cargo build` / `tsc --noEmit` / `npx tsc --noEmit` (shell) all pass

## Feedback loops

- `cd ~/Projects/major/shell && npx tsc --noEmit`
- `deno test supabase/functions/major-finalize-run/` (when Stream E test suite lands)
- Manual: POST to `major-finalize-run` from a Shell with a deliberately-wrong `caller_shell_id` and verify the RPC raises.

## References

- Plan 001 § 5 finding F-11 + Stream B task 1
- ADR 022 (PROXY/Major pressure-aware admission — adjacent context)
- Stream B migration: `supabase/migrations/20260512000001_rpc_v2_stream_b.sql` — `p_caller_shell_id` parameter
- Stream D PR #154 review: this gap was flagged as a non-blocking follow-up

## Quality bar

production
