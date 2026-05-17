---
title: "Tachikoma skill hardening — implement ADR 008 principles in the current substrate"
tags: [tachikoma, proxy, agent-design, hardening, skill]
last_updated: "2026-05-16"
status: accepted
---

# Tachikoma skill hardening (2026-05-16)

**Status**: Accepted — 2026-05-16.

**Scope**: Modifications to `~/projects/personal-nix/skills/tachikoma/` to implement PROXY ADR 008 (Agent Design Principles) against the *current* loop substrate, until PROXY v2's `LocalDockerBackend` (slice `proxy-04c`) supersedes the skill.

**Authorizes**: this decision is the ADR required by PROXY's CLAUDE.md hard rule #5 ("Edits outside [migration-completion] scope still require an ADR") for the changes listed below.

## Context

PROXY ADR 008 codifies 10 principles every autonomous agent must satisfy. PROXY v2's `LocalDockerBackend` (slice `proxy-04c`) is the long-term home; it doesn't ship until M3 (weeks 5-8 of the v1.0 plan per `~/projects/personal-nix/wiki/recipes/agentic-shell-v1-slice-plan.md`). Until then, the Tachikoma skill is the substrate — and the substrate is currently missing several of the principles.

Concrete gaps identified in the 2026-05-16 research pass:

- **P1 oracle separation**: sentinel is a substring grep on model output — model can lie about tests passing and the harness ships.
- **P2 ACI discipline**: no repo-map injected; every iteration spends turns on `Grep`/`Glob` discovery.
- **P3 planner/executor split**: same model handles plan, execute, self-verify; no `--model` flag passed (silent dependency on CLI default).
- **P5 progress journal compaction**: `progress.txt` is append-only forever; runs past iter 20 risk context rot.
- **P6 PR + CI feedback**: auto-ship opens PR, then loop ends. CI red = manual reload.
- **P7 frozen private eval set**: every `prompt.md.tmpl` change is vibes; no regression measurement.

## Decision

Implement the following changes to the Tachikoma skill. Each maps to one or more ADR 008 principles.

### Change 1 — Verifier-gated sentinel (P1, P8)

`lib/verifier-gate.sh` (new). Called by `tachikoma.sh` *after* the sentinel substring is detected, *before* `exit 0` or ship-fire. Checks (all must pass):

1. `git status --porcelain` empty (working tree clean — no uncommitted leftovers).
2. The last commit's diff is *not* empty (model didn't sentinel without doing work).
3. Re-run `TYPECHECK_CMD`, `TEST_CMD`, `LINT_CMD` from supervisor process (not via `claude`); each must exit zero.
4. Scan the cumulative diff `BASE_BRANCH..HEAD` for cheat patterns: `\.skip\(`, `xit\(`, `xdescribe\(`, `\.only\(`, `# TODO`, `# FIXME`, `pytest\.mark\.skip`, `it\.todo`, `expect\.assertions\(0\)`, `--no-verify`, `pytest\.skip`. Any match fails the gate.
5. Scan the cumulative diff for *deleted* test files (`-` lines on `*.test.*`, `*_test.*`, `tests/**`). Fail if any.

On gate fail: append a `## Iter N — verifier-gate REJECTED` block to `progress.txt` listing which check failed, do NOT ship, do NOT exit, continue iterating (consumes one more iteration budget).

On gate pass: proceed to ship phase as before.

### Change 2 — Repo-map injection (P2)

`lib/repo-map.sh` (new). Generates a token-budgeted repo map at scaffold time. Three tiers, fall-through:

1. If `ctags` is installed: `ctags -R --languages=... -f - <REPO>` filtered to public symbols, capped at ~2K tokens.
2. Else if `tree-sitter` CLI installed: equivalent symbol extraction.
3. Else: `git -C <REPO> ls-files | head -200` + `find <REPO> -type d -not -path '*/node_modules/*' ... -maxdepth 3` formatted as a tree.

Result written to `<WORKTREE>/.tachikoma/repo-map.md`. `prompt.md.tmpl` gets a new `{{REPO_MAP}}` placeholder; SKILL.md scaffold step renders it from the file.

### Change 3 — Explicit `--model` flag + planner/executor split (P3)

`~/.claude/tachikoma.conf` gains two new keys:

```
model = sonnet           # executor model for the iteration loop
planner_model = opus     # planner / evaluator model
```

`tachikoma.sh.tmpl` accepts a `MODEL` placeholder (substituted at scaffold time from `model`). The `run_claude()` function passes `--model "$MODEL"` to `claude -p`. SKILL.md scaffold phase uses `planner_model` for plan synthesis (`to-prd`, PRD decomposition) and for the optional evaluator pass.

