# Tachikoma User Guide

Tachikoma is an autonomous AI coding loop. You describe a goal; it picks tasks, writes code, runs your feedback loops, commits, and repeats — in its own isolated git worktree — until the backlog is done or it hits a cap. You merge what it builds.

---

## Prerequisites

- Inside a git repo with at least one commit
- `claude` CLI on PATH
- Git ≥ 2.5 (for `git worktree`)
- For GitHub modes: `gh` CLI, authenticated (`gh auth status`)
- Label vocab set up on target repo (run `/setup-matt-pocock-skills` once per repo if not done)

---

## Starting a run

### New local task

```
/tachikoma
```

Runs a ~7-question grill (goal, quality bar, files in/out of scope, stop condition, feedback loops, mode, cap). Nothing is created until you approve. Good for work that doesn't need a GitHub issue.

### From a GitHub issue

```
/tachikoma --issue 138
/tachikoma 138          # shorthand
/tachikoma #138         # also fine
```

Skips the mode grill. Uses the issue body as the PRD. Fetches it, posts an agent brief comment, auto-creates a local work_request linked to the issue. Applies the label lifecycle (see below).

### Publish to GitHub first (remote greenfield)

```
/tachikoma --remote
```

Takes your goal through `to-prd` → `to-issues`, publishes child issues labeled `ready-for-agent`, then runs the loop against them. Use this when you want a paper trail on GitHub before coding starts.

### No args — smart routing

```
/tachikoma
```

With no args, Tachikoma first checks existing worktrees in this repo:
- One **completed** worktree → goes straight to Phase 6 (merge flow)
- One **interrupted** worktree → offers Resume / Review / Restart
- Multiple terminal worktrees → picker to choose which to act on
- Only **running** worktrees → tells you to use `/tachikoma status` or `/tachikoma stop`

---

## The grill

When starting a new run, Tachikoma grills you for ~7 fields. It leads with a concrete recommendation for each so you can often just hit enter. Key fields:

| Field | What it needs |
|---|---|
| **Goal** | One-sentence end-state: "Tachikoma is done when…" |
| **Quality bar** | `prototype` (fast+rough), `production` (tests required), `library` (API stability matters) |
| **Files in scope** | Globs Tachikoma may modify — be explicit or it'll redefine "done" |
| **Files out of scope** | Globs it must not touch |
| **Stop condition** | Concrete, testable acceptance criteria |
| **Mode** | `once` (foreground, good for quick tasks) or `afk N` (backgrounded, capped at N iterations) |
| **Feedback loops** | Auto-detected from `package.json` / `Makefile` — confirm or edit |

---

## During a run

### `--once` (foreground)

Output streams directly to your terminal. When it finishes, you're immediately in the merge flow (Phase 6). Good for tasks you want to watch.

### `--afk N` (backgrounded)

Launches detached via `nohup`/`disown`. Survives the session ending. Fires a macOS notification when done. A worktree path and tail command are printed after launch:

```
Worktree: ~/Projects/platform-tachikoma-issue-138-fix-vital-age/
Branch:   tachikoma/issue-138-fix-vital-age  (off main)
Tail:     tail -f .../tachikoma/run.log
```

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

Sends SIGTERM. The loop finishes its current iteration cleanly, writes `outcome=stopped`, exits.

---

## Reviewing and merging (Phase 6)

Triggered automatically after `--once` completes, or manually with:

```
/tachikoma done           # if one completed loop exists
/tachikoma done <slug>    # specific one
```

Phase 6 walks you through:

1. **Show diff stat** — `git log` + `git diff --stat` for what changed
2. **Squash-merge** into your base branch (refuses if the base worktree is dirty — commit/stash there first)
3. **Cleanup** — delete the worktree and branch in one prompt
4. **PR** — push and open a PR if there's a remote
5. **Close issue** — for issue-linked runs, with a smart default (no if GitHub will auto-close via `Closes #N`)
6. **Label transition** — `ready-for-review` applied, `agent-running` removed (issue-linked runs only)
7. **Work-request cleanup** — auto-deletes the linked work_request file if one exists

Phase 6 is idempotent — bailing out mid-way and re-entering with `/tachikoma done` picks up where you left off.

---

## Recovering an interrupted run

