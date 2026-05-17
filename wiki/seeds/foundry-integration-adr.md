# Seed — Foundry integration ADR

Status: draft seed, not yet authored. Hand-off brief for the next branch's ADR drafter.

## Problem statement

Dev intake currently uses gpt-4o + the `rice-score` skill to triage `work_request` rows, then promotes survivors to Jira via `CreateWorkRequestJiraTicket`. The model has no awareness of the actual codebase — it scores blind. Foundry (RelyMD's Triage / AFK Agent Loop, see `common/docs/foundry/` in the platform repo) is the code-aware replacement: it inspects the monorepo, opens GitHub issues, and can hand AFK-ready Work Items off to agents.

We want to swap the triage backend from gpt-4o to Foundry without rewriting the intake schema, and we want the promotion chain to be tracker-neutral so Jira stays the durable system-of-record for humans while Foundry/GitHub become the durable record for agent work.

## Scope outline

1. **Triage swap** — replace the gpt-4o call inside `TriageWorkRequest` with a Foundry hand-off. The Foundry side runs the code-aware scoring + acceptance-criteria pass and writes the result back into `triageResult` (same JSON shape; agents reading `triageResult` shouldn't have to change).
2. **Tracker chain** — `work_request → Foundry Work Item → GitHub issue → Jira ticket`. Foundry owns the Work Item, GitHub owns the actionable issue (agent-grabbable), Jira owns the human/portfolio view. The chain is one-way; edits propagate from left to right at promotion time, not continuously.
3. **`externalIssueType` discriminator** — already in schema (`'jira' | 'foundry' | 'github'`). The ADR formalizes that exactly one of these is the "primary durable tracker" for a given row, and that downstream UI uses the discriminator to decide which deep-link to render. (The detail page's `Create Jira Ticket` button becomes `Promote to Foundry` once the swap lands.)
4. **Bootstrap-list cleanup** — the original intake form's hardcoded enum lists (`WorkRequestType`, `WorkRequestAreaAffected`, `WorkRequestImpact`) were sized for a wizard that no longer exists post chat-cutover. The chat flow infers these from conversation. Decide whether to keep them, retire them, or move them to per-tenant config now that Foundry is doing the heavy classifying.

## Downstream slice candidates

Each of these is a separately-grabbable follow-up after the ADR lands. None are in the current branch.

- Foundry triage adapter (replace gpt-4o call site)
- Bidirectional sync from Foundry status → `work_request.status` (so the insight-2 detail page stays live)
- `PromoteToFoundry` command (mirror of `CreateWorkRequestJiraTicket`)
- GitHub issue creator (downstream of Foundry promotion)
- 14-day cleanup cron for promoted `work_request` rows (deferred from PLRM-1222)
- `UpdateWorkRequest` command — must reject mutations once `externalIssueKey` is set (post-promotion read-only rule)
- Bottom-left "Submit work request" persistent entry point in insight-2 (replaces sidebar nav for submitters)
- Bootstrap-list retirement (only after Foundry classification is trusted)
- Admin "Edit" feature on detail page (only meaningful for `submitted` / `triaged`, before promotion)
- Jira-push comment threading (so Jira ticket reflects ongoing Foundry/agent activity)

## Decisions inherited from PLRM-1222 (lock in, don't re-litigate)

These were settled on the `feat/PLRM-1222-rice-intake` and `tachikoma/plrm-1222-foundry-badge-and-docs` branches; the ADR should cite them rather than reopen them.

- **`work_request` is a short-lived intake buffer**, not a durable record. The 14-day cron is the explicit signal of that intent.
- **`externalIssue*` columns replace the former `jiraIssue*` columns** (commit `50064d17b`). The schema is tracker-neutral; the discriminator is `externalIssueType`.
- **Post-promotion read-only rule** — once `externalIssueKey IS NOT NULL`, the insight-2 detail page hides edit affordances and any future `UpdateWorkRequest` command must reject the call. Jira (or Foundry, post-swap) is the source of truth from that point.
- **Chat replaced the wizard** at `/dev/intake/create` (commit `9c6756e9e`). `chatTranscript` is persisted as audit, not as the canonical request data — agents synthesise the structured fields from the conversation at submit time.
- **Local-only decision policy** — this branch documents Foundry plans without filing a GitHub issue. The ADR drafter should keep that posture; the actual ADR is the artifact, not a tracking issue.

## Where to look first when drafting

- Platform repo (`~/Projects/platform`):
  - `apps/insight-2/src/features/dev/intake/` — current UI surface
  - `packages/actions/src/commands/workRequests/` — `CreateWorkRequest`, `TriageWorkRequest`, `CreateWorkRequestJiraTicket`
  - `packages/database/src/entities/WorkRequest.ts` — schema + enums
  - `common/docs/foundry/` — Foundry domain docs
  - `docs/adr/` (or context-scoped `docs/adr/` under each context) — ADR location
- Wiki:
  - `~/projects/personal-nix/wiki/seeds/` — this file and adjacent intake/cron seeds
  - `~/projects/personal-nix/wiki/decisions/` — for ADR-lite local follow-ups
