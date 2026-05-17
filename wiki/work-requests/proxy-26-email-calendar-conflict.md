---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-13
---

# PROXY — Calendar conflict detection v1 (slice 26, email vertical)

Detects meeting invites arriving in inbox that conflict with the user's existing calendar events. Surfaces as a `Meeting Conflict` briefing (urgency = meeting-conflict, category = Meeting Conflict, orange). Never auto-declines. Read-only on calendar (`Calendars.Read` scope only). Schedule-write (V2) is deferred — the "Propose alt time" action shows but is disabled with a tooltip.

## Goal

When a meeting-invite email arrives (Outlook detects via `meetingMessageType: meetingRequest`), PROXY checks the user's calendar in the proposed time window. If conflict found:

- Briefing gets `urgency = meeting-conflict` + category `Meeting Conflict` (orange)
- Briefing `key_details` includes conflict structured record: `{ conflicting_event_title, conflicting_event_start, conflicting_event_end, conflicting_event_organizer }`
- Reviewer surface offers: Accept anyway (deep-link to Outlook) / Decline (opens slice 23 compose with pre-drafted decline message, user confirms send) / Propose alt time (V2 disabled with tooltip)

No auto-decline. No auto-acceptance. User decides.

Non-conflict invites still get briefings (routed to `External Meetings & Info` by slice 21), just without the meeting-conflict treatment.

## Files in scope

- `daemon/src/email/calendar_conflict.rs` — meeting-invite detector + Graph calendar query + conflict structured record
- `daemon/src/outlook/calendar_client.rs` — `Calendars.Read` Graph wrapper (extends slice 19's client struct)
- `apps/web/src/app/email/reviewer/components/ConflictBriefing.tsx` — specialized briefing render for conflict urgency
- Scope addition in `daemon/src/outlook/scopes.rs`: append `Calendars.Read` (already in slice 19's initial consent; this slice just wires consumption)
- Slice 20's `briefing.rs` integration: call `calendar_conflict::check(message)` for meeting-invite messages

## Files out of scope

- Calendar write (V2: `Calendars.ReadWrite`, schedule-meeting Reviewer action)
- Propose-alt-time send-flow (V2 — depends on calendar write)
- Briefing engine plumbing (slice 20 already handles routing the conflict result to a briefing record)
- Outlook OAuth (slice 19) — slice 19 must include `Calendars.Read` in its initial consent

## Stop condition

- [ ] `Calendars.Read` scope wired in `OutlookGraphClient` (slice 19 grants it; this slice consumes it)
- [ ] Meeting-invite detector identifies messages with `meetingMessageType == "meetingRequest"` from Graph
- [ ] `calendar_conflict::check(message)` flow:
  1. Parse invite start/end from message
  2. Query user's calendar events in `[invite.start - 5min, invite.end + 5min]` window via Graph `/me/calendarView`
  3. Filter out: cancelled events, all-day events that don't overlap meaningfully
  4. If any remaining event overlaps → emit `ConflictRecord` struct
  5. Return `None` if no conflict
- [ ] `ConflictRecord` fields: `conflicting_event_title`, `conflicting_event_start`, `conflicting_event_end`, `conflicting_event_organizer`, `is_organizer_user` (user might be organizing the conflicting event)
- [ ] Briefing engine (slice 20) consumes `ConflictRecord`:
  - Sets `urgency = meeting-conflict`
  - Adds category `Meeting Conflict` (orange)
  - Includes conflict record in `briefing.key_details` as structured JSON
- [ ] Reviewer renders Conflict briefings differently (slice 22 uses this component):
  - Prominent "⚠️ Conflicts with: [event title] at [time]" callout at top of briefing detail
  - Conflict details visible alongside the invite summary
- [ ] Reviewer action panel for conflict briefings:
  - "Accept anyway" → opens Outlook deep link to original invite (`https://outlook.office.com/calendar/...`)
  - "Decline" → opens slice 23's ComposePanel with pre-drafted decline message ("Thanks for the invite — unfortunately I have a conflict at this time...") + recipient = organizer
  - "Propose alt time" → disabled with tooltip "v2 — requires Calendars.ReadWrite"
- [ ] Non-conflict invites still generate normal briefings via slice 21 routing (`External Meetings & Info` folder, no special urgency or category)
- [ ] All-day-event edge case: PROXY does NOT flag all-day events as conflicts with a specific-time invite unless explicitly configured; default behavior is "all-day events don't conflict with timed meetings"
- [ ] User-as-organizer edge case: if user is the organizer of the conflicting event, briefing still shows conflict but with note "(you are organizing this)"
- [ ] `cargo test` covers:
  - Conflict detection (positive)
  - No-conflict (negative)
  - Multi-conflict (returns first; or list — pick one in impl)
  - All-day event non-flag
  - Cancelled-event filter
  - User-as-organizer note
- [ ] `cargo clippy --all-targets -- -D warnings`
- [ ] `npx tsc --noEmit` passes (Reviewer component)

## Feedback loops

- `cargo test`
- Manual: send self a meeting invite that conflicts with existing calendar event → verify briefing appears with `urgency=meeting-conflict` + category `Meeting Conflict` + conflict details

## Quality bar

production

## v3 context

- See ADR 005 § D2 (calendar conflict = briefing, not auto-decline) and § D6 (V1 read-only, V2 ReadWrite)
- Sets up V2 expansion to `Calendars.ReadWrite` — "Schedule meeting" Reviewer action + "Propose alt time" actually sending a counter-proposal
- Decline action delegates to slice 23's iterative compose flow — user can iterate on the decline message tone before confirming send
