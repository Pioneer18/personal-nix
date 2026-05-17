---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-14
---

# PROXY — Operations triage engine (slice 31)

Dedup detection + priority suggestion + position suggestion + Objective decomposition + async triage worker for newly-captured Operations. Builds on slice 30's pgvector substrate.

## Goal

When the handler captures an Op via `/op` (low-friction) or `/op-grill` (high-friction), this slice provides the triage intelligence:

1. **Synchronous dedup** at capture time (called by skills, slice 33): pgvector cosine on title+description vs existing Ops; surfaces "looks like Op X" prompt above threshold.
2. **Async triage worker** that runs after low-friction Op drop: suggests priority bucket, position-within-bucket, and (when title implies it) initial Objectives. Result lands as a Recommendation in the inbox.
3. **High-friction inline suggestions** (called from `/op-grill`): for each field (priority, Objectives, links), produces a suggestion the handler can accept/override.

Untriaged Ops (priority=unset) remain excluded from next-up engine consumption (slice 32) until handler accepts the triage Recommendation.

## Files in scope

- `daemon/src/operations/triage/mod.rs` — public API: `dedup(text) -> Vec<(op_slug, score)>`, `triage_async(op_id)`, `suggest_priority(op_id) -> Priority`, `decompose_objectives(description) -> Vec<ObjectiveText>`, `suggest_links(objectives) -> Vec<Option<LinkRef>>`
- `daemon/src/operations/triage/dedup.rs` — pgvector cosine similarity query; threshold tunable via `proxy.toml` (default 0.85)
- `daemon/src/operations/triage/priority.rs` — heuristics + LLM call: keyword patterns ("urgent", "blocker", "P0"), theater rules, linked-Epic-state lookup (if any Objective links to a top-of-Queue Epic → suggest P0/P1)
- `daemon/src/operations/triage/decompose.rs` — LLM call: given description, return ranked Objective candidates as plain text
- `daemon/src/operations/triage/links.rs` — heuristic + LLM call: for each Objective text, search Epics by slug similarity, search Jira tickets by `jira_project=PLRM` keyword, search recent Briefings by sender/subject, propose best match (or none)
- `daemon/src/operations/triage/worker.rs` — async worker that processes triage queue: pulls `priority=unset` Ops, runs full triage, emits Recommendation
- `daemon/src/recommendations/op_triage.rs` — Recommendation kind: `op-triage`; payload includes suggested priority, position, Objectives, link suggestions; handler can accept all, accept partial, or override
- `proxy.toml` additions: `[operations]` section with `dedup_threshold = 0.85`, `triage_model = "claude-haiku-..."`, `decompose_max_objectives = 5`

## Files out of scope

- Capture skill UX (slice 33) — this slice exposes the API; skill consumes it
- Proactive engine cron (slice 32) — separate concern; this slice handles new-capture triage only
- pgvector extension install (slice 30)
- Embedding computation on Op create (slice 30)
- Web UI for accepting triage (slice 35)
- TUI display of triage Recommendations (slice 34)

## Stop condition

- [ ] `dedup(text)` returns ranked list of existing Ops with cosine score > threshold; threshold configurable in `proxy.toml`
- [ ] Dedup query latency p95 < 500ms with up to 100 existing Ops (verified with synthetic data)
- [ ] `triage_async(op_id)` is enqueued on Op create when `priority IS NULL`; runs within 30s of capture
- [ ] `suggest_priority(op_id)` returns a P-bucket plus a short rationale string; rationale included in Recommendation payload
- [ ] Priority heuristic considers: title keywords, theater config, linked Epic state (if any Objective links to a top-of-Queue Epic → bias to P0/P1)
- [ ] `decompose_objectives(description)` returns 0-5 Objective candidates; respects `decompose_max_objectives` cap; never invents links (links suggested separately)
- [ ] `suggest_links(objectives)` proposes Epic/Jira/Briefing matches OR returns None per Objective; never auto-applies
- [ ] Recommendation `op-triage` emitted with all suggestions; handler accepts via web/TUI/CLI → applies changes atomically (priority, position, Objectives, links)
- [ ] Untriaged Ops (priority=unset) are filtered out of slice 32's stale-detection + can-start engine inputs
- [ ] LLM calls use prompt caching where possible (system prompt + theater config cached)
- [ ] LLM call failures log warning + emit a Recommendation `op-triage-failed` with the raw error; do NOT block Op (it stays untriaged, handler can re-triage manually)
- [ ] `proxy op triage <slug>` CLI command to manually re-run triage on an existing Op
- [ ] `cargo test` covers: dedup ranking with synthetic embeddings, priority heuristic edge cases (keyword match, theater override, linked-Epic boost), decompose contract (returns valid Objective text array), triage worker queue semantics
- [ ] `cargo clippy --all-targets -- -D warnings`

## Feedback loops

- `cargo test`
- `cargo clippy --all-targets -- -D warnings`
- Manual: capture an Op via `proxy op new`, observe triage Recommendation appears in inbox within 30s, accept it, verify Op gains priority + Objectives

## Quality bar

production

## v3 context

- See ADR 007 D7-D9 for triage decisions
- pgvector dedup threshold (0.85) is an initial guess; expect calibration on real data — track in slice followup
- Embedding model TBD here if slice 30 default proves insufficient; revisit
- LLM model choice: prefer Haiku for triage (cheap, fast, sufficient quality); Sonnet only if Haiku quality fails on real data
- Triage worker reuses `proxy-11b-pg-scheduler` queue infrastructure (LISTEN/NOTIFY)
- Recommendations consumed by existing inbox surface (proxy-12) and slice 32's proactive engine
