---
name: create-work-request
description: Promote a wiki seed (or current-conversation context) into a properly-shaped `wiki/work-requests/<slug>.md` ready for tachikoma dispatch. Validates `target_repo`, writes frontmatter + body sections, and deletes the source seed in the same operation. Triggers — `/create-work-request`, `/create-work-request <seed-slug>`, `/wiki promote <seed-slug>`, "promote this seed", "land this as a work request".
---

# Create Work Request

The promote step in the `seed → grill → work-request → tachikoma` pipeline. Takes a grilled idea and lands it as a `wiki/work-requests/<slug>.md` file with correct frontmatter, validated `target_repo`, and body sections sharp enough for tachikoma to grab.

This skill complements `/wiki add work-requests` (frictionless capture) and `/grill-me` (interview-only). Use this *after* grilling, when the design is settled and you want it queued for tachikoma.

## Invocation forms

| Form | Behavior |
|---|---|
| `/create-work-request <seed-slug>` | Promote an existing seed at `wiki/seeds/<seed-slug>.md` (recommended path) |
| `/create-work-request` | Capture from current conversation context (no seed required — use when grilling happened in this session and never landed in a seed) |
| `/wiki promote <seed-slug>` | Alias for the first form (symmetric with `/wiki add`) |

## Step 1 — Load source

**If invoked with `<seed-slug>`:**

1. Read `~/projects/personal-nix/wiki/seeds/<seed-slug>.md`.
2. If the file doesn't exist, refuse and list available seeds: `ls ~/projects/personal-nix/wiki/seeds/*.md`.
3. Extract body + any frontmatter tags as the starting material.

**If invoked with no args:**

1. Use the current conversation context as the starting material.
2. Ask the user for a slug (kebab-case, descriptive). Validate it doesn't collide with an existing `wiki/work-requests/<slug>.md`.

## Step 2 — Interview for missing fields

Ask via `AskUserQuestion` (single multi-question batch where possible):

1. **`target_repo`** — Required. Absolute path to the repo this work targets. Validate with `test -d <path>` before accepting; refuse if it doesn't exist on this machine. If the work is repo-agnostic, refuse and ask the user to pick a meta repo (typically `~/projects/personal-nix` for skills/docs/wiki work).
2. **`github_issue`** — Optional. If the work is linked to an existing GitHub issue, capture as `org/repo#N`. Leave empty otherwise.
3. **`title`** — One-line H1 for the body. Default from seed title or conversation context.
4. **Body sections** — confirm or refine the three required sections (use seed/conversation content as defaults):
   - **Why this exists** — the problem or opportunity
   - **Goal / acceptance criteria** — what "done" looks like, concretely
   - **Why this timing** — only if non-obvious (skip otherwise)

Surface open questions from the source as a separate "Open questions to grill on" section if any remain unresolved — tachikoma will resolve at dispatch time.

## Step 3 — Write `wiki/work-requests/<slug>.md`

Use this exact frontmatter shape:

```yaml
---
status: open
priority: 3
target_repo: <validated-absolute-path>
github_issue: ""
failure_count: 0
last_updated: <today YYYY-MM-DD>
promoted_from: <seed-slug>        # omit if no seed
---
```

Body structure:

```markdown
# <title>

## Why this exists

<problem statement, 2-4 sentences>

## Goal

<acceptance criteria — bullet list or short prose; concrete enough that a tachikoma can self-check>

## Why this timing (optional)

<only if non-obvious — e.g. unblocking a dependent build, deadline, opportunity window>

## Open questions

<from source, if any>

## See also

<links to related skills, seeds, decisions, ADRs>
```

## Step 4 — Delete the source seed (if applicable)

If a seed slug was provided:

```bash
rm ~/projects/personal-nix/wiki/seeds/<seed-slug>.md
```

Do NOT commit. The user owns commit timing (per wiki convention — see `wiki/SKILL.md` § "Commit discipline").

## Step 5 — Confirm to user

Report in 2-3 lines:

- Path written: `wiki/work-requests/<slug>.md`
- Path deleted: `wiki/seeds/<seed-slug>.md` (or "no seed deleted (no-seed invocation)")
- Reminder: `commit personal-nix when ready`
- Hint at next step: `dispatch via /tachikoma <slug> or proxy dispatch <slug>`

## Hard rules

- **target_repo must validate.** Refuse to write if `test -d` fails. Stale `target_repo` is the #1 reason tachikoma dispatch fails downstream.
- **Slug uniqueness.** Refuse if `wiki/work-requests/<slug>.md` already exists. Either pick a different slug or have user resolve manually.
- **Never commit.** Skill writes + deletes files; commit is the user's call.
- **Seed deletion is conditional on success.** Only delete the seed after the work-request file is successfully written. Order: write → verify → delete.
- **Promoted_from is audit trail.** Always record when promoting from a seed — preserves traceability.

## Edge cases

- **Seed already promoted** (work-request exists with same slug): refuse; instruct user to delete the stale seed manually or pick a different slug.
- **Conversation context too thin** (no-seed invocation but nothing grilled in conversation): refuse; suggest user grill first via `/grill-me`.
- **Source seed has frontmatter** (some seeds may be self-typed): preserve any useful tags; skip seed-specific fields that don't map to work-request frontmatter.
- **target_repo is a worktree path**: warn but allow — user may know what they're doing. Most tachikoma dispatch expects the canonical repo path, not a worktree.

## See also

- `~/.claude/skills/wiki/SKILL.md` — wiki schema this writes to
- `~/.claude/skills/grill-me/SKILL.md` — upstream interview skill
- `~/.claude/skills/grill-to-epic/SKILL.md` — sibling promotion skill (slice list → Epic in QUEUE.yaml)
- `~/projects/personal-nix/wiki/decisions/seeds-folder.md` — the surface this closes the loop on
