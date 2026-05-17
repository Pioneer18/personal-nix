## Summary

Follow-up to [PLRM-1222](https://relymd.atlassian.net/browse/PLRM-1222). Replaces the static numeric anchors in `RELYMD-PRIMER.md` (Sections 1 & 2) with `{{moustache}}` placeholders that get hydrated at AI-call time from a Redis-cached metrics payload, while keeping the curated narrative content (impact criteria, mis-scoring patterns, effort exemplars) as hand-maintained markdown.

Hybrid model: live numbers + curated reasoning.

## Why

Quarterly batch refresh of the primer creates a 90-day staleness window for numeric anchors. As new tenants onboard / visit volume drifts / new patient cadence shifts, the AI's reach math drifts with it. A 5-minute Redis cache collapses staleness to operational immediacy without losing the human-checkpoint refresh cadence for the curated content.

## Changes

### New: admin metrics endpoint
- `GET /v1/tenants/admin/platform-metrics` — admin-only via `RoleAccessValidator`; returns full `PlatformMetricsPayload` (roles, top tenants, visits, new patients, work-request distribution, RICE distribution).
- `GetPlatformMetrics` CQRS query — Redis-cached at key `platform-metrics:v1`, 5-minute TTL. Cache miss runs 6 SQL queries in parallel (`Promise.all`) adapted from the existing `update-rice-primer/scripts/queries/*.sql`.

### Primer template
- `RELYMD-PRIMER.md` Sections 1 & 2 now use `{{moustache}}` placeholders for all numeric anchors (active user counts, tenant shares, visit volumes, new-patient cadence, etc.). Header documents the template model.
- Section 3 (impact criteria), Section 4 (confidence rubric), Section 5 (effort baselines), Section 6 (mis-scoring patterns) unchanged — those remain hand-curated.
- Section 7 (refresh cadence) updated to describe the new live-hydration model.

### Triage handler
- `TriageWorkRequestHandler` now fetches the metrics payload, hydrates the primer template, computes a SHA-256 `metricsPayloadHash` of the payload, and writes the hash to `triageResult.metadata.metricsPayloadHash` so admins can correlate score variance with primer-hydration refreshes.
- `hydratePrimer()` fails fast with a descriptive error on any unresolved `{{...}}` placeholder — the primer is never sent to gpt-4o with literal mustache markers.
- `RetriggerTriageWorkRequestHandler` updated to pass Redis through to the triage handler constructor.

### Entity
- `WorkRequestTriageResult` type extends with optional `metadata.metricsPayloadHash`.

## Test plan

- [x] `pnpm validate` — typecheck + lint, 101/101 green
- [x] Unit tests for hydration logic — placeholders present pre-hydration · substitution happy path · determinism per cache window · missing-placeholder failure · hash mismatch on different payloads
- [x] Unit tests for `GetPlatformMetrics` query — cache hit short-circuits SQL · payload shape · role aggregation · top-tenants key shape
- [x] Integration test for the admin endpoint — admin gating · returns payload · Redis caching
- [ ] Manual smoke: hit `GET /v1/tenants/admin/platform-metrics` with admin token, then trigger a re-triage on an existing work request and confirm the system prompt embeds live numbers

## Follow-ups (not blocking)

1. **Failure-mode fallback** — the work-request spec called for last-cached payload → baked-in default if metrics fetch fails, with a `degraded: true` flag on triageResult.metadata. Current implementation hard-throws on empty payload. Acceptable for dev/internal-tool volume; file a separate slice for production resilience.
2. **DI pattern cleanup** — `TriageWorkRequestHandler` instantiates `new GetPlatformMetricsHandler(...)` directly instead of going through the bus/container. Works because the handler is stateless; clean up to the tsyringe pattern when the bus pattern stabilises here.

## Branching

- Base: `feat/PLRM-1222-rice-intake` (NOT `develop`) — the rice-score skill + primer + queries live on this feature branch.
- Authored by: Tachikoma loop (`plrm-1222-primer-live-metrics`), human-reviewed.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[PLRM-1222]: https://relymd.atlassian.net/browse/PLRM-1222?atlOrigin=eyJpIjoiNWRkNTljNzYxNjVmNDY3MDlhMDU5Y2ZhYzA5YTRkZjUiLCJwIjoiZ2l0aHViLWNvbS1KU1cifQ
