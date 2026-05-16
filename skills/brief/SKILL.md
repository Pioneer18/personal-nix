---
name: brief
description: Brief PROXY on a new dossier — interview the user (or accept a pre-grilled seed/spec), write a v2 dossier-brief markdown file, then invoke `proxy brief <slug>` so the daemon imports it into the `dossiers` table and deletes the transient file. The downstream surface of the `seed → grill-me → brief → infil` pipeline. Triggers — `/brief`, `/brief <slug>`, "brief proxy on X", "create a dossier for Y", "promote this seed to a dossier".
---

# `/brief` — write a PROXY v2 dossier

This skill closes the loop from "rough idea" to "PROXY-ingested dossier ready for `proxy infil`". It is a promotion flow — high-friction interview, sharp output — not a frictionless capture (use `/wiki add seeds` for that).

## Invocation

| Form | Behavior |
|---|---|
| `/brief <slug>` | Promote an existing `wiki/seeds/<slug>.md` (or start fresh with that slug if no seed) |
| `/brief` | Capture from current conversation context; ask for a slug |

## Inputs you must collect

The dossier schema (see `proxy-v2-01-schema-migration` for the canonical column list) requires:

**Required**
- `title` — one-line human-readable; goes into the markdown H1
- `target_repo` — absolute path, must exist on this machine (validate via `test -d <path>`)
- `files_in_scope` — array of glob patterns the loop may touch
- `files_out_of_scope` — array of glob patterns the loop must NOT touch (assertion, not a hint)
- `acceptance_criteria` — checklist that defines "done"
- `feedback_loops` — list of commands the loop must pass before committing (typecheck, test, lint, build, etc.)
- `body` — prose description of the task (everything after the H1 in the markdown)

**Advisory (nullable)**
- `recommended_callsign` — preset name, e.g. `quill`, `dossier-clerk` — handler can override at `proxy infil` time
- `recommended_clearance` — e.g. `commit`, `pr`, `worktree` — handler may override
- `recommended_comms` — `loud` or `quiet` — handler may override
- `linked_issues` — GitHub issue refs or URLs, optional

If the input is a seed, read it first and pre-fill what you can from its frontmatter + body. Only ask for fields that are missing or that the seed leaves ambiguous.

## Interview rules

- One question at a time. Don't batch.
- For each question, propose a recommended answer based on context (seed body, conversation, repo layout). The user accepts, edits, or rejects.
- If the user already ran `/grill-me` against the seed, much of the interview is already done — skim the conversation context for the answers and only ask for true gaps.
- Refuse to proceed if `target_repo` does not exist on disk (`test -d` must pass). Offer to create it or pick a different repo.
- Refuse to proceed if `acceptance_criteria` is vague ("works", "is done") — push for testable predicates.
- Refuse to proceed if `feedback_loops` are empty unless the user explicitly opts out with reason (docs-only changes, schema-only migrations, etc.).

## Output: v2 dossier-brief markdown

Write the dossier to `/tmp/proxy-brief-<slug>.md` with this exact shape:

```markdown
---
slug: <slug>
target_repo: <validated-absolute-path>
files_in_scope:
  - <glob>
  - <glob>
files_out_of_scope:
  - <glob>
  - <glob>
recommended_callsign: <preset-name-or-null>
recommended_clearance: <level-or-null>
recommended_comms: <loud|quiet|null>
acceptance_criteria:
  - <predicate>
  - <predicate>
feedback_loops:
  - <command>
  - <command>
linked_issues:
  - <ref-or-url>
briefed_by: claude-code-skill:brief
---

# <title>

<body>
```

Notes on shape:
- Lists are YAML arrays — `proxy brief` parses them into `jsonb` columns.
- Advisory fields may be set to `null` or omitted entirely; the daemon stores `NULL`.
- The H1 inside the body becomes the dossier `title`; everything after it becomes the dossier `body`.
- Do not include a `status:` field — the daemon sets `state='BRIEFED'` on import.

## Hand-off to the daemon

Once the file is written, invoke:

```bash
proxy brief <slug> --file /tmp/proxy-brief-<slug>.md
```

(The `--file` flag bypasses the interactive editor that `proxy brief <slug>` opens by default. If `proxy brief` later renames this flag, update this skill.)

`proxy brief` will:
1. Parse the frontmatter + body
2. Create a `dossiers` row with `state='BRIEFED'`
3. Delete the transient file at `/tmp/proxy-brief-<slug>.md`

Verify success:
```bash
proxy dossiers | grep <slug>
```

If the row appears, the brief succeeded. If `proxy brief` exits non-zero, do NOT delete the file yourself — show the error to the user, fix the markdown, and re-invoke.

## Promotion bookkeeping

If the input was a seed at `wiki/seeds/<slug>.md`, delete it after `proxy brief` succeeds:

```bash
git -C ~/projects/personal-nix rm wiki/seeds/<slug>.md
```

Do not commit on the user's behalf — leave that for them to bundle with related changes. Remind them: "I deleted the seed; commit `personal-nix` when you're ready."

If the input was conversation context (no seed), there is nothing to clean up.

## Confirm to user

Print a one-paragraph confirmation:
- Dossier slug + title + target_repo
- Recommended callsign / clearance / comms (or "none, handler decides at infil time")
- File deleted: `/tmp/proxy-brief-<slug>.md`
- Seed deleted: `wiki/seeds/<slug>.md` (if applicable)
- Next step: `proxy infil <callsign> --dossier <slug>` (suggest the recommended callsign if set)

## Why this is not `/wiki add work-requests`

`/wiki add work-requests` writes a v1 work-request markdown file into the wiki — a *capture* surface, frictionless, no daemon involvement. `/brief` writes a v2 dossier directly into the PROXY daemon's database via `proxy brief` — a *promotion* surface, high-friction interview, hands the work off to the orchestrator. The v1 work-request flow is being phased out as PROXY v2 takes over; new work should be briefed, not captured.

## Upstream

- `/wiki add seeds` — captures rough ideas
- `/grill-me` — sharpens a seed into a brief-ready spec (interview-only; does not write the dossier)

## Downstream

- `proxy brief <slug>` — daemon-side ingest (proxy-v2-08)
- `proxy infil <callsign> --dossier <slug>` — dispatches a loop on the dossier (proxy-v2-08)
