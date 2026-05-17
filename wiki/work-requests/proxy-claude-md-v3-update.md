---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-12
notes: "Landed directly in this session (no PR/Tachikoma); CLAUDE.md updated 2026-05-12. Kept for audit trail."
---

# PROXY — Update CLAUDE.md for v3 (agentic shell scope)

`tachikoma-starter/CLAUDE.md` was written for PROXY v2 ("local-first replacement for the filesystem-based Tachikoma skill"). After the 2026-05-11 agentic-shell grilling, v3 expanded scope to "agentic shell that includes work orchestration." CLAUDE.md needs alignment with v3 so Tachikomas claiming any v3 slice have correct context. Listed as follow-on in ADR 001.

## Goal

`tachikoma-starter/CLAUDE.md` accurately describes PROXY v3: agentic shell + work orchestration. Hard rules updated. Tech stack section updated (Cargo workspace per ADR 004, voice daemon, sqlx for migrations). Branding section unchanged. Read-before-acting list adds new ADRs.

## Files in scope

- `~/Projects/tachikoma-starter/CLAUDE.md` (the main edit)

## Files out of scope

- `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` (already updated to v3)
- ADRs (already written: 001-004)
- Personal-nix files

## Stop condition

- [ ] CLAUDE.md opening paragraph mentions v3 + agentic shell, not just v2 work-orchestrator
- [ ] "Read before acting" list adds ADR 001, 002, 003, 004
- [ ] "Hard rules" section reviewed; rules 1-5 stay valid for v3; add a rule for v3 like "PROXY v3 includes a synchronous Chat tab — see ARCH.md § 16; don't refactor chat session lifecycle without an ADR"
- [ ] "Tech stack" section updated:
  - Add proxy-voice daemon
  - Drop Drizzle ("decommissioned in M3; sqlx is the migrations source-of-truth per ADR 004")
  - Mention Cargo workspace (daemon/ + voice/ members)
  - Mention notify-app/ Swift project
- [ ] "Per-repo config (v2 extensions)" section adds the v3 fields (voice config, computer-use enabled flag) — or links to ADR 004's proxy.toml schema
- [ ] "Slice plan" section adds the M1-M7 v3 slice plan with link to `personal-nix/wiki/recipes/agentic-shell-v1-slice-plan.md`
- [ ] No conflicting v2 statements remain; v3 supersedes via clear "Part II" or "v3" callouts

## Feedback loops

- Manual diff: `git diff CLAUDE.md` — review the changes
- Read through CLAUDE.md from top to bottom; verify no v2-only assumptions remain that would confuse a Tachikoma claiming a v3 slice
- Check that "When in doubt" footer still applies (still says "ARCHITECTURE.md wins" — yes, still correct)

## Quality bar

production

## v3 context

This is a doc-only slice but high-leverage: every Tachikoma claiming a v3 slice will read CLAUDE.md as part of context. Inaccurate CLAUDE.md = wasted Tachikoma cycles or misaligned implementations. Should land BEFORE any v3 code slice (shell-04, proxy-01b, etc.). See [ADR 001](~/Projects/tachikoma-starter/docs/adr/001-proxy-scope-expansion-agentic-shell.md) Follow-on work for the original mention.
