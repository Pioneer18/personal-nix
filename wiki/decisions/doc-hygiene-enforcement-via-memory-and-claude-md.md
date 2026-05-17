---
title: "Doc-hygiene enforcement: memory + CLAUDE.md sharpening (not hooks)"
tags: [decision, claude-code, doc-hygiene, automation]
last_updated: "2026-05-12"
status: accepted
---

# Doc-hygiene enforcement: memory + CLAUDE.md sharpening (not hooks)

## Context

Global `~/.claude/CLAUDE.md` had a Documentation Hygiene rule since at least early May 2026: "document system changes proactively in the appropriate existing location without waiting to be asked." Despite the rule, the agent kept skipping the doc step under task-focus. On 2026-05-12 the user noted that they still had to ask for documentation too often — CleanShot X installation, mac-filesystem-hygiene optimizations, PAT migration, etc. all left undocumented until prompted.

## Options considered

| Option | Mechanism | Strength | Cost |
|---|---|---|---|
| A. Stop hook (every turn) | `settings.json` injects "did this turn create state needing doc?" check at every turn end | Hard-deterministic | Latency on every turn, nag |
| B. Targeted PreToolUse hook | Hook fires only on Edit/Write to durable-state paths (nix, CLAUDE.md, wiki) | Targeted-deterministic | Setup once; low noise; misses non-tool changes |
| C. Feedback memory | Auto-loaded `MEMORY.md` index → soft behavioral feedback across sessions | Soft, sticky across sessions | Free |
| D. CLAUDE.md rule sharpening | Concrete trigger table + pre-response checkpoint + "anti-pattern to refuse" framing | Soft, project + global scoped | Free |

## Decision

**Adopt C + D.** Skip A and B for now.

- Add project-scoped feedback memory at `~/.claude/projects/-Users-pioneer-Projects-tachikoma-starter/memory/feedback_doc_hygiene_proactive.md` (loaded every session in tachikoma-starter).
- Sharpen `~/.claude/CLAUDE.md § Documentation Hygiene` with: pre-response checkpoint, concrete trigger → required-doc table, explicit "task is not done" framing for missed docs, anti-pattern to refuse.

## Why not hooks (yet)

- Hooks add latency to every turn (Stop) or every relevant tool call (PreToolUse) — friction during high-velocity Tachikoma fan-out sessions.
- The rule sharpening makes the trigger checklist concrete enough that *missing* a doc is now obvious mid-session, not just at retrospective.
- Memory provides cross-session enforcement at zero runtime cost.
- If C + D still drifts after a 2-week trial → escalate to B (targeted PreToolUse hook on `Edit|Write` of paths matching `(dev-environment|personal-nix|CLAUDE\.md|ARCHITECTURE\.md|docs/adr)`).

## Consequences

- Every install of a new cask / MCP / skill → wiki/tools/ stub same session.
- Every trade-off decision → wiki/decisions/ entry same session.
- Every ordered procedure → wiki/recipes/ entry same session.
- The agent treats missed docs as task failure, not optional polish.
- Project memory index (`~/.claude/projects/-Users-pioneer-Projects-tachikoma-starter/memory/MEMORY.md`) gains a pointer to the doc-hygiene feedback file.

## Apply

CLAUDE.md change lives in the nix source at `~/Projects/dev-environment/users/jonathan-sells.nix` (heredoc'd into `home.file.".claude/CLAUDE.md".text`). Requires `dev` rebuild to materialize. Feedback memory + MEMORY.md updates are direct file writes (not nix-managed).

## Re-evaluation trigger

If 3+ doc-skip incidents occur in a 2-week window after this lands → escalate to Option B (targeted PreToolUse hook).
