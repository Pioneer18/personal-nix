---
status: done
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# Tachikoma: Update /tachikoma done description in invocation table

The invocation table describes `/tachikoma done` as the primary merge trigger. Now that auto-ship runs automatically on completion, `/tachikoma done` is a fallback for failed auto-ship. The description is misleading.

## Goal

Tachikoma is done when the invocation table entry for `/tachikoma done` accurately describes it as a manual fallback for when auto-ship fails, and any other references to `/tachikoma done` as the "primary" merge path are updated.

## Files in scope

skills/tachikoma/SKILL.md

## Files out of scope

skills/tachikoma/USER-GUIDE.md
skills/tachikoma/README.md

## Stop condition

- [ ] Invocation table `/tachikoma done` row says it is a fallback for failed auto-ship, not the primary merge trigger
- [ ] No other sentence in SKILL.md implies the user must run `/tachikoma done` after a successful AFK run
- [ ] The ship phase "Triggered" section already accurately describes auto-ship — verify it still reads correctly after this change

## Feedback loops

No automated tests — verify by reading the updated invocation table and ship phase trigger description.

## Quality bar

production
