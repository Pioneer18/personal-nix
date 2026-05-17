---
status: done
priority: 2
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-15
shipped_pr: https://github.com/MioMarker/tachikoma-starter/pull/56
---

# PROXY — "Start" button on work-request detail page + admission-gated dispatch endpoint

Add a one-click "Start" button to the work-request detail page header at `/work-requests/<id>`. Clicking it calls a new daemon REST endpoint that runs the admission rubric (`proxy admission check tachikoma`, shipped in PR #52) before scaffolding a tachikoma worktree and launching the loop. If admission denies (sustained RED memory pressure, swap above threshold, too many live tachikomas), the endpoint returns 503 with the reason and the UI surfaces it inline near the button — the tachikoma does NOT launch.

## Why now

Today launching a tachikoma requires either (a) a `/tachikoma queue <slug>` skill invocation in a Claude session, or (b) the orchestrator (me) running the scaffold+launch sequence by hand. Both paths bypass admission for slug-form invocations and require an interactive session. As the queue grows, the friction of "open Claude → type /tachikoma queue <slug> → wait for it to scaffold" is no longer the right UX for "I see something I want to run right now, click it." This slice closes the loop: button in the UI → admission gate → launch → status visible immediately.

## Goal

A single button labelled `Start` (or `Launch tachikoma`) lives in the header of `/work-requests/<id>`. Pressing it:

1. POSTs to a new endpoint on the daemon at `POST /api/work-requests/<id>/dispatch`
2. Daemon runs the admission rubric (same logic as `proxy admission check tachikoma`) — if `defer`, returns 503 with `{reason, retry_after_seconds}` in the body
3. If admit: daemon scaffolds the worktree (creates `feat/<slug>` + `tachikoma/<slug>` branches, renders `.tachikoma/` files, commits scaffold) and launches `nohup caffeinate -di .tachikoma/tachikoma.sh --afk <cap>` detached
4. Daemon emits a `tachikoma_dispatched` row to `system_recommendations` for audit
5. Endpoint returns 202 with `{worktree_path, branch, pid, cap}`
6. UI replaces the Start button with a `Tachikoma running (pid N)` chip + a link to a future logs/status surface (out of scope for this slice — just a label is fine)
7. Refresh `/work-requests` list shows the row's status as `grabbed` (daemon flips it in the same transaction as the dispatch)

## Files in scope

- `daemon/src/api/dispatch.rs` (new) — POST handler at `/api/work-requests/:id/dispatch`. Loads the work-request, runs admission, scaffolds worktree, launches loop, writes audit row, returns 202
- `daemon/src/dispatch/mod.rs` (new module) — scaffold + launch logic. Mirrors the markdown scaffold flow in `~/.claude/skills/tachikoma/SKILL.md` (worktree path computation, branch creation, template rendering, file commit). Single source of truth for "how to dispatch a tachikoma" — eventually `/tachikoma queue` should also call this rather than re-implementing in markdown
- `daemon/src/dispatch/scaffold.rs` — pure worktree-scaffold logic (separable for tests)
- `daemon/src/dispatch/launch.rs` — `nohup ... & disown` invocation; captures pid + writes `run.pid`
- `daemon/src/dispatch/templates/` — embedded copies of `tachikoma.sh.tmpl`, `prompt.md.tmpl`, `ship.md.tmpl`. Source of truth still lives in the skill repo, but daemon needs its own copy for runtime use (sync via build script if necessary)
- `daemon/src/main.rs` — wire the new route into the router
- `daemon/src/admission/mod.rs` (extend) — expose the rubric as a reusable `check_admission(&pool) -> Verdict` fn so both the CLI and the new dispatch endpoint use the same code path
- `apps/web/app/work-requests/[id]/page.tsx` — add the Start button to the header (next to the StatusBadge)
- `apps/web/app/work-requests/[id]/dispatch-button.tsx` (new client component) — owns the POST + pending state + error display
- `apps/web/app/api/work-requests/[id]/dispatch/route.ts` (new) — thin proxy that forwards to the daemon's `/api/work-requests/<id>/dispatch`
- `apps/web/src/lib/api/work-requests.ts` — add `dispatchWorkRequest(id)` helper
- `docs/ARCHITECTURE.md` — document the new endpoint + the dispatch module's relation to the tachikoma skill

## Files out of scope

- Refactoring `/tachikoma queue` skill to call the new endpoint — sequencing follow-up; this slice's contract is just "endpoint + button work end-to-end." Bringing the skill onto the endpoint is its own slice.
- Streaming logs / SSE for in-flight tachikoma output — out of scope; future slice can layer that on top.
- A "Stop tachikoma" button on the same page — natural follow-up, separate slice
- Authentication / authorization on the endpoint — daemon is localhost-only; this slice trusts the caller. If exposed beyond loopback later, add auth.
- Dispatch from CLI (`proxy dispatch <slug>`) — should mirror the endpoint logic but is a separate slice. The dispatch module should be designed reusable.

## Stop condition

- [ ] `POST /api/work-requests/<id>/dispatch` exists in daemon, handler implemented
- [ ] Handler runs admission rubric before any side effects; returns 503 with `{reason, retry_after_seconds, sensor_snapshot}` on defer
- [ ] On admit, handler scaffolds the worktree (branches + `.tachikoma/` files + scaffold commit) and launches `tachikoma.sh --afk <cap>` via `nohup caffeinate -di` (caffeinate default true unless overridden by query param)
- [ ] Cap is configurable via `?cap=N` query param; default reads `iteration_cap` from `~/.claude/tachikoma.conf` (falls back to 10 if unreadable)
- [ ] Handler refuses if work-request status is not `open` (returns 409 with reason); refuses if a worktree at the computed path already exists (returns 409)
- [ ] Handler atomically flips `work_requests.status` from `open` to `grabbed` as part of the dispatch — same transaction as the scaffold-commit timestamp where feasible
- [ ] `system_recommendations` row emitted with `kind='tachikoma_dispatched'`, slug, worktree path, pid, sensor snapshot at admission time
- [ ] Endpoint returns 202 with `{worktree_path, branch, pid, cap, admitted_at}`
- [ ] `apps/web/app/work-requests/[id]/page.tsx` renders a `Start` button in the header when status is `open`; button disabled + replaced with `Running (pid N)` chip when status is `grabbed`/`running`; hidden when status is `done` or `needs-triage`
- [ ] Button click hits Next.js proxy route `/api/work-requests/[id]/dispatch` which forwards to the daemon
- [ ] On 503 defer: button shows inline error toast/banner with the daemon's reason (`memory pressure: warn`, `swap_used 12000MB > limit 8000MB`, etc.) — does NOT launch
- [ ] On 202: button transitions to running state immediately, then `router.refresh()` pulls the new status from the API
- [ ] Daemon CLI verb `proxy dispatch <slug-or-id>` invokes the same dispatch module locally (sanity check that the module is reusable across HTTP + CLI surfaces). Returns same exit codes as `proxy admission check tachikoma` for the admission gate, plus 0/4 for dispatch success/failure
- [ ] `cargo test --workspace` passes
- [ ] `cargo clippy --workspace --all-targets -- -D warnings` clean
- [ ] `(cd apps/web && npx tsc --noEmit)` clean
- [ ] Manual end-to-end: pick an `open` work-request, click Start, verify worktree appears + tachikoma running + status flips to `grabbed`
- [ ] Manual defer test: force pressure (e.g. lower `MIN_AVAIL_MEM_MB` env), click Start, verify endpoint returns 503 + UI surfaces the reason + no worktree is created

## Feedback loops

- `cargo test --workspace`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `(cd apps/web && npx tsc --noEmit)`
- Manual: dispatch a small open work-request from the UI, watch the worktree appear in `~/Projects/<repo>-tachikoma-<slug>` and `mcp__tachikoma__tachikoma_status` report it as running

## Quality bar

production

## Design notes

- **Admission integration.** `auto-tachi-pressure-management` (PR #52) added `proxy admission check tachikoma` CLI + the underlying rubric module. This slice exposes the same rubric internally — the dispatch handler imports the admission module and calls `check_admission()` directly rather than shelling out to the CLI. If the CLI form is also useful (for debugging), keep both surfaces but share the implementation.
- **Worktree scaffold = port of skill markdown.** The tachikoma skill's `scaffold phase` is documented in markdown and currently followed by a `claude -p` session. The dispatch module ports that logic into deterministic Rust. Slug normalization, branch naming (`feat/<slug>` + `tachikoma/<slug>`), worktree path (`<parent>/<repo>-tachikoma-<slug>`), template rendering, scaffold commit — all of it. The skill remains as a higher-level orchestration wrapper for interactive flows; the daemon module is the durable substrate.
- **Template embedding.** Templates today live in `~/.claude/skills/tachikoma/*.tmpl`. The daemon can either (a) read them at runtime from a configured path (fragile — depends on filesystem layout) or (b) embed them at build time via `include_str!` (preferred — daemon ships self-contained). Update flow: a small sync script in `scripts/` copies the skill's templates into `daemon/src/dispatch/templates/` and the daemon rebuilds.
- **Atomicity of status flip + scaffold commit.** The current `/tachikoma queue` flow flips status before scaffolding — if scaffold fails, the row is stuck `grabbed`. The endpoint should either: (a) flip-then-scaffold with rollback on failure, or (b) flip after scaffold succeeds. Prefer (b) — scaffold is the side-effect we care about; status reflects "scaffold succeeded and loop is running."
- **`router.refresh()` cadence.** After a successful dispatch, the UI should refresh once to pull the new status. The status chip will move from `Open` to `Grabbed` (or `Running` if we add that intermediate state). No polling required — user can manually refresh to see further state changes for this slice.
- **Local-only daemon.** The dispatch endpoint is hit at `127.0.0.1:4321` — no exposure beyond loopback. If PROXY ever gets remote backends or a public surface, add auth before exposing this endpoint.
- **Conflict cases.** If two clients dispatch the same work-request near-simultaneously, the second call should see status=`grabbed` and refuse with 409. Use a DB-level check (atomic status transition) to enforce this.

## Recommended Tachikoma cap

`--afk 12` — new daemon module + endpoint + admission integration + frontend button + tests across both Rust and TS. Medium-large surface; cap leaves headroom for iteration.
