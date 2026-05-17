---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-17
depends_on: [proxy-v2-22-provider-schema, proxy-v2-23-provider-trait]
quality_bar: production
---

# PROXY v2 — CLI provider verbs (MV8.28)

Add the handler-facing CLI surface for provider control. New `proxy provider` subcommand tree + `--provider` flag on `proxy infil`. The `switch-all-queued` verb is the explicit escape hatch for the "yesterday" rate-limit scenario.

## Goal

Handler can — in one command — flip every queued (not-yet-started) infil from Claude to Codex when Anthropic rate-limits. `proxy provider status` shows current quota state for both providers. `proxy provider pause/resume` manually sets/clears the rate-limit window (for testing or proactive throttling).

## Files in scope

- `daemon/src/cli/provider.rs` (new) — clap subcommand tree
- `daemon/src/cli/mod.rs` — register `provider` subcommand
- `daemon/src/cli/infil.rs` — add `--provider` flag
- `daemon/src/api/provider.rs` (new) — REST endpoints backing the CLI: `GET /api/provider/status`, `POST /api/provider/pause`, `POST /api/provider/resume`, `POST /api/provider/switch-all-queued`
- Tests: `daemon/tests/cli_provider.rs`

## Files out of scope

- The UI surfaces for these endpoints (web + TUI come later; CLI ships first per the agentic-shell ethos)
- Mid-infil provider swap (out of scope per ADR 009 alternative #4)

## Verb spec

```
proxy provider status
  # Tabular view: provider | state | rate_limited_until | last_success_at | total_429_today
  # Example output:
  #   claude   ok        -                   2026-05-17T14:23:01Z   3
  #   codex    ok        -                   2026-05-17T15:01:44Z   0

proxy provider pause <claude|codex> [--until <iso-8601>] [--source <text>]
  # Default --until: NOW() + 5 minutes
  # Default --source: 'manual-pause'

proxy provider resume <claude|codex>
  # Clears rate_limited_until + rate_limit_source; emits provider_quota_cleared NOTIFY

proxy provider switch-all-queued <from> <to> [--dry-run]
  # Affects only infils in state='BRIEFED' OR ('LIVE' AND admission deferred).
  # Excludes any infil whose dossier pins provider (out of scope to override).
  # --dry-run prints what would change without writing.

proxy infil <callsign> --dossier <slug> [--provider claude|codex] ...
  # When --provider omitted: falls back to repo_configs.default_provider, then to proxy.toml [provider].default.
```

## Stop condition

- [ ] `proxy provider status` reads `provider_state` and prints a 2-row table
- [ ] `proxy provider pause/resume` writes the row, emits `provider_quota_cleared` on resume
- [ ] `proxy provider switch-all-queued claude codex` updates affected infils' `provider` column, prints count, supports `--dry-run`
- [ ] `--provider` flag on `proxy infil` validated against the `Provider` enum; bad value rejects with usage hint
- [ ] REST endpoints back each CLI verb (CLI calls them via the existing daemon API client)
- [ ] Endpoint authz: only `localhost`-bound; no remote callers
- [ ] Tests: each verb has a happy-path test + an invalid-input test
- [ ] `cargo build --workspace`, clippy, tests all pass
- [ ] Manual e2e: pause claude → dispatch infil → observe Defer → switch-all-queued → infils flip provider → admission re-runs → infils start

## Feedback loops

- `cargo test -p proxy-daemon cli_provider`
- `proxy provider pause claude --until '2026-05-17T20:00:00Z'`
- `proxy provider status`

## Quality bar

production
