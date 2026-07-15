---
title: "/rmd-triage — re-prioritized RMD ticket stream"
summary: "RelyMD platform skill. Maintains a live-impact-tiered (P0-P3) pickup queue of open RMD Jira tickets on a dedicated ops/rmd-triage git branch. Verbs: read (default), refresh, pickup. See decision rmd-triage-branch-store."
category: "skill"
tags: [relymd, platform, jira, triage, workbench, claude-skill, rmd]
link: "~/Projects/platform/common/agents/skills/rmd-triage/SKILL.md"
last_updated: "2026-07-14"
---

Re-prioritizes open RMD tickets by live patient/end-user impact (not Jira priority), collapsing systemic clusters into single incidents. Ledger lives on the long-lived `ops/rmd-triage` branch (single source of truth), read/written via GitHub MCP with SHA optimistic concurrency. `/rmd-triage` reads the pickup queue; `refresh` re-triages the Jira delta; `pickup <KEY>` verifies + claims (ledger-only; Jira write blocked until Atlassian write tooling exists). Portable to any RelyMD dev. See `decisions/rmd-triage-branch-store.md`.
