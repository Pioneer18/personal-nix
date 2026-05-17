---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-14
---

# PROXY — Operations TUI (6-region stacked) (slice 34)

Ink TUI right pane redesigned as 6-region stacked layout with Active Op (North Star) as the primary region. Status bar + Live proxies + Queue + Inbox below. `★` filter flags items linked to active Op; `*` toggles show-all.

## Goal

When handler glances at the TUI, the active Op + what to do next is unambiguous. Queue + Inbox stay accessible but de-emphasized in favor of the North Star.

After ship, the TUI is no longer "list of proxy jobs" — it reads as a section of operatives serving an active Operation, with the handler as the visible decision-maker.

## Files in scope

- `apps/tui/src/components/StatusBar.tsx` — single-line top bar: face + theater + voice mode + memory % + swap rate (memory + swap from existing daemon API)
- `apps/tui/src/components/ActiveOpPane.tsx` — North Star region: title + bucket + status + 1-line goal + "Next up" top-3 + Objectives summary + Follow-ups summary; consumes `proxy op next` + Op detail API
- `apps/tui/src/components/LiveProxiesPane.tsx` — running loops; shrinks-to-fit; shows archetype + slice slug + state + duration + small face
- `apps/tui/src/components/QueuePane.tsx` — existing pane; modified to:
  - Show top 5 items by default (down from existing N?)
  - Render `★` glyph next to Epics linked to active Op via any Objective's `link`
  - Respect `*` toggle for show-all vs filtered
- `apps/tui/src/components/InboxPane.tsx` — existing pane; modified to:
  - Show top 5 by default
  - `★` glyph for items linked to active Op (Recommendations targeting Op, Briefings whose Briefing-id is an Objective link, feed items for the Op)
  - Respect `*` toggle
- `apps/tui/src/components/RightPaneLayout.tsx` — new top-level layout: vertical stack of StatusBar + ActiveOpPane (~30% height) + LiveProxiesPane (shrinks-to-fit) + QueuePane (fixed 5) + InboxPane (fixed 5); each collapsible
- `apps/tui/src/keybindings.ts` — single-key region toggles (`o` Op pane, `p` proxies, `q` queue, `i` inbox); `Tab` / `Shift-Tab` for cursor; `Enter` to drill; `*` to toggle Op-centric filter
- `apps/tui/src/state/activeOp.ts` — react state hook subscribing to active Op via daemon API; updates on OPERATIONS.yaml change
- Daemon API additions (if not in slice 30): `GET /api/operations/active?theater=relymd` returns active Op summary; `GET /api/operations/<slug>/next` returns ranked actionable items

## Files out of scope

- Web UI (slice 35)
- The Operation data model (slice 30)
- Triage / proactive engine logic (slices 31-32)
- Skills (slice 33)
- BMO face rendering (existing; this slice consumes face state)

## Stop condition

- [ ] StatusBar renders single-line with: BMO face glyph + theater name + voice mode + `mem N%` + `swap N/s`; truncates gracefully on narrow terminals
- [ ] ActiveOpPane displays:
  - [ ] Op title + bucket badge (P0/P1/P2/P3) + status (live/on-ice/burned)
  - [ ] One-line goal (from frontmatter `title` + `description` first line)
  - [ ] "Next up" section: top 3 actionable items from `/operations/<slug>/next` API
  - [ ] Objectives summary: count + stale warning glyph if any
  - [ ] Follow-ups summary: count + due-today glyph if any
  - [ ] If no active Op in current Theater: empty state with "Create your first Op" prompt (CTA opens `/op-grill`)
- [ ] LiveProxiesPane shows running loops with archetype face (Tracer / Quill / Phantom / Echo) + slug + state + minutes; capped at `max_concurrent_per_repo` rows
- [ ] QueuePane shows top 5 items with `★` glyph for active-Op-linked Epics
- [ ] InboxPane shows top 5 items with `★` glyph for active-Op-linked items
- [ ] `*` keystroke toggles `★`-filter off (show all) and on (filter to active-Op-linked); persists across renders
- [ ] `o` / `p` / `q` / `i` keystrokes collapse/expand respective region; collapsed state shows region header + count summary only
- [ ] `Tab` / `Shift-Tab` move cursor between regions; `Enter` drills into focused item (Op detail / proxy detail / Epic detail / inbox item)
- [ ] Resize behavior: on terminals < 30 rows, ActiveOpPane shrinks first; Queue + Inbox stay fixed at 5; LiveProxies shrinks-to-fit; StatusBar always visible
- [ ] BMO face state extended: stale-Op count > 3 in active Theater triggers `out-of-wack` face (existing trigger list per CLAUDE.md)
- [ ] Updates propagate via existing daemon SSE / LISTEN-NOTIFY: edit OPERATIONS.yaml, TUI reflects within 2s
- [ ] `pnpm test` covers: layout snapshot tests, keybinding tests, `★`-filter toggle, collapse/expand state
- [ ] `pnpm typecheck` + `pnpm lint` clean

## Feedback loops

- `pnpm test`
- `pnpm typecheck`
- `pnpm lint`
- Manual: run `pnpm dev` in `apps/tui`, verify all 6 regions render, keybindings work, `★` filter toggles

## Quality bar

production

## v3 context

- See ADR 007 D13 for surface design
- Replaces / extends the existing `proxy-16-tui-v2` right pane layout (which only had queue + face)
- Depends on slice 30 for daemon API + Op data; slice 33 for skill invocations (since handler can press a keystroke to invoke `/op-grill` for the focused Op)
- LiveProxies pane uses the 5ECH archetype faces (Tracer `>_<`, Quill `o_o`, Phantom `-_-`, Echo `◕‿◕`) per FACES.md — proxies appear as operatives, not jobs
- `★` filter default-ON is opinionated; the Op-centric view is the North Star; `*` is the escape hatch
- Status bar's voice mode display reads from `proxy-voice` daemon's current mode (Hey PROXY / Wispr / Open / Off)
