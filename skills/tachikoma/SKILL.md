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
| `/tachikoma` | Plan + run. Mode (existing-issue / local / remote-greenfield) is chosen via two grill questions in preflight. Creates a new sibling worktree, scaffolds in it, launches loop. |
| `/tachikoma --remote` | **Fast-path** for remote-greenfield mode — skips the mode-selection grill questions. PRD → `to-prd` → `to-issues` → auto-promoted to `ready-for-agent`. New worktree per run. |
| `/tachikoma --issue <ref>` | **Fast-path** for existing-issue mode — skips the mode-selection grill questions. Uses a GitHub issue body as the PRD; loop scoped to that single issue. New worktree per run. |
| `/tachikoma 138` or `/tachikoma #138` | **Shorthand** — a bare integer or `#N` as the first positional arg is normalized to `/tachikoma --issue <N>`. Same fast-path behavior, same preconditions (7, 8). |
| `/tachikoma done` (optionally `<slug>`) | Manually trigger ship phase. With `<slug>`, picks that specific completed worktree; otherwise picker if multiple complete, auto-pick if one. Auto-triggered when `/tachikoma` (no args) is run with a single completed worktree in the repo. |
| `/tachikoma resume` (optionally `<slug>`) | Re-launch a previously interrupted loop. With `<slug>`, picks that specific worktree; otherwise picker if multiple recoverable. Auto-offered when `/tachikoma` (no args) is run with recoverable state. |
| `/tachikoma status` (alias `/tachikoma t`, optionally `<slug>`) | Telemetry. With no args: compact summary table across all tachikoma worktrees in this repo. With `<slug>`: drill into that specific loop (PID liveness, iter, last milestone, log tail). Read-only. |
| `/tachikoma stop` (optionally `<slug>` or `--all`) | SIGTERM. Cwd-implicit if cwd is itself a tachikoma worktree. Picker if >1 running. `--all` halts every running tachikoma in the repo. |
| `/tachikoma queue` (optionally `<slug>`) | Drain the work-request queue sequentially — full Phases 1–6 per item, batch preferences set once up front. With `<slug>`: run a single specific queue item. With `--caffeinated` (alias `-C`): prevent macOS sleep for the entire session by wrapping each item's launch with `caffeinate -d`. |
| `/tachikoma queue <repo>` | Queue-drain mode sourced from GitHub. Fetches all `ready-for-agent AND NOT agent-running` issues from `<repo>` (format: `org/repo`), auto-creates linked work_requests for any without one, then runs the normal queue drain (Phases 1–6 per item). Ends with a HITL notification when no `ready-for-agent` issues remain. |

`--remote` and `--issue <ref>` are **fast-paths**, not requirements — bare `/tachikoma` collects the same answers via two grill questions in preflight (existing issue? then, if not, local-or-remote?). Use the flags when you already know the mode and want to skip those questions; either flow lands in the same plan phase/3 logic.

`<ref>` accepts: `#138`, `138`, or `org/repo#138`. The `org/repo` form must match the cwd repo's `nameWithOwner`; if not, refuse and tell the user to `cd` first.

**Argument normalization (runs before preconditions):** if the first positional argument matches a bare integer (`/tachikoma 138`) or a `#N` pattern (`/tachikoma #138`), rewrite the invocation to `/tachikoma --issue <N>` before any further processing. This means precondition 7 (`gh` auth) and precondition 8 (issue exists, repo matches) apply just as they would for an explicit `--issue` invocation. The shorthand is purely a parsing convenience — it has no effect once normalized.

`<slug>` matches against the trailing slug of the worktree's branch name (e.g. `issue-138-fix-vital-age` matches `tachikoma/issue-138-fix-vital-age`). Substring match is OK if unambiguous; otherwise refuse and list candidates.

Multiple tachikomas can run concurrently in the same repo (in separate worktrees). The per-worktree lockfile (`<wt>/.tachikoma/run.pid`) prevents two loops in the same worktree, but loops in *different* worktrees of the same repo are fine and expected.

## Preconditions (refuse with explanation if violated)

All refusal messages use this format:
```
✗ <what went wrong>
  → <exact next step>
```

1. cwd must be inside a git repo (`git rev-parse --git-dir`). On failure:
   ```
   ✗ Not inside a git repository.
     → cd into your project and try again, or run: git init && git commit --allow-empty -m init
   ```

2. Repo must have at least one commit (`git rev-parse HEAD` succeeds). On failure:
   ```
   ✗ Repo has no commits — Tachikoma needs a HEAD to branch from.
     → git commit --allow-empty -m init
   ```

