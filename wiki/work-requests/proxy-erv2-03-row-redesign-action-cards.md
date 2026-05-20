# proxy-erv2-03 — Row redesign + action cards

## Goal

Tachikoma is done when each list row shows the new compact layout (shape badge + one-liner + sender + subject) and the detail pane shows shape-aware action cards. The urgency color bar is removed. Actions fire their Graph / Jira calls and trigger auto-advance.

## Files in scope

- `apps/web/app/email/reviewer/components/BriefingList.tsx` — row layout overhaul
- `apps/web/app/email/reviewer/components/BriefingDetail.tsx` — action card section
- `apps/web/app/email/reviewer/components/` — new `ActionCards.tsx` component
- `apps/web/app/api/email/briefings/[id]/actions/route.ts` — add action types: `calendar-accept`, `calendar-tentative`, `calendar-decline`, `jira-transition`
- `apps/web/src/lib/email/types.ts` — add `shape` field to `EmailBriefing`

## Files out of scope

- `daemon/` — shape already stored by erv2-02
- Draft / chat / reply flows — erv2-05
- Bulk select — erv2-04
- Search — erv2-04

## Action cards by shape

| Shape | Cards shown |
|-------|-------------|
| `jira-jsm` | Jira ticket status transitions (Open → In Progress → Done) + Reply (drafts in erv2-05) |
| `calendar-invite` | Accept / Tentative / Decline (Graph `calendar/events/{id}/accept` etc.) |
| `fyi` | Archive (keyboard: `a`) |
| `needs-reply` | Draft reply (triggers erv2-05 flow) |
| `other` | Archive + Delete |

## Auto-advance

After any successful action (archive, delete, calendar accept/decline, Jira transition), the reviewer automatically selects the next unread email in the current folder view. If none, show empty-state message.

## Stop condition

- [ ] List rows show: shape badge (monospace tag, color by shape) + one-liner + sender + subject; urgency color bar removed
- [ ] Detail pane shows action cards section below body
- [ ] Calendar accept/tentative/decline call Graph (requires Calendars.ReadWrite scope on Azure registration — note in PR description)
- [ ] Jira transition buttons read available transitions from `GET /rest/api/3/issue/{key}/transitions` and render them
- [ ] Auto-advance fires after each action
- [ ] Keyboard shortcut `a` still archives; `d` still deletes; both auto-advance
- [ ] TypeScript: no `any`, no compile errors

## Feedback loops

```
pnpm exec tsc --noEmit   # from apps/web/
```

## Quality bar

production
