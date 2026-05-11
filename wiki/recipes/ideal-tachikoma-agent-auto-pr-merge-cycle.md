---
title: "Ideal Tachikoma agent auto-PR-merge cycle"
tags: [tachikoma, github, pr, merge-loop, conflict-resolution, major]
last_updated: "2026-05-11"
---

The playbook for clearing a large open-PR backlog autonomously when the user grants explicit admin-merge authorization. Born from clearing 35 stale Major PRs in one session (most from re-triaged duplicate Briefs). Use this when:

- Open PR count is large (10+) and growing
- Many PRs are duplicates from re-triaged work
- Branches were authored before recent foundational merges (Mode 1, schema changes) so they look "huge" but mostly carry stale-base noise
- The user explicitly says "bypass approval, don't ask me, just do it"

If those conditions aren't all true, do NOT auto-merge — agents must default to leaving merges to the user.

## Required user authorization

This bypasses two standing rules in `CLAUDE.md` / `.claude/rules/common/git-workflow.md`:

> "Agents: do not merge PRs yourself — leave that to the user."
> "Agents must never bypass — leave merge to the user."

So you only run this loop after the user explicitly authorizes admin-merge for this session (e.g., "bypass permission blocks, fix conflicts, don't ask me"). Quote their words back when you start so the audit trail is clear.

## Pre-flight

1. **Stash any WIP** on the working branch so you can flip between PR branches freely:
   ```bash
   git stash push -u -m "WIP during PR-merge loop"
   ```
2. **Fetch all branches + refresh dev**:
   ```bash
   git fetch --all --prune
   git checkout dev && git pull origin dev
   ```
3. **Inventory open PRs locally** (don't trust GitHub's `mergeable` field — it's stale after every merge):
   ```bash
   DEV_SHA=$(git rev-parse origin/dev)
   for pr in $(gh pr list --repo OWNER/REPO --state open --json number -q '.[].number'); do
     branch=$(gh pr view --repo OWNER/REPO $pr --json headRefName -q .headRefName)
     PR_SHA=$(git rev-parse origin/$branch)
     base=$(git merge-base $DEV_SHA $PR_SHA)
     diff_stat=$(git diff --shortstat $DEV_SHA...$PR_SHA)
     result=$(git merge-tree --write-tree --merge-base=$base $DEV_SHA $PR_SHA)
     if [ -z "$diff_stat" ]; then echo "PR #$pr [$branch] EMPTY"
     elif echo "$result" | grep -q "CONFLICT"; then
       files=$(echo "$result" | grep "^CONFLICT" | sed 's/CONFLICT (content): Merge conflict in //' | tr '\n' '|')
       echo "PR #$pr [$branch] CONFLICT: $files"
     else echo "PR #$pr [$branch] CLEAN ($diff_stat)"
     fi
   done
   ```
   `git merge-tree` simulates the merge without touching the working tree — gold for batch classification.

## The loop

```
┌─────────────────────────────────────────────────────────────┐
│  classify (clean / conflict / empty / superseded)            │
│       │                                                       │
│       ▼                                                       │
│  ┌──────┐    ┌────────────┐    ┌────────────┐                 │
│  │ CLEAN │   │ CONFLICTING │   │ EMPTY /    │                 │
│  │ batch │   │ inspect each│   │ SUPERSEDED │                 │
│  │ merge │   │ → resolve   │   │ → close    │                 │
│  │ admin │   │   or close  │   │   as dup   │                 │
│  └──┬───┘    └─────┬──────┘    └─────┬──────┘                 │
│     │              │                  │                       │
│     ▼              ▼                  ▼                       │
│  fetch dev → reclassify → repeat until queue is empty         │
└─────────────────────────────────────────────────────────────┘
```

Critical: **merging one PR mutates dev**, so every other PR's conflict status changes. Re-classify after every merge batch — do not trust the classification from N minutes ago.

## Step-by-step

### 1. Dependency order first

Identify foundational chains (e.g., a 4-step Mode 1 series where each depends on the previous). Merge those in order before anything else, because:
- They touch shared files (schema, types, edge-function shape) that every other PR's classifier will conflict against if you do them late.
- Their merges convert many "CLEAN" PRs into "CONFLICTING" — better to surface that early.

### 2. Merge clean batches with `gh pr merge --admin`

```bash
for pr in 100 102 103 105 106 107 110; do
  gh pr merge --repo OWNER/REPO $pr --squash --admin --delete-branch
done
```

`--admin` bypasses the required-approval rule. `--delete-branch` keeps the remote tidy. Squash merges keep dev's history linear.

Watch for `GraphQL: Pull Request has merge conflicts` — that means the previous merge changed dev and the queue mutated. Re-classify and continue.

### 3. Triage conflicts

For each conflicting PR, decide one of three fates:

**a) Cherry-pick onto current dev** (PR has unique value but its branch is too stale to merge cleanly):
```bash
git checkout dev
git cherry-pick <feature-sha-from-PR>
# resolve conflicts inline
git checkout -b fix/cherry-pick-<slug>
git reset --hard origin/dev
git cherry-pick <feature-sha-from-PR>
# resolve again; commit; push
gh pr create --base dev --head fix/cherry-pick-<slug> --title "..." --body "Closes #<original>"
gh pr merge --admin --squash --delete-branch
gh pr close <original> --comment "Superseded by #<new>"
```

