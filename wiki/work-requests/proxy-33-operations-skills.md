---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-14
---

# PROXY — Operations skills (`/op`, `/op-grill`, `/op-next`) (slice 33)

Three Claude Code slash command skills for Operation capture + query. `/op` = low-friction (title-only async triage). `/op-grill` = high-friction grill walking all fields with inline AI suggestions. `/op-next` = fast-query in chat with actionable buttons.

## Goal

Handler can capture Ops + query the North Star without leaving the chat tab. Voice transcripts (Hey PROXY / Wispr / Open) automatically invoke these skills via existing `tmux send-keys` routing (ADR 002) — no new voice code needed.

After ship, `/op fix the auth latency thing` is a single-shot capture; `/op-grill` opens the structured interview; `/op-next` returns the ranked actionable list right in chat.

## Files in scope

- `~/.claude/skills/op/SKILL.md` — low-friction capture skill
- `~/.claude/skills/op/INSTRUCTIONS.md` — instructions Claude follows when `/op` is invoked
- `~/.claude/skills/op-grill/SKILL.md` — high-friction grill skill
- `~/.claude/skills/op-grill/INSTRUCTIONS.md` — instructions for the structured interview
- `~/.claude/skills/op-grill/GRILL-FLOW.md` — the field-by-field walkthrough spec (title → description → theater → priority → objectives → follow-ups)
- `~/.claude/skills/op-next/SKILL.md` — fast-query skill
- `~/.claude/skills/op-next/INSTRUCTIONS.md` — instructions for rendering ranked items as actionable buttons

Skill invocations call `proxy op` / `proxy op grill` / `proxy op next` CLI under the hood (slice 30). Synchronous dedup runs against slice 31's API; async triage handled by slice 31 worker.

- Skill metadata: `description` field for the user-invocable-skills surface; concise enough to register without bloating the skill list

## Files out of scope

- The CLI commands themselves (slice 30)
- Triage logic (slice 31)
- Proactive engine (slice 32)
- TUI rendering of skill output (slice 34 — North Star pane shows results when skill is invoked from voice)
- Web surfaces (slice 35)

## Stop condition

- [ ] `/op` skill:
  - [ ] Invocation with title arg (`/op fix the auth latency thing`) drops Op immediately after sync dedup check
  - [ ] Invocation without arg (`/op`) prompts handler for title (one-line input)
  - [ ] Sync dedup check: if score > threshold, skill displays "looks like Op `<slug>` — append as Objective, or new?" with [append / new] options
  - [ ] On `append`: invokes `proxy obj add <op-slug> "<title>"`
  - [ ] On `new`: invokes `proxy op new --title "<title>"`; returns Op slug; informs handler "Op `<slug>` captured. Triage Recommendation will appear in inbox shortly."
  - [ ] Returns control to handler within 1s of input (excluding dedup latency)
- [ ] `/op-grill` skill:
  - [ ] Invocation without arg: starts new Op grill
  - [ ] Invocation with arg (`/op-grill <slug>`): grills an existing Op (refines partial fields, asks about missing Objectives, etc.)
  - [ ] Walks fields in order: title → description → theater → priority → objectives → follow-ups
  - [ ] At each step, presents AI suggestion (priority bucket suggested with rationale; Objectives decomposed from description with "accept all / accept partial / override / skip" options; link suggestions per Objective)
  - [ ] Handler can edit any field; AI does not silently override
  - [ ] At end: sync dedup check — if overlap with existing Op, ask "merge into <slug>, or keep separate?"
  - [ ] On confirm: invokes `proxy op grill <slug>` to commit fields; emits Recommendations for any unresolved suggestions
- [ ] `/op-next` skill:
  - [ ] Invocation returns ranked actionable list (~5 items default; `--n 10` to expand)
  - [ ] Each item displays type + summary + action button(s):
    - "Review package" → button to open exfil package
    - "Respond to briefing" → button to open Reviewer at briefing
    - "Approve recommendation" → button to accept / decline
    - "Handler-direct" → button to mark Objective done / link to surface
    - "Follow-up due" → button to resolve / snooze
    - "Stale" → button to snooze / chase / drop
  - [ ] Returns active Op slug + title at top (so handler knows what they're acting on)
- [ ] Voice routing verified: saying "Hey PROXY, new Op fix the auth thing" lands as `/op fix the auth thing` in the chat tab (existing ADR 002 routing — no new code)
- [ ] All three skills work in both single-shot mode (one invocation, return result) and conversational mode (continued grill)
- [ ] Skill files appear in the user-invocable-skills list with concise descriptions
- [ ] Manual: capture an Op via `/op`, verify triage Recommendation appears in inbox; grill it via `/op-grill <slug>`, verify Objectives accepted

## Feedback loops

- Manual: invoke each skill in the chat tab, verify expected behavior
- Manual: invoke `/op` via voice (Hey PROXY mode), verify capture
- No automated test harness for skills (consistent with existing PROXY skills pattern)

## Quality bar

production

## v3 context

- See ADR 007 D7 + D13 for skill design + flow
- Voice integration uses existing `proxy-voice` daemon + `tmux send-keys` routing — no new voice code
- Skills live in `~/.claude/skills/` per existing PROXY skills convention
- Skills must NOT bypass the dedup + triage flow (slice 31) — they're thin shells over the CLI + triage API
- `/op-grill` field-by-field flow follows the same pattern as the existing `grill-with-docs` skill: walk down the decision tree, one question at a time, with inline AI suggestion + handler accept/override
