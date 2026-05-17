# Tachikoma User Guide

Tachikoma is an autonomous AI coding loop. You type `/tachikoma 138`; it reads your config, fetches the issue, writes code, commits, squash-merges, opens a PR — and auto-closes the issue. You review the PR on GitHub.

This guide covers day-to-day use. For the authoritative spec of every phase and edge case, see `SKILL.md` in this directory.

---

## Prerequisites

- Inside a git repo with at least one commit
- `claude` CLI on PATH
- Git ≥ 2.5 (for `git worktree`)
- For GitHub modes (`--issue`, `--remote`, `queue <repo>`): `gh` CLI, authenticated (`gh auth status`)
- `~/.claude/tachikoma.conf` (auto-created on your first run — see next section)

---

## First run: onboarding writes `~/.claude/tachikoma.conf`

The first time you invoke `/tachikoma` on a machine that has no `~/.claude/tachikoma.conf`, the **preflight** phase runs a short onboarding flow (takes about a minute). It asks three questions and saves your answers to `~/.claude/tachikoma.conf`. Every run after that reads this file silently — no questions.

The three onboarding questions:

| # | Question | Default | Notes |
|---|---|---|---|
| 1 | Quality bar | `production` | `prototype` / `production` / `library` |
| 2 | Run mode | `afk` | `afk` (background, capped, fires notification) or `once` (foreground, single iteration) |
| 3 | Iteration cap | `15` | 1–50. Only asked when run mode is `afk`. |

Resulting file:

```
quality_bar = production
iteration_mode = afk
iteration_cap = 15
```

You can edit `~/.claude/tachikoma.conf` any time. The keys it understands:

| Key | What it controls | Default |
|---|---|---|
| `quality_bar` | Standard for generated code (`prototype` / `production` / `library`) | `production` |
| `iteration_mode` | `afk` (backgrounded, capped) or `once` (foreground, one iteration) | `afk` |
| `iteration_cap` | Max iterations for AFK runs (hard ceiling: 50) | `15` |
| `allowed_tools` | Space-separated tokens for `claude -p --allowed-tools`. Missing = a broad built-in default. | see SKILL.md |

Per-issue overrides: issue bodies can override `quality_bar` and the file-scope settings — add `## Files in Scope`, `## Files out of Scope`, or `## Acceptance Criteria` sections to your issues and Tachikoma will pick them up.

After onboarding, every subsequent `/tachikoma` invocation goes straight from the launch summary into work. No grill.

---

## Phases at a glance

Every run flows through the same named phases. You will see these names in logs, banners, and error messages — get familiar with them:

| Phase | What happens |
|---|---|
| **preflight** | Read `~/.claude/tachikoma.conf`. Detect feedback loops. Resolve goal, scope, stop condition. Print launch summary. |
| **scaffold** | Create the sibling worktree and the `tachikoma/<slug>` branch. Render `tachikoma.sh`, `prompt.md`, and `ship.md` from templates. |
| **launch** | Kick off the loop — `--once` (foreground) or `--afk N` (backgrounded via `nohup ... & disown`). |
| **ship** | Squash-merge the tachikoma branch into the issue branch, push, open the PR, update issue labels. Fully automatic. |
| **recover** | Re-launch an interrupted loop (crashed, capped, or stopped). Auto-retries once, then opens a draft PR if it still fails. |

The old "Phase 1 / Phase 6 / Phase R" numbering is gone. Use the names above.

---

## Starting a run

### Invocation table

