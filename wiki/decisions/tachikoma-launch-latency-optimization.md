---
title: "Tachikoma launch latency optimization — `--prd` flag, parallel scaffold, haiku compaction"
tags: [tachikoma, proxy, performance, skill]
last_updated: "2026-05-16"
status: proposed
---

# Tachikoma launch latency optimization (2026-05-16)

**Status**: Proposed — 2026-05-16.

**Scope**: Modifications to `~/projects/personal-nix/skills/tachikoma/` that reduce per-launch wall-clock cost. Independent of PROXY v2's `LocalDockerBackend` (slice `proxy-04c`) and `proxy-fast-dispatch-mode` (M3); these are skill-side wins that ship under the *current* loop substrate and remain useful after the substrate flip (the `--prd` interface is the natural CLI surface fast-dispatch-mode will wrap).

**Authorizes**: this decision is the ADR required by PROXY's `CLAUDE.md` hard rule #5 ("Edits outside [migration-completion] scope still require an ADR") for the three changes listed below. Companion to [`tachikoma-skill-hardening-2026-05-16.md`](./tachikoma-skill-hardening-2026-05-16.md) — that ADR hardened correctness (ADR 008 principles); this one tightens speed without touching correctness surface.

## Context

The `parallel_tachikoma_pattern` memory captures the operational reality: fan-out only pays off for slices > 30 min of code, because per-launch overhead is uneconomical for small slices. The same memory notes that `proxy-fast-dispatch-mode` (M3 slice, weeks 5-8 of the v1.0 plan) is the canonical fix — but M3 is ~5-8 weeks away.

A read of the current skill (SKILL.md §§ Plan / Scaffold / Launch, `tachikoma.sh.tmpl`) identifies three latency sources addressable *now*, without touching the substrate or waiting for fast-dispatch-mode:

1. **The grill is interactive and unavoidable** for any of the three modes (`local`, `--remote`, `--issue`). A parent claude wanting to fan out *N* tachikomas must invoke `/tachikoma` and answer the grill *N* times. `--issue <N>` skips PRD synthesis but still grills for files-in-scope, quality-bar, and stop-condition. No non-interactive entry point exists.
2. **PRD synthesis and worktree creation are serial.** Plan phase (PRD) completes before Scaffold phase (`git worktree add` + repo-map generation + template rendering) begins. The slug is computable from grill output before Plan starts, so the worktree can be created in parallel.
3. **Compaction uses `planner_model = opus`** by default (per `~/.claude/tachikoma.conf` schema in SKILL.md § Configuration). Every `compaction_interval` iters (default 10) a `claude -p --model "$PLANNER_MODEL"` call regenerates `progress.summary.md`. Compaction is a structured summarization task — Opus is overkill and slow.

These three are independently small wins; bundled they meaningfully shrink the latency floor for fan-out and queue-drain patterns.

### What this ADR does NOT cover

- **MCP allowlist plumbing for `claude -p`.** Initial investigation suggests the `--allowed-tools` flag constrains tool *use* but does not gate MCP server *startup*. Scoping MCPs per loop-iteration needs claude CLI flag research (`--mcp-config` or equivalent) and is deferred to a follow-up ADR if the win warrants the complexity.
- **Warm-claude-process pool / persistent stdin session** for the iteration loop. The bigger structural win (avoid cold-starting `claude -p` *per iteration*) has real memory cost in PROXY's memory-aware substrate. Deferred until `proxy-fast-dispatch-mode` ships and post-this-ADR latency can be re-measured.
- **Switching the orchestrator's own model.** The grill itself runs in whatever model the orchestrator chat is using — not separately configurable from the skill.

## Decision

Implement the following three changes to the Tachikoma skill.

### Change 1 — `--prd <file>` non-interactive entry point

Add a CLI mode that accepts a pre-baked PRD file and skips the grill entirely. Intended for: queue-drain workers, parent-claude fan-out, scripted launches.

**Interface** (rendered into SKILL.md § Invocation):

```
/tachikoma --prd <path-to-prd-json>
/tachikoma --prd <path-to-prd-json> --issue <ref>   # combinable
```

**PRD file shape v1** (extends the local-mode `plans/prd.json` schema in SKILL.md § Plan; canonical schema at `lib/prd-schema.json`):

