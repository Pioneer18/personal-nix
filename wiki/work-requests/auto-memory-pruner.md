---
status: grabbed
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-12
---

# Auto-memory pruner — scheduled LLM-driven memory hygiene

A weekly (or configurable) LaunchAgent that invokes `claude -p` with a structured prompt to evaluate the auto-memory directory and propose pruning decisions. Designed to keep memory tight over months without losing anything load-bearing. Safety bias: recommend-only by default; auto-archive only fires on entries with explicit expiry metadata.

**Why this exists**: the auto-memory system accumulates entries over time. Some go stale (project memories where the project shipped), some become redundant (multiple notes on overlapping topics), some are just low-signal. Without periodic pruning, memory bloats and signal-to-noise degrades — claude wastes context on stuff that no longer matters. A scheduled LLM review keeps memory clean without manual upkeep.

**Why scheduled, not on-demand**: pruning is the kind of maintenance that never gets done if it requires user initiation. A weekly job that surfaces "here are 3 stale entries — archive y/n?" via notification keeps memory hygienic with near-zero user effort.

## Goal

After this slice ships:

- A nix-managed LaunchAgent fires weekly (default Sunday 03:00 local, configurable).
- The fired script invokes `claude -p` with a structured prompt that reads `MEMORY.md` + every memory file in `~/.claude/projects/-Users-pioneer/memory/`.
- Claude emits a markdown report at `~/.claude/projects/-Users-pioneer/memory/.prune-reports/YYYY-MM-DD.md` categorizing each entry as `KEEP` / `CONSOLIDATE` / `ARCHIVE-RECOMMEND` / `ARCHIVE-AUTO` with one-line rationale.
- `ARCHIVE-AUTO` entries (only those with explicit expiry metadata that has passed) are moved to `~/.claude/projects/-Users-pioneer/memory/.archive/YYYY-MM-DD/` automatically.
- `ARCHIVE-RECOMMEND` entries surface to the user via macOS notification ("3 memory entries suggested for archive — review?") with a deep-link to the report. User reviews + edits MEMORY.md manually (or via a follow-up `proxy memory archive <slug>` CLI in v1.5).
- A dry-run mode (`--dry-run` flag) writes the report without moving any files.

## Files in scope

- `personal-nix/scripts/prune-memory.sh` — the LaunchAgent's program. Sets up env, invokes claude with the prompt, parses report, handles auto-archive.
- `personal-nix/scripts/prune-memory-prompt.md` — the structured prompt template (claude reads this + memory contents, emits structured report).
- `personal-nix/modules/memory-prune.nix` — `launchd.agents.memory-prune` definition. Cron schedule via `StartCalendarInterval`.
- `personal-nix/default.nix` — optional import (user opts in when ready by adding `./modules/memory-prune.nix` to imports).
- `personal-nix/modules/README.md` — document the new module.

## Files out of scope

- A CLI for interactive memory editing (`proxy memory archive <slug>`) — could be a follow-up slice in v1.5+.
- A web UI for memory management (could be part of M6 web UI later).
- Tracking memory access frequency (would require instrumenting claude itself; out of scope for v1).

## Pruning criteria (the prompt encodes this)

The claude prompt at `prune-memory-prompt.md` enumerates the rules below. Output is a markdown table per memory file with a category + rationale.

**KEEP** — entry stays as-is:
- User identity / role / preferences (user-type entries; rarely go stale)
- Strong feedback rules ("never do X", "always do Y") — durable
- Reference pointers to external systems that still exist
- Recently-modified entries (within last 30 days)
- Entries explicitly marked `permanent: true` in frontmatter

**CONSOLIDATE** — flag for the user to merge with another entry:
- Multiple entries covering the same topic (e.g., 3 notes about Tachikoma usage that could be one)
- Entries that substantially overlap with always-loaded docs (CLAUDE.md, build-state notes)

**ARCHIVE-RECOMMEND** — propose to user, don't auto-act:
- Project-type entries where the project has shipped or closed (status verifiable via referenced files/links)
- Project entries with relative dates that have passed (e.g., "M1 in progress" once M1 done)
- Entries referencing files/decisions that no longer exist on disk
- Feedback entries about a specific completed task

