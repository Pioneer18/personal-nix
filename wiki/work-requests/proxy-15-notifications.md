---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
v2_note: "macOS action-button notifications in modern macOS require a bundled signed app; cannot be done from osascript alone. If this work-request shipped with osascript-only notifications, an amendment is required for action-button support."
---

> **v2 NOTE (2026-05-11)**: Modern macOS (≥ 11) restricts notification action buttons to bundled signed apps with a proper bundle ID and UNUserNotificationCenter registration. A plain `osascript -e 'display notification ...'` call posts a notification *without* action buttons. Since PROXY's confirmation UX (per [`~/Projects/tachikoma-starter/docs/ARCHITECTURE.md`](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) § 8) requires user-actionable buttons ("Close Chrome", "Snooze", "Settings"), this work needs to include a bundled Swift app (small, signed via Developer ID) that the daemon invokes to post notifications. See `proxy-12b-recommendations-engine.md` for what gets posted.

# PROXY — macOS + Browser Notifications

Fire macOS system notifications and browser Web Push notifications for todo reminders. BullMQ handles scheduling. Notification preferences are stored per notebook entry.

## Goal

A todo with a due date and notification channel set fires a macOS notification and/or browser push notification at the scheduled time. Browser notification click opens PROXY UI to the relevant entry.

## Files in scope

- `apps/web/src/lib/notifications/**`
- `apps/web/src/lib/workers/notification-worker.ts`
- `apps/web/src/app/api/push/**` (Web Push subscription endpoint)
- `apps/web/public/sw.js` (service worker for Web Push)

## Files out of scope

- SMS notifications
- Email notifications

## Stop condition

- [ ] macOS notification: `notification-worker` calls `osascript -e 'display notification "<title>" with title "PROXY"'` — works from the Next.js server process on macOS
- [ ] Web Push: VAPID keys generated (stored in env vars), `POST /api/push/subscribe` stores push subscription in DB, `POST /api/push/unsubscribe` removes it
- [ ] Service worker at `public/sw.js` handles `push` events and shows browser notification
- [ ] On todo create/update: if `due_at` and `notification_channel` are set, a BullMQ `notification` job is scheduled for that exact timestamp
- [ ] Notification job payload includes: todo title, entry URL, channel(s) to fire
- [ ] Browser notification click: focuses PROXY tab and navigates to the notebook entry
- [ ] `notification_channel: both` fires macOS AND browser notification
- [ ] After notification fires, `notebook_entries.notified` is set to true
- [ ] `npx tsc --noEmit` passes

## Feedback loops

- `npx tsc --noEmit`
- Manual test: create a todo due 2 minutes from now with `notification_channel: both`, wait, verify macOS notification appears and browser push fires

## Quality bar

production