```json
{
  "schema_version": 1,                    // REQUIRED. Daemon/skill refuses unknown versions.

  "target_repo": "<org/repo>",            // REQUIRED. "org/repo" form. Normalized to local path via per-repo config.
  "goal": "<goal — string, multi-line markdown allowed>",                       // REQUIRED.
  "quality_bar": "prototype | production | library",                            // REQUIRED.
  "stop_condition": "<verifiable stop condition>",                              // REQUIRED.
  "files_in_scope": ["<glob>", ...],      // REQUIRED.
  "files_out_of_scope": ["<glob>", ...],  // REQUIRED.

  "items": [                              // optional. Shape: {id, category, description, steps, blocked_by}. NO `passes` field — execution state, set to false by skill at materialization.
    { "id": "T-001", "category": "functional", "description": "<one-line>", "steps": ["<step>"], "blocked_by": [] }
  ],

  "pr_target_branch": "develop",          // optional. Falls back to local repo state check: develop → dev → main → master.

  "github_issue": "<org/repo>#<N>",       // optional. If set, skill/daemon applies label state machine (agent-running, ready-for-review).
  "epic_slug": "<slug>",                  // optional. ADR 006. v1 unvalidated; M3+ validates against Epic table.
  "operation_slug": "<slug>",             // optional. ADR 007.
  "objective_id": "<id>",                 // optional. Requires operation_slug.

  "iteration_cap": 15,                    // optional. Overrides tachikoma.conf.
  "iteration_mode": "afk",                // optional. Overrides tachikoma.conf.
  "feedback_loops": {                     // optional. Overrides skill defaults.
    "typecheck": "<cmd>",
    "test": "<cmd>",
    "lint": "<cmd>"
  },
  "model": "sonnet",                      // optional. Per-run executor override.
  "planner_model": "haiku-4.5",           // optional. Per-run planner/compactor override.

  "idempotency_key": "<uuid>"             // optional. REST-only; skill ignores. Same key + same blob → existing run id; same key + different blob → 409.
}
```

**Validation**: strict on top-level fields — any unknown key is a hard refusal. Easier to relax than tighten. Schema bumps via `schema_version` when new fields land.

**Decision log** (grill 2026-05-16):

- **`schema_version`**: required, integer. v1 = `1`. Daemon refuses unknown versions with explicit error. Forward-compat hook for breaking changes only (additive fields can ship within the same major version).
- **`target_repo`**: `"org/repo"` form. Daemon (M3) and skill both resolve to local path via per-repo config table (existing schema in ARCHITECTURE.md § Per-repo config, keyed by `repo_path`). Matches `work-request` slug pattern. Future `RemoteDockerBackend` can clone-on-demand from `org/repo` cleanly.
- **`pr_target_branch`**: optional. Fallback uses local repo state check (`develop` → `dev` → `main` → `master`) — works in both modes without network call. Required would be cleaner contract but smart-default keeps the common case ergonomic.
- **Validation strictness**: strict (reject extra top-level fields). v1 ships small + tight; relaxation is reversible, tightening breaks callers.
- **`github_issue`**: optional. Composable with the `--issue` flag — the flag becomes shorthand for "fetch issue, synthesize PRD from it, fill `github_issue` automatically". A pre-baked PRD can set `github_issue` directly without the flag.
- **`epic_slug` / `operation_slug` / `objective_id`**: optional, forward-compat hooks for ADR 006 (Epic+Queue) and ADR 007 (Operations). v1 carries the fields but doesn't validate against tables that don't exist yet. M3+ slices add validation.
- **Email vertical (ADR 005)**: explicitly **out of scope**. Email isn't a coding-loop task. ADR 005's vertical has its own dispatch surface; don't conflate.
- **`items`**: optional. If absent, the goal + stop_condition + (optional) github_issue body provide the spec; the orchestrator-claude decomposes inside the loop. Matches existing `--issue` mode behavior — issue body IS the spec, no JSON items list needed.
- **`goal`**: single string, multi-line markdown allowed. Rendered as-is into `prompt.md`.
- **Items shape**: omit `passes` from input schema. `passes` is execution-side state; skill writes `passes: false` to all items when materializing input PRD to `<WORKTREE_PATH>/plans/prd.json`.
- **`model` / `planner_model`**: optional per-PRD overrides of `~/.claude/tachikoma.conf`. Enables per-run model selection (e.g. fan-out batch overrides `planner_model` for compaction speed).
- **`idempotency_key`**: REST-only. Skill ignores. Standard REST idempotency semantics: same key + same blob = return existing run id (200); same key + different blob = 409 Conflict with `"key reused with different content"`.

