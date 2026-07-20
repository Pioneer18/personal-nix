---
title: "/rmd-triage — re-prioritized RMD ticket stream"
summary: "RelyMD platform skill. Maintains a live-impact-tiered (P0-P3) pickup queue of open RMD Jira tickets on a dedicated ops/rmd-triage git branch. Verbs: read (default), refresh, pickup, reconcile. See decision rmd-triage-branch-store."
category: "skill"
tags: [relymd, platform, jira, triage, workbench, claude-skill, rmd]
link: "~/Projects/platform/common/agents/skills/rmd-triage/SKILL.md"
last_updated: "2026-07-20"
---

Re-prioritizes open RMD tickets by live patient/end-user impact (not Jira priority), collapsing systemic clusters into single incidents. Ledger lives on the long-lived `ops/rmd-triage` branch (single source of truth), read/written via GitHub MCP with SHA optimistic concurrency. `/rmd-triage` reads the pickup queue; `refresh` re-triages the Jira delta; `pickup <KEY>` verifies, claims in the ledger, and assigns in Jira for real via `editJiraIssue` + `assignee.accountId` (verified 2026-07-20; confirms first if already assigned to someone else); `reconcile [KEY ...]` judges whether tickets should still exist and still say the right thing (`keep`/`close`/`merge`/`rewrite-ac`/`rescope`/`needs-info`) against the ledger, git, workbench, and sibling tickets, then applies to Jira on confirmation. Portable to any RelyMD dev. See `decisions/rmd-triage-branch-store.md`.
