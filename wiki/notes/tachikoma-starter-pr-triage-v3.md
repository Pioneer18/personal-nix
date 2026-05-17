---
title: "tachikoma-starter — v2/v3 PR triage (2026-05-11)"
tags: [pr-triage, tachikoma-starter, v3-migration, one-time]
last_updated: "2026-05-11"
---

# tachikoma-starter PR triage (2026-05-11) — v2/v3 transition

15 open PRs accumulated from a v1-era Tachikoma queue burst on 2026-05-11. After the v2 redesign and the v3 agentic-shell expansion that same day, several PRs target now-obsolete designs. This triage records the disposition of each so we can stop accumulating cleanup debt.

**Triage performed by**: 2026-05-11 design session synthesis pass.
**Approval needed before action**: yes — recommendations only. User decides.

## Categories

- **KEEP** — directly aligned with v2/v3; merge when reviewed.
- **AMEND** — partially aligned; needs follow-up commit before merge (e.g. drop BullMQ usage, swap to sqlx).
- **OBSOLETE** — superseded by v2/v3 architectural decisions; close without merging.
- **EXTEND** — keep + add follow-up scope (v3 extensions).

## Triage table

| # | Title | Slice | Disposition | Reason |
|---|---|---|---|---|
| 21 | proxy-17 filesystem → PG queue migration | proxy-17 | **KEEP** | Still required to cut over from skill-based queue to daemon-managed queue. v3 doesn't change this. |
| 20 | proxy-01b Rust daemon scaffold | proxy-01b | **KEEP — high priority merge** | Exact match for M3's first slice. Foundation for everything downstream. Verify it follows the Cargo workspace layout in ADR 004. |
| 19 | proxy-16 Ink TUI control hub | proxy-16 | **KEEP** | Aligned with M4 (proxy-16-extended). The "extended" scope is mainly status-bar wiring + voice mode display — small addition post-merge. |
| 18 | proxy-15 notifications (BullMQ scheduling, notified flag) | proxy-15 | **AMEND** | UI / notified flag concept is salvageable. **BullMQ scheduling must be removed** (per v2/v3 PG-scheduler decision). Notification delivery itself needs the bundled signed Swift app (v3 § 19, M5 — `notify-app/`). Recommend: split into "UI + DB schema" (mergeable now) and "delivery mechanism" (becomes proxy-15-extended in M5). |
| 17 | proxy-14 notebook | proxy-14 | **KEEP** | v3 doesn't change. M6 web UI will render the notebook entries. |
| 16 | proxy-13 email-ingestion (Gmail OAuth + BullMQ data_ingestion worker) | proxy-13 | **AMEND** | Gmail OAuth + feed-item generation is salvageable. **BullMQ worker must be removed** — refit to in-daemon PG scheduler (per v2 disposition). Treat as proxy-13-refitted. Recommend: salvage OAuth UI + tokens-in-DB, rework the worker into a daemon-scheduled job. |
| 15 | proxy-12 activity feed + inbox | proxy-12 | **EXTEND** | Aligned with v3's "extended" scope: also surfaces `system_recommendations` rows (v3 § 8 system manager). Recommend: merge as-is, then follow-up commit adds recommendation rendering. |
| 13 | proxy-10 auto-tag commits + PRs | proxy-10 | **KEEP** | v3 doesn't change. |
| 12 | proxy-09 Jira integration | proxy-09 | **KEEP** | v3 doesn't change. |
| 11 | proxy-08 GitHub Issues integration | proxy-08 | **KEEP** | v3 doesn't change. |
| 10 | proxy-07 encrypted PAT mgmt | proxy-07 | **AMEND** | v2 § 10 disposition: "encryption moves to the Rust daemon (use age or RustCrypto)." If this PR's encryption is in TypeScript, the work must be re-implemented in Rust as part of M3. Recommend: keep the AES-256-GCM scheme + Settings UI; defer Rust port to a follow-up commit landing alongside proxy-01b. |
| 9 | proxy-06 per-repo config | proxy-06 | **EXTEND** | Aligned with v2 "extended" + v3 fields. Recommend: merge as-is; v3 adds memory_limit_mb, max_concurrent_per_repo, backend, voice config fields in a follow-up commit (per ADR 004 proxy.toml schema). |
| 7 | proxy-03 work-request CRUD UI | proxy-03 | **KEEP** | v3 doesn't change CRUD; M3 daemon will replace the BullMQ-backed worker behind it but the API + UI stay. |
| 6 | proxy-02 core DB schema + state machine | proxy-02 | **EXTEND** | v2 "extended" adds sensor_samples, system_recommendations, apps_registry, host_metrics tables. v3 adds proxy_voice_state, proxy_voice_events, computer_use_audit tables. Recommend: merge proxy-02 as-is; M3's proxy-02-extended PR adds the v2/v3 tables. |
| 5 | proxy-01 scaffold (Turborepo + Docker Compose) | proxy-01 | **AMEND** | Turborepo + apps/web + apps/tui structure: KEEP. PG container: KEEP. **Redis container**: drop (v2 dropped Redis with BullMQ). **Always-on Next.js**: change to daemon-managed-subprocess (v3 § 16). Recommend: merge with a follow-up commit removing Redis from docker-compose and making Next.js launch lazy. |

