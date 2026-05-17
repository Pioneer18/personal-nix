---
status: open
priority: 3
target_repo: ~/Projects/platform
github_issue: ""
failure_count: 0
last_updated: 2026-05-16
---

# Foundry integration ADR — dev intake → Foundry triage

> Grilled 2026-05-16. This is a pure documentation synthesis ADR — decisions are inherited from PLRM-1222 branches (lock in, don't re-litigate). Target file: `common/docs/foundry/docs/adr/0004-foundry-integration-from-dev-intake.md`. Ready for tachikoma dispatch.

## Why now

Dev intake currently uses gpt-4o + the `rice-score` skill for triage. Foundry (RelyMD's code-aware Triage / AFK Agent Loop) is the replacement: it inspects the monorepo, opens GitHub issues, and hands AFK-ready Work Items to agents. The PLRM-1222 work shipped the schema groundwork (`externalIssue*` columns replace `jiraIssue*`; chat replaced the wizard; 14-day cleanup cron; post-promotion read-only rule). The remaining missing piece is the ADR that formalizes the swap, names the tracker chain, and lists the downstream slices. Without the ADR, the next implementer would either re-litigate decisions or implement against an unwritten spec.

## Goal

Land `common/docs/foundry/docs/adr/0004-foundry-integration-from-dev-intake.md` (next sequential ADR after 0001/0002/0003) that:

- Formalizes the gpt-4o → Foundry triage backend swap inside `TriageWorkRequest`
- Specifies the tracker chain `work_request → Foundry Work Item → GitHub issue → Jira ticket` and which surface "owns" durably (one-way; left-to-right propagation at promotion time)
- Cements the `externalIssueType` discriminator semantics: exactly one of `jira | foundry | github` is the "primary durable tracker" for a row; downstream UI uses the discriminator to render the right deep-link
- Documents inherited PLRM-1222 decisions (cite, don't re-litigate): work_request is short-lived intake; `externalIssue*` replaces `jiraIssue*`; post-promotion read-only rule; chat replaced wizard; local-only decision policy
- Lists the downstream slice candidates (Foundry triage adapter, sync, PromoteToFoundry command, GitHub issue creator, 14-day cleanup cron, UpdateWorkRequest hardening, bottom-left submit entry, bootstrap-list retirement, admin edit, Jira-push comment threading)
- Calls out the open question: keep / retire / move the bootstrap-list enums (`WorkRequestType`, `WorkRequestAreaAffected`, `WorkRequestImpact`)

## Files in scope

- `common/docs/foundry/docs/adr/0004-foundry-integration-from-dev-intake.md` (new) — the ADR itself
- Reference (read-only context — do NOT modify):
  - `apps/insight-2/src/features/dev/intake/` — current UI surface
  - `packages/actions/src/commands/workRequests/CreateWorkRequest*` — schema-touching commands
  - `packages/actions/src/commands/workRequests/TriageWorkRequest*` — the gpt-4o call site that gets replaced
  - `packages/actions/src/commands/workRequests/CreateWorkRequestJiraTicket*` — the mirror command
  - `packages/database/src/entities/WorkRequest.ts` — schema + `externalIssueType` enum
  - `common/docs/foundry/` — Foundry domain docs (read these for vocabulary alignment)
  - Existing ADRs `common/docs/foundry/docs/adr/0001-runner-orchestration.md` and `0002-runner-credential-management.md` — for ADR style/format reference
- `common/docs/foundry/docs/adr/README.md` (if exists) or the foundry-docs INDEX — update with link to 0004

## Files out of scope

- Implementation of any of the downstream slices (Foundry triage adapter, sync, etc.) — those are separate work-requests, not this ADR
- Schema changes — the `externalIssue*` columns already exist (PLRM-1222 commit `50064d17b`); this ADR cites them
- Touching production code paths in `apps/insight-2/`, `packages/actions/`, `packages/database/` — strictly read-only references
- Per-tenant config for bootstrap-list enums — flagged as open question in the ADR, not resolved here
- Filing a GitHub issue for tracking — per inherited "local-only decision policy" (PLRM-1222), this ADR is the artifact; no issue needed

## Stop condition

- [ ] `common/docs/foundry/docs/adr/0004-foundry-integration-from-dev-intake.md` exists in the platform repo
- [ ] ADR follows the same format as 0001/0002 (status, context, decision, consequences, alternatives if any)
- [ ] Status field: `Accepted` (the decisions are inherited, not proposed)
- [ ] Date: 2026-05-16
- [ ] Sections present:
  - **Context** — current state (gpt-4o + rice-score in `TriageWorkRequest`); why swap; reference PLRM-1222 commits
  - **Decision** — formalize: gpt-4o replaced by Foundry; tracker chain; `externalIssueType` semantics
  - **Inherited decisions (cite, don't re-litigate)** — bullet list with commit refs (`50064d17b`, `9c6756e9e`, etc.)
  - **Downstream slice catalog** — table or bulleted list, 10 items per seed scope
  - **Open questions** — bootstrap-list enum disposition is the named one
  - **Consequences** — what changes for callers, UI deep-link logic, and the 14-day cron
- [ ] Cross-links: cites Foundry docs in `common/docs/foundry/`, references PLRM-1222 branch and commits, references the two existing ADRs
- [ ] Length target: 250-400 lines (matches the existing ADRs' depth)
- [ ] No code changes in this PR — pure docs addition
- [ ] PR opened against `dev` (platform's integration branch) with title `docs(foundry): ADR 0004 — foundry integration from dev intake`
- [ ] `bin/relymd validate` (or whichever doc-validation tool platform uses) passes — no broken links

## Feedback loops

- `git diff` shows ONLY the new ADR file + (optionally) an INDEX/README link addition. If touching any other file, abort and reconsider scope.
- Read the existing ADRs (`0001-runner-orchestration.md`, `0002-runner-credential-management.md`) before drafting — match their tone, depth, and structure.
- After drafting: re-read the seed at `~/projects/personal-nix/wiki/seeds/foundry-integration-adr.md` and verify EVERY inherited decision and slice candidate from the seed appears in the ADR (or is intentionally cut with explanation).
- Manual: `git log --oneline --grep="PLRM-1222"` to confirm commit refs cited in the ADR are accurate.

## Quality bar

production (this is platform-repo work; matches `production` per per-repo config)

## Design notes

- **This ADR is paperwork, not architecture.** The decisions exist already — scattered across PLRM-1222 branches, commit messages, and the wiki seed. The ADR consolidates them so the next implementer has one document to read instead of five branches.
- **Status = `Accepted`, not `Proposed`.** These decisions have already been made and partially shipped (schema migration landed). The ADR documents them retrospectively.
- **Don't expand scope.** The seed explicitly says "downstream slice candidates" are *separate* future work. Don't draft implementation specs in this ADR; just enumerate the slices.
- **Read existing ADRs first.** `common/docs/foundry/docs/adr/0001-runner-orchestration.md` and `0002-runner-credential-management.md` set the house style. Match it — section headers, level of detail, citation format.
- **Use `relymd-dive` first, not `relymd-deep-dive`.** This is a focused ADR draft; the lightweight orientation (~100 lines) is enough. Full deep-dive (260+ lines) is overkill for this scope.
- **Foundry domain vocabulary.** Read `common/docs/foundry/` glossary before writing. Use Work Item / triage / agent loop consistently with how Foundry's own docs use them.
- **Inherited PLRM-1222 decisions: cite commits.** Don't paraphrase decisions; cite the commit SHA (`50064d17b` for `externalIssue*` rename; `9c6756e9e` for chat-replaces-wizard).

## Recommended Tachikoma cap

`--afk 8` — pure documentation work, narrow scope (single new ADR file). Reading existing ADRs + Foundry docs + WorkRequest schema is the bulk of the work; writing is the smaller fraction. Should fit comfortably.

## Related

- `~/projects/personal-nix/wiki/seeds/foundry-integration-adr.md` — the source seed (delete after ADR ships)
- PLRM-1222 branches: `feat/PLRM-1222-rice-intake`, `tachikoma/plrm-1222-foundry-badge-and-docs`
- `~/projects/personal-nix/wiki/work-requests/plrm-1222-*.md` — the chain of PLRM-1222 work-requests this ADR sits atop
- `common/docs/foundry/docs/adr/0001-runner-orchestration.md` — style reference
- `common/docs/foundry/docs/adr/0002-runner-credential-management.md` — style reference
