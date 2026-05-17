---
name: op-next
description: Fast-query "what should I do next?" for PROXY Operations (ADR 007). Returns a ranked actionable list mixed across Objectives, Follow-ups, Recommendations, exfil-ready packages, and pending Briefings — all rolled up under the active Operation. Use when user types /op-next, asks "what's next?", "what should I work on?", "what's my North Star?", or wants the daily handler-actionable view.
---

Fast-query the active Operation's actionable surface. Returns a ranked list of things the handler can act on **right now**.

## What "active Op" means

Top of the `relymd` theater section in `~/projects/personal-nix/wiki/OPERATIONS.yaml` is the active Op (per ADR 007 D6 — position-as-activeness). V1 has only the `relymd` theater.

## Behavior

1. **Find active Op**: read `OPERATIONS.yaml`, get the first Op slug in the `relymd` theater section.
2. **Load Op state**: read `~/projects/personal-nix/wiki/operations/<slug>.md` frontmatter (objectives + follow_ups).
3. **Compute actionable items** (mixed types):
   - **Objectives with `link.kind == "epic"`**: check if the linked Epic has any slice in `exfil-ready` state → "Review package: slice `<slice-slug>` (`<archetype>`)". (Pre-slice-30: read work-request files in `~/projects/personal-nix/wiki/work-requests/` for status — slice state machine is fs-driven.)
   - **Objectives with `link.kind == "briefing"`**: check if the Briefing is `new` or `opened` → "Respond to Briefing: `<sender>` / `<subject>`". (Pre-slice-22: skip — no Briefings yet.)
   - **Objectives with `link.kind == "jira"`**: check Jira state via existing Atlassian MCP if available → "Action Jira `<ticket-id>`: `<status>`".
   - **Objectives with `link IS NULL`**: "Handler-direct: `<objective-text>`" — these are things only the handler can do.
   - **Follow-ups with `remind_at <= now`**: "Follow-up due: `<text>`".
   - **Follow-ups with `next_fire_at <= now`** (recur fire): "Recurring Follow-up: `<text>` (cycle starts today)".
   - **Stale items**: if `last_touched_at` is past the bucket threshold (P0=1d, P1=3d, P2=7d, P3=30d), append "⚠ Stale: `<item>` (`<n>` days since touched)".
   - **Pending Recommendations**: read inbox surface (pre-slice-32: skip — no Recommendations yet).
4. **Rank**: stale + due Follow-ups first, then exfil-ready packages (handler unblocks proxy work), then handler-direct Objectives, then everything else.
5. **Return top N** (default 5, user can request more via `/op-next --n 10`).
6. **Render**: each item shows type + summary + (when possible) a direct command the user can run (e.g. `proxy queue grab proxy-31` to look at an exfil package; `code ~/projects/personal-nix/wiki/operations/<slug>.md` to edit the Op).

## Output format

```
Active Op: <slug> (<bucket>, <status>)
"<one-line goal from title + description>"

Next up:
  1. <type>: <summary>
     → <suggested action>
  2. <type>: <summary>
     → <suggested action>
  ...
```

## Hard rules

- **Read-only.** This skill never writes. No file mutations, no state transitions.
- **Don't invent items.** If a section has nothing actionable (e.g. no Briefings yet), skip it cleanly — don't fabricate "placeholder" items.
- **Don't include untriaged Ops in the active set** per ADR 007 D7. If the top Op has `priority: null`, walk to the next Op down. If all Ops in `relymd` are untriaged, return "No triaged Op active — run `/op-grill <slug>` to triage one."
- **Pre-slice-32 honesty**: when the proactive engine ships, this skill should also pull pending Recommendations from the inbox. Until then, surface only items derivable from filesystem + existing integrations.
