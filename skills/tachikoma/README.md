# Tachikoma

Pocock's "Tachikoma Wiggum" autonomous AI coding loop, adapted to this machine, the RelyMD toolchain, and the existing `to-prd` / `to-issues` / `triage` skill chain.

## TL;DR

`/tachikoma` grills you for a goal, generates a PRD (local JSON or GitHub issues), creates a sibling **git worktree** off cwd's HEAD, branches it as `tachikoma/<slug>`, and launches a capped bash loop in that worktree that calls `claude -p` per iteration until the backlog drains or the cap is hit. Loop runs out-of-process — survives the parent Claude Code session ending.

**Multiple tachikomas can run concurrently on the same codebase** — each in its own sibling worktree. Discovery is per-repo via `git worktree list`; no global registry.

## Invocation

| Form | Behavior |
|---|---|
| `/tachikoma` | Plan + run. Mode (existing-issue / local / remote-greenfield) is chosen via two grill questions in Phase 1. New sibling worktree. |
| `/tachikoma --remote` | Fast-path: skip the mode-selection grill questions and go straight to remote-greenfield mode. PRD via `to-prd` → `to-issues`. New worktree. |
| `/tachikoma --issue <ref>` | Fast-path: skip the mode-selection grill questions and go straight to existing-issue mode. Uses GitHub issue body as PRD. New worktree. `<ref>` accepts `#138`, `138`, `org/repo#138`. |
| `/tachikoma 138` or `/tachikoma #138` | Shorthand — a bare integer or `#N` first arg is normalized to `/tachikoma --issue <N>` before preconditions run. Same fast-path behavior. |
| `/tachikoma done` (optionally `<slug>`) | Phase 6 — interactive squash-merge into base + worktree+branch cleanup + optional PR/issue-close. Picker if >1 completed; auto-pick if 1. |
| `/tachikoma resume` (optionally `<slug>`) | Phase R — re-launch an interrupted loop. Picker if >1 recoverable. |
| `/tachikoma status` (alias `/tachikoma t`, optionally `<slug>`) | Read-only telemetry. No args: compact summary table across all tachikoma worktrees in the repo. With slug: drill in. |
| `/tachikoma stop` (optionally `<slug>` or `--all`) | SIGTERM. Cwd-implicit if cwd is a tachikoma worktree. Picker if >1 running. |
| `/tachikoma queue` (optionally `<slug>`) | Drain the work-request queue sequentially — full Phases 1–6 per item. Batch preferences set once up front. With `--caffeinated` / `-C`: wraps each item's launch with `caffeinate -d` to prevent macOS sleep during long overnight runs. |

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
└── platform-tachikoma-issue-142-cleanup/         ← worktree 3 (complete, awaiting Phase 6)
```

## Locked-in design decisions

Reasoning so future-you doesn't relitigate.

- **Always-on git worktrees.** Every `/tachikoma` run creates a sibling worktree (`<main-parent>/<repo>-tachikoma-<slug>/`) and works inside it. No in-place mode. Lets multiple tachikomas run on the same codebase concurrently; lets the main repo stay dirty while a tachikoma runs (only HEAD is needed for `git worktree add`). One code path.
- **Per-repo discovery via `git worktree list`.** No global registry across repos. `/tachikoma status`/`stop`/`done`/`resume` enumerate worktrees of the current repo and find ones with `.tachikoma/` state. Cross-repo "lost tachikoma" → use `pgrep -f tachikoma.sh`.
- **Branch off cwd-worktree's HEAD.** New tachikoma branches off whichever branch the cwd worktree currently has checked out. Lets you tachikoma-off-a-feature-branch by `cd`ing into that worktree. Phase 6 captures this as `BASE_BRANCH` in `.tachikoma/base_branch` and merges back into it.
- **Worktree+branch cleanup is one combined prompt in Phase 6.** Squash-merge succeeds → ask "delete worktree `<path>` and branch `<tachikoma-branch>`?" — yes runs both ops; no leaves both for manual cleanup. They're coupled (worktree without its branch is incoherent).
- **Phase 6 merge runs in the base-worktree.** `git -C <base-wt>` does the merge regardless of orchestrator cwd. Refuses if base-worktree dirty. Auto-stash deemed too risky.
- **Refuse `/tachikoma` from inside an active tachikoma worktree.** Branching off a mid-tachikoma state would inherit half-finished commits. User cd's to main repo or a non-tachikoma worktree first.
- **No batch fanout in v1.** Three sequential `/tachikoma --issue N` invocations cover the parallelism use case; batch design (shared grill, fan-in status) deferred until pain points emerge.
- **Three modes, picked in the grill (with fast-path flags).** Local for prototype work, remote-greenfield for new backlogs, existing-issue for a specific GitHub issue. Phase 1 collects the choice via two questions ("existing issue?" then, if no, "local or remote?"). `--remote` and `--issue <ref>` are fast-paths that skip those questions when the user already knows the mode. Same loop logic across all three; only the task-source query and completion check differ.
- **Phase 6 auto-runs at sentinel.** Bash loop writes `.tachikoma/outcome=complete` on success. `--once` mode immediately enters Phase 6. For `--afk`, the next `/tachikoma` invocation detects completed worktrees and routes to Phase 6.
- **Phase R recovers interrupted runs.** State is fully resumable per worktree. After an interruption, `/tachikoma` (or `/tachikoma resume`) detects recoverable worktrees and offers Resume / Review / Restart per worktree. Restart can fully remove the worktree.
- **Milestone banners stream during the run.** Per-iteration `✓ MILESTONE` banner with a one-line "what's now true that wasn't", plus `🏁 TACHIKOMA COMPLETE` / `⏱ CAP HIT` banner on exit.
- **`/tachikoma status` (alias `/tachikoma t`) — compact summary by default, drill-in by slug.** Multi-loop summary is one row per worktree. `/tachikoma status <slug>` shows the full ~40-line detail for one loop.
- **Test-must-exist enforcement, not full TDD.** Per-iteration prompt requires: if you added new behavior, a test must exist that exercises it.
- **Human-approved issue close in Phase 6 is fine.** That step is interactive; the agents-don't-close-issues convention only constrains the autonomous AFK loop.
- **No Docker sandbox in v1.** Tool-allowlist via `claude -p --allowed-tools` with constrained `Bash(<bin> *)` globs.
- **No `--dangerously-skip-permissions`.** Pocock's article uses it; we don't.
- **Sentinel = `<promise>COMPLETE</promise>`.** Pocock-exact, XML-tagged.
- **Per-iteration commit, never push.** Phase 6 is the merge gate.
- **`.tachikoma/` gitignored, lives inside the worktree.** Per-worktree state. Removed when the worktree is removed.
- **Iteration cap heuristic.** 1–3 PRD items → 5, 4–9 → 15, 10+ → 30. Hard ceiling 50.
- **Notification = `osascript` banner + `\a` bell.** No external services. Notification body includes worktree branch, so multiple concurrent tachikomas are distinguishable.
- **Tachikoma-specific grill, not generic `grill-me`.** Targets fields Tachikoma needs (files in/out of scope, stop condition, quality bar).

## Phases of one `/tachikoma`

1. **Preconditions** — git repo, ≥1 commit, `claude` on PATH, `git worktree` available, cwd not an active tachikoma worktree, no name collisions for the new worktree/branch, `gh` auth (remote mode).
2. **Grill** — goal, quality bar, files in/out of scope, stop condition, mode, cap.
3. **Auto-detect feedback loops** — from `package.json`/`Makefile`/`justfile`/`AGENTS.md`. Confirm.
4. **PRD synthesis** — local: write `<wt>/plans/prd.json`. Remote: `to-prd` → `to-issues` → agent brief → label.
5. **Worktree + scaffold** — `git -C <main-repo> worktree add <wt> -b tachikoma/<slug> <base-branch>`; render `<wt>/.tachikoma/tachikoma.sh`, `<wt>/.tachikoma/prompt.md`, `<wt>/.tachikoma/base_branch`. Commit scaffolding inside the worktree. Print worktree path.
6. **Prompt review** — show full rendered prompt; require approval.
7. **Launch** — `cd <wt> && .tachikoma/tachikoma.sh --once` (foreground) or `cd <wt> && nohup .tachikoma/tachikoma.sh --afk N > .tachikoma/run.log 2>&1 & disown`.

## Common breakages

- **"already running" refusal in a worktree** — stale lockfile in that specific worktree. `cat <wt>/.tachikoma/run.pid; kill <pid>; rm <wt>/.tachikoma/run.pid`.
- **Worktree path collision** — Phase 3 refuses if `<wt-path>` already exists. Run `git -C <main-repo> worktree remove <wt-path>` (or `--force` if files linger), then re-run `/tachikoma`.
- **Branch collision** — Phase 3 refuses if `tachikoma/<slug>` exists. `git -C <main-repo> branch -D tachikoma/<slug>` or finish/abandon the existing run.
- **`git worktree remove` fails on cleanup** — untracked files in the worktree (`.tachikoma/run.log`, etc.). Phase 6 retries with `--force`.
- **Phase 6 refuses: base-worktree dirty** — the worktree currently holding `<base-branch>` (usually main repo) has uncommitted edits. Commit/stash/discard there, then re-run `/tachikoma done`.
- **Allowlist too narrow / too wide** — orchestrator missed (or oversaturated) a `Bash(<bin> *)` glob. Edit `<wt>/.tachikoma/tachikoma.sh`, re-run.
- **`gh pr create` fails after run** — repo has no remote. Merge locally or add a remote.
- **Squash-merge → `git branch -d` refuses** — Phase 6 uses `-D`. Squash isn't fast-forward.
- **Auth expires mid-AFK** — iteration errors out, loop exits, notification fires `outcome=error`. Phase R routes to recovery.
- **Working tree dirty inside a worktree at iteration start** — bash loop bails. Manual cleanup inside that worktree, then `/tachikoma resume <slug>`.
- **Refuses to start because cwd is an active tachikoma worktree** — cd to main repo or a non-tachikoma worktree first.
- **Long-lived Claude Code session uses stale SKILL.md** — open a fresh Claude session in the repo. Bash loop and rendered prompt are unaffected (already on disk).
- **`.tachikoma/base_branch` missing** — Phase 6 falls back to asking which branch to merge into. Happens for worktrees scaffolded by an old version of this skill.
- **Queue drain: item cap hit** — queue drain auto-retries once at half the cap. Second cap = failure, appends `## Queue Failures` to the work-request file, bumps `failure_count`. Two failures → `needs-triage`.
- **Queue drain: merge conflict in Phase 6** — aborts merge, pushes branch as a draft PR, logs failure, moves to next item. Work-request gets a `## Queue Failures` entry with the conflicting files.
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
