---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-13
---

# PROXY — Email briefing engine (slice 20, email vertical)

Core ingestion + analysis loop for the email vertical. Polls the connected Outlook inbox via Graph (using slice 19's `OutlookGraphClient`), generates per-thread Email Briefings, runs auto-action rules (file/delete/archive/mark-read), writes to the briefing queue, and emits audit log entries for every Claude API call.

Built to operate in **structural mode** (body never sent to Claude) by default. Body mode is enabled by slice 24's flag mechanism — this slice must respect the flag but does not own it.

## Goal

Daemon polls inbox every 10 min (configurable via `proxy.toml`). For each new message:
1. Apply sender allow/deny lists + PHI regex pre-filter
2. Auto-delete if sender ∈ ok-to-delete list (with receipt feed item)
3. Auto-file to correct PROXY folder via routing rules from slice 21 (server-side Graph `move_message`)
4. Generate or update the per-thread Email Briefing using Outlook `conversationId`
5. New thread → new briefing in queue; existing-thread new message → re-open briefing to top with `[N new]` badge
6. Write audit log row for every Claude API call

In structural mode, briefing summary/action items/suggested actions are heuristic (subject + sender + thread metadata only). In body mode (slice 24 flag ON), Claude generates from body content.

## Files in scope

- `daemon/src/email/poller.rs` — schedule-driven Graph poller (registered with `proxy-11b-pg-scheduler`)
- `daemon/src/email/briefing.rs` — per-thread briefing generation, heuristic + Claude paths
- `daemon/src/email/rules.rs` — auto-action rules engine (allow/deny, ok-to-delete matching)
- `daemon/src/email/phi_guard.rs` — regex pre-filter (SSN, DOB, MRN, "patient #", "chart #")
- `daemon/src/email/audit.rs` — audit log writer
- `daemon/src/email/auto_actions.rs` — executor for file/delete/archive/mark-read actions
- DB migrations:
  - `email_briefings` table (full schema per ADR 005 § D3)
  - `email_audit_log` table: `id UUID PK, briefing_id UUID nullable, sender text, subject text, body_included bool, model text, prompt_token_count int, completion_token_count int, called_at timestamptz`
- `apps/web/src/app/api/email/briefings/route.ts` — GET briefings list (paginated, urgency-first default)
- `apps/web/src/app/api/email/briefings/[id]/route.ts` — GET single briefing

## Files out of scope

- Outlook OAuth (slice 19)
- Folder + category setup (slice 21) — this slice consumes the routing rules but doesn't create the folders
- Reviewer UX (slice 22)
- Iterative compose (slice 23)
- Body-flag mechanism (slice 24) — this slice respects the flag but doesn't own it
- Jira ticket creation (slice 25)
- Calendar conflict detection (slice 26) — this slice routes to the briefing but the conflict detector lives in slice 26

## Stop condition

- [ ] `email_briefings` migration runs clean; table exists with full schema
- [ ] `email_audit_log` migration runs clean
- [ ] Poller registered with pg-scheduler at `proxy.toml` cadence (default 600s, configurable)
- [ ] Poller fetches messages since last poll via Graph delta query (efficient, no duplicates)
- [ ] PHI regex pre-filter blocks SSN/DOB/MRN/"patient #"/"chart #" before any Claude call; emits stub briefing with subject + sender + `PHI-Flagged` category
- [ ] Sender allow/deny list config in `proxy.toml`:
  ```toml
  [email.allowlist]
  ok_to_delete = [
    { domain = "github.com", sender = "noreply@github.com" },
    { domain = "microsoft.com", sender = "MSSecurity-noreply@microsoft.com" },
  ]
  ```
- [ ] Auto-delete fires only for senders matching both domain AND specific known-noreply sender name; writes feed-item receipt "Deleted email from {sender}: {subject}" with "Undo" action
- [ ] Auto-file calls slice 21's `routing::route(message)` → Graph `move_message` to target folder + applies categories
- [ ] Per-thread briefing logic: new `conversationId` → new row; existing → update `latest_message_id`, `last_updated`, set `user_status=new` if was `opened` (re-open behavior)
- [ ] Briefing urgency heuristic (structural mode): subject keywords (`urgent`, `asap`, `eod`, `priority`) → high/urgent; sender priority (Dany, high-touch list) → med-high baseline; age penalty for unread+aged
- [ ] Audit log row written for EVERY Claude API call regardless of mode; record sender + subject (metadata only, no body) + body_included flag + model + token counts
- [ ] Structural mode (`BodyFlag::off`): heuristic briefing only; `body_included` always false in audit
- [ ] Body mode (`BodyFlag::on`, from slice 24): Claude generates summary + action_items + suggested_actions from body; audit records `body_included=true`
- [ ] Auto-archive sweep job (daily at 02:00 local): briefings with `user_status=opened AND opened_at < now() - 21d AND no user actions since` → Graph move to Archive folder, DB `user_status=archived`
- [ ] Daily Auto-action Summary briefing generated at 23:55 local: counts of filed/deleted/archived/marked-read for the day, with one-tap bulk-revert action
- [ ] `cargo test` covers: PHI block, allowlist delete (positive + false-positive cases), folder routing, per-thread merge, urgency heuristic, audit-log write, structural-vs-body branch
- [ ] `cargo clippy --all-targets -- -D warnings`

## Feedback loops

- `cargo test`
- Manual: connect Outlook (slice 19) → run `proxy email init` (slice 21) → wait one poll cycle → verify briefings appear in DB with correct urgency + folder + audit log entries

## Quality bar

production

## v3 context

- See ADR 005 § D2 (trust boundary), § D3 (data model), § D5 (operational scale)
- Reuses `proxy-11b-pg-scheduler` for poller scheduling
- Audit log is the forensic substrate for the body-flag flip (slice 24's flip-checklist queries it)
- Briefing record schema is canonical per ADR 005 § D3; do not deviate without ADR amendment
- **Safety**: this slice is downstream of slice 24's body-flag — never call Claude with body without going through the flag-guard helper
