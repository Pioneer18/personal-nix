# Ralph

Pocock's "Ralph Wiggum" autonomous AI coding loop, adapted to this machine, the RelyMD toolchain, and the existing `to-prd` / `to-issues` / `triage` skill chain.

## TL;DR

`/ralph` grills you for a goal, generates a PRD (local JSON or GitHub issues), branches off HEAD into `ralph/<slug>`, launches a capped bash loop that calls `claude -p` per iteration until the backlog drains or the cap is hit. Loop runs out-of-process — survives the parent Claude Code session ending.

## Invocation

| Form | Behavior |
|---|---|
| `/ralph <goal>` | Plan + run, **local mode**. PRD in `plans/prd.json`, deleted on completion. |
| `/ralph --remote <goal>` | Plan + run, **remote-greenfield mode**. PRD via `to-prd` → `to-issues` → auto-promoted to `ready-for-agent`. |
| `/ralph --issue <ref>` | Plan + run, **existing-issue mode**. Uses GitHub issue body as the PRD; loop scoped to that one issue. `<ref>` accepts `#138`, `138`, or `org/repo#138`. |
| `/ralph done` | Phase 6 — interactive post-completion review (squash-merge, branch cleanup, optional PR, optional issue close). Auto-triggered when `/ralph` (no args) is run in a repo with a finished loop. |
| `/ralph resume` | Phase R — re-launch an interrupted loop, picking up at the next unfinished task. Auto-offered when `/ralph` (no args) is run in a repo with partial state. |
| `/ralph stop` | SIGTERM running loop in cwd via `.ralph/run.pid`. |

## File layout

```
~/projects/personal-nix/skills/ralph/        ← source (this dir)
├── README.md                                 this file (human orientation)
├── SKILL.md                                  orchestrator instructions (~270 lines)
├── ralph.sh.tmpl                             bash loop template
├── prompt.md.tmpl                            per-iteration prompt template
└── AGENT-BRIEF.tmpl                          remote-mode comment template

~/.claude/skills/ralph                       ← symlink (created by `dev`)
```

Per-run, scaffolded into the target repo:

```
<repo>/.ralph/                                ← runtime state, all gitignored
├── ralph.sh                                  rendered loop
├── prompt.md                                 rendered per-iteration prompt
├── progress.txt                              append-only epistemic log
├── run.pid                                   lockfile
└── run.log                                   AFK stdout/stderr

<repo>/plans/prd.json                         ← local mode only; committed per iter, deleted at completion
```

## Locked-in design decisions

Reasoning so future-you doesn't relitigate.

- **Three modes, flagged at invocation.** Local (default) for prototype work, `--remote` for greenfield backlogs (creates the PRD on the tracker), `--issue <ref>` for existing GitHub issues (uses the issue body as PRD, loop scoped to one issue). Same loop logic; only the task-source query and completion check differ.
- **Phase 6 auto-runs at sentinel.** Bash loop writes `.ralph/outcome=complete` on success. `--once` mode immediately enters Phase 6 (squash-merge → branch cleanup → optional PR → optional issue close → state cleanup, asking at each step). For `--afk` mode, the next `/ralph` invocation detects `outcome=complete` and routes to Phase 6 instead of starting a new run. Eliminates the "now run these 5 git commands manually" friction.
- **Phase R recovers interrupted runs.** State is fully resumable: `progress.txt` records what's been done, `prd.json` flags `passes: true` per task, the rendered ralph.sh and prompt.md persist. After an interruption (kill, /ralph stop, cap-hit), running `/ralph` again detects partial state and offers Resume / Review / Restart. Resume picks up at the next unfinished task. Hard refusal only on a dirty working tree (which signals a mid-iteration crash).
- **Human-approved issue close in Phase 6 doesn't violate the agents-don't-close-issues convention.** That convention applies to the autonomous AFK loop. Phase 6 is interactive — every step requires your approval — so closing there is just executing your intent.
- **Always branch to `ralph/<slug>`.** Branches off whatever HEAD is. Never commits to `main`/`master`/etc. Loop also defense-in-depth checks.
- **No Docker sandbox in v1.** Tool-allowlist via `claude -p --allowed-tools` with constrained `Bash(<bin> *)` globs. Blocks realistic accidents. Layer Docker only if multi-hour overnight loops become routine.
- **No `--dangerously-skip-permissions`.** Pocock's article uses it; we don't.
- **Sentinel = `<promise>COMPLETE</promise>`.** Pocock-exact, XML-tagged.
- **Per-iteration commit, never push.** Human reviews + squash-merges manually.
- **`.ralph/` and `progress.txt` gitignored.** Code commits = durable trail. PRD committed per iter only in local mode (gives iteration-to-iteration diffs).
- **Iteration cap heuristic.** 1–3 PRD items → 5, 4–9 → 15, 10+ → 30. Hard ceiling 50.
- **Notification = `osascript` banner + `\a` bell.** No external services.
- **Ralph-specific grill, not the generic `grill-me`.** Targets fields Ralph needs (files in/out of scope, stop condition, quality bar) — Pocock's tip #3, vague intake → Ralph cuts corners.