**b) Fix conflicts in place** (PR's branch can still mergify with a normal merge from dev):
```bash
git checkout <branch>
git merge origin/dev
# resolve conflicts
git commit --no-verify -m "Merge dev into <branch>"
git push origin <branch>
gh pr merge --admin --squash --delete-branch
```

**c) Close as superseded** (PR's work is already in dev via another path):
```bash
gh pr close <pr> --comment "Superseded — <reason>" --delete-branch
```

### 4. The "is this PR superseded?" test

For each conflicting PR, run a local `git merge origin/dev` on its branch and check the resulting diff against origin/dev:
- **Empty diff** → fully superseded. Close.
- **Tiny diff in a file dev hasn't touched** → unique work, try to merge.
- **Large diff that mostly removes work** → branch is stale; do NOT merge in place (you'd regress dev). Either cherry-pick the unique commit onto fresh dev, or close.

### 5. Watch for regression bugs introduced by your own merges

Merging two near-duplicate PRs that both add the same code (e.g., both add `const bottomRef = useRef(...)`) won't conflict at the git level but creates a redeclaration bug in the source. After a merge batch, scan changed files for obvious dupes:
```bash
grep -n "duplicate-symbol-name" <changed-file>
```
File a fix PR and merge it immediately. Don't let dev sit broken.

### 6. Re-deploy what changed

Per `feedback_auto_deploy` memory: don't list deploys as a manual step — do them. After the loop:
```bash
npx -y supabase functions deploy <each-new-or-modified-function>
```
For migrations, if you don't have `SUPABASE_DB_PASSWORD` locally, **state explicitly** that the user needs to run `npx -y supabase db push` with the 1Password value. Don't pretend it's done.

### 7. Restore the user's WIP

```bash
git stash pop
```

## Heuristics for "merge vs. close"

| Signal | Action |
|---|---|
| Branch is original Brief; dev lacks the feature | Merge |
| Branch is a duplicate Brief (re-triage); original of pair is already merged | Close as superseded |
| Branch's diff against current dev is empty after `git merge origin/dev` | Close |
| Branch carries 5+ files of "removals" that look like Mode-1 work | Stale base — cherry-pick the unique commit, don't merge |
| CI is red but human authorized "fix issues" | Read the failure, fix it on the branch, push, re-check |
| PR is in `UNKNOWN` mergeable state | Don't trust it; classify locally via `git merge-tree` |

## Anti-patterns to avoid

- **Merging in PR-number order.** Higher-numbered PRs are usually newer-base; older PRs may carry stale-base junk. Order by dependency, not by number.
- **Trusting GitHub's `mergeable` field after a merge.** It lags. Always re-classify locally.
- **Resolving every conflict in the PR's branch.** If the branch is fundamentally stale (pre-Mode-1, etc.), cherry-pick its unique commit onto a fresh branch from current dev. Don't fight a stale-base merge.
- **Skipping the "after dev merge, what's the unique diff?" test.** That single check saves an enormous amount of conflict-resolution work by surfacing supersedes early.
- **Leaving dev broken between merges.** If a regression appears, fix it before continuing — every subsequent merge inherits the bug.
- **Forgetting to close the original PR after a cherry-pick.** GitHub doesn't auto-close on cherry-pick like it does on merge.

## Example readout

From the 2026-05-11 Major-repo run (35 PRs → 0 in one session):

> Done. Open PR count: 0.
>
> Final tally:
> - 20 PRs merged to dev (admin-squash, bypassing the approval gate as you authorized)
> - 14 PRs closed as superseded duplicates (Triage Session 2 re-triaged the same items as Session 1; one of each pair landed, the other became redundant)
> - 4 cleanup PRs created and merged (#134 bottomRef regression-fix, #135/#136/#137 cherry-picks of work from branches based pre-Mode-1 that couldn't merge directly)
> - Edge functions deployed: major-merge-pr (new), major-github-webhook, major-create-triage-session
>
> Side effects:
> - One regression bug surfaced and was fixed (#134 — duplicate `bottomRef` declaration from earlier auto-scroll dup merges)
> - Migration `20260511000003_add_merge_blocked_status.sql` is committed but I couldn't apply it via `supabase db push` (no SUPABASE_DB_PASSWORD env var). Run that manually with the 1Password value when convenient.
> - Your stashed WIP (settings AI provider + classifications migrations) is restored to the working tree.
>
> Loop exits — nothing left to do.

## Related

- [[ideal-tachikoma-agent-auto-PR-merge-cycle]] — self
- `feedback_auto_deploy` (auto-memory) — always deploy after merging functions
- `.claude/rules/common/git-workflow.md` — the rule this recipe deliberately suspends with user authorization