**ARCHIVE-AUTO** — move to `.archive/` without prompting:
- Empty / malformed files (zero useful content)
- Duplicate files (same content, different filenames)
- Entries with explicit `expires_at: <date>` in frontmatter where the date has passed
- Entries with `valid_until: <condition>` where the condition can be verified false

Default schedule: **weekly, Sunday 03:00 local time**. Configurable via the LaunchAgent's `StartCalendarInterval`.

## Stop condition

- [ ] LaunchAgent loads via `launchctl list | grep memory-prune` after `dev`
- [ ] LaunchAgent fires on its schedule (manual test via `launchctl kickstart`)
- [ ] Script invokes `claude -p` with the prompt + memory contents and produces a report at `.prune-reports/<date>.md`
- [ ] Report uses the 4-category table format (KEEP / CONSOLIDATE / ARCHIVE-RECOMMEND / ARCHIVE-AUTO)
- [ ] `ARCHIVE-AUTO` entries are actually moved to `.archive/<date>/` (preserving original paths) and removed from `MEMORY.md` index
- [ ] `ARCHIVE-RECOMMEND` entries trigger a macOS notification with a deep-link or path to the report
- [ ] `--dry-run` flag produces the report without moving any files
- [ ] Auto-archive is **idempotent**: re-running on the same memory state produces no new archives (entries with expired metadata are gone from the live dir)
- [ ] Documented in `modules/README.md` how to opt in, configure schedule, and recover an archived entry (`mv .archive/<date>/<file> .`)
- [ ] Recovery is one-line: `mv ~/.claude/projects/-Users-pioneer/memory/.archive/<date>/<file> ~/.claude/projects/-Users-pioneer/memory/<file>` + re-add to MEMORY.md index

## Safety properties

- **Never delete, only archive.** All "removed" entries land in `.archive/<date>/<original-filename>.md`. Recovery is a `mv`.
- **Auto-archive is opt-in narrow.** Only fires on entries with explicit time-bounded metadata (`expires_at`, `valid_until`). Entries without that metadata require user approval via the RECOMMEND path.
- **Audit trail.** Every prune run writes a report to `.prune-reports/<date>.md`. Includes what was auto-archived, what was recommended, and full rationale.
- **Confirmation pre-action.** On first 3 runs (or until user disables via config), the auto-archive step is skipped and everything goes through RECOMMEND. Lets the user calibrate the system before trusting it.
- **MEMORY.md is preserved** as a comment in the archive folder so the index can be restored.

## Feedback loops

- `dev` (LaunchAgent loads)
- Manual: `launchctl kickstart -k gui/$(id -u)/com.personal.memory-prune` → check report at `.prune-reports/<today>.md`
- Manual: insert a malformed memory file → verify it's flagged as ARCHIVE-AUTO
- Manual: insert a memory file with `expires_at: 2024-01-01` → verify it's auto-archived on next run
- Manual: insert a project memory referencing a deleted file → verify it's flagged as ARCHIVE-RECOMMEND, not AUTO

## Quality bar

production

## v3 context

This is **not** part of the M1-M7 v1.0 critical path — it's a side-quest infrastructure slice for memory hygiene. Can ship anytime independently of PROXY's milestones. Best slotted in **v1.5** (after the agentic shell is dogfooded for a few weeks and memory has had time to accumulate) but could land earlier if memory bloat becomes a real concern.

**Why not a Tachikoma slice**: this is a `personal-nix` change (scripts + nix module + prompt) — independent of `tachikoma-starter`. Sized at ~half a day of work; Tachikoma overhead pays off marginally. Build directly when motivated.

**Future extensions** (v1.5+):
- `proxy memory archive <slug>` CLI for one-shot manual archive
- `proxy memory restore <slug>` for un-archive
- Web UI integration showing pending RECOMMEND items in the inbox
- Cross-Mac coordination — if memory is iCloud-synced (shell-13), only run the prune on one designated Mac to avoid duplicate work

## See also

- [Memory rules in CLAUDE.md](~/.claude/CLAUDE.md) — the rules the pruner evaluates against
- [Agentic shell build state](../notes/agentic-shell-build-state.md) — where this slice fits
- [Agentic shell v1.0 slice plan](../recipes/agentic-shell-v1-slice-plan.md) — main build plan (this slice lives outside it, in v1.5+)
- [`shell-13-memory-icloud-sync.md`](shell-13-memory-icloud-sync.md) — memory location post-M1 (iCloud-synced), informs cross-Mac considerations
