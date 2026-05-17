---
status: done
priority: 3
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-16
---

# Skill idea — `/grill-to-epic`

> Seeded from `wiki/seeds/grill-to-epic-skill.md`. Body below is the original seed; treat as
> rough — needs grilling + scope refinement before tachikoma dispatch.

After a grilling session ends with a coherent design + slice list, invoke `/grill-to-epic` to take the design from "decided in conversation" → "Epic in the work queue, ready to grab" in one step.

## What it does

1. **Parse the conversation transcript** for the resulting slice list (typically from a "Follow-on work / slice breakdown" section, an ADR's "slice table," or a wrap-up summary)
2. **Confirm Epic metadata interactively** via `AskUserQuestion`:
   - Epic slug (suggested from title)
   - Epic title
   - One-line goal
   - Queue position (top / bottom / specific position)
3. **Write the Epic entry** into `~/projects/personal-nix/wiki/QUEUE.yaml` (atomic temp + rename)
4. **Optionally write slice `.md` files** if not already created in conversation; offer to generate stubs from grilling content
5. **Verify** each referenced slice slug resolves to a real work-request file; warn on missing
6. **Report**: "Epic `<slug>` added to queue at position N with M slices: [slug1, slug2, ...]"

## Use case

Closes the loop on the grilling → working-queue workflow.

Demonstrated 2026-05-13/14 with:
- `email-vertical` Epic (8 slices) — done conversationally
- `queue-infrastructure-v1` Epic (3 slices) — done conversationally

Both worked but pattern was repeated 2x in one day. Worth automating into a discrete skill.

## Dependencies

Requires Epic + Queue infrastructure (proxy-27/28/29) shipped. QUEUE.yaml at `~/projects/personal-nix/wiki/QUEUE.yaml` is the file target. ADR 006 has the schema spec.

## Related

- `/grill-me` — upstream skill, produces the design conversation this consumes
- `/create-work-request` — existing skill, creates individual slice files from seeds
- ADR 006 — Epic + Queue architecture
- `proxy queue add-epic` + `proxy queue add-slice` — CLI commands that this skill orchestrates

## Implementation hints

- Pure transcript parser; no DB queries needed (claude reads the conversation)
- Detect slice breakdown table or "Follow-on work" section; map markdown table → slug list
- Validate each slug against existing work-request files; offer to write stubs for missing
- Atomic write on QUEUE.yaml; respect existing entries (insert at requested position, don't overwrite)
- Edge case: grilling produced N slices but user only wants M to land as the Epic — multi-select to filter
- Edge case: slugs already in another Epic — refuse and prompt user to decide (move? duplicate? cancel?)
- Could become a recipe instead of a skill if interactivity is light enough — pick form during impl

## Future extension

- `/grill-to-epic --auto` — no-confirm, infer everything from transcript context. Risky but powerful for routine grills.
- Integration with `tachikoma queue` — after Epic created, optionally auto-launch Tachikoma on first slice ("dispatch and run").
