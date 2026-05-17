# PROXY ↔ filesystem work-queue compatibility

Audit of the existing markdown-file work-queue at `wiki/work-requests/`, captured for the eventual PROXY Slice 17 migration to a backend-managed queue. The goal: whatever PROXY ships must preserve every behavior the two consumer skills already depend on, so the cutover is invisible to users mid-flight.

This document is **descriptive, not prescriptive**. It records what is true today (2026-05-11) by auditing the actual files in `wiki/work-requests/`, the skill `skills/work-queue/SKILL.md`, and the queue-drain section of `skills/tachikoma/SKILL.md`. Nothing here changes the queue.

## Queue layout

| Path | Role |
|---|---|
| `wiki/work-requests/` | Queue root. One markdown file per work-request. |
| `wiki/work-requests/<slug>.md` | A single work-request. `<slug>` is kebab-case and is also the filename stem. |
| `wiki/work-requests/.gitkeep` | Keeps the directory tracked when empty. Ignored by both skills. |
| `wiki/work-requests/.last-queue-run.md` | Free-form summary written by `/tachikoma queue` after a drain finishes. Not a work-request. Dot-prefixed so glob skips it. |
| `skills/work-queue/work-request.tmpl` | Template used by `/work-queue add` when creating a new file. |
| `~/.tachikoma/queue-drain.state[.N]` | Per-drain runtime state (out of repo). Atomic write-temp + `mv`. Removed on clean drain exit. Not part of the queue itself, but `/tachikoma sitrep` reads it. |

Globbing rule used by both skills: `wiki/work-requests/*.md`, excluding `.gitkeep`, dot-prefixed files, and any non-`.md` file. PROXY must reproduce this filter or the dot-prefixed run-summary file will be misread as a work-request.

## File anatomy

Every work-request file is markdown with a YAML frontmatter block delimited by `---` lines.

```
---
status: open
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# <Title>

<one-sentence description>

## Goal
...

## Files in scope
...

## Files out of scope
...

## Stop condition
...

## Feedback loops
...

## Quality bar
...
```

The closing `---` on its own line marks the end of frontmatter; everything below is body. Body length is measured (skills enforce > 50 chars) by counting characters below the closing fence.

## Frontmatter fields

Audited against the four files currently in `wiki/work-requests/` and the field tables in both skill files. Only fields actually written or read are listed.

| Field | Type | Required | Written by | Read by | Notes |
|---|---|---|---|---|---|
| `status` | enum: `open` \| `grabbed` \| `done` \| `needs-triage` | yes | `/work-queue grab\|done`, `/tachikoma queue` | both skills | Drives the state machine. `done` is transient — `done` flow deletes the file, so `done` only persists if a delete failed mid-flight. |
| `target_repo` | path string (may use `~`) | yes | `/work-queue add` | both skills (existence check) | Tilde expansion required. Readiness checks resolve the path on disk before grabbing. |
| `github_issue` | `""` or `<org>/<repo>#<N>` | yes (may be empty string) | `/work-queue add`, `/tachikoma` auto-create | `/tachikoma queue` (matching + label updates) | Empty string `""` is the canonical "no issue" value. Non-empty values must match `^[^/]+/[^#]+#\d+$`. |
| `failure_count` | integer ≥ 0 | optional (missing = 0) | `/tachikoma queue` only | both skills | Cumulative across all time. Never decremented. Drives `open` ↔ `needs-triage` transition at threshold 2. |
| `last_updated` | ISO date `YYYY-MM-DD` | yes | both skills | both skills (display only) | Bumped on every state change. |

### Observed-but-undocumented fields

The dependency-aware-queue work-request file (`tachikoma-dependency-aware-queue.md`) carries two fields that are **not** yet part of either skill's documented schema, included here so PROXY doesn't drop them on import:

| Field | Where seen | Status |
|---|---|---|
| `status: blocked` | one file as of 2026-05-11 | Informal hold state used to keep an item out of the drain without flipping to `needs-triage`. Not yet documented in skill files; treated by skills as an unknown status (shows up in `list` under an `Unknown` group). |
| `blocked_reason` | string, present only when `status: blocked` | Human-readable explanation of why the item is held. Free-form. |

Slice 17 should preserve both verbatim on round-trip, even though they are not part of the canonical state machine, so manually-set hold states survive the migration.

### Fields specced but not yet in any real file

The body of `tachikoma-dependency-aware-queue.md` specs a `blocked_by: [slug, slug]` array (dependency edges between work-requests). As of this audit no real work-request actually carries `blocked_by` in its frontmatter — the field is forward-looking. PROXY should plan for it but not assume any production data contains it yet.