| Form | What it does |
|---|---|
| `/tachikoma --issue 138` | Fast-path: use GitHub issue #138 as the spec. Scoped to that one issue. |
| `/tachikoma 138` | Shorthand for `--issue 138`. |
| `/tachikoma #138` | Same shorthand. `org/repo#138` also works (must match cwd repo). |
| `/tachikoma --remote` | Fast-path: take your goal through `to-prd` → `to-issues`, publish `ready-for-agent` issues, then loop against them. |
| `/tachikoma` | Always starts a new task. Asks two mode-selection questions in preflight (existing issue? if not, local-or-remote?), then runs the appropriate flow. Existing worktrees are not affected. |
| `/tachikoma done` | Manually trigger the **ship** phase on a completed worktree. Use this only when auto-ship failed. |
| `/tachikoma done <slug>` | Ship a specific completed worktree. |
| `/tachikoma resume` | Re-launch an interrupted loop (the **recover** phase). |
| `/tachikoma resume <slug>` | Resume a specific interrupted worktree. |
| `/tachikoma status` (alias `/tachikoma t`) | Read-only telemetry across every Tachikoma worktree in the repo. |
| `/tachikoma status <slug>` | Drill into one specific loop. |
| `/tachikoma stop` | SIGTERM the running loop. Picker if multiple. |
| `/tachikoma stop <slug>` / `--all` | Stop a specific loop, or every loop in the repo. |
| `/tachikoma queue` | Single worker, auto-grabs the next ready slice via `proxy queue grab` (respecting Epic order, intra-Epic position, `blocked_by`, `paused`). Empty queue exits cleanly with a hint to add work. |
| `/tachikoma queue <N>` | **Parallel drain — N background workers** sharing the same queue. Each worker independently auto-grabs the next ready slice. Use for overnight runs (e.g. `queue 3`). N must be ≥ 2. |
| `/tachikoma queue <slug>` | **Manual override** — bypass auto-grab and run that specific item. Useful for re-running a `needs-triage` slice or hand-picking out of Epic order. |
| `/tachikoma queue --caffeinated` (alias `-C`) | Same drain, but wrap each launch in `caffeinate -d` to prevent macOS sleep. Combinable with `<N>`. |
| `/tachikoma queue <org/repo>` | Drain a GitHub-sourced queue (`ready-for-agent AND NOT agent-running` issues from `<repo>`). Combinable with `<N>` (e.g. `queue MioMarker/healthbite 3`). |
| `/tachikoma queue add` | Create a new work-request (guided interview). |
| `/tachikoma queue add <target-repo>` | Same, skip the repo question. |
| `/tachikoma queue list` | Show all work-requests in the queue. |
| `/tachikoma queue stop` | Stop the running drain after the current item finishes. With multiple workers: `queue stop <worker-id>` or `queue stop --all`. |
| `/tachikoma sitrep` | Show status of all running queue-drain workers. Read-only. |

### From a GitHub issue (most common)

```
/tachikoma --issue 138
/tachikoma 138          # shorthand
/tachikoma #138         # also fine
```

Tachikoma reads the issue body for goal, stop condition, and scope, fills the rest from your config, prints a one-line launch summary, and immediately starts working.

### New local task

```
/tachikoma
```

Asks two short mode-selection questions in preflight (is this for an existing issue? if not, local-or-remote?), then synthesizes a `plans/prd.json` from the conversation context and launches. Still reads `~/.claude/tachikoma.conf` for quality bar, cap, and tools.

### Publish to GitHub first (remote greenfield)

```
/tachikoma --remote
```

Takes your goal through `to-prd` → `to-issues`, publishes child issues labeled `ready-for-agent`, then runs the loop against them.

### `/tachikoma` always starts a new task

Bare `/tachikoma` always starts a brand-new run. It asks two mode-selection questions (existing issue? if not, local-or-remote?) and then goes straight into plan → scaffold → launch.

Existing completed or interrupted worktrees in the repo are not a blocker — use `/tachikoma done` or `/tachikoma resume` to act on those.

---

## What Tachikoma infers automatically

Before launching, the preflight phase resolves these silently — nothing is asked beyond first-run onboarding:

| Field | Source (priority order) |
|---|---|
| Goal | Issue title / body → conversation context |
| Stop condition | `## Acceptance Criteria` in issue body → derived from title |
| Quality bar | Issue body keyword → `~/.claude/tachikoma.conf` → `production` |
| Files in scope | `## Files in Scope` in issue body → `**` (whole repo) |
| Files out of scope | `## Files out of Scope` in issue body → none |
| Feedback loops | `package.json` scripts → `Makefile` → `justfile` → `AGENTS.md` / `CLAUDE.md` → `echo "skipped"` |
| PR target branch | `develop` → `dev` → repo default |
| Allowed tools | `~/.claude/tachikoma.conf` → built-in broad default |

All resolved values are logged in the PR body so you have full visibility.

