---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# PROXY — Jira Integration

Integrate with Jira via the Atlassian MCP. Create/update Jira tickets from work requests. Mirror state machine transitions to Jira status. Poll assigned Jira tickets to create PROXY work requests automatically.

## Goal

A work request linked to `PLRM-1234` stays in sync with Jira — status updates flow out automatically as the loop progresses. Assigned Jira tickets can be pulled in as new work requests via a "Sync from Jira" action.

## Files in scope

- `apps/web/src/lib/jira/**`
- `apps/web/src/app/api/work-requests/**` (jira_ticket field)
- `apps/web/src/lib/workers/jira-sync.ts`
- `apps/web/src/app/work-requests/[id]/**` (Create/Link Jira Ticket button)

## Files out of scope

- BullMQ scheduler (Slice 11) — initial jira sync is a manual trigger, scheduler wires it up later
- GitHub integration (Slice 8)

## Stop condition

- [ ] `work_requests.jira_ticket` field added (format: `PROJ-N`, nullable)
- [ ] Jira client module wraps Atlassian MCP calls with typed functions: `createTicket`, `updateStatus`, `getAssignedTickets`
- [ ] Per-repo config `jira_project` drives which project new tickets are created in
- [ ] State transitions update Jira status:
  - `grabbed` → Jira "In Progress"
  - `done` → Jira "In Review"
  - `needs-triage` → Jira "Blocked"
- [ ] "Create Jira Ticket" button: creates ticket from work request title/description, stores `PROJ-N` reference
- [ ] "Link Jira Ticket" input: paste `PROJ-N` to link existing ticket
- [ ] "Sync from Jira" button: fetches tickets assigned to the configured Jira account, creates work requests for any not already in PROXY (matched by jira_ticket field)
- [ ] `npx tsc --noEmit` passes

## Feedback loops

- `npx tsc --noEmit`
- Manual test: create a work request, create a Jira ticket from it, start a run, verify Jira status moves to "In Progress"

## Quality bar

production
