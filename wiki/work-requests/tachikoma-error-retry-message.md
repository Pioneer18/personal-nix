---
status: grabbed
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# Tachikoma: Add explanatory message to error double-retry draft PR

The recover phase `error` auto-retry path says "push as draft PR, fire notification, no user prompt." The user sees a notification with no explanation of what happened or what to do. This needs the same treatment as the cap double-retry message we added.

## Goal

Tachikoma is done when the error double-retry path prints a clear message explaining what happened, what the draft PR contains, and what the user should do next — consistent with the cap double-retry message format.

## Files in scope

skills/tachikoma/SKILL.md

## Files out of scope

skills/tachikoma/tachikoma.sh.tmpl
skills/tachikoma/ship.md.tmpl

## Stop condition

- [ ] The recover phase Step 3 `error` auto-retry path includes a print block after the draft PR is pushed
- [ ] The message explains: what happened (crashed twice), what the draft PR is (partial work, won't merge until promoted), what to do next (review PR, check logs, fix the underlying error, or discard)
- [ ] The message format matches the cap double-retry message (same structure: what happened / draft PR line / what to do next bullet list)

## Feedback loops

No automated tests — verify by reading the updated SKILL.md recover phase for consistency.

## Quality bar

production
