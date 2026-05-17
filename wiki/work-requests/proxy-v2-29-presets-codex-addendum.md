---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-17
depends_on: [proxy-v2-04-presets-seed, proxy-v2-23-provider-trait]
quality_bar: production
---

# PROXY v2 — Codex addendum for 4 callsigns (MV8.29)

The `proxy_presets` table holds a single `prompt_addendum` column (Anthropic-XML-shaped). Codex (OpenAI) wants the same callsign personality but in a slightly different prompt shape — markdown-ish, no XML wrappers. This slice adds a per-(callsign, provider) addendum storage and seeds the 4 callsigns × 2 providers (8 rows). `Provider::callsign_addendum()` reads from this table.

## Goal

When an infil starts with `provider='codex'`, the runner injects the Codex-shaped addendum for the chosen callsign; with `provider='claude'`, it injects the Claude-shaped addendum. Behavior knobs (`pause_on`, `emit_cadence`, etc.) stay singular on `proxy_presets` — they're provider-neutral.

## Why now

ADR-005-v2 D5 specifies system-prompt addendums per callsign as the load-bearing personality lever. Without a Codex-shaped variant, every Codex infil gets Claude-shaped XML instructions that may degrade behavior. Codex callsign quality is no worse than Claude callsign quality only after this lands.

## Schema decision

Add a sibling table `proxy_preset_addendums` keyed on (callsign, provider):

```sql
CREATE TABLE IF NOT EXISTS proxy_preset_addendums (
  callsign        TEXT NOT NULL REFERENCES proxy_presets(callsign) ON DELETE CASCADE,
  provider        TEXT NOT NULL CHECK (provider IN ('claude','codex')),
  prompt_addendum TEXT NOT NULL,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (callsign, provider)
);
```

Keep the `proxy_presets.prompt_addendum` column for the v1 read path (fallback if the addendum table is empty for that pair) — drop in a future slice once both providers are seeded everywhere.

## Files in scope

- `daemon/migrations/<timestamp>_proxy_preset_addendums.sql` (new — table + initial seed)
- `daemon/src/db/types.rs` — add `ProxyPresetAddendum` struct
- `daemon/src/providers/claude.rs` — `callsign_addendum()` reads from new table (provider='claude'), falls back to `proxy_presets.prompt_addendum`
- `daemon/src/providers/codex.rs` — same, provider='codex'
- `daemon/src/providers/tests.rs` — extend tests for fallback + lookup

## Codex addendum drafts (4 callsigns)

Drafted by the slice author (handler review required before seed). Source: take each Claude addendum, strip XML, rephrase imperatives in plain markdown, preserve every concrete behavior directive verbatim. Length: 3-8 sentences, matching the Claude version's token count within ~20%.

Initial drafts produced in this slice; handler reviews + edits before the migration is merged.

## Stop condition

- [ ] Migration creates `proxy_preset_addendums` table
- [ ] Migration seeds 8 rows (4 callsigns × 2 providers); Claude rows duplicate `proxy_presets.prompt_addendum` text
- [ ] `Provider::callsign_addendum()` queries the new table; falls back to `proxy_presets.prompt_addendum` when no row exists for that (callsign, provider)
- [ ] Codex addendum drafts reviewed + approved by handler (review step in PR)
- [ ] Tests: lookup hits, fallback hits, missing callsign errors clearly
- [ ] `cargo build`, clippy, tests pass

## Feedback loops

- `cargo test -p proxy-daemon providers::callsign_addendum`
- `psql -c "select callsign, provider, length(prompt_addendum) from proxy_preset_addendums"`
- Manual: launch a Codex infil on each callsign, inspect the spawned prompt for the right addendum

## Quality bar

production
