# Tachikoma User Guide

Tachikoma is an autonomous AI coding loop. You type `/tachikoma --issue 138`; it reads your config, fetches the issue, writes code, commits, squash-merges, and opens a PR — all without asking anything. You review the PR on GitHub.

---

## Prerequisites

- Inside a git repo with at least one commit
- `claude` CLI on PATH
- Git ≥ 2.5 (for `git worktree`)
- For GitHub modes: `gh` CLI, authenticated (`gh auth status`)
- `~/.claude/tachikoma.conf` (create once — see below)

---

## One-time setup: `~/.claude/tachikoma.conf`

Create this file once. All runs inherit from it silently.

```
quality_bar = production
iteration_cap = 15
iteration_mode = afk
allowed_tools = Edit Write Read Glob Grep Bash(git *) Bash(gh *) Bash(pnpm *) Bash(npm *) Bash(npx *) Bash(node *) Bash(make *) Bash(rg *) Bash(find *) Bash(cat *) Bash(echo *) Bash(ls *) Bash(mkdir *) Bash(cp *) Bash(mv *) Bash(rm *) Bash(touch *)
```

| Key | What it controls |
|---|---|
| `quality_bar` | `prototype`, `production`, or `library` |
| `iteration_cap` | Max iterations for AFK runs (hard ceiling: 50) |
| `iteration_mode` | `afk` (backgrounded) or `once` (foreground) |
| `allowed_tools` | Tools the loop agent is allowed to use |

Issue bodies can override `quality_bar` and file scope — add `## Files in Scope` / `## Acceptance Criteria` sections to your issues and tachikoma will pick them up.

---

## Starting a run

### From a GitHub issue (most common)

```
/tachikoma --issue 138
/tachikoma 138          # shorthand
/tachikoma #138         # also fine
```

Tachikoma reads the issue body for goal, stop condition, and scope, fills the rest from your config, prints a one-line launch summary, and immediately starts working. No questions.

### New local task

```
/tachikoma
```

Synthesizes a `plans/prd.json` from the conversation context. Still reads config for quality bar, cap, and tools.

### Publish to GitHub first (remote greenfield)

```
/tachikoma --remote
```

Takes your goal through `to-prd` → `to-issues`, publishes child issues labeled `ready-for-agent`, then runs the loop against them.

### No args — smart routing

```
/tachikoma
```

With no args, checks existing worktrees in this repo first:
- One **completed** worktree → Phase 6 (runs automatically)
- One **interrupted** worktree → Phase R (auto-retries once, then draft PR)
- Multiple terminal worktrees → picker to choose which to act on
- Only **running** worktrees → tells you to use `/tachikoma status` or `/tachikoma stop`

---

## What tachikoma infers automatically

Before launching, tachikoma silently resolves these fields — nothing is asked:

| Field | Source (priority order) |
|---|---|
| Goal | Issue title / body → conversation context |
| Stop condition | `## Acceptance Criteria` in issue body → derived from title |
| Quality bar | Issue body keyword → `~/.claude/tachikoma.conf` → `production` |
| Files in scope | `## Files in Scope` in issue body → `**` (whole repo) |
| Files out of scope | `## Files out of Scope` in issue body → none |
| Feedback loops | `package.json` scripts → `Makefile` → `AGENTS.md`/`CLAUDE.md` → `echo "skipped"` |
| PR target branch | `develop` → `dev` → repo default |
| Allowed tools | `~/.claude/tachikoma.conf` → built-in broad default |

All resolved values are logged in the PR body so you have full visibility.

---

## During a run

### `--once` (foreground)

Output streams to your terminal. On completion, Phase 6 runs automatically (squash-merge, cleanup, PR, issue close). No prompts.

### `--afk N` (backgrounded)

Launches detached via `nohup`/`disown`. Survives the session ending. Fires a macOS notification when done. A worktree path and tail command are printed after launch:

```
Worktree: ~/Projects/platform-tachikoma-issue-138-fix-vital-age/
Branch:   tachikoma/issue-138-fix-vital-age  (off feat/issue-138-fix-vital-age)
Tail:     tail -f .../tachikoma/run.log
```

When the notification fires, type `/tachikoma` — Phase 6 runs automatically.

---

## Checking on a run

```
/tachikoma status         # compact table of all loops in this repo
/tachikoma t              # alias
/tachikoma status <slug>  # drill into one loop — iter progress, last milestone, log tail
```

### Stopping

