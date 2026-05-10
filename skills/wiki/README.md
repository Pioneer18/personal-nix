# Wiki skill

Personal knowledge base for this machine, accessible to AI on demand.

## TL;DR

`/wiki` reads/searches/adds entries in `~/projects/personal-nix/wiki/`. Markdown files with frontmatter, organized into seven subdirs. Public via personal-nix repo, syncs across Macs. Sensitive content goes to auto-memory instead.

## File layout

```
~/projects/personal-nix/skills/wiki/         ← this skill
├── README.md                                  this file
└── SKILL.md                                   orchestrator instructions

~/projects/personal-nix/wiki/                ← content root
├── INDEX.md                                   static "what is this" doc
├── tools/                                     catalog stubs (link to canonical docs)
├── recipes/                                   how-tos
├── decisions/                                 ADR-lite
├── glossary/                                  term → definition
├── runbooks/                                  "when X breaks, do Y"
├── inbox/                                     uncategorized capture
└── notes/                                     random saves
```

## Invocation reference

| Form | Behavior |
|---|---|
| `/wiki` | Show INDEX.md |
| `/wiki <query>` | Search across all subdirs |
| `/wiki <subdir>` | List entries in subdir |
| `/wiki <subdir> <query>` | Search within subdir |
| `/wiki add` | Capture into `inbox/` |
| `/wiki add <subdir>` | Capture into specific subdir |

## Locked-in design decisions

- **On-demand only.** No eager-loaded index in CLAUDE.md. Wiki content is queried via `/wiki`, not pre-loaded into every session.
- **Public-by-default.** Lives in the public personal-nix repo. Sensitive content goes to the gitignored auto-memory at `~/.claude/projects/.../memory/`. Skill refuses to write secrets.
- **Fixed subdir vocabulary.** Seven subdirs, no ad-hoc creation. Promote a tag to a subdir if it accumulates 10+ entries; demote a subdir if it's been empty 6+ months.
- **Summarize-and-link for tools.** `tools/<x>.md` is a 5-line stub + link to the canonical doc (e.g., a skill's README). Catalog is for discoverability, not duplication.
- **Frontmatter is the query primitive.** Common: `title`, `tags`, `last_updated`. Type-specific extras for `tools/`, `glossary/`, `decisions/`. Skill filters by frontmatter before falling back to body grep.
- **No auto-commit.** Skill writes the file; user commits when convenient. Avoids surprise commits on `personal-nix`.
- **No auto-INDEX-regen.** INDEX.md stays static (describes the *categories*). Catalogs are computed on demand by the skill, not pre-baked.

## Ergonomics tradeoffs we picked

| Decision | Cost | Benefit |
|---|---|---|
| Frontmatter required on every entry | Friction at capture | Reliable AI queries |
| Skill prompts for required fields | More turns at capture | Consistent shape |
| Inbox subdir | Triage debt | Frictionless capture when category is unclear |
| Public-only, no private split | Some content can't go here | One mental model, one location |
| Fixed subdir vocabulary | Less flexibility | Predictable AI catalog answers |

## Common breakages

- **"unknown subdir" refusal** — typo, or someone tried `/wiki add foo`. Skill enforces the vocabulary.
- **Wiki dir missing on a fresh Mac** — the `dev` rebuild + bootstrap should clone personal-nix. If missing, run bootstrap.sh.
- **Search returns nothing for an obvious term** — frontmatter probably wasn't tagged. `grep -r` the body manually, then add the tag.
- **Two entries with the same slug** — slug collisions. Skill adds a date suffix; clean up later by merging or renaming.
- **Sensitive content slipped in** — `git log --all -- wiki/` to find it, rewrite history with `git filter-repo`, force-push. Avoid by using auto-memory for anything you'd be embarrassed to publish.

## Hacking on the skill itself

Symlink at `~/.claude/skills/wiki` points at the live working tree (after `dev` activates it). Edits to `SKILL.md` here take effect immediately — no rebuild needed.

## Adjacent systems

- **Auto-memory** (`~/.claude/projects/.../memory/`) — Claude's session-spanning notes about you. Auto-captured. Private/local. Use for sensitive context.
- **`orient-to-machine` skill** — architectural map of this Mac (nix-darwin, layers, recipes for modifications). Use when you need to *change* the machine, not just look something up.
- **Global `CLAUDE.md`** (`~/.claude/CLAUDE.md`) — instructions loaded into every session. Use for behavior rules, not knowledge.
- **Per-skill READMEs** — canonical docs for each skill (e.g., `skills/tachikoma/README.md`). The wiki's `tools/` stubs link to these.

The wiki is for **knowledge that's true regardless of session, durable, queryable on demand.** Anything else belongs in one of the systems above.
