---
title: "auto-review-prs"
summary: "Two-pass PR triage on a repo's dev branch — autonomous merge for clean/good-enough PRs, interactive walkthrough for the rest"
category: "skill"
tags: [github, pr, automation, claude-skill, code-review, dev-trunk]
link: "~/projects/personal-nix/skills/auto-review-prs/SKILL.md"
last_updated: "2026-05-11"
---

Pass 1 (autonomous): re-evaluates every open PR against a strict `clean` rubric or a relaxed `good-enough` rubric (path or size carve-out for logic-without-tests). Silently squash-merges what passes. Re-evaluates PRs labeled `auto-merge-blocked` instead of skipping them. Replaces stale `[auto-review-prs]` comments on each PR.

Pass 2 (walkthrough): walks you through everything pass 1 couldn't merge, one PR at a time, in most-fixable-first tier order. Each iteration renders a plain-English briefing (what / why-in-queue / next-step / links) and an `AskUserQuestion` with 2 contextual actions + Diagnose + Skip. Agency rules: mechanical ops just run; agent-drafted text shows the draft first; code changes go through a separate review cycle; destructive actions require explicit `y/N`.

**Invocation:**
- `/auto-review-prs` — full pass (autonomous + walkthrough)
- `/auto-review-prs auto` or `--autonomous-only` — autonomous pass only; queue printed to report

**Hard rules:**
- Refuses to run inside `~/Projects/platform` (RelyMD monorepo)
- Targets `dev` branch only — fails pre-flight if `dev` doesn't exist on the remote
- Squash-merges only; deletes the branch after
- Eval-gate paths (`supabase/functions/chat-with-ai/**`, `eval/**`) are never auto-merged — always walkthrough tier 3
- Self-authored PRs get a comment-based audit trail instead of an `--approve` review (GitHub hard-blocks self-approval)

**Audit trail:** appends to `~/projects/personal-nix/wiki/auto-merged-pr-report.md` on every run — merged-with-tier, walkthrough actions taken, queue at exit, pending CI.

**Depends on:** the `dev` ruleset allowing self-approval / 0 required approvals. In healthbite this is captured in [ADR 003](https://github.com/MioMarker/healthbite/blob/main/docs/adr/003-self-approval-on-dev.md); the `main` ruleset stays strict.
