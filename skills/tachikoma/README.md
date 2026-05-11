# Tachikoma

Pocock's "Tachikoma Wiggum" autonomous AI coding loop, adapted to this machine, the RelyMD toolchain, and the existing `to-prd` / `to-issues` / `triage` skill chain.

## TL;DR

`/tachikoma --issue 138` reads `~/.claude/tachikoma.conf`, fetches the issue, scaffolds a sibling **git worktree**, and launches a capped bash loop that calls `claude -p` per iteration. When the loop finishes it automatically squash-merges, opens a PR, closes the issue, and cleans up. Zero prompts. You review the PR on GitHub.

**Multiple tachikomas can run concurrently on the same codebase** — each in its own sibling worktree. Discovery is per-repo via `git worktree list`; no global registry.

## Invocation

| Form | Behavior |
|---|---|
| `/tachikoma` | **Always starts a new task.** Mode (existing-issue / local / remote-greenfield) asked via two preflight questions. Reads `~/.claude/tachikoma.conf` for defaults; runs first-run onboarding if absent. New sibling worktree. Existing worktrees are not a blocker. |
| `/tachikoma --remote` | Fast-path for remote-greenfield mode — skips the mode-selection questions. PRD via `to-prd` → `to-issues`. New worktree. |
| `/tachikoma --issue <ref>` | Fast-path for existing-issue mode — skips the mode-selection questions. Uses GitHub issue body as PRD. New worktree. `<ref>` accepts `#138`, `138`, `org/repo#138`. |
| `/tachikoma 138` or `/tachikoma #138` | Shorthand — a bare integer or `#N` first arg is normalized to `/tachikoma --issue <N>` before preconditions run. Same fast-path behavior. |
| `/tachikoma done` (optionally `<slug>`) | Manually trigger ship phase. Fallback when auto-ship fails (or for any case where manual control is needed) — auto-ship is the normal merge trigger. Picker if >1 completed; auto-pick if 1. Also auto-routes here when bare `/tachikoma` runs with a single completed worktree. |
| `/tachikoma resume` (optionally `<slug>`) | Recover phase — re-launch an interrupted loop. Picker if >1 recoverable. |
| `/tachikoma status` (alias `/tachikoma t`, optionally `<slug>`) | Read-only telemetry. No args: compact summary table across all tachikoma worktrees in the repo. With slug: drill in. |
| `/tachikoma stop` (optionally `<slug>` or `--all`) | SIGTERM. Cwd-implicit if cwd is a tachikoma worktree. Picker if >1 running. |
| `/tachikoma queue` (optionally `<slug>`) | Drain the work-request queue sequentially — full tachikoma lifecycle (plan → ship) per item. Batch preferences set once up front. With `--caffeinated` / `-C`: wraps each item's launch with `caffeinate -d` to prevent macOS sleep during long overnight runs. |
| `/tachikoma queue <repo>` | GitHub-sourced queue drain. Fetches all `ready-for-agent AND NOT agent-running` issues from `<repo>` (`org/repo`), auto-creates linked work_requests for any without one, then runs normal queue drain. Fires a macOS HITL notification + terminal summary when no `ready-for-agent` issues remain. |

## File layout

```
~/projects/personal-nix/skills/tachikoma/        ← source (this dir)
├── README.md                                 this file (human orientation)
├── SKILL.md                                  orchestrator instructions
├── tachikoma.sh.tmpl                             bash loop template
├── prompt.md.tmpl                            per-iteration prompt template
└── AGENT-BRIEF.tmpl                          remote-mode comment template

~/.claude/skills/tachikoma                       ← symlink (created by `dev`)
```

Per-run, scaffolded into a **sibling worktree** of the main repo:

```
~/Projects/
├── platform/                                 ← main repo
└── platform-tachikoma-issue-138/                 ← sibling worktree (one per concurrent tachikoma)
    ├── .git                                  pointer file → main repo's .git/
    ├── .gitignore                            (modified to ignore .tachikoma/)
    ├── .tachikoma/                               runtime state, all gitignored
    │   ├── tachikoma.sh                          rendered loop ({{REPO_PATH}} = this worktree)
    │   ├── prompt.md                         rendered per-iteration prompt
    │   ├── progress.txt                      append-only epistemic log
    │   ├── base_branch                       single line: branch we'll merge back into
    │   ├── outcome                           complete | cap | error | stopped (written on exit)
    │   ├── run.pid                           lockfile (per-worktree, not per-repo)
    │   └── run.log                           AFK stdout/stderr
    ├── plans/prd.json                        ← local mode only
    └── ...                                   the codebase, on branch tachikoma/issue-138-...
```

