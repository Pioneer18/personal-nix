---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-13
---

# PROXY — Deep Jira ticket creation from briefing (slice 25, email vertical)

Reviewer action that creates a Jira ticket from a current briefing, pre-filling title / description / project / priority from the briefing content, with one-click confirm. Future emails in the same thread auto-link to the same ticket. Extends existing `proxy-09-jira-integration`.

## Goal

From Reviewer action panel → External > "Create Jira Ticket". Side panel opens with pre-filled fields:

- **Title**: `[subject]` truncated to Jira-friendly length (≤ 200 chars)
- **Description**: briefing summary + relevant key_details + (in body mode) Claude-suggested ticket framing paragraph
- **Project**: heuristic pick from sender/folder mapping (e.g. `RMD Support` folder → `SUPPORT` project) — picker dropdown allows override
- **Assignee**: default to user
- **Priority**: maps from briefing urgency — `urgent` → P1, `high` → P2, `med` → P3, `low` → P4

User edits as needed → confirm → PROXY creates ticket via existing Jira MCP path, stores ticket ID in `briefing.linked_external.jira_ticket_id`. Future thread emails (same `conversationId`) auto-detect existing link and skip duplicate ticket creation.

**Important**: RMD Support emails are often already linked to RMD board tickets externally (subject contains `[RMD-XXXX]` or similar). PROXY should detect this and NOT create duplicate tickets — instead, parse the existing ticket ID and store it.

## Files in scope

- `apps/web/src/app/email/reviewer/components/CreateJiraPanel.tsx`
- `apps/web/src/app/api/email/briefings/[id]/jira/route.ts` — POST create-and-link
- `daemon/src/email/jira_linker.rs` — auto-link future thread emails to existing ticket; detect pre-existing RMD ticket refs in subject
- `daemon/src/email/jira_pre_existing.rs` — subject regex for `[RMD-NNNN]` / `[PLRM-NNNN]` / etc.
- DB: extend `email_briefings.linked_external` jsonb with documented schema:
  ```json
  {
    "jira_ticket_id": "SUPPORT-1234",
    "jira_creation_source": "proxy_created" | "subject_detected",
    "linked_at": "2026-05-13T..."
  }
  ```
- Config in `proxy.toml`:
  ```toml
  [email.jira]
  default_project = "SUPPORT"
  folder_to_project = { "RMD Support" = "SUPPORT", "Internal" = "INTERNAL", "Titled Threads" = "EPIC" }
  pre_existing_ticket_regex = "\\[([A-Z]+-\\d+)\\]"
  ```

## Files out of scope

- Jira MCP itself (already exists — see `proxy-09-jira-integration`)
- Reviewer UI shell (slice 22)
- Briefing engine (slice 20) — this slice consumes briefing data, doesn't change briefing generation

## Stop condition

- [ ] Pre-fill logic produces sensible defaults for 4 test cases:
  - RMD Support email with no existing ticket ref → new ticket in `SUPPORT` project, P2-P3 priority
  - RMD Support email with `[SUPPORT-1234]` in subject → no new ticket; existing ID stored in `linked_external.jira_ticket_id` with source `subject_detected`
  - Calendar-conflict briefing → ticket would be unusual; panel still works but flags "non-standard ticket source"
  - Internal ops email → ticket in `INTERNAL` project
- [ ] Project picker dropdown allows override of heuristic
- [ ] Priority dropdown allows override of urgency mapping
- [ ] Jira creation via existing `proxy-09` MCP path (`mcp__plugin_atlassian_atlassian__*` tools)
- [ ] Created ticket ID stored in `briefing.linked_external.jira_ticket_id` with `source: "proxy_created"`
- [ ] Subject-detected pre-existing tickets parsed and stored on first encounter; future thread messages link to same ID
- [ ] Future-thread auto-link: when slice 20's briefing-update path detects `linked_external.jira_ticket_id` already set, skip CreateJiraPanel offering; instead show "Linked: [JIRA-1234]" badge
- [ ] Reviewer renders the badge prominently when briefing has a linked ticket; click → opens Jira ticket in new tab
- [ ] Body-mode (flag ON): description includes a 1-paragraph Claude-suggested ticket framing extracted from briefing
- [ ] Structural mode: description is briefing heuristic summary verbatim, no Claude framing
- [ ] On Jira creation, write Jira sync feed item (per `proxy-12` conventions): "Created [SUPPORT-1234] from email: {subject}"
- [ ] `npx tsc --noEmit` passes
- [ ] E2E test: create ticket from briefing → verify Jira side has ticket + briefing has `linked_external.jira_ticket_id` populated; second email in same thread → no duplicate ticket, badge shows existing ID

## Feedback loops

- `npx tsc --noEmit`
- `npm test` (component tests for pre-fill, subject regex, priority mapping)
- Manual: full create-link flow against the real Jira instance (or a sandbox project)

## Quality bar

production

## v3 context

- See ADR 005 § D6 (Jira deep integration in v1 scope)
- Builds on existing `proxy-09-jira-integration` — the MCP integration already works; this slice adds the email-vertical pre-fill + auto-link logic
- Pre-existing ticket detection is critical for RMD Support emails (they're already board-linked) — avoid duplicate-ticket sprawl
