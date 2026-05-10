---
name: work-queue
description: Manage the personal work-request queue at `~/projects/personal-nix/wiki/work-requests/`. Create, list, grab, and mark items done. Triggers — `/work-queue`, `/work-queue list`, `/work-queue add`, `/work-queue add <target-repo>`, `/work-queue grab`, `/work-queue grab <slug>`, `/work-queue done <slug>`, or any natural-language request like "what's queued?", "add a work request", "create a work request", "start the next work request", "grab the next one for tachikoma", "mark this work request done".
---

# Work Queue

Thin manager for `~/projects/personal-nix/wiki/work-requests/`. Lists open items, walks you into a `/tachikoma` launch with the body pre-loaded, tracks lifecycle (`open` → `grabbed` → `done`, with `needs-triage` as a quarantine state for repeatedly-failing items).

This skill does NOT launch tachikoma itself — Claude Code skills can't programmatically invoke other skills. The skill's job is queue-state management + seeding the next conversation turn so you only have to type `/tachikoma` and paste the seed.

## Invocation

| Form | Behavior |
|---|---|
| `/work-queue` (no args) | Equivalent to `/work-queue list`. |
| `/work-queue list` | Show all entries grouped by status. Flag readiness issues inline. |
| `/work-queue add` | Grill the user for a new work item, then write it as a structured work-request file. |
| `/work-queue add <target-repo>` | Same but skip the repo question. |
| `/work-queue grab` | Pick the next open + ready entry; if multiple, picker. Bumps `status: grabbed`. Prints the tachikoma seed block. |
| `/work-queue grab <slug>` | Grab a specific slug (substring match against filename). |
| `/work-queue done <slug>` | Flip `status: grabbed` → `done`. Bumps `last_updated`. Refuses `needs-triage` items — see Frontmatter below. |

`<slug>` matches by substring against `wiki/work-requests/*.md` filenames. Refuse if no match or ambiguous; list candidates.

## Frontmatter

Each work-request file carries a YAML frontmatter block. Fields written and read by this skill:

| Field | Type | Written by | Purpose |
|---|---|---|---|
| `status` | `open` \| `grabbed` \| `done` \| `needs-triage` | this skill, `/tachikoma queue` | Lifecycle state. See state machine below. |
| `target_repo` | path string (may use `~`) | this skill (`add`) | Where tachikoma runs. Validated for existence on `list` and `grab`. |
| `failure_count` | integer (≥ 0; missing = 0) | `/tachikoma queue` only | Cumulative failure count from queue-drain runs. Bumped on any failure (cap-twice, error, stopped, blocker-exit, phase6-conflict). Never decremented. |
| `last_updated` | ISO date (`YYYY-MM-DD`) | this skill, `/tachikoma queue` | Bumped on every state change. |

**State machine.** This skill drives `open → grabbed` (on `grab`) and `grabbed → done` (on `done`). `/tachikoma queue` drives the remaining transitions:
- `grabbed → open` on a single failure with `failure_count < 2` after bump (retryable).
- `grabbed → needs-triage` on a failure with `failure_count ≥ 2` after bump (quarantined).
- `grabbed → done` if `/tachikoma queue` completes Phase 6 successfully.

`needs-triage` is a terminal-until-manual-reset state. This skill refuses to grab or mark-done a `needs-triage` item — the human must edit the file (typically resetting `status: open` and reviewing the appended `## Queue Failures` log) before it re-enters the queue.

## add flow

**Purpose:** capture a new work item from the user and store it as a well-formed, tachikoma-ready work-request file. Uses a relentless one-at-a-time grill to ensure every required field is specific, measurable, and unambiguous.

**Step 1 — Target repo**

If `<target-repo>` was not passed on the command line, ask for it. Expand `~`, verify the path exists on disk — refuse if it doesn't.

**Step 2 — Explore the repo**

Before asking any grill questions, read the target repo to gather context:
- Check for `package.json`, `Makefile`, `justfile`, `pyproject.toml`, etc. to auto-detect available test/lint/typecheck commands.
- Note key directories and file patterns to inform scope recommendations.
- Do this silently — don't narrate the exploration. Use findings to pre-fill recommended answers in the grill.

