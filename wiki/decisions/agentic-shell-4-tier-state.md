---
title: "Agentic shell: 4-tier state model + team-shareable boundary"
tags: [agentic-shell, proxy, state, sync, icloud, multi-mac, team-shareable]
last_updated: "2026-05-11"
status: accepted
---

# Agentic shell: 4-tier state model + team-shareable boundary

**Status**: Accepted — 2026-05-11.

**Scope**: This decision applies to Pioneer18's MacBook-Pro-2 (and any future Mac running the agentic shell). It defines what data follows the user across machines, what stays local, and where the team-shareable boundary lies.

## Context

During the 2026-05-11 agentic-shell grilling (immediate follow-on to the PROXY v2 redesign — see [`docs/ARCHITECTURE.md`](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) Part II), the user articulated a multi-Mac vision:

> I want to MAX out what nix will allow me to do, being able to just instant boot my setup on any machine […] I also want like a generic version or option for sharing this with my teammates but not dumping all my data on them.

The vision has two distinct axes that initial framing conflated:

1. **Sync model** — what state follows the user across their own Macs vs lives only on each machine.
2. **Shareability** — what's safe to share with teammates (substrate) vs what's personal (config + work + memory).

These are orthogonal. The 4-tier model resolves both.

### Forces

- The user already runs a two-layer nix-darwin setup: team `dev-environment` (RelyMD-shared) + personal `personal-nix` (private). The agentic-shell layering extends this pattern with substrate + personal + iCloud + per-machine tiers.
- Memory (the `~/.claude/projects/.../memory/` directory) is currently per-machine. The user wants claude to "remember them" on every Mac — memory must follow.
- Wiki, work-requests, runbooks, recipes, decisions, notes — collectively "my work" — must follow. They live in `personal-nix` today, which already git-syncs.
- Chat history is huge (potentially GB per machine over time), privacy-sensitive across devices, and rarely useful from the "other Mac." Best kept per-machine.
- PROXY queue / sensor data is machine-specific by nature (different containers, different memory pressure history). Per-machine.
- Coworker adoption requires a clean substrate fork with no personal data leak. `tachikoma-starter` is the natural Tier-0 home; it's already a public repo.

### Alternatives considered

1. **Two-tier (nix + per-machine, no iCloud sync)** — simplest but loses memory continuity across Macs. Claude has to relearn the user on every Mac. Rejected.
2. **Maximalist sync (everything replicates via custom Postgres replication or similar)** — most "magical" but most fragile. Replication lag, conflicts, schema drift, mid-flight queue items mid-replicated. Cost of fragility outweighs the benefit (chat history is rarely needed on the "other" Mac anyway). Rejected.
3. **Three-tier (nix + iCloud + per-machine) without team boundary** — works for personal multi-Mac but doesn't address the shareable substrate concern. Rejected as incomplete.
4. **Four-tier (chosen)** — adds the team-substrate tier explicitly. Each tier has a clear home, sync mechanism, and recovery path on a new Mac.

## Decision

**Four-tier state model with explicit shareability boundary at Tier 0.**

### Tiers

