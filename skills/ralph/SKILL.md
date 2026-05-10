---
name: ralph
description: Autonomous AI coding loop. Interviews for a goal, generates a PRD (local JSON, GitHub greenfield, or existing GitHub issue), launches a capped `claude -p` loop, then walks you through squash-merge / PR / issue-close. Survives interruption (resumable from disk state). Triggers — `/ralph`, `/ralph --remote`, `/ralph --issue <ref>`, `/ralph done`, `/ralph resume`, `/ralph status` (alias `/ralph t`), `/ralph stop`, or any natural-language request to start, check on, recover, or wrap up a Ralph run ("kick off Ralph on issue #138", "AFK this backlog", "check the ralph status", "did ralph finish", "resume the ralph loop"). For methodology, see Matt Pocock's aihero.dev article and the Ralph SOP.
---

# Ralph

Autonomous AI coding loop. The user provides an end-state; Ralph picks tasks, implements one per iteration, runs feedback loops, commits, and repeats until done or capped.

## Invocation

| Form | Behavior |
|---|---|
| `/ralph` | Plan + run, **local mode** (PRD lives in `plans/prd.json`, deleted on completion) |
| `/ralph --remote` | Plan + run, **remote-greenfield mode** (PRD → `to-prd` → `to-issues` → auto-promoted to `ready-for-agent`) |
| `/ralph --issue <ref>` | Plan + run, **existing-issue mode** — uses a GitHub issue body as the PRD; loop scoped to that single issue |
| `/ralph done` | Manually trigger Phase 6 (post-completion review: squash-merge, branch cleanup, optional PR, optional issue close) for a loop that finished without your interaction. Auto-triggered when `/ralph` is invoked with no args in a repo where `.ralph/outcome` is `complete`. |
| `/ralph resume` | Re-launch a previously interrupted loop. Agent reads `.ralph/progress.txt` + the PRD and picks up at the next unfinished task. Auto-offered when `/ralph` (no args) is run in a repo with partial state. |
| `/ralph status` (alias `/ralph t`) | Telemetry check on a running or recently-finished loop. Shows PID liveness, current iter, last milestone banner, last progress note, recent log lines. Read-only — does not interrupt the loop. |
| `/ralph stop` | SIGTERM the running loop in cwd via `.ralph/run.pid` |

`<ref>` accepts: `#138`, `138`, or `org/repo#138`. The `org/repo` form must match the cwd repo's `nameWithOwner`; if not, refuse and tell the user to `cd` first.

If the user types `/ralph` while a lockfile already exists at `.ralph/run.pid` and the PID is alive, refuse and tell them to `/ralph stop` or kill the PID.

## Preconditions (refuse with explanation if violated)

1. cwd must be inside a git repo (`git rev-parse --git-dir`).
2. Repo must have at least one commit (`git rev-parse HEAD` succeeds). Unborn repo = refuse; tell user to `git commit --allow-empty -m init` first. Without this, the loop's dirty-tree check, `git log` references, and squash-merge guidance all break.
3. Working tree must be clean (`git status --porcelain` empty). Dirty tree = refuse; tell user to commit/stash first.
4. `claude` CLI on PATH (`command -v claude`).
5. For `--remote` and `--issue`: `gh` CLI on PATH and authenticated (`gh auth status`).
6. For `--issue <ref>`:
   - The issue must exist and be open (`gh issue view <num> --json state,title,body,labels` succeeds and `state == OPEN`). If closed, refuse; user can reopen if they really mean it.
   - The cwd repo's `nameWithOwner` must match the ref's repo (if user passed `org/repo#N`). If mismatch, refuse — `cd` first.
   - The label vocabulary must be set up in the target repo (`gh label list --limit 100` includes a label that maps to `ready-for-agent`). If absent, tell user to run `/setup-matt-pocock-skills` against this repo first.
7. `.ralph/` and `plans/` may contain partial state from a previous run. Read it carefully and route — do NOT just refuse. State-detection sequence:

   **a. Is the loop still alive?** If `.ralph/run.pid` exists and `kill -0 <pid>` succeeds:
      → Refuse: "loop running at PID <X>; use `/ralph stop` or `kill <X>` first."

   **b. Is the working tree dirty?** If `git status --porcelain` is non-empty (regardless of outcome):
      → Refuse: state is inconsistent — a prior iteration probably crashed mid-commit. User must `git status`, then commit/stash/reset, then re-run `/ralph`.

   **c. Did the previous run complete cleanly?** If `.ralph/outcome` is `complete`:
      → Route to Phase 6 (post-completion review). Don't refuse; this is their finished run waiting for merge.

   **d. Did the previous run end in a recoverable state?** If `.ralph/outcome` is `cap`, `error`, or `stopped`, OR if the lockfile exists with a dead PID (crash, no graceful cleanup):
      → Enter **Phase R: recovery** (below). Show the user the partial state and offer three paths.

   **e. Pure stale clutter** (e.g., `.ralph/` exists but nothing inside is meaningful): ask whether to clean.

