---
name: work-queue
description: Manage the personal work-request queue via the PROXY API (http://localhost:3000/api/work-requests). Create and list work items; execution is handled by `/tachikoma queue`. Triggers — `/work-queue`, `/work-queue list`, `/work-queue add`, `/work-queue add <target-repo>`, `/work-queue done <slug>`, or any natural-language request like "what's queued?", "add a work request", "create a work request", "list my queue", "mark this work request done".
---

# Work Queue

Thin manager for the PROXY work-request queue at `http://localhost:3000/api/work-requests`. Adds new items and tracks lifecycle (`open` → `grabbed` → `done`, with `needs-triage` as a quarantine state for repeatedly-failing items). Execution — running items and draining the queue — is handled entirely by `/tachikoma queue`.

The queue used to live in `~/projects/personal-nix/wiki/work-requests/*.md`. Those files have been migrated into the PROXY DB (slice 17) and archived under `wiki/work-requests/archived/`. **Do not read or write the markdown files** — they are historical.

## Prerequisite

PROXY must be running. If `curl -fsS http://localhost:3000/api/work-requests?limit=1` fails (connection refused or non-2xx), refuse with:

```
✗ PROXY API unreachable at http://localhost:3000
  → Start PROXY: cd ~/Projects/tachikoma-starter && docker compose up
```

Do not fall back to the filesystem.

## Invocation

| Form | Behavior |
|---|---|
| `/work-queue` (no args) | Equivalent to `/work-queue list`. |
| `/work-queue list` | Show all entries in a flat table. Flag readiness issues and staleness inline. |
| `/work-queue add` | Grill the user for a new work item, then POST it to PROXY. |
| `/work-queue add <target-repo>` | Same but skip the repo question. |
| `/work-queue done <slug>` | Soft-delete the work_request in PROXY. Refuses `needs-triage` items — see Status below. |
| `/work-queue help` | Display the user guide in chat. |

`<slug>` matches by substring against the `slug` field of work_requests returned by `GET /api/work-requests`. Refuse if no match or ambiguous; list candidates.

## DB fields

Each work_request is a row in the PROXY `work_requests` table. Fields written and read by this skill:

| Field | Type | Source | Purpose |
|---|---|---|---|
| `id` | UUID | DB | Primary key; required for PATCH/DELETE. |
| `slug` | kebab-case string | this skill (`add`), migration | Short stable identifier. Unique. Substring-matched by `done`. |
| `title` | string | this skill (`add`) | Human-readable title. |
| `description` | string (markdown body) | this skill (`add`) | Body content: Goal, Files in scope, Files out of scope, Stop condition, Feedback loops, Quality bar. |
| `status` | `open` \| `grabbed` \| `done` \| `needs-triage` | server (state machine via `/api/runs/*`) | Lifecycle state. See state machine below. |
| `targetRepo` | path string (may use `~`) | this skill (`add`) | Where tachikoma runs. Validated for existence on `list` and `add`. |
| `githubIssue` | string `org/repo#N` or `null` | this skill (`add`), `/tachikoma` (auto-create) | Links to a GitHub issue. Null = not linked. |
| `config.failure_count` | integer (≥ 0) | `/tachikoma queue` only | Cumulative failure count. Read-only here. |
| `createdAt` / `updatedAt` | ISO timestamp | DB | Bumped on every update. |

**State machine.** This skill does **not** flip `status` directly. State transitions are owned by:
- `POST /api/runs` (started run) — flips `open → grabbed`
- `POST /api/runs/[id]/events` (loop reports state) — flips `grabbed → done`, `grabbed → open` (retry), or `grabbed → needs-triage`

The `done` command in this skill is a **soft delete** (`DELETE /api/work-requests/[id]`) — it removes the item from the queue view. Status text is preserved on the row but the item won't appear in `list`.

`needs-triage` is a terminal-until-manual-reset state. This skill refuses to mark-done a `needs-triage` item — the human must inspect failures in the PROXY UI and either re-open the row (via PROXY's UI / PATCH) or accept the soft-delete by issuing `/work-queue done <slug>` after acknowledging the quarantine in the UI.

## add flow

**Purpose:** capture a new work item from the user and POST it to PROXY as a well-formed, tachikoma-ready work_request. Uses a relentless one-at-a-time grill to ensure every required field is specific, measurable, and unambiguous.

**Step 1 — Preflight**

Verify PROXY is reachable (see Prerequisite). Refuse if not.

**Step 2 — Target repo**

If `<target-repo>` was not passed on the command line, ask for it. Expand `~`, verify the path exists on disk — refuse if it doesn't.

**Step 3 — Explore the repo**

Before asking any grill questions, read the target repo to gather context:
- Check for `package.json`, `Makefile`, `justfile`, `pyproject.toml`, etc. to auto-detect available test/lint/typecheck commands.
- Note key directories and file patterns to inform scope recommendations.
- Do this silently — don't narrate the exploration. Use findings to pre-fill recommended answers in the grill.

**Step 4 — Grill the user (one question at a time)**

Interview the user relentlessly until all required fields are resolved. Walk through each field in order. For each question, provide a concrete recommended answer (derived from exploration and what the user has said) before asking. Only move to the next field once the current one is answered. Do not ask multiple questions at once.

Fields to resolve, in order:

1. **Slug** — short kebab-case identifier (e.g. `fix-vital-age`, `refactor-auth-middleware`). Recommend one based on the task description. Before accepting, `GET /api/work-requests?limit=100` and walk pages if needed to verify the slug isn't already in use. Refuse if a conflict exists.
2. **Title** — human-readable title for the H1 in the body. Recommend title-cased slug.
3. **Description summary** — one-sentence summary of the work (optional but encouraged). Recommend based on what the user has described so far.
4. **Goal** — the "Tachikoma is done when…" statement. Must be specific and end-state-focused. Push back on vague goals like "improve the code" — keep grilling until it's concrete.
5. **Files in scope** — globs or paths tachikoma may read and modify. Recommend based on repo exploration.
6. **Files out of scope** — globs or paths tachikoma must not touch. Recommend obvious exclusions (e.g. lock files, generated assets, unrelated modules).
7. **Stop condition** — concrete acceptance criteria (readable as a checklist). Must be independently verifiable without running the app. Recommend based on goal.
8. **Feedback loops** — commands to verify correctness: typecheck, tests, lint. Recommend commands discovered from repo exploration (e.g. `npx tsc --noEmit`, `npm test`). Confirm with user before accepting.
9. **Quality bar** — `prototype`, `production`, or `library`. Recommend based on the target repo and task nature. Explain the tradeoff if the user is unsure: prototype = fast+rough, production = correct+polished, library = API stability matters.
10. **GitHub issue link** (optional) — Ask: *"Is this work_request linked to an existing GitHub issue? (e.g. `MioMarker/healthbite#22`, or skip)"*. Validate format if provided (`org/repo#N`). Send as `githubIssue` in the POST body; omit if skipped.

**Step 5 — POST to PROXY**

Render the body content using the same section structure as the old work-request template (preserves parity with migrated rows):

```markdown
# {title}

{description_summary}

## Goal

{goal}

## Files in scope

{files_in_scope}

## Files out of scope

{files_out_of_scope}

## Stop condition

{stop_condition}

## Feedback loops

{feedback_loops}

## Quality bar

{quality_bar}
```

Then call:

```
POST http://localhost:3000/api/work-requests
Content-Type: application/json

{
  "slug": "<slug>",
  "title": "<title>",
  "description": "<rendered markdown body>",
  "targetRepo": "<target_repo>",
  "githubIssue": "<org/repo#N>" | null
}
```

The server sets `status: "open"` and `id`. Handle responses:
- `201` — success. Capture `id` and `slug` for the confirmation message.
- `409 slug already in use` — back up to Step 4 field 1, ask for a different slug.
- `400 invalid input` — show the validation details to the user, fix the offending field, retry.

**Step 6 — Confirm**

```
Created: <slug> (id: <uuid>)
  status:      open
  target:      <targetRepo>
  quality bar: <quality_bar>

Run `/tachikoma queue <slug>` to run it now, or `/work-queue list` to see the queue.
```

## list flow

1. Preflight: verify PROXY is reachable.
2. `GET http://localhost:3000/api/work-requests?limit=100&offset=0`. If `total > limit`, paginate by bumping `offset` until `items.length + offset >= total`. Concatenate `items`.
3. Filter `items` client-side: keep `status` ∈ `{open, grabbed, needs-triage}`. Hide `done` (the row is soft-deleted from the queue view; in case any leak through, drop them).
4. For each item, validate readiness:
   - `targetRepo` field present (always true — server validates)
   - `targetRepo` path exists on disk (expand `~`)

   Mark unready entries inline with the failing reason.
5. For each `needs-triage` entry, `GET /api/work-requests/<id>` to read `config.failure_count` (default 0 if missing). Show it so the user can see how many times it failed before quarantine.
6. Group by `status` in this order: `open` → `grabbed` → `needs-triage`. Within each group, sort by `createdAt` ascending (oldest first).
7. Output format:

   ```
   ## Work Queue

   | Slug | Target | Status | Notes |
   |---|---|---|---|
   | fix-vital-age | ~/projects/platform | open | READY |
   | refactor-auth-middleware | ~/projects/platform | open | NOT READY: targetRepo missing |
   | wire-up-feature-flags | ~/projects/platform | grabbed | since 2026-05-08 |
   | flaky-cron-cleanup | ~/projects/platform | needs-triage | 2 failures · since 2026-05-09 |
   ```

   - Use a single flat table — all statuses in one view, no section breaks.
   - Status column values: `open`, `grabbed`, `needs-triage`.
   - Notes column: for `open` show `READY` or `NOT READY: <reason>`; for `grabbed` show `since <updatedAt date>` — append `⚠ abandoned? (>3 days)` if `updatedAt` is more than 3 days ago; for `needs-triage` show `<N> failures · since <updatedAt date>`.
   - Keep total output under ~30 lines.

## done flow

Completed (or hand-finished) work-requests are soft-deleted in PROXY. The row is preserved in the DB (audit trail, transitions, runs) but is excluded from the queue view.

1. Preflight: verify PROXY is reachable.
2. Resolve slug: `GET /api/work-requests?limit=100` (paginate if needed). Substring-match user-provided `<slug>` against the `slug` field of each item. Refuse on no-match or ambiguity.
3. Read the matched item's `status`. Route:
   - `needs-triage` — **refuse**. Fetch full row (`GET /api/work-requests/<id>`) to read `config.failure_count`. Print: *"`<slug>` is `needs-triage` (failure_count: N). Inspect the failure log in the PROXY UI at http://localhost:3000, then either reset it from the UI or confirm by running `/work-queue done <slug> --force` (TODO: not implemented in this slice). Don't auto-delete — needs-triage exists precisely to force human review."*
   - `open` or `grabbed` — proceed.
4. Soft-delete: `DELETE http://localhost:3000/api/work-requests/<id>`.
5. Confirm: `<slug> deleted. (was <previous status>)`

## Failure modes

Error format: `✗ <what went wrong>\n  → <exact next step>`

- **PROXY API unreachable** — `✗ PROXY API unreachable at http://localhost:3000\n  → Start PROXY: cd ~/Projects/tachikoma-starter && docker compose up`
- **API returns 5xx** — `✗ PROXY returned <status>: <body>\n  → Check PROXY logs (docker compose logs web) and retry.`
- **`targetRepo` path doesn't exist on disk** — mark as `NOT READY: targetRepo <path> not found` in `list`; refuse to `add`.
- **Slug already exists (add)** — `✗ slug "<slug>" already in use.\n  → Choose a different slug, or edit the existing work_request in the PROXY UI.`
- **Slug ambiguous (done)** — `✗ Ambiguous slug — matches: <slug1>, <slug2>.\n  → Retry with a more specific slug.`
- **Slug not found (done)** — `✗ No work_request matching "<slug>".\n  → /work-queue list`
- **Item is `needs-triage`** — refuse `done` with: `✗ <slug> is needs-triage (failure_count: N). Inspect failures in the PROXY UI before soft-deleting.`
- **No open + ready entries** — `✗ No open + ready items.\n  → /work-queue list  to see what's stuck or quarantined.`

## Privacy

PROXY runs locally; the DB is on your laptop. But work_requests can be linked to GitHub issues — anything you put in `githubIssue` or `title` is visible to whoever can see that issue. Don't manage RelyMD work via this queue unless the linked issue is in a private RelyMD repo.

## Help

**When invoked as `/work-queue help`:** display the following user guide in chat.

---

## Work Queue — User Guide

Manages a personal queue of work items in the PROXY DB (http://localhost:3000). This skill handles queue state; execution is handled by `/tachikoma queue`.

### Commands

| Command | What it does |
|---|---|
| `/work-queue` or `/work-queue list` | Show all queued items in a flat table |
| `/work-queue add` | Create a new work item (guided interview) |
| `/work-queue add <repo-path>` | Same, skip the repo question |
| `/work-queue done <slug>` | Soft-delete the work_request (marks it complete) |
| `/work-queue help` | Show this guide |

### Status lifecycle

```
open → grabbed → done
```

Items that fail twice in a queue drain are quarantined as `needs-triage`. Inspect them in the PROXY UI and re-open from there to re-queue. To discard a `needs-triage` item entirely, run `/work-queue done <slug>` only after reviewing the failure log.

### Example workflow

```
1. /work-queue add ~/projects/platform    — capture a task (guided)
2. /tachikoma queue <slug>               — run it (or /tachikoma queue to drain all)
3. /work-queue done <slug>              — called automatically on success; run manually if needed
```

### Queue drain

A "drain" is one worker against the shared PROXY queue. The worker pops the next `open + ready` item, runs the full tachikoma lifecycle on it, then pops the next.

- `/tachikoma queue` — 1 worker, foreground in current session
- `/tachikoma queue <N>` — N background workers in parallel (N ≥ 2). They share the queue and partition the work via the atomic `open` → `grabbed` flip done server-side by `POST /api/runs`. Typical overnight: `/tachikoma queue 3 -C`.
- `/tachikoma queue <slug>` — run a single specific item

Add `--caffeinated` (alias `-C`) to prevent macOS sleep during overnight runs.

### Privacy

PROXY is local; the DB is on your laptop. Don't link work_requests to public GitHub issues if the content is RelyMD-confidential.
