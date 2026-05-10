---
name: issue-2-create-label-vocab-on-target-rep
status: done
github_issue: MioMarker/tachikoma-starter#2
target_repo: /Users/pioneer/Projects/tachikoma-starter
last_updated: 2026-05-10
failure_count: 0
---

## Goal

Add label-vocab setup to `bootstrap.sh` (skippable prompt) and a standalone `scripts/setup-repo-labels.sh <org/repo>` script.

## Files in Scope

- `bootstrap.sh`
- `scripts/setup-repo-labels.sh`

## Files out of Scope

- `.git/**`
- `flake.nix`
- `flake.lock`
- `skills/**`
- `wiki/**`

## Stop Condition

1. `bootstrap.sh` prompts for org/repo and creates the 4 Tachikoma labels if entered
2. Step is skippable (Enter skips without error)
3. `scripts/setup-repo-labels.sh <org/repo>` exists standalone
4. Idempotent — no-op on repos that already have the labels

## Feedback Loops

- `nix flake check`
- `bash -n bootstrap.sh && bash -n scripts/setup-repo-labels.sh`