Ralph branches to `ralph/<slug>` off whatever HEAD is. Being on `main`/`master` is fine — Ralph never commits there. Capture the base branch name (`git rev-parse --abbrev-ref HEAD`) before branching so you can show it to the user and reference it in completion guidance.

## Phase 1: planning grill

Run a Ralph-specific grill — do **not** invoke the generic `grill-me` skill. The fields below are required; ask only for those you cannot infer from the conversation context already.

In **`--issue <ref>` mode**: fetch the issue first (`gh issue view <num> --json title,body,labels,comments,assignees`). The issue body is the source of truth for **goal** and **stop condition** — extract them directly. Only grill the user for fields the issue body doesn't cover (typically: files in/out of scope, quality bar, mode/cap, feedback loops). Confirm the extracted goal/stop-condition with the user before proceeding.

### Required fields

1. **Goal** — one-sentence end-state. "Ralph is done when …". *In `--issue` mode: extracted from issue body, confirmed with user.*
2. **Quality bar** — one of:
   - `prototype` ("speed over perfection, shortcuts OK")
   - `production` ("must be maintainable, tests required, no shortcuts")
   - `library` ("public API, backward compatibility matters, careful with breaking changes")
3. **Files in scope** — explicit globs/paths Ralph may modify. Pocock's tip #3 — without this, Ralph redefines "done" to exclude inconvenient files.
4. **Files out of scope** — explicit globs/paths Ralph must NOT touch. Use a list that does NOT overlap with files-in-scope (e.g., name specific dirs to exclude rather than `**` which matches everything).
5. **Stop condition** — concrete acceptance criteria. "Done" must be testable, not "improve the codebase". *In `--issue` mode: extracted from issue acceptance criteria if present.*
6. **Iteration mode** — `--once` (one iteration, foreground) or `--afk N` (capped loop, background). *In `--issue` mode: bias toward `--once` since the loop is scoped to a single issue.*
7. **Iteration cap** (AFK only) — if user has no preference, suggest based on PRD size: 1–3 items → 5, 4–9 → 15, 10+ → 30. Hard ceiling 50; refuse higher. *In `--issue` mode: cap at 5 unless the user explicitly overrides — single issues rarely need more.*

### Auto-detected fields (confirm with user before locking in)

8. **Feedback-loop commands** — auto-detect from these sources, in order:
   - `package.json` `scripts` keys: `typecheck`/`type-check`, `test`, `lint`
   - `Makefile` targets of the same names
   - `justfile` recipes of the same names
   - `AGENTS.md` / `CLAUDE.md` if they document the canonical commands
   - Cargo / Go / Python equivalents if applicable

   Show the user the detected commands and ask: "These look right? Anything to add/remove?" If nothing detected, ask explicitly. At least one feedback loop must be defined; refuse to launch without any.

### Grill output