`skills/tachikoma/SKILL.md` (queue-drain Step 2b) also names `files_in_scope:` and `files_out_of_scope:` as optional frontmatter alternatives to `## Files in scope` / `## Files out of scope` body sections. No current file uses the frontmatter form — body sections only.

## Body sections

The template (`skills/work-queue/work-request.tmpl`) defines the canonical body layout. Audited body sections actually present across the four current files:

| Section | Present in | Used by |
|---|---|---|
| `# <Title>` (H1) | all | display |
| One-line description paragraph | most | display |
| `## Goal` | all | tachikoma grill-field extraction (Goal) |
| `## Background` | some | informational only |
| `## Context` | some | informational only |
| `## Files in scope` | most | tachikoma grill-field extraction |
| `## Files out of scope` | most | tachikoma grill-field extraction |
| `## Stop condition` | all | tachikoma grill-field extraction (also `## Acceptance Criteria`, `## Done When` accepted as aliases) |
| `## Feedback loops` | most | tachikoma grill-field extraction (also `## Tests`, `## Verification` aliases) |
| `## Quality bar` | most | tachikoma grill-field extraction |
| `## Queue Failures` | appended on failure | `/tachikoma queue` failure-log writer; human triage reader |

The Goal extractor falls back to "first non-heading paragraph" if `## Goal` is absent. Files-in/out-of-scope default to `**` / empty if neither frontmatter nor body section exists.

## State machine

State transitions performed by the two skills:

```
              ┌──────────────────────────────────────┐
              │                                      │
   (add) → open ──grab──> grabbed ──done──> done ──> (file deleted)
              │                │
              │                ├──fail (count<2)──> open
              │                │
              │                └──fail (count≥2)──> needs-triage
              │
              └──(manual edit)──> blocked  (informal hold state)

   needs-triage ──(human resets file)──> open
```

Authoritative per-transition table:

| From | To | Driver | Condition |
|---|---|---|---|
| (none) | `open` | `/work-queue add` | initial create |
| `open` | `grabbed` | `/work-queue grab` | manual single-item flow |
| `open` | `grabbed` | `/tachikoma queue` Step 2d | per-item commit point in a drain |
| `grabbed` | `done` | `/work-queue done` | manual completion (then file deleted) |
| `grabbed` | `done` | `/tachikoma queue` Step 2i | Phase 6 success (then file deleted) |
| `grabbed` | `open` | `/tachikoma queue` failure path | `failure_count` after bump < 2 |
| `grabbed` | `needs-triage` | `/tachikoma queue` failure path | `failure_count` after bump ≥ 2 |
| `grabbed` | `open` | `/tachikoma queue` Step 0 recovery | grabbed item has no matching worktree (crash before scaffold) |
| `grabbed` | `open` | `/tachikoma queue` user-abort path | Ctrl-C between grab and worktree creation; no `failure_count` bump |
| `needs-triage` | `open` | manual human edit | only after reading `## Queue Failures` |

Both skills refuse to grab or mark-done a `needs-triage` item. `needs-triage` is terminal-until-human.

The `done → file-deleted` step is part of the contract: `/work-queue list` and the readiness checks treat any `done` value still on disk as stale (shown under an `Unknown` group). PROXY must preserve the delete-on-done behavior, or migrate by treating all post-cutover `done` items as soft-deleted.

## Per-file mutation patterns

These are the exact mutation surfaces the skills currently perform. The smoke test exercises the same surfaces. PROXY's storage layer must support each.

| Operation | Mutation |
|---|---|
| Create | Write whole file from template (`work-request.tmpl`) with substitutions. |
| Grab | In-place edit: `status: open` → `status: grabbed`, bump `last_updated`. Preserve all other frontmatter and body verbatim. |
| Fail (retryable) | In-place edit: `status: grabbed` → `status: open`, bump `failure_count`, bump `last_updated`. Append `## Queue Failures` section (or new entry under existing one). |
| Fail (quarantine) | In-place edit: `status: grabbed` → `status: needs-triage`, bump `failure_count`, bump `last_updated`. Append `## Queue Failures`. |
| Done (success) | Delete file from disk. |
| Done (manual) | Delete file from disk. |
| Manual hold | Human edit: `status: <anything>` → `status: blocked`, add `blocked_reason: "..."`. |