---

## During a run

### `--once` (foreground)

The loop runs in the foreground. By default it runs in **light mode**: only structured progress banners print to the terminal; all raw claude output goes to `.tachikoma/run.log`. Pass `--dev` for full streaming output:

```bash
# light (default) — progress banners only
cd <WORKTREE_PATH> && .tachikoma/tachikoma.sh --once

# dev mode — full streaming output to terminal
cd <WORKTREE_PATH> && .tachikoma/tachikoma.sh --dev --once
```

When the loop exits with `outcome=complete`, the orchestrator runs the **ship** phase immediately (still in-session). No prompts.

### `--afk N` (backgrounded)

The launch phase backgrounds the loop via `nohup ... & disown` so it survives the session ending. Runs in light mode by default (pass `--dev` if you want full output in the log — though `run.log` already captures everything regardless of mode). Fires a macOS notification when done. You see something like:

```
── Launched  (afk, cap 15)
  Worktree:  ~/Projects/platform-tachikoma-issue-138-fix-vital-age
  PID:       54321  ·  branch tachikoma/issue-138-fix-vital-age
  Tail:      tail -f ~/Projects/platform-tachikoma-issue-138-fix-vital-age/.tachikoma/run.log
  Check in:  /tachikoma status
  Stop:      /tachikoma stop  ·  kill 54321
  Done:      auto-ships on completion  (or /tachikoma done if it fails)
```

**Auto-ship**: when the loop finishes successfully, `tachikoma.sh` runs `claude -p "$(cat .tachikoma/ship.md)"` itself — no human in the loop. The squash-merge happens, the PR opens, the issue closes (or gets `ready-for-review`), the worktree is removed, and you get a macOS notification. Your only action is reviewing the PR on GitHub.

**`/tachikoma done` is the fallback**, not the primary merge trigger. Use it only when auto-ship fails (rare — surfaced as a notification with a failure message). Your work is still committed on the `tachikoma/<slug>` branch, so nothing is lost.

---

## Checking on a run

```
/tachikoma status         # compact table of all loops in this repo
/tachikoma t              # alias for status
/tachikoma status <slug>  # drill into one loop — iter progress, last milestone, log tail
```

`status` is read-only — it never modifies anything.

### Stopping

```
/tachikoma stop           # stops the one running loop (or picker if multiple)
/tachikoma stop <slug>    # stop a specific one
/tachikoma stop --all     # stop everything in this repo
```

Sends SIGTERM. The loop finishes its current iteration cleanly, writes `outcome=stopped`, and the **ship** phase runs on whatever was committed (a deliberate Ctrl+C is treated as complete enough to ship). If SIGTERM doesn't take within 60s, Tachikoma falls back to SIGKILL.

---

## Ship phase: automatic on AFK

After the loop finishes successfully, the ship phase runs with no prompts. Auto-ship is triggered in two ways:

- **`--once` mode**: the orchestrator runs the ship phase immediately after the loop exits, still in-session.
- **`--afk N` mode**: `tachikoma.sh` itself runs `claude -p "$(cat .tachikoma/ship.md)"` after detecting the sentinel and before exiting.

What it does, in order:

1. **Stash** any uncommitted work in the base worktree (auto-restored after merge).
2. **Squash-merge** the `tachikoma/<slug>` branch into the issue branch (the only stop is a real merge conflict).
3. **Delete worktree + tachikoma branch** automatically.
4. **Push + open PR** against `develop` / `dev` / default branch — PR body includes a full run log (config used, feedback loops detected, iterations completed).
5. For issue-linked runs: **apply `ready-for-review`**, remove `agent-running`.
6. **Close the issue** if needed (skipped if GitHub will auto-close via `Closes #N` on PR merge into default branch).
7. **Work-request cleanup** — auto-deletes the linked work_request, or defers to the GitHub Action that cleans it up when the PR merges.

Your only action: review the PR on GitHub.

### Manual ship (`/tachikoma done`) — fallback only

```
/tachikoma done           # picker if multiple complete; auto-pick if one
/tachikoma done <slug>    # ship a specific completed worktree
```

