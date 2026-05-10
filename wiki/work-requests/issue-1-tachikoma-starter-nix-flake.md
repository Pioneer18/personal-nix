---
name: issue-1-tachikoma-starter-nix-flake
status: grabbed
github_issue: MioMarker/tachikoma-starter#1
target_repo: /Users/pioneer/Projects/tachikoma-starter
last_updated: 2026-05-10
failure_count: 0
---

## Goal

Minimal nix-darwin + home-manager flake for a non-technical colleague to bootstrap Tachikoma on a fresh Apple Silicon Mac in one command.

## Files in Scope

- `flake.nix`
- `bootstrap.sh`
- `skills/**`
- `wiki/**`
- `README.md`
- `.claude/**` (except `settings.local.json`)

## Files out of Scope

- `.git/**`

## Stop Condition

1. `bootstrap.sh` runs end-to-end: Determinate Systems nix install → `darwin-rebuild switch` → `gh auth status` check
2. Skills (`tachikoma`, `work-queue`, `wiki`, `tachikoma-tutorial`) symlinked at `~/.claude/skills/` after rebuild
3. `/wiki tachikoma` and `/wiki gh-auth` surface correctly
4. `/tachikoma-tutorial` covers all 7 modes in plain English, zero developer jargon
5. `nix flake check` passes, `bash -n bootstrap.sh` passes

## Feedback Loops

- `nix flake check`
- `bash -n bootstrap.sh`