The `open` ↔ `grabbed` flip is a read-modify-write on the markdown frontmatter, not atomic. The skill explicitly accepts this race window (small in practice; documented in `skills/tachikoma/SKILL.md` Step 2d's race-condition note). PROXY can tighten this — a backend with a real claim primitive removes the race entirely — but must not loosen it.

## What `/work-queue list` relies on

1. Glob `wiki/work-requests/*.md` (skip dotfiles and `.gitkeep`).
2. Parse YAML frontmatter on each file. Tolerate malformed frontmatter: skip with a warning, do not crash.
3. Group by `status` in the order `open` → `grabbed` → `needs-triage`. Any other value (`done`, `blocked`, anything unrecognized) lands in an `Unknown` group.
4. For each `open`, validate readiness:
   - `target_repo` field present
   - `target_repo` path exists on disk (expand `~`)
   - body length > 50 chars
5. For each `needs-triage`, display `failure_count` (default 0 if missing).
6. Render a flat table with columns: Slug · Target · Status · Notes.

## What `/tachikoma queue` relies on

1. Same glob and parse as `list`.
2. Readiness check before grab (Step 1 pre-flight):
   - `status: open`
   - `target_repo` present and path exists on disk
   - Body length > 50 chars
   - `failure_count` < 2
3. Session recovery (Step 0): find files with `status: grabbed`, cross-reference against `git worktree list` for matching `tachikoma/*<slug>*` branches. Grabbed-with-no-worktree → auto-reset to `open`.
4. Body-section extraction (Step 2b) for grill fields, with header aliases (Goal / Stop condition / Feedback loops have multiple accepted headers).
5. Two-pass match between a finished tachikoma run and its work-request (ship-phase Step 9): exact filename match against the branch slug first, then `github_issue` field fallback.
6. Failure log append (`## Queue Failures` section) preserving prior entries.
7. Filename ↔ branch derivation: `tachikoma/<slug>` ↔ `wiki/work-requests/<slug>.md`.

Anything PROXY changes that breaks one of these seven contracts is a breaking change for the skills.

## Cutover criteria for Slice 17

When PROXY's queue backend replaces the filesystem queue, all of the following must hold before the skills can be repointed:

- [ ] **Field parity.** Every frontmatter field listed above (`status`, `target_repo`, `github_issue`, `failure_count`, `last_updated`, plus the observed-but-undocumented `blocked` / `blocked_reason`) is readable and writable through the backend. Unknown fields round-trip unchanged.
- [ ] **State-machine parity.** All transitions in the per-transition table above are supported, including the manual `needs-triage → open` reset path (human-driven, not API-driven, but the backend must accept the resulting state).
- [ ] **Delete-on-done parity.** Successful completion of an item removes it from the queue listing (whether by hard delete or soft-delete with default-filtered list).
- [ ] **Body-section preservation.** All markdown body content survives create → grab → fail → grab → done round-trips verbatim, including appended `## Queue Failures` entries.
- [ ] **Readiness check semantics.** The backend exposes enough metadata for the two skills' readiness checks (existence of `target_repo` on disk is a client-side check, but body length and `failure_count` are server-side).
- [ ] **Glob-filter semantics.** Files like `.last-queue-run.md` and `.gitkeep` either don't exist in the new model or are filtered out of the queue listing.
- [ ] **Dual-write window.** During cutover, the filesystem queue and the PROXY queue are kept in sync (one writes through to the other) for at least one full drain cycle, so a mid-flight `/tachikoma queue` started against the old store can finish without corruption.
- [ ] **Smoke test green on both stores.** `scripts/smoke-test-queue.sh` (or its successor) passes against both the filesystem store and the PROXY store with the same frontmatter shape.
- [ ] **Skill files unchanged at cutover.** The cutover ships without modifying either `skills/work-queue/SKILL.md` or `skills/tachikoma/SKILL.md` beyond a single config-pointer swap (or equivalent). If wider edits are needed, the abstraction has leaked.
- [ ] **Rollback path.** Repoint-back to the filesystem store works in one step if PROXY misbehaves.
- [ ] **`.last-queue-run.md` analog.** The drain-summary artifact has an equivalent in PROXY (either a real file in the same location for compatibility, or a backend-served log that `/tachikoma sitrep` can read).
- [ ] **`~/.tachikoma/queue-drain.state*` files.** These are per-drain runtime state, **out of scope** for Slice 17 — they live outside the queue store and stay on disk after migration.

## Out of scope for this document

- PROXY's internal data model — this audit constrains the external contract only.
- Migration tooling (one-shot importer of existing `*.md` files into PROXY).
- Multi-tenant concerns — the filesystem queue is single-user, single-machine; if PROXY introduces sharing, that is a Slice-17 design decision, not a compatibility constraint.
- The `~/.tachikoma/queue-drain.state*` runtime state files used by `/tachikoma sitrep`. Those are orchestrator state, not queue state, and live outside the queue store.