### Change 4 — Progress journal compaction (P5)

`lib/progress-summary.sh` (new). Called by `tachikoma.sh` at iter 10, 20, 30. Reads `progress.txt`, invokes `claude -p --model "$PLANNER_MODEL"` with a summarization prompt scoped to dense factual capture, writes `progress.summary.md`. The iteration prompt is updated to instruct the model: "Read `progress.summary.md` if present, then the last 3 entries in `progress.txt`."

### Change 5 — Post-ship CI feedback ingestion (P6) **— REVERTED SAME-DAY**

> **Status (2026-05-16):** REVERTED. See § Reverted same-day at the bottom of this doc.

*Original design (for the historical record):* `ci-fix.md.tmpl` (new). After `ship.md.tmpl` opens the PR, `tachikoma.sh` polls `gh pr checks` for up to `CI_POLL_MINUTES` (default 10). If any required check fails: capture failing-check logs via `gh run view --log`, render `ci-fix.md` from the template with failure logs as `{{CI_FAILURE_LOG}}`, fire one more `claude -p` iteration scoped *narrowly* to fixing CI (allowed_tools restricted to Edit + Read + Bash(git *) + Bash(gh *) + the relevant test/lint commands). On success, push fixup commit and stop. On failure, notify and stop. Only one CI-fixup attempt per ship — further failures escalate to human.

The design landed and was reverted the same day. Reasoning under § Reverted same-day.

### Change 6 — Frozen private eval set (P7)

`lib/eval.sh` (new). Subcommands:

- `eval add <issue-ref>` — pins an issue + the resulting PR's diff stats + optional acceptance script as a regression case.
- `eval list` — show pinned cases.
- `eval run [<case-slug>]` — re-runs Tachikoma against pinned cases on a `eval/<case-slug>` branch; records pass/iters/tokens.
- `eval report` — diff results across runs (regression detection).

Eval cases stored at `~/projects/personal-nix/wiki/tachikoma-eval/` (gitignored if anything sensitive surfaces in diffs).

### Change 7 — Subagent isolation for discovery (P2 extension)

`prompt.md.tmpl` gets a new section: "For large discovery passes (>20 files, full-codebase searches, dependency audits), use the Task tool to spawn a subagent. The subagent returns a summary, keeping your main context clean."

No tool-allowlist change required — `Task` is implicit in Claude Code.

### Change 8 — Parallel fan-out for hard tasks (LE-3)

Documented-only addition to SKILL.md: handlers can launch `/tachikoma --issue N` N times concurrently. The skill already supports per-worktree isolation; each run picks the next available `<repo>-tachikoma-issue-N-<slug>-<discriminator>` path. First verifier-gate-pass wins; the others are stopped via `/tachikoma stop --all`. No code change — leverages existing concurrent-worktree support.

### Change 9 — MicroVM tier deferral (P4 future tier)

Documented-only: the third blast-radius tier (microVM for untrusted/remote) is owned by PROXY v2's deferred `RemoteDockerBackend`, gated on the triggers in [`proxy-defer-remote-workhorse`](proxy-defer-remote-workhorse.md). No code change in the Tachikoma skill.

## Consequences

**Positive:**
- Sentinel can no longer lie — verifier-gate (Change 1) shuts the biggest production-grade gap.
- Iteration cost drops via repo-map injection (Change 2) — fewer discovery turns per iter.
- Cost / quality trade-off is now controllable per-phase (Change 3).
- Long runs (>iter 20) survive context rot (Change 4).
- CI red after auto-ship no longer requires manual intervention in the common case (Change 5).
- Prompt-template iteration becomes measurable instead of vibes (Change 6).

**Negative:**
- Verifier-gate (Change 1) adds 5-15 s per sentinel-accept (re-run typecheck/test/lint from supervisor). Acceptable: correctness ≫ speed.
- Planner/executor split (Change 3) costs more (Opus calls expensive). Bounded by plan-once + evaluator-once-per-ship.
- Repo-map (Change 2) adds tokens to every iteration prompt. Bounded by 2K-token cap in the helper.
- Compaction (Change 4) adds an Opus call every 10 iters. Negligible at our scale.
- CI poll (Change 5) extends ship-phase wall-clock by up to 10 min. Mitigated by parallel-friendly (other tachikomas keep running).

