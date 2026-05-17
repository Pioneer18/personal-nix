---
title: "relymd-deep-dive"
summary: "Heavyweight one-shot load of all RelyMD platform orientation docs (~260 lines): AGENTS.md, CONTEXT-MAP.md, directory-structure.md, and the five rules/common files"
category: "skill"
tags: [relymd, platform, orientation, claude-skill, monorepo, telehealth, deep-dive]
link: "~/Projects/platform/.agents/skills/relymd-deep-dive/SKILL.md"
last_updated: "2026-05-14"
---

Pay the full orientation context cost up front rather than fetching docs on demand. Use before substantial platform work (new feature, cross-cutting refactor, scoped Foundry/Apollo Hermes/Dev Intake task).

Loads the orientation set only — per-context `CONTEXT.md` and pattern-specific rule files stay lazy. Cheap (~254 lines) compared to `[[proxy-deep-dive]]` (~1,335) and Major's deep-dive (~1,200).

For lightweight orientation, use `[[relymd-dive]]` instead.

**Invocation:** `Skill(relymd-deep-dive)`, or natural-language ("deep-dive into platform", "load all relymd orientation").
