## Summary

- New `POST /api/work-requests/:id/dispatch` on the daemon: runs the live admission rubric before any side effects (503 + structured reason on defer), scaffolds the worktree via `DispatchService` (now split into `scaffold()` + `launch()` halves), flips `work_requests.status` `open → grabbed` atomically with a `state_transitions` row, inserts a `tachikoma_dispatched` audit row, launches the loop via `nohup caffeinate -di`.
- One-click **Start** button on the work-request detail page header. Client component owns POST + pending state + error display; falls back to inline error banner when daemon returns 503/409.
- Cap is configurable via `?cap=N`; falls back to `~/.claude/tachikoma.conf` `iteration_cap`, then to 10.
- `daemon/src/admission.rs` gains a reusable `check_admission()` shared between the CLI (`proxy admission check tachikoma`) and the new endpoint. Docker VM gates collapse to "host has 1 GB free" for the host-process tachikoma path.
- Migration `…_recommendations_kind_tachikoma_dispatched.sql` extends the `system_recommendations.kind` CHECK constraint.
- `docs/ARCHITECTURE.md` documents the new endpoint + dispatch module relationship to the tachikoma skill.

Implements `~/projects/personal-nix/wiki/work-requests/proxy-work-request-dispatch-button.md`. Built on top of `auto-tachi-pressure-management` (PR #52).

## Test plan

- [ ] `cargo test --workspace` passes
- [ ] `cargo clippy --workspace --all-targets -- -D warnings` clean
- [ ] `(cd apps/web && npx tsc --noEmit)` clean
- [ ] Manual happy path: pick an `open` work-request, click **Start**, verify worktree appears, status flips to `grabbed`, tachikoma running per `mcp__tachikoma__tachikoma_status`
- [ ] Manual defer: force pressure (e.g. lower `MIN_AVAIL_MEM_MB`), click **Start**, verify 503 + UI surfaces reason + no worktree
- [ ] Manual conflict: dispatch twice in quick succession — second call returns 409 with status=`grabbed`
- [ ] Verify `system_recommendations` row written with `kind='tachikoma_dispatched'`, slug, worktree path, pid, sensor snapshot

🤖 Generated with [Claude Code](https://claude.com/claude-code)
