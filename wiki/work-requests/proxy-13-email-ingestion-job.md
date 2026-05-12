---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# PROXY — Email Ingestion Job

Gmail OAuth integration. A BullMQ `data_ingestion` job pulls emails on a schedule, processes them with a user-defined Claude prompt, and emits a digest feed item to the inbox.

## Goal

User connects their Gmail account via Settings > Integrations, configures a schedule and a Claude processing prompt, and each morning (or whenever scheduled) a digest card appears in their PROXY inbox with the processed email summary.

## Files in scope

- `apps/web/src/lib/workers/data-ingestion/**`
- `apps/web/src/lib/gmail/**`
- `apps/web/src/app/settings/integrations/**`
- `apps/web/src/app/api/integrations/gmail/**`

## Files out of scope

- Other job types
- SMS/email notification delivery (Slice 15)

## Stop condition

- [ ] Gmail OAuth flow: Settings > Integrations > Connect Gmail opens Google OAuth consent screen
- [ ] OAuth tokens (access + refresh) stored encrypted in DB (reuse crypto from Slice 7)
- [ ] Token refresh handled automatically before expiry
- [ ] `data_ingestion` worker for Gmail: fetch unread emails since last run, batch send to Claude with user-defined prompt, emit single `email_digest` feed item
- [ ] Feed item type `email_digest`: title = "Email digest — {date}", body = Claude's processed output
- [ ] Job config fields: `gmail_account` (string), `claude_prompt` (text), `label_filter` (optional Gmail label), `output_to` (`feed` or `inbox`)
- [ ] Settings > Integrations page shows connected Gmail account + connected/disconnect button
- [ ] Manual "Run now" button on scheduled job to trigger immediately (for testing)
- [ ] `npx tsc --noEmit` passes

## Feedback loops

- `npx tsc --noEmit`
- Manual test: configure a Gmail ingestion job for `jonathan.sells@relymd.com`, click "Run now", verify a digest feed item appears in the inbox

## Quality bar

production
