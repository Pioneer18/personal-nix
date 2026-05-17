## Summary

Follow-up to [PLRM-1222](https://relymd.atlassian.net/browse/PLRM-1222) — the big-bang post-grill cleanup. Removes user-submitted RICE numeric inputs entirely, centralises AI-computed RICE as the canonical source, rebuilds the list and detail surfaces around the simplified data model, and retunes the primer's impact-band criteria.

This collapses ~9 decisions from the design grill into one branch because the changes ripple together (entity columns ↔ migration ↔ command validators ↔ chat prompt ↔ list page ↔ detail page).

## Decisions captured

| Decision | Result in this PR |
|---|---|
| AI score is canonical; drop user RICE numeric inputs | `riceReach` / `riceImpact` / `riceConfidence` / `riceEffort` / `riceScore` columns dropped; `adjustedRiceScore` renamed to `riceScore` |
| Drop `userInputDeltas` from `RiceReasoning` (always empty after dropping user input) | Removed from schema + zod + tests |
| Chat AI never asks for RICE numbers; soft audience question in Standard lane only, encourage specificity but don't require, never ask for effort | `systemPrompt.ts` updated; propose card RICE fields removed |
| Lanes pin to top sections (Emergency, Regulatory) above RICE-sorted Standard queue | List page rebuilt as three stacked sections |
| Detail page: hero band (AI Score · Impact band · Effort band) + acceptance criteria promoted + submission demoted | New `RiceHeroBand` + `WhatNeedsToHappenSection`; `RiceScoreSection` and `RiceScoreDisplay` deleted |
| Reach renders with `/quarter` suffix; Confidence shows breakdown; Effort band-first | `RiceComponentPanel` formatters updated |
| Primer Section 3: add `coordinator` to "primary user role" criteria; drop compliance criteria (lane handles it); sharpen revenue cliff; reword internal-tool | `RELYMD-PRIMER.md` Section 3 edits only |

## Changes by area

- **Database**: drops 5 user-side RICE columns, renames `adjustedRiceScore` → `riceScore`, drops `work_request_impact_enum` Postgres enum type (`packages/database/src/migrations/<timestamp>-CleanupUserRiceColumnsAndRenameAdjustedScore.ts`). Entity reflects the new shape.
- **Actions / CQRS**: `CreateWorkRequest` no longer validates or writes user RICE fields. `TriageWorkRequest` writes the AI score directly to the canonical `riceScore` column (no more "adjusted" variant). `CreateAIResponse` zod schema for the propose-work-request tool drops the RICE fields. `CreateWorkRequestJiraTicket` emits a single `RICE Score: <value>` line in the Jira ticket body.
- **React-core hook**: `useCreateWorkRequest` request-body type drops the RICE fields.
- **Chat**: `systemPrompt.ts` removes the RICE-defaults block, drops the "don't grill for RICE numbers" line, adds the lane-conditional audience-hint guidance. `ProposeWorkRequestCard` strips the RICE numeric fields from the propose UI.
- **List page (`WorkRequestsDataTable`)**: rebuilt as three stacked sections — Emergency lane (top), Regulatory lane, Standard queue (paginated, sorted by `riceScore DESC`). New helpers: `WorkRequestLaneTable`, `WorkRequestSectionShell`, `WorkRequestStandardRow`, `WorkRequestStandardTable`, `WorkRequestStatusBadge`, `WorkRequestTitleLink`, `workRequestRowFormatting`. Triage-failed rows pinned top of Standard; triaging rows at bottom; promoted hidden behind a toggle.
- **Detail page (`WorkRequestDetail`)**: hero band at top with three calibrated headlines. Acceptance criteria promoted to its own top-of-page section (`WhatNeedsToHappenSection`). Submission demoted to mid-page secondary. RICE reasoning panels render the new component formats.
- **Primer Section 3**: coordinator added to primary-user-role criteria. Compliance criteria removed (the Regulatory lane handles routing). Revenue-cliff wording sharpened to cover ongoing leakage and one-shot loss. Internal-tool criterion reworded to drop "not customer-visible" ambiguity.
- **Tests**: new `CreateWorkRequest.unit.test.ts` (237 lines) plus updates to `TriageWorkRequest.unit.test.ts` (+146), `CreateWorkRequestJiraTicket.unit.test.ts`, integration-test fixtures across `apps/api/src/tests/`.

## Migration safety

- Drops are forward-only. The down migration reverses the rename and re-adds the columns with appropriate nullable defaults but cannot recover the dropped enum or per-row data.
- Pre-existing rows on dev DB will lose their user-side RICE values. Acceptable because (a) those values were never source of truth post-grill, (b) PR #891 hasn't merged so no production data is at risk.
- The `work_request_impact_enum` Postgres enum type is dropped after the column is removed.

## Test plan

- [x] `pnpm validate:fix` — typecheck + lint green via tachikoma iter loop
- [x] Unit tests for `CreateWorkRequest` (handler does not touch RICE columns)
- [x] Unit tests for `TriageWorkRequest` (writes to `riceScore`, no `userInputDeltas`)
- [x] Unit tests for `CreateWorkRequestJiraTicket` (single RICE Score line)
- [x] Integration fixtures refreshed
- [ ] Manual smoke: submit a chat-originated request → no RICE numeric inputs on the propose card → triage → list page shows three sections → detail page renders hero band + promoted acceptance criteria
- [ ] Migration runs forward + backward cleanly against dev DB

## Branching

- Base: `feat/PLRM-1222-rice-intake` (NOT `develop`).
- Authored by: Tachikoma loop (`plrm-1222-rice-data-model-cleanup`), human-reviewed.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[PLRM-1222]: https://relymd.atlassian.net/browse/PLRM-1222?atlOrigin=eyJpIjoiNWRkNTljNzYxNjVmNDY3MDlhMDU5Y2ZhYzA5YTRkZjUiLCJwIjoiZ2l0aHViLWNvbS1KU1cifQ
