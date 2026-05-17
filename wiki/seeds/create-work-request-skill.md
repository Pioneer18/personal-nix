---
title: "/create-work-request skill — promote a seed into a tachikoma-ready work-request"
tags: [skill, claude-code, wiki, work-requests, grill-me, seeds]
last_updated: "2026-05-13"
target_repo: "~/projects/personal-nix"
status: open
---

# `/create-work-request` skill

The missing link in the `seed → grill-me → work-request → tachikoma` pipeline. Today seeds get captured via `/wiki add seeds`, and `/grill-me` can interview against any plan, but there is no skill that takes the grilled output and lands it as a proper `wiki/work-requests/<slug>.md` with the right frontmatter, the right `target_repo`, the right body shape, **and** deletes the source seed in the same operation.

This is the first seed, deliberately — it dogfoods the surface.

## What it should do

1. **Accept input** in two shapes:
   - `/create-work-request <seed-slug>` — promote an existing seed (default path)
   - `/create-work-request` — capture from current conversation context (no seed required)
2. **Read the seed** (if applicable) and surface its body + tags as the starting point.
3. **Interview** for the missing work-request fields that `/wiki add work-requests` requires:
   - `target_repo` (absolute path, must exist on this machine — validate via `test -d`)
   - `github_issue` (optional, link if it exists)
   - body sections: **Why this exists**, **Goal** (acceptance criteria), **Why this timing** if non-obvious
4. **Write** `wiki/work-requests/<slug>.md` with:
   ```yaml
   ---
   status: open
   target_repo: <validated>
   github_issue: ""
   failure_count: 0
   last_updated: <today>
   promoted_from: <seed-slug>        # NEW — audit trail; omit if no seed
   ---
   ```
5. **Delete the source seed** (`git rm wiki/seeds/<seed-slug>.md` style, but don't commit — leave that to the user per wiki convention).
6. **Confirm** to user: paths written + deleted; remind them to commit `personal-nix`.

## Why not just extend `/wiki add work-requests`?

`/wiki add work-requests` is a *capture* flow — frictionless write with minimal interview. `/create-work-request` is a *promotion* flow — it deliberately interviews more thoroughly because the output is going to feed tachikoma, which needs sharper acceptance criteria than "I had an idea." The skills are siblings, not the same shape.

It could also reasonably be a `/wiki promote seeds <slug>` subcommand. Open question to resolve when this seed is grilled.

## Open questions to grill on

- Standalone skill vs `/wiki` subcommand?
- Should it also support promoting from `inbox/` entries (mirror flow)?
- Should `grill-me` integration be tight (one composite skill) or loose (user runs them sequentially)?
- Should it auto-suggest a `target_repo` based on tags/title heuristics, or always ask?
- When the seed is repo-agnostic, what's the fallback `target_repo` UX — refuse, default to a meta repo, leave blank with a warning?

## See also

- `wiki/decisions/seeds-folder.md` — the surface this skill closes the loop on
- `~/.claude/skills/wiki/SKILL.md` § "Work requests and tachikoma" — the schema this skill writes
- `~/.claude/skills/grill-me/` — the upstream interview skill that feeds this
