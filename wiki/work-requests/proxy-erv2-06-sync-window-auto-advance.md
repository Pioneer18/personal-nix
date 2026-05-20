# proxy-erv2-06 — Sync window (7-day) + load-more + auto-advance polish

## Goal

Tachikoma is done when (1) the daemon's initial Outlook sync is capped at 7 days of history, (2) a "load previous 7 days" button in the reviewer lets the user extend the window, and (3) auto-advance behavior is polished (correct next-unread selection, empty-state handling, focus restored after keyboard action).

## Files in scope

- `daemon/src/email/ingestion.rs` — cap delta start at `now - 7d` on first sync; store `sync_window_start` in `email_poll_state`
- `apps/web/app/api/email/briefings/load-older/route.ts` — new: `POST { days: 7 }` → triggers daemon to fetch N more days of history
- `apps/web/app/email/reviewer/page.tsx` — "load previous 7 days" button + auto-advance edge cases
- `apps/web/app/email/reviewer/components/BriefingList.tsx` — show load-older button at bottom when sync window can extend

## Files out of scope

- Draft/reply flow (erv2-05)
- Shape detection (erv2-02)

## Sync window behavior

- First sync: `startDateTime = now - 7d` passed to Graph delta query. Stored in `email_poll_state.sync_window_start`.
- "Load previous 7 days" button at bottom of list: calls `POST /api/email/briefings/load-older` which extends `sync_window_start` by 7 more days and triggers a one-shot historical fetch (not part of normal delta cycle).
- Button only shown when `sync_window_start > email_account.created_at + 7d` (i.e., there's more history to fetch).

## Auto-advance polish

- After action, select the email that was below the actioned one in the current sorted/filtered view. If at the end of the list, select the one above. If list is empty, show "no more emails" empty state.
- Keyboard focus moves to the new selected item (scroll into view).
- Focus mode auto-closes when list empties.

## Stop condition

- [ ] New Outlook connections only fetch last 7 days on first sync (not entire inbox)
- [ ] `email_poll_state` stores `sync_window_start`
- [ ] "Load previous 7 days" button visible at list bottom; triggers historical fetch; new emails appear in list
- [ ] Auto-advance after action selects correct next email
- [ ] Empty-state shown when all emails acted on
- [ ] Focus mode closes if email count hits 0 while in focus

## Feedback loops

```
cargo check
pnpm exec tsc --noEmit   # from apps/web/
```

## Quality bar

production
