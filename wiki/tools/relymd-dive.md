---
title: "relymd-dive"
summary: "Lightweight ~100-line orientation map for the RelyMD platform monorepo at ~/Projects/platform — tech stack, app/package layout, hard rules, MCP tools, bounded-context map, and pointers to per-area docs"
category: "skill"
tags: [relymd, platform, orientation, claude-skill, monorepo, telehealth]
link: "~/Projects/platform/.agents/skills/relymd-dive/SKILL.md"
last_updated: "2026-05-14"
---

Front door for any platform work. Orient first, then load only the per-area docs (`<context-path>/CONTEXT.md`, pattern-specific rule files) the task actually needs.

Companion: `[[relymd-deep-dive]]` for one-shot heavy load of all orientation docs (~260 lines).

**Pattern parallel:** `[[proxy-dive]]` (~/Projects/tachikoma-starter) and `[[major-dive]]` (~/Projects/major). Same lightweight-front-door shape; the per-repo content differs.

**Invocation:** `Skill(relymd-dive)`, or natural-language ("orient to platform", "what's the relymd monorepo layout").
