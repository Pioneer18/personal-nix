---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
grabbed_at: 2026-05-11
---

# PROXY — Per-Repo Config Management

DB schema and UI for storing per-repo PROXY configurations privately on this machine. Config covers Jira project, quality bar, branch naming, feedback loops, file scoping, PAT reference, and more. Config is never committed to any repo.

## Goal

User can open PROXY UI, navigate to Settings > Repos, add a repo path (e.g. `~/Projects/platform`) and configure all behavior fields. Config is stored in the DB and is invisible to anyone else working in that repo.

## Files in scope

- `apps/web/src/app/settings/repos/**`
- `apps/web/src/app/api/repo-configs/**`
- DB migration for `repo_configs` table

## Files out of scope

- PAT storage (Slice 7)
- Jira API calls (Slice 9)

## v2 amendment (2026-05-11) — must follow up even if status:done

Add three new fields per `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` § 5 + § 10:
- `memory_limit_mb` (int, nullable — populated by first-run wizard) — per-loop hard memory cap passed as `docker run --memory`
- `max_concurrent_per_repo` (int, default 2) — replaces `max_concurrent_loops`; per-repo concurrency cap
- `backend` (text, default `"local"`) — `"local"` only in v1; `"remote"` reserved for the future remote backend (see `~/projects/personal-nix/wiki/decisions/proxy-defer-remote-workhorse.md`)

If this work-request shipped without these fields, a follow-up migration is required before slice `proxy-04c-run-backend-trait-and-local-docker` can land.

## Stop condition

- [ ] `repo_configs` table: id, repo_path (unique), jira_project (nullable), quality_bar (enum: prototype/production/library), branch_naming (string template), feedback_loops (JSONB array of commands), files_in_scope (JSONB), files_out_of_scope (JSONB), auto_pr (bool, default true), **`memory_limit_mb` (int nullable, set by wizard)**, **`max_concurrent_per_repo` (int, default 2)**, **`backend` (text default `"local"`)**, pat_id (nullable FK to pats), extra_config (JSONB for future extensibility), created_at, updated_at
- [ ] `GET /api/repo-configs` returns all configs
- [ ] `POST /api/repo-configs` creates config for a repo path
- [ ] `PATCH /api/repo-configs/[id]` updates fields
- [ ] `DELETE /api/repo-configs/[id]` removes config (repo returns to global defaults)
- [ ] Settings > Repos page: list all configured repos, "Add Repo" form, edit in-place, delete
- [ ] All fields editable in the UI with sensible defaults pre-filled
- [ ] Loop runner reads repo config when spawning a loop for a given target_repo
- [ ] `npx tsc --noEmit` passes

## Feedback loops

- `npx tsc --noEmit`
- Manual test: add a repo config for `~/Projects/platform` with `jira_project: PLRM`, verify it persists and is returned by the API

## Quality bar

production
