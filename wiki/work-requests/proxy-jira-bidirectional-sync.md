---
status: open
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-16
depends_on: []
quality_bar: production
---

# PROXY — Jira bidirectional sync + auto-tag

Extends the existing `jira_ticket` field on `work_requests` with: bidirectional state sync, Create/Link Ticket UI, Sync-from-Jira pull, and runner-side `PROXY_JIRA_TICKET` env injection so the loop auto-tags commits and PRs.

## Background

Previously attempted in PRs #12 + #13 (closed 2026-05-16) on a v1 substrate chain superseded by the v1.0 ship 2026-05-12. The `jira_ticket` column already exists on develop (migration `20260512060000_work_requests.sql`); this work-request layers the sync + UI + auto-tag on top of the current substrate.

## Goal

When a work-request has a linked Jira ticket:
1. **Outbound sync** — state transitions on the work-request push to Jira (`open → grabbed → done`) via the Atlassian MCP or REST.
2. **Inbound sync** — periodic poll updates the work-request when Jira state changes (closed, in-progress, etc.). Webhook path is deferred to a follow-up.
3. **Create/Link Ticket UI** — work-request detail page button to create a new Jira ticket OR link an existing one.
4. **Auto-tag** — runner injects `PROXY_JIRA_TICKET=<ticket>` into the loop env; the brief.json includes a note that commits and PR titles should start with `<ticket>:`.

## Files in scope

- `daemon/src/api/jira.rs` (new) — link, unlink, push-state, pull-state endpoints
- `daemon/migrations/<timestamp>_jira_sync_metadata.sql` (new) — add `jira_state text nullable`, `jira_synced_at timestamptz nullable` to `work_requests`
- `daemon/src/runner/agent-brief.rs` — inject `PROXY_JIRA_TICKET` env when the linked ticket is present; brief.json hint
- `apps/web/src/app/work-requests/[id]/page.tsx` — Create/Link Ticket button + modal
- `apps/web/src/lib/api/jira.ts` (new) — TS client
- Periodic Jira poll job — runs every N minutes (5-15) against linked tickets via the in-daemon PG scheduler

## Out of scope

- Jira webhooks for push-based sync — deferred follow-up
- Cross-project Jira linking — defer
- Full custom-field support on Jira ticket creation — v1 sets summary + description + project only

## Stop condition

- [ ] Migration adds the two sync-metadata columns
- [ ] `POST /work-requests/:id/jira/link`, `unlink`, `sync` endpoints
- [ ] Outbound: state transition on a work-request triggers push to Jira (testable via Atlassian MCP or mocked HTTP)
- [ ] Inbound: periodic poll updates `jira_state` + `jira_synced_at` at the configured cadence
- [ ] Web UI Create/Link Ticket button works end-to-end
- [ ] Runner injects `PROXY_JIRA_TICKET` env when the work-request has a linked ticket
- [ ] `cargo build`, `tsc --noEmit`, `npm run lint` all pass

## Feedback loops

- `cd daemon && cargo build`
- `cd apps/web && npm run build`
- Manual: link a Jira ticket on a test work-request, transition states, verify Jira mirrors; then change state in Jira and verify the work-request reflects after the next poll

## References

- `~/Projects/tachikoma-starter/CLAUDE.md` § Key integrations — Jira (PROXY is source of truth; Jira is a mirror)
- Existing field on develop: `work_requests.jira_ticket` via `daemon/migrations/20260512060000_work_requests.sql`
- Closed predecessors: PRs #12 + #13 on the v1 chain. This is a clean restart against current develop.

## Quality bar

production
