---
title: "Agentic shell v1.0 — build state snapshot"
tags: [agentic-shell, proxy, build-state, session-handoff]
last_updated: "2026-05-12"
---

# Agentic shell v1.0 — build state snapshot

**Purpose**: durable handoff doc so any fresh claude session can pick up the build without re-grilling. Updated as the build progresses.

## TL;DR — Where we are

- **M1 — Boot exists**: ✅ done (shell-01/02/10/13)
- **M2 — Hey PROXY voice**: ✅ done (shell-04/05; shell-09 TTS wiring 🚀 in progress)
- **M3 — Daemon foundation**: ✅ done (proxy-01b, proxy-02-extended, proxy-04b, proxy-04c, proxy-11b, proxy-fast-dispatch-mode, proxy-drizzle-01/02/03)
- **M4 — Ink TUI**: ✅ done (proxy-16-tui-v2)
- **M5 — Full voice modes + notify**: ✅ done (shell-06/07/08 Wispr/Open/Off + switching, proxy-15-extended signed notify-app) — PRs #38/39/40/41
- **M6 — Web UI**: ✅ done (proxy-12-extended Next.js dashboard, drizzle decommission) — PRs #36/37/42
- **M7 — First-run wizard**: ✅ done (proxy-15b `proxy wizard` CLI + machine probes + defaults calc) — PR #44
- **shell-09 TTS wiring**: ✅ done (mode-switch announcements + Claude Code Stop hook) — PR #43

**🚀 v1.0.0 SHIPPED 2026-05-12** — tagged + merged to `develop`. All ship checklist items complete.

