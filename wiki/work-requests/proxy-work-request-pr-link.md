---
status: open
priority: 2
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-14
---

# PROXY — work_request ↔ GitHub PR link + auto-done sync

Add explicit GitHub PR linkage to `work_requests` so externally-created PRs (dev team, manual workflow) can flip the work-queue row to `done` automatically when merged. Keeps PROXY usable without GitHub (local-only rows just don't set the field), while letting GitHub-tracked work sync state honestly. Replaces the bug surface where work created outside the tachikoma flow stays `open` forever even after a PR merges.

## Why now

2026-05-14: `plrm-1222-edit-feature` sat at `status=open` in the DB after the dev team opened + waited on a PR for it. The work-queue had no mechanism to know an external PR existed for that slug, so the row never advanced. Manual `/work-queue done <slug>` is the only path today for non-tachikoma work — easy to forget, doesn't scale across a queue of dozens.

The two alternatives both have worse trade-offs:
- **Slug-scan cron** (query GH for any merged PR matching `feat/<slug>` or with slug in title) — fragile, name-collision risk, makes GH a hard dependency.
- **Manual-only** — what we have today; the bug surface this slice is closing.

## Goal

A `work_requests` row can carry an optional `github_pr` link. When set, a daemon-side poller (later: webhook) syncs that row's status with the PR's state — `done` when the PR merges or closes. Rows without `github_pr` retain today's manual lifecycle. Tachikoma's existing `ship phase` continues to auto-populate `github_issue` (and `github_pr` once available), so tachikoma-driven runs get the new behavior for free.

## Files in scope

- `daemon/migrations/<YYYYMMDDHHMMSS>_work_requests_github_pr.sql` (new) — `ALTER TABLE work_requests ADD COLUMN github_pr text;`
- `daemon/src/work_requests/mod.rs` (or wherever the WorkRequest struct lives) — add `github_pr: Option<String>`
- `daemon/src/api/work_requests.rs` — extend POST/PATCH to accept and write `github_pr`; extend GET to return it
- `daemon/src/cli/queue.rs` — new subcommand `proxy queue link <slug> <pr-url-or-org/repo#N>` that PATCHes `github_pr`
- `daemon/src/queue/pr_sync.rs` (new) — poller module: every 5 min, for each row with `github_pr` set and `status NOT IN (done, needs-triage)`, run `gh pr view <pr> --json state,mergedAt` (or use octocrab if `gh` shell-out feels wrong); flip `status` to `done` on `MERGED` or `CLOSED`
- `daemon/src/main.rs` — wire pr_sync into the daemon's tick loop (sibling of sensor sampling cadence)
- `apps/web/src/lib/queue/types.ts` + relevant API route handlers — surface `github_pr` in the list view
- `apps/web/app/work-requests/page.tsx` — show the link as a clickable PR badge per row
- `~/.claude/skills/tachikoma/SKILL.md` — ship phase Step 6 should also `proxy queue link <slug> <pr-url>` after PR creation, so tachikoma-shipped rows get the link populated alongside `github_issue`
- `~/.claude/skills/work-queue/SKILL.md` — document the new field, the `link` subcommand, and the auto-done behavior

## Files out of scope

- GitHub webhook receiver — defer to a follow-on slice. The poller is the v1; webhook is the optimization.
- PR-merge → branch cleanup automation — separate concern.
- Multiple PRs per work_request — v1 is one PR per row. If a work-request spawned multiple PRs in the wild, last-write-wins via `proxy queue link`.
- Slug-from-PR-body parser (e.g. reading `<!-- work-request: <slug> -->` markers from PR descriptions to auto-link without explicit CLI) — interesting but deferred.

## Stop condition

- [ ] DB migration adds `github_pr text` nullable column to `work_requests`; existing rows stay NULL
- [ ] `WorkRequest` struct + serde JSON include `github_pr` round-tripped
- [ ] `POST /api/work-requests` accepts optional `github_pr` field; `PATCH /api/work-requests/<id>` can set it
- [ ] `proxy queue link <slug> <ref>` CLI works — accepts both full URL (`https://github.com/org/repo/pull/N`) and shorthand (`org/repo#N`)
- [ ] Refuses to link if work_request status is already `done` or `needs-triage` (or warns + requires `--force`)
- [ ] Poller module ticks every 5 min (configurable via `proxy.toml` `[pr_sync] poll_period_sec`)
- [ ] Each tick: query `work_requests` for rows where `github_pr IS NOT NULL AND status NOT IN ('done', 'needs-triage')`; for each, fetch PR state; flip `status='done'` on `MERGED` or `CLOSED`
- [ ] Status flip emits a `system_recommendations` row of kind `work_request_auto_closed` for audit
- [ ] Web `/work-requests` page shows PR link as a clickable badge (open in new tab) per row that has one
- [ ] Tachikoma `ship phase` Step 6 calls `proxy queue link <slug> <pr-url>` after PR creation, populating the field for tachikoma-driven rows automatically
- [ ] `work-queue` SKILL.md documents the new field + subcommand + auto-done behavior; explicitly notes that rows without `github_pr` retain today's manual lifecycle
- [ ] `cargo test` covers: link parsing (URL + shorthand), poller skips non-linked rows, poller flips on MERGED, poller flips on CLOSED, poller skips already-`done` rows, audit row emission
- [ ] `cargo clippy --all-targets -- -D warnings` clean

## Feedback loops

- `cargo test`
- `cargo clippy --all-targets -- -D warnings`
- Manual end-to-end: create a work_request, run `proxy queue link <slug> <some-open-PR-URL>`, merge the PR on GitHub, wait <5 min, verify row flips to `done` + audit row appears
- Manual: create a row without `github_pr`, verify poller doesn't touch it
- Manual: tachikoma a small slice, verify ship phase populates `github_pr` automatically

## Quality bar

production

## Design notes

- **Poller vs webhook.** v1 is a poller because it's stateless, local, and works behind firewalls / without exposing PROXY to the internet. Webhook is v2 — same flip logic, just triggered by an event handler at `/api/github/webhook` instead of a cron tick. Design the flip function so it's reusable across both paths.
- **GH access.** Poller uses the `gh` CLI on the daemon's PATH (already required for other PROXY paths). If `gh` is absent, log a warning and skip; the slice's correctness shouldn't depend on it being installed (graceful degradation — rows just stay open, as they would today).
- **Auth scope.** Polling uses whatever `gh auth status` says — user's token. If they hit rate limits on a heavy queue, document the trade-off and recommend a personal access token with appropriate scope.
- **Race with manual `/work-queue done`.** If the user marks a linked row done before the poller catches the merge, no conflict — poller's UPDATE has `WHERE status NOT IN ('done', 'needs-triage')` guard.
- **Closed-without-merge case.** A PR that closes without merging (e.g. abandoned) is still a terminal state for the work — flip to `done` regardless. If the user wants to re-open, they can manually re-set `status='open'`.
- **Backfill.** Existing rows have `github_pr=NULL`. No backfill required — anyone who wants old rows linked can run `proxy queue link <slug> <url>` retroactively.

## Recommended Tachikoma cap

`--afk 8` — DB migration + new poller module + new CLI verb + web UI tweak + skill doc updates + tests. Mid-size.
