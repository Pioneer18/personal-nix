---
name: grill-to-epic
description: Convert a grilling-session conversation (with a settled slice breakdown) into a PROXY Epic landed in `wiki/QUEUE.yaml` — confirms Epic metadata interactively, validates each slice slug resolves to a real work-request file, and reports completion. Triggers — `/grill-to-epic`, "land this as an Epic", "promote this grill to the queue", "Epic these slices".
---

# Grill to Epic

The promote step in the `grill → slice breakdown → Epic in queue` workflow. Reads the slice list from the conversation (typically the wrap-up of a `/grill-me` or `/grill-with-docs` session), confirms Epic metadata with the user, and inserts the Epic block into `~/projects/personal-nix/wiki/QUEUE.yaml`.

Sibling to `/create-work-request` (which lands individual slices); this skill lands the *container* — the Epic — once the slices are settled.

## Prerequisites

- Epic + Queue infrastructure shipped (proxy-27/28/29, per ADR 006). The file `~/projects/personal-nix/wiki/QUEUE.yaml` must exist.
- A grilling conversation in scope with a clear slice breakdown — typically a markdown table, a "Follow-on work" bullet list, or an explicit ADR slice section.

If `QUEUE.yaml` doesn't exist or no slice breakdown is in scope, refuse with a clear pointer.

## QUEUE.yaml schema (reference)

```yaml
queue:
- epic: <epic-slug-kebab>
  title: <one-line title>
  goal: <one-paragraph goal — what done looks like>
  slices:
  - <slice-slug-1>
  - <slice-slug-2>
- standalone: <work-request-slug>      # non-Epic entry
- epic: <another-epic-slug>
  ...
```

Entries are ordered; position in the list = queue priority (top = next up).

## Step 1 — Parse the conversation for slices

Scan the recent conversation for a slice breakdown. Look for, in priority order:

1. **A markdown table** with a slug column (often labeled `Slug`, `Slice`, `ID`, or `proxy-XX-...`)
2. **A bullet list** under a heading like "Follow-on work", "Slice breakdown", "Plan", "Implementation slices"
3. **An ADR slice section** (especially if `/grill-with-docs` was used)

Extract slugs in their listed order. If multiple candidate lists exist, ask the user which one is canonical.

If no slice breakdown is found, refuse with: "No slice list detected — run `/grill-me` or `/grill-with-docs` first to produce one, then re-invoke."

## Step 2 — Confirm Epic metadata

Ask via `AskUserQuestion` (single batched call where possible):

1. **Epic slug** — kebab-case. Suggest from the conversation's working title or topic. Refuse if it collides with an existing `epic:` key in QUEUE.yaml.
2. **Title** — one-line H1 for the Epic. Default from conversation title.
3. **Goal** — one-paragraph "what does done look like". Default from the conversation's overall goal statement.
4. **Queue position** — `top` (insert at index 0), `bottom` (append), or a specific position number (1-indexed). Default: bottom.

## Step 3 — Validate slice slugs

For each slug parsed in Step 1:

1. Check `~/projects/personal-nix/wiki/work-requests/<slug>.md` exists.
2. If missing: list all missing slugs and ask the user:
   - **Generate stub work-requests** — use `/create-work-request` per missing slug to land stubs from conversation context
   - **Skip and proceed** — write the Epic anyway, missing slices will fail tachikoma dispatch later
   - **Cancel** — abort the Epic write

Also detect **cross-Epic conflict** — if any slice slug already appears under another Epic's `slices:` list in QUEUE.yaml, refuse and ask the user to decide:
   - **Move** — remove from old Epic, add to new one
   - **Duplicate** — leave in both (rare; usually a mistake)
   - **Cancel**

## Step 4 — Write QUEUE.yaml (atomic)

Read the current `QUEUE.yaml`, splice the new Epic block at the requested position, write to a temp file (`QUEUE.yaml.tmp` in same dir), then atomic rename:

```bash
mv ~/projects/personal-nix/wiki/QUEUE.yaml.tmp ~/projects/personal-nix/wiki/QUEUE.yaml
```

Preserve existing entries exactly (don't reformat). Insert the new Epic as a top-level list item with proper indentation.

## Step 5 — Optional: generate slice stubs

If the user chose "Generate stub work-requests" in Step 3, invoke `/create-work-request` per missing slug. Pass conversation context as the body source. Confirm each before writing.

## Step 6 — Report

```
Epic `<slug>` added to QUEUE.yaml at position N with M slices:
  - <slice-1>  ✓
  - <slice-2>  ✓
  - <slice-3>  ⚠ stub generated this session
Reminder: commit personal-nix when ready.
Next: dispatch via `proxy queue grab` or `tachikoma queue`.
```

## Hard rules

- **Atomic writes only.** Always temp-file + rename for QUEUE.yaml. Concurrent writes (PROXY daemon may also touch it) require atomicity.
- **Slug uniqueness across Epics.** A slice slug may appear in at most one Epic's `slices:` list. Refuse cross-Epic duplicates unless user explicitly chooses "Duplicate".
- **Never commit.** Skill writes QUEUE.yaml; commit is the user's call.
- **Validate before write.** All checks (slug uniqueness, file existence, cross-Epic conflict) must complete before any write happens. Don't write a partial-validated Epic.

## Edge cases

- **No slice breakdown in conversation** — refuse, suggest grilling first.
- **Slice list is enormous (>15 slices)** — warn the user; Epics that big usually want to be split. Don't refuse; just flag.
- **Conversation referenced multiple grills** — ask the user which one is canonical for this Epic.
- **Slug naming collision with existing standalone** — refuse; instruct user to either rename the Epic slug or remove the standalone first.
- **Existing QUEUE.yaml is malformed** — refuse and surface the parse error; don't try to rewrite.

## Future extensions (not in v1)

- `--auto` flag: skip confirmation if conversation has enough signal.
- Post-write hook: optionally invoke `tachikoma queue grab` to auto-dispatch the first slice.
- Cross-skill chain: `/grill-me --to-epic` could invoke this skill at session-end.

## See also

- `~/.claude/skills/grill-me/SKILL.md` — upstream interview skill
- `~/.claude/skills/grill-with-docs/SKILL.md` — sibling grilling skill that updates ADRs inline
- `~/.claude/skills/create-work-request/SKILL.md` — promotes individual slices (this skill's complement)
- `~/Projects/tachikoma-starter/docs/adr/006-epic-queue-architecture.md` — Epic + Queue architecture spec
- `~/projects/personal-nix/wiki/QUEUE.yaml` — the file this skill writes