**Integration branch tip**: `5e7231a` (fix: docker-compose Drizzle decommission, on top of `0870a0b` wizard PR #44)

**Active loops**: none

**Rust compilation**: ✅ verified 2026-05-12 — both `daemon` and `voice` crates build clean.

**Branch state**: `feat/proxy-12b-recommendations-engine` merged → `develop`. Tagged `v1.0.0`.

**Critical discovery 2026-05-12**: Picovoice abandoned the Rust SDK (all crates yanked Aug 2025). Pivoted to `livekit-wakeword` (open ONNX-format Rust crate, no AccessKey). ADR 002 amended. See shell-05 PR #24.

## What's actually on disk + applied

| Slice | Files on disk | `dev` applied | Verified working |
|---|---|---|---|
| `shell-01` boot LaunchAgent | ✅ `personal-nix/modules/proxy-boot.nix`, `scripts/proxy-boot.sh` | ✅ | ✅ fullscreen Ghostty at login (2026-05-12) |
| `shell-02` chat + queue panes | ✅ `scripts/proxy-tmux-launcher.sh`, `scripts/proxy-tui-placeholder.sh`, `.tmux.conf` block in proxy-boot.nix | ✅ | ✅ chat (claude) + placeholder TUI panes visible |
| `shell-10` Shortcuts MCP | ✅ `mcps/shortcuts/{package.json, index.ts, README.md}`, `mcp.nix` register line | ✅ | ✅ `claude mcp list` shows shortcuts Connected (2026-05-12) |
| `shell-13` memory iCloud sync | ✅ `scripts/sync-memory.sh`, `default.nix` activation hook | ✅ | ✅ `~/.claude/projects/-Users-pioneer/memory` → iCloud (2026-05-12) |

**M1 verification — DONE 2026-05-12**:
1. ✅ `dev` ran cleanly — Shortcuts MCP registered, syncMemoryToiCloud activated, tmux 3.6a installed
2. ✅ Proxy session restarted via `launchctl kickstart`
3. ✅ All checks pass: `claude mcp list` shows shortcuts/tachikoma/github/filesystem/applescript Connected; memory symlinked to `~/Library/Mobile Documents/com~apple~CloudDocs/.claude-memory`; `tmux -V` = 3.6a

## Authoritative docs (read these first if picking up cold)

| Doc | What it covers |
|---|---|
| `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` (Part II § 14-22) | v3 agentic-shell architecture: 11 decisions, components, voice daemon, tool catalog, 4-tier state, boot, slice plan |
| `~/Projects/tachikoma-starter/docs/adr/001-proxy-scope-expansion-agentic-shell.md` | Why PROXY scope grew from work-orchestrator → agentic shell |
| `~/Projects/tachikoma-starter/docs/adr/002-voice-daemon-proxy-voice.md` | `proxy-voice` daemon, 4 modes, multi-path switching |
| `~/Projects/tachikoma-starter/docs/adr/003-computer-use-and-8-layer-gating.md` | Computer use deferred to v2.0; 8 gating layers |
| `~/Projects/tachikoma-starter/docs/adr/004-cargo-workspace-and-tech-stack-lockin.md` | Cargo workspace layout, sqlx migrations, `proxy.toml` schema |
| `~/projects/personal-nix/wiki/decisions/agentic-shell-4-tier-state.md` | 4-tier state model + team-shareable boundary |
| `~/projects/personal-nix/wiki/recipes/agentic-shell-v1-slice-plan.md` | Full M1-M7 build plan with weekly breakdown |
| `~/projects/personal-nix/wiki/work-requests/shell-*.md` | Individual v3 slice specs (10 total) |
| `~/projects/personal-nix/wiki/work-requests/proxy-fast-dispatch-mode.md` | M3 slice that unlocks non-interactive Tachikoma fan-out |
| `~/projects/personal-nix/wiki/notes/tachikoma-starter-pr-triage-v3.md` | Disposition of the 15 open PRs on tachikoma-starter |

Quick orientation: `/proxy-deep-dive` loads ARCH.md + ADRs + decision docs + recipe into context (~1,500 lines). `/orient-to-machine` for the personal-nix layout.

## v1.0 SHIP checklist — ✅ ALL DONE 2026-05-12

1. ✅ **`proxy wizard` run** — 2 probes prompted (low free memory, 92 login items), 0 executable fixes, computed defaults written to `proxy_settings`.
2. ✅ **Integration branch merged** — `feat/proxy-12b-recommendations-engine` → `develop` (push `4cad213`).
3. ✅ **Tagged v1.0.0** — pushed to origin.

## Next parallel work (while human does v1.0 checklist)

1. **shell-cleanshot** — open, unblocked (shell-10 Shortcuts MCP done in M1, CleanShot installed). License key in Keychain `cleanshot_license` is user-pending for E2E test but code integration can proceed. Next Tachikoma candidate.
2. **proxy-18-telemetry-polish** — blocked (see work-request for blocker condition).

## Parallelism options (until `proxy-fast-dispatch-mode` ships)

Fast-dispatch is M3's parallelism unlock. Until then, manual orchestration:

| Lane | What | How |
|---|---|---|
| **Tachikoma queue (big slices)** | `shell-04` daemon scaffold (1-2h Rust), `proxy-02-extended` schema (30-60 min) | From any session: `/tachikoma queue shell-04` — drives interactive preflight, then runs `--once` autonomously |
| **Direct work (small slices, this session)** | `shell-09` TTS hook, `shell-10` MCP edits, doc updates, ADR follow-ups | Claude writes files; user `dev`s + verifies |
| **Manual / human-required** | porcupine account + .ppn training (shell-05 prereq), Apple Developer account (proxy-15-extended prereq) | User does these out-of-band |
| **Background research** | Agent subagent in background — e.g. "research porcupine Rust bindings + emit a one-page report" | `Agent(run_in_background=true, ...)` from orchestrator session |

**Recommended setup**: 1 fresh claude session as orchestrator + 1-2 Tachikoma loops running autonomously in worktrees. Don't try to drive Tachikoma from multiple claude sessions simultaneously — the preflight is interactive and only one human can answer at a time.

## Cleanup items (small, do anytime)

- [ ] `proxy-claude-md-v3-update` work-request — work is shipped (CLAUDE.md updated 2026-05-12), but the work-request file still says `status: open`. Mark `done` or delete.
- [ ] `tachikoma-starter` PR triage from `notes/tachikoma-starter-pr-triage-v3.md` — 15 open PRs categorized, action recommended is `/auto-review-prs auto` to clear the 8 clean ones autonomously.
- [ ] Verify `tmux` actually installed after `dev` (was added to packages.nix but not yet `dev`'d at time of writing this note).

## How a fresh session should pick up

```
# In a fresh claude session:
1. Read this build-state note
2. Read ~/Projects/tachikoma-starter/CLAUDE.md (v3 agent context)
3. Optional deeper: /proxy-deep-dive
4. Optional: /orient-to-machine for personal-nix structure

# Then for active work:
5. cd ~/Projects/tachikoma-starter (most code lives there)
6. If kicking off Tachikoma: /tachikoma queue shell-04
7. If continuing direct: pick next slice from "Next moves" above
```

## Session log

- **2026-05-11 evening — 05-12 morning**: design grilling + ARCH.md v3 amendments + 4 ADRs + decision docs + 11 work-requests + M1 implementation (shell-01, shell-02, shell-10, shell-13) + fast-dispatch work-request. Build-state snapshot landed.
- **2026-05-12 (fresh session)**: `dev` applied M1 hooks (Shortcuts MCP registered, memory→iCloud symlink, tmux installed). Proxy session restarted. All 3 M1 verification checks pass. M1 ✅. shell-04 queued to Tachikoma.
- **2026-05-12 (later same session)**: docs (ARCHITECTURE.md + 4 ADRs + .claude/skills) committed to feat/proxy-14-notebook (aa8f15e). Re-scaffolded shell-04 off feat/proxy-14-notebook (was incorrectly off bare develop). shell-04 shipped autonomously via auto-ship → PR #22 opened. Porcupine signup started. Subagent surfaced Picovoice Rust SDK abandonment (all crates yanked Aug 2025) → ADR 002 amended with vendor-v3.0 strategy (d36f1a8, bundled in PR #22). M2 1/3 shipped.
- **2026-05-12 (morning, post-overnight)**: verified Rust workspace compiles clean (`daemon` + `voice` both build; cmake required, now added to packages.nix). Updated build-state to reflect overnight's M2/M3/M4 completion. Tip: ddc6004 on feat/proxy-12b-recommendations-engine. Next: `dev` to pick up rustup+cmake, then queue M5.
- **2026-05-12 (continued session)**: M5 shipped (shell-06/07/08 voice modes + proxy-15-extended signed notify-app, PRs #38/39/40/41). M6 shipped (proxy-drizzle-02/03 daemon HTTP + web drizzle decommission, PRs #37/42). Launched parallel AFK loops: proxy-15b first-run wizard (M7 critical path) + shell-09 TTS wiring. Both completed + auto-shipped. M7 ✅ (PR #44). shell-09 ✅ (PR #43). Merged both. Tip: 0870a0b. **All M1-M7 milestones DONE. v1.0 SHIP checklist remaining (human steps).**
- **2026-05-14**: v1.0 fully shipped (2026-05-13 prior session). **v2.0 5ECH theme overhaul designed via grilling session**. 21 design lockdowns captured. Epic + 21 child work-requests written at `~/projects/personal-nix/wiki/work-requests/proxy-v2-{5ech-epic,01..21}-*.md`. Decision doc: `~/projects/personal-nix/wiki/decisions/proxy-v2-5ech-theme-overhaul.md`. Dependency order MV1→MV7. No code yet on v2; ready for Tachikoma fan-out per the proxy-v2-* slices. Substrate (daemon, voice, sensor, admission, Docker runner) preserved; theme + schema + vocabulary overhaul. Computer use (formerly v2.0) renumbered to v3.0, design intact in ADR 003.

## v2.0 5ECH theme overhaul — design summary

**Core decisions** (full 21 lockdowns in [decision doc](../decisions/proxy-v2-5ech-theme-overhaul.md) + [epic](../work-requests/proxy-v2-5ech-epic.md)):

- 4 callsign characters on 2×2 matrix (Comms × Trust): Tracer (Loud×Runs), Echo (Loud×Asks), Phantom (Quiet×Runs), Quill (Quiet×Asks)
- 3 runner knobs per callsign: prompt addendum + pause_on event list + emit_cadence
- 5-level clearance: read → patch → commit → push → execute (+ insert-flag external-write overrides)
- 7-state lifecycle (BRIEFED, LIVE, STANDBY, EXFIL_RDY, EXFIL'D, BURNED, RECALLED), DARK computed
- Full vocab swap: work_requests → dossiers, runs → inserts, feed_items → comms_events, pending_approvals → standby_requests
- 12-verb CLI: brief, dossiers, insert, status, comms, grant, deny, exfil, recall, burn, drops, archive
- Typed packages (pr / report / patch / mixed); untyped dead drops
- Hybrid face system: kaomoji + per-callsign big-ASCII-art; BMO retired
- Per-proxy TTS voices using macOS built-in
- Clean cutover + light data import; substrate preserved

**Slice plan** (21 work-requests, dependency-ordered):

| Milestone | Slices |
|---|---|
| MV1 — Schema + migration foundation | proxy-v2-01 (sqlx migration), proxy-v2-02 (v1→v2 data transform), proxy-v2-03 (wiki work-requests importer) |
| MV2 — Daemon runner with callsign knobs | proxy-v2-04 (presets seed), proxy-v2-05 (runner branching), proxy-v2-06 (STANDBY flow), proxy-v2-07 (EXFIL flow + typed package) |
| MV3 — CLI v2 verb surface | proxy-v2-08 (dossier verbs), proxy-v2-09 (runtime verbs), proxy-v2-10 (terminal verbs) |
| MV4 — Face system | proxy-v2-11 (small kaomoji), proxy-v2-12 (big-ASCII-art + splash), proxy-v2-13 (face rendering) |
| MV5 — Voice | proxy-v2-14 (command mode), proxy-v2-15 (per-proxy TTS routing) |
| MV6 — UI surfaces | proxy-v2-16 (TUI section grid), proxy-v2-17 (Web section grid + pages) |
| MV7 — Skills + docs | proxy-v2-18 (skill rename `/create-work-request` → `/brief`), proxy-v2-19 (ARCHITECTURE.md v4 Part III), proxy-v2-20 (repo CLAUDE.md update), proxy-v2-21 (ADR 005) |

MV1 must land first; MV2 after MV1; MV3 after MV2; MV4-MV7 fully parallelizable after MV3.

**v2.0 SHIP definition:** all 22 child slices `status: done`, ADR 005 + ARCH v4 + CLAUDE.md updates published, end-to-end `proxy brief → infil → exfil` happy path verified, v1→v2 data migration verified, voice command mode tested with at least one `proxy infil`, v2.0.0 tag pushed to develop.
