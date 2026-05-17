---
status: grabbed
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-12
---

# PROXY — Fast-dispatch mode (non-interactive Tachikoma launch)

A non-interactive launch path for Tachikoma. Reads everything from a work-request file's frontmatter + body, skips the preflight grill + scaffold confirmation + launch gate, fires the loop immediately in `--afk` mode, returns control to the caller in seconds rather than minutes.

**Why this exists**: discovered 2026-05-12 mid-build of M1. The user (or an upstream claude orchestrator) wanted to fan out Tachikomas in parallel on small slices to speed up the v1.0 build. Tachikoma's existing flow is designed for human-in-the-keyboard preflight — appropriate for fresh work, pure overhead for work-requests that already specify everything. At small-slice scale (~10-15 min of actual work), the 5-10 min of preflight + scaffold + launch ceremony eats the parallelism savings.

This slice unblocks the parallelism math by adding a non-interactive path that trusts the work-request file as a complete PRD.

## Goal

After this slice ships:

- `proxy dispatch <slug>` reads `~/projects/personal-nix/wiki/work-requests/<slug>.md`, validates well-formedness, scaffolds the tachikoma worktree, launches `--afk` mode in background, returns within ~10-20 seconds with the loop PID and worktree path.
- `proxy dispatch --batch slug1 slug2 slug3` fires N tachikomas in parallel from one call (subject to admission rule).
- `POST /api/dispatch { "slug": "..." }` exposes the same path as a REST endpoint, callable from another claude session via `curl`, from the Web UI, or from arbitrary scripts.
- Invalid / underspecified work-requests refuse cleanly with a specific reason and a non-zero exit code that distinguishes "fix the file" from "system error."

This is the architectural fix for "Tachikoma's overhead dominates for small slices."

## Files in scope

- `daemon/src/cli/dispatch.rs` — new CLI subcommand wiring under `clap`
- `daemon/src/api/dispatch.rs` — new REST handler under the daemon's HTTP server
- `daemon/src/validator/work_request.rs` — work-request well-formedness validator
- `daemon/src/tachikoma_invoke.rs` — wraps the tachikoma skill's launch sequence non-interactively (worktree scaffold + `nohup .tachikoma/tachikoma.sh --afk N` + return)
- `daemon/src/cli/mod.rs` — register the new `dispatch` subcommand
- `daemon/src/api/mod.rs` — register the new `/api/dispatch` route
- `daemon/README.md` — document the dispatch CLI + endpoint with examples
- Tests: `daemon/tests/dispatch_integration.rs`

## Files out of scope