After the grill, summarize all fields in a numbered list — including **Base branch** (current HEAD, where `ralph/<slug>` will be rooted and where you'll merge back at the end) and **Ralph branch** (the computed `ralph/<slug>` name). Ask "Approved?" before proceeding.

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

The `to-prd` and `to-issues` skills require the issue tracker / label vocabulary mapping. Run `/setup-matt-pocock-skills` first if not configured.

### Existing-issue mode (`--issue <ref>`)

The issue **is** the PRD. No `to-prd`/`to-issues` calls; no `plans/prd.json`.

1. Fetch the full issue: `gh issue view <num> --json title,body,labels,comments,assignees,number`. You should already have done this in Phase 1.
2. Render an agent brief from [AGENT-BRIEF.tmpl](AGENT-BRIEF.tmpl) using the grill answers + the issue body's existing content. Lean heavily on the issue body — don't restate what's already there. The brief is a *supplement*, not a replacement.
3. Post the rendered brief as a new comment on the issue. Even if a prior brief comment exists, post a fresh one — old briefs may have stale assumptions; let the human reading the issue see the timestamp progression.
4. Apply the `ready-for-agent` label to the issue. If `needs-triage`, `needs-info`, or any other state label is present, remove it.
5. Capture the issue number — the loop's task source will be scoped to it specifically (not the broader `ready-for-agent` query).

If the issue is already labeled `ready-for-agent` and has a recent agent-brief comment from a prior `/ralph` invocation, ask the user whether to repost a fresh brief or reuse the existing one.

## Phase 3: branch + scaffolding

1. Compute slug. Source depends on mode:
   - Local / Remote-greenfield: derive from grill goal.
   - `--issue`: derive from issue title — `ralph/issue-<N>-<slug-of-title>`. Keeps the issue number in the branch name for traceability.

   Slug normalization in all cases: lowercase, alphanumeric + dashes, max 40 chars.
2. `git checkout -b ralph/<slug>` (or `ralph/issue-<N>-<slug>` in `--issue` mode).
3. Create `.ralph/` directory.
4. Append `.ralph/` to repo's `.gitignore` if not already ignored.
5. Render `.ralph/ralph.sh` from [ralph.sh.tmpl](ralph.sh.tmpl). `chmod +x`.
6. Render `.ralph/prompt.md` from [prompt.md.tmpl](prompt.md.tmpl).
7. In **local** mode only: write `plans/prd.json`. (Remote-greenfield and `--issue` modes read from the tracker per iteration.)
8. **Commit the scaffolding** before launching. The loop requires a clean working tree at iteration start; uncommitted scaffolding will trip its `git status --porcelain` check immediately.
   - Local: `git add .gitignore plans/prd.json && git commit -m "chore: scaffold ralph loop for <slug>"`
   - Remote-greenfield: `git add .gitignore && git commit -m "chore: scaffold ralph loop for <slug>"`
   - `--issue`: `git add .gitignore && git commit -m "chore: scaffold ralph loop for issue #<N>"`
   - `.ralph/` itself is gitignored — the rendered scripts/logs do not get committed.

## Phase 4: prompt review (mandatory)

Show the user the rendered `.ralph/prompt.md` in full. Ask "Launch?" — only proceed on explicit approval. If user requests edits, edit `.ralph/prompt.md` and re-show.

## Phase 5: launch

### `--once`
Run via Bash tool in foreground:
```bash
.ralph/ralph.sh --once
```
Stream output. When it exits, show the user `cat .ralph/progress.txt`, then **immediately enter Phase 6** (the orchestrator is still in-session; don't print manual git instructions).

### `--afk N`
Launch backgrounded and detached so it survives this session ending:
```bash
nohup .ralph/ralph.sh --afk N > .ralph/run.log 2>&1 & disown
```
After launch, give the user a compact post-launch message with these four pointers (in this order):
- **PID**: `<pid>`, branch `<ralph-branch>`, cap `N` iterations, log `.ralph/run.log`
- **Check in**: `/ralph status` (or `/ralph t`) — read-only telemetry, doesn't interrupt the loop
- **Stop**: `/ralph stop` or `kill <pid>`
- **When done**: macOS notification fires; then `/ralph` (no args) auto-routes to Phase 6 for review/merge/PR

Do NOT print manual `git log`/`git merge`/`git branch -D` instructions — Phase 6 handles those.

## Phase 6: post-completion review

Triggered when:
- `--once` mode finishes (orchestrator transitions immediately)
- User runs `/ralph done` in a repo with a finished loop
- User runs `/ralph` with no args in a repo where `.ralph/outcome` is `complete`

**Step 1 — Show what changed.** Run both:
```bash
git log <ralph-branch> ^<base-branch> --oneline
git diff <base-branch>...<ralph-branch> --stat
```
Present output. Don't summarize — let the user see the raw commits and stat output.

**Step 2 — Offer squash-merge.** Ask: *"Squash-merge `<ralph-branch>` into `<base-branch>`?"*
- On yes:
  ```bash
  git checkout <base-branch>
  git merge --squash <ralph-branch>
  ```
  Propose a commit message — for `--issue` mode use `<issue-title> (#<N>)\n\nCloses #<N>`; for local/remote use a summary derived from the goal. Show the proposed message and let user edit before:
  ```bash
  git commit -m "<approved message>"
  ```
- On "let me review first" / no: exit Phase 6 quietly. User can re-trigger with `/ralph done` later.

**Step 3 — Offer branch cleanup.** Only after a successful merge: *"Delete `<ralph-branch>`?"*
- On yes: `git branch -D <ralph-branch>` (force; squash-merge isn't fast-forward so plain `-d` would refuse).

**Step 4 — Offer PR.** Only if `git remote -v` shows a remote AND `gh auth status` succeeds: *"Push `<base-branch>` and open a PR?"*
- On yes:
  - Push if needed: `git push -u origin <base-branch>` (or skip if already up to date)
  - Open PR: `gh pr create --title "<derived>" --body "<derived>"`. For `--issue` mode, body should reference `Closes #<N>`. Show the proposed title/body and let user edit before running.
  - Print the PR URL. Capture it for Step 5.
- On no: skip; user can do it manually later.

**Step 5 — Offer to close the issue** *(`--issue` mode only)*. Ask: *"Close issue #<N> now?"*

Note: this is human-approved closure, not autonomous. The "agents don't close issues" convention applies to the AFK loop in Phase 5, NOT to Phase 6 where the user is actively approving every step.

Smart default for the prompt:
- If a PR was opened in Step 4 AND `<base-branch>` is the repo's default branch: recommend **"no"** — GitHub will auto-close on merge via the `Closes #<N>` line.
- If a PR was opened but `<base-branch>` is NOT the default branch: recommend **"yes"** — the merge into a non-default branch won't trigger auto-close.
- If no PR was opened (Step 4 skipped): recommend **"yes"** — there's nothing else that will close it.

On yes:
```bash
gh issue close <N> --comment "Resolved via Ralph: squash-merged <ralph-branch> into <base-branch> as <commit-sha>.<pr-line-if-any>"
```
Where `<pr-line-if-any>` is `\nPR: <url>` if a PR was opened, else empty.

On no: skip; user can close manually later via `gh issue close <N>`.

**Step 6 — Cleanup.** Remove `.ralph/outcome` so the next `/ralph` invocation in this repo doesn't re-route to Phase 6:
```bash
rm -f .ralph/outcome
```
Leave the rest of `.ralph/` (the prompt, run.log, progress.txt) for the user's reference; they can `rm -rf .ralph/` themselves.

**If user bails mid-Phase-6** (says no at any step): exit cleanly. The state is recoverable — `.ralph/outcome` stays, so `/ralph done` works again later. Phase 6 is idempotent; re-entering picks up where they left off (skip steps that are already done — e.g., if the merge already happened, skip Step 2 and resume at Step 3).

## Phase R: recovery from interruption

Triggered when:
- Precondition 7d detects partial state (outcome ∈ {cap, error, stopped} or stale lockfile with dead PID)
- User runs `/ralph resume` explicitly

**Step 1 — Show what happened.** Read and present:
- Last entry in `.ralph/progress.txt` (most recent iteration's note)
- Last 30 lines of `.ralph/run.log` if it exists
- Completed-task count: in local mode, count items where `passes: true` in `plans/prd.json`. In remote/`--issue` mode, list commits on the ralph branch since base.
- Outcome value (if any) and the iter count from the loop's own banner.

**Step 2 — Verify the resume is safe.** Re-check `git status --porcelain`. Should be clean (precondition 7b would have refused otherwise, but double-check before re-launching). If anything is off, surface it and stop.

**Step 3 — Offer three paths.** Ask the user:

| Path | What it does |
|---|---|
| **Resume** | Re-launch `.ralph/ralph.sh` with the user's chosen mode/cap. Agent reads progress.txt + PRD/issue, picks the next `passes: false` item (or in `--issue` mode, the unfinished portion based on commits already made), continues. |
| **Review** (Phase 6) | Treat what's already committed as "done enough." Enter Phase 6 to squash-merge the partial work into the base branch. Useful if the loop got far enough to ship something. |
| **Restart** | `rm -rf .ralph/ plans/prd.json` and run a fresh `/ralph`. Discards partial work. The `ralph/<slug>` branch and its commits stay — you can review/cherry-pick later if you want to salvage anything. |

For the **Resume** path:
- Default cap suggestion: `--afk 5` if previous mode was `--afk` (most resumes only need a few more iterations); `--once` if previous was `--once`. Let user override.
- Before re-launching, remove the stale `.ralph/run.pid` and `.ralph/outcome` if present so the bash loop's startup checks pass cleanly.
- Re-launch via the same Phase 5 mechanism (`--once` foreground or `--afk N` via nohup+disown).

For the **Review** path: jump straight to Phase 6, treating the current branch state as the final result.

For the **Restart** path: confirm destructive action ("this will delete `.ralph/` and `plans/prd.json` — the branch stays. OK?"). On confirmation, clean and fall through to a fresh planning grill.

## Subcommand: `/ralph status` (alias `/ralph t`)

Read-only telemetry. Never modifies state. Works whether the loop is running, finished, or interrupted.

**Step 1 — Detect state:**
- `.ralph/run.pid` exists + `kill -0 <pid>` succeeds → **running**
- `.ralph/outcome=complete` → **finished, awaiting Phase 6**
- `.ralph/outcome ∈ {cap, error, stopped}` → **interrupted, awaiting Phase R**
- No `.ralph/` → tell user no Ralph state in this repo, exit

**Step 2 — Gather:**
- PID + alive-status
- Branch (`git rev-parse --abbrev-ref HEAD` if on ralph branch, else parse from log)
- Cap and iter-progress: scan `.ralph/run.log` for the most recent `==================== iter N / M ====================` line
- Last milestone banner: scan `.ralph/run.log` for the most recent `✓ MILESTONE` block (5 lines), or `⚠ BLOCKER` block, or the final `🏁 RALPH COMPLETE` / `⏱ CAP HIT` banner if present
- Last progress note: tail of `.ralph/progress.txt` (most recent `## Iter N` block)
- Last 15 lines of `.ralph/run.log` for raw context

**Step 3 — Format output** like this:

```
Ralph telemetry — <ralph-branch>
─────────────────────────────────────────────────────
  Status:   <RUNNING / COMPLETE / CAP / ERROR / STOPPED>
  PID:      <pid> (alive | dead)
  Iter:     <N> / <M>
  Mode:     <--once | --afk M>

Last milestone:
  <copy the milestone banner block verbatim>

Last progress note:
  <copy the most recent ## Iter N block from progress.txt>

Recent log (last 15 lines):
  <tail of run.log>

────
Stop: /ralph stop  ·  Resume on next interaction: /ralph
```

**Step 4 — Light suggestions** based on state:
- **Running**: "Loop is healthy. Check back when notification fires, or run `/ralph status` again."
- **Complete**: "Loop done. Run `/ralph` (no args) to enter Phase 6."
- **Interrupted**: "Loop ended in `<outcome>`. Run `/ralph` (no args) to see Phase R recovery options."

Keep the whole output under ~40 lines. The user wants a glanceable check-in, not a full debug dump.

## Subcommand: `/ralph stop`

1. Read `.ralph/run.pid`. If missing or PID dead, tell user no loop is running.
2. `kill -TERM <PID>`. The script's trap catches SIGTERM, finishes the current iteration cleanly, removes the lockfile, fires the completion notification with outcome `stopped`, exits.
3. Wait up to 60s for graceful exit; if still alive, escalate to `kill -KILL <PID>` and warn user about possible dirty working tree.

## Templates in this skill

- [ralph.sh.tmpl](ralph.sh.tmpl) — the bash loop. Placeholders: `{{ALLOWED_TOOLS}}`, `{{SENTINEL}}`, `{{REPO_PATH}}`.
- [prompt.md.tmpl](prompt.md.tmpl) — the per-iteration prompt. Placeholders: `{{GOAL}}`, `{{QUALITY_BAR_PARAGRAPH}}`, `{{FILES_IN_SCOPE}}`, `{{FILES_OUT_OF_SCOPE}}`, `{{STOP_CONDITION}}`, `{{TASK_SOURCE_BLOCK}}`, `{{TYPECHECK_CMD}}`, `{{TEST_CMD}}`, `{{LINT_CMD}}`, `{{COMMIT_INSTRUCTIONS}}`, `{{COMPLETION_INSTRUCTIONS}}`.
- [AGENT-BRIEF.tmpl](AGENT-BRIEF.tmpl) — remote-mode agent brief comment.

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
  2. `git add -A && git commit -m "chore: ralph complete, remove plans/prd.json"`
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

Exception: if you decomposed the issue into subtasks because it was too large for one iteration, do NOT emit the sentinel. Append a blocker note to `.ralph/progress.txt` with the proposed decomposition, optionally post a comment on issue #<N> outlining the split, and exit. The human will triage.
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
Instead, append a blocker note to `.ralph/progress.txt` describing what you
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

`.ralph/` is ephemeral runtime state. The repo's `.gitignore` keeps it out of commits. `plans/prd.json` is committed per iteration in local mode (so iteration-to-iteration diffs work) and deleted at completion. The `ralph/<slug>` branch is the durable record — review it, squash-merge or rebase, ship.

After a successful run, **enter Phase 6** — do NOT print manual git instructions to the user. Phase 6 walks them through the squash-merge, branch cleanup, and PR flow interactively.

## Failure modes to watch for

- Loop crashes mid-iteration with dirty working tree → next iteration must `git stash` or refuse cleanly. The bash template handles this.
- Issue tracker auth expires mid-AFK run (remote mode) → loop logs error, exits, notification fires with `outcome=error`.
- Feedback loop times out or never finishes → not handled by v1; user kills the loop manually.
- User opens the same repo in another Claude Code session and starts editing → not handled; the lockfile only prevents concurrent ralph loops, not concurrent humans.
