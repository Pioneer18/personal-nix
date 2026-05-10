---
name: work-queue
description: Manage the personal work-request queue at `~/projects/personal-nix/wiki/work-requests/`. List queued items, grab the next open one and prep it for a ralph launch, mark items done after merge. Triggers — `/work-queue`, `/work-queue list`, `/work-queue grab`, `/work-queue grab <slug>`, `/work-queue done <slug>`, or any natural-language request like "what's queued?", "start the next work request", "grab the next one for ralph", "mark this work request done".
---

# Work Queue

Thin manager for `~/projects/personal-nix/wiki/work-requests/`. Lists open items, walks you into a `/ralph` launch with the body pre-loaded, tracks lifecycle (`open` → `grabbed` → `done`).

This skill does NOT launch ralph itself — Claude Code skills can't programmatically invoke other skills. The skill's job is queue-state management + seeding the next conversation turn so you only have to type `/ralph` and paste the seed.

## Invocation

| Form | Behavior |
|---|---|
| `/work-queue` (no args) | Equivalent to `/work-queue list`. |
| `/work-queue list` | Show all entries grouped by status. Flag readiness issues inline. |
| `/work-queue grab` | Pick the next open + ready entry; if multiple, picker. Bumps `status: grabbed`. Prints the ralph seed block. |
| `/work-queue grab <slug>` | Grab a specific slug (substring match against filename). |
| `/work-queue done <slug>` | Flip `status: grabbed` → `done`. Bumps `last_updated`. |

`<slug>` matches by substring against `wiki/work-requests/*.md` filenames. Refuse if no match or ambiguous; list candidates.

## list flow

1. Glob `~/projects/personal-nix/wiki/work-requests/*.md` (skip `.gitkeep` and any non-`.md`).
2. Parse frontmatter on each. If frontmatter is malformed, skip with a warning — don't crash the whole list.
3. Group by `status`: `open` → `grabbed` → `done`.
4. For each `open` entry, validate readiness:
   - `target_repo` field present
   - `target_repo` path exists on disk (expand `~`)
   - body length > 50 chars (avoid one-line stubs that ralph can't seed from)

   Mark unready entries inline with the failing reason.
5. Output format:

   ```
   Open (2)
     fix-vital-age           — ~/projects/platform                       READY
     refactor-auth-middleware — target_repo missing                       NOT READY

   Grabbed (1)
     wire-up-feature-flags    — ~/projects/platform                       (since 2026-05-08)

   Done (5)
     [...older entries collapsed; show count only unless verbose...]
   ```

   Keep total output under ~30 lines. If there are more than 5 done entries, collapse to a count.

## grab flow

1. Glob open work-requests, filter for ready (target_repo exists, body > 50 chars).
2. Pick:
   - If user passed `<slug>`: substring match against filenames; refuse on no-match or ambiguity.
   - Else if exactly one ready: that one.
   - Else if zero ready: tell user "no open + ready items; `/work-queue list` to see what's stuck." Exit.
   - Else: present picker via AskUserQuestion (show slug + target_repo + first line of body).
3. Read full body (everything below the closing `---` of frontmatter).
4. **Update the file in place**: change `status: open` → `status: grabbed`, set `last_updated` to today's date. Use Edit tool — preserve all other frontmatter and body verbatim.
5. Print the seed block:

   ```
   Grabbed: <slug>
   Target:  <target_repo>

   Next steps:
     1. cd <target_repo>
     2. /ralph
     3. When ralph's grill asks for goal / files-in-scope / stop-condition,
        use the body below as your source.
     4. After ralph launches in --afk and the work merges:
        /work-queue done <slug>

   --- work-request body (verbatim) ---
   <body>
   ---
   ```

   Do NOT auto-cd or auto-invoke ralph. The user runs those.

## done flow

1. Resolve slug: substring match against `wiki/work-requests/*.md` filenames. Refuse on no-match or ambiguity.
2. Read frontmatter. If `status` is already `done`, tell user and exit (no-op).
3. Update file: `status: <current>` → `status: done`, bump `last_updated`.
4. Confirm: `<slug> marked done. (was <previous status>)`

## Failure modes

- **`wiki/work-requests/` missing** — tell user the personal-nix repo may be out of sync; do not auto-create. (The wiki skill is supposed to maintain this.)
- **Frontmatter malformed in an entry** — skip with a warning; show which file. Don't crash the command.
- **`target_repo` path doesn't exist on disk** — mark as not-ready in `list`; refuse to grab.
- **Slug ambiguous** — list candidates, refuse to act. User retries with a more specific slug.
- **No open + ready entries** — empty queue. Suggest `/work-queue list` to see if any are stuck on readiness.

## Privacy

Same constraints as the wiki itself — `personal-nix` is a public GitHub repo. Don't manage RelyMD work via this queue; that belongs in a private mechanism (GitHub issue, internal tracker, or auto-memory).

## What this skill does NOT do (yet)

- **Launch ralph.** Skills can't invoke other skills. This skill prepares the launch and prints the seed; you type `/ralph`.
- **Concurrent batch launch.** Single-item grab only. Multi-launch was scoped out — most queues are <5 items and grilling each one is the right discipline.
- **Auto status updates on merge.** No webhook, no PR-watcher. You run `/work-queue done <slug>` after merge. If that friction adds up, we can build a `/ralph done` hook that also bumps queue status.
- **Errand-flavored items.** Non-ralph agent tasks (browser automation, filesystem errands, etc.) live in `wiki/inbox/` with tag `errand` for now. If those accumulate (≥3), promote `errands/` into the wiki vocabulary and write its own launcher.
