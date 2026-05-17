---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: []
quality_bar: production
---

# PROXY v2 — ARCHITECTURE.md v4 (Part III: 5ECH model) (MV7.19)

Rewrite (or extend) `docs/ARCHITECTURE.md` with Part III describing the v2 5ECH operative model. Part I (v2 substrate) and Part II (v3 agentic-shell expansion) remain. Part III becomes the canonical reference for v2's runner, lifecycle, vocabulary, and surfaces.

## Goal

`ARCHITECTURE.md` Part III sections capture the 21 design lockdowns in canonical detail. Anyone picking up v2 work reads Part III and has the full picture.

## Part III outline

### § 23 — 5ECH model (overview)
- Handler / proxies / dossier / clearance / infil / exfil vocabulary
- Why v2 reshapes v1 (synergy, theme coherence, expressive lifecycle)

### § 24 — Callsign design (2×2 matrix)
- Comms axis (loud/quiet) × Trust axis (asks/runs)
- 4 corners: Tracer, Quill, Phantom, Echo with full per-callsign default table

### § 25 — Runner knobs
- prompt_addendum, pause_on, emit_cadence — how runner branches data-driven
- Tool gate enforcement of pause_on

### § 26 — Clearance system
- 5 levels: read / patch / commit / push / execute
- Default ceilings, infil-time override, external-write flags
- Exfil-controlled actions (PR create, merge, deploy)

### § 27 — Lifecycle state machine (v2)
- 7 stored states + DARK computed
- Dossier-vs-infil state split
- Transition diagram (markdown ascii)

### § 28 — Vocabulary swap (top-to-bottom mapping)
- v1 → v2 rename table (DB tables, code identifiers, API routes, CLI verbs)
- `loop` (internal substrate) retained
- "5ECH" as UI branding

### § 29 — Package & dead drops
- Typed package (pr / report / patch / mixed)
- Drops as opaque file blobs, auto-purge policy

### § 30 — Voice integration v2
- Hey PROXY wake-word retained
- Command mode (voice→CLI grammar)
- Per-proxy TTS voice routing

### § 31 — Face system v2
- Hybrid kaomoji + big-ASCII-art
- 5 per-callsign expressions + 3 shared universal

### § 32 — Migration plan (v1.0 → v2.0)
- Clean cutover strategy
- v1 wiki work-requests importer
- Skill ecosystem update

## Files in scope

- `docs/ARCHITECTURE.md` (extend with Part III, §§ 23-32)
- Optional: a `docs/architecture-v2-quickref.md` for at-a-glance lookup

## Files out of scope

- ADR 005 (proxy-v2-21)
- CLAUDE.md update (proxy-v2-20)
- v1 docs (untouched — they remain valid for the substrate)

## Stop condition

- [ ] Part III added to ARCHITECTURE.md with all 10 sections
- [ ] All 21 design lockdowns reflected in canonical text
- [ ] State transition diagram included
- [ ] Vocab swap mapping table included
- [ ] Cross-references to ADRs 001-004 (v2 substrate) + ADR 005 (v2 theme)
- [ ] Markdown lints pass (no broken refs, valid frontmatter if any)

## Feedback loops

- Visual review of rendered markdown
- Cross-check each § against the 21 lockdowns

## Quality bar

production
