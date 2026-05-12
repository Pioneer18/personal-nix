---
status: done
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
shipped_pr: https://github.com/Pioneer18/personal-nix/pull/15
shipped_at: 2026-05-11
---

# PROXY — Filesystem Queue Compatibility Layer

Audit the existing `~/projects/personal-nix/wiki/work-requests/` filesystem queue. Document exactly what must stay intact during PROXY development. Add a smoke test that confirms the old Tachikoma skill still works. Establish written cutover criteria for Slice 17 (the migration).

## Goal

The existing Tachikoma work request queue is verified working. A written compatibility doc and smoke test script exist as a regression guard. No changes are made to any existing skill files.

## Files in scope

- `~/projects/personal-nix/wiki/work-requests/` (read-only audit)
- `~/projects/personal-nix/skills/work-queue/SKILL.md` (read-only audit)
- `~/projects/personal-nix/skills/tachikoma/SKILL.md` (read-only audit)
- New files to create:
  - `~/projects/personal-nix/wiki/COMPATIBILITY.md`
  - `~/projects/personal-nix/scripts/smoke-test-queue.sh`

## Files out of scope

- Any modification to existing skill files
- PROXY app code

## Stop condition

- [ ] `COMPATIBILITY.md` written documenting: all filesystem queue behaviors, frontmatter fields relied upon, state machine transitions used by the current skill, what `/work-queue list` and `/tachikoma queue` depend on
- [ ] `smoke-test-queue.sh` script that: creates a test work request file, verifies it can be read/parsed by the skill conventions, checks all required frontmatter fields are present, then cleans up
- [ ] `smoke-test-queue.sh` exits 0 when the queue is healthy, non-zero if something is broken
- [ ] `COMPATIBILITY.md` includes a "Cutover criteria for Slice 17" section: the conditions that must be true before the filesystem queue can be retired
- [ ] Zero modifications to any existing skill or work-request files

## Feedback loops

- `bash ~/projects/personal-nix/scripts/smoke-test-queue.sh` (expect exit 0)

## Quality bar

production
