---
name: tachikoma
description: Autonomous AI coding loop. Interviews for a goal, generates a PRD (local JSON, GitHub greenfield, or existing GitHub issue), launches a capped `claude -p` loop in its own git worktree, then walks you through squash-merge / PR / issue-close. Multiple tachikomas can run concurrently on the same codebase — each in its own sibling worktree. Survives interruption (resumable from disk state). Triggers — `/tachikoma`, `/tachikoma --remote`, `/tachikoma --issue <ref>`, `/tachikoma 138` or `/tachikoma #138` (shorthand for `--issue 138`), `/tachikoma done`, `/tachikoma resume`, `/tachikoma status` (alias `/tachikoma t`), `/tachikoma stop`, `/tachikoma queue` (drain the work-request queue; add `--caffeinated` / `-C` to prevent macOS sleep during long overnight runs), or any natural-language request to start, check on, recover, or wrap up a Tachikoma run ("kick off Tachikoma on issue #138", "AFK this backlog", "check the tachikoma status", "did tachikoma finish", "resume the tachikoma loop", "drain the queue", "work through my queue", "run the queue caffeinated"). For methodology, see Matt Pocock's aihero.dev article and Jeffrey Huntley's Tachikoma Wiggum SOP.
---

# Tachikoma

Autonomous AI coding loop. The user provides an end-state; Tachikoma picks tasks, implements one per iteration, runs feedback loops, commits, and repeats until done or capped.

## Worktree model

Every Tachikoma run gets its own **git worktree**, sibling to the main repo:

```
<main-parent>/<repo>-tachikoma-<slug>/
```

This is what lets you run multiple tachikomas on the same codebase in parallel — each in its own branch, working directory, and `.tachikoma/` state. The main repo can stay dirty during a run; `git worktree add` only needs HEAD, not a clean working tree.

Discovery for `status`, `stop`, `done`, `resume` is **per-repo via `git worktree list`**. No global registry. Cross-repo concurrency (one tachikoma on `platform`, another on `personal-nix`) keeps working as before — different repos, different `.git` dirs.

When you run `/tachikoma` inside any worktree (the main repo, a feature-branch worktree, or anywhere else in the repo), the orchestrator computes the **main repo path** via `git rev-parse --path-format=absolute --git-common-dir` (then `dirname`). New worktrees go as siblings of *that*, regardless of cwd. The new branch is created off **cwd-worktree's HEAD**, so you can tachikoma-off-a-feature-branch by `cd`ing into the worktree that holds it.

Throughout this skill: `MAIN_REPO` = main worktree path, `WORKTREE_PATH` = the new tachikoma worktree, `BASE_BRANCH` = the branch the tachikoma branched off, `TACHIKOMA_BRANCH` = `tachikoma/<slug>`. The orchestrator's own cwd never matters for any operation — every git command uses `git -C <path>`.

## Invocation

| Form | Behavior |
|---|---|
| `/tachikoma` | Plan + run. Mode (existing-issue / local / remote-greenfield) is chosen via two grill questions in Phase 1. Creates a new sibling worktree, scaffolds in it, launches loop. |
| `/tachikoma --remote` | **Fast-path** for remote-greenfield mode — skips the mode-selection grill questions. PRD → `to-prd` → `to-issues` → auto-promoted to `ready-for-agent`. New worktree per run. |
| `/tachikoma --issue <ref>` | **Fast-path** for existing-issue mode — skips the mode-selection grill questions. Uses a GitHub issue body as the PRD; loop scoped to that single issue. New worktree per run. |
| `/tachikoma 138` or `/tachikoma #138` | **Shorthand** — a bare integer or `#N` as the first positional arg is normalized to `/tachikoma --issue <N>`. Same fast-path behavior, same preconditions (7, 8). |
| `/tachikoma done` (optionally `<slug>`) | Manually trigger Phase 6. With `<slug>`, picks that specific completed worktree; otherwise picker if multiple complete, auto-pick if one. Auto-triggered when `/tachikoma` (no args) is run with a single completed worktree in the repo. |
| `/tachikoma resume` (optionally `<slug>`) | Re-launch a previously interrupted loop. With `<slug>`, picks that specific worktree; otherwise picker if multiple recoverable. Auto-offered when `/tachikoma` (no args) is run with recoverable state. |
| `/tachikoma status` (alias `/tachikoma t`, optionally `<slug>`) | Telemetry. With no args: compact summary table across all tachikoma worktrees in this repo. With `<slug>`: drill into that specific loop (PID liveness, iter, last milestone, log tail). Read-only. |
| `/tachikoma stop` (optionally `<slug>` or `--all`) | SIGTERM. Cwd-implicit if cwd is itself a tachikoma worktree. Picker if >1 running. `--all` halts every running tachikoma in the repo. |
| `/tachikoma queue` (optionally `<slug>`) | Drain the work-request queue sequentially — full Phases 1–6 per item, batch preferences set once up front. With `<slug>`: run a single specific queue item. With `--caffeinated` (alias `-C`): prevent macOS sleep for the entire session by wrapping each item's launch with `caffeinate -d`. |
| `/tachikoma queue <repo>` | Queue-drain mode sourced from GitHub. Fetches all `ready-for-agent AND NOT agent-running` issues from `<repo>` (format: `org/repo`), auto-creates linked work_requests for any without one, then runs the normal queue drain (Phases 1–6 per item). Ends with a HITL notification when no `ready-for-agent` issues remain. |

`--remote` and `--issue <ref>` are **fast-paths**, not requirements — bare `/tachikoma` collects the same answers via two grill questions in Phase 1 (existing issue? then, if not, local-or-remote?). Use the flags when you already know the mode and want to skip those questions; either flow lands in the same Phase 2/3 logic.

`<ref>` accepts: `#138`, `138`, or `org/repo#138`. The `org/repo` form must match the cwd repo's `nameWithOwner`; if not, refuse and tell the user to `cd` first.

**Argument normalization (runs before preconditions):** if the first positional argument matches a bare integer (`/tachikoma 138`) or a `#N` pattern (`/tachikoma #138`), rewrite the invocation to `/tachikoma --issue <N>` before any further processing. This means precondition 7 (`gh` auth) and precondition 8 (issue exists, repo matches) apply just as they would for an explicit `--issue` invocation. The shorthand is purely a parsing convenience — it has no effect once normalized.

`<slug>` matches against the trailing slug of the worktree's branch name (e.g. `issue-138-fix-vital-age` matches `tachikoma/issue-138-fix-vital-age`). Substring match is OK if unambiguous; otherwise refuse and list candidates.

Multiple tachikomas can run concurrently in the same repo (in separate worktrees). The per-worktree lockfile (`<wt>/.tachikoma/run.pid`) prevents two loops in the same worktree, but loops in *different* worktrees of the same repo are fine and expected.

## Preconditions (refuse with explanation if violated)