**Migration / sequencing:**
- All changes ship today (2026-05-16). Order:
  1. New library scripts (`verifier-gate.sh`, `repo-map.sh`, `progress-summary.sh`, `eval.sh`) + new template (`ci-fix.md.tmpl`).
  2. `tachikoma.conf` adds `model` + `planner_model` keys.
  3. `tachikoma.sh.tmpl` wires gates + `--model` + post-ship CI poll.
  4. `prompt.md.tmpl` adds `{{REPO_MAP}}` + subagent guidance + summary-aware reading.
  5. `ship.md.tmpl` invokes CI poll.
  6. `SKILL.md` documents all of the above + references ADR 008.
- Existing `.tachikoma/` directories in active worktrees are unaffected — they ran with the prior templates and will continue. Changes take effect on the next `/tachikoma` invocation.

**Supersession:**
- When PROXY v2's `LocalDockerBackend` (slice `proxy-04c`) ships, the Tachikoma skill stops being the primary substrate. ADR 008 governs the new substrate from day one. This decision doc's role ends there.

## Reverted same-day

**Change 5 (Post-ship CI feedback ingestion / ADR 008 P6) — reverted 2026-05-16.**

The CI feedback ingestion piece of Change 5 landed in the morning and was reverted the same afternoon during a grilling session on PROXY v2 state-machine design. The deciding signal was operational: **zero observed firings between landing and reversion.** The handler reported that CI red rates are low ("usually passes, definitely not always") but had never seen P6 actually engage.

This is the YAGNI test failing live — a fresh feature designed for a failure mode without observed-failure data to inform the design. The right time to remove an untested speculative feature is before habits and downstream complexity crystallize around it.

**Cascading wins from the revert:**

- The PROXY v2 5ECH grilling (parallel session) had reached a branching question (Q13) about where post-ship CI-poll should live under strict handler-gated exfil (Q8 = B). That whole question dissolves — daemon exfil → `gh pr create` + auto-merge → state flips to EXFIL'D immediately. Slice `proxy-v2-05a-liveness-and-reaper` stays small (heartbeat + reaper + dossier escalation only; no daemon-side CI watcher, no fix-infil spawn endpoint, no `ci_fix_count` column).
- The supervisor's `tachikoma.sh` lifecycle simplifies: sentinel → verifier-gate → ship → done. No post-ship phase. No narrowed-tool-list branch for fix iterations.
- ADR 008 P6 reads cleaner — "PR as sole touchpoint" is now an active enforcement principle on the auto-ship contract, not a mixed bag of "ship + then sometimes re-engage."
- The `lib/eval.sh` frozen eval set stays simpler — cases don't need to encode CI-poll-and-fix behavior.

**Rollback executed:**

- `~/projects/personal-nix/skills/tachikoma/ci-fix.md.tmpl` — deleted.
- `~/projects/personal-nix/skills/tachikoma/tachikoma.sh.tmpl` — `ci_poll_and_fix` function removed; post-ship call site removed; `CI_POLL_MINUTES`, `CI_FIX_TMPL`, `CI_FIX_PROMPT_FILE`, `CI_FIX_LOG_FILE` variables removed.
- `~/.claude/tachikoma.conf` — `ci_poll_minutes` key removed (if present).
- `~/Projects/tachikoma-starter/docs/adr/008-agent-design-principles.md` — P6 renamed from "PR as sole touchpoint + CI feedback ingestion" to "PR as sole touchpoint"; CI feedback bullet stripped; revert note added.
- This decision doc — Change 5 marked REVERTED with original spec preserved for the historical record.

**If we ever reintroduce post-ship CI handling:**

Design it *from observed failure patterns*, not as a generic auto-fix loop. Likely shapes worth considering when the data exists: (a) categorizing CI failures by type (snapshot drift vs missing migration vs flaky integration vs env mismatch) and only auto-fixing the mechanical categories; (b) putting the CI-poll on the daemon, decoupled from the supervisor lifecycle entirely (matches PROXY v2's daemon-canonical control plane); (c) treating CI failure as a *new infil with a different prompt template*, not a continuation of the original supervisor's lifecycle. Each of those is more invasive than the original P6 but more durable because grounded in observed shapes.

## See also

- [PROXY ADR 008 — Agent Design Principles](~/Projects/tachikoma-starter/docs/adr/008-agent-design-principles.md) — the principles this decision implements
- [`proxy-defer-remote-workhorse`](proxy-defer-remote-workhorse.md) — gates the microVM tier
- [`~/Projects/tachikoma-starter/docs/ARCHITECTURE.md`](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) §10 — slice plan; `proxy-04c` is where ADR 008 lives in v2
- Tachikoma skill: `~/projects/personal-nix/skills/tachikoma/SKILL.md`
