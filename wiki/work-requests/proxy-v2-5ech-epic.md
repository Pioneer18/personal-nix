---
status: open
type: epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-17
quality_bar: production
---

# PROXY v2 — 5ECH operative-model theme overhaul (EPIC)

v2 transforms PROXY's BMO-themed work-orchestrator into a Splinter-Cell-styled operative section. Four named callsigns (Tracer / Quill / Phantom / Echo) with distinct behavioral knobs replace the single-loop-runner model. New vocabulary swaps top to bottom (dossier, infil, clearance, exfil, standby, burned, recalled). Substrate (daemon, voice, sensor, admission, Docker loop runner, MCP) is preserved; schema, CLI, faces, voice routing, web/TUI all migrate to v2 shape.

## Why now

PROXY v1.0 shipped 2026-05-12. v1.0's vocabulary (work-request, run, queue, BMO faces) is engineering-internal and lacks the synergy of a coherent operative metaphor. v2:

- Gives each callsign distinct behavior (prompt addendum + pause_on + emit_cadence) mapped to a 2×2 personality matrix (Comms × Trust)
- Replaces ad-hoc "single face for whole system" with per-callsign grid view
- Adds explicit STANDBY + EXFIL_RDY states for handler review gates
- Adds typed packages (PR / report / patch) + dead-drop intermediate artifacts
- Aligns CLI, voice, faces, and docs around one coherent vocabulary

## Locked design decisions (21)

**Identity & section model**
1. Four callsigns on a 2×2 matrix: Comms (loud/quiet) × Trust (runs/asks). Tracer (Loud×Runs), Echo (Loud×Asks), Phantom (Quiet×Runs), Quill (Quiet×Asks)
2. Scope and clearance are infil flags (orthogonal to callsign)
3. Multi-instance: callsign is a tag, many concurrent infils allowed, addressed as `callsign@dossier`
4. Section view = grid of 4 always-present callsign cards with counts + worst-state face

**Runner behavior**
5. Each callsign sets 3 runner knobs: system-prompt addendum + pause_on event list + emit_cadence
6. pause_on triggers STANDBY: all callsigns on impasse; Quill+Echo on clearance_boundary; Echo only on irreversible
7. Irreversible = strict core: push-to-protected, force-push, gh pr merge, deploys, applied prod migrations, destructive ops outside working tree
8. In-branch commits flow freely; PR create is exfil-controlled
9. Echo's pre-commit "announce intent" is a comms behavior (loud channel), separable from STANDBY

**Clearance**
10. 5 levels: `read` → `patch` → `commit` → `push` → `execute`
11. Default ceilings: Tracer=read, Quill=commit, Phantom=push, Echo=commit (overridable down at infil)
12. External writes via explicit infil flags (`--allow-slack-post`, etc.)

**Lifecycle**
13. 7 stored states: BRIEFED, LIVE, STANDBY, EXFIL_RDY, EXFIL'D, BURNED, RECALLED. DARK is computed from heartbeat freshness, not stored
14. State split: BRIEFED on dossier, running states on infil

**Vocabulary & schema**
15. Full vocab swap top-to-bottom: `work_requests`→`dossiers`, `runs`→`infils`, `feed_items`→`comms_events`, `pending_approvals`→`standby_requests`. `loop` (Docker container) stays internal. `proxy-daemon` binary unchanged; "5ECH" is UI branding
16. DB-canonical dossiers; transient markdown brief parsed at `proxy brief` time; advisory recommendation fields (callsign / clearance / comms)

**CLI surface**
17. 12 verbs: brief, dossiers, infil, status, comms, grant, deny, exfil, recall, burn, drops, archive

**Package & drops**
18. Package is typed (`pr` / `report` / `patch` / `mixed`) with type-specific exfil behavior; drops are untyped file blobs at `~/.proxy/drops/<infil_id>/`, auto-purged on terminate