You only need this when auto-ship failed. The notification when AFK exits will tell you so. The work is still on the `tachikoma/<slug>` branch — `/tachikoma done` re-runs the same ship phase against it.

---

## Recover phase: interrupted runs (`/tachikoma resume`)

If the loop crashed, hit the iteration cap, or was deliberately stopped, the worktree state survives. The **recover** phase resumes it:

```
/tachikoma resume         # picker if multiple recoverable; auto-pick if one
/tachikoma resume <slug>  # resume a specific worktree
```

Auto-retry logic:

| Outcome | What happens |
|---|---|
| `error` (crashed) | Auto-retry once. If it errors again: push the branch as a draft PR with the failure log, fire macOS notification. |
| `cap` (hit iteration limit) | Auto-retry once at half the original cap. If it caps again: same draft-PR path. |
| `stopped` (deliberate Ctrl+C) | Skip retry — jump directly to the **ship** phase on whatever was committed. |

`/tachikoma resume` is the explicit entry point for taking manual control of an interrupted worktree. Since bare `/tachikoma` always starts a new run, `/tachikoma resume` is the only way to re-enter an existing interrupted worktree.

---

## Error handling summary

- **Loop crashes** (outcome=`error`): auto-retry once. If it fails again, push a draft PR with the failure log, fire a macOS notification.
- **Iteration cap hit** (outcome=`cap`): auto-retry once at half the cap. If it caps again, same draft-PR path.
- **Deliberate stop** (outcome=`stopped`, via `/tachikoma stop` or Ctrl+C): the ship phase runs on whatever was committed.
- **Merge conflict in ship phase**: the only case that requires human intervention. Tachikoma opens a draft PR with conflicting files listed and surfaces the error.

---

## Work-request queue

The queue is a folder of markdown files (`~/projects/personal-nix/wiki/work-requests/`). Each file is a structured task with frontmatter (`status`, `target_repo`, `github_issue`, `failure_count`).

### Drain the queue

**Mental model: a "drain" is one worker against the shared queue.** It pops the next `open` work-request, runs the full lifecycle on it in its own worktree, then pops the next. Repeats until the queue is empty or you stop it. The queue itself is the folder of markdown files — there's no central process owning it.

You can run **multiple workers in parallel** — they share the queue and partition the work via the atomic `open` → `grabbed` status flip on each file. Same model as a worker pool draining a job queue.

```
/tachikoma queue                  # 1 worker, foreground — auto-grabs the next ready slice
/tachikoma queue 3                # 3 background workers — overnight throughput
/tachikoma queue <slug>           # manual override — run one specific item (bypass auto-grab)
/tachikoma queue --caffeinated    # prevent macOS sleep (good for overnight runs)
/tachikoma queue -C               # alias for --caffeinated
/tachikoma queue 3 -C             # 3 workers + sleep prevention (typical AFK launch)
```

### Auto-grab (no-slug form)

`/tachikoma queue` with no positional argument delegates slice selection to the daemon. The skill shells out to `lib/queue-grab.sh`, which wraps `proxy queue grab` — that returns the next ready slug honoring Epic order, intra-Epic position, `blocked_by` constraints, and `paused` state.

Worked example: an Epic with three open dependency-free slices, run sequentially:

```
$ /tachikoma queue          # → grabs epic-a-1, runs lifecycle, ships PR
$ /tachikoma queue          # → grabs epic-a-2, runs lifecycle, ships PR
$ /tachikoma queue          # → grabs epic-a-3, runs lifecycle, ships PR
$ /tachikoma queue
Nothing to grab. Add an Epic with `proxy queue add-epic` or create work-requests.
```

If `proxy` is not on PATH (bootstrap before the daemon is installed), the skill falls back to a legacy filesystem scan over `~/projects/personal-nix/wiki/work-requests/` and picks the first `status: open` item that passes the readiness check.

Auto-grab only ever surfaces `open` slices — items already in `grabbed`, `done`, or `needs-triage` are skipped by the daemon-side algorithm; the wrapper does not re-filter.

Each item gets its own worktree, branch, and PR — the full preflight → scaffold → launch → ship lifecycle per item. Failures are logged and skipped — the queue keeps moving.