Multiple concurrent tachikomas in the same repo:

```
~/Projects/
├── platform/                                 ← main repo
├── platform-tachikoma-issue-138-fix-vital-age/   ← worktree 1 (running)
├── platform-tachikoma-issue-140-add-cohort/      ← worktree 2 (running)
└── platform-tachikoma-issue-142-cleanup/         ← worktree 3 (complete, awaiting ship)
```

## Configuration

`~/.claude/tachikoma.conf` is the single source of run defaults — quality bar, iteration cap, iteration mode, and allowed tools. Read once per run, missing keys fall back to built-in defaults. Issue bodies can override quality bar and file scope per-run; everything else is global.

```
quality_bar    = production         # prototype | production | library
iteration_cap  = 15                 # integer, max 50
iteration_mode = afk                # afk | once
# allowed_tools = Edit Write Read Glob Grep Bash(git *) Bash(gh *) ...
```

**First-run onboarding.** If `~/.claude/tachikoma.conf` is absent, the first `/tachikoma` invocation runs a ~1-minute onboarding (three questions: quality bar, run mode, iteration cap), writes the config, and continues. Subsequent runs are silent.

## Locked-in design decisions

Reasoning so future-you doesn't relitigate.

- **Always-on git worktrees.** Every `/tachikoma` run creates a sibling worktree (`<main-parent>/<repo>-tachikoma-<slug>/`) and works inside it. No in-place mode. Lets multiple tachikomas run on the same codebase concurrently; lets the main repo stay dirty while a tachikoma runs (only HEAD is needed for `git worktree add`). One code path.
- **Per-repo discovery via `git worktree list`.** No global registry across repos. `/tachikoma status`/`stop`/`done`/`resume` enumerate worktrees of the current repo and find ones with `.tachikoma/` state. Cross-repo "lost tachikoma" → use `pgrep -f tachikoma.sh`.
- **Branch off cwd-worktree's HEAD.** New tachikoma branches off whichever branch the cwd worktree currently has checked out. Lets you tachikoma-off-a-feature-branch by `cd`ing into that worktree. Ship phase captures this as `BASE_BRANCH` in `.tachikoma/base_branch` and merges back into it.
- **`~/.claude/tachikoma.conf` is the single configuration source.** Quality bar, iteration cap, iteration mode, and allowed tools are set once globally. Issue bodies can override quality bar and file scope per-run. First-run onboarding seeds it; thereafter every launch is silent.
- **Ship is fully autonomous — no prompts.** Squash-merge, worktree+branch delete, push, PR creation, issue close all happen automatically. Decisions are logged in the PR body. The only exception is a merge conflict, which requires human judgment.
- **The PR is the artifact.** All decisions tachikoma made autonomously (config values used, feedback loops detected, iterations completed) are logged in the PR body for full visibility. The user's only touchpoint is reviewing the PR on GitHub.
- **Error auto-retry once, then draft PR.** `outcome=error` or `outcome=cap` triggers one automatic retry (cap retries at half the cap). Second failure pushes a draft PR with the failure log in the body and fires a macOS notification. No recover-phase prompts for automated runs.
- **Worktree+branch cleanup is automatic in ship phase.** After squash-merge, both are deleted without asking. Worktree isolation means no risk to the main repo.
- **Ship merge runs in the base-worktree.** `git -C <base-wt>` does the merge. If base-worktree is dirty, ship auto-stashes before merging and pops the stash after — no manual intervention required (a stash-pop conflict surfaces as a warning but does not block the PR).
- **Refuse `/tachikoma` from inside an active tachikoma worktree.** Branching off a mid-tachikoma state would inherit half-finished commits. User cd's to main repo or a non-tachikoma worktree first.
- **No batch fanout in v1.** Three sequential `/tachikoma --issue N` invocations cover the parallelism use case.
- **`agent-running` is the distributed claim signal.** Applied before worktree scaffolding (Phase 2.5), not after. Verified by re-fetching the issue after applying the label — if `agent-running` is absent, another agent claimed it first; skip or exit.
- **Label lifecycle mirrors work_request state.** Issue-linked runs: `ready-for-agent` → `agent-running` at claim; `agent-running` → `ready-for-review` at ship-phase completion. Failure reverts to `ready-for-agent` (< 2 failures) or `needs-triage` (≥ 2). Deliberate stop reverts without bumping `failure_count`.
- **Work_requests are always the canonical unit.** GitHub issues auto-create linked work_requests in Phase 2 (existing-issue mode) and `/tachikoma queue <repo>` Step 0.
- **Three modes, inferred automatically (with fast-path flags).** `--remote` and `--issue <ref>` skip mode-selection; bare `/tachikoma` asks two questions to choose. Same loop logic across all three; only the task-source query and completion check differ.
- **Ship auto-runs at sentinel.** `--once` immediately enters ship phase on exit 0 (orchestrator is still in-session). For `--afk`, `tachikoma.sh` runs `claude -p "$(cat .tachikoma/ship.md)"` after the sentinel is detected, before the script exits. If auto-ship fails, the work stays committed on the tachikoma branch and `/tachikoma done` retries the ship sequence manually.
- **Recover phase runs only on explicit `/tachikoma resume`.** Automated runs self-heal (retry once → draft PR). The manual Resume/Review/Restart paths are preserved for when the user explicitly intervenes.
- **Two log modes: light (default) and dev (`--dev`).** In light mode only structured progress banners print to the terminal; all raw claude output goes to `.tachikoma/run.log`. Pass `--dev` before the mode flag (`--dev --once` or `--dev --afk N`) to stream claude's full output to the terminal as well. Queue drain always runs light — `--dev` is for debugging a single item interactively.
- **Milestone banners always print to the terminal.** Per-iteration `✓ MILESTONE` banner, plus `🏁 TACHIKOMA COMPLETE` / `⏱ CAP HIT` on exit — regardless of log mode. Raw claude output only reaches the terminal in dev mode.
- **Allowed tools come from `~/.claude/tachikoma.conf`.** Default is a broad but glob-constrained list. No `--dangerously-skip-permissions`.
- **Sentinel = `<promise>COMPLETE</promise>`.** Pocock-exact, XML-tagged.
- **Per-iteration commit, never push.** Ship phase is the merge gate.
- **`.tachikoma/` gitignored, lives inside the worktree.** Removed when the worktree is removed.
- **Notification = `osascript` banner + `\a` bell.** No external services.