**Schema authority**: `lib/prd-schema.json` (JSON Schema draft 2020-12). Skill validates via python3 stdlib (hand-written validator, zero new deps). M3 daemon validates via Rust `jsonschema` crate. Both consume the same schema file.

**Behavior**:

1. Skill validates the PRD against `lib/prd-schema.json`. On any required field missing or malformed, or any unknown top-level key: refuse with a precise error pointing at the field. No grill fallback — explicit failure is the contract.
2. Skill jumps directly from Preflight (precondition checks only, no grill) to Scaffold. Plan phase is a no-op: the PRD file *is* the plan, materialized verbatim (plus `passes: false` per item) to `<WORKTREE_PATH>/plans/prd.json` during scaffold.
3. All scaffold/launch steps proceed as for local mode.
4. **Collision response**: existing `<WORKTREE_PATH>`, `<ISSUE_BRANCH>`, or `<TACHIKOMA_BRANCH>` → skill refuses with explicit info (path + branch names + remediation). REST endpoint returns `409 Conflict` with the same info in JSON body. No auto-retry, no slug-suffix increment — user resolves.
5. The `--issue <N>` flag remains independently usable, including in combination with `--prd`: when both are set, the PRD provides items/scope and the flag fills `github_issue` + applies the label state machine.

**Confirmation prompt**: skill prints a one-screen summary (goal, scope, cap, target branch, worktree path) and asks for a single `y/n` before scaffold. Programmatic callers pass `--yes` to skip:

```
/tachikoma --prd <path> --yes
```

`--yes` semantics: requires `--prd` to be set. Without `--prd`, `--yes` is an error. The earlier tty-check is dropped — it added confusion without safety; the `--prd` requirement is sufficient gating.

**Tests** (new in `lib/`):
- `tachikoma-prd-validation.test.sh` — happy path, each required-field-missing case, each malformed-value case, unknown-top-level-key rejection.
- `tachikoma-prd-collision.test.sh` — existing worktree/branch collision response (skill stdout + REST 409 shape).

### Change 2 — Parallel worktree creation + PRD synthesis

In local and remote-greenfield modes, the slug is computable from grill output before PRD synthesis begins. Today's flow is strictly sequential:

```
grill → synthesize PRD → compute slug → create worktree → scaffold
```

New flow:

```
grill → compute slug → start (worktree create + repo-map gen) in background ─┐
                                                                              ├─ scaffold
                     → synthesize PRD ────────────────────────────────────────┘
```

**Implementation outline** (rendered into SKILL.md § Plan and § Scaffold):

1. After grill, compute slug + paths + branch names (existing Scaffold step 1 logic) *immediately* — before PRD synthesis. Capture into orchestrator-session state.
2. Spawn the worktree-creation and repo-map generation in parallel with PRD synthesis. Concretely: the orchestrator issues `git -C <MAIN_REPO> worktree add ...` and `lib/repo-map.sh ...` via a single Bash invocation that does both, then continues into the PRD-synthesis turn while the Bash invocation completes.
3. At Scaffold start, the worktree directory and repo-map file already exist. Scaffold's remaining steps (template renders, prd.json write, scaffold commit) are unchanged.
4. **Failure mode**: if worktree creation fails (collision, dirty main repo, etc.) it surfaces at Scaffold start — same point the failure surfaces today. PRD synthesis was wasted; this is an acceptable cost because (a) PRD synthesis is fast and (b) the collision check already happens at grill time as a precondition, so failures here are rare.
5. **`--prd` mode is exempt** — PRD synthesis is a no-op there, so there's nothing to parallelize against. Worktree creation proceeds inline.
6. **`--issue` mode**: slug is derivable from issue title before Plan, so parallelization applies. Saves ~1s.

**Tests**: extend existing scaffold smoke tests with a flag that verifies worktree existence at the point Scaffold begins (asserting the parallelization actually fires).

### Change 3 — Default `planner_model = haiku-4.5`

