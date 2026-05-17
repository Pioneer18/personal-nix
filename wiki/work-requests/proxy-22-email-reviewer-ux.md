---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-13
---

# PROXY — Email Reviewer UX (slice 22, email vertical)

Web-primary Reviewer UI for managing Email Briefings. Three-pane layout: briefing list (left) + current briefing render with sandboxed iframe HTML body (center) + action panel (right). Keyboard nav per ADR 005 § D4 keys. Deep-links from TUI + activity feed inbox.

This slice ships the UX **without** iterative compose (slice 23 owns that), Jira creation (slice 25), and calendar-scheduling (slice 26 V2). Action buttons for those are rendered but disabled with tooltips.

## Goal

User navigates to `/email/reviewer` and sees:

- Briefing list left pane, default urgency-first sort, re-sortable by recency / sender / folder
- Click briefing → center pane renders source email (body lazy-fetched via Graph per ADR 005 § D5)
- Right pane: action menu (Email / External / AI / Nav groups)
- Keyboard: ← / → for prev/next briefing, `a` archive, `d` delete, `r` reply (opens slice 23 panel), `f` forward, `s` skip, `b` back, `o` / Enter open, `/` search
- Briefing-open triggers server-side mark-as-read (Graph + DB) + sets `opened_at` for 21-day archive clock

## Files in scope

- `apps/web/src/app/email/reviewer/page.tsx` — main Reviewer route
- `apps/web/src/app/email/reviewer/[id]/page.tsx` — single briefing direct link
- `apps/web/src/app/email/reviewer/components/BriefingList.tsx`
- `apps/web/src/app/email/reviewer/components/BriefingDetail.tsx`
- `apps/web/src/app/email/reviewer/components/ActionPanel.tsx`
- `apps/web/src/app/email/reviewer/components/SafeEmailFrame.tsx` — DOMPurify-sanitized iframe wrapper
- `apps/web/src/app/email/reviewer/components/AttachmentList.tsx`
- `apps/web/src/app/email/reviewer/hooks/useKeyboardNav.ts`
- `apps/web/src/app/api/email/briefings/[id]/open/route.ts` — POST mark-opened
- `apps/web/src/app/api/email/briefings/[id]/actions/route.ts` — POST action (archive/delete/move/snooze/etc.)
- `apps/web/src/app/api/email/briefings/[id]/body/route.ts` — GET body (proxies to Graph)
- `apps/web/src/app/api/email/briefings/[id]/attachments/[attachment_id]/route.ts` — GET attachment binary
- `apps/tui/src/views/EmailQueue.tsx` — TUI queue count + new-briefing notifier with "open web Reviewer" deep-link

## Files out of scope

- Briefing engine (slice 20)
- Iterative compose UI (slice 23) — Reply/Forward buttons render but route to slice 23 component (stubbed in this slice)
- Jira ticket creation (slice 25)
- Calendar scheduling (slice 26)
- Body-flag mechanism (slice 24)

## Stop condition

- [ ] `/email/reviewer` route loads briefings from `/api/email/briefings` paginated, urgency-first default
- [ ] Re-sort controls work (recency, sender alpha, folder)
- [ ] Click briefing → center pane renders source email; body lazy-fetched via Graph (NOT cached in PROXY DB)
- [ ] HTML body sanitized via DOMPurify (kills scripts, iframes, external trackers); rendered in `<iframe sandbox="allow-same-origin">`
- [ ] Plaintext fallback for `text/plain` emails
- [ ] Inline images render via CID resolver (replace `cid:xxx` with Graph attachment URL)
- [ ] Quoted-reply chain collapsible (auto-collapse if >2 quoted blocks)
- [ ] Attachment list renders with download buttons; clicking downloads via Graph attachment endpoint
- [ ] Action panel groups render with correct enabled/disabled states:
  - Email actions enabled
  - AI > Iterative compose disabled with tooltip "ships in slice 23"
  - External > Create Jira ticket disabled with tooltip "ships in slice 25"
  - External > Schedule meeting disabled with tooltip "ships in slice 26 V2"
- [ ] Keyboard shortcuts per ADR 005 § D4 table; visible cheat sheet on `?` press
- [ ] Opening briefing emits POST `/open` → Graph `mark_read` + DB `user_status=opened, opened_at=now()` (starts 21-day archive clock per slice 20's sweep)
- [ ] Archive action → Graph `move_message` to Archive folder, DB `user_status=archived`
- [ ] Delete action → Graph `delete_message` (soft delete to Trash), DB `user_status=deleted`. NEVER permanent delete.
- [ ] Snooze action → DB `snoozed_until=now()+24h` (or user-picked duration), hidden from queue until expiry
- [ ] Move-folder action → Graph `move_message` to picked folder, updates briefing `proxy_folder`
- [ ] Add-category action → Graph `set_categories` (additive)
- [ ] Inbox tab (`proxy-12-activity-feed-inbox`) extended to render Email Briefings inline alongside feed items + recommendations, with "Review" deep-link button to Reviewer
- [ ] TUI `EmailQueue` view shows unread count; updates PROXY face when >5 unread (per `proxy-12-activity-feed-inbox` convention)
- [ ] `npx tsc --noEmit` passes
- [ ] Component tests for SafeEmailFrame (XSS test cases), BriefingList sort, ActionPanel disabled states
- [ ] E2E test: connect Outlook → poll cycle → open Reviewer → archive 3 briefings → verify Outlook state

## Feedback loops

- `npx tsc --noEmit`
- `npm test` (component tests; include XSS sanitization tests for SafeEmailFrame)
- Manual: full Reviewer workflow against live RelyMD inbox

## Quality bar

production

## v3 context

- See ADR 005 § D4 for full UX decisions
- Builds on `proxy-12-extended-web-dashboard` (Next.js app shell + feed/inbox already exist in M6)
- Inbox tab extension required — coordinate with the `proxy-12-activity-feed-inbox` UI to ensure Email Briefings render alongside feed items + recommendations (the `system_recommendations` v2 surface)
- Compose-flow integration point: Reply/Forward buttons hand off to slice 23's `ComposePanel` component
