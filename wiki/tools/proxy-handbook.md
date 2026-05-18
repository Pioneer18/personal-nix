---
title: "proxy-handbook — comprehensive PROXY feature reference"
tags: [proxy, skill, handbook, reference, 5ech]
last_updated: "2026-05-18"
link: "~/Projects/tachikoma-starter/.claude/skills/proxy-handbook/SKILL.md"
---

Feature-by-feature handler reference for PROXY. Lookup style — "how does the email vertical work", "what's the standby gate", "what verbs exist", "where does state live" — rather than narrative walkthrough.

26 sections covering: daemon, CLI verb catalogue, queue (Epics + slices), Operations + Objectives + Follow-ups, callsigns + infils (5ECH model), standby + exfil review gates, chat tab + tmux layout, voice daemon, web UI (`:3737`), TUI, email vertical (Outlook OAuth + folder taxonomy + body-to-Claude flag + briefings + Reviewer + iterative compose + deep Jira creation), Jira bidirectional sync, provider routing (claude/codex), sensor + 5-gate admission, computer use (deferred), timers, cron, notifications, Tachikoma integration, MCP servers, notebook, wizard + recalibrate, per-machine + per-repo config, handler cheat sheet, file system layout.

Each section flags **live / partial / stubbed / spec-only** as of 2026-05-18 PM.

Companion to [[proxy-dive]] (lightweight orientation map), [[proxy-tutorial]] (narrative walkthrough), [[proxy-deep-dive]] (one-shot doc load). See [[proxy-v2-cutover-deferred]] for the v2 cutover state.

Refresh when CLI verb surface shifts or a new ADR lands in `~/Projects/tachikoma-starter/docs/adr/`.
