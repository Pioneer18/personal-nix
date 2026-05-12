---
name: auto-review-prs
description: Two-pass PR triage on the current repo's `dev` branch. Pass 1 silently auto-merges PRs that meet the strict `clean` rubric or the relaxed `good-enough` rubric, re-evaluating every open PR including ones previously labeled `auto-merge-blocked`. Pass 2 walks you through the rest one-by-one with a plain-English briefing, contextual actions (request reviewer, post comment, draft tests, resolve conflicts), and a Diagnose escape hatch. Refuses to run inside `~/Projects/platform`. Triggers — `/auto-review-prs` (full pass), `/auto-review-prs auto` or `--autonomous-only` (autonomous only), "auto-merge PRs", "walk me through open PRs", or any natural-language request for assisted PR triage.
---

# auto-review-prs

Two-pass PR triage for the current repo's `dev` branch. Pass 1 silently merges the safe stuff. Pass 2 walks you through the rest.

## Invocation

| Form | Behavior |
|---|---|
| `/auto-review-prs` | Full pass: autonomous merge → interactive walkthrough |
| `/auto-review-prs auto` | Autonomous pass only; remaining queue printed to report |
| `/auto-review-prs --autonomous-only` | Same as `auto` |

## Absolute rules

1. **Pass 1 (autonomous) asks no questions.** If anything is ambiguous, the PR drops into the walkthrough queue.
2. **Banned repo.** If the cwd resolves under `/Users/pioneer/Projects/platform`, print an error and exit immediately.
3. **Target branch is `dev`.** If `dev` doesn't exist on the remote, exit with an error before doing anything.
4. **Squash merges only, branch deleted after.** No merge commits, no rebases.
5. **Auto-merge always leaves an audit trail.** For PRs authored by *another* GitHub user, post a `--approve` review with the rubric summary, then squash-merge. For self-authored PRs, GitHub hard-blocks `--approve` (`GraphQL: Can not approve your own pull request`) regardless of branch protection — post the rubric summary as a regular PR comment instead, then merge. Either way the rubric ends up on the PR thread.
6. **Eval-gate paths never auto-merge.** Any PR touching `supabase/functions/chat-with-ai/**` or `eval/**` is forced into the walkthrough (tier 3) regardless of how clean the rest looks.
7. **Re-evaluate every open PR every run.** The `auto-merge-blocked` label is a cached last-result marker, not a gate. Never skip a PR because of it.
8. **Replace stale auto-review comments.** When re-evaluating a previously-flagged PR, delete the prior `[auto-review-prs]` comment from this account before posting a new one — keeps the PR thread tidy.

## Pre-flight

Run these sequentially. Any failure → exit with the message, do not enter pass 1.

1. Verify cwd is a git repo: `git rev-parse --show-toplevel`.
2. Resolve cwd; check it is **not** inside `/Users/pioneer/Projects/platform`.
3. Verify `gh auth status` succeeds.
4. Verify `dev` branch exists on the remote: `gh api repos/{owner}/{repo}/branches/dev` returns 200.
5. Ensure the `auto-merge-blocked` label exists; create if missing:
   ```bash
   gh label list --search auto-merge-blocked --json name -q '.[].name' | grep -qx auto-merge-blocked \
     || gh label create auto-merge-blocked --color FBCA04 --description "Auto-review flagged; needs human review"
   ```
6. Ensure the report path is writable: `mkdir -p ~/projects/personal-nix/wiki && touch ~/projects/personal-nix/wiki/auto-merged-pr-report.md`.

Announce mode in one line — `"Auto-review on <owner>/<repo> → dev. Mode: <full | autonomous-only>."` — then start pass 1.

## Pass 1 — Autonomous

### Fetch and order

```bash
gh pr list --base dev --state open --json number,title,author,isDraft,labels,headRefName,additions,deletions,files,mergeable,mergeStateStatus,statusCheckRollup --limit 100
```

