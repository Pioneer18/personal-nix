---
name: op-grill
description: High-friction structured grill for capturing or refining a PROXY Operation (ADR 007). Walks the user through every field — title, description, theater, priority, Objectives, Follow-ups — one question at a time with inline AI suggestions. Use when user types /op-grill, /op-grill <slug>, says "grill me on this Op", or wants to flesh out an existing Op captured via /op.
---

Structured grill to capture (or refine) a PROXY Operation. Unlike `/op` (low-friction), this walks every field with inline suggestions the user can accept or override.

## What an Operation is

See `/op` skill for short version. Full glossary at `~/Projects/tachikoma-starter/CONTEXT.md`; schema at `docs/adr/007-operations-and-objectives.md`.

## Mode detection

- **No arg** (`/op-grill`): grill a new Op from scratch.
- **Arg given** (`/op-grill <slug>`): grill an existing Op — read its current frontmatter, identify missing/incomplete fields, ask about those only. Don't re-ask fields the user already filled.

## Grill flow (new Op)

Ask one question at a time. Provide a recommended answer with each.

1. **Title** — one-line summary. *Recommend*: terse, action-flavored ("Q2 Platform Stability", not "Make platform more stable").
2. **Description** — short paragraph explaining why this Op exists. *Recommend*: 1-3 sentences.
3. **Theater** — V1 default `relymd`. *Recommend*: accept default unless user signals otherwise (multi-Theater is V2; don't grill for it).
4. **Priority** — P0 / P1 / P2 / P3. *Recommend a bucket* based on the title + description (keywords like "urgent", "blocker", "deadline" → P0/P1; "eventually", "nice to have" → P2/P3). Show the rationale ("I read this as P1 because of the SOC2 deadline mention"). User accepts or overrides.
5. **Objectives** — decompose the description into concrete action items. *Propose 2-5 Objectives* the user can accept all / accept partial / override / skip. Each Objective is one line of text, status=open, link=null. (User can link later via `/op-grill <slug>` re-run, or via `proxy obj link` once slice 30 ships.)
6. **Follow-ups** — loose ends to chase, questions to track, people to ping. *Propose 0-2 Follow-ups* from the description if any names or open questions appear. User accepts / overrides / skips.
7. **Dedup check at end**: re-run the fuzzy title match (same pattern as `/op` skill). If overlap with existing Op: "this overlaps with `<existing-slug>` — merge into it, or keep separate?"

After last question, write the Op file (same format as `/op` skill but with all fields populated) and append to OPERATIONS.yaml.

## Grill flow (existing Op — `<slug>` arg)

1. Read `~/projects/personal-nix/wiki/operations/<slug>.md` frontmatter.
2. Identify missing/incomplete fields: `priority IS NULL`? Empty `objectives` array? Empty `follow_ups`? Stale `last_touched_at` (> 7d)?
3. For each missing/incomplete field, ask the corresponding grill question above. Skip fields that are already populated unless user says "re-grill everything".
4. After grill, update file with new values; bump `last_touched_at`.

## Hard rules

- **One question at a time.** No batched multi-field forms.
- **Always propose a recommendation.** Empty-handed questions are bad UX.
- **User can override any AI suggestion.** Especially priority — never auto-set without an explicit accept.
- **Atomic file writes** (temp + rename).
- **Don't grill for Theater in V1.** Default to `relymd`. Multi-Theater is V2 deferred per ADR 007 D15.
- **Pre-slice-31 limitation**: dedup is title fuzzy match only (no pgvector yet). Surface this in the prompt if user asks: "Full semantic dedup ships with slice 31."
