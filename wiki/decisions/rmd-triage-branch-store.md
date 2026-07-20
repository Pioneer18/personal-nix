---
title: "RMD triage ledger lives on a dedicated git branch, not Confluence"
tags: [relymd, platform, jira, confluence, triage, atlassian-mcp, git, claude-skill]
last_updated: "2026-07-14"
status: accepted
---

# RMD triage ledger on an ops/rmd-triage branch

**Status**: Accepted — 2026-07-14.

**Scope**: The `/rmd-triage` RelyMD platform skill (`~/Projects/platform/common/agents/skills/rmd-triage/`) and its ledger.

## Context

`/rmd-triage` maintains a re-prioritized stream of open RMD Jira tickets, tiered P0-P3 by live patient/end-user impact, for any RelyMD developer to pick up. The stream must be a single shared source of truth that an unattended 7am job can write and every dev can read, using only tooling each dev already has (no per-machine secrets).

The natural home was Confluence: a single shared page, editable by the job and by devs, visible to non-dev stakeholders (Tina/Alyssa). It was blocked by tooling.

## Options

1. **Repo file on `develop`** — works today, but freshness propagates only through PRs; a daily auto-refresh means daily PR churn, and claims collide as merge conflicts.
2. **Confluence single page** — best UX (single doc, atomic-ish edits, stakeholder-visible) but requires a **write path that does not exist**. The repo's Atlassian MCP is read-only: every tool is `get*`/`search*`, with no `updateConfluencePage`, `createConfluencePage`, `transitionJiraIssue`, or `assignJiraIssue`. A per-dev scoped API token (the RICE-intake pattern) is exactly the "only on my machine" trap to avoid.
3. **Dedicated `ops/rmd-triage` git branch** — the ledger file lives on a long-lived branch, read/written via the GitHub MCP against the remote branch (never the dev's checkout). The blob SHA is an optimistic lock: stale-SHA write fails, re-read/re-apply/retry. Git is universal, gives free history, needs no new credentials.

## Decision

**Option 3.** The ledger is one markdown file on the `ops/rmd-triage` branch. I/O via GitHub MCP (`get_file_contents` / `create_or_update_file` with SHA). Never merged to `develop`, excluded from CI, rebuildable via `refresh --full`.

Corollaries forced by the read-only Atlassian MCP:

- **Overlay-only**: the re-prioritization tier is never written back to Jira's priority field. *(Still holds.)*
- **Pickup claims are ledger-only**: `pickup` records the claim in the ledger and prints a manual "assign yourself in Jira" reminder; it cannot assign/transition in Jira. — **⚠️ SUPERSEDED 2026-07-20, see Update below.** Assignment and transition both work now.

## Consequences

- Single source of truth today, portable to every dev, no new secrets, no PR churn, no merge-conflict claims.
- Cost: the ledger lives off `develop`, so it is not in a dev's working tree — the skill is the interface; GitHub gives a web view + history. Mildly unconventional branch that must be documented so nobody merges or garbage-collects it, and CI must filter `ops/**`.
- **Future swap**: if Atlassian write tooling is enabled org-wide, the store can move to a Confluence page and pickup can gain real Jira assignment. Only `references/store.md` changes; the triage brain is store-agnostic.

## Update — 2026-07-20: write tooling arrived, store stays

The "future swap" trigger above **partly fired**. The Rovo Atlassian MCP now exposes `editJiraIssue`, `transitionJiraIssue`, `addCommentToJiraIssue`, `createIssueLink`, `createConfluencePage`, and `updateConfluencePage`. Option 2 is no longer tooling-blocked.

**The store decision does not change.** The ledger stays on `ops/rmd-triage`, for reasons that were secondary in the original weighing and are now primary:

- The re-prioritization is an **overlay**. Tiers are this skill's judgment, not shared truth; pushing them into Jira or a stakeholder-visible Confluence page makes them look authoritative to people who did not opt into the rubric.
- **Git history and SHA optimistic concurrency are load-bearing**, not incidental. They are what serialize the unattended job against on-demand refreshes and pickup claims. Confluence gives no equivalent primitive.

**What did change**: the new `reconcile` verb writes real ticket changes back to Jira (transition, comment, duplicate-link, acceptance-criteria edit) on explicit confirmation. It is the only verb that writes to Jira, it never writes tiers, and it is propose-only when unattended. `close` transitions with a resolution; it never deletes.

The **pickup corollary is retired.** Verified 2026-07-20 against RMD: there is no dedicated assign tool, but `editJiraIssue` with `fields: { assignee: { accountId } }` sets it directly and succeeds. Resolve the accountId via `atlassianUserInfo` (current user) or `lookupJiraAccountId` (anyone else). `pickup` now assigns for real, so the ledger claim and Jira agree instead of relying on a human to follow a printed reminder.

Two behaviours the verification established:

- Re-assigning a ticket to the accountId it already holds is **inert** — no changelog entry, no `updated` bump. So `pickup` is safely re-runnable and cannot corrupt the ledger's `Seen` diff anchor.
- Assigning over *another* dev's ticket is a real, watcher-notifying change, so `pickup` confirms before overwriting a non-empty assignee.

The original tooling premise behind option 2 (Confluence) was likewise wrong by 2026-07-20 — but as argued above, the store still stays on the branch for reasons independent of tooling.