3. ~~Working tree must be clean.~~ **Relaxed.** With worktree mode, the tachikoma branch is created off cwd's HEAD via `git worktree add`, which only needs HEAD — the cwd's working tree may be dirty. (The new worktree's working tree is clean by construction.)

4. **cwd must NOT be an active tachikoma worktree** — *new-run invocations only* (`/tachikoma`, `/tachikoma --issue`, `/tachikoma --remote`, `/tachikoma queue`). Refuse if either is true: (a) `<cwd>/.tachikoma/run.pid` exists and the PID is alive, (b) `git -C <cwd> rev-parse --abbrev-ref HEAD` matches `tachikoma/*`. Reason: branching off a mid-tachikoma state would inherit half-finished commits. **`status`, `stop`, `done`, and `resume` are exempt.** On failure:
   ```
   ✗ You're inside an active Tachikoma worktree — can't start a new run from here.
     → cd <MAIN_REPO>
   ```

5. `claude` CLI on PATH (`command -v claude`). On failure:
   ```
   ✗ `claude` CLI not found on PATH.
     → Install it: https://claude.ai/code, then re-run.
   ```

6. `git worktree` available (Git ≥ 2.5). On failure:
   ```
   ✗ `git worktree` is not available — Git ≥ 2.5 required.
     → brew upgrade git
   ```

7. For `--remote`, `--issue`, and `queue <repo>`: `gh` CLI on PATH and authenticated. On `gh` missing:
   ```
   ✗ `gh` CLI not found on PATH — required for GitHub mode.
     → brew install gh && gh auth login
   ```
   On auth failure:
   ```
   ✗ `gh` is not authenticated.
     → gh auth login
   ```
   For `queue <repo>`: repo must also be accessible via `gh repo view <repo>`. On failure:
   ```
   ✗ Cannot access repo <repo> — check the org/repo format and your GitHub permissions.
     → gh repo view <repo>
   ```

8. For `--issue <ref>`:
   - The issue must exist and be open. This check applies at **every** invocation — a prior ship phase squash-merge can auto-close via `Closes #N`. On closed issue:
     ```
     ✗ Issue #<N> is already closed.
       → Reopen it on GitHub if you want to Tachikoma it again.
     ```
     On issue not found:
     ```
     ✗ Issue #<N> not found in <org/repo>.
       → Check the number and repo, or run: gh issue view <N>
     ```
   - The cwd repo's `nameWithOwner` must match the ref's repo (if user passed `org/repo#N`). On mismatch:
     ```
     ✗ Issue ref <org/repo#N> doesn't match this repo (<cwd-repo>).
       → cd into <org/repo>'s local path and try again.
     ```
   - Label vocabulary is **not** a precondition; it is auto-created by setup phase (see below).

9. **No worktree-path or branch collision.** Compute `WORKTREE_PATH` and `TACHIKOMA_BRANCH` (scaffold phase) and check up front:
   - If `<WORKTREE_PATH>` already exists:
     ```
     ✗ Worktree path already exists: <WORKTREE_PATH>
       → git worktree remove <WORKTREE_PATH>  (or --force if files linger)
     ```
   - If `<TACHIKOMA_BRANCH>` already exists:
     ```
     ✗ Branch already exists: <TACHIKOMA_BRANCH>
       → Finish or abandon the existing run, or: git branch -D <TACHIKOMA_BRANCH>
     ```
   - For `--issue <N>` re-runs (both path and branch collide — expected guard):
     ```
     ✗ A Tachikoma run for issue #<N> already exists.
       → /tachikoma resume  to continue it, or clean up first:
         git worktree remove <WORKTREE_PATH> && git branch -D <TACHIKOMA_BRANCH>
     ```

10. **State detection across worktrees.** Enumerate via `git worktree list --porcelain`, then for each worktree check:

   **a. Loop still alive?** `<wt>/.tachikoma/run.pid` exists and `kill -0 <pid>` succeeds. Note the worktree as RUNNING.

   **b. Outcome on disk?** Read `<wt>/.tachikoma/outcome` if present. Values: `complete`, `cap`, `error`, `stopped`.

   **c. Stale lockfile?** `<wt>/.tachikoma/run.pid` exists with a dead PID — treat as crash, recoverable.

   **d. Working tree dirty inside a worktree with state?** `git -C <wt> status --porcelain` non-empty + `.tachikoma/` present — loop crashed mid-commit. Print:
   ```
   ✗ Worktree <wt> has uncommitted changes from a crashed loop — cannot resume safely.
     → cd <wt> && git status  (then stash or commit, and retry /tachikoma resume)
   ```

   Routing depends on what the user just typed:
   - `/tachikoma` (no args) with **one** completed worktree → ship phase on it.
   - `/tachikoma` (no args) with **one** interrupted/recoverable worktree → recover phase on it.
   - `/tachikoma` (no args) with **multiple** terminal worktrees → present picker; let user choose which to act on.
   - `/tachikoma` (no args) with only RUNNING worktrees → print:
     ```
     ✗ <N> Tachikoma(s) already running — no completed runs to act on.
       → /tachikoma status   to see them
       → /tachikoma stop     to halt one
     ```
   - `/tachikoma <new-args>` (start a new run) — terminal worktrees are NOT a blocker. Proceed to preflight.
   - Pure stale clutter (`.tachikoma/` with nothing meaningful) — ignore unless user is explicitly acting on that worktree.

## Setup: label vocabulary

Tachikoma uses four GitHub labels for its issue lifecycle: `ready-for-agent`, `agent-running`, `ready-for-review`, `needs-triage`. Before preflight begins — for any invocation that will touch GitHub issues (`--remote`, `--issue <ref>`, `/tachikoma queue <repo>`) — verify the labels exist in the target repo and silently create any that are missing.

Target repo derivation:
- `--issue <ref>`: from the ref (or cwd's `nameWithOwner` if no `org/repo` prefix).
- `--remote`: cwd's `nameWithOwner` (`gh repo view --json nameWithOwner --jq .nameWithOwner`).
- `/tachikoma queue <repo>`: the explicit `<repo>` argument.

1. Print: `Checking labels in <org/repo>…`
2. List existing labels in one call:
   ```bash
   gh label list --repo <org/repo> --limit 100 --json name --jq '.[].name'
   ```
3. Compute the missing set against the four required names.
4. **If all four exist:** print nothing and continue to preflight.
5. **If any are missing:** create each missing label silently with `gh label create <name> --repo <org/repo>` (default color/description are fine — these are internal lifecycle labels). Then emit exactly one log line, comma-separated in the order created, and continue to preflight:
   ```
   Created missing labels: <name1>, <name2>, ...
   ```

No confirmation prompt — this is infrastructure, not a decision the user needs to weigh in on. If a `gh label create` call fails (auth dropped, rate limit, etc.), surface the raw error and refuse — but never interrupt to ask the user about labels they didn't ask to be asked about.

For bare `/tachikoma` (mode chosen via preflight grill), the mode isn't known at preconditions time. If the user's grill answers route the run into existing-issue or remote-greenfield mode, run setup phase the moment that mode is selected — still before any GitHub-mutating step in plan phase. For local mode, setup phase is a no-op; no labels are touched.

## Configuration (`~/.claude/tachikoma.conf`)

Tachikoma reads its defaults from `~/.claude/tachikoma.conf` before every run. Create this file once; all runs inherit from it silently. Keys are `key = value` pairs, one per line; `#` for comments. Missing file or missing key → built-in default applies.

| Key | Default | Values |
|---|---|---|
| `quality_bar` | `production` | `prototype`, `production`, `library` |
| `iteration_cap` | `15` | Integer, max 50 |
| `iteration_mode` | `afk` | `afk` or `once` |
| `allowed_tools` | see below | Space-separated tokens for `claude -p --allowed-tools` |

Default `allowed_tools` if the key is absent:
```
Edit Write Read Glob Grep Bash(git *) Bash(gh *) Bash(pnpm *) Bash(npm *) Bash(npx *) Bash(node *) Bash(make *) Bash(cargo *) Bash(go *) Bash(python *) Bash(python3 *) Bash(rg *) Bash(find *) Bash(cat *) Bash(echo *) Bash(ls *) Bash(mkdir *) Bash(cp *) Bash(mv *) Bash(rm *) Bash(touch *)
```

Example `~/.claude/tachikoma.conf`:
```
quality_bar = production
iteration_cap = 15
iteration_mode = afk
# allowed_tools = Edit Write Read Glob Grep Bash(git *) Bash(gh *) Bash(pnpm *)
```

## Preflight

All run parameters are resolved from three sources in priority order:
1. The GitHub issue body (in `--issue` mode)
2. `~/.claude/tachikoma.conf`
3. Built-in defaults

**Cancel path.** Only honored if the user types `cancel`/`stop`/`exit`/`nevermind` before scaffold phase begins. Once the worktree exists, use `/tachikoma stop` instead.

**Step 1 — First-run onboarding.** Check whether `~/.claude/tachikoma.conf` exists.

- **If it exists:** read it, parse `key = value` pairs, apply built-in defaults for any missing keys. Continue to Step 2 — no questions asked.

- **If it does not exist:** this is the user's first run. Run the onboarding flow before doing anything else:

  Print:
  ```
  Welcome to Tachikoma — autonomous AI coding loop.
  ────────────────────────────────────────────────────
  Let's set your defaults (takes ~1 minute). These are saved to
  ~/.claude/tachikoma.conf and used silently on every future run.
  You can edit the file any time to change them.
  ```

  Ask three questions (one at a time, each with a recommended default shown inline):

  **Q1 — Quality bar** (what standard should generated code meet by default?)
  ```
  Quality bar [production]:
    prototype  — speed over correctness, shortcuts OK
    production — tests required, no hacks, maintainable  (recommended)
    library    — public API, backward-compat matters
  ```

  **Q2 — Iteration mode** (how should the loop run by default?)
  ```
  Run mode [afk]:
    afk   — background, capped loop, fires a notification when done  (recommended)
    once  — foreground, single iteration, stays in your terminal
  ```

  **Q3 — Iteration cap** (AFK only — max iterations before stopping for review)
  ```
  Iteration cap [15]:  (1–50; Tachikoma stops and notifies you when hit)
  ```
  Skip Q3 if the user chose `once` in Q2.

  Write `~/.claude/tachikoma.conf` with the chosen values:
  ```
  quality_bar = <value>
  iteration_mode = <value>
  iteration_cap = <value>   # omit if once mode
  ```

  Print:
  ```
  ✓ Saved to ~/.claude/tachikoma.conf
    Edit any time to change defaults. Now continuing…
  ────────────────────────────────────────────────────
  ```

  Continue to Step 2 using the just-written config values.

**Step 2 — In `--issue` mode: fetch and parse the issue.**

Print: `Fetching issue #<N>…`
```bash
gh issue view <N> --json title,body,labels,comments,assignees,number
```
Extract from the issue body:
- **Goal**: issue title (or clearer one-liner from first paragraph of body)
- **Stop condition**: `## Acceptance Criteria` / `## Done When` / `## AC` section if present; else derive from title
- **Quality bar override**: scan for `prototype`, `production`, or `library` (case-insensitive, whole-word); if exactly one matches, override the config value; if ambiguous, config value wins
- **Files in scope**: `files_in_scope:` frontmatter or `## Files in Scope` section; default `**` (whole repo)
- **Files out of scope**: `files_out_of_scope:` frontmatter or `## Files out of Scope` section; default empty (no exclusions)

**Step 3 — Auto-detect feedback loops.** Check in order (no confirmation asked):
- `package.json` `scripts` keys: `typecheck`/`type-check`, `test`, `lint`
- `Makefile` targets of the same names
- `justfile` recipes of the same names
- `AGENTS.md` / `CLAUDE.md` documented commands
- Cargo / Go / Python equivalents

If nothing detected, set feedback loops to `echo "no feedback loop — skipped"`. Never refuse to launch for missing feedback loops.

**Step 4 — Determine PR target branch.** Check (in order, no prompt): `develop` exists → use it; `dev` exists → use it; else repo default branch (`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`).

**Step 5 — AFK permission check (silent).** For `afk` mode only: check `permissions.allow` in `.claude/settings.json` and `~/.claude/settings.json` for a token covering `nohup`. If absent, silently add `Bash(nohup *)` to project `.claude/settings.json` via the `update-config` skill. No user prompt.

**Step 6 — Print launch summary and immediately proceed to plan phase/3:**

```
── Tachikoma launching — <issue #N: title | goal>
  Quality:    <quality_bar>           [config | issue body]
  Mode:       --afk <cap>             [config]
  Feedback:   <typecheck> | <test> | <lint>   [detected]
  Scope:      <files_in_scope> (excluding: <out_of_scope or "none">)
  PR target:  <PR_TARGET_BRANCH>
  Worktree:   (creating...)
```

No user input required. plan phase/3 begin immediately.

## Plan: PRD synthesis (mode-forked)

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

The `to-prd` and `to-issues` skills require their issue-tracker mapping config (which abstract states map to which concrete labels). Run `/setup-matt-pocock-skills` first if not configured. (Label *existence* in the target repo is handled separately by setup phase above.)

### Existing-issue mode (`--issue <ref>`)

The issue **is** the PRD. No `to-prd`/`to-issues` calls; no `plans/prd.json`.

1. Fetch the full issue: `gh issue view <num> --json title,body,labels,comments,assignees,number`. You should already have done this in preflight.
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

## Claim: label (issue-linked runs)

For any run with a linked `github_issue` (from `--issue <N>`, `/tachikoma queue <repo>`, or a work_request with `github_issue` set):

**Before creating the worktree** (after plan phase, before scaffold phase):

1. Apply `agent-running` label to the issue, remove `ready-for-agent`:
   ```bash
   gh issue edit <N> --repo <org/repo> --add-label "agent-running" --remove-label "ready-for-agent"
   ```
2. Re-fetch the issue: `gh issue view <N> --repo <org/repo> --json labels`. Verify `agent-running` is present. This is the optimistic distributed lock — if another agent claimed it first, the label state will be inconsistent. If `agent-running` is absent, refuse and skip to the next issue (queue mode) or exit with a message (single-issue mode).
3. Update the linked work_request: `status: open` → `status: grabbed`, bump `last_updated`.

The `agent-running` label is the distributed claim signal. A concurrent Tachikoma filtering `ready-for-agent AND NOT agent-running` will not see this issue after step 1.

## Scaffold: worktree creation

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
   - `PR_TARGET_BRANCH` — determined by checking (in order): does `develop` exist (`git -C <MAIN_REPO> show-ref --verify --quiet refs/heads/develop`)? Does `dev` exist? If neither, ask the user: *"No `develop` or `dev` branch found. Which branch should the PR target?"* This is the branch the issue branch will PR against.
   - `ISSUE_BRANCH` = `feat/<slug>` for local/remote mode; `feat/issue-<N>-<slug>` for `--issue` mode. This intermediate branch is created off `PR_TARGET_BRANCH` and is the squash-merge target in ship phase.
   - `BASE_BRANCH` = `ISSUE_BRANCH`. The branch the tachikoma branches off and the merge target for ship phase. (Stored in `.tachikoma/base_branch`.)

3. **Collision check** (precondition 9 applied here in detail):
   - If `<WORKTREE_PATH>` exists: refuse with the exact path. Tell user to remove it (`git -C <MAIN_REPO> worktree remove <WORKTREE_PATH>`) or pick a different goal.
   - If `<ISSUE_BRANCH>` already exists (`git -C <MAIN_REPO> show-ref --verify --quiet refs/heads/<ISSUE_BRANCH>`): refuse — that branch already exists. Tell user to delete it first.
   - If `<TACHIKOMA_BRANCH>` already exists (`git -C <MAIN_REPO> show-ref --verify --quiet refs/heads/<TACHIKOMA_BRANCH>`): refuse and tell user to delete it (`git -C <MAIN_REPO> branch -D <TACHIKOMA_BRANCH>`) or finish/abandon the existing run.

4. **Create the issue branch and worktree:**
   ```bash
   # Create the issue branch off PR_TARGET_BRANCH (no checkout — stays in background):
   git -C <MAIN_REPO> branch <ISSUE_BRANCH> <PR_TARGET_BRANCH>
   # Create the tachikoma worktree branching off ISSUE_BRANCH:
   git -C <MAIN_REPO> worktree add <WORKTREE_PATH> -b <TACHIKOMA_BRANCH> <ISSUE_BRANCH>
   ```
   This creates the issue branch, the tachikoma branch off it, and a clean worktree directory.

5. **Scaffold inside the worktree.** All paths below are relative to `<WORKTREE_PATH>`:
   - Append `.tachikoma/` to `<WORKTREE_PATH>/.gitignore` if not already there.
   - Create `<WORKTREE_PATH>/.tachikoma/`.
   - Render `<WORKTREE_PATH>/.tachikoma/tachikoma.sh` from [tachikoma.sh.tmpl](tachikoma.sh.tmpl). **Set `{{REPO_PATH}} = WORKTREE_PATH`** (the script's `cd "$REPO"` keeps everything inside the worktree). `chmod +x`.
   - Render `<WORKTREE_PATH>/.tachikoma/prompt.md` from [prompt.md.tmpl](prompt.md.tmpl).
   - Write `<WORKTREE_PATH>/.tachikoma/base_branch` — single line containing `<ISSUE_BRANCH>`. ship phase reads this to know the squash-merge target. (Conversation context isn't enough — AFK runs span sessions.)
   - Write `<WORKTREE_PATH>/.tachikoma/pr_target_branch` — single line containing `<PR_TARGET_BRANCH>`. ship phase reads this to know what branch to open the PR against.
   - Render `<WORKTREE_PATH>/.tachikoma/ship.md` from [ship.md.tmpl](ship.md.tmpl). Substitute all placeholders:
     - `{{WORKTREE_PATH}}`, `{{TACHIKOMA_BRANCH}}`, `{{BASE_BRANCH}}`, `{{PR_TARGET_BRANCH}}`, `{{SLUG}}`
     - `{{REPO_OWNER_NAME}}` — `gh repo view --json nameWithOwner --jq .nameWithOwner` (or empty for local mode)
     - `{{GITHUB_ISSUE_LINE}}` — `Issue: <org/repo>#<N>` for `--issue` mode; empty otherwise
     - `{{COMMIT_MESSAGE}}` — `<issue-title> (#<N>)\n\nCloses #<N>` for `--issue` mode; goal summary for local/remote
     - `{{PR_TITLE}}` — issue title for `--issue` mode; goal summary otherwise
     - `{{PR_BODY_ESCAPED}}` — the full PR body (see ship phase Step 6 for required content), with internal double-quotes escaped for shell safety
     - `{{ISSUE_LABEL_BLOCK}}` — for issue-linked runs: the Step 6 label-update instructions (`gh issue edit ... --add-label ready-for-review --remove-label agent-running`); empty for local/remote
     - `{{ISSUE_CLOSE_BLOCK}}` — for `--issue` mode: the Step 7 close-issue instructions; empty otherwise
   - In **local** mode only: write `<WORKTREE_PATH>/plans/prd.json`.

6. **Commit the scaffolding inside the worktree** so the loop's first iteration has a clean tree. Use `git -C <WORKTREE_PATH>`:
   - Local: `git -C <WORKTREE_PATH> add .gitignore plans/prd.json && git -C <WORKTREE_PATH> commit -m "chore: scaffold tachikoma loop for <slug>"`
   - Remote-greenfield: `git -C <WORKTREE_PATH> add .gitignore && git -C <WORKTREE_PATH> commit -m "chore: scaffold tachikoma loop for <slug>"`
   - `--issue`: `git -C <WORKTREE_PATH> add .gitignore && git -C <WORKTREE_PATH> commit -m "chore: scaffold tachikoma loop for issue #<N>"`
   - `.tachikoma/` itself is gitignored — rendered scripts, logs, and `base_branch` do not get committed.

7. **Confirm worktree ready.** This resolves the `Worktree: (creating...)` line from the preflight summary. Print:
   ```
   ✓ Worktree ready
     Path:         <WORKTREE_PATH>
     Branch:       <TACHIKOMA_BRANCH>  (off <ISSUE_BRANCH>)
     Issue branch: <ISSUE_BRANCH>  (→ PR against <PR_TARGET_BRANCH>)
   ```

> Phase 4 (the standalone prompt review) was merged into preflight's combined plan-summary-and-launch confirmation. launch phase's number is preserved so cross-references in this skill, in run logs, and in user muscle memory stay valid; there is no separate gate between scaffold phase and launch phase.

## Launch

The orchestrator's cwd doesn't matter — both modes `cd` into `<WORKTREE_PATH>` first.

### `--once`
Run via Bash tool in foreground:
```bash
cd <WORKTREE_PATH> && .tachikoma/tachikoma.sh --once
```
Stream output. When the Bash tool returns, route on exit code:

- **Exit 0** (clean completion): show the user `cat <WORKTREE_PATH>/.tachikoma/progress.txt`, then **immediately enter ship phase** (the orchestrator is still in-session; don't print manual git instructions).
- **Non-zero exit** (Ctrl+C, internal error, or any other abnormal termination): read `<WORKTREE_PATH>/.tachikoma/outcome` and route on its value:
  - `stopped` — user pressed Ctrl+C. Tell them the loop was interrupted, then enter ship phase on whatever was committed (treat as complete enough for a draft PR).
  - `error` — internal error. **Auto-retry once**: clear the lockfile (`rm -f <WORKTREE_PATH>/.tachikoma/run.pid <WORKTREE_PATH>/.tachikoma/outcome`), re-run `cd <WORKTREE_PATH> && .tachikoma/tachikoma.sh --once`, and route on the new exit. If it errors again: push branch as a draft PR with the failure logged in the body, fire a macOS notification, and exit. Do NOT offer recover phase options.
  - missing or `unknown` — script never wrote an outcome file (killed with SIGKILL). **Auto-retry once** using the same logic as `error` above.

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

After launch, give the user a compact post-launch message in this format:
```
── Launched  (afk, cap <N>)
  Worktree:  <WORKTREE_PATH>
  PID:       <pid>  ·  branch <TACHIKOMA_BRANCH>
  Tail:      tail -f <WORKTREE_PATH>/.tachikoma/run.log
  Check in:  /tachikoma status
  Stop:      /tachikoma stop  ·  kill <pid>
  Done:      auto-ships on completion  (or /tachikoma done if it fails)
```

Do NOT print manual `git log`/`git merge`/`git branch -D`/`git worktree remove` instructions — ship phase handles those.

## Ship: merge, PR, cleanup (fully autonomous)

All steps run automatically — no prompts. Every decision is logged in the PR body. The only case that surfaces to the user is a merge conflict (can't be resolved without human judgment).

Triggered automatically in two ways:
- **`--once` mode**: orchestrator runs ship phase immediately after the loop exits (still in-session).
- **`--afk N` mode**: `tachikoma.sh` runs `claude -p "$(cat .tachikoma/ship.md)"` after the sentinel is detected, before exiting. The `ship.md` prompt was rendered at scaffold time with all variables pre-substituted. If auto-ship fails, the work is still committed on the tachikoma branch and the user can run `/tachikoma done` to ship manually.

Also triggerable manually:
- User runs `/tachikoma done` (optionally `/tachikoma done <slug>`) — for failed auto-ship recovery or any case where manual control is needed.

**Step 0 — Pick the tachikoma worktree, capture variables.**

Enumerate via `git -C <cwd> worktree list --porcelain`. Among worktrees with `outcome=complete`:
- If exactly one: that's `WORKTREE_PATH`.
- If user passed `/tachikoma done <slug>`: match against branch name; refuse if no match.
- Otherwise: present picker via AskUserQuestion.

Capture:
- `WORKTREE_PATH` — chosen above.
- `TACHIKOMA_BRANCH` = `git -C <WORKTREE_PATH> rev-parse --abbrev-ref HEAD` (must start with `tachikoma/`).
- `BASE_BRANCH` = contents of `<WORKTREE_PATH>/.tachikoma/base_branch`. Fallback: ask user.
- `PR_TARGET_BRANCH` = contents of `<WORKTREE_PATH>/.tachikoma/pr_target_branch`. Fallback: repo default branch.
- `MAIN_REPO` = `dirname` of `git -C <WORKTREE_PATH> rev-parse --path-format=absolute --git-common-dir`.

Print the ship phase header immediately after picking the worktree:
```
ship phase — <SLUG>
────────────────────────────────────────────────────
```

**Step 1 — Locate the base-worktree.**

Find the worktree where `<BASE_BRANCH>` is checked out. Call it `BASE_WT`. If not found anywhere, set `BASE_WT = MAIN_REPO` (will check out `<BASE_BRANCH>` there in Step 2).

**Step 2 — Handle dirty base-worktree.**

Print: `  Checking base worktree…`

Run `git -C <BASE_WT> status --porcelain`.

- **If clean:** print `  ✓ Base worktree clean`. Continue.
- **If dirty:** auto-stash, merge, then pop. Print `  ⚠ Base worktree has uncommitted changes — stashing…` then:
  ```bash
  git -C <BASE_WT> stash push -u -m "tachikoma auto-stash before ship (<SLUG>)"
  ```
  Print `  ✓ Stashed  (will restore after merge)`. Set `STASHED=true` and continue to Step 3.

After Step 4 (squash-merge), if `STASHED=true`:
  Print `  Restoring stash…`
  ```bash
  git -C <BASE_WT> stash pop
  ```
  - On success: print `  ✓ Stash restored`
  - On conflict: print:
    ```
      ⚠ Stash pop conflict — your stashed changes conflict with the merge.
        Resolve manually:
          cd <BASE_WT>
          git status        # see conflicting files
          git add <files> && git stash drop
    ```
    This doesn't block the PR or cleanup — the merge already landed. Proceed.

**Step 3 — Log the diff:**

Print: `  Diffing changes…`

```bash
git -C <WORKTREE_PATH> log <TACHIKOMA_BRANCH> ^<BASE_BRANCH> --oneline
git -C <WORKTREE_PATH> diff <BASE_BRANCH>...<TACHIKOMA_BRANCH> --stat
```
Print the diff output verbatim (indented 2 spaces), then print: `  ✓ <N> commits, <M> files changed`

**Step 4 — Squash-merge (automatic):**

Print: `  Squash-merging into <BASE_BRANCH>…`

```bash
git -C <BASE_WT> checkout <BASE_BRANCH>   # only if not already checked out there
git -C <BASE_WT> merge --squash <TACHIKOMA_BRANCH>
git -C <BASE_WT> commit -m "<auto-commit-message>"
```

Auto-commit message:
- `--issue` mode: `<issue-title> (#<N>)\n\nCloses #<N>`
- local/remote: one-line summary derived from goal

On success print: `  ✓ Squash-merged  (<commit-sha>)`

If the merge exits with a conflict: run `git -C <BASE_WT> merge --abort`, push the tachikoma branch as a draft PR with conflict files listed in the body, and surface the error to the user — this is the one case that requires human attention. Print:

```
  ✗ Merge conflict — cannot auto-merge <TACHIKOMA_BRANCH> into <BASE_BRANCH>

  Conflicting files:
    <file1>
    <file2>

  Draft PR opened: <PR_URL>

  To resolve:
    1. cd <WORKTREE_PATH>           # tachikoma's branch is still here
    2. git merge <BASE_BRANCH>      # re-trigger the conflict locally
    3. Resolve conflicts, then: git add . && git commit
    4. git push
    5. Convert the draft PR to ready for review on GitHub
    6. Delete the worktree when done: git worktree remove <WORKTREE_PATH> && git branch -D <TACHIKOMA_BRANCH>
```

Capture the commit SHA.

**Step 5 — Worktree + branch cleanup (automatic):**

Print: `  Cleaning up worktree…`

```bash
git -C <MAIN_REPO> worktree remove <WORKTREE_PATH>
# if that fails due to untracked files:
git -C <MAIN_REPO> worktree remove --force <WORKTREE_PATH>
git -C <MAIN_REPO> branch -D <TACHIKOMA_BRANCH>
```

On success print: `  ✓ Worktree + branch removed`

**Step 6 — Push + open PR (automatic):**

If `git -C <BASE_WT> remote -v` shows no remote or `gh auth status` fails: print `  ⚠ No remote — skipping PR` and continue to Step 7.

Otherwise:

Print: `  Pushing <BASE_BRANCH>…`

```bash
git -C <BASE_WT> push -u origin <BASE_BRANCH>
```

On success print: `  ✓ Pushed`

Print: `  Opening PR…`

```bash
gh -R <owner/repo> pr create --title "<derived>" --body "<pr-body>" --base <PR_TARGET_BRANCH> --head <BASE_BRANCH>
```

PR title: `<issue-title>` for `--issue` mode; goal summary for local/remote.

PR body must include:
```markdown
<summary of what was done — derived from progress.txt and commit log>

## Tachikoma run

- **Issue**: #<N> (if --issue mode)
- **Quality bar**: <quality_bar> [source: config | issue body]
- **Mode**: --afk <cap> [source: config]
- **Feedback loops**: <detected commands>
- **Files in scope**: <scope>
- **Iterations**: <N> completed
- **Branch**: `<TACHIKOMA_BRANCH>` → `<BASE_BRANCH>` → PR against `<PR_TARGET_BRANCH>`

Closes #<N>

<!-- tachikoma-slug: <SLUG> -->
<!-- tachikoma-issue: <org/repo#N> -->
```

Omit `Closes #<N>` and `tachikoma-issue` line for local/remote mode.

On success print: `  ✓ PR opened  <PR_URL>`

Register in `~/projects/personal-nix/wiki/pending-pr-cleanups.yml`:
```yaml
- pr_url: <PR_URL>
  slug: <SLUG>
  issue: <org/repo#N>   # omit if not --issue mode
  added: <YYYY-MM-DD>
```
Commit + push this to `personal-nix` (`git -C ~/projects/personal-nix commit -am "chore: register pending cleanup for <SLUG>" && git -C ~/projects/personal-nix push`).

For any issue-linked run (regardless of whether a PR was opened), print `  Updating issue labels…` then:
```bash
gh issue edit <N> --repo <org/repo> --add-label "ready-for-review" --remove-label "agent-running"
```

On success print: `  ✓ Labels updated  (ready-for-review)`

**Step 7 — Close issue (automatic, `--issue` mode only):**

- If a PR was opened AND `<PR_TARGET_BRANCH>` is the repo's default branch: print `  ✓ Issue will auto-close on PR merge  (Closes #<N>)` — skip explicit close.
- Otherwise: print `  Closing issue #<N>…` then:
  ```bash
  gh issue close <N> --comment "Resolved via Tachikoma: squash-merged <TACHIKOMA_BRANCH> into <BASE_BRANCH> as <commit-sha>.<pr-line>"
  ```
  Where `<pr-line>` is `\nPR: <url>` if a PR was opened, else empty.
  On success print: `  ✓ Issue #<N> closed`

**Step 8 — Final cleanup:**

Worktree was removed in Step 5. Nothing more to do for git state.

**Step 9 — Work-queue cleanup.**

Derive `SLUG` by stripping `tachikoma/` from `TACHIKOMA_BRANCH`. Check `~/projects/personal-nix/wiki/work-requests/<SLUG>.md`:
- If it doesn't exist: skip silently.
- If PR was opened: skip deletion — `tachikoma-cleanup` GitHub Actions workflow deletes it when the PR merges. Print `  ✓ Work-request will auto-delete on PR merge`
- If no PR was opened: invoke `/work-queue done <SLUG>` immediately. Print `  ✓ Work-request deleted`

After Step 9, print the completion footer:
```
────────────────────────────────────────────────────
✓ Done — <SLUG>
  PR:  <PR_URL>          (or "no PR — no remote")
  SHA: <commit-sha>
────────────────────────────────────────────────────
```

## Recover: interrupted run

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

**Step 3 — Auto-route by outcome:**

- **`error` or stale lockfile (crashed)**: auto-retry once. Clear `run.pid` and `outcome`, re-launch with `--afk <original-cap>` (or `--once` if that was the original mode). If the retry also ends in `error`: push the branch as a draft PR with the failure log in the body, fire a macOS notification, and exit. No user prompt.
- **`cap` (hit iteration limit)**: auto-retry once at `floor(cap / 2)`. If it caps again: push the branch as a draft PR, fire a macOS notification, and print:
  ```
  ⏱ Cap hit twice — opening draft PR with partial work.

  What happened:
    Tachikoma ran <original-cap> iterations, then retried at <half-cap>,
    and still didn't reach the goal. The work so far is real but incomplete.

  Draft PR opened: <PR_URL>
    The PR contains everything committed up to this point.
    It's a draft — nothing will merge until you promote it.

  What to do next:
    • Review the PR to see how far it got.
    • If the goal is too large: break it into smaller issues and run
      /tachikoma on each one individually.
    • If it just needs more iterations: reopen the issue, raise
      iteration_cap in ~/.claude/tachikoma.conf, and re-run.
    • To discard: close the draft PR and delete the branch.
  ```
- **`stopped` (deliberate Ctrl+C)**: jump directly to ship phase with `WORKTREE_PATH` pre-selected. Treat whatever was committed as complete enough.

Only surface to the user if the user explicitly runs `/tachikoma resume` — in that case offer the three manual paths (Resume / ship phase / Restart) as before, since the user is actively choosing to intervene.

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
- Last 15 lines of `<wt>/.tachikoma/ship.log` **only if that file exists** (most recent ship-phase output — surfaces why auto-ship failed without the user having to `cat` the file)
- Last 15 lines of `<wt>/.tachikoma/run.log` for raw context

Output:
```
Tachikoma — <tachikoma-branch>
────────────────────────────────────────────────────
  Status:    <RUNNING / COMPLETE / CAP / ERROR / STOPPED>
  PID:       <pid> (alive | dead)
  Iter:      <N> / <M>
  Mode:      <--once | --afk M>
  Worktree:  <WORKTREE_PATH>

Last milestone:
  <copy the milestone banner block verbatim>

Last progress note:
  <copy the most recent ## Iter N block from progress.txt>

Last ship attempt (last 15 lines):    # include this section ONLY when .tachikoma/ship.log exists; otherwise omit it entirely (no empty placeholder, no header)
  <tail of ship.log>

Recent log (last 15 lines):           # omit this section when .tachikoma/ship.log exists — the ship phase tees its output into run.log too, so the ship.log tail subsumes it and dropping run.log here keeps the view under ~40 lines
  <tail of run.log>

────────────────────────────────────────────────────
/tachikoma stop  ·  /tachikoma resume  ·  /tachikoma done
```

Light suggestions based on state:
- **RUNNING**: "Loop is healthy. Check back when notification fires."
- **COMPLETE**: "Loop done. `/tachikoma done` to enter ship phase."
- **CAP / ERROR / STOPPED**: "Loop ended in `<outcome>`. `/tachikoma resume` to see recover phase options."

Keep under ~40 lines.

### Multiple tachikomas (compact summary)

```
Tachikoma — <repo-name>  (<N> loops)
────────────────────────────────────────────────────
  RUNNING   <tachikoma-branch-1>   iter <N>/<M>   pid <pid>
  RUNNING   <tachikoma-branch-2>   iter <N>/<M>   pid <pid>
  COMPLETE  <tachikoma-branch-3>   awaiting /tachikoma done
  CAP       <tachikoma-branch-4>   ended at iter <N>/<M>
────────────────────────────────────────────────────
/tachikoma status <slug>  ·  /tachikoma stop  ·  /tachikoma done
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
2. Wait up to 60s for graceful exit; if still alive, `kill -KILL <PID>` and warn user about possibly-dirty worktree (which they'd see in recover phase).

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
────────────────────────────────────────────────────
[1/3] fix-vital-age  →  ~/projects/platform
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

**e. `cd` to `target_repo`.** Run scaffold phase (worktree creation + scaffolding) using the extracted fields. The target_repo's current HEAD is the base branch. Queue mode's per-item "Launch this item?" at step (c) is the single approval gate — Phase 4 was merged into preflight for the bare `/tachikoma` flow, and queue mode's step (c) plays the same role here, so there's no second prompt-review step before launch.

**f. launch phase — launch `--once` (foreground).** Stream the iteration output directly. Queue drain is the session driver; `--once` keeps items sequential and output readable.

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
── ship phase: fix-vital-age
```
This separates tachikoma's raw output from queue drain's ship phase actions in the scrollback.

**h. ship phase (abbreviated, uses batch preferences):**
- Show diff stat verbatim.
- Squash-merge: auto-approve unless conflicts arise (see failure handling below for conflict path).
- Worktree + branch cleanup: if `auto-clean=yes`, skip the interactive prompt and clean up automatically.
- PR: if `auto-open=yes`, derive title/body from goal + slug and open without review (user can edit on GitHub). Print the PR URL.
- Issue close: skip for local-mode items. For `--issue`-sourced items, apply ship phase Step 7 smart default.

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
- Treat as a failure (same path as `error` below). Do NOT auto-resume a third time.
- Before logging the failure, print:
  ```
  ⏱ [N/M] <slug> — cap hit twice (<original-cap> then <half-cap> iterations).
     The goal is likely too large for one run. Draft PR opened with partial work.
     See the failure log in the work-request file for what to try next.
  ```

#### Outcome: `error`, `stopped`, or `blocker-exit`

Skip immediately. No retry. Proceed to the failure-log path below, then move to the next item.

`stopped` = deliberate kill, don't retry. `blocker-exit` = tachikoma self-assessed as stuck, human input needed.

#### On any failure (after exhausting retries):

1. **Partial commits check:** run `git -C <WORKTREE_PATH> log <TACHIKOMA_BRANCH> ^<BASE_BRANCH> --oneline`. If commits exist beyond the scaffold commit:
   - Push the branch: `git -C <WORKTREE_PATH> push -u origin <TACHIKOMA_BRANCH>`
   - Open a draft PR: `gh pr create --draft --title "[partial] <goal-slug>" --body "Partial work from queue drain. See work-request failure log for context."`
   - Record the draft PR URL for the failure log.
   - **For `error` outcome (loop crashed twice), print this explanatory block** so the user sees a clear next-step picture when the notification fires:
     ```
     ⚠ [N/M] <slug> — loop crashed twice (outcome: error)

       The loop exited with an internal error and could not auto-recover. Partial work
       has been pushed as a draft PR so nothing is lost.

       Draft PR: <PR_URL>  (stays as draft — won't merge until you promote it to ready)

       What to do next:
         • Review the draft PR to see what was attempted
         • Check the run log: <WORKTREE_PATH>/.tachikoma/run.log
         • Fix the underlying error in the work-request and re-queue, OR
         • Discard the draft PR and close out the work-request
     ```
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

#### ship phase merge conflict

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
────────────────────────────────────────────────────
Queue drain complete — 2026-05-10
────────────────────────────────────────────────────
✓  fix-vital-age            PR #142  ~/projects/platform
✓  add-sleep-chart           PR #143  ~/projects/healthbite
✗  refactor-auth-middleware  FAILED (error · draft PR #144 · 1/2 failures)
⚠  wire-up-feature-flags     NEEDS TRIAGE (2/2 failures — excluded from future runs)

PRs opened:  #142, #143, #144 (draft)
Needs attention: 1 failed item · 1 needs-triage item
────────────────────────────────────────────────────
```

Write `.last-queue-run.md` using the identical content so it's readable both in terminal and in a text editor.

### When `<repo>` arg is provided: GitHub-sourced queue drain

When `/tachikoma queue <repo>` is invoked (e.g. `/tachikoma queue MioMarker/healthbite`):

**Step 0 — Fetch GitHub queue:**
1. `gh issue list --repo <repo> --label "ready-for-agent" --state open --json number,title,body,labels,comments --limit 100`
2. Filter out any issues that also have `agent-running` label (already claimed).
3. For each remaining issue, check `~/projects/personal-nix/wiki/work-requests/` for an existing work_request with `github_issue: <repo>#<N>`. If none exists, auto-create one (see plan phase work_request auto-creation rules above).
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
- [ship.md.tmpl](ship.md.tmpl) — the auto-ship prompt, run by `tachikoma.sh` via `claude -p` after the sentinel is detected. Placeholders: `{{WORKTREE_PATH}}`, `{{TACHIKOMA_BRANCH}}`, `{{BASE_BRANCH}}`, `{{PR_TARGET_BRANCH}}`, `{{SLUG}}`, `{{REPO_OWNER_NAME}}`, `{{GITHUB_ISSUE_LINE}}`, `{{COMMIT_MESSAGE}}`, `{{PR_TITLE}}`, `{{PR_BODY_ESCAPED}}`, `{{ISSUE_LABEL_BLOCK}}`, `{{ISSUE_CLOSE_BLOCK}}`.
- [AGENT-BRIEF.tmpl](AGENT-BRIEF.tmpl) — remote-mode agent brief comment, posted as a GitHub issue comment after `to-issues` promotes child issues. Placeholders: `{{CATEGORY}}`, `{{SUMMARY}}`, `{{CURRENT_BEHAVIOR}}`, `{{DESIRED_BEHAVIOR}}`, `{{KEY_INTERFACES}}`, `{{ACCEPTANCE_CRITERIA}}`, `{{OUT_OF_SCOPE}}`, `{{QUALITY_BAR}}`. Fill from grill answers + issue body content. Used in both `--remote` and `--issue` modes.

## Rendering `{{ALLOWED_TOOLS}}` (required, exact format)

This is the string Bash passes to `claude -p --allowed-tools`. Read the `allowed_tools` key from `~/.claude/tachikoma.conf` and use it verbatim. If the key is absent, use the built-in default (see Configuration section above).

Tokens must be **space-separated**. Do NOT pass an unqualified `Bash` — that grants carte blanche. The config default is intentionally broad but still glob-constrained.

### Anti-pattern (never render)
```
Bash,Read,Edit,Write     # commas not spaces; unqualified Bash
Bash                     # unqualified — grants everything
```

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

The **worktree** is the per-run sandbox. `.tachikoma/` lives inside it (gitignored). The `tachikoma/<slug>` branch is the durable record. ship phase squash-merges into base and (with user approval) removes the worktree + branch atomically.

After a successful run, **enter ship phase** — do NOT print manual git instructions to the user. ship phase walks them through the squash-merge, combined worktree+branch cleanup, and PR flow interactively.

`.tachikoma/base_branch` (single line, written at scaffold time) is the only piece of cross-session metadata ship phase needs that isn't recoverable from git itself.

## Failure modes to watch for

- Loop crashes mid-iteration with dirty working tree (in the worktree) → next iteration must refuse cleanly. The bash template handles this.
- Issue tracker auth expires mid-AFK run (remote mode) → loop logs error, exits, notification fires with `outcome=error`.
- Feedback loop times out or never finishes → not handled by v1; user kills the loop manually.
- User opens the worktree in another Claude Code session and starts editing → not handled; the per-worktree lockfile only prevents concurrent tachikoma loops in the *same* worktree, not concurrent humans there.
- `git worktree add` fails because path exists or branch exists → handled by precondition 9 + scaffold phase step 3 collision check; refuse with the exact path/branch.
- `git worktree remove` fails because of untracked files (e.g. `.tachikoma/run.log`) → ship phase retries with `--force`. Restart path in recover phase also uses `--force`.
- Base branch isn't checked out anywhere when ship phase runs → `BASE_WT = MAIN_REPO`; ship phase checks out `<BASE_BRANCH>` there before merging, but only if main repo's working tree is clean. Otherwise refuses.
- User runs `/tachikoma` from inside an active tachikoma worktree → precondition 4 refuses; tell them to `cd` to main repo or a non-tachikoma worktree.
- `.tachikoma/base_branch` missing (e.g. user manually deleted it, or worktree was scaffolded by an old version of this skill) → ship phase falls back to asking the user which branch to merge into.
