---
status: done
priority: 3
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-16
---

# Skill — /reorient (deep machine-state review + memory rewrite)

> Seeded from `wiki/seeds/reorient-skill.md`. Body below is the original seed; treat as
> rough — needs grilling + scope refinement before tachikoma dispatch.

A skill that does a **deep top-down review** of the machine's state and rewrites the memory system so PROXY (and any Claude session) wakes up truly oriented to current reality, not yesterday's snapshot.

**Review order (top-down):**
1. **Machine level** — performance telemetry history (CPU/mem pressure trends, OrbStack disk, recent crashes/reboots)
2. **PROXY** — current build state, M-milestone, in-flight work
3. **File system** — disk usage, hygiene drift (per `mac-filesystem-hygiene` skill)
4. **`~/Projects`** specifically — what repos exist, which are active vs dormant, branch state
5. **Anything else worth catching** — open work-requests, stale seeds, expiring credentials, etc.

**Memory update behavior:**
- **Prune** memories that are definitively deprecated (the referenced thing no longer exists / is no longer true)
- **Ask confirmation** before deleting memories that *seem* deprecated but are ambiguous
- **Update** memories whose facts have shifted (dates, paths, statuses)
- **Add** new memories for context that should be there but isn't (gaps surfaced during the review)

**Goal:** memory optimized so any cold-start agent (PROXY, Claude Code, tachikoma) is immediately oriented without needing the user to re-explain context.

**Naming:** skill is `/reorient` (not `sanitize-memory` — the verb that matters is the *agent's* re-orientation, not the data-cleaning side effect).

**Pairs with [[cron-system]]** — `/reorient` is the first scheduled consumer (intended to run nightly @ 4am).

**Open questions to resolve during grilling:**
- Where does "machine performance telemetry history" come from? (existing log? new instrumentation?)
- Confirmation UX when Mac is asleep at 4am and reorient runs unattended — auto-skip ambiguous deletes? queue them?
- Is `/reorient` a Claude Code skill, a PROXY-native job, or both?
- Scope of "memory": just `~/.claude/projects/-Users-pioneer/memory/` or also CLAUDE.md, MEMORY.md indexes, wiki INDEX.md?
- Diff/preview surface so user can review what changed after an unattended run?
- Per-section drilldown vs. monolithic pass?