## Counts

- **KEEP** (merge as-is): 8 PRs — #21, #20, #19, #17, #13, #12, #11, #7
- **EXTEND** (merge + follow-up): 3 PRs — #15, #9, #6
- **AMEND** (merge + corrections): 3 PRs — #18, #16, #10, #5
- **OBSOLETE**: 0 PRs

Wait — re-count: 8 + 3 + 4 = 15. ✓ matches total.

## Recommended order of merge

To minimize merge conflicts, suggested order:

1. **Foundation first**: #5 (scaffold), #6 (DB schema), #20 (Rust daemon) — these underlie everything. AMEND #5's Redis removal as a separate follow-up.
2. **Core flows**: #7 (CRUD UI), #11 (GH integration), #12 (Jira), #13 (auto-tag)
3. **Per-repo + auth**: #9 (per-repo config), #10 (PAT mgmt — note Rust port follow-up)
4. **Feed + UI**: #15 (feed + inbox), #19 (Ink TUI)
5. **Background jobs**: #18 (notifications — split UI vs delivery), #16 (email ingestion — refit needed), #17 (notebook)
6. **Migration**: #21 (filesystem → PG queue cutover)

## Follow-up commits required (after merge)

These corrections need to land before the affected slice is "done":

| PR | Follow-up |
|---|---|
| #5 | Remove `redis` from docker-compose; make Next.js a daemon-managed subprocess (proxy-12-extended in M6) |
| #18 | Split into UI/DB (this PR, AMENDED to remove BullMQ) + delivery (proxy-15-extended in M5 with Swift notify-app) |
| #16 | Refit BullMQ worker → in-daemon PG scheduler (proxy-11b + proxy-13-refitted) |
| #10 | Port AES-256-GCM encryption from TS → Rust daemon (proxy-07-rust-port; lands with M3) |
| #15 | Extend to render `system_recommendations` rows (M5) |
| #9 | Add v3 fields to per-repo config (M3's proxy-06-extended commit) |
| #6 | Add v2/v3 tables (M3's proxy-02-extended PR) |

## Recommended action

1. Review this triage with the user.
2. For KEEP PRs: enable `/auto-review-prs auto` (autonomous-only mode) on `tachikoma-starter`. The 8 clean PRs auto-merge if they pass the strict rubric. Walk through the rest in Pass 2.
3. For AMEND PRs: add comments per the "Follow-up commits required" table; merge when corrections land or open follow-up PRs.

## See also

- `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` § 10 — original slice disposition table (v2 perspective)
- `~/Projects/tachikoma-starter/docs/adr/004-cargo-workspace-and-tech-stack-lockin.md` — Cargo workspace + tech-stack final decisions
- `~/projects/personal-nix/wiki/recipes/agentic-shell-v1-slice-plan.md` — M1-M7 v1.0 build plan
- `~/projects/personal-nix/wiki/recipes/mac-pre-proxy-prep.md` — original observation that some PRs were obsoleted
- `~/.claude/skills/auto-review-prs/` — the user's PR triage skill
