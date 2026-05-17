---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-17
depends_on: [proxy-v2-01-schema-migration]
quality_bar: production
---

# PROXY v2 — provider schema (MV8.22)

Add the schema surface for ADR 009's provider abstraction: `provider` column on `infils`, `default_provider` on `repo_configs`, and a new `provider_state` table tracking per-provider rate-limit windows. Forward-only sqlx migration. Rust types in `daemon/src/db/types.rs` gain a `Provider` enum, an updated `Infil` struct with the new field, and a fresh `ProviderState` struct.

## Goal

`sqlx migrate run` against an already-v2-migrated DB adds the provider columns + table without disrupting existing rows. New `Infil` rows default `provider='claude'`; admission, runner, and CLI code keeps compiling unchanged (none of it reads the new column yet — that's MV8.23-26). `cargo build` passes.

## Why now

MV8.23 (`Provider` trait) and MV8.26 (admission Gate 5) both read these columns; landing them without the schema in place would block both. Schema-first is the cheapest unblock.

## Files in scope

- `daemon/migrations/<timestamp>_provider_abstraction.sql` (new)
- `daemon/src/db/types.rs` (add `Provider` enum, extend `Infil`, add `ProviderState` struct)
- `daemon/src/db/mod.rs` (export new types if not re-exported via `pub use types::*`)

## Files out of scope

- `Provider` trait + Claude/Codex impls (MV8.23)
- Container image rebuild (MV8.24)
- Env/auth injection (MV8.25)
- Admission Gate 5 (MV8.26)
- Chat tab tmux layout (MV8.27)
- CLI provider verbs (MV8.28)
- Codex addendum seed data (MV8.29)

## Stop condition

- [ ] Migration creates PG enum `provider_kind` with values `('claude','codex')` — matches the `infil_state` / `dossier_state` pattern from MV1.01
- [ ] Migration adds `provider provider_kind NOT NULL DEFAULT 'claude'` to `infils`
- [ ] Migration adds `default_provider provider_kind NOT NULL DEFAULT 'claude'` to `repo_configs`
- [ ] Migration creates `provider_state` table: `provider provider_kind PRIMARY KEY`, `rate_limited_until TIMESTAMPTZ`, `rate_limit_source TEXT`, `last_success_at TIMESTAMPTZ`, `total_429_today INTEGER NOT NULL DEFAULT 0`, `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- [ ] Migration seeds `provider_state` with rows `('claude')` and `('codex')` via `ON CONFLICT DO NOTHING`
- [ ] All DDL idempotent: `CREATE TYPE` wrapped in `DO $$ … EXCEPTION WHEN duplicate_object THEN NULL; END $$;`; `ALTER TABLE … ADD COLUMN` wrapped in `DO $$ … EXCEPTION WHEN duplicate_column THEN NULL; END $$;`; `CREATE TABLE IF NOT EXISTS`
- [ ] `Infil` struct in `db/types.rs` gains `pub provider: Provider`
- [ ] New `Provider` enum mirrors the PG enum values; lowercase wire encoding; derives Serialize / Deserialize / `sqlx::Type` with `type_name = "provider_kind"`
- [ ] New `ProviderState` struct mirrors the table column-for-column; derives `sqlx::FromRow`
- [ ] Round-trip test for `Provider` serde mirrors the existing `infil_state_serde_matches_pg_enum_values` test
- [ ] `cargo build --workspace` passes with no warnings
- [ ] `cargo clippy --workspace --all-targets -- -D warnings` passes

## Feedback loops

- `cd daemon && cargo build --workspace`
- `cd daemon && cargo clippy --workspace --all-targets -- -D warnings`
- `cd daemon && sqlx migrate run` against a fresh DB seeded through v2 migrations
- `psql -c "\d infils" | grep provider` and `psql -c "\d+ provider_state"`

## Quality bar

production
