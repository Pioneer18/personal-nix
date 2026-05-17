---
title: "/op-next — fast-query what's next on active Op"
summary: "Read-only ranked list of handler-actionable items rolled up under the active Operation: exfil-ready packages, Briefings owed, due Follow-ups, stale items, pending Recommendations. (ADR 007)"
category: "skill"
tags: [proxy, operations, north-star, query, claude-skill, adr-007]
link: "~/projects/personal-nix/skills/op-next/SKILL.md"
last_updated: "2026-05-14"
---

Read-only. Returns top-N actionable items from the active Op (top of `relymd` theater in OPERATIONS.yaml). Excludes untriaged Ops (priority unset). Pre-slice-32 surfaces only filesystem-derivable items.
