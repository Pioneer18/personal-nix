---
status: grabbed
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-14
blocked_by: [proxy-27b-queue-watcher-sync-cli]
---

# PROXY — Tachikoma `queue` no-arg auto-grab wiring (slice 29b, queue-infrastructure-v1-completion)

Complete the parts of `proxy-29-queue-tui-and-tachikoma` that landed only partially in PR #50 (commit `dc3f20e`). TUI components + state are in develop; this slice adds the Tachikoma skill update that wires `tachikoma queue` (no-arg) to call `proxy queue grab` for auto-grab.

Hard rule: this slice modifies files under `~/projects/personal-nix/skills/tachikoma/`. CLAUDE.md hard rule #5 (tachikoma-starter) used to block this; the rule was updated 2026-05-13 to mark the migration as completing with proxy-27/28/29 — this slice is **explicitly part of that migration's completion**. Worth a CLAUDE.md edit as part of this slice to clarify that skills/tachikoma/ is now unblocked for migration-related changes only.

## Goal

User runs `tachikoma queue` with no slug argument. Skill invokes `proxy queue grab` to get the next ready slice slug, then proceeds with normal Tachikoma flow (preflight + scaffold + AFK loop) as if the user had typed `tachikoma queue <slug>`. The existing `tachikoma queue <slug>` form is preserved for manual override.

## Files in scope

- `~/projects/personal-nix/skills/tachikoma/SKILL.md` — document the no-arg form + auto-grab behavior
- `~/projects/personal-nix/skills/tachikoma/lib/queue-grab.sh` (new) — thin wrapper around `proxy queue grab` with error handling
- `~/projects/personal-nix/skills/tachikoma/README.md` — user-facing doc update
- `~/projects/personal-nix/skills/tachikoma/USER-GUIDE.md` — workflow example update
- `~/Projects/tachikoma-starter/CLAUDE.md` — update hard rule #5 to clarify skills/tachikoma/ is unblocked for queue-migration completion

## Files out of scope

- TUI components — shipped in PR #50
- Daemon `proxy queue grab` implementation (slice 27b owns)
- Web UI (slice 28b)
- Tachikoma core behavior changes (out of scope)

## Stop condition

- [ ] `tachikoma queue` (no args) invokes `proxy queue grab`
- [ ] If grab returns a non-empty slug: proceeds with normal Tachikoma flow as if user typed `tachikoma queue <slug>`
- [ ] If queue is empty / nothing ready: prints clear message "Nothing to grab. Add an Epic with `proxy queue add-epic` or create work-requests." and exits cleanly (no error)
- [ ] `tachikoma queue <slug>` (existing form) still works unchanged for manual override
- [ ] Tachikoma queue-grab only grabs `open` slices; never re-grabs slices already in `grabbed` state
- [ ] SKILL.md, README.md, USER-GUIDE.md all document the new no-arg form with at least one example
- [ ] CLAUDE.md hard rule #5 updated to note that skills/tachikoma/ modifications for the queue-migration completion are unblocked
- [ ] Skill tests cover both forms (no-arg + with-slug)
- [ ] E2E test: queue has Epic with 3 open slices in dependency-free order → `tachikoma queue` invoked three times → each invocation grabs the next slice in Epic order

## Feedback loops

- Manual test of `tachikoma queue` (no slug) against the seeded QUEUE.yaml (initially picks queue-infrastructure-v1-completion's first ready slice)
- Skill self-test if one exists

## Quality bar

production

## v3 context

- See ADR 006 § D7 (CLI form) + the gap-analysis seed at `~/projects/personal-nix/wiki/seeds/complete-queue-infrastructure-gaps.md`
- Depends on slice 27b for `proxy queue grab` to exist
- After this slice ships, the full Epic + Queue workflow is end-to-end: CLI add → web UI reorder → TUI view → Tachikoma auto-grab
- **Recommended Tachikoma cap: `--afk 8`** — ~9 acceptance items; mostly doc + thin wrapper
