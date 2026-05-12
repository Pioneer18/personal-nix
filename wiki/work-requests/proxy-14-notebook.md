---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# PROXY — Notebook

A personal notebook with ideas, todos, and custom categories. Ideas can be promoted to work requests via a grill flow. Todos have due dates and notification channel preferences. Categories are user-defined with configurable behavior flags.

## Goal

User can jot down ideas and todos in the PROXY notebook. Ideas have a "Turn into Work Request" button. Todos have due dates and show as overdue when past. Custom categories can be added with configurable notifiable/promotable flags.

## Files in scope

- `apps/web/src/app/notebook/**`
- `apps/web/src/app/api/notebook/**`
- DB migrations for `notebook_entries` and `notebook_categories` tables

## Files out of scope

- Notification delivery (Slice 15) — todos store preferences here, delivery is Slice 15

## Stop condition

- [ ] `notebook_categories` table: id, name (unique), notifiable (bool), promotable (bool), created_at. Seed: `idea` (notifiable: false, promotable: true), `todo` (notifiable: true, promotable: false)
- [ ] `notebook_entries` table: id, category_id (FK), title, body (markdown, nullable), due_at (nullable), notification_channel (enum: macos/browser/both, nullable), notified (bool, default false), created_at, updated_at
- [ ] `GET/POST/PATCH/DELETE /api/notebook/entries`
- [ ] `GET/POST/PATCH/DELETE /api/notebook/categories`
- [ ] Notebook page: tabs per category, add entry (quick title input or full form), edit, delete
- [ ] "Promote to Work Request" button on idea entries: opens work request create form pre-filled with idea title + body as description
- [ ] Todos tab: sorted by due_at, overdue entries highlighted in red/warning color
- [ ] Settings > Notebook Categories page: add custom category, set notifiable/promotable flags, delete
- [ ] `npx tsc --noEmit` passes

## Feedback loops

- `npx tsc --noEmit`
- Manual test: create an idea, click "Promote to Work Request", verify fields carry over to the create form

## Quality bar

production
