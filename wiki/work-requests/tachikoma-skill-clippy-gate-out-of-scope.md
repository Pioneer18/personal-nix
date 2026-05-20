---
status: open
target_repo: ~/projects/personal-nix
last_updated: 2026-05-20
quality_bar: production
---

# Tachikoma — verifier/clippy gate fails on out-of-scope pre-existing warnings

The tachikoma verifier gate (ADR 008 P1) runs the work-request's `Feedback loops` as block conditions for emitting COMPLETE. For Rust slices that include `cargo clippy --workspace --all-targets -- -D warnings` in feedback loops, a clean slice can still be blocked by **pre-existing clippy warnings in files outside the slice's `files_in_scope`**.

Observed 2026-05-20 on `proxy-v2-22-provider-schema`: the slice's own work was already shipped (commit `c1906b0`), but the loop refused COMPLETE because **9 `cmp_owned` errors in `daemon/src/runner/clearance.rs`** (out of scope, inherited from PR #160) failed the workspace-wide clippy. This is a false-negative — the slice is done; the warnings are someone else's job.

## Goal

The verifier gate scopes clippy (and analogous workspace-wide lints) to the files declared in the work-request's `files_in_scope`, or at minimum surfaces out-of-scope warnings as a soft-warning instead of a hard block. A slice with clean in-scope code can ship even if unrelated files have lingering warnings.

## Files in scope

- `skills/tachikoma/lib/verifier-gate.sh` — where the feedback-loop gate logic lives
- `skills/tachikoma/SKILL.md` — document the scoping rule
- `skills/tachikoma/tachikoma.sh.tmpl` — only if the gate invocation lives here

## Files out of scope

- The work-request schema (no new frontmatter field needed; `files_in_scope` is already there)
- Changing the underlying tools (`cargo clippy`, `tsc`, etc.) — only the gate's interpretation

## Stop condition

- [ ] `verifier-gate.sh` reads `files_in_scope` from the active work-request and constrains workspace-wide checks accordingly. For `cargo clippy`, prefer `cargo clippy -p <crate>` or path-filtered output diff against the merge-base.
- [ ] Out-of-scope warnings produce a `WARN — N pre-existing warnings in out-of-scope files (ignored)` line in run.log, not a gate rejection
- [ ] Regression test: a slice with one clean in-scope file + one dirty out-of-scope file passes the gate
- [ ] Manual verification — re-run `proxy-v2-22-provider-schema` after fix, gate passes, COMPLETE emits

## Feedback loops

- `bash skills/tachikoma/tests/*.sh`
- Manual: re-dispatch `proxy-v2-22-provider-schema`, confirm gate no longer blocks on `clearance.rs` warnings

## Quality bar

production