```
/tachikoma resume         # if one interrupted loop exists
/tachikoma resume <slug>  # specific one
```

Shows what happened (last progress note, log tail, completed tasks). Offers:

| Option | What it does |
|---|---|
| **Resume** | Re-launch the loop; picks up from the last completed task |
| **Review** | Treat what's committed as "done enough" — goes to Phase 6 |
| **Restart** | Delete the worktree and branch; back to a fresh grill |

---

## Work-request queue

The queue is a folder of markdown files (`~/projects/personal-nix/wiki/work-requests/`). Each file is a structured task with frontmatter (`status`, `target_repo`, `github_issue`, `failure_count`).

### Drain the queue

```
/tachikoma queue          # runs all open+ready items, one at a time
/tachikoma queue <slug>   # run one specific item
/tachikoma queue --caffeinated   # same, but prevents macOS sleep (good for overnight runs)
```

Batch preferences (quality bar, iteration cap, auto-PR, auto-clean) are asked once up front. Each item gets its own worktree, branch, and PR. Failures are logged and skipped — the queue keeps moving.

### Managing the queue

```
/work-queue add           # grill for a new work item → writes the file
/work-queue list          # show all items grouped by status
/work-queue grab <slug>   # mark grabbed + print seed block for /tachikoma
/work-queue done <slug>   # delete the file (tachikoma queue does this automatically)
```

Items with `failure_count ≥ 2` are quarantined as `needs-triage` — they're excluded from future drains until you manually reset them.

---

## GitHub-sourced queue drain

```
/tachikoma queue MioMarker/healthbite
```

Instead of draining local work-request files, fetches open issues labeled `ready-for-agent AND NOT agent-running` from the repo. For each:
- Auto-creates a linked local work_request if none exists
- Runs the full queue drain lifecycle (Phases 1–6)

After the drain completes, checks remaining open issues and fires a macOS notification if any need human attention, plus a terminal summary:

```
⏸ Queue drained — 3 issues need human attention (MioMarker/healthbite)

  #14  Add onboarding screen        needs-triage    → triage and label
  #19  Redesign settings UI         ready-for-human → implement manually
  #23  Clarify acceptance criteria  needs-info      → respond to reporter
```

---

## GitHub label lifecycle

For any run linked to a GitHub issue:

```
ready-for-agent
    ↓ Phase 2.5 (before worktree scaffolding)
agent-running          ← distributed claim signal; concurrent agents skip this issue
    ↓ Phase 6 (after merge/PR)
ready-for-review       ← whether or not a PR was opened

On failure:
  failure_count < 2  → ready-for-agent  (back in the pool)
  failure_count ≥ 2  → needs-triage     (quarantined; human resets)

On deliberate stop (/tachikoma stop):
  → ready-for-agent  (no failure_count bump — intentional stop isn't a failure)
```

The claim is verified after applying `agent-running` — if another Tachikoma claimed it first, this run skips or exits rather than double-working the issue.

---

## Multiple concurrent runs

Each `/tachikoma` run gets its own sibling worktree, so you can run several in parallel on the same codebase:

```
~/Projects/platform/                              ← your main repo (can be dirty)
~/Projects/platform-tachikoma-issue-138-fix.../  ← running
~/Projects/platform-tachikoma-issue-140-add.../  ← running
~/Projects/platform-tachikoma-issue-142.../      ← done, awaiting /tachikoma done
```

`/tachikoma status` shows all of them. `/tachikoma done` picks which to merge (picker if multiple complete).

---

## Common gotchas

| Problem | Fix |
|---|---|
| "cwd is an active tachikoma worktree" | `cd` to the main repo or a non-tachikoma worktree first |
| "worktree path already exists" | `git worktree remove <path>` (or `--force` if files linger) |
| "branch already exists" | `git branch -D tachikoma/<slug>` or finish the existing run |
| Phase 6 refuses: "base-worktree dirty" | Commit/stash in the base branch worktree, then retry |
| `agent-running` stuck after crash | `gh issue edit <N> --repo <org/repo> --remove-label "agent-running" --add-label "ready-for-agent"` |
| Loop caps out repeatedly | Lower the scope — the goal is too large for one tachikoma; split into multiple issues |
| macOS sleeps mid-queue drain | Use `--caffeinated` / `-C` |