Queue drain runs items with `--once` mode (sequential, foreground) regardless of your `iteration_mode` config. With `queue N` the foreground session collects your batch preferences once, writes them to `~/.claude/tachikoma.conf`, then spawns N detached `claude -p "/tachikoma queue"` workers and exits.

**Sizing N:**
- `queue` (no N) — keep up with reviews in near-real-time.
- `queue 2`–`queue 3` — typical overnight throughput; balances API rate limits with review backlog the next morning.
- `queue 5+` — high risk of hitting Anthropic per-minute caps; do this only if you have a dedicated review session planned and your tier supports it.

Workers compete on a single shared file-based queue. The race window between two workers grabbing the same item is small but non-zero — see the SKILL spec for hardening notes.

### Managing the queue

```
/tachikoma queue add           # create a new work item
/tachikoma queue list          # show all items and their status
/tachikoma queue stop          # abort the drain after the current item finishes
/work-queue done <slug>        # delete a specific file (drain does this automatically on success)
```

Items with `failure_count ≥ 2` are quarantined as `needs-triage` — excluded from future drains until manually reset. To discard a `needs-triage` item: `rm ~/projects/personal-nix/wiki/work-requests/<slug>.md`.

---

## GitHub-sourced queue drain

```
/tachikoma queue MioMarker/healthbite
```

Fetches open issues labeled `ready-for-agent AND NOT agent-running` from the repo. For each:

- Auto-creates a linked local work_request if none exists
- Runs the full per-item lifecycle (preflight → scaffold → launch → ship)

After the drain, fires a macOS notification if any issues need human attention (anything still labeled `needs-triage`, `needs-info`, `ready-for-human`, or `ready-for-review`).

---

## GitHub label lifecycle

For any run linked to a GitHub issue:

```
ready-for-agent
    ↓ before scaffold phase (claim)
agent-running          ← distributed claim signal; concurrent agents skip this issue
    ↓ ship phase (automatic, after merge/PR)
ready-for-review

On failure:
  failure_count < 2  → ready-for-agent  (back in the pool)
  failure_count ≥ 2  → needs-triage     (quarantined; human resets)

On deliberate stop (/tachikoma stop):
  → ready-for-agent  (no failure_count bump)
```

Tachikoma auto-creates any missing labels (`ready-for-agent`, `agent-running`, `ready-for-review`, `needs-triage`) in the target repo the first time it runs there — silently, no prompt.

---

## Multiple concurrent runs

Each `/tachikoma` run gets its own sibling worktree:

```
~/Projects/platform/                              ← your main repo (can be dirty)
~/Projects/platform-tachikoma-issue-138-fix.../  ← running
~/Projects/platform-tachikoma-issue-140-add.../  ← running
~/Projects/platform-tachikoma-issue-142.../      ← done (ship phase auto-ran, PR opened)
```

Multiple loops on the same repo work as long as each is in its own worktree. The per-worktree lockfile (`<wt>/.tachikoma/run.pid`) prevents two loops in the same worktree. Cross-repo concurrency (one Tachikoma on `platform`, another on `personal-nix`) also works.

`/tachikoma status` shows all of them.

---

## Common gotchas

| Problem | Fix |
|---|---|
| "cwd is an active tachikoma worktree" | `cd` to the main repo or a non-tachikoma worktree first |
| "worktree path already exists" | `git worktree remove <path>` (or `--force` if files linger) |
| "branch already exists" | `git branch -D tachikoma/<slug>` or finish the existing run |
| Ship phase refuses: "base-worktree dirty" | Commit/stash in the base branch worktree, then `/tachikoma done` |
| `agent-running` stuck after crash | `gh issue edit <N> --repo <org/repo> --remove-label "agent-running" --add-label "ready-for-agent"` |
| Loop caps out repeatedly | Goal is too large — split into multiple issues |
| macOS sleeps mid-queue drain | Use `/tachikoma queue --caffeinated` (or `-C`) |
| Draft PR instead of real PR | Loop hit `error` or `cap` twice — check the PR body for the failure log |
| Auto-ship failed | Run `/tachikoma done` — the work is still on `tachikoma/<slug>` |
| First run is asking me three questions | That's onboarding writing `~/.claude/tachikoma.conf`. Edit the file later if your answers change. |
