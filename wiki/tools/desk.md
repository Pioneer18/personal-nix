---
title: "/desk — personal task + meeting ledger"
summary: "Near-zero-friction capture of tasks, meetings, people, projects, and ref info into ~/projects/desk (private GitHub Pioneer18/desk), with P0-P3 FIFO prioritization, generated NOW.md board, 1:1 prep, weekly review, and Friday leadership report. Personal; unrelated to PROXY."
category: "skill"
tags: [desk, tasks, meetings, prioritization, capture, claude-skill, personal]
link: "~/projects/personal-nix/skills/desk/SKILL.md"
last_updated: "2026-09-30"
---

`/desk <anything>` captures. `/desk` shows NOW. Verbs: triage, prep, project, find, day, week, report, import, push. The stdlib CLI at `skills/desk/bin/desk` does the mechanical work, and the launchd `desk-push` agent (modules/desk-push.nix) pushes daily at 18:00. Design: [decisions/desk-personal-ledger.md](../decisions/desk-personal-ledger.md).
