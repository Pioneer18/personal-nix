# Wiki

Pioneer18's machine wiki. Knowledge that should outlive any single session — captured here, queried via the `/wiki` skill, synced across Macs via the personal-nix repo.

This INDEX is static. The `/wiki` skill provides search and listing on demand — don't try to maintain a hand-rolled catalog here.

## Subdirs

| Dir | What goes here | Distinct from |
|---|---|---|
| `tools/` | Stubs for tools, skills, MCPs, CLIs available on this machine. **Summarize + link** to canonical doc; never duplicate. | Each entry is a discoverability hook, not the doc itself |
| `recipes/` | Walkthroughs: "how to set up X", "how to do Y". | Runbooks (which fire on failure) |
| `decisions/` | ADR-lite: design decisions and rationale. "What we settled and why." | Recipes (instructions) and notes (random) |
| `glossary/` | Term → definition. RelyMD domain language and general technical terms. | Notes — strict format, just `term` and `definition` |
| `runbooks/` | "When X breaks, do Y." Incident-response playbooks. | Recipes — runbooks fire on failure, recipes are setup |
| `inbox/` | Friction-free staging for captures you haven't categorized yet. | Triage periodically — promote to a real subdir |
| `notes/` | Random saves, half-formed thoughts, anything not warranting its own subdir yet. Tag-categorized. | Inbox (which is unsorted); notes are kept-as-notes intentionally |
| `work-requests/` | Work captured for tachikoma to pick up later — alternative to GitHub issues. `status` field tracks `open` / `grabbed` / `done`. | Inbox (unsorted) — work-requests are intentional, tachikoma-targeted |

## Frontmatter conventions

Every entry has these required fields:

```yaml
title: "Human-readable title"
tags: [tag1, tag2]
last_updated: "YYYY-MM-DD"
```

Subdir-specific extras:

- **`tools/`**: `summary` (one-liner for catalog listings), `category` (string e.g. "agent-dev", "shell", "nix"), `link` (path or URL to canonical doc)
- **`glossary/`**: `term` (the word being defined)
- **`decisions/`**: `status` (`proposed` / `accepted` / `superseded`), optional `supersedes` / `superseded_by` (slug refs)
- **`work-requests/`**: `target_repo` (required, absolute path of the codebase tachikoma should worktree from), `status` (`open` / `grabbed` / `done`)

## Privacy

This dir lives in `~/projects/personal-nix/`, a **public** GitHub repo. Don't put RelyMD secrets, half-formed personal vents, or anything you'd be embarrassed to share. Sensitive context belongs in the auto-memory at `~/.claude/projects/.../memory/` (gitignored, machine-local).

## How to add an entry

```
/wiki add <subdir>
```

The skill prompts for required fields, generates the slug, writes the file. Or just create the file directly with your editor — the skill will pick it up.

## How to find something

```
/wiki <query>              # search across all subdirs
/wiki <subdir>             # list entries in one subdir
/wiki <subdir> <query>     # search within one subdir
```