1. cwd must be inside a git repo (`git rev-parse --git-dir`).
2. Repo must have at least one commit (`git rev-parse HEAD` succeeds). Unborn repo = refuse; tell user to `git commit --allow-empty -m init` first. Without this, the loop's dirty-tree check, `git log` references, and squash-merge guidance all break.
3. ~~Working tree must be clean.~~ **Relaxed.** With worktree mode, the tachikoma branch is created off cwd's HEAD via `git worktree add`, which only needs HEAD — the cwd's working tree may be dirty. (The new worktree's working tree is clean by construction.)
4. **cwd must NOT be an active tachikoma worktree.** Refuse if either is true: (a) `<cwd>/.tachikoma/run.pid` exists and the PID is alive, (b) `git -C <cwd> rev-parse --abbrev-ref HEAD` matches `tachikoma/*`. Reason: branching off a mid-tachikoma state would inherit half-finished commits. Tell user to `cd` to the main repo or a non-tachikoma worktree.
5. `claude` CLI on PATH (`command -v claude`).
6. `git worktree` available (Git ≥ 2.5; assume yes on macOS, but verify with `git worktree list` and refuse if it errors).
7. For `--remote`, `--issue`, and `queue <repo>`: `gh` CLI on PATH and authenticated (`gh auth status`). For `queue <repo>`: additionally, `<repo>` must be a valid `org/repo` string and accessible via `gh repo view <repo>`.
8. For `--issue <ref>`:
   - The issue must exist and be open (`gh issue view <num> --json state,title,body,labels` succeeds and `state == OPEN`). This check applies at **every** invocation, not just first-time — a prior Phase 6 squash-merge can auto-close the issue (via `Closes #N`), and a re-run of `/tachikoma --issue <N>` against the same number must refuse rather than silently re-tachikoma a finished issue. If `state != OPEN`, refuse with: "Issue #N is already closed. Reopen it if you want to tachikoma it again."
   - The cwd repo's `nameWithOwner` must match the ref's repo (if user passed `org/repo#N`). If mismatch, refuse — `cd` first.
   - Label vocabulary is **not** a precondition; it is auto-created by Phase 0 (see "Phase 0: label vocabulary setup" below).
9. **No worktree-path or branch collision.** Compute `WORKTREE_PATH` and `TACHIKOMA_BRANCH` (Phase 3) and check up front:
   - If `<WORKTREE_PATH>` already exists (file or dir): refuse with the path.
   - If `git -C <MAIN_REPO> show-ref --verify --quiet refs/heads/<TACHIKOMA_BRANCH>` succeeds: refuse — that branch already exists. Tell user to delete it first or pick a different goal/issue.
   - For `--issue <N>` re-runs against the same issue: this collision is the expected guard. Tell user to clean up the old worktree (`git worktree remove ...; git branch -D tachikoma/issue-<N>-...`) or finish/abandon the existing run.
10. **State detection across worktrees.** Some `.tachikoma/` may exist in some worktree of this repo. Enumerate via `git worktree list --porcelain`, then for each worktree check:

   **a. Loop still alive?** `<wt>/.tachikoma/run.pid` exists and `kill -0 <pid>` succeeds. Note the worktree as RUNNING.

   **b. Outcome on disk?** Read `<wt>/.tachikoma/outcome` if present. Values: `complete`, `cap`, `error`, `stopped`.

   **c. Stale lockfile?** `<wt>/.tachikoma/run.pid` exists with a dead PID — treat as crash, recoverable.

   **d. Working tree dirty inside a worktree with state?** `git -C <wt> status --porcelain` non-empty + `.tachikoma/` present — that worktree's loop crashed mid-commit. Surface to user; resume blocked until they clean up that specific worktree.

   Routing depends on what the user just typed:
   - `/tachikoma` (no args) with **one** completed worktree → Phase 6 on it.
   - `/tachikoma` (no args) with **one** interrupted/recoverable worktree → Phase R on it.
   - `/tachikoma` (no args) with **multiple** terminal worktrees (any combination of complete/recoverable) → present picker; let user choose which to act on.
   - `/tachikoma` (no args) with only RUNNING worktrees → tell user "N tachikomas running. `/tachikoma status` to see them, `/tachikoma stop` to halt one."
   - `/tachikoma <new-args>` (start a new run) — terminal worktrees in the repo are NOT a blocker. Proceed to Phase 1; the user is starting an additional tachikoma alongside whatever's there.
   - Pure stale clutter in some worktree (`.tachikoma/` with nothing meaningful) — ignore unless user is explicitly acting on that worktree.

## Phase 0: label vocabulary setup

Tachikoma uses four GitHub labels for its issue lifecycle: `ready-for-agent`, `agent-running`, `ready-for-review`, `needs-triage`. Before Phase 1 begins — for any invocation that will touch GitHub issues (`--remote`, `--issue <ref>`, `/tachikoma queue <repo>`) — verify the labels exist in the target repo and silently create any that are missing.

Target repo derivation:
- `--issue <ref>`: from the ref (or cwd's `nameWithOwner` if no `org/repo` prefix).
- `--remote`: cwd's `nameWithOwner` (`gh repo view --json nameWithOwner --jq .nameWithOwner`).
- `/tachikoma queue <repo>`: the explicit `<repo>` argument.

1. List existing labels in one call:
   ```bash
   gh label list --repo <org/repo> --limit 100 --json name --jq '.[].name'
   ```
2. Compute the missing set against the four required names.
3. **If all four exist:** print nothing and continue to Phase 1.
4. **If any are missing:** create each missing label silently with `gh label create <name> --repo <org/repo>` (default color/description are fine — these are internal lifecycle labels). Then emit exactly one log line, comma-separated in the order created, and continue to Phase 1:
   ```
   Created missing labels: <name1>, <name2>, ...
   ```

No confirmation prompt — this is infrastructure, not a decision the user needs to weigh in on. If a `gh label create` call fails (auth dropped, rate limit, etc.), surface the raw error and refuse — but never interrupt to ask the user about labels they didn't ask to be asked about.

For bare `/tachikoma` (mode chosen via Phase 1 grill), the mode isn't known at preconditions time. If the user's grill answers route the run into existing-issue or remote-greenfield mode, run Phase 0 the moment that mode is selected — still before any GitHub-mutating step in Phase 2. For local mode, Phase 0 is a no-op; no labels are touched.

## Phase 1: planning grill

Run a Tachikoma-specific grill — do **not** invoke the generic `grill-me` skill. The fields below are required; ask only for those you cannot infer from the conversation context already.

**Open the grill with this framing**, before asking any questions:

> I'll ask ~7 questions to scope this run (goal, quality bar, files in/out of scope, stop condition, mode, cap). Takes ~2 minutes. Type 'cancel' at any point to abort — nothing is created until you approve the plan.

**Cancel path.** If at any point during the grill — including the final "Launch?" prompt — the user replies with `cancel`, `stop`, `exit`, or `nevermind` (or any clear abort intent), respond with exactly *"Cancelled. Nothing was created."* and exit cleanly. Do not write any files, do not create the worktree, do not invoke `to-prd`/`to-issues`. The cancel is honored up until Phase 3 begins; once the worktree exists, the user must use `/tachikoma stop` instead.

In **`--issue <ref>` mode** (fast-path flag, or grill question 3 returned an issue ref): fetch the issue first (`gh issue view <num> --json title,body,labels,comments,assignees`). The issue body is the source of truth for **goal** and **stop condition** — extract them directly. Also scan the issue body (case-insensitive, whole-word) for the quality bar keywords `prototype`, `production`, and `library` — if exactly one matches, pre-fill it and skip question 2 (if multiple distinct keywords appear, the extraction is ambiguous; ask normally). Only grill the user for fields the issue body doesn't cover (typically: files in/out of scope, mode/cap, feedback loops, and quality bar when extraction failed). Confirm the extracted goal/stop-condition with the user before proceeding.

### Required fields

1. **Goal** — one-sentence end-state. "Tachikoma is done when …". *In `--issue` mode: extracted from issue body, confirmed with user.*
2. **Quality bar** — one of:
   - `prototype` ("speed over perfection, shortcuts OK")
   - `production` ("must be maintainable, tests required, no shortcuts")
   - `library` ("public API, backward compatibility matters, careful with breaking changes")

   *In `--issue` mode: skip this question entirely if the issue body contains exactly one of `prototype`, `production`, or `library` (case-insensitive, whole-word). Pre-fill the matched value and surface it in the grill output as `quality bar: <value> (extracted from issue body)`, so the user can override by editing the plan summary before approving. If two or three distinct keywords appear, the extraction is ambiguous — ask normally.*
3. **Existing GitHub issue?** — Ask: *"Do you have an existing GitHub issue to work from? (paste the number, or say no)"*. Skip this question if invoked via the `--issue <ref>` or `--remote` fast-paths.
   - If the user answers with an issue ref (`138`, `#138`, or `org/repo#138`): switch this run into existing-issue mode for the rest of the grill — equivalent to `/tachikoma --issue <ref>`. Apply the `--issue` preconditions now (precondition 7 + 8), fetch the issue, and use its body as the source of truth for goal and stop condition (reconcile with the goal answered in step 1; ask the user to confirm if they diverge). Skip step 4.
   - If the user answers "no" / none / similar: continue to step 4.
4. **Greenfield mode** — Only asked when step 3 was "no" (and not skipped by a fast-path flag). Ask: *"Keep tasks local (faster) or publish to GitHub Issues first? (local / remote)"*.
   - `local` (default) — tasks live in `plans/prd.json`; no GitHub round-trip. Equivalent to bare `/tachikoma`.
   - `remote` — equivalent to `/tachikoma --remote`. PRD goes through `to-prd` → `to-issues` and child issues are auto-promoted to `ready-for-agent`. Apply the `--remote` precondition now (precondition 7).
5. **Files in scope** — explicit globs/paths Tachikoma may modify. Pocock's tip #3 — without this, Tachikoma redefines "done" to exclude inconvenient files.
6. **Files out of scope** — explicit globs/paths Tachikoma must NOT touch. Use a list that does NOT overlap with files-in-scope (e.g., name specific dirs to exclude rather than `**` which matches everything).
7. **Stop condition** — concrete acceptance criteria. "Done" must be testable, not "improve the codebase". *In `--issue` mode: extracted from issue acceptance criteria if present.*
8. **Iteration mode** — Ask: *"How should I run this? **Once** (one iteration, runs now in the foreground — good for quick tasks) or **AFK** (capped loop, runs in the background — good for larger goals)?"* Use plain-language Once/AFK framing in the question itself. The raw flag form (`--once` or `--afk N`) is internal — record it in the grill output summary so the user can see what Phase 5 will execute, but never lead with it in the question. *In `--issue` mode: bias toward Once since the loop is scoped to a single issue.*
9. **Iteration cap** (AFK only) — if user has no preference, suggest based on PRD size: 1–3 items → 5, 4–9 → 15, 10+ → 30. Hard ceiling 50; refuse higher. *In `--issue` mode: cap at 5 unless the user explicitly overrides — single issues rarely need more.*

### Auto-detected fields (confirm with user before locking in)

10. **Feedback-loop commands** — auto-detect from these sources, in order:
   - `package.json` `scripts` keys: `typecheck`/`type-check`, `test`, `lint`
   - `Makefile` targets of the same names
   - `justfile` recipes of the same names
   - `AGENTS.md` / `CLAUDE.md` if they document the canonical commands
   - Cargo / Go / Python equivalents if applicable

   Show the user the detected commands and ask: "These look right? Anything to add/remove?" If nothing detected, ask explicitly. At least one feedback loop must be defined; refuse to launch without any.

### Plan summary + launch confirmation

After the grill, present a single combined view that the user approves once. This is the only approval gate before Phase 2/3 — the legacy Phase 4 prompt-review step has been merged in here so the user reads (and edits) the plan and the prompt's key sections together, then launches with one confirmation.

**Section A — Field summary** (numbered list, all the fields collected above) plus:
- **Iteration mode** (rendered as the raw flag form: `--once` or `--afk N`, so the user can see what Phase 5 will execute even though they answered in plain language)
- **Base branch** (cwd-worktree's current HEAD, where `tachikoma/<slug>` will be rooted and where Phase 6 will merge back)
- **Tachikoma branch** (the computed `tachikoma/<slug>` name)
- **Worktree path** (the sibling dir that will be created via `git worktree add`)

Any field auto-extracted from the issue body (e.g., quality bar in `--issue` mode) must be tagged `(extracted from issue body)` in the summary so the user knows it wasn't asked, and can override it.

**Section B — Rendered prompt preview.** Show the key sections of what `prompt.md` will contain when Phase 3 renders it from [prompt.md.tmpl](prompt.md.tmpl), with placeholders substituted from the grill answers:
- **Goal** (`{{GOAL}}`)
- **Quality bar** — the full `{{QUALITY_BAR_PARAGRAPH}}` for the chosen tier (the loop reads this paragraph as guardrail text; the user should see the exact wording the agent will be primed with, not just the tier label).
- **Files in scope** (`{{FILES_IN_SCOPE}}`)
- **Files out of scope** (`{{FILES_OUT_OF_SCOPE}}`)
- **Stop condition** (`{{STOP_CONDITION}}`)
- **Feedback-loop commands** (`{{TYPECHECK_CMD}}`, `{{TEST_CMD}}`, `{{LINT_CMD}}`)
- **Task source** (`{{TASK_SOURCE_BLOCK}}`) — for `--issue` mode the issue ref + acceptance criteria, for local the PRD shape, for remote-greenfield the parent PRD issue.

Show enough that the user can spot wrong commands, fuzzy stop conditions, or scope mistakes without a separate review step. Don't dump the entire template — the agent reads the full file at iteration time. Boilerplate template scaffolding (`{{COMMIT_INSTRUCTIONS}}`, `{{COMPLETION_INSTRUCTIONS}}`) is omitted from the preview.

**Section B.5 — AFK permission preflight (AFK mode only).** Skip entirely for `--once` mode. For `--afk N`, the Phase 5 launch is `nohup .tachikoma/tachikoma.sh --afk N > .tachikoma/run.log 2>&1 & disown`, which Claude Code's auto-mode classifier blocks unless `Bash(nohup *)` is in the user's settings allowlist. Check up front so the user isn't surprised at launch time:

1. Read `.claude/settings.json` and `.claude/settings.local.json` from the cwd worktree (project-level), then `~/.claude/settings.json` (user-level). Look in each file's `permissions.allow` array for any token that would cover the launch — exact matches `Bash(nohup *)` or `Bash(nohup .tachikoma/tachikoma.sh *)`, or a permissive parent like `Bash(*)`. Any one match is sufficient; absence of all three files is treated the same as no match.
2. **If a matching permission is present:** silently continue to Section C.
3. **If no matching permission is present:** warn the user before launch and offer to add it. Render exactly:

   > ⚠ AFK launch will likely be blocked — `Bash(nohup *)` is not in your `.claude/settings.json` allowlist. Without it, Claude Code's auto-mode classifier will refuse the `nohup ... & disown` invocation when Phase 5 fires it, and you'll have to retry or run it yourself.
   >
   > Add `Bash(nohup *)` to project `.claude/settings.json` via `/update-config` before launch? (yes / no / show)

4. **On `yes`:** invoke the `update-config` skill with the request `add "Bash(nohup *)" to permissions.allow in project-level .claude/settings.json`. Wait for it to complete, then re-read the file to verify the entry now appears. Continue to Section C.
5. **On `no`:** continue to Section C unchanged. The Phase 5 blocked-launch fallback (see `--afk N` below) will still print the `!` recovery command if the launch is in fact blocked, so the user has a clear next step.
6. **On `show`:** print the exact JSON delta `/update-config` would apply (the `Bash(nohup *)` token added to `permissions.allow`, with surrounding context for clarity), then re-ask the yes/no/show question.

This preflight runs only in Phase 1 (initial planning). Phase R's Resume path does not re-run it — the Phase 5 blocked-launch fallback covers re-launches.

**Section C — Launch confirmation.** Ask exactly one question, phrased per iteration mode:
- AFK mode: *"Launch the AFK loop (cap N)?"*
- Once mode: *"Launch foreground loop?"*

If the user requests edits to any field (a scope glob, the stop condition, a feedback-loop command, etc.), edit the grill data in-conversation, re-show Sections A + B, and re-ask Section C. There is no second approval after this — once the user says yes, Phase 3 renders `prompt.md` to disk using the approved fields and Phase 5 launches immediately.

## Phase 2: PRD synthesis (mode-forked)

### Local mode (default)

Synthesize `plans/prd.json` directly from grill output. Shape:

```json
{
  "goal": "<grill goal>",
  "quality_bar": "<prototype|production|library>",
  "files_in_scope": ["<glob>", ...],
  "files_out_of_scope": ["<glob>", ...],
  "stop_condition": "<grill stop_condition>",
  "items": [
    {
      "id": "T-001",
      "category": "functional|refactor|test|docs|spike",
      "description": "<one-line>",
      "steps": ["<verification step 1>", "<verification step 2>"],
      "blocked_by": [],
      "passes": false
    }
  ]
}
```

Decompose the goal into vertical-slice items. Each item should be small enough that one iteration can verify it with 1–2 unit tests or one E2E flow (Pocock's tip #6). If you can't decompose, ask the user to break the goal down further.

### Remote-greenfield mode (`--remote`)

1. Invoke the `to-prd` skill with the grill output as conversation context. It will publish a parent PRD issue with `needs-triage`.
2. Invoke the `to-issues` skill against the PRD. It will publish vertical-slice child issues, also with `needs-triage`.
3. For each child issue, render an agent brief from [AGENT-BRIEF.tmpl](AGENT-BRIEF.tmpl) using grill data + the issue body, post it as a comment, and apply the `ready-for-agent` label.
4. Remove the `needs-triage` label from each promoted issue.

The `to-prd` and `to-issues` skills require their issue-tracker mapping config (which abstract states map to which concrete labels). Run `/setup-matt-pocock-skills` first if not configured. (Label *existence* in the target repo is handled separately by Phase 0 above.)

### Existing-issue mode (`--issue <ref>`)

The issue **is** the PRD. No `to-prd`/`to-issues` calls; no `plans/prd.json`.

1. Fetch the full issue: `gh issue view <num> --json title,body,labels,comments,assignees,number`. You should already have done this in Phase 1.
2. Render an agent brief from [AGENT-BRIEF.tmpl](AGENT-BRIEF.tmpl) using the grill answers + the issue body's existing content. Lean heavily on the issue body — don't restate what's already there. The brief is a *supplement*, not a replacement.
3. Post the rendered brief as a new comment on the issue. Even if a prior brief comment exists, post a fresh one — old briefs may have stale assumptions; let the human reading the issue see the timestamp progression.
4. Apply the `ready-for-agent` label to the issue. If `needs-triage`, `needs-info`, or any other state label is present, remove it.
5. Capture the issue number — the loop's task source will be scoped to it specifically (not the broader `ready-for-agent` query).

If the issue is already labeled `ready-for-agent` and has a recent agent-brief comment from a prior `/tachikoma` invocation, ask the user whether to repost a fresh brief or reuse the existing one.

**Work_request auto-creation (issue mode)**:
1. Compute slug: `issue-<N>-<slug-of-title>` (same normalization as `TACHIKOMA_BRANCH` slug).
2. Check if `~/projects/personal-nix/wiki/work-requests/<slug>.md` already exists AND its `github_issue` field matches this issue. If so, reuse it — do not duplicate.
3. If no matching work_request exists: create `~/projects/personal-nix/wiki/work-requests/<slug>.md` using the work-request template. Fill from the issue body: goal = issue title, stop_condition = acceptance criteria if present, target_repo = `git -C <cwd> rev-parse --show-toplevel`. Set `github_issue: <org/repo>#<N>`, `status: open`.
4. This applies to both `/tachikoma --issue N` (single-issue fast-path) and queue mode sourced from GitHub.

## Phase 2.5: label claim (issue-linked runs)

For any run with a linked `github_issue` (from `--issue <N>`, `/tachikoma queue <repo>`, or a work_request with `github_issue` set):

**Before creating the worktree** (after Phase 2, before Phase 3):

1. Apply `agent-running` label to the issue, remove `ready-for-agent`:
   ```bash
   gh issue edit <N> --repo <org/repo> --add-label "agent-running" --remove-label "ready-for-agent"
   ```
2. Re-fetch the issue: `gh issue view <N> --repo <org/repo> --json labels`. Verify `agent-running` is present. This is the optimistic distributed lock — if another agent claimed it first, the label state will be inconsistent. If `agent-running` is absent, refuse and skip to the next issue (queue mode) or exit with a message (single-issue mode).
3. Update the linked work_request: `status: open` → `status: grabbed`, bump `last_updated`.

The `agent-running` label is the distributed claim signal. A concurrent Tachikoma filtering `ready-for-agent AND NOT agent-running` will not see this issue after step 1.

## Phase 3: worktree creation + scaffolding

1. **Compute slug.** Source depends on mode:
   - Local / Remote-greenfield: derive from grill goal.
   - `--issue`: derive from issue title; the final slug is `issue-<N>-<normalized-title>`. Keeps the issue number for traceability.

   Slug normalization (applied in this order):
   1. **Strip leading commit/scope prefix.** If the source begins with `<word>:` or `<word>(<scope>):` (e.g. `feat:`, `fix(api):`, `tachikoma:`), drop everything up to and including that colon. These prefixes are commit-message noise, not path-worthy.
   2. **Lowercase + dash-separate.** Replace each run of non-alphanumeric chars with a single `-`.
   3. **Drop `tachikoma` tokens.** Remove any standalone `tachikoma` from the slug. The worktree path separator already injects one (`<REPO_NAME>-tachikoma-<slug>`); a second copy yields paths like `<REPO_NAME>-tachikoma-tachikoma-...`.
   4. **Drop `<REPO_NAME>` substring.** Remove the repo dirname as a whole substring (multi-word repo names like `personal-nix` are matched as a single unit, not per-token). The repo name is already the parent dirname; repeating it is redundant.
   5. **Collapse and trim.** Collapse runs of `-` to a single `-`, then strip leading/trailing `-`.
   6. **Cap at 40 chars total** — for `--issue` mode this cap applies to the *combined* `issue-<N>-<normalized-title>` string, not to the title portion alone — then re-trim any trailing `-` produced by truncation.

   This bounds the worktree-path slug at 50 chars after the repo prefix (`tachikoma-` + 40-char slug). Worked example: title `tachikoma: shorten worktree path slug` in repo `personal-nix` for issue #4 → slug `issue-4-shorten-worktree-path-slug` → path `personal-nix-tachikoma-issue-4-shorten-worktree-path-slug`.

2. **Compute paths and capture variables:**
   - `MAIN_REPO` = `dirname` of `git -C <cwd> rev-parse --path-format=absolute --git-common-dir`. This is the main worktree's path regardless of which worktree the user invoked from.
   - `REPO_NAME` = `basename "$MAIN_REPO"` (e.g. `platform`).
   - `TACHIKOMA_BRANCH` = `tachikoma/<slug>` (e.g. `tachikoma/issue-138-fix-vital-age`).
   - `WORKTREE_PATH` = `<dirname $MAIN_REPO>/<REPO_NAME>-tachikoma-<slug>` (e.g. `/Users/pioneer/Projects/platform-tachikoma-issue-138-fix-vital-age`).
   - `BASE_BRANCH` = `git -C <cwd> rev-parse --abbrev-ref HEAD` — captured from the **cwd worktree**, not main repo. This is the branch the new tachikoma branches off, and the merge target for Phase 6.

3. **Collision check** (precondition 9 applied here in detail):
   - If `<WORKTREE_PATH>` exists: refuse with the exact path. Tell user to remove it (`git -C <MAIN_REPO> worktree remove <WORKTREE_PATH>`) or pick a different goal.
   - If `<TACHIKOMA_BRANCH>` already exists (`git -C <MAIN_REPO> show-ref --verify --quiet refs/heads/<TACHIKOMA_BRANCH>`): refuse and tell user to delete it (`git -C <MAIN_REPO> branch -D <TACHIKOMA_BRANCH>`) or finish/abandon the existing run.

4. **Create the worktree:**
   ```bash
   git -C <MAIN_REPO> worktree add <WORKTREE_PATH> -b <TACHIKOMA_BRANCH> <BASE_BRANCH>
   ```
   This creates the worktree directory, the new branch, and checks the branch out in that worktree.

5. **Scaffold inside the worktree.** All paths below are relative to `<WORKTREE_PATH>`:
   - Append `.tachikoma/` to `<WORKTREE_PATH>/.gitignore` if not already there.
   - Create `<WORKTREE_PATH>/.tachikoma/`.
   - Render `<WORKTREE_PATH>/.tachikoma/tachikoma.sh` from [tachikoma.sh.tmpl](tachikoma.sh.tmpl). **Set `{{REPO_PATH}} = WORKTREE_PATH`** (the script's `cd "$REPO"` keeps everything inside the worktree). `chmod +x`.
   - Render `<WORKTREE_PATH>/.tachikoma/prompt.md` from [prompt.md.tmpl](prompt.md.tmpl).
   - Write `<WORKTREE_PATH>/.tachikoma/base_branch` — single line containing `<BASE_BRANCH>`. Phase 6 reads this to know the merge target. (Conversation context isn't enough — AFK runs span sessions.)
   - In **local** mode only: write `<WORKTREE_PATH>/plans/prd.json`.

6. **Commit the scaffolding inside the worktree** so the loop's first iteration has a clean tree. Use `git -C <WORKTREE_PATH>`:
   - Local: `git -C <WORKTREE_PATH> add .gitignore plans/prd.json && git -C <WORKTREE_PATH> commit -m "chore: scaffold tachikoma loop for <slug>"`
   - Remote-greenfield: `git -C <WORKTREE_PATH> add .gitignore && git -C <WORKTREE_PATH> commit -m "chore: scaffold tachikoma loop for <slug>"`
   - `--issue`: `git -C <WORKTREE_PATH> add .gitignore && git -C <WORKTREE_PATH> commit -m "chore: scaffold tachikoma loop for issue #<N>"`
   - `.tachikoma/` itself is gitignored — rendered scripts, logs, and `base_branch` do not get committed.

7. **Print the worktree path prominently.** The orchestrator's cwd doesn't change, so the user needs the path to tail logs, open the worktree in an editor, or cd there manually. Format:
   ```
   Worktree: <WORKTREE_PATH>
   Branch:   <TACHIKOMA_BRANCH>  (off <BASE_BRANCH>)
   Tail:     tail -f <WORKTREE_PATH>/.tachikoma/run.log
   ```

> Phase 4 (the standalone prompt review) was merged into Phase 1's combined plan-summary-and-launch confirmation. Phase 5's number is preserved so cross-references in this skill, in run logs, and in user muscle memory stay valid; there is no separate gate between Phase 3 and Phase 5.

## Phase 5: launch

The orchestrator's cwd doesn't matter — both modes `cd` into `<WORKTREE_PATH>` first.

### `--once`
Run via Bash tool in foreground:
```bash
cd <WORKTREE_PATH> && .tachikoma/tachikoma.sh --once
```
Stream output. When the Bash tool returns, route on exit code:

- **Exit 0** (clean completion): show the user `cat <WORKTREE_PATH>/.tachikoma/progress.txt`, then **immediately enter Phase 6** (the orchestrator is still in-session; don't print manual git instructions).
- **Non-zero exit** (Ctrl+C, internal error, or any other abnormal termination): read `<WORKTREE_PATH>/.tachikoma/outcome` and route on its value:
  - `stopped` — the user pressed Ctrl+C and the script's signal trap fired. Tell them: *"Loop was interrupted (Ctrl+C). What would you like to do?"* and immediately present the Phase R options (Resume / Review / Restart) with `WORKTREE_PATH` already selected (skip Phase R Step 0).
  - `error` — the loop exited on an internal error. Tell them: *"Loop exited with an error at iter N. Check `<WORKTREE_PATH>/.tachikoma/run.log`."* Then offer the same Phase R options.
  - missing or `unknown` — the script never wrote an outcome file (e.g. killed with SIGKILL before its trap could fire). Report the raw exit code and the path to `<WORKTREE_PATH>/.tachikoma/run.log`; do not auto-route to Phase 6 or Phase R. The user decides.

This replaces the prior implicit "any exit goes to Phase 6" behavior — a Ctrl+C'd `--once` run is not complete and must not feed into the squash-merge prompts.

### `--afk N`
Launch backgrounded and detached so it survives this session ending:
```bash
cd <WORKTREE_PATH> && nohup .tachikoma/tachikoma.sh --afk N > .tachikoma/run.log 2>&1 & disown
```

**If the launch is blocked** by Claude Code's auto-mode classifier (the Bash tool call returns a permission/auto-block error rather than backgrounding the process), do NOT just re-prompt for retry. Immediately surface a recovery path with both options the user actually has:

> ✗ Auto-mode classifier blocked the AFK launch — `nohup ... & disown` is not in your `.claude/settings.json` allowlist.
>
> Two ways forward:
>
> **1. Add the permission so future AFK launches just work** (`/update-config`):
>    `/update-config add "Bash(nohup *)" to permissions.allow`
>    Then I'll retry the launch.
>
> **2. Run it yourself right now via `!` escape** (paste this verbatim into the prompt):
>    `!cd <WORKTREE_PATH> && nohup .tachikoma/tachikoma.sh --afk N > .tachikoma/run.log 2>&1 & disown`
>    The `!` prefix bypasses the classifier. The loop will start immediately and survive this session ending.

Substitute the real `<WORKTREE_PATH>` and `N` into the `!` command — it must be paste-ready, not a placeholder. If the user picks option 1, after `update-config` finishes, retry the original Bash launch once before falling back to option 2 again. If the user picks option 2, wait for them to confirm they ran it, then read `<WORKTREE_PATH>/.tachikoma/run.pid` to capture the PID for the post-launch message below. Either way the user always sees the `!` command — never just a bare retry prompt.

After launch, give the user a compact post-launch message with these pointers (in this order):
- **Worktree**: `<WORKTREE_PATH>`
- **PID**: `<pid>`, branch `<TACHIKOMA_BRANCH>` (off `<BASE_BRANCH>`), cap `N` iterations
- **Tail**: `tail -f <WORKTREE_PATH>/.tachikoma/run.log`
- **Check in**: `/tachikoma status` (or `/tachikoma t`) — read-only telemetry across all running tachikomas in this repo
- **Stop**: `/tachikoma stop` (picker if >1 running) or `kill <pid>`
- **When done**: macOS notification fires; then `/tachikoma` (no args) auto-routes to Phase 6. If multiple loops are done, picker chooses which to merge.

Do NOT print manual `git log`/`git merge`/`git branch -D`/`git worktree remove` instructions — Phase 6 handles those.

## Phase 6: post-completion review

Triggered when:
- `--once` mode finishes (orchestrator transitions immediately, with `WORKTREE_PATH` already known from this session).
- User runs `/tachikoma done` (optionally `/tachikoma done <slug>`).
- User runs `/tachikoma` with no args and exactly one worktree of this repo has `.tachikoma/outcome=complete`.
- User runs `/tachikoma` with no args, **multiple** worktrees have terminal outcomes, and they pick a complete one from the picker.

**Step 0 — Pick the tachikoma worktree, capture variables.**

Enumerate via `git -C <cwd> worktree list --porcelain`. For each worktree, check `<wt>/.tachikoma/outcome`. Among those with `outcome=complete`:
- If exactly one: that's `WORKTREE_PATH`.
- If user passed `/tachikoma done <slug>`: match against the worktree's branch name; refuse if no match.
- Otherwise: present picker via AskUserQuestion. (`--once` mode skips this — the orchestrator already knows.)

Then capture:
- `WORKTREE_PATH` — chosen above.
- `TACHIKOMA_BRANCH` = `git -C <WORKTREE_PATH> rev-parse --abbrev-ref HEAD` (must start with `tachikoma/`; refuse if not).
- `BASE_BRANCH` = contents of `<WORKTREE_PATH>/.tachikoma/base_branch` (single line). Fallback: ask user. Without this we can't safely merge.
- `MAIN_REPO` = `dirname` of `git -C <WORKTREE_PATH> rev-parse --path-format=absolute --git-common-dir`.

**Step 1 — Locate the base-worktree.**

Find the worktree where `<BASE_BRANCH>` is currently checked out (parse `git -C <MAIN_REPO> worktree list --porcelain` for `branch refs/heads/<BASE_BRANCH>`). Call it `BASE_WT`.

- If found: continue.
- If not found (base branch isn't checked out anywhere): the main worktree is the place to do the merge. Set `BASE_WT = MAIN_REPO`. We'll check out `<BASE_BRANCH>` there in Step 2 — but only if `MAIN_REPO`'s working tree is clean.

**Step 2 — Verify base-worktree is clean.**

Run `git -C <BASE_WT> status --porcelain`. If non-empty: refuse with a clear message naming the path. The user must commit/stash/discard work in `<BASE_WT>` before we can merge there. Do NOT auto-stash — stash conflicts on pop are worse than the friction.

**Step 3 — Show what changed.** Run:
```bash
git -C <WORKTREE_PATH> log <TACHIKOMA_BRANCH> ^<BASE_BRANCH> --oneline
git -C <WORKTREE_PATH> diff <BASE_BRANCH>...<TACHIKOMA_BRANCH> --stat
```
Present output verbatim. Don't summarize.

**Step 4 — Offer squash-merge.** Ask: *"Squash-merge `<TACHIKOMA_BRANCH>` into `<BASE_BRANCH>` (in worktree `<BASE_WT>`)?"*
- On yes:
  ```bash
  # If BASE_BRANCH wasn't checked out in MAIN_REPO yet:
  git -C <BASE_WT> checkout <BASE_BRANCH>

  # Merge:
  git -C <BASE_WT> merge --squash <TACHIKOMA_BRANCH>
  ```
  Propose a commit message — for `--issue` mode use `<issue-title> (#<N>)\n\nCloses #<N>`; for local/remote use a summary derived from the goal. Show the proposed message and let user edit before:
  ```bash
  git -C <BASE_WT> commit -m "<approved message>"
  ```
  Capture the new commit SHA for Step 7.
- On "let me review first" / no: exit Phase 6 quietly. The worktree, branch, and `.tachikoma/outcome=complete` all stay — `/tachikoma done` works again later.

**Step 5 — Combined worktree + branch cleanup.** Only after a successful merge. Single prompt:

> *"Delete worktree `<WORKTREE_PATH>` and branch `<TACHIKOMA_BRANCH>`?"*

- On yes:
  ```bash
  git -C <MAIN_REPO> worktree remove <WORKTREE_PATH>
  ```
  If that fails because of untracked files (e.g. `.tachikoma/run.log`), retry with `--force`:
  ```bash
  git -C <MAIN_REPO> worktree remove --force <WORKTREE_PATH>
  ```
  Then delete the branch:
  ```bash
  git -C <MAIN_REPO> branch -D <TACHIKOMA_BRANCH>
  ```
  (`-D` is required — squash-merge isn't fast-forward, so `-d` would refuse.)
- On no: leave both. User can clean up manually later via `git worktree remove ...` and `git branch -D ...`. They might want to copy something out of the worktree first.

**Step 6 — Offer PR.** Only if `git -C <BASE_WT> remote -v` shows a remote AND `gh auth status` succeeds: *"Push `<BASE_BRANCH>` and open a PR?"*
- On yes:
  - Push if needed: `git -C <BASE_WT> push -u origin <BASE_BRANCH>`
  - Open PR: `gh -R <owner/repo> pr create --title "<derived>" --body "<derived>" --base <default-branch> --head <BASE_BRANCH>`. For `--issue` mode, body should reference `Closes #<N>`. Show the proposed title/body and let user edit before running.
  - Print the PR URL. Capture for Step 7.
- On no: skip; user can do it manually later.

For any run with a linked `github_issue` (applies regardless of whether a PR was opened):
```bash
gh issue edit <N> --repo <org/repo> --add-label "ready-for-review" --remove-label "agent-running"
```

**Step 7 — Offer to close the issue** *(`--issue` mode only)*. Ask: *"Close issue #<N> now?"*

Note: this is human-approved closure, not autonomous. The "agents don't close issues" convention applies to the AFK loop in Phase 5, NOT to Phase 6.

Smart default:
- If a PR was opened in Step 6 AND `<BASE_BRANCH>` is the repo's default branch: recommend **"no"** — GitHub auto-closes on merge via `Closes #<N>`.
- If a PR was opened but `<BASE_BRANCH>` is NOT the default: recommend **"yes"**.
- If no PR was opened: recommend **"yes"**.

On yes:
```bash
gh issue close <N> --comment "Resolved via Tachikoma: squash-merged <TACHIKOMA_BRANCH> into <BASE_BRANCH> as <commit-sha>.<pr-line-if-any>"
```
Where `<pr-line-if-any>` is `\nPR: <url>` if a PR was opened, else empty.

**Step 8 — Final cleanup.**
- If Step 5 user said yes: worktree (and `.tachikoma/`) are gone. Nothing more to do for git state.
- If Step 5 user said no: remove `<WORKTREE_PATH>/.tachikoma/outcome` so a future `/tachikoma` invocation doesn't keep routing to Phase 6 for this finished run:
  ```bash
  rm -f <WORKTREE_PATH>/.tachikoma/outcome
  ```
  Leave the rest of `.tachikoma/` (prompt, run.log, progress.txt) and the worktree itself for the user.

**Step 9 — Work-queue cleanup.**

Only runs after a successful squash-merge (Step 4 user said yes).

Derive the work-request slug by stripping the `tachikoma/` prefix from `TACHIKOMA_BRANCH`:
```
SLUG = TACHIKOMA_BRANCH.removePrefix("tachikoma/")
```

Check if `~/projects/personal-nix/wiki/work-requests/<SLUG>.md` exists. If it does, invoke `/work-queue done <SLUG>` to delete it. If it doesn't, skip silently — not every tachikoma run originates from the work queue.

**If user bails mid-Phase-6** (says no at Step 4): exit cleanly. State is recoverable — `<WORKTREE_PATH>/.tachikoma/outcome=complete` stays, so `/tachikoma done` works again later. Phase 6 is idempotent; re-entering picks up where they left off. Steps that already happened (already-merged, already-pushed) are detected by re-running the same probe (e.g. `git log <BASE_BRANCH>..<TACHIKOMA_BRANCH>` empty → already merged → skip to Step 5).

## Phase R: recovery from interruption

Triggered when:
- Precondition 10 detects an interruptable worktree: `.tachikoma/outcome ∈ {cap, error, stopped}` OR a stale lockfile (PID dead).
- User runs `/tachikoma resume` explicitly (optionally `/tachikoma resume <slug>`).

**Step 0 — Pick the worktree.**

Enumerate via `git -C <cwd> worktree list --porcelain`. For each, read `<wt>/.tachikoma/outcome` and check `<wt>/.tachikoma/run.pid` liveness. Among recoverable ones:
- If exactly one: that's `WORKTREE_PATH`.
- If user passed `/tachikoma resume <slug>`: match by branch name; refuse on no match.
- Otherwise: present picker (showing slug, outcome, last progress line). User chooses one.

Capture: `WORKTREE_PATH`, `TACHIKOMA_BRANCH`, `BASE_BRANCH` (read `<WORKTREE_PATH>/.tachikoma/base_branch`).

**Step 1 — Show what happened** (for the chosen worktree):
- Last entry in `<WORKTREE_PATH>/.tachikoma/progress.txt` (most recent iteration's note).
- Last 30 lines of `<WORKTREE_PATH>/.tachikoma/run.log` if it exists.
- Completed-task count: local mode → count `passes: true` in `<WORKTREE_PATH>/plans/prd.json`; remote / `--issue` → `git -C <WORKTREE_PATH> log <TACHIKOMA_BRANCH> ^<BASE_BRANCH> --oneline`.
- Outcome value and the iter count from the loop's banner.

**Step 2 — Verify safe to resume.** `git -C <WORKTREE_PATH> status --porcelain`. If non-empty: surface and stop. The user must clean up that specific worktree (`cd <WORKTREE_PATH>; git status; git stash` etc.) before resuming.

**Step 3 — Offer three paths.** Ask:

| Path | What it does |
|---|---|
| **Resume** | Re-launch `<WORKTREE_PATH>/.tachikoma/tachikoma.sh` with chosen mode/cap. Agent reads progress.txt + PRD/issue, picks the next unfinished task, continues. |
| **Review** (Phase 6) | Treat what's committed as "done enough." Jump to Phase 6 with this worktree pre-selected. |
| **Restart** | Discard partial work in this worktree. Asks whether to also remove the worktree directory and the `tachikoma/<slug>` branch. |

For the **Resume** path:
- Default cap suggestion: `--afk 5` if previous mode was `--afk`; `--once` if previous was `--once`. Let user override.
- Before re-launching: `rm -f <WORKTREE_PATH>/.tachikoma/run.pid <WORKTREE_PATH>/.tachikoma/outcome` so the bash loop's startup checks pass.
- Re-launch via Phase 5 mechanism: `cd <WORKTREE_PATH> && nohup .tachikoma/tachikoma.sh --afk N > .tachikoma/run.log 2>&1 & disown` (or `--once` foreground).

For the **Review** path: jump to Phase 6 with `WORKTREE_PATH` already selected (skip Step 0).

For the **Restart** path:
- Confirm: "Delete worktree `<WORKTREE_PATH>` and branch `<TACHIKOMA_BRANCH>`? Their commits will be unrecoverable except via reflog. OK?"
- On yes:
  ```bash
  git -C <MAIN_REPO> worktree remove --force <WORKTREE_PATH>
  git -C <MAIN_REPO> branch -D <TACHIKOMA_BRANCH>
  ```
  Then fall through to a fresh planning grill (Phase 1).
- On no: exit cleanly. The user changed their mind about restarting; the worktree, branch, and `.tachikoma/` state are all left as-is so they can re-enter Phase R later.

## Subcommand: `/tachikoma status` (alias `/tachikoma t`)

Read-only telemetry. Never modifies state. Works whether loops are running, finished, or interrupted.

**Step 1 — Enumerate tachikomas in this repo.**

Run `git -C <cwd> worktree list --porcelain`. For each worktree (including the main repo), check:
- `<wt>/.tachikoma/run.pid` exists + PID alive → **RUNNING**
- `<wt>/.tachikoma/outcome=complete` → **COMPLETE**
- `<wt>/.tachikoma/outcome ∈ {cap, error, stopped}` → **CAP / ERROR / STOPPED**
- Otherwise (no `.tachikoma/`): not a tachikoma worktree, skip.

If zero tachikoma worktrees: tell user "No Tachikoma state in this repo." Exit.

**Step 2 — Format depends on count.**

### Single tachikoma (or `/tachikoma status <slug>` drilling in)

Today's full detail format. For the matched worktree, gather:
- PID + alive-status
- Branch and worktree path
- Cap and iter-progress: scan `<wt>/.tachikoma/run.log` for the most recent `==================== iter N / M ====================` line
- Last milestone banner: scan `<wt>/.tachikoma/run.log` for the most recent `✓ MILESTONE` block (5 lines), or `⚠ BLOCKER`, or the final `🏁 TACHIKOMA COMPLETE` / `⏱ CAP HIT` banner if present
- Last progress note: tail of `<wt>/.tachikoma/progress.txt` (most recent `## Iter N` block)
- Last 15 lines of `<wt>/.tachikoma/run.log` for raw context

Output:
```
Tachikoma telemetry — <tachikoma-branch>
─────────────────────────────────────────────────────
  Status:    <RUNNING / COMPLETE / CAP / ERROR / STOPPED>
  PID:       <pid> (alive | dead)
  Iter:      <N> / <M>
  Mode:      <--once | --afk M>
  Worktree:  <WORKTREE_PATH>

Last milestone:
  <copy the milestone banner block verbatim>

Last progress note:
  <copy the most recent ## Iter N block from progress.txt>

Recent log (last 15 lines):
  <tail of run.log>

────
Stop: /tachikoma stop  ·  Resume / review on next interaction: /tachikoma
```

Light suggestions based on state:
- **RUNNING**: "Loop is healthy. Check back when notification fires."
- **COMPLETE**: "Loop done. `/tachikoma done` to enter Phase 6."
- **CAP / ERROR / STOPPED**: "Loop ended in `<outcome>`. `/tachikoma resume` to see Phase R options."

Keep under ~40 lines.

### Multiple tachikomas (compact summary)

```
Tachikoma status — <repo-name> repo (<N> loops)
─────────────────────────────────────────────────────
  RUNNING   <tachikoma-branch-1>   iter <N>/<M>   pid <pid>
  RUNNING   <tachikoma-branch-2>   iter <N>/<M>   pid <pid>
  COMPLETE  <tachikoma-branch-3>   awaiting /tachikoma done
  CAP       <tachikoma-branch-4>   ended at iter <N>/<M>

Drill in: /tachikoma status <slug>
Stop:     /tachikoma stop  (picker)  ·  /tachikoma stop --all
Done:     /tachikoma done  (picker on completed)
```

Keep one row per loop, ≤80 chars wide. Don't print log tails or progress notes — that's drill-in territory.

## Subcommand: `/tachikoma stop`

**Step 1 — Enumerate running tachikomas** (worktrees with live `.tachikoma/run.pid`).

- Zero running: tell user "No tachikoma running in this repo." Exit.
- One running: stop it (Step 3).
- Multiple running:
  - If cwd is itself one of the running tachikoma worktrees: stop that one (cwd-implicit). Tell user explicitly which one you're stopping.
  - Else if user passed `--all`: stop every running loop (Step 3 for each).
  - Else if user passed `/tachikoma stop <slug>`: match by branch name and stop that one.
  - Else: present picker via AskUserQuestion.

**Step 2 — `/tachikoma stop <slug>`** matches by trailing branch slug or worktree slug. Refuse on no match with a list of running slugs.

**Step 3 — Stop a single loop:**
1. `kill -TERM <PID>`. The script's trap catches SIGTERM, finishes the current iteration cleanly, removes the lockfile, fires notification with `outcome=stopped`, exits.
2. Wait up to 60s for graceful exit; if still alive, `kill -KILL <PID>` and warn user about possibly-dirty worktree (which they'd see in Phase R).

For `--all`: send SIGTERM to all in parallel; wait up to 60s for all; SIGKILL stragglers.

## Subcommand: `/tachikoma queue` (queue-drain mode)

Sequentially drains the work-request queue, running a full tachikoma lifecycle (Phases 1–6) per item. Designed for long unattended sessions. Each item gets its own worktree, branch, and PR. Built to keep moving — failures are logged and skipped, never block the queue.

**`--caffeinated` flag (alias `-C`):** When passed, prevents macOS from sleeping during the drain by wrapping each item's `--once` launch with `caffeinate -d`. Recommended for AFK overnight runs. Can also be set interactively via the batch preferences question (see Step 1). Without this flag the system may sleep mid-drain and stall the loop.

**Work-request directory:** `~/projects/personal-nix/wiki/work-requests/*.md`

**Frontmatter fields used by queue drain:**

| Field | Purpose |
|---|---|
| `status` | `open` → `grabbed` → `done` → `needs-triage` |
| `target_repo` | Repo path, expanded `~` |
| `failure_count` | Integer. Bumped on each failure. Missing = 0. |
| `last_updated` | ISO date, bumped on every state change |

**Readiness check** (open+ready):
- `status: open`
- `target_repo` present and path exists on disk
- Body length > 50 chars
- `failure_count` < 2 (items with ≥ 2 failures are `needs-triage`, not grabbed)

### Step 0 — Session recovery (check first, before pre-flight)

Before anything else, scan for interrupted state from a prior session:

1. Glob all work-requests for `status: grabbed`.
2. For each grabbed item, check for a matching tachikoma worktree via `git worktree list --porcelain` (branch matching `tachikoma/*<slug>*`).
3. If any grabbed items exist, print a compact interrupted-state summary:
   ```
   ⚠  Interrupted session detected — 1 item was in progress:
        fix-vital-age  (grabbed, worktree exists, outcome=unknown)

   Resume interrupted items first, then continue queue? [Y/n]
   ```
4. On yes (default): handle each interrupted item first using the failure-handling rules in Step 1f before starting any new items. On no: skip interrupted items and start fresh (they remain grabbed — user owns cleanup).
5. If a grabbed item has no matching worktree (crash before scaffold): reset `status: open` automatically and include it in the normal pre-flight queue.

### Step 1 — Pre-flight

1. Glob and parse all work-requests. Distinguish two empty states:
   - **Truly empty** — no `.md` files (excluding `.gitkeep`): `"No work requests found. Create one with /work-queue add."`
   - **Items exist but none ready** — show each blocking reason inline: `"2 items exist but none are ready:"`
     ```
       fix-vital-age           — target_repo ~/projects/platform not found on disk
       refactor-auth-middleware — body too short (< 50 chars)
     ```
   - Exit in both cases.

2. Show all candidates with indices. Include `needs-triage` items visibly but mark them excluded:
   ```
   Queue drain — 3 items to run  (1 excluded)

     [1] fix-vital-age            → ~/projects/platform
     [2] refactor-auth-middleware  → ~/projects/platform
     [3] add-sleep-chart           → ~/projects/healthbite
     [–] wire-up-feature-flags     → ~/projects/platform    ⚠ needs-triage (2 failures)
   ```
   With `/tachikoma queue <slug>`: filter to that one item. Refuse on no match, ambiguity, or `needs-triage` status (tell user to reset it manually first).

3. Ask batch preferences **once**, showing defaults inline so enter accepts:
   ```
   Quality bar [production]:
   Iteration cap [10]:
   Auto-open PRs? [yes]:
   Auto-clean worktrees? [yes]:
   Keep system awake (caffeinate -d)? [yes]:
   ```
   The caffeinate preference is pre-answered `yes` if `--caffeinated` / `-C` was passed on the command line; otherwise the user chooses interactively. Record the answer as `caffeinated: true|false` for use in Step 2f.

4. Confirm before entering the loop. Accept a plain enter/yes, or a space-separated list of indices/slugs to exclude:
   ```
   Proceed with 3 items? (enter to confirm, or type indices/slugs to exclude, e.g. "2 auth-middleware"):
   ```
   Strip excluded items from the run list before continuing.

### Step 2 — Item loop (sequential, foreground)

For each item in queue order:

**a. Print item header:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[1/3] fix-vital-age → ~/projects/platform
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**b. Extract grill fields from the work-request body.** Look for these sections in order of precedence (explicit header > first paragraph):

| Field | Look for |
|---|---|
| Goal | `## Goal`, `## Objective`, or first non-heading paragraph |
| Files in scope | `## Files in Scope`, `files_in_scope:` in frontmatter |
| Files out of scope | `## Files out of Scope`, `files_out_of_scope:` in frontmatter |
| Stop condition | `## Stop Condition`, `## Acceptance Criteria`, `## Done When` |
| Feedback loops | `## Feedback Loops`, `## Tests`, `## Verification` |

**If the body is freeform prose with no recognizable headers:** show the raw body and ask the user to identify each field interactively before proceeding (abbreviated grill — only missing fields). At minimum, goal + stop condition must be resolved before launch.

For well-structured bodies, show the extracted fields and confirm in one pass.

**c. Ask "Launch this item?"** User can type "skip" to move to the next item. Do NOT update the queue file until the user confirms launch — if the user aborts or skips at this point, `status` stays `open`.

**d. Update the queue file:** `status: open` → `status: grabbed`, bump `last_updated` to today. This is the commit point — anything after this that exits unexpectedly leaves the item grabbed and triggers Step 0 recovery on the next run.

**e. `cd` to `target_repo`.** Run Phase 3 (worktree creation + scaffolding) using the extracted fields. The target_repo's current HEAD is the base branch. Queue mode's per-item "Launch this item?" at step (c) is the single approval gate — Phase 4 was merged into Phase 1 for the bare `/tachikoma` flow, and queue mode's step (c) plays the same role here, so there's no second prompt-review step before launch.

**f. Phase 5 — launch `--once` (foreground).** Stream the iteration output directly. Queue drain is the session driver; `--once` keeps items sequential and output readable.

If `caffeinated=true`, wrap the launch to prevent macOS sleep:
```bash
caffeinate -d bash -c "cd <WORKTREE_PATH> && .tachikoma/tachikoma.sh --once"
```
Otherwise launch normally:
```bash
cd <WORKTREE_PATH> && .tachikoma/tachikoma.sh --once
```

**g. Transition banner after tachikoma output ends:**
```
━━━ Queue Drain — Phase 6: fix-vital-age ━━━━━━━━━━━━━━
```
This separates tachikoma's raw output from queue drain's Phase 6 actions in the scrollback.

**h. Phase 6 (abbreviated, uses batch preferences):**
- Show diff stat verbatim.
- Squash-merge: auto-approve unless conflicts arise (see failure handling below for conflict path).
- Worktree + branch cleanup: if `auto-clean=yes`, skip the interactive prompt and clean up automatically.
- PR: if `auto-open=yes`, derive title/body from goal + slug and open without review (user can edit on GitHub). Print the PR URL.
- Issue close: skip for local-mode items. For `--issue`-sourced items, apply Phase 6 Step 7 smart default.

**i. Mark item `status: done`**, bump `last_updated`, bump nothing on `failure_count` (success resets nothing — count is cumulative across all time).

**j. Print completion line:**
```
✓ [1/3] fix-vital-age — DONE  (PR #142 opened, worktree cleaned)
```

### Failure handling (keep the queue moving)

The goal is to skip and continue — never block the queue waiting for human input unless human input is genuinely required (e.g. merge conflicts that can't be resolved automatically).

#### Outcome: `cap` (hit iteration limit)

```
⏱ [1/3] fix-vital-age — CAP HIT (10/10 iterations)
         Auto-resuming once at reduced cap (5 iterations)...
```

Re-launch `--once` with `floor(original_cap / 2)`. If it caps again:
- Treat as a failure (same path as `error` below).
- Do NOT auto-resume a third time.

#### Outcome: `error`, `stopped`, or `blocker-exit`

Skip immediately. No retry. Proceed to the failure-log path below, then move to the next item.

`stopped` = deliberate kill, don't retry. `blocker-exit` = tachikoma self-assessed as stuck, human input needed.

#### On any failure (after exhausting retries):

1. **Partial commits check:** run `git -C <WORKTREE_PATH> log <TACHIKOMA_BRANCH> ^<BASE_BRANCH> --oneline`. If commits exist beyond the scaffold commit:
   - Push the branch: `git -C <WORKTREE_PATH> push -u origin <TACHIKOMA_BRANCH>`
   - Open a draft PR: `gh pr create --draft --title "[partial] <goal-slug>" --body "Partial work from queue drain. See work-request failure log for context."`
   - Record the draft PR URL for the failure log.
   - Clean up the worktree: `git -C <MAIN_REPO> worktree remove --force <WORKTREE_PATH>` (branch stays — it's the draft PR's head).
   - If no commits beyond scaffold: clean up worktree + branch entirely.

2. **Write failure log entry** to the work-request file. Append a `## Queue Failures` section (or add an entry to an existing one):
   ```markdown
   ## Queue Failures

   ### 2026-05-10 — outcome: error

   **Last progress note:**
   <last entry from .tachikoma/progress.txt>

   **Log tail:**
   <last 15 lines of .tachikoma/run.log>

   **Draft PR:** https://github.com/... (if partial commits exist)

   **What to try next:**
   <synthesized suggestion — read the progress note + log tail and derive a concrete,
   actionable recommendation. E.g. "tsc failed on src/utils/sleepNormalizer.ts at line 42:
   cannot find name 'mergeSleepIntervals'. Check the import path — the function was moved
   to sleepNormalizer/merge.ts in the last refactor.">
   ```

3. **Bump `failure_count`** in frontmatter (missing = 0, treat as 0 before bumping).

4. **Status transition:**
   - `failure_count` after bump < 2: reset `status: grabbed` → `status: open`
   - `failure_count` after bump ≥ 2: set `status: needs-triage` (excluded from all future queue drains until manually reset)

5. **Label reversion** (for issue-linked work_requests — those with a non-empty `github_issue` field):
   - `failure_count` after bump < 2: `gh issue edit <N> --repo <org/repo> --remove-label "agent-running" --add-label "ready-for-agent"` (issue back in the pool)
   - `failure_count` after bump ≥ 2: `gh issue edit <N> --repo <org/repo> --remove-label "agent-running" --add-label "needs-triage"` (quarantined — human must reset)
   - During in-session cap retry (before final failure decision): keep `agent-running` — no label change while actively retrying.
   - On `stopped` outcome (deliberate kill): `gh issue edit <N> --repo <org/repo> --remove-label "agent-running" --add-label "ready-for-agent"` (no `failure_count` bump — deliberate stop isn't a failure).

6. **Print failure line:**
   ```
   ✗ [1/3] fix-vital-age — FAILED (error · draft PR opened · needs-triage after 2 failures)
   ```

#### Phase 6 merge conflict

If squash-merge exits with a conflict:
- Abort the merge: `git -C <BASE_WT> merge --abort`
- Push the tachikoma branch as-is: `git -C <WORKTREE_PATH> push -u origin <TACHIKOMA_BRANCH>`
- Open a draft PR with the conflict noted in the body.
- Write a failure log entry (outcome: `phase6-conflict`) with the conflicting files listed.
- Bump `failure_count`, apply the same status transition as above.
- Clean up the worktree.
- Continue to the next item.

#### User aborts before tachikoma launches

If the user sends Ctrl-C or types "abort" **after** `status: grabbed` was written but **before** the worktree is created:
- Reset `status: grabbed` → `status: open` immediately.
- Do not bump `failure_count` (no attempt was made).
- Exit queue drain cleanly.

If the abort happens **after** the worktree is created but before tachikoma launches:
- Clean up the worktree + branch.
- Reset `status: grabbed` → `status: open`.
- Do not bump `failure_count`.
- Exit queue drain cleanly.

### Step 3 — Session summary

After all items are processed, print the summary and write it to `~/projects/personal-nix/wiki/work-requests/.last-queue-run.md` (same content, for morning review if the terminal is gone).

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Queue drain complete — 2026-05-10
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓  fix-vital-age            PR #142  ~/projects/platform
✓  add-sleep-chart           PR #143  ~/projects/healthbite
✗  refactor-auth-middleware  FAILED (error · draft PR #144 · 1/2 failures)
⚠  wire-up-feature-flags     NEEDS TRIAGE (2/2 failures — excluded from future runs)

PRs opened:  #142, #143, #144 (draft)
Needs attention: 1 failed item · 1 needs-triage item
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Write `.last-queue-run.md` using the identical content so it's readable both in terminal and in a text editor.

### When `<repo>` arg is provided: GitHub-sourced queue drain

When `/tachikoma queue <repo>` is invoked (e.g. `/tachikoma queue MioMarker/healthbite`):

**Step 0 — Fetch GitHub queue:**
1. `gh issue list --repo <repo> --label "ready-for-agent" --state open --json number,title,body,labels,comments --limit 100`
2. Filter out any issues that also have `agent-running` label (already claimed).
3. For each remaining issue, check `~/projects/personal-nix/wiki/work-requests/` for an existing work_request with `github_issue: <repo>#<N>`. If none exists, auto-create one (see Phase 2 work_request auto-creation rules above).
4. Build the run list from these work_requests. Proceed into the normal queue-drain Step 1 (pre-flight) with this list.

**HITL notification** (after Step 3 session summary):

After the drain completes, fetch current issue state:
```bash
gh issue list --repo <repo> --state open --json number,title,labels --limit 100
```

Classify remaining open issues:
- `needs-triage` → *"triage and label"*
- `needs-info` → *"respond to reporter"*
- `ready-for-human` → *"implement manually"*
- `ready-for-review` → *"review open PR"* (already handled but not yet closed)

If any remain, fire a macOS notification:
```bash
osascript -e 'display notification "N issues need human attention in <repo>" with title "Tachikoma — HITL required"'
```

And print a terminal summary:
```
⏸ Queue drained — N issues need human attention (<repo>)

  #14  Add onboarding screen        needs-triage    → triage and label
  #19  Redesign settings UI         ready-for-human → implement manually
  #23  Clarify acceptance criteria  needs-info      → respond to reporter
```

If zero issues remain (everything closed or resolved): print `✓ Queue clear — no open issues in <repo>.`

### Constraints

- **Strictly sequential** — one tachikoma at a time, no concurrent launches. Prevents branch conflicts when multiple items target the same repo.
- **`--once` mode only** — not `--afk`. Queue drain is the session driver. If an item is too large for one `--once` iteration, tachikoma blocker-exits and failure handling takes over.
- **`--caffeinated` / `-C`** — pass this flag (or answer yes to the batch preference) for long overnight runs. Each item's launch is wrapped with `caffeinate -d` to prevent macOS from sleeping between iterations.
- Items targeting different repos could theoretically run in parallel but queue drain doesn't — too much session-state complexity for v1.
- The queue file is the durable state. `grabbed` = in-progress; Step 0 recovery handles crashes.

## Templates in this skill

- [tachikoma.sh.tmpl](tachikoma.sh.tmpl) — the bash loop. Placeholders: `{{ALLOWED_TOOLS}}`, `{{SENTINEL}}`, `{{REPO_PATH}}`.
- [prompt.md.tmpl](prompt.md.tmpl) — the per-iteration prompt. Placeholders: `{{GOAL}}`, `{{QUALITY_BAR_PARAGRAPH}}`, `{{FILES_IN_SCOPE}}`, `{{FILES_OUT_OF_SCOPE}}`, `{{STOP_CONDITION}}`, `{{TASK_SOURCE_BLOCK}}`, `{{TYPECHECK_CMD}}`, `{{TEST_CMD}}`, `{{LINT_CMD}}`, `{{COMMIT_INSTRUCTIONS}}`, `{{COMPLETION_INSTRUCTIONS}}`.
- [AGENT-BRIEF.tmpl](AGENT-BRIEF.tmpl) — remote-mode agent brief comment, posted as a GitHub issue comment after `to-issues` promotes child issues. Placeholders: `{{CATEGORY}}`, `{{SUMMARY}}`, `{{CURRENT_BEHAVIOR}}`, `{{DESIRED_BEHAVIOR}}`, `{{KEY_INTERFACES}}`, `{{ACCEPTANCE_CRITERIA}}`, `{{OUT_OF_SCOPE}}`, `{{QUALITY_BAR}}`. Fill from grill answers + issue body content. Used in both `--remote` and `--issue` modes.

## Rendering `{{ALLOWED_TOOLS}}` (required, exact format)

This is the string Bash passes to `claude -p --allowed-tools`. Render it as **space-separated** tokens, **constrained per `Bash(...)` glob**. Do NOT pass an unqualified `Bash` — that grants the loop iteration carte blanche to run anything (including `rm -rf`), which defeats the v1 sandboxing decision.

### Always-included tokens
```
Edit Write Read Glob Grep
```

### Bash glob tokens (compose from the grill answers)
- Always: `Bash(git *)`
- For each non-empty feedback-loop command, take the **first word** and add a glob. Examples:
  - typecheck `pnpm type-check` → `Bash(pnpm *)`
  - tests `npm test` → `Bash(npm *)`
  - lint `cargo clippy` → `Bash(cargo *)`
  - inline shell like `echo 'no typecheck'` or `grep -q hello hello.txt` → `Bash(echo *)` and `Bash(grep *)`
  - the typecheck/test/lint commands collapse — dedupe so the same first-word glob isn't repeated.
- For `--remote` mode only: also `Bash(gh *)`

### Worked example

Grill produced:
- typecheck: `pnpm type-check`
- tests: `pnpm test`
- lint: `pnpm lint`
- mode: local

Render:
```
Edit Write Read Glob Grep Bash(git *) Bash(pnpm *)
```

### Worked example (smoke test)

Grill produced:
- typecheck: `echo "no typecheck — skipped"`
- tests: `grep -q hello hello.txt && echo "PASS"`
- lint: `echo "no lint — skipped"`

Render:
```
Edit Write Read Glob Grep Bash(git *) Bash(echo *) Bash(grep *)
```

### Anti-pattern (never render)
```
Bash,Read,Edit,Write     # commas not spaces; unqualified Bash
Bash                     # unqualified — grants everything
```

If the grill's feedback-loop commands include shell pipelines or operators (`&&`, `|`, `;`), the **first word still applies** — `claude -p` evaluates the whole command string against the allowlist via the leading binary.

## Quality bar paragraphs (drop into `{{QUALITY_BAR_PARAGRAPH}}`)

- **prototype**: "This is prototype code. Speed over perfection. Shortcuts and skipped edge cases are acceptable. Do NOT over-engineer."
- **production**: "This codebase will outlive you. Every shortcut becomes someone else's burden. Every hack compounds into technical debt. Fight entropy. Production code requires tests, type safety, and explicit error handling."
- **library**: "This is a public library API. Backward compatibility matters. Be careful with breaking changes — flag them explicitly in commit messages. Public-facing types and exports require deliberate design."

## Task-source block (drop into `{{TASK_SOURCE_BLOCK}}`)

### Local mode
```
Read `plans/prd.json` for the backlog. Pick the highest-priority item where `passes` is `false` and all `blocked_by` items have `passes: true`. After implementing, set that item's `passes` to `true` in the same commit.
```

### Remote-greenfield mode (`--remote`)
```
Run `gh issue list --label ready-for-agent --state open --json number,title,body,labels` to fetch the backlog. Pick the highest-priority issue with no open `Blocked by` dependencies. Read its full body and the agent-brief comment. After implementing, the closing reference goes in your commit message — do NOT close the issue via gh CLI.
```

### Existing-issue mode (`--issue <N>`)
```
Your task is issue #<N>. Run `gh issue view <N> --json title,body,comments,labels,state` to read the full spec. The issue body and the most recent agent-brief comment are your specification — there is no PRD JSON, no other backlog. Do NOT pick up other issues even if they're labeled `ready-for-agent`; you are scoped to #<N> only. After implementing, include `Closes #<N>` in your commit message — do NOT close the issue via gh CLI.
```

## Commit instructions block (`{{COMMIT_INSTRUCTIONS}}`)

### Local
```
Commit message format:
  <type>: <description> [T-NNN]

  <body if needed>

Where <type> is feat|fix|refactor|test|docs|chore. Include the PRD item id in brackets.
```

### Remote
```
Commit message format:
  <type>: <description>

  Closes #<issue-number>

The "Closes #N" line is mandatory — it's how the loop knows the issue is done.
```

## Completion instructions (`{{COMPLETION_INSTRUCTIONS}}`)

### Local
```
If, after marking your item `passes: true`, every item in `plans/prd.json` has `passes: true`:
  1. `rm plans/prd.json`
  2. `git add -A && git commit -m "chore: tachikoma complete, remove plans/prd.json"`
  3. Output exactly: <promise>COMPLETE</promise>
```

### Remote-greenfield
```
If, after your commit, `gh issue list --label ready-for-agent --state open` returns zero issues, output exactly: <promise>COMPLETE</promise>
```

### Existing-issue (`--issue <N>`)
```
After your commit lands AND verification passed (typecheck, tests, lint), the work for issue #<N> is complete. The "Closes #<N>" line in your commit message will close the issue when this branch is merged into the default branch — but the loop does not push or merge.

Output exactly: <promise>COMPLETE</promise>

Exception: if you decomposed the issue into subtasks because it was too large for one iteration, do NOT emit the sentinel. Append a blocker note to `.tachikoma/progress.txt` with the proposed decomposition, optionally post a comment on issue #<N> outlining the split, and exit. The human will triage.
```

## Anti-shortcut framing (always include in prompt)

```
You will be tempted to declare victory early by redefining what "done" means.
You will be tempted to skip writing tests because the code "obviously works".
You will be tempted to mark items complete that you only partially addressed.
DO NOT.

The stop condition above is the only definition of done. Files in scope means
those exact files — not a subset you decide are user-facing. Feedback loops
must pass with zero errors before commit, no exceptions.

If you genuinely cannot complete an item, do NOT mark it `passes: true`.
Instead, append a blocker note to `.tachikoma/progress.txt` describing what you
tried and why it failed, then exit without emitting the sentinel.
```

## Step-size and prioritization (always include)

```
Iteration discipline:
- ONE feature per iteration. If a task feels too large, decompose it into
  subtasks in the PRD before working on it.
- Small steps. Quality over speed.
- Prioritize spikes, integrations, and architectural decisions FIRST. Save
  polish, cleanup, and quick wins for last.
- If you discover a blocker, integration issue, or architectural problem
  mid-iteration, stop, document it in progress.txt, and exit. Do not paper
  over it.
```

## Notification on AFK exit

The bash script handles this — calls `osascript -e 'display notification ...'` and prints `\a` on exit. Skill does not need to do anything here.

## Cleanup philosophy

The **worktree** is the per-run sandbox. `.tachikoma/` lives inside it (gitignored). The `tachikoma/<slug>` branch is the durable record. Phase 6 squash-merges into base and (with user approval) removes the worktree + branch atomically.

After a successful run, **enter Phase 6** — do NOT print manual git instructions to the user. Phase 6 walks them through the squash-merge, combined worktree+branch cleanup, and PR flow interactively.

`.tachikoma/base_branch` (single line, written at scaffold time) is the only piece of cross-session metadata Phase 6 needs that isn't recoverable from git itself.

## Failure modes to watch for

- Loop crashes mid-iteration with dirty working tree (in the worktree) → next iteration must refuse cleanly. The bash template handles this.
- Issue tracker auth expires mid-AFK run (remote mode) → loop logs error, exits, notification fires with `outcome=error`.
- Feedback loop times out or never finishes → not handled by v1; user kills the loop manually.
- User opens the worktree in another Claude Code session and starts editing → not handled; the per-worktree lockfile only prevents concurrent tachikoma loops in the *same* worktree, not concurrent humans there.
- `git worktree add` fails because path exists or branch exists → handled by precondition 9 + Phase 3 step 3 collision check; refuse with the exact path/branch.
- `git worktree remove` fails because of untracked files (e.g. `.tachikoma/run.log`) → Phase 6 retries with `--force`. Restart path in Phase R also uses `--force`.
- Base branch isn't checked out anywhere when Phase 6 runs → `BASE_WT = MAIN_REPO`; Phase 6 checks out `<BASE_BRANCH>` there before merging, but only if main repo's working tree is clean. Otherwise refuses.
- User runs `/tachikoma` from inside an active tachikoma worktree → precondition 4 refuses; tell them to `cd` to main repo or a non-tachikoma worktree.
- `.tachikoma/base_branch` missing (e.g. user manually deleted it, or worktree was scaffolded by an old version of this skill) → Phase 6 falls back to asking the user which branch to merge into.
