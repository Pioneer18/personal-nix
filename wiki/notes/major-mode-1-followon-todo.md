---
title: "Major Mode 1 follow-on TODO"
tags: [major, todo, mode-1, bot-identity]
last_updated: "2026-05-11"
---

End-of-AFK "merge all ready-for-review PRs" feature for Major. Three ADRs drafted as `Proposed` on 2026-05-11 (`docs/adr/015`, `016`, `017`). These are the items only I can handle — Tachikomas can take the rest.

## My TODO

1. **Provision `major-shell-bot` GitHub account.** Signup, app-based 2FA, recovery email on an operator-owned address.
2. **Generate fine-grained PAT for it.** Scope: `MioMarker/{major,healthbite,healix}` with `Contents: Write`, `Pull requests: Write`, `Issues: Write`, `Actions: Read`. Expiration 1 year (max). Store in 1Password as `major-shell-bot github PAT`.
3. **Add bot as collaborator.** Write role (not Admin) on the three repos. Verify with a throwaway-branch push + `gh pr create` smoke test before considering setup done.
4. **Wire the new PAT.**
   - `shell/.env` → swap `GITHUB_TOKEN` to bot PAT.
   - `npx supabase secrets set GITHUB_TOKEN=<bot-pat>` against dev project. Confirm `major-create-github-issue`, `major-import-external-issues`, `major-list-external-issues`, `major-github-webhook` still function.
5. **One-off admin-merge of the 33 stuck PRs.** Throwaway shell script: `gh pr merge --admin --squash` in tier order (docs → bug-fix/refactor → feature). Run once, delete, don't commit.
6. **Decide ADR promotion.** Flip 015 / 016 from `Proposed` → `Accepted` once provisioning + merge feature land, or run another grilling pass first. 017 stays `Proposed` and waits for its triggers (required CI lands, or stale-approval clutter shows up, or operator feedback says (b)'s summaries are unhelpful).

## Pointers

- `docs/adr/015-major-shell-bot-identity.md` — bot identity rationale, scopes, rotation surface.
- `docs/adr/016-merge-blocked-brief-status.md` — schema change + transition rules.
- `docs/adr/017-mode-1-pre-flight-merge-algorithm.md` — deferred algorithm upgrade.
- `docs/adr/011-outbound-brief-to-issue-resolution-comment.md` — amended on 2026-05-11 to note 015 supersedes the comment-author decision.