**Voice**
19. Keep "Hey PROXY" wake-word; add command-mode (voice→CLI); per-proxy TTS voices using macOS built-in voices

**Faces**
20. Hybrid: kaomoji for grid (5 per-callsign expressions) + signature big-ASCII-art per callsign for splash/detail + 3 shared universal faces (burned / recalled / dark). ~27-31 assets

**Migration**
21. Clean cutover + light data import: import open work-requests → dossiers; archive closed; seeds unchanged; skills update in cutover

## Slice plan

### MV1 — Schema + migration foundation
- [proxy-v2-01-schema-migration](proxy-v2-01-schema-migration.md) — sqlx migration for new tables
- [proxy-v2-02-data-migration](proxy-v2-02-data-migration.md) — v1→v2 transform script
- [proxy-v2-03-wiki-import](proxy-v2-03-wiki-import.md) — `wiki/work-requests/*.md` importer

### MV2 — Daemon runner with callsign knobs
- [proxy-v2-04-presets-seed](proxy-v2-04-presets-seed.md) — `proxy_presets` rows for 4 callsigns
- [proxy-v2-05-runner-branching](proxy-v2-05-runner-branching.md) — loop runner reads preset, injects knobs
- [proxy-v2-05a-liveness-and-reaper](proxy-v2-05a-liveness-and-reaper.md) — heartbeat endpoint + reaper task + dossier failure_count escalation (added 2026-05-16 from state-machine grilling)
- [proxy-v2-06-standby-flow](proxy-v2-06-standby-flow.md) — STANDBY + grant/deny
- [proxy-v2-07-exfil-flow](proxy-v2-07-exfil-flow.md) — EXFIL_RDY + typed package + handler approval

### MV3 — CLI v2 verb surface
- [proxy-v2-08-cli-dossier-verbs](proxy-v2-08-cli-dossier-verbs.md) — brief / dossiers / infil / recall
- [proxy-v2-09-cli-runtime-verbs](proxy-v2-09-cli-runtime-verbs.md) — status / comms / grant / deny
- [proxy-v2-10-cli-terminal-verbs](proxy-v2-10-cli-terminal-verbs.md) — exfil / burn / drops / archive

### MV4 — Face system
- [proxy-v2-11-face-assets-small](proxy-v2-11-face-assets-small.md) — kaomoji + universal
- [proxy-v2-12-face-assets-big](proxy-v2-12-face-assets-big.md) — big ASCII-art + splash
- [proxy-v2-13-face-rendering](proxy-v2-13-face-rendering.md) — CLI/TUI/Web face components

### MV5 — Voice
- [proxy-v2-14-voice-command-mode](proxy-v2-14-voice-command-mode.md) — voice→CLI grammar
- [proxy-v2-15-voice-tts-routing](proxy-v2-15-voice-tts-routing.md) — per-proxy macOS voice routing

### MV6 — UI surfaces
- [proxy-v2-16-tui-section-grid](proxy-v2-16-tui-section-grid.md) — Ink TUI dashboard
- [proxy-v2-17-web-section-grid](proxy-v2-17-web-section-grid.md) — Next.js web UI

### MV7 — Skills + docs
- [proxy-v2-18-skill-rename](proxy-v2-18-skill-rename.md) — `/create-work-request` → `/brief`
- [proxy-v2-19-architecture-v4](proxy-v2-19-architecture-v4.md) — ARCHITECTURE.md v4 rewrite
- [proxy-v2-20-claude-md-update](proxy-v2-20-claude-md-update.md) — repo CLAUDE.md alignment
- [proxy-v2-21-adr-005](proxy-v2-21-adr-005.md) — ADR 005 capturing rationale

