---
status: blocked
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
blocked_reason: "Current queue drain mid-flight. Unblock (flip status to `open`) and start a new `/tachikoma queue` invocation after the current drain ends. Editing SKILL.md and proxy-*/major-mode-* frontmatter while a drain is running risks races on the same files."
---

# Tachikoma — dependency-aware queue scheduling

Add `blocked_by` semantics to the work-request queue so that `/tachikoma queue N` can parallelize independent items while preserving order for dependent chains (e.g. proxy-01..16).

## Goal

A worker drains the queue grabbing the next item where `status: open AND all blocked_by are status: done`. Multiple workers naturally partition: independent items run in parallel, chains serialize. No worker burns tokens while waiting — when nothing's eligible, the worker exits.

## Background

The file-based queue currently has 18+ work-requests, many with implicit ordering (proxy-01 → proxy-02 → … proxy-16). Naive `queue 3` workers race: worker A grabs proxy-02 while B grabs proxy-03 — proxy-03's worktree branches off `develop` and doesn't see proxy-02's changes (still in an open PR, not yet merged to develop). Phase 6 ships a PR but doesn't auto-merge into the base branch, so `status: done` ≠ "code in develop."

This work-request implements the fix.

## Design decisions (locked via /grill-me)

1. **Dependency representation**: per-file frontmatter (`blocked_by: [slug, slug]`, optional, default `[]`). Matches the existing PRD-internal `blocked_by` convention; keeps each work-request self-describing.
2. **Satisfaction semantics**: `status: done` is the gate, but only meaningful if Phase 6 actually merges into the base branch. So this work also adds an **auto-merge mode** (α1) for personal repos.
3. **Worker behavior when nothing eligible**: skip-and-exit. Working workers loop to pull the next eligible item when they finish current; idle workers exit immediately rather than poll. No new state. Worker re-globs and grabs next eligible *before* exiting current iteration (so it doesn't miss freshly-unblocked items).
4. **Failure cascade**: hard block, dependents stay `open`. `needs-triage` upstream keeps downstream ineligible until human fixes upstream. No cascading quarantine. `/work-queue list` annotates "BLOCKED (waiting on <slug>)" in the notes column for visibility.
5. **Validation**: at drain start, before spawning workers, build the dep graph and refuse if: any `blocked_by` slug references a missing file, any cycle, any self-reference. Print the offending nodes and exit.
6. **Build scope**: full — all 8 items below.

## Implementation

### 1. Schema change

Add `blocked_by` field to work-request frontmatter:

```yaml
blocked_by: []      # optional; list of slugs that must be status: done first
```

Document in `skills/work-queue/SKILL.md` under the Frontmatter section.

### 2. Readiness check (in `skills/tachikoma/SKILL.md`)

Update the readiness check (currently around the queue-drain section) to add a 5th criterion:

- `status: open`
- `target_repo` present and path exists on disk
- Body length > 50 chars
- `failure_count` < 2
- **NEW**: every slug in `blocked_by` exists as a work-request AND has `status: done`

### 3. Drain-start validation (new section in `skills/tachikoma/SKILL.md`)

Before spawning any workers, walk the queue and validate:

1. Glob all `*.md` work-requests; build `{slug: blocked_by}` map.
2. For each slug in any `blocked_by`, confirm it's a known slug. If not: `✗ Missing reference: <a> blocked_by <missing-slug>`.
3. Self-reference: reject with `✗ Self-reference: <a> blocked_by <a>`.
4. DFS cycle detection: if cycle, print `✗ Dependency cycle: a → b → c → a`.
5. On any failure: exit before spawning workers.

### 4. Phase 6 auto-merge (α1 mode)

Add a config knob in `~/.claude/tachikoma.conf`:

```toml
auto_merge = true   # default false; when true, Phase 6 auto-merges the PR into PR_TARGET_BRANCH before flipping status: done
```

In Phase 6, after `gh pr create` succeeds, if `auto_merge` is true:

```sh
gh pr merge <PR> --squash --auto
# poll gh pr view <PR> --json mergedAt until non-null (max 60s)
```

Only after merge confirmed → flip `status: done`. If merge fails or times out → log to PR body + flip `status: needs-triage`. Document the security implications in `USER-GUIDE.md` (auto-merge bypasses human review — personal repos only).

### 5. Chain branches (β mode)

Add a per-WR override in frontmatter:

```yaml
pr_target_branch: feat/proxy-01-scaffold-docker-compose   # optional; default = repo's default branch
```

When `pr_target_branch` is set, the scaffold phase creates `ISSUE_BRANCH` off this branch (not `develop`). Phase 6 opens PR against this branch. Use case: when `auto_merge` isn't acceptable and the user wants a PR stack instead of human-gated merges.

Auto-derivation rule: if `pr_target_branch` is unset AND `blocked_by` is non-empty, derive `pr_target_branch = feat/<blocked_by[0]>`. Skip auto-derivation when `auto_merge: true` (those flows assume merges land in develop).

### 6. `/work-queue add` prompt

Add a step to the `add` flow asking "Does this depend on other work-requests being shipped first? (optional, comma-separated slugs)". Validate each entered slug exists in the queue; show a substring-match picker if ambiguous. Write the resolved slugs to the new file's `blocked_by` frontmatter.

### 7. `/work-queue list` annotation

For `open` items with non-empty `blocked_by`, in the notes column:
- All blockers are `done`: omit annotation (item is ready).
- Any blocker is non-done: `BLOCKED (waiting on <slug>: <upstream-status>)`. Show only the first blocker for compactness; if multiple, append `+N more`.

### 8. Docs

Update:
- `skills/tachikoma/SKILL.md` — readiness check, validation section, Phase 6 auto-merge, chain-branch derivation
- `skills/tachikoma/USER-GUIDE.md` — explain dep model + new commands + auto-merge caveat
- `skills/tachikoma/README.md` — command table entries
- `skills/work-queue/SKILL.md` — schema, add flow, list flow
- `wiki/tools/tachikoma.md` — overview update

### 9. Frontmatter rollout (data work)

After the spec lands, walk every work-request in `wiki/work-requests/` and add `blocked_by` where applicable. Known chains as of writing:

- proxy-01 → proxy-02 → proxy-03 → … → proxy-16 (linear chain of 16)
- proxy-17 depends on proxy-16 (currently `blocked` for unrelated reason; preserve that)
- proxy-18 depends on proxy-17
- major-mode-1-01 → major-mode-1-02 → major-mode-1-03 → major-mode-1-04
- tachikoma-ui-* and other singletons have no chain — leave `blocked_by: []` or omit

Confirm with the user before applying any chain that isn't obvious from slug naming.

## Acceptance criteria

1. `blocked_by` accepted in work-request frontmatter; missing field treated as `[]`.
2. Readiness check filters items where any `blocked_by` slug is not `status: done`.
3. Drain-start validation refuses to spawn workers on cycle / missing ref / self-ref; exits with a clear message.
4. With `auto_merge: true` in `~/.claude/tachikoma.conf`, Phase 6 auto-merges the PR and only then flips `status: done`.
5. With `pr_target_branch` set (or auto-derived from `blocked_by[0]`), the worktree branches off the predecessor's feat branch.
6. `/work-queue add` prompts for dependencies and writes them to frontmatter.
7. `/work-queue list` annotates `BLOCKED (waiting on <slug>)` for items with unsatisfied dependencies.
8. Manual end-to-end test: queue with proxy-01..03 having a chain runs sequentially under `/tachikoma queue 3` (3 workers launch, 2 exit immediately, 1 serializes the chain).
9. Docs updated across all 5 files.
10. All proxy-* and major-mode-* work-request files have their `blocked_by` chains populated.

## Out of scope

- Polling/wait-and-watch worker modes (we explicitly chose skip-and-exit).
- Multi-queue separation by category.
- A central manifest file or sqlite-backed queue (per-file frontmatter is the source of truth).
- Replacing the markdown-frontmatter atomic-flip locking with `flock(2)` or sqlite (the race window is acceptable for now; flagged for future hardening in SKILL.md).
- BLOCKED-as-distinct-state (new status value). The grill explicitly chose to derive "blocked upstream" from `blocked_by` + `status` in `/work-queue list` annotations rather than introduce a new persisted state.