- The Tachikoma skill itself stays unchanged. Fast-dispatch is a **wrapper** — it reuses the skill's existing scaffold + launch logic, just skips the interactive grill/gate steps.
- Web UI for managing dispatches (M6's existing scope can extend this later, or a v1.5 slice)
- Modifications to existing interactive `/tachikoma` flow — that path remains fully supported for fresh work

## Stop condition

- [ ] `proxy dispatch <slug>` runs without any prompts, scaffolds a worktree, fires `--afk` in background, returns within 20 seconds
- [ ] Returned output includes: worktree path, branch name, loop PID, log path
- [ ] `proxy dispatch --batch slug1 slug2 slug3` fires 3 parallel tachikomas; each gets its own worktree; admission rule gates total memory
- [ ] `POST http://localhost:3000/api/dispatch -d '{"slug":"<slug>"}'` works end-to-end with the same return shape as the CLI
- [ ] Invalid work-request (missing required fields) → refuses with `✗ work-request not well-formed: <specific reason>` + exit code 2 (user fixable)
- [ ] System error (e.g. git operation fails, daemon not running) → exit code 3 (system issue)
- [ ] Already-running slug (status `grabbed`) → refuses with exit code 4 (concurrent dispatch attempt; user can use `proxy status` to check)
- [ ] README documents: CLI usage, REST endpoint, the well-formedness checklist, error codes, troubleshooting

## Well-formedness checklist

A work-request file is **well-formed** for fast-dispatch when ALL of these pass:

| Check | Why |
|---|---|
| Frontmatter has `status`, `target_repo`, `last_updated` | Required for queue lifecycle |
| `status` is `open` (not `grabbed`, `done`, or `needs-triage`) | Anything else means another agent is on it OR it's done |
| `target_repo` path exists on disk | Can't run a tachikoma against a non-existent repo |
| `target_repo` is a valid git repository (`git -C <path> rev-parse --git-dir`) | Tachikoma needs git worktrees |
| `failure_count` < 2 | Anything ≥ 2 is `needs-triage` and requires manual reset |
| Body contains a `## Goal` section (case-insensitive) with non-empty content | The goal IS the PRD |
| Body contains a `## Files in scope` section (or `files_in_scope:` in frontmatter) | Scope is required for the loop's prompt |
| Body contains a `## Stop condition` section with ≥ 1 checklist item (`- [ ]`) | Definition of done |
| Body length > 100 chars total | Sanity check — a 50-char body is probably a stub |

If any check fails, refuse with the exact failing condition and a hint:
```
✗ Work-request not well-formed:
  - Missing ## Stop condition section with checklist items
  → Add a section header `## Stop condition` followed by at least one
    `- [ ]` checkbox item. See the work-request template for examples.
```

For underspecified work-requests, the fallback path is the existing interactive `/tachikoma queue <slug>` — fast-dispatch does NOT attempt to fill in gaps itself. Trust the work-request author.

## REST endpoint spec

```
POST /api/dispatch
Content-Type: application/json

Request body:
{
  "slug": "<work-request-slug>",
  "afk_cap": 15        // optional, defaults to config value
}

Response (success):
{
  "status": "dispatched",
  "slug": "...",
  "worktree": "/path/to/worktree",
  "branch": "tachikoma/<slug>",
  "pid": 12345,
  "log": "/path/to/log"
}

Response (well-formedness failure):
HTTP 400
{
  "status": "rejected",
  "reason": "missing-stop-condition",
  "message": "Work-request body lacks a ## Stop condition section with checklist items",
  "hint": "Add a section header ## Stop condition followed by at least one - [ ] item"
}

Response (concurrent dispatch):
HTTP 409
{
  "status": "rejected",
  "reason": "already-dispatched",
  "message": "Work-request <slug> is already in status `grabbed` (worktree exists)",
  "existing_worktree": "/path/to/existing"
}
```

Batch endpoint: `POST /api/dispatch/batch` with `{ "slugs": [...] }` — returns an array of the above responses, one per slug, in order.

## CLI spec

```
proxy dispatch <slug>              # single, non-interactive, returns immediately
proxy dispatch --batch <slug>...   # parallel, returns when all are launched (not when they complete)
proxy dispatch --dry-run <slug>    # validate well-formedness without spawning anything
proxy dispatch --json <slug>       # machine-readable output (matches REST shape)
```

Exit codes:
- `0` — dispatched successfully
- `2` — work-request not well-formed (user fixable)
- `3` — system error (daemon down, git failure, etc.)
- `4` — concurrent dispatch (slug already `grabbed`)

## Feedback loops

- `cargo build --release` (workspace member must compile)
- `cargo test --test dispatch_integration` (well-formedness validator + dispatch happy path)
- Manual: create a well-formed test work-request, dispatch it, verify worktree + nohup'd loop survive shell close

## Quality bar

production

## v3 context

Slice in M3 (daemon foundation) — **add as the final M3 slice** after `proxy-11b-pg-scheduler`. Rationale: this depends on:
- `proxy-01b` (daemon scaffold) — for the CLI infrastructure
- `proxy-02-extended` (DB schema) — to read/write work-request state from the queue table (if migrated by then) or files (M3 still uses filesystem queue)
- `proxy-04c` (RunBackend trait + LocalDockerBackend) — for the loop spawning machinery (the dispatch handler reuses this)

Landing this in M3 unlocks parallel Tachikoma fan-out for **M4 onwards**, which means the rest of the v1.0 build can compress significantly via parallel slice execution. Without this, M2 and M3 are sequential by necessity (the orchestrator can't fan out small slices economically).

**Why not v1.5**: the user (or an orchestrator claude) building M4+ benefits from this immediately. Pushing it to v1.5 means M4-M7 still pay the small-slice parallelism tax. Better to invest 2-3 days in M3 to enable the rest.

**See also**:
- `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` § 22 (slice plan)
- `~/Projects/tachikoma-starter/docs/adr/004-cargo-workspace-and-tech-stack-lockin.md` (daemon CLI conventions)
- `~/.claude/skills/tachikoma/SKILL.md` (the skill this slice wraps non-interactively)
- `~/projects/personal-nix/wiki/recipes/agentic-shell-v1-slice-plan.md` (v1.0 slice plan, M3 details)