### MV8 — Provider abstraction (Claude / Codex) — ADR 009
- [proxy-v2-22-provider-schema](proxy-v2-22-provider-schema.md) — `infils.provider` + `repo_configs.default_provider` + `provider_state` table
- [proxy-v2-23-provider-trait](proxy-v2-23-provider-trait.md) — `Provider` trait + `ClaudeProvider` / `CodexProvider` impls in `daemon/src/providers/`
- [proxy-v2-24-loop-image-bilingual](proxy-v2-24-loop-image-bilingual.md) — single container image with both CLIs + entrypoint dispatch on `$PROXY_PROVIDER`
- [proxy-v2-25-env-auth-injection](proxy-v2-25-env-auth-injection.md) — OpenAI key in encrypted store + per-provider env + mount routing
- [proxy-v2-26-admission-gate-5](proxy-v2-26-admission-gate-5.md) — Gate 5 provider quota check + 429 detection + optional auto-fallback
- [proxy-v2-27-chat-tab-bilingual](proxy-v2-27-chat-tab-bilingual.md) — dual-window tmux (claude/codex) + voice-daemon active-window awareness
- [proxy-v2-28-cli-provider-verbs](proxy-v2-28-cli-provider-verbs.md) — `proxy provider {status,pause,resume,switch-all-queued}` + `--provider` flag on `proxy infil`
- [proxy-v2-29-presets-codex-addendum](proxy-v2-29-presets-codex-addendum.md) — Codex addendum text for the 4 callsigns + presets-seed migration

## Dependency graph

```
MV1 (01 → 02 → 03)
   ↓
MV2 (04 → 05 → 05a → 06, 07)
   ↓
MV3 (08, 09, 10  — parallel)
   ↓
MV4-MV7 (11-21  — fully parallelizable; MV6.17 also depends on 05a for two-tier dossier badge spec)
   ↓
MV8 (22 → 23 → 24 → 25 → 26 substrate; 27, 28, 29 fan out)
   ↑
   amends MV1.01 schema and MV2.05 runner; can land in parallel with MV4-MV7 once MV2 is stable
```

MV1.01 (schema) must land before anything else. MV2.04 (presets seed) before MV2.05 (runner reads presets). **MV2.05a (liveness + reaper) is the keystone between 05 and 06/07** — STANDBY and EXFIL_RDY both depend on heartbeat semantics being live. After MV3, all face/voice/UI/docs slices can fan out via Tachikoma in parallel.

**MV8 ordering**: 22 (schema amendment) must land before 23-26 (which read the new columns). 26 (admission Gate 5) must land before 27 (chat-tab dual-window uses the same provider-state surface for its voice routing). 27, 28, 29 are independent of each other once 26 is in. MV8 does **not** block v2 ship — if it slips, v2 ships Claude-only and MV8 lands as a follow-on minor (v2.1).

## Definition of done (v2 ship)

- All 22 child slices marked `status: done`
- ADR 005 published, ARCHITECTURE.md v4 published, repo CLAUDE.md updated
- `proxy status` renders the grid view with 4 callsign cards
- End-to-end happy path verified: `proxy brief <slug>` → `proxy infil <callsign> --dossier <slug> --clearance <lvl>` → loop runs → `proxy exfil <ref>` opens PR
- Voice command mode tested with at least one `proxy infil` invocation
- v1→v2 data migration verified (open work-requests imported as dossiers; no data loss)
- v2.0.0 tag pushed to `develop`

## References

- v1.0 build-state: `~/projects/personal-nix/wiki/notes/agentic-shell-build-state.md`
- v1.0 ARCHITECTURE: `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md`
- v1.0 ADRs 001-004: `~/Projects/tachikoma-starter/docs/adr/`
- ADR 009 (provider abstraction — Claude/Codex interchange, drives MV8): `~/Projects/tachikoma-starter/docs/adr/009-provider-abstraction-claude-codex.md`
- Grilling session that produced this epic: 2026-05-14
- ADR 009 + MV8 added: 2026-05-17 (in response to Anthropic Max rate-limit incident 2026-05-16)
