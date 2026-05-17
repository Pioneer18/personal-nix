---
name: wiki
description: Search, list, or add entries in Pioneer18's personal wiki at `~/projects/personal-nix/wiki/`. Use when the user asks "what tools/skills/MCPs do I have?", "what's in my wiki?", "add this to my wiki", "save this for later", "do I have notes on X?", or any request that maps to durable personal knowledge across machines. Triggers — `/wiki`, `/wiki <query>`, `/wiki <subdir>`, `/wiki add <subdir>`, or any natural-language request to query or extend the wiki.
---

# Wiki

Pioneer18's machine wiki. Knowledge that outlives any single Claude session, queryable on demand. Lives at `~/projects/personal-nix/wiki/`, syncs across Macs via the personal-nix repo.

## Subdirs (fixed vocabulary — refuse unknown subdirs)

- `tools/` — stubs for tools/skills/MCPs/CLIs (summarize + link to canonical doc; do not duplicate)
- `recipes/` — how-to walkthroughs
- `decisions/` — ADR-lite, design decisions and rationale
- `glossary/` — term → definition
- `runbooks/` — "when X breaks, do Y"
- `inbox/` — uncategorized captures (triage later)
- `notes/` — random saves, tag-categorized
- `seeds/` — pre-brief ideas; promoted via `/grill-me` → `/brief` (which writes a v2 dossier into PROXY and deletes the seed on promotion). Interim surface until PROXY's notebook ships (M6); see `decisions/seeds-folder.md`.
- `work-requests/` — work captured for tachikoma to pick up later (alternative to GitHub issues)

## Invocation

| Form | Behavior |
|---|---|
| `/wiki` | Show contents of `wiki/INDEX.md` |
| `/wiki <query>` | Search across all subdirs |
| `/wiki <subdir>` | List all entries in that subdir |
| `/wiki <subdir> <query>` | Search within that subdir |
| `/wiki add` | Guided capture, defaults to `inbox/` |
| `/wiki add <subdir>` | Guided capture into specific subdir |
| `/wiki help` | Display the user guide in chat. |

If `<subdir>` is not in the fixed vocabulary above, refuse and list valid subdirs.

## Read flow

1. **No args** — `cat wiki/INDEX.md` and present it to the user. Done.

2. **Subdir only** — list every `.md` in `wiki/<subdir>/`. For each, parse frontmatter and print: `<title> — <summary or first body line>` (one line each). If empty, say so.

3. **Query (with or without subdir)** — search in this order:
   - **Frontmatter match first**: glob `wiki/<subdir>/*.md` (or `wiki/**/*.md`), parse frontmatter on each, score by:
     - exact `tags` match (highest weight)
     - exact `category` match (`tools/` only)
     - `title` substring match
     - `summary` substring match
   - **Body grep fallback**: if frontmatter scoring returns < 3 matches, fall back to `grep -ril <query> wiki/<subdir>/` (or full wiki).
   - Return up to 10 matches, ordered by relevance, formatted as: `<path> — <title> — <one-line summary>`.
   - If 0 matches: say so and suggest `/wiki <subdir>` to browse, or `/wiki add` to capture.

4. **Following links** — when a `tools/` entry has a `link` field pointing to a local file (e.g., `~/projects/personal-nix/skills/tachikoma/README.md`), do not auto-follow. Surface the link and let the user decide. If the user explicitly asks for the full doc, then read it.

## Add flow

1. **Validate subdir.** If invalid, refuse with the valid list.