Bump the built-in default for `planner_model` in `~/.claude/tachikoma.conf` from `opus` to `haiku-4.5`.

**Rationale**: `planner_model` is used in exactly two places (SKILL.md § Configuration + § Templates):

1. `lib/progress-summary.sh` — periodic compaction of `progress.txt` into `progress.summary.md`. Structured-summarization task; Haiku 4.5 handles this well.
2. `to-prd` skill invocation (`--remote` mode only) — PRD synthesis from grill output. Still structured-summarization-shaped; Haiku 4.5 handles this well.

Neither is on the critical path for code-generation quality (the executor `model` — separately configured, default `sonnet` — does the actual code work). Defaulting to Haiku saves 5-15s per compaction × compaction-count-per-run (afk-15 with `compaction_interval=10` triggers 1 compaction; afk-50 triggers 5).

**User override**: anyone with `planner_model = opus` (or any other value) in their `~/.claude/tachikoma.conf` is unaffected — the explicit setting wins. Only fresh installs and users who haven't set it pick up the new default.

**Migration**: no migration needed. Existing conf files already set the explicit value; new installs read the new default.

**Tests**: extend `lib/progress-summary.sh` smoke test to verify it accepts both `opus` and `haiku-4.5` as `PLANNER_MODEL` env. No quality bar — output shape matters more than wording.

## Consequences

**Positive:**
- `--prd` unblocks programmatic fan-out below the M3 timeline. Queue-drain workers and parent-claude fan-outs become cheap.
- Parallel worktree + PRD shaves ~1s off every interactive launch. Compounds over a session.
- Haiku compaction is a real per-run win (5-15s × compaction count).
- `--prd` schema becomes the natural input contract that `proxy-fast-dispatch-mode` will wrap when it ships — this ADR's interface choice influences M3's REST/CLI surface design favorably.

**Negative:**
- `--prd` adds a new validation surface. Mitigated by tight schema + clear error messages.
- `--yes` is a new "non-interactive accept" flag. Risk: scripted fan-out without `--prd` accidentally bypasses confirmation. Mitigated by the dual-gate (`--prd` required *and* `--yes` flag — neither alone is sufficient).
- Default Haiku for `planner_model` could degrade compaction quality on edge-case journals. Mitigated by user override; tracked via the frozen eval set (ADR 008 P7) if a regression surfaces.
- Parallel worktree creation surfaces existing-worktree failures *after* PRD synthesis is wasted. Acceptable cost; failure path is well-defined.

**Follow-on work:**

- (Deferred) MCP allowlist plumbing for `claude -p` — investigate `--mcp-config` or equivalent flag; size win.
- (Deferred) Warm-claude-process pool inside the iteration loop. Re-evaluate after this ADR's wins land and `proxy-fast-dispatch-mode` resolves the substrate question.
- (Now, parallel) `proxy-fast-dispatch-mode` slice will wrap the `--prd` interface as its REST/CLI surface; the ADR there can reference this one for the input contract.

## Triggers for revisit

Revisit (with intent to extend with MCP allowlist + warm process pool) when **any one of these is true**:

1. **Fan-out demand**: parent-claude or queue-worker fan-out becomes a regular pattern (≥ 3 fan-outs/week) and post-ADR latency is still the dominant bottleneck.
2. **`proxy-fast-dispatch-mode` ships** and the substrate question is resolved — the warm-pool decision becomes simpler post-flip.
3. **Per-iter MCP cold-start cost is empirically measured** above the trivial threshold (~500ms/iter aggregate). If MCP startup is < 500ms, the deferred work isn't worth the complexity.

## See also

- [`tachikoma-skill-hardening-2026-05-16.md`](./tachikoma-skill-hardening-2026-05-16.md) — companion ADR for correctness changes.
- [`proxy-defer-remote-workhorse.md`](./proxy-defer-remote-workhorse.md) — `RunBackend` trait shape that `proxy-fast-dispatch-mode` will implement.
- `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` § 22 — M3 `proxy-fast-dispatch-mode` slice scope.
- `~/.claude/projects/-Users-pioneer/memory/parallel_tachikoma_pattern.md` — operational reality this ADR addresses.
- `~/projects/personal-nix/skills/tachikoma/SKILL.md` §§ Invocation, Plan, Scaffold, Launch — the surfaces being modified.
