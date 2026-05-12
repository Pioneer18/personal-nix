---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# PROXY — GitHub Issues Integration

Link work requests to GitHub issues. Read issue body as additional loop context. Update GitHub issue labels automatically as the work request state machine transitions. Create a GitHub issue from a work request in one click.

## Goal

A work request linked to `org/repo#N` gets that issue's labels updated as it moves through states. The running loop receives the issue body as context. User can create a GitHub issue from any work request and the reference is stored.

## Files in scope

- `apps/web/src/lib/github/**`
- `apps/web/src/app/api/work-requests/**` (add github_issue field)
- `apps/web/src/lib/runner/**` (inject issue context)
- `apps/web/src/app/work-requests/[id]/**` (Create Issue button)

## Files out of scope

- Jira integration (Slice 9)

## Stop condition

- [ ] `work_requests.github_issue` field added (format: `org/repo#N`, nullable)
- [ ] When a run starts on a work request with a github_issue, the issue body is fetched (using linked PAT) and injected into the agent brief
- [ ] State machine transitions update GitHub issue labels:
  - `grabbed` → add label `agent-running`
  - `done` → remove `agent-running`, add `ready-for-review`
  - `needs-triage` → remove `agent-running`, add `needs-triage`
- [ ] "Create GitHub Issue" button on work request detail: creates issue with work request title + body, stores `org/repo#N` reference
- [ ] "Link GitHub Issue" input on work request form (paste `org/repo#N`)
- [ ] Labels auto-created in target repo if missing (same 4 labels as current Tachikoma skill)
- [ ] GH_TOKEN injected from linked PAT (from Slice 7)
- [ ] `npx tsc --noEmit` passes

## Feedback loops

- `npx tsc --noEmit`
- Manual test: link a work request to a test GitHub issue, start a run, verify `agent-running` label is applied

## Quality bar

production
