---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-17
depends_on: [proxy-v2-22-provider-schema, proxy-v2-25-env-auth-injection]
quality_bar: production
---

# PROXY v2 — admission Gate 5 (per-provider quota) (MV8.26)

Extend the four-gate admission rule (ARCHITECTURE.md § 7) with a fifth gate that consults `provider_state.rate_limited_until` for the infil's selected provider. Detect 429 responses in the loop's stdout tail and update `provider_state`. Optional auto-fallback to the other provider for queued-but-not-started infils.

## Goal

When Claude returns 429 mid-infil, the running infil errors naturally (Hard Rule #2 — never kill running infils). Within seconds the daemon's stdout-tail sets `provider_state.claude.rate_limited_until = NOW() + retry_after`. Subsequent admission decisions for Claude-provider infils return `Decision::Defer` until the window clears. If `proxy.toml [provider].fallback_when_rate_limited = "codex"` is set AND the dossier doesn't pin Claude AND Codex's window is clean, admission re-evaluates with `Provider::Codex` and the infil starts. A `feed_item` of kind `provider_auto_failover` records the switch.

## Files in scope

- `daemon/src/admission/mod.rs` — add Gate 5 after the existing four
- `daemon/src/admission/provider_quota.rs` (new) — read provider_state, evaluate window, propose fallback
- `daemon/src/runtime/stdout_tail.rs` (or wherever the loop's stdout is tailed) — detect 429 markers per provider; write `provider_state`
- `daemon/src/db/queries/provider_state.rs` (new) — typed CRUD for the new table
- `daemon/src/scheduler/listen_notify.rs` — add `provider_quota_cleared` channel; daemon task that polls `rate_limited_until` and `NOTIFY`s when the window elapses
- `daemon/src/feed_items/kinds.rs` (or equivalent) — add `provider_rate_limited`, `provider_auto_failover`
- `~/.config/proxy/proxy.toml.example` — document `[provider]` block

## Files out of scope

- CLI verbs (MV8.28)
- Chat-tab voice integration (MV8.27)
- Daily 429 counter rollover (cron concern — schedule into the daemon's tick loop, but no UI yet)

## 429 detection

Parsed from the loop's stdout. Both `claude` and `codex` emit recognizable error markers:

- Claude: lines matching `^.*429.*rate.?limit` or HTTP error blocks containing `"type":"rate_limit_error"`
- Codex: lines matching `^.*429` or `RateLimitError`

Per-provider regex set lives in `Provider` trait (extend it with `fn rate_limit_pattern(&self) -> &'static Regex`). When matched, the tail task writes `provider_state` and emits a `feed_item`.

Heuristic when `retry-after` header isn't extractable: 5 minutes for Claude (matches Anthropic's typical Max-tier reset), 1 minute for Codex (more aggressive recovery).

## Stop condition

- [ ] `admission::check()` calls Gate 5 after the existing four; returns `Decision::Defer { reason, retry_after_seconds, fallback: Option<Provider> }` when the selected provider is rate-limited
- [ ] `provider_state` read/write functions; transactional updates with `last_success_at` reset on next-success path
- [ ] Stdout-tail recognizes 429 markers per provider; writes `provider_state.rate_limited_until` with the right window
- [ ] `feed_items` of kind `provider_rate_limited` written on detection
- [ ] Optional auto-failover: when `proxy.toml [provider].fallback_when_rate_limited = "codex"`, `infil.provider` is unpinned (no dossier-level override), and Codex's window is clean → re-evaluate admission with `Provider::Codex`; write `feed_item` of kind `provider_auto_failover`
- [ ] LISTEN/NOTIFY channel `provider_quota_cleared` emits when a window elapses; admission re-runs for pending infils
- [ ] Daily 429 counter (`total_429_today`) increments; rollover at local midnight (use `chrono::Local` for the rollover boundary)
- [ ] Unit tests cover: 429 detection from sample stdout (both providers); window-elapsed re-admission; auto-failover triggers; auto-failover skipped when dossier pins provider
- [ ] Integration test: simulate Claude 429 → infil errors → state row written → next dispatch defers → after window → admission re-runs and succeeds

## Feedback loops

- `cargo test -p proxy-daemon admission::gate_5`
- `cargo test -p proxy-daemon stdout_tail::rate_limit_detection`
- `cargo clippy --workspace --all-targets -- -D warnings`
- Manual: launch an infil, manually `UPDATE provider_state SET rate_limited_until = NOW() + interval '5 min'`, dispatch another infil, observe `Defer` response

## Quality bar

production
