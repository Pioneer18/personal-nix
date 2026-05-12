---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# PROXY — Auto-Tag Commits + PRs with Jira Ticket

When a loop runs in a repo with a Jira-configured per-repo config, automatically inject the Jira ticket number into commit messages and PR titles following the repo's commit convention.

## Goal

A work request linked to `PLRM-1234` running in `~/Projects/platform` produces commits formatted as `feat(scope): description [PLRM-1234]` and a PR title ending with `[PLRM-1234]`. Repos without Jira config are unaffected.

## Files in scope

- `apps/web/src/lib/runner/**` (agent brief template, env injection)
- `apps/web/src/lib/agent-brief.tmpl`

## Files out of scope

- Jira API calls (covered by Slice 9)
- GitHub PR creation logic beyond title formatting

## Stop condition

- [ ] Loop runner reads `jira_ticket` from work request and `jira_project` from repo config before spawning
- [ ] If `jira_ticket` is set: `PROXY_JIRA_TICKET` env var injected into the subprocess
- [ ] Agent brief template includes an instruction: "Include `[{PROXY_JIRA_TICKET}]` at the end of every commit message and PR title" (only rendered when the var is set)
- [ ] Generated commits include ticket number in the repo's commit format (e.g. `[PLRM-1234]` suffix matching platform's existing convention)
- [ ] PR title includes `[PLRM-1234]`
- [ ] Work requests with no `jira_ticket` field produce unmodified commit messages
- [ ] `npx tsc --noEmit` passes

## Feedback loops

- `npx tsc --noEmit`
- Manual test: run a loop on a work request linked to a real PLRM ticket in `~/Projects/platform`, inspect the resulting commit message and PR title

## Quality bar

production