Drop drafts. **Keep** PRs with `auto-merge-blocked` — they get re-evaluated.

For ordering within this pass (so concurrent merges in an overlap group don't race):

- Build a file-overlap graph: edge between two PRs that share any path.
- Isolated PRs first, sorted by total diff ascending.
- For each connected overlap-group, only the smallest-diff PR is eligible this pass; the others will re-evaluate next run.
- Process eligible PRs in that order.

### Per-PR classification

For each eligible PR, run hard gates first, then the rubric. Classification outcomes are `clean`, `good-enough`, or one of the walkthrough tiers (1–4).

**Hard gates (failure → walkthrough, never auto-merge):**

1. **Conflict.** `mergeable == "CONFLICTING"` → walkthrough tier 1 (conflicts).
2. **CI status** via `statusCheckRollup`:
   - `IN_PROGRESS` / `PENDING` / `QUEUED` / `EXPECTED` → defer; don't classify yet (re-check at end of pass).
   - `FAILURE` / `CANCELLED` / `TIMED_OUT` / `ACTION_REQUIRED` → walkthrough tier 1 (CI failed).
   - `SUCCESS` / `NEUTRAL` / `SKIPPED` / no checks → proceed.
3. **Size cap.** `additions + deletions > 10000` → walkthrough tier 3 (large diff).
4. **Eval-gate paths.** Any file in `supabase/functions/chat-with-ai/**` or `eval/**` → walkthrough tier 3 (eval-gate). Never auto-merge.

**Rubric (run if hard gates pass).** Fetch the diff with `gh pr diff <N>` and metadata with `gh pr view <N> --json title,body,files`.

1. **Secrets / credentials.** Hardcoded API keys, tokens, passwords, JWT-shaped strings, AWS keys, private keys. Patterns: `sk-…`, `ghp_…`, `ghu_…`, `AKIA…`, `-----BEGIN .* PRIVATE KEY-----`, `password\s*=\s*["'][^"']{6,}`, raw connection strings with embedded passwords. Allow test fixtures (`**/fixtures/**`, `**/test*/**`, names starting with `test_`/`fake_`/`dummy_`). → walkthrough tier 3 (secrets).
2. **Obvious bugs.** Clear correctness errors visible from the diff: null/undefined deref on a value just shown to be possibly absent; off-by-one in loop bounds; inverted boolean; wrong operator (`=` vs `===`, `&&` vs `||`); swapped argument order against a callee signature visible in the diff; an error catch that swallows and ignores. No speculation about runtime behavior you can't see. → walkthrough tier 3 (obvious bugs).
3. **Scope mismatch.** Diff modifies areas not implied by title/description. → walkthrough tier 2 (scope mismatch).
4. **Logic without tests.** Categorize each file:
   - **No-test allowlist:** `**/*.md`, `**/docs/**`, lockfiles (`**/package*.json`, `**/*.lock`, `**/*.sum`), `**/.github/**`, `**/.gitignore`, `**/.editorconfig`, test files themselves (`**/test/**`, `**/tests/**`, `**/__tests__/**`, `**/*.test.*`, `**/*.spec.*`).
   - **Pure-UI carve-out:** `src/app/**/*.tsx`, `src/components/**/*.tsx`.
   - **Logic:** everything else — hooks, services, utils, lib, providers, schemas, types, data, supabase functions and migrations, scripts, config files (`*.config.*`, `app.config.ts`, `eas.json`, `tsconfig*.json`).

   If the diff contains any Logic file and no test file, check the **good-enough carve-outs:**

   - **Path carve-out:** every Logic file in the diff lives in `src/types/**`, `src/data/**`, `src/constants/**`, or matches `*.config.*` / `app.config.ts` / `eas.json`. → tier `good-enough` (path).
   - **Size carve-out:** total Logic-file additions+deletions ≤ 30 AND total PR diff ≤ 100 AND every Logic file has fewer than 10 changed lines. → tier `good-enough` (size).
   - Otherwise → walkthrough tier 2 (logic without tests).

If hard gates and rubric all pass, tier = `clean`.

### Auto-merge (clean + good-enough)

For `clean` and `good-enough` PRs, branch the audit-trail mechanism on authorship. Determine the active user with `gh api user --jq .login`; compare against the PR's `author.login`.

**Other-authored PR (canonical path):**

```bash
gh pr review <N> --approve --body "<approval template — see Comment templates>"
gh pr merge <N> --squash --delete-branch
```

**Self-authored PR (GitHub blocks self-approval with `GraphQL: Can not approve your own pull request`):**

```bash
gh pr comment <N> --body "<self-merge template — see Comment templates>"
gh pr merge <N> --squash --delete-branch
```

On the `dev` ruleset (`Required approvals: 0` per [ADR 003 in healthbite](https://github.com/MioMarker/healthbite/blob/main/docs/adr/003-self-approval-on-dev.md)), the merge succeeds without an approval. The rubric ends up on the PR thread either way — different mechanism, same audit trail.

After a successful merge (either path):

- Remove the `auto-merge-blocked` label if present: `gh pr edit <N> --remove-label auto-merge-blocked`.
- Delete any prior `[auto-review-prs]` comment from this account. Find via:
  ```bash
  gh api repos/{owner}/{repo}/issues/<N>/comments \
    --jq '.[] | select(.body | startswith("[auto-review-prs]")) | .id'
  ```
  Delete each: `gh api -X DELETE repos/{owner}/{repo}/issues/comments/<ID>`.

If the merge call fails (race, branch protection unexpectedly rejects, etc.) → drop to walkthrough tier 1 with reason `"merge call failed: <stderr>"`.

### End of pass 1

- Re-check deferred (in-flight CI) PRs; if CI completed during the pass, classify and either auto-merge or queue them.
- Anything still in flight at end-of-pass → record as **pending CI at exit** in the report (not the walkthrough).
- Give one progress line in chat per ~5 PRs processed (`"Pass 1: merged 3, queued 4 so far."`).

When pass 1 ends, announce: `"Pass 1 done. Merged <M> (<C> clean, <G> good-enough). Queued for walkthrough: <W>."`

## Pass 2 — Walkthrough

**Skipped entirely** in `--autonomous-only` mode. The walkthrough queue is dumped to the report instead.

### Ordering

Tier ascending (1 → 4), oldest-first within each tier:

| Tier | Categories | Why this tier |
|---|---|---|
| **1 — mechanical** | conflicts, CI failed, merge call failed | Agent can pull/rebase or diagnose a failing log directly |
| **2 — agent-assisted** | scope mismatch, logic without tests | Agent can draft tests or suggest a PR split |
| **3 — human-decision** | secrets, obvious bugs, large diff (>10k), eval-gate paths | Needs your judgment; agent presents context |
| **4 — cleanup** | stale (no commits in 30 days) | Close or nudge |

### Per-PR cycle

For each PR in the queue, in tier order:

1. **Render briefing** (full template — see below).
2. **AskUserQuestion** with 4 options: 2 contextual actions + Diagnose + Skip. `Other` is auto-available for free-form follow-up (including `"end walkthrough"` / `"stop"` / `"quit"` to exit cleanly).
3. **Execute** the user's pick, governed by the agency rules below.
4. **Log** the action taken in the session's report buffer.
5. **Advance** to the next PR.

### Briefing template

```
─── PR #<N> ───────────────────────────────────────────
<title>
Author: <login>  •  <head-branch> → dev
Size: <total> lines  •  <L>L + <T>T + <O>O  •  CI: <status>

▸ What this PR does
  <1–2 line plain-English summary derived from title + diff fingerprint>

▸ Why this PR is in the queue
  <tier and rejection reason in 1–3 lines>

▸ Next step (recommended)
  <agent's specific recommendation>

▸ Links
  PR:    https://github.com/<owner>/<repo>/pull/<N>
  Files: https://github.com/<owner>/<repo>/pull/<N>/files
  <conditional: failing CI run, individual file URLs, etc.>
───────────────────────────────────────────────────────
```

Legend for the size line: `L` = logic files, `T` = test files, `O` = other (docs, config, lockfile, etc.).

### Action menus

Two contextual options per rejection category, plus universals (Diagnose + Skip for now):

| Rejection category | Contextual option 1 | Contextual option 2 |
|---|---|---|
| Conflicts | Pull and resolve conflicts *(code)* | Comment asking author to rebase *(text)* |
| CI failed | Open failing check in browser *(mechanical)* | Diagnose and suggest a fix *(text/code)* |
| Logic without tests | Draft tests for the changed functions *(code)* | Override as good-enough and merge *(destructive)* |
| Scope mismatch | Post a split-suggestion comment *(text)* | Convert PR to draft *(mechanical)* |
| Secrets | Open the offending file in browser *(mechanical)* | Close PR and post rotation steps *(destructive)* |
| Obvious bugs | Post comment with file:line + suggested fix *(text)* | Request changes *(mechanical)* |
| Large diff (>10k) | Post split-suggestion comment *(text)* | Convert to draft *(mechanical)* |
| Eval-gate path | Open eval CI run in browser *(mechanical)* | Post needs-eval-review comment *(text)* |
| Stale (>30d no commits) | Post "still active?" comment *(text)* | Close PR *(destructive)* |
| Merge call failed | Retry merge now *(mechanical)* | Diagnose why it failed *(text)* |

Universals on every briefing:

- **Diagnose** — sub-conversation about this PR (no commitment to an action).
- **Skip for now** — this-session-only; PR returns to the next run's queue.

### Agency rules

| Action class | Examples | Policy |
|---|---|---|
| **Mechanical GitHub op** | request reviewer, add/remove label, open URL, convert to draft | Just do it. The option-pick is the confirmation. |
| **Text the agent generates** | comments, review messages, nudges | Show the draft inline (in chat). User replies `"send"`, `"edit: <new text>"`, or `"skip"` before it posts. |
| **Code change** | drafting tests, resolving conflicts locally, fixing a CI typo | Make the edit, show the diff, ask before pushing. |
| **Destructive** | close PR, force-push to PR branch, delete branch | Explicit `y/N` confirmation, even if the option was already picked. |

Rule of thumb: **the more reversible the action, the less ceremony.** A label add is one click to undo; a force-push isn't.

### Mid-walkthrough exit

Any AskUserQuestion accepts `Other → "end walkthrough"` (or `"stop"`, `"quit"`). The skill writes the partial report and exits cleanly.

## Comment templates

### Approval — clean (other-authored PR)

Posted via `gh pr review <N> --approve --body ...`.

```
[auto-review-prs] Auto-approved as **clean**. Rubric:
- Size: <N> lines (under 10000-line cap)
- Secrets/credentials: clean
- Obvious bugs: none found
- Scope: matches title/description
- Tests: <touched | N/A: pure-UI carve-out | N/A: allowlist only>
- CI: <green (<N> checks passed) | not configured>
- Conflicts: none against `dev`
```

### Approval — good-enough (other-authored PR)

Posted via `gh pr review <N> --approve --body ...`.

```
[auto-review-prs] Auto-approved as **good enough**. Rubric:
- Size: <N> lines (under 10000-line cap)
- Secrets/credentials: clean
- Obvious bugs: none found
- Scope: matches title/description
- Tests: relaxed via <path carve-out: <files> | size carve-out: <N> logic lines, <total> total>
- CI: <green | not configured>
- Conflicts: none against `dev`
```

### Self-merge comment — clean (self-authored PR)

Posted via `gh pr comment <N> --body ...`. GitHub blocks self-approval, so this is the substitute audit trail.

```
[auto-review-prs] Auto-merged as **clean**. Rubric:
- Size: <N> lines (under 10000-line cap)
- Secrets/credentials: clean
- Obvious bugs: none found
- Scope: matches title/description
- Tests: <touched | N/A: pure-UI carve-out | N/A: allowlist only>
- CI: <green (<N> checks passed) | not configured>
- Conflicts: none against `dev`

_Self-authored on `dev` — GitHub blocks the `--approve` review on own PRs, so the rubric is recorded as a comment instead. Merge enabled by ADR 003._
```

### Self-merge comment — good-enough (self-authored PR)

```
[auto-review-prs] Auto-merged as **good enough**. Rubric:
- Size: <N> lines (under 10000-line cap)
- Secrets/credentials: clean
- Obvious bugs: none found
- Scope: matches title/description
- Tests: relaxed via <path carve-out: <files> | size carve-out: <N> logic lines, <total> total>
- CI: <green | not configured>
- Conflicts: none against `dev`

_Self-authored on `dev` — GitHub blocks the `--approve` review on own PRs, so the rubric is recorded as a comment instead. Merge enabled by ADR 003._
```

### Walkthrough-generated comment

Posted only when the user picks a "comment" action in the walkthrough. The skill replaces any prior `[auto-review-prs]` comment from this account before posting.

```
[auto-review-prs] <one-line reason, action-oriented>

**Details:**
<specific evidence>

<optional closing line, e.g. "Re-run /auto-review-prs after the next push to re-evaluate.">
```

## Final report

When the skill exits (clean exit or via mid-walkthrough `"end walkthrough"`):

**a. Print to stdout** as a markdown summary in chat.

**b. Append to `~/projects/personal-nix/wiki/auto-merged-pr-report.md`** with a dated header. Format:

```markdown
# <ISO-8601 timestamp> — <owner>/<repo>

**Mode:** <full | autonomous-only>  •  **Duration:** HH:MM

## Merged (<count>)
- #123 [clean] — <title>
- #142 [good-enough: path carve-out — src/types/**] — <title>
- #133 [good-enough: size carve-out — 22 logic lines] — <title>

## Walkthrough actions taken (<count>)
- #149 [tier-1: conflicts] — <title> → posted "please rebase" comment
- #145 [tier-2: scope mismatch] — <title> → converted to draft
- #131 [tier-3: eval-gate path] — <title> → skipped this session

## Walkthrough queue at exit (<count>)
- #130 [tier-4: stale 47d] — <title>

## Pending CI at exit (<count>)
- #134 — <title> (3 checks running)

---
```

In `--autonomous-only` mode, "Walkthrough actions taken" is omitted; everything that didn't auto-merge appears under "Walkthrough queue at exit."

## Failure handling

**Recoverable (continue, don't exit):**

- `gh` network 5xx → log to stdout, skip the PR, continue.
- Rate limit (HTTP 429 or `gh` rate-limit error) → log; retry the call once after a short wait.
- `gh pr merge` race (another merge landed first) → drop the PR into the walkthrough queue with reason, continue.

**Unrecoverable (write partial report, exit):**

- `gh auth status` fails mid-pass → print `gh auth login` instruction, write partial report, exit.
- Three consecutive PRs hit total API failures → write partial report, exit.

## Notes for the agent running this skill

- Trigger is `/auto-review-prs`. Positional arg `auto` or flag `--autonomous-only` switches to autonomous-only.
- After pre-flight, announce mode in one line, then start pass 1 silently (no per-PR narration during pass 1).
- During pass 1, give a one-line progress update every ~5 PRs processed.
- Before entering pass 2, announce: `"Pass 1 done. Merged <M> (<C> clean, <G> good-enough). Queued for walkthrough: <W>."`
- During pass 2, render the full briefing for each PR — not a summary.
- Don't narrate individual PR decisions in chat during pass 1; the GitHub audit trail and the final report already capture them.
- Pre-flight does **not** verify branch protection settings. If a merge call hits an unexpected approval requirement (e.g. ruleset reverted), let the call fail and drop the PR into the walkthrough with reason "merge call failed: <stderr>".
