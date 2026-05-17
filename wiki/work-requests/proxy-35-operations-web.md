---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-14
---

# PROXY — Operations web surfaces (slice 35)

Web routes: `/` Op-dashboard (active Op at top — North Star); `/operations` list view + drag-reorder + expand-collapse Objectives/Follow-ups; `/operations/[slug]` single Op detail page. Notebook surface gains `idea → Op` promotion alongside existing `idea → work-request`.

## Goal

Handler opening the web UI sees the active Op at the top of the dashboard — same North Star ethos as TUI. The `/operations` page is the editable surface for ranking, drag-reordering, expanding Objectives, accepting Recommendations inline.

After ship, web becomes Op-primary; `/queue` (ADR 006) becomes the secondary surface for proxy-work specifics.

## Files in scope

- `apps/web/app/page.tsx` — `/` dashboard root; restructured: ActiveOpBlock at top (mirroring TUI ActiveOpPane), feed/inbox/recommendations below
- `apps/web/app/operations/page.tsx` — `/operations` list view; drag-reorder Ops via react-dnd or similar; expand/collapse to show Objectives + Follow-ups per Op; filter by Theater dropdown (V2-ready, V1 only `relymd`)
- `apps/web/app/operations/[slug]/page.tsx` — `/operations/[slug]` detail page; full Op view; edit Objectives + Follow-ups inline; show all linked surfaces (Epic state, Briefings, Jira tickets, Drafts) with deep-links
- `apps/web/components/ActiveOpBlock.tsx` — block component for dashboard top; same data shape as TUI ActiveOpPane
- `apps/web/components/OpListRow.tsx` — single row for `/operations` list; drag handle + bucket badge + status + counts
- `apps/web/components/ObjectiveRow.tsx` — single Objective row with state toggle + link display + edit-in-place
- `apps/web/components/FollowUpRow.tsx` — single Follow-up row with state toggle + `remind_at` + recur display + edit-in-place
- `apps/web/components/RecommendationCard.tsx` — modified to handle Op-engine Recommendation kinds (`op-stale`, `op-draft-epic`, `op-draft-jira`, `op-draft-briefing`, `op-kill-or-revive`, `op-recur-fire`, `op-triage`); accept / decline buttons trigger CLI-equivalent actions via daemon API
- `apps/web/components/notebook/IdeaPromotionMenu.tsx` — modified: existing `Promote to work-request` button; add `Promote to Op` button; on click, opens `/op-grill`-equivalent web flow pre-filled from idea body
- API additions (or extensions to slice 30's API): `PATCH /api/operations/<slug>` (priority/state/position changes), `POST /api/operations/<slug>/objectives` (add), `PATCH /api/operations/<slug>/objectives/<obj-id>` (edit), `DELETE /api/operations/<slug>/objectives/<obj-id>`, analogous for follow-ups, `POST /api/notebook/<idea-id>/promote-to-op`
- Drag-reorder UX: optimistic update + atomic PATCH; revert + toast on failure

## Files out of scope

- TUI rendering (slice 34)
- Op data model + daemon API foundation (slice 30)
- Triage engine (slice 31)
- Proactive engine (slice 32)
- Skills (slice 33)
- `notebook.todo` migration (slice 36)

## Stop condition

- [ ] `/` dashboard root:
  - [ ] ActiveOpBlock displays at top; mirrors TUI region content
  - [ ] Feed + Inbox + Recommendations remain below; Recommendations show Op-engine kinds correctly
  - [ ] If no active Op: empty state with CTA to create first Op
- [ ] `/operations` list view:
  - [ ] Lists all open + live Ops by default; toggle to show all states (incl. burned + done)
  - [ ] Drag-reorder updates OPERATIONS.yaml atomically; daemon sync reflects in DB within 2s
  - [ ] Each Op row expandable to show Objectives + Follow-ups inline; collapse default
  - [ ] Theater filter dropdown (V1: only `relymd` available; V2-ready)
  - [ ] "New Op" button → opens grill flow (web-equivalent of `/op-grill`)
- [ ] `/operations/[slug]` detail page:
  - [ ] Full frontmatter view (title, theater, bucket, status, created_at, last_touched_at, embedding hash)
  - [ ] Description body rendered as markdown
  - [ ] Objectives list: add / edit / link / state-change inline; linked surfaces deep-link out (`epic:auth-middleware-rewrite` → `/queue#auth-middleware-rewrite`; `jira:PLRM-1438` → opens Jira; `briefing:<id>` → `/email/briefings/<id>`)
  - [ ] Follow-ups list: add / edit / `remind_at` picker / recur input (with LLM-normalized preview) / state-change
  - [ ] "Drop Op" + "Burn Op" actions in header (with confirm modals)
  - [ ] Audit history: feed_items related to this Op shown in a side panel
- [ ] Notebook promotion:
  - [ ] `idea` row in notebook UI gains "Promote to Op" button alongside existing "Promote to work-request"
  - [ ] Click → opens grill flow pre-filled with idea title + body; on save, creates Op + marks idea as `promoted_to=op:<slug>`
- [ ] Recommendation cards handle Op-engine kinds:
  - [ ] `op-stale`: shows Op + Objective context, [Snooze 7d / Chase / Drop / Dismiss] buttons
  - [ ] `op-draft-epic`: shows draft Epic body + slice preview; [Accept (create Epic + add to QUEUE.yaml + link Objective) / Edit / Decline]
  - [ ] `op-draft-jira`: shows draft ticket title + description; [Accept (create Jira via Atlassian MCP + link) / Edit / Decline]
  - [ ] `op-draft-briefing`: shows draft email subject + body; [Accept (open in Reviewer compose pane) / Edit / Decline]
  - [ ] `op-kill-or-revive`: shows Op summary + stale Objectives; [Burn / Revive / Edit]
  - [ ] `op-recur-fire`: shows recurring item context; [Accept new cycle / Snooze / Edit recur]
  - [ ] `op-triage`: shows suggested priority/position/Objectives/links; [Accept all / Accept partial / Override]
- [ ] Drag-reorder + edit-in-place pass optimistic UI tests
- [ ] All POST/PATCH/DELETE endpoints use daemon API; no direct DB writes from web
- [ ] `pnpm test` covers: page render snapshots, drag-reorder logic, Recommendation accept flow per kind, idea→Op promotion
- [ ] `pnpm typecheck` + `pnpm lint` clean

## Feedback loops

- `pnpm test`
- `pnpm typecheck`
- `pnpm lint`
- Manual: `pnpm dev` in `apps/web`, visit `/`, verify Op dashboard renders; create Op via `/op` in chat tab, verify appears in `/operations` within 2s

## Quality bar

production

## v3 context

- See ADR 007 D13 for surface design
- Depends on slice 30 (data + API), slice 31 (triage), slice 32 (Recommendations); extends `proxy-12-extended` (web dashboard) and `proxy-28-queue-web-ui` (drag-reorder pattern)
- Web routes are SSR via Next.js per existing pattern; auth handled by existing session middleware
- Theater filter dropdown is V1-ready but V1 only has `relymd` — wired for V2 multi-Theater
- `/queue` (ADR 006 slice 28) preserved unchanged; this slice does NOT modify queue routes
- BMO face indicator on dashboard reflects same global state as TUI status bar
