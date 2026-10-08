---
title: "/desk: personal markdown ledger, agent for language + CLI for mechanics"
tags: [desk, tasks, meetings, prioritization, claude-skill, personal]
last_updated: "2026-09-30"
status: accepted
---

# /desk personal ledger

**Status**: Accepted, 2026-09-30 (grill-me session, built the same day).

## Context

Jonathan is Engineering Program Lead (ApolloMD) + Senior Developer (RelyMD). He has high meeting volume and a steady stream of one-off asks. Tasks got lost in scattered notes, and priority was hard to keep visible. He needed near-zero-friction capture, with the value in organization, prioritization, tracking, and quick reference. The tool is personal, not a team tool.

## Options considered

- Build on PROXY (Ops/Follow-ups, daemon + Postgres): rejected. Capture must never depend on a daemon, and the user said the two are unrelated.
- Store the data in personal-nix/wiki: rejected. The content is sensitive (people, org, vendor), and transcripts are high-volume.
- One big TASKS.md: rejected. Whole-file rewrites, no per-task progress log, and hard to query.
- Pure-agent ordering/rendering: rejected. An LLM re-sorting hundreds of items will eventually drop a P0, and IDs could collide.

## Decision

- Data: `~/projects/desk/`, private GitHub `Pioneer18/desk` (SSH remote). The CLI commits on every write, and launchd pushes daily at 18:00. **Never** in the platform repo.
- One file per item with frontmatter: `tasks/T-####` (closed → `tasks/done/YYYY-MM/`), `meetings/YYYY/MM/`, `people/`, `projects/`, `ref/`, `reports/`. `NOW.md` is generated.
- Kinds: mine / delegate / waiting / ask. Delegate → handoff → waiting.
- Priority: P? / P0 fire / P1 now / P2 planned / P3 someday (hidden). FIFO inside a bucket plus a `top` pin. Due within 2 business days → Due-soon strip; past due → OVERDUE. Waiting items get a nudge date (default +3 business days), not a priority. Ask items have no priority.
- The AI suggests P-levels with a reason, never blocks capture, and never auto-promotes. P0 suggestions are loud. A per-person `urgency_bias` discounts habitual "ASAP".
- Capture: infer → write → receipt. The only question it asks is before creating a new person/project. Meetings are the exception: a draft is shown before anything is written.
- PHI: redacted on ingest (hard rule), `desk phi-scan` backstop, original docs not kept.
- External: Jira/PR links on tasks, read-only status checks that only suggest closing. No ticket creation in v1.
- Stdlib Python CLI (`skills/desk/bin/desk`, 3.9-compatible for `/usr/bin/python3`) owns IDs, ordering, NOW, moves, and git. The agent owns classification, extraction, matching, and suggestions.
- Triggers: explicit "desk" only. Generic "note this"/"remember this" is left to the platform `inbox` skill to avoid routing personal notes into team scratch.

## Consequences

- Board correctness is unit-tested (`skills/desk/tests`).
- New skills or verbs extend the CLI first, then SKILL.md.
- Possible later additions: GDEV ticket creation from delegate handoff, calendar-aware `/desk day`.