**Step 3 — Grill the user (one question at a time)**

Interview the user relentlessly until all required fields are resolved. Walk through each field in order. For each question, provide a concrete recommended answer (derived from exploration and what the user has said) before asking. Only move to the next field once the current one is answered. Do not ask multiple questions at once.

Fields to resolve, in order:

1. **Slug** — short kebab-case filename (e.g. `fix-vital-age`, `refactor-auth-middleware`). Recommend one based on the task description. Refuse if a file with that name already exists in `wiki/work-requests/`.
2. **Title** — human-readable title for the H1 in the file. Recommend title-cased slug.
3. **Description** — one-sentence summary of the work (optional but encouraged). Recommend based on what the user has described so far.
4. **Goal** — the "Tachikoma is done when…" statement. Must be specific and end-state-focused. Push back on vague goals like "improve the code" — keep grilling until it's concrete.
5. **Files in scope** — globs or paths tachikoma may read and modify. Recommend based on repo exploration.
6. **Files out of scope** — globs or paths tachikoma must not touch. Recommend obvious exclusions (e.g. lock files, generated assets, unrelated modules).
7. **Stop condition** — concrete acceptance criteria (readable as a checklist). Must be independently verifiable without running the app. Recommend based on goal.
8. **Feedback loops** — commands to verify correctness: typecheck, tests, lint. Recommend commands discovered from repo exploration (e.g. `npx tsc --noEmit`, `npm test`). Confirm with user before accepting.
9. **Quality bar** — `prototype`, `production`, or `library`. Recommend based on the target repo and task nature. Explain the tradeoff if the user is unsure: prototype = fast+rough, production = correct+polished, library = API stability matters.

**Step 4 — Write the file**

Once all fields are resolved, write `~/projects/personal-nix/wiki/work-requests/<slug>.md` using the template at `skills/work-queue/work-request.tmpl`. Substitute all `{{PLACEHOLDER}}` values. Set `status: open` and `last_updated` to today's ISO date.

**Step 5 — Confirm**

```
Created: wiki/work-requests/<slug>.md
  status:      open
  target:      <target_repo>
  quality bar: <quality_bar>

Run `/work-queue grab <slug>` to prep it for tachikoma, or `/work-queue list` to see the queue.
```

## list flow

