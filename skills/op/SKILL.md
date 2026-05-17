---
name: op
description: Low-friction Operation capture for PROXY (ADR 007). Take a title, drop an Operation into ~/projects/personal-nix/wiki/operations/ and OPERATIONS.yaml within seconds. Use when the user types /op, /op <title>, says "new Op", "capture this", or describes a director-level workstream they want to start tracking.
---

Low-friction capture for a PROXY Operation. The user wants this fast — don't grill, don't decompose, don't infer Objectives. Just drop the Op and return control.

## What an Operation is

Director-level workstream (above Epic). Has Objectives + Follow-ups + priority + status. See ~/Projects/tachikoma-starter/CONTEXT.md for the full glossary. See ~/Projects/tachikoma-starter/docs/adr/007-operations-and-objectives.md for the full schema.

## Behavior

1. **Title**: take it from the user's args; if no args, prompt for a one-line title (one input, no other questions).
2. **Slug**: kebab-case the title; prefix with `relymd-` if not already prefixed (V1 default theater).
3. **Dedup check** (pre-slice-31, lightweight): list existing `~/projects/personal-nix/wiki/operations/*.md` slugs + read their `title` from frontmatter. If a slug or title is a fuzzy match for the new title, ask: "Looks like existing Op `<slug>` — append as Objective, or new Op?" Wait for response. On "append": invoke the file-edit path for adding an Objective (see below). On "new": continue.
4. **Write Op file** at `~/projects/personal-nix/wiki/operations/<slug>.md` with this frontmatter (priority left null — async triage will fill it once slice 31 ships; for now, the file is captured but untriaged):

```yaml
---
slug: <slug>
title: "<title>"
theater: relymd
priority: null
status: live
created_at: <today's date>
last_touched_at: <today's date>
objectives: []
follow_ups: []
---

# <title>

(Capture context here later via /op-grill or by editing this file directly.)
```

5. **Append to OPERATIONS.yaml** at the bottom of the `relymd` theater section, position = next available integer. If OPERATIONS.yaml doesn't exist yet, create it (see seed pattern in ADR 007 D2).
6. **Confirm to user**: "Op `<slug>` captured. Triage will run when slice 31 ships; until then, run `/op-grill <slug>` to flesh out priority + Objectives."

## Appending as Objective (the "append" branch)

If the user picks "append as Objective":
1. Read the target Op's frontmatter.
2. Append a new Objective: `{ id: "obj-NN" (next int), text: "<title>", status: "open", link: null }`.
3. Bump the target Op's `last_touched_at`.
4. Confirm: "Added Objective `obj-NN` to Op `<target-slug>`."

## Hard rules

- **NEVER prompt for more than the title.** If the user wanted to grill, they'd have invoked `/op-grill`. Honor the low-friction contract.
- **NEVER auto-assign priority.** Triage runs async (slice 31). Until then, `priority: null` means "not yet triaged" — which excludes the Op from "what's next" suggestions per ADR 007 D7.
- **File edits are atomic**: write to a temp file (`<path>.tmp`), then rename. Don't leave partial writes.
- **Do not skip the dedup check.** It's the cheap version of pgvector — the user will be annoyed if duplicates pile up.
