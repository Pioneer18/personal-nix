---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-14
---

# PROXY — Operations proactive engine (slice 32)

6-hour cron that sweeps Operations, Objectives, Follow-ups for: stale detection, can-start drafting (Epic / Jira / Briefing drafts), recur fires. Emits Recommendations to inbox. **Draft-only — never auto-actions** (hard rule #9 per ADR 007 D8 + CLAUDE.md).

## Goal

Handler doesn't have to manually re-check their Op list daily. The engine does it every 6 hours and surfaces only the items that need attention — staleness, opportunities for proxy work, recurring deliverables — as Recommendations the handler can approve or dismiss.

After ship, PROXY moves from reactive (handler queries) to proactive (engine surfaces). The Recommendation surface is the only gate for any externally-visible action.

## Files in scope

- `daemon/src/operations/proactive/mod.rs` — orchestrator; scheduled by `proxy-11b-pg-scheduler` every 6 hours
- `daemon/src/operations/proactive/stale.rs` — stale detection: walks Operations + Objectives + Follow-ups; bucket-keyed thresholds (P0=1d, P1=3d, P2=7d, P3=30d); `last_touched_at` comparison; emits Recommendation `op-stale` per stale item (Op-level + Objective-level + Follow-up-level)
- `daemon/src/operations/proactive/can_start.rs` — can-start drafting:
  - For Objectives with `link IS NULL` and proxy-shape title (regex: `^(land|implement|rewrite|build|migrate|wire|add) `): draft Epic + slice work-request `.md` body; emit Recommendation `op-draft-epic`
  - For Objectives with `link IS NULL` and platform-shape title (regex: `^(fix|patch|refactor|optimize) ` + `jira_project` set): draft Jira ticket title + description; emit `op-draft-jira`
  - For Follow-ups matching `^chase (\w+) ` (person name): draft email Briefing body (subject, body, recipient); emit `op-draft-briefing`
  - For Ops where all Objectives stale past 2x bucket threshold: emit `op-kill-or-revive`
- `daemon/src/operations/proactive/recur.rs` — recur fires: query Objectives + Follow-ups where `next_fire_at <= now`; emit Recommendation per item; compute next `next_fire_at` (LLM call to re-parse `recur`); do NOT auto-create new records
- `daemon/src/operations/proactive/touched.rs` — helper: compute `last_touched_at` per Op including linked-Epic slice transitions (proxy work counts as touched)
- `daemon/src/recommendations/op_engine.rs` — Recommendation kinds: `op-stale`, `op-draft-epic`, `op-draft-jira`, `op-draft-briefing`, `op-kill-or-revive`, `op-recur-fire`; payloads include all context needed for handler approval (Op slug, Objective/Follow-up id, draft body, suggested action)
- Cron registration: `proxy-11b-pg-scheduler` job `op-proactive-engine`, cadence `0 */6 * * *`
- `proxy.toml` additions: `[operations.proactive]` section with `enabled = true`, `stale_thresholds = { P0 = "1d", P1 = "3d", P2 = "7d", P3 = "30d" }`, `cron = "0 */6 * * *"`

## Files out of scope

- Triage engine (slice 31) — that's capture-time; this is cron-time
- Recommendation rendering in inbox (existing — `proxy-12-extended`)
- Notification firing (slice 30 handles `remind_at` via scheduler; this slice handles `next_fire_at` via Recommendation only)
- Auto-action execution (never — hard rule #9)
- Cross-Op dependency detection (V2)
- Burndown / time tracking (out of scope indefinitely)

## Stop condition

- [ ] Cron registered with `proxy-11b-pg-scheduler` at 6-hour cadence; verifiable via `proxy scheduler list`
- [ ] Stale detection sweep:
  - [ ] Skips untriaged Ops (priority=unset)
  - [ ] Skips Ops with `state IN ('done', 'burned')`
  - [ ] Uses per-bucket thresholds from `proxy.toml`
  - [ ] Computes `last_touched_at` correctly including linked-Epic slice transitions
  - [ ] Emits at most one `op-stale` Recommendation per (Op, sweep) — dedupes against existing open Recommendations
- [ ] Can-start engine sweep:
  - [ ] `op-draft-epic`: emits with full draft body (matching slice 27's work-request schema) + suggested Epic name + intra-Epic position
  - [ ] `op-draft-jira`: emits with suggested ticket title + description + project key from `jira_project` config
  - [ ] `op-draft-briefing`: emits with email subject + body + recipient resolved from person name (handler's contact list / sender allowlist from ADR 005)
  - [ ] `op-kill-or-revive`: emits with summary of all stale Objectives in the Op + options (kill = state→burned, revive = bump last_touched_at)
  - [ ] All drafts never executed — handler approval via Recommendation acceptance is the only path to action
- [ ] Recur sweep:
  - [ ] Emits `op-recur-fire` for any Objective/Follow-up with `next_fire_at <= now`
  - [ ] After emission, computes new `next_fire_at` from `recur` string via LLM normalize
  - [ ] If LLM normalize fails: emit `op-recur-parse-failed` Recommendation, set `next_fire_at = NULL` (suspends the recurrence until handler fixes)
- [ ] Recommendation handler approval triggers actual action:
  - [ ] `op-stale` accept → bump `last_touched_at` to now (snooze); decline → no-op
  - [ ] `op-draft-epic` accept → create work-request file at proxy-XX-slug.md, add Epic to QUEUE.yaml, link Objective to Epic
  - [ ] `op-draft-jira` accept → create Jira ticket via Atlassian MCP, link Objective to Jira ID
  - [ ] `op-draft-briefing` accept → open compose pane in email Reviewer with pre-filled draft (slice ADR 005 D4)
  - [ ] `op-kill-or-revive` accept → run chosen action (state transition or touch)
- [ ] **Hard rule check**: no path in this slice creates external state without traversing Recommendation acceptance. Audit: grep for direct calls to `create_epic`, `create_jira_ticket`, `send_email` — all must be gated behind Recommendation handler.
- [ ] Cron runs idempotently: repeating the sweep with no state changes = no new Recommendations
- [ ] `cargo test` covers: stale threshold calculation per bucket, touched-includes-Epic-transitions, can-start regex matching, dedup of repeated Recommendations, recur next-fire computation
- [ ] `cargo clippy --all-targets -- -D warnings`

## Feedback loops

- `cargo test`
- `cargo clippy --all-targets -- -D warnings`
- Manual: backdate an Op's `last_touched_at` to 8 days ago (P1), trigger sweep manually via `proxy op sweep --now`, verify `op-stale` Recommendation appears

## Quality bar

production

## v3 context

- See ADR 007 D8 for full engine design
- Hard rule #9 (CLAUDE.md) enforced: draft-only, never auto-action; even Jira ticket creation requires handler approval
- Extends `proxy-11b-pg-scheduler` (cron) and `proxy-12b-recommendations-engine` (Recommendation emission)
- Email Briefing drafts depend on slice 23 (`proxy-23-email-iterative-compose`) for the compose pane integration — if 23 hasn't shipped, draft falls back to plain-text body in Recommendation payload
- Jira ticket creation depends on `proxy-09-jira-integration` (already shipped)
- Recur LLM normalization uses Haiku for cost; falls back to ISO-8601 if string can't be parsed
- Stale thresholds (1d/3d/7d/30d) are initial defaults; tune in `proxy.toml` after first month of use