## Phases of one `/tachikoma`

1. **Preconditions** — git repo, ≥1 commit, `claude` on PATH, `git worktree` available, cwd not an active tachikoma worktree, no name collisions for the new worktree/branch, `gh` auth (remote/issue/queue-repo mode).
2. **Pre-flight** — read `~/.claude/tachikoma.conf`; fetch issue (issue mode); auto-detect feedback loops; determine PR target branch; print one-line launch summary. No questions asked.
3. **PRD synthesis** — local: write `<wt>/plans/prd.json`. Remote: `to-prd` → `to-issues` → agent brief → label. Issue mode: fetch issue, post agent brief, apply `ready-for-agent`. Auto-create a linked work_request if none exists.
4. **Label claim** (issue-linked runs only) — apply `agent-running`, remove `ready-for-agent`; re-fetch to verify claim succeeded (concurrent-agent guard); update work_request `status: grabbed`.
5. **Worktree + scaffold** — `git -C <main-repo> worktree add <wt> -b tachikoma/<slug> <issue-branch>`; render `<wt>/.tachikoma/tachikoma.sh`, `<wt>/.tachikoma/prompt.md`, `<wt>/.tachikoma/base_branch`, `<wt>/.tachikoma/pr_target_branch`. Commit scaffolding. Print worktree path and tail command.
6. **Launch** — `cd <wt> && .tachikoma/tachikoma.sh --once` (foreground) or `cd <wt> && nohup .tachikoma/tachikoma.sh --afk N > .tachikoma/run.log 2>&1 & disown`. Errors auto-retry once; second failure → draft PR.
7. **Ship (automatic)** — squash-merge → delete worktree + branch → push → open PR (with full run log in body) → apply `ready-for-review` / remove `agent-running` → close issue (smart default) → work-queue cleanup. No prompts. Only stops for merge conflicts. If auto-ship itself errors, the tachikoma branch retains all the work; run `/tachikoma done` to retry the ship sequence manually.

## Common breakages

