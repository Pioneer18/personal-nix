---
title: "Wiki `seeds/` — pre-work-request idea capture"
tags: [decision, wiki, proxy, notebook, work-requests, grill-me]
last_updated: "2026-05-13"
status: accepted
---

# Wiki `seeds/` — pre-work-request idea capture

## Context

Two-stage capture problem: there are ideas the user knows they want to act on, but doesn't yet want to commit to the discipline of a full work-request (`target_repo`, scope, acceptance criteria, etc.). Today those ideas have no home — they get dropped in chat, lost when the session compacts, or force-fit into `work-requests/` with placeholder fields. Examples accumulating in conversation: "build a `/create-work-request` skill" (referenced multiple times, never captured), "add a periodic seed-review job", etc.

The intended downstream flow is well-formed: `seed → /grill-me <seed> → /create-work-request → work-request file → tachikoma`. The missing piece is the inbox for the *first* step.

PROXY's v3 architecture anticipates this: the **notebook** (CLAUDE.md `Notebook` section) has three default categories, the first of which is `idea — promotable to work request, not notifiable`. Notebook is SQL-backed, ships in v1.0 M6 (web UI / `proxy-12-extended` + `proxy-14` notebook keep slice). It is not yet built; v1.0 just shipped on 2026-05-13.

## Options considered

| Option | Mechanism | When it wins | When it loses |
|---|---|---|---|
| A. Wiki now, migrate to notebook when M6 ships | New `wiki/seeds/` subdir (file-based, Tier 1 personal-nix); a one-shot importer pushes them into the notebook `idea` rows when M6 lands; the `seeds/` dir is **deleted** after migration | Available immediately, syncs across Macs via personal-nix, costs zero new infra, fits existing wiki ergonomics | Two storage homes briefly during the migration window |
| B. Wiki forever | `seeds/` lives alongside `work-requests/`, never migrates to notebook | Durable seeds belong with the rest of durable personal knowledge | Loses PROXY's clean "idea → promote" flow in the notebook UI |
| C. Wait for notebook (M6) | No new surface; ideas live in chat/scratch until notebook ships | Avoids interim two-home state | Weeks/months of friction before the surface exists |
| D. Both: SQL row + wiki mirror | New `proxy_ideas` table now + wiki mirror | Forward-compatible | Over-engineered for an interim |

## Decision

**Adopt A.** `wiki/seeds/` is the pre-work-request idea inbox until PROXY's notebook UI ships (M6 / v1.5+). When notebook lands, a one-shot importer maps every seed into a `notebook.idea` row, then **deletes** the `seeds/` directory so it doesn't linger as a stale shadow.

Naming: `seeds/`, not `ideas/`. Reasons:
- Avoids collision with the notebook's `idea` category (which is more general — todos and customs live next to it).
- Captures the lifecycle: a seed *becomes* a work-request through grilling. Distinct semantic.

## Schema

Each seed is `wiki/seeds/<slug>.md`:

```yaml
---
title: "<one-line description>"
tags: [<tag1>, <tag2>]
last_updated: "<YYYY-MM-DD>"
target_repo: "<optional ~-prefixed path>"   # nullable; some seeds are repo-agnostic
status: open                                 # always `open`; `promoted` triggers delete
---

<free-form body — as much or as little as you want at capture time>
```

## Lifecycle

1. **Capture** — `/wiki add seeds` (or direct Write). Frontmatter requires `title`, `tags`, `last_updated`. `target_repo` and body are optional at capture time — that's the whole point.
2. **Browse / search** — `/wiki seeds` lists, `/wiki seeds <query>` searches. Identical to other subdirs.
3. **Promote** — `/grill-me <seed-slug>` interviews to expand the seed into a real work-request spec; the resulting `/create-work-request` (skill TBD — itself the first seed) writes `wiki/work-requests/<slug>.md` with `promoted_from: <seed-slug>` in its frontmatter, then **deletes the seed file**. The git history is the audit trail.
4. **Migration to PROXY notebook (M6+)** — one-shot importer reads every `seeds/*.md`, inserts a `notebook` row with `category=idea`, body, tags, created_at from `last_updated`. After verification, `git rm -r wiki/seeds/` + commit. The wiki subdir vocabulary contracts back to its pre-seed state.

## Consequences

**Positive:**
- The idea surface exists today (zero new infra).
- Workflow (`seed → grill → work-request → tachikoma`) is end-to-end coherent.
- Seeds sync across Macs via personal-nix (Tier 1).
- Migration to notebook is mechanical and one-way; no permanent dual-home state.

**Negative:**
- Two homes briefly during the migration window. Mitigated by the importer + immediate delete.
- One more subdir in the wiki vocabulary (now nine instead of eight). The `/wiki` skill SKILL.md + README.md + INDEX.md all need a one-line update.
- The promotion flow depends on a `/create-work-request` skill that doesn't exist yet — captured as the **first seed** to dogfood the surface.

## Follow-on work

- (Now) Add `seeds/` to `/wiki` skill's fixed vocabulary; update SKILL.md + README.md + INDEX.md.
- (Now) Write first seed: `seeds/create-work-request-skill.md` (the skill that will close the loop).
- (When `/create-work-request` is built) Ensure it writes `promoted_from: <seed-slug>` to the work-request frontmatter and deletes the source seed in the same operation.
- (M6 / v1.5) Write the importer: `seeds/*.md → notebook.idea` rows. Verify, then `git rm -r wiki/seeds/`. Update this decision to `superseded_by: <new-decision-slug>` and supersede the wiki subdir entry.

## See also

- `~/Projects/tachikoma-starter/CLAUDE.md` § Notebook — the v3 design that this subdir is interim for
- `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` § 22 (M6) — where notebook ships
- `wiki/decisions/agentic-shell-4-tier-state.md` — Tier 1 personal-nix is the seeds' home
