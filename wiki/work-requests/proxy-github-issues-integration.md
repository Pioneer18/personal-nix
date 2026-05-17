---
status: open
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-16
depends_on: []
quality_bar: production
---

# PROXY — GitHub Issues integration

Adds first-class GitHub Issues support to PROXY: label sync, issue-context injection into the loop's brief, Create/Link Issue from a work-request.

## Background

Previously attempted in PR #11 (closed 2026-05-16) on a v1 substrate chain that was superseded by the v1.0 ship 2026-05-12. The feature is NOT yet on develop. This work-request restarts the implementation against the current Rust daemon + Next.js dashboard + v2-extended schema.

## Goal

A work-request can link to a GitHub Issue (`org/repo#N`). When a PROXY loop runs against a linked work-request:
1. The issue's body, labels, and comments are injected into the loop's context (via the brief on disk).
2. Labels on the issue are auto-managed across loop lifecycle: `agent-running`, `ready-for-review`, `needs-triage`, `ready-for-agent`.
3. The Create/Link Issue button on the work-request detail page opens a modal to either create a new issue or link an existing one.

## Files in scope

- `daemon/src/api/github_issues.rs` (new) — link, unlink, fetch issue body + labels + comments via `gh` CLI or octocrab
- `daemon/migrations/<timestamp>_github_issue_link.sql` (new) — `github_issue_url text nullable` column on `work_requests`, with index
- `daemon/src/runner/agent-brief.rs` — inject issue context into `brief.json`
- `apps/web/src/app/work-requests/[id]/page.tsx` — Create/Link Issue button + modal
- `apps/web/src/lib/api/github-issues.ts` (new) — TS client for the daemon endpoints

## Out of scope

- Issue webhooks (push-based sync from GitHub → PROXY) — separate slice if/when needed
- Cross-repo issue linking — defer
- Auto-close issue on PR merge — defer (handled by GitHub's native "Closes #N" syntax in the PR body)

## Stop condition

- [ ] Migration adds `github_issue_url` column on `work_requests`
- [ ] `POST /work-requests/:id/github-issue/link`, `DELETE …/unlink` endpoints
- [ ] Agent-brief includes issue body + labels when work_request has a linked issue
- [ ] Web UI Create/Link Issue button works end-to-end (create new + link existing)
- [ ] Label management on loop lifecycle: `agent-running` on loop start, `ready-for-review` on PR open, `needs-triage` on failure
- [ ] `cargo build`, `tsc --noEmit`, `npm run lint` all pass

## Feedback loops

- `cd daemon && cargo build`
- `cd apps/web && npm run build`
- `cd apps/web && npm run lint`
- Manual: link a real issue on a test work-request, run a loop, verify label transitions on GitHub

## References

- `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` — Tech stack (Rust daemon, per-repo config)
- `~/Projects/tachikoma-starter/CLAUDE.md` — Key integrations § GitHub
- Closed predecessor: PR #11 on the v1 chain. This is a clean restart against current develop.

## Quality bar

production