- **"already running" refusal in a worktree** — stale lockfile in that specific worktree. `cat <wt>/.tachikoma/run.pid; kill <pid>; rm <wt>/.tachikoma/run.pid`.
- **Worktree path collision** — Phase 3 refuses if `<wt-path>` already exists. Run `git -C <main-repo> worktree remove <wt-path>` (or `--force` if files linger), then re-run `/tachikoma`.
- **Branch collision** — Phase 3 refuses if `tachikoma/<slug>` exists. `git -C <main-repo> branch -D tachikoma/<slug>` or finish/abandon the existing run.
- **`git worktree remove` fails on cleanup** — untracked files in the worktree (`.tachikoma/run.log`, etc.). Ship phase retries with `--force`.
- **Ship stash-pop conflict** — base-worktree had uncommitted edits when ship started; auto-stash worked, but `git stash pop` after the merge collided with the merged changes. The merge itself already landed — resolve manually in the base worktree (`git status` to see conflicts, then `git add <files> && git stash drop` when done). Does not block the PR.
- **Allowlist too narrow / too wide** — update `allowed_tools` in `~/.claude/tachikoma.conf`; takes effect on the next run.
- **`gh pr create` fails after run** — repo has no remote. Merge locally or add a remote.
- **Squash-merge → `git branch -d` refuses** — ship uses `-D`. Squash isn't fast-forward.
- **Auth expires mid-AFK** — iteration errors out, loop exits, notification fires `outcome=error`. Tachikoma auto-retries once; second failure opens a draft PR with the error log.
- **Working tree dirty inside a worktree at iteration start** — bash loop bails. Manual cleanup inside that worktree, then `/tachikoma resume <slug>`.
- **Refuses to start because cwd is an active tachikoma worktree** — cd to main repo or a non-tachikoma worktree first.
- **Long-lived Claude Code session uses stale SKILL.md** — open a fresh Claude session in the repo. Bash loop and rendered prompt are unaffected (already on disk).
- **`.tachikoma/base_branch` missing** — ship phase falls back to asking which branch to merge into. Happens for worktrees scaffolded by an old version of this skill.
- **Label claim lost (issue-linked run)** — after applying `agent-running`, re-fetch shows it's absent: another Tachikoma claimed it first. Single-issue mode exits with a message; queue mode skips to the next item. No worktree is created, no `failure_count` bump.
- **`agent-running` stuck on issue after crash** — Tachikoma died before ship phase could apply `ready-for-review`. Manually run: `gh issue edit <N> --repo <org/repo> --remove-label "agent-running" --add-label "ready-for-agent"` to return it to the pool.
- **Queue drain: item cap hit** — queue drain auto-retries once at half the cap. Second cap = failure, appends `## Queue Failures` to the work-request file, bumps `failure_count`. Two failures → `needs-triage`.
- **Queue drain: merge conflict at ship time** — aborts merge, pushes branch as a draft PR, logs failure, moves to next item. Work-request gets a `## Queue Failures` entry with the conflicting files.
- **macOS sleeps mid-queue-drain** — use `/tachikoma queue --caffeinated` (or `-C`); each item's launch is wrapped with `caffeinate -d`.

## Hacking on tachikoma itself

Symlink points at live working tree — edits to `~/projects/personal-nix/skills/tachikoma/*` take effect immediately. `dev` rebuild is only needed when adding a *new* skill directory under `personal-nix/skills/`.

## Open issues / known gaps

- **No token/cost cap.** Iteration count is the only budget knob.
- **No batch fanout.** Spinning up 3 tachikomas requires 3 sequential `/tachikoma --issue N` invocations.
- **No concurrent-human protection inside a worktree.** The per-worktree lockfile only prevents two tachikoma loops in the same worktree, not a human editing files there while tachikoma runs.
- **Feedback-loop timeout unset.** A pathological test command can hang an iteration; user kills the loop manually.
- **No cross-repo discovery.** `/tachikoma status` only sees worktrees of the current repo; cross-repo escape hatch is `pgrep -f tachikoma.sh`.
- **`--caffeinated` is macOS-only.** The flag wraps launches with `caffeinate -d`, a macOS utility. On Linux the flag is silently ignored (caffeinate doesn't exist). Use the OS-appropriate equivalent (`systemd-inhibit`, etc.) manually if needed.

## References

- Matt Pocock, ["11 Tips For AI Coding With Tachikoma Wiggum"](https://www.aihero.dev/tips-for-ai-coding-with-tachikoma-wiggum) (aihero.dev)
- Jeffrey Huntley, original Tachikoma Wiggum SOP
- Anthropic, ["Effective Harnesses"](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) (long-running agent design research)