1. Glob `~/projects/personal-nix/wiki/work-requests/*.md` (skip `.gitkeep` and any non-`.md`).
2. Parse frontmatter on each. If frontmatter is malformed, skip with a warning — don't crash the whole list.
3. Group by `status` in this order: `open` → `grabbed` → `needs-triage`. Any unrecognized status value (including `done` — stale file from before the delete-on-done change) goes in a trailing `Unknown` group with a warning; tell the user they can delete those files.
4. For each `open` entry, validate readiness:
   - `target_repo` field present
   - `target_repo` path exists on disk (expand `~`)
   - body length > 50 chars (avoid one-line stubs that tachikoma can't seed from)

   Mark unready entries inline with the failing reason.
5. For each `needs-triage` entry, show `failure_count` (default 0 if missing) so the user can see how many times it failed before quarantine.
6. Output format:

   ```
   Open (2)
     fix-vital-age           — ~/projects/platform                       READY
     refactor-auth-middleware — target_repo missing                       NOT READY

   Grabbed (1)
     wire-up-feature-flags    — ~/projects/platform                       (since 2026-05-08)

   Needs Triage (1)
     flaky-cron-cleanup       — ~/projects/platform   2 failures          (since 2026-05-09)
   ```

   Keep total output under ~30 lines. Always show every `needs-triage` entry in full — they require human attention. Done items don't appear (files are deleted on done).

## grab flow

1. Glob work-requests with `status: open`, filter for ready:
   - `target_repo` field present and path exists on disk
   - body length > 50 chars
   - `failure_count < 2` (defensive — items that failed twice should already be `needs-triage`, but a manually-edited file might be `open` with a high count)

   Items with `status: needs-triage` are excluded entirely (they're a separate state, not a readiness sub-condition).
2. Pick:
   - If user passed `<slug>`: substring match against filenames. Refuse on no-match or ambiguity. **Refuse with a pointer to the failure log if the matched item has `status: needs-triage`** — tell the user to inspect `## Queue Failures` and reset `status: open` manually before grabbing.
   - Else if exactly one ready: that one.
   - Else if zero ready: tell user "no open + ready items; `/work-queue list` to see what's stuck." Exit.
   - Else: present picker via AskUserQuestion (show slug + target_repo + first line of body).
3. Read full body (everything below the closing `---` of frontmatter).
4. **Update the file in place**: change `status: open` → `status: grabbed`, set `last_updated` to today's date. Use Edit tool — preserve all other frontmatter (including `failure_count`) and body verbatim.
5. Print the seed block:

   ```
   Grabbed: <slug>
   Target:  <target_repo>

   Next steps:
     1. cd <target_repo>
     2. /tachikoma
     3. When tachikoma's grill asks for goal / files-in-scope / stop-condition,
        use the body below as your source.
     4. After tachikoma launches in --afk and the work merges:
        /work-queue done <slug>

   --- work-request body (verbatim) ---
   <body>
   ---
   ```

   Do NOT auto-cd or auto-invoke tachikoma. The user runs those.

## done flow

Completed work-request files have no retention value — the goal/scope/stop-condition all live in the commit. Delete, don't archive.

1. Resolve slug: substring match against `wiki/work-requests/*.md` filenames. Refuse on no-match or ambiguity.
2. Read frontmatter. Route on current `status`:
   - `needs-triage` — **refuse**. Print: *"`<slug>` is `needs-triage` (failure_count: N). Inspect `## Queue Failures` in the file, then reset `status: open` manually if you want to re-queue it, or delete the file directly if you've finished it by hand."* Don't auto-delete — `needs-triage` exists precisely to force human review.
   - `open` or `grabbed` — proceed.
3. Delete the file: `rm ~/projects/personal-nix/wiki/work-requests/<slug>.md`.
4. Confirm: `<slug> deleted. (was <previous status>)`

## Failure modes

- **`wiki/work-requests/` missing** — tell user the personal-nix repo may be out of sync; do not auto-create. (The wiki skill is supposed to maintain this.)
- **Frontmatter malformed in an entry** — skip with a warning; show which file. Don't crash the command.
- **`target_repo` path doesn't exist on disk** — mark as not-ready in `list`; refuse to grab or add.
- **Slug already exists (add)** — refuse and show the existing file. User picks a different slug or edits the existing one.
- **Slug ambiguous (grab/done)** — list candidates, refuse to act. User retries with a more specific slug.
- **Item is `needs-triage`** — refuse `grab` and `done` with a pointer to `## Queue Failures` in the file. Human resets `status: open` (or sets `done` directly if they finished it by hand) after reading the failure log. Do not auto-transition.
- **No open + ready entries** — empty queue. Suggest `/work-queue list` to see if any are stuck on readiness or quarantined as `needs-triage`.

## Privacy

Same constraints as the wiki itself — `personal-nix` is a public GitHub repo. Don't manage RelyMD work via this queue; that belongs in a private mechanism (GitHub issue, internal tracker, or auto-memory).

## What this skill does NOT do (yet)

- **Launch tachikoma.** Skills can't invoke other skills. This skill prepares the launch and prints the seed; you type `/tachikoma`.
- **Concurrent batch launch.** Single-item grab only. Multi-launch was scoped out — most queues are <5 items and grilling each one is the right discipline.
- **Auto status updates on merge.** Tachikoma's Phase 6 Step 9 calls `/work-queue done <slug>` automatically when the branch matches a work-request slug. For non-tachikoma work or manual merges, run `/work-queue done <slug>` yourself.
- **Errand-flavored items.** Non-tachikoma agent tasks (browser automation, filesystem errands, etc.) live in `wiki/inbox/` with tag `errand` for now. If those accumulate (≥3), promote `errands/` into the wiki vocabulary and write its own launcher.