## Phases of one `/ralph`

1. **Preconditions** — git repo, clean tree, `claude` on PATH, no stale `.ralph/` state, `gh` auth (remote mode only).
2. **Grill** — goal, quality bar, files in/out of scope, stop condition, mode (`--once`/`--afk`), cap.
3. **Auto-detect feedback loops** — from `package.json`/`Makefile`/`justfile`/`AGENTS.md`. Confirm with user.
4. **PRD synthesis** — local: write `plans/prd.json`. Remote: `to-prd` → `to-issues` → auto-render agent brief → label `ready-for-agent`.
5. **Branch + scaffold** — `git checkout -b ralph/<slug>`; render `.ralph/ralph.sh` and `.ralph/prompt.md`.
6. **Prompt review** — show full rendered prompt; require explicit approval.
7. **Launch** — `--once` foreground or `--afk N` via `nohup ... & disown`.

## Common breakages

- **"already running" refusal** — stale lockfile. `cat .ralph/run.pid; kill <pid>; rm .ralph/run.pid`.
- **Allowlist too narrow → iter 1 fails** — orchestrator missed a `Bash(<bin> *)` glob. Edit `.ralph/ralph.sh` to add it, re-run.
- **Allowlist too wide (e.g. unqualified `Bash`)** — orchestrator ignored SKILL.md's anti-pattern guidance. Re-run, or hand-edit `.ralph/ralph.sh`.
- **`gh pr create` fails after run** — repo has no remote. Expected for scratch dirs; merge locally or add a remote.
- **Squash-merge → `git branch -d` refuses** — use `-D`. Squash isn't fast-forward, git sees branch as unmerged.
- **Auth expires mid-AFK** — iterations error out, loop exits, notification fires `outcome=error`. Re-auth, re-run.
- **Working tree dirty at iteration start** — bash loop bails. Manual cleanup (`git status; git stash`/commit), then re-run.

## Hacking on ralph itself

Symlink points at live working tree — edits to `~/projects/personal-nix/skills/ralph/*` take effect immediately. `dev` rebuild is only needed when adding a *new* skill directory under `personal-nix/skills/`.

## Open issues / known gaps

- **No token/cost cap.** Iteration count is the only budget knob. AFK runs on huge PRDs can spend a lot.
- **No resume from crash.** If the loop dies mid-iteration with a dirty tree, you fix manually before re-running.
- **No concurrent-human protection.** Lockfile only prevents two `ralph` loops in the same repo, not a human editing files while ralph runs.
- **Feedback-loop timeout unset.** A pathological test command can hang the iteration; user kills the loop manually.

## References

- Matt Pocock, ["11 Tips For AI Coding With Ralph Wiggum"](https://www.aihero.dev/tips-for-ai-coding-with-ralph-wiggum) (aihero.dev)
- Jeffrey Huntley, original Ralph Wiggum SOP
- Anthropic, ["Effective Harnesses"](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) (long-running agent design research)