| Tier | What | Where | New-Mac recovery |
|---|---|---|---|
| **0 — Team substrate** (public, shareable) | PROXY platform code, generic skills, default configs, gating logic, voice daemon, templates | [`tachikoma-starter`](https://github.com/MioMarker/tachikoma-starter) repo | Anyone forks, runs bootstrap, gets platform with no personal data |
| **1 — Personal config + work** (private, git-sync) | User's skills, MCPs, packages, **wiki, work-requests, runbooks, recipes, decisions, notes** | [`personal-nix`](https://github.com/Pioneer18/personal-nix) repo | `personal-nix/bootstrap.sh` clones + restores all |
| **2 — Synced state** (iCloud + Keychain) | Memory (`~/.claude/projects/.../memory/`), Keychain secrets, Shortcuts (already auto-sync), wallpapers | iCloud Drive + Keychain (both iCloud-replicated) | Automatic when iCloud connects post-bootstrap |
| **3 — Per-machine local** | Chat history, PROXY queue runtime, sensor samples, build caches, worktrees, recommendation history | Local DB / local files | Doesn't restore — fresh each Mac |

### Memory iCloud sync — the small new piece

`~/.claude/projects/-Users-pioneer/memory/` is currently per-machine. v3 moves it to iCloud Drive on each Mac, one-time:

```bash
# One-time setup, on each Mac:
mv ~/.claude/projects/-Users-pioneer/memory \
   ~/Library/Mobile\ Documents/com~apple~CloudDocs/.claude-memory
ln -s ~/Library/Mobile\ Documents/com~apple~CloudDocs/.claude-memory \
      ~/.claude/projects/-Users-pioneer/memory
```

After this, `MEMORY.md` and all memory entries follow across Macs automatically.

**Conflict resolution**: iCloud's standard last-writer-wins. Acceptable because memory entries are mostly append-only — claude saves new memories, doesn't typically edit existing ones. Edge cases (two Macs concurrently saving similar memories) collapse via duplicate-detection on next read.

**Bootstrap idempotence**: the symlink check is added to `personal-nix/scripts/sync-memory.sh` (planned) — runs on each `dev` invocation; sets up the symlink if absent, no-op if present.

### Team-shareable boundary — how a coworker adopts

The boundary is at Tier 0 ↔ Tier 1. Tier 0 is the public substrate; Tier 1 is the user's private overlay.

Adoption flow:

1. **Fork `tachikoma-starter`** — get the PROXY platform code, default skills, default configs. Zero personal data crosses.
2. **Clone `personal-nix-template`** — empty skeleton shipped in `tachikoma-starter` as `templates/personal-nix-template/`. They commit it to their own private repo as their `personal-nix`.
3. **Sign into their own iCloud** — fresh memory, no leak.
4. **Run bootstrap** — their own `personal-nix/bootstrap.sh`, fed from their own GitHub.

No data crosses. Substrate is reusable; personal layers are private to each adopter.

### `personal-nix-template` — the skeleton

Ships in `tachikoma-starter` as `templates/personal-nix-template/`:

```
personal-nix-template/
├── packages.nix          # empty list, ready to fill
├── mcp.nix               # bootstrap MCPs only (no personal API keys)
├── skills/               # empty
├── wiki/                 # template subdirs:
│   ├── runbooks/
│   ├── decisions/
│   ├── recipes/
│   ├── notes/
│   └── work-requests/
├── scripts/
│   └── secrets-from-keychain.sh   # generic template
└── bootstrap.sh          # tailored to the forker's username on first run
```

## Consequences

**Positive:**
- Memory follows you. Open a new Mac, run bootstrap, and after iCloud syncs, claude already knows your role, preferences, and prior decisions.
- Wiki + work-requests + runbooks follow you via the existing `personal-nix` git sync. No new infrastructure.
- Team adoption is friction-free for coworkers — fork the substrate, start their own personal layer, never see your data.
- Privacy boundaries are explicit: Tier 0 is shareable, Tier 1 is private to you, Tier 2 follows you only, Tier 3 stays put. No accidental cross-contamination.

**Negative:**
- Memory iCloud sync depends on iCloud being healthy. iCloud Drive sometimes lags (minutes to hours) on slow connections. Mitigation: the symlink targets the iCloud Drive folder; if iCloud is offline, you have last-synced state, not nothing.
- `personal-nix-template` requires careful audit to ensure no personal data slipped into it from the source `personal-nix`. Mitigation: a one-time scrubbing pass, then a CI check on `tachikoma-starter` PRs to flag anything that looks like an API key, username, or path-specific content.
- The 4-tier model is more complex than two-tier; new contributors to `tachikoma-starter` need to understand which tier a new feature's data lives in. Mitigation: this decision doc + ARCH.md § 20 + a per-feature checklist in the README.

**Follow-on work:**

- (Now) ✅ Land this decision doc.
- (M1, week 1-2) Implement the memory iCloud sync setup (one-shot script + nix activation hook).
- (Eventual v2.0) Build and ship the `personal-nix-template` skeleton inside `tachikoma-starter` after a thorough personal-data audit of the current `personal-nix` repo.
- (Eventual) CI check on `tachikoma-starter` PRs that scans for personal-data leakage patterns (API keys, usernames, machine-specific paths).

## See also

- [`~/Projects/tachikoma-starter/docs/ARCHITECTURE.md`](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) § 20 — 4-tier state model in ARCH.md
- [`~/Projects/tachikoma-starter/docs/adr/001-proxy-scope-expansion-agentic-shell.md`](~/Projects/tachikoma-starter/docs/adr/001-proxy-scope-expansion-agentic-shell.md) — parent ADR
- [`agentic-shell-v1-slice-plan`](../recipes/agentic-shell-v1-slice-plan.md) — M1 includes the memory sync setup