2. **Prompt for required fields** (do not ask for fields you can infer from conversation context):
   - **All subdirs**: `title` (required), `tags` (comma-sep, optional, default `[]`), body
   - **`tools/`**: also `summary` (required, one line), `category` (required), `link` (optional)
   - **`glossary/`**: also `term` (required, often same as title)
   - **`decisions/`**: also `status` (one of `proposed`/`accepted`/`superseded`, default `accepted`)
   - **`work-requests/`**: also `target_repo` (required, absolute path or `~`-prefixed — must exist on this machine), `status` (one of `open`/`grabbed`/`done`, default `open`). Optional `promoted_from: <seed-slug>` if the work-request was promoted from a seed.
   - **`seeds/`**: also `target_repo` (**optional** — some seeds are repo-agnostic; ask but don't require), `status` (always `open` at capture; promotion deletes the file rather than transitioning status)
   - **`recipes/` / `runbooks/` / `notes/` / `inbox/`**: just title, tags, body

3. **Compute slug** from title: lowercase, alphanumeric + dashes, max 40 chars. Filename = `wiki/<subdir>/<slug>.md`.

4. **Collision check.** If file exists, ask user whether to: append a date suffix (`<slug>-2026-05-09.md`), overwrite, or cancel.

5. **Write the file** with this shape:

```markdown
---
title: "<title>"
tags: [<tag1>, <tag2>]
last_updated: "<YYYY-MM-DD>"
<subdir-specific fields>
---

<body>
```

`last_updated` = today's date in `YYYY-MM-DD`. Use the date provided in the conversation context if available (e.g., from a `currentDate` system instruction), otherwise `date +%Y-%m-%d` via Bash.

6. **Confirm to user**: print the relative path written.

7. **If subdir is `inbox/`**: gently remind: "Inbox entries should be triaged into a real subdir within the next few days — `/wiki inbox` to review."

8. **Do not auto-commit.** Tell the user the file is written; they commit when convenient. (`git -C ~/projects/personal-nix add wiki/<subdir>/<slug>.md && git commit -m "wiki: <title>"`).

## Special cases

### Editing an existing entry

If the user asks to update or extend an existing entry, find the file via the read flow first, then use Edit on the matched file. Update `last_updated` to today.

### Decisions promotion / supersession

When a `decisions/` entry is replaced by a newer one, the user may ask to mark it superseded. Set the old entry's `status: superseded` and add `superseded_by: <slug-of-new-entry>` to its frontmatter. The new entry should reference `supersedes: <slug-of-old-entry>`.

### Glossary collisions

If a `glossary/` entry already exists for the term, prefer **editing** the existing entry over creating a duplicate. Glossary terms should have exactly one entry.

### Seeds — pre-work-request ideas

`seeds/` entries are the inbox for ideas the user knows they want to act on later but doesn't want to commit to as a full work-request yet (no required `target_repo`, no acceptance criteria, just a captured thought). Lifecycle:

- Capture is intentionally low-friction: `title`, `tags`, body, optional `target_repo`.
- The user grills a seed via `/grill-me <seed-slug>` to expand it into a PROXY v2 dossier-brief spec.
- Promotion via `/brief <seed-slug>` writes a transient v2 dossier-brief markdown file, invokes `proxy brief <slug>` to create the `dossiers` row in PROXY's database, and **deletes** the source seed in the same operation. Git history is the audit trail; no archive subdir.
- Do not maintain a `status: promoted` state — promotion = deletion. If a user changes their mind about a seed, just delete it.

This subdir is **interim** until PROXY's notebook UI ships (v1.5+, M6). At migration, a one-shot importer maps every seed into a `notebook.idea` row and `seeds/` is removed from the vocabulary. See `decisions/seeds-folder.md`.

When the user asks "what ideas do I have?", list `seeds/` entries by `last_updated` desc.

### Work requests and tachikoma

`work-requests/` entries are durable seeds for tachikoma runs — an alternative to filing a GitHub issue. Lifecycle:

- New entries default to `status: open`.
- Every entry must have a `target_repo` — the absolute path of the codebase tachikoma should worktree from. Validate it exists at write time; refuse if not.
- When the user points tachikoma at an entry, update its `status` to `grabbed` (and bump `last_updated`).
- When the work lands (PR merged or task abandoned), update to `status: done`.

When the user asks "what work do I have queued?" or similar, list `work-requests/` entries with `status: open` first. Tachikoma will typically interview/expand the entry into a PRD before looping — the entry is the seed, not the spec.

Same privacy guardrails as the rest of the wiki: public repo, so no RelyMD work.

### Tool entries that already have a canonical doc

For `tools/` entries about things with existing READMEs (skills, MCPs, etc.):
- Body should be ≤ 5 lines: what it is, when to use it, and a link
- The `link` frontmatter field points to the canonical doc
- Do **not** copy content from the canonical doc into the catalog entry — keep the entry stub-thin so it doesn't drift

## Privacy guardrails

The wiki dir lives in a public GitHub repo (`personal-nix`). Refuse to write any of:
- API keys, tokens, passwords (anything matching common secret patterns)
- RelyMD-specific business logic that isn't already public
- Personal information about identifiable third parties

If a user request would violate this, surface the concern, suggest the auto-memory system instead (`~/.claude/projects/.../memory/`), and ask before proceeding.

## Failure modes

- **Subdir doesn't exist** (someone deleted one) — recreate it; inform user.
- **Frontmatter malformed in an entry** — when scanning, skip and warn (don't fail the whole search).
- **Slug collision** — see add flow step 4.
- **Wiki dir missing entirely** — wiki/ should always exist (it's tracked in personal-nix). If missing, tell user the personal-nix repo may be in a bad state; do not auto-recreate.

## Help

**When invoked as `/wiki help`:** display the following user guide in chat.

---

## Wiki — User Guide

Pioneer18's personal knowledge base at `~/projects/personal-nix/wiki/`. Syncs across Macs via the personal-nix repo.

### Commands

| Command | What it does |
|---|---|
| `/wiki` | Show the wiki index (INDEX.md) |
| `/wiki <query>` | Search all subdirs for a query |
| `/wiki <subdir>` | List all entries in a subdir |
| `/wiki <subdir> <query>` | Search within a specific subdir |
| `/wiki add` | Capture a new entry (guided); defaults to `inbox/` |
| `/wiki add <subdir>` | Capture into a specific subdir |
| `/wiki help` | Show this guide |

### Subdirectories

| Subdir | What goes here |
|---|---|
| `tools/` | Stubs for tools, skills, MCPs, CLIs |
| `recipes/` | How-to walkthroughs |
| `decisions/` | Design decisions and rationale (ADR-lite) |
| `glossary/` | Term → definition |
| `runbooks/` | "When X breaks, do Y" |
| `inbox/` | Uncategorized captures (triage later) |
| `notes/` | Random saves, tag-categorized |
| `seeds/` | Pre-brief ideas; promote via `/grill-me` → `/brief` |
| `work-requests/` | Work items for tachikoma |

### Example workflow

```
/wiki add recipes        — capture a new how-to
/wiki recipes auth       — search recipes for "auth"
/wiki tools tachikoma    — look up the tachikoma tool stub
/wiki add inbox          — quick capture; triage later
/wiki add seeds          — capture a pre-work-request idea
/wiki seeds              — list all pending ideas
```

### Seeds workflow (idea → work-request → tachikoma)

`seeds/` is the inbox for ideas you know you want to act on later but aren't ready to commit to as a full work-request. Lower friction than `work-requests/` (no required `target_repo`, no acceptance criteria) — just a captured thought.

The pipeline:

```
/wiki add seeds                       — capture (title, tags, optional target_repo, body)
/wiki seeds                           — browse pending ideas
/wiki seeds <query>                   — search them
/grill-me wiki/seeds/<slug>.md        — interview to expand into a v2 dossier-brief spec
/brief <slug>                         — promote: writes /tmp/proxy-brief-<slug>.md, invokes
                                        `proxy brief <slug>` (creates dossiers row), DELETES the seed
```

Key properties:

- **Capture is friction-free.** Only `title` + `tags` required. Body and `target_repo` are optional — fill them in later during grilling.
- **Promotion = deletion.** No `status: promoted` state, no archive subdir. Git history is the audit trail.
- **Repo-agnostic seeds are fine.** Some ideas don't have an obvious target repo yet; that's the whole point of capturing them before committing to a work-request.
- **Interim surface.** When PROXY's notebook UI ships (M6 / v1.5+), a one-shot importer maps every seed into a `notebook.idea` row and the `seeds/` directory is retired from the wiki vocabulary. See `decisions/seeds-folder.md` for the migration plan.

Historical note: the original `/create-work-request` skill was the first seed dogfooding this surface. It has since been superseded by `/brief`, which writes a PROXY v2 dossier directly into the daemon rather than a v1 work-request markdown file.

### Privacy

`personal-nix` is a public repo. Don't write API keys, passwords, RelyMD business logic, or personal third-party info. Use auto-memory (`~/.claude/projects/.../memory/`) for sensitive context.

---

## Pointer to human-facing docs

[README.md](README.md) — orientation for future-you, including layout, design decisions, and common breakages.