```
/tachikoma stop           # stops the one running loop (or picker if multiple)
/tachikoma stop <slug>    # stop a specific one
/tachikoma stop --all     # stop everything
```

Sends SIGTERM. The loop finishes its current iteration cleanly, writes `outcome=stopped`, and Phase 6 runs on whatever was committed.

---

## Phase 6: fully automatic

After the loop finishes, Phase 6 runs with no prompts:

1. **Squash-merge** into the issue branch (only stops if there's a merge conflict)
2. **Delete worktree + branch** automatically
3. **Push + open PR** against `develop`/`dev`/default — PR body includes a full run log (config used, feedback loops detected, iterations completed)
4. **Apply `ready-for-review` label**, remove `agent-running` (issue-linked runs)
5. **Close issue** if needed (skipped if GitHub will auto-close via `Closes #N` on PR merge)
6. **Work-request cleanup** — auto-deletes the linked work_request if one exists

Your only action: review the PR on GitHub.

---

## Error handling

- **Loop crashes or errors**: auto-retry once. If it fails again: push a draft PR with the failure log in the body, fire a macOS notification.
- **Iteration cap hit**: auto-retry once at half the cap. If it caps again: same draft PR path.
- **Deliberate Ctrl+C** (`/tachikoma stop`): Phase 6 runs on whatever was committed.
- **Merge conflict**: the only case that requires human intervention. Tachikoma opens a draft PR with conflicting files listed and surfaces the error.

---

## Work-request queue

The queue is a folder of markdown files (`~/projects/personal-nix/wiki/work-requests/`). Each file is a structured task with frontmatter (`status`, `target_repo`, `github_issue`, `failure_count`).

### Drain the queue

```
/tachikoma queue          # runs all open+ready items, one at a time
/tachikoma queue <slug>   # run one specific item
/tachikoma queue --caffeinated   # same, but prevents macOS sleep (good for overnight runs)
```

Each item gets its own worktree, branch, and PR. Failures are logged and skipped — the queue keeps moving.

### Managing the queue

```
/work-queue add           # create a new work item
/work-queue list          # show all items grouped by status
/work-queue done <slug>   # delete the file (tachikoma queue does this automatically)
```

Items with `failure_count ≥ 2` are quarantined as `needs-triage` — excluded from future drains until manually reset.

---

## GitHub-sourced queue drain

```
/tachikoma queue MioMarker/healthbite
```

Fetches open issues labeled `ready-for-agent AND NOT agent-running` from the repo. For each:
- Auto-creates a linked local work_request if none exists
- Runs the full queue drain lifecycle (Phases 1–6)

After the drain, fires a macOS notification if any issues need human attention.

---

## GitHub label lifecycle

For any run linked to a GitHub issue:

```
ready-for-agent
    ↓ Phase 2.5 (before worktree scaffolding)
agent-running          ← distributed claim signal; concurrent agents skip this issue
    ↓ Phase 6 (automatic, after merge/PR)
ready-for-review

On failure:
  failure_count < 2  → ready-for-agent  (back in the pool)
  failure_count ≥ 2  → needs-triage     (quarantined; human resets)

On deliberate stop (/tachikoma stop):
  → ready-for-agent  (no failure_count bump)
```

---

## Multiple concurrent runs

Each `/tachikoma` run gets its own sibling worktree:

```
~/Projects/platform/                              ← your main repo (can be dirty)
~/Projects/platform-tachikoma-issue-138-fix.../  ← running
~/Projects/platform-tachikoma-issue-140-add.../  ← running
~/Projects/platform-tachikoma-issue-142.../      ← done (Phase 6 auto-ran, PR opened)
```

`/tachikoma status` shows all of them.

---

## Common gotchas

| Problem | Fix |
|---|---|
| "cwd is an active tachikoma worktree" | `cd` to the main repo or a non-tachikoma worktree first |
| "worktree path already exists" | `git worktree remove <path>` (or `--force` if files linger) |
| "branch already exists" | `git branch -D tachikoma/<slug>` or finish the existing run |
| Phase 6 refuses: "base-worktree dirty" | Commit/stash in the base branch worktree, then `/tachikoma done` |
| `agent-running` stuck after crash | `gh issue edit <N> --repo <org/repo> --remove-label "agent-running" --add-label "ready-for-agent"` |
| Loop caps out repeatedly | Goal is too large — split into multiple issues |
| macOS sleeps mid-queue drain | Use `--caffeinated` / `-C` |
| Draft PR instead of real PR | Loop hit an error twice — check the PR body for the failure log |
