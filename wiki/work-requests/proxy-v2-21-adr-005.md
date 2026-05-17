---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: []
quality_bar: production
---

# PROXY v2 — ADR 005: 5ECH theme overhaul (MV7.21)

Write ADR 005 capturing the umbrella decision behind v2: why the theme overhaul, what alternatives were considered, what the consequences are. This is the historical record — six months from now, the question "why did we rename everything?" should land here.

## Goal

`docs/adr/005-proxy-v2-5ech-theme-overhaul.md` exists in the canonical ADR format, references prior ADRs (001-004), and tells the whole story of the 21 design decisions.

## ADR structure

### Status
Accepted, 2026-05-14

### Context
- v1.0 shipped 2026-05-12 with BMO faces, single-loop-runner, work-request vocab
- Vocabulary was engineering-internal; "synergy" of operating with 4 named operatives offered narrative + behavioral coherence
- Grilling session 2026-05-14 produced 21 locked design decisions

### Decision
Adopt v2 5ECH operative model. Four callsigns (Tracer / Quill / Phantom / Echo) on a 2×2 matrix (Comms × Trust) with three runner-level knobs (prompt addendum + pause_on + emit_cadence). Full vocabulary swap top-to-bottom. 7-state lifecycle with STANDBY + EXFIL_RDY review gates. 5-level clearance. Typed packages. Per-proxy TTS voices.

(Full enumeration of the 21 lockdowns from the epic.)

### Alternatives considered
- **Pure theme skin** (rejected): faces and names as UI presentation only. Hollow synergy.
- **Hybrid shared-core + per-proxy defaults** (rejected): less behavioral distinction.
- **Use-case-based identities without axis design** (rejected): leaves overlap (Tracer vs Echo on verbosity, Phantom vs Quill on scope).
- **Different lifecycle axes** (rejected after analysis): the 2×2 (Comms × Trust) is the cleanest decomposition.
- **Singleton-per-callsign** (rejected): caps concurrency at 4 and forces callsign-shopping.
- **Reskin-only schema** (rejected): translation layer divergence.
- **Greenfield rebuild** (rejected): premature given v1.0 just shipped.

### Consequences
**Positive**:
- Coherent vocabulary across CLI, voice, UI, docs
- Behavioral teeth (pause_on, emit_cadence) make the proxies meaningfully distinct
- 5-level clearance gives finer authority granularity
- Typed packages support both code and audit workflows

**Negative**:
- ~1 week of refactor effort (vocab swap touches Rust + TS + SQL + docs + skills)
- v1 BMO art retired
- Existing v1 work-requests need import (mechanical, low-risk)
- Higher cognitive load for new contributors (more vocab to learn upfront)

**Followups / open questions**:
- Per-proxy TTS voice picks may need iteration based on listening tests
- pause_on triggers (especially "irreversible" set) may need adjustment as edge cases surface
- Long-term: 5th callsign for recurring/scheduled work? Defer; assess in v2.1.

### References
- v2 epic: `~/projects/personal-nix/wiki/work-requests/proxy-v2-5ech-epic.md`
- ARCHITECTURE.md Part III (§§ 23-32)
- Prior ADRs 001-004 (v2 substrate)

## Files in scope

- `docs/adr/005-proxy-v2-5ech-theme-overhaul.md` (new)

## Files out of scope

- ARCHITECTURE.md (proxy-v2-19)
- CLAUDE.md (proxy-v2-20)

## Stop condition

- [ ] ADR 005 file created in canonical format
- [ ] All 21 design lockdowns listed in the Decision section
- [ ] Alternatives section enumerates at least 5 rejected paths with reasons
- [ ] Consequences section has both positive + negative
- [ ] References point to epic + ARCHITECTURE.md + prior ADRs

## Feedback loops

- Visual review
- Cross-check against the epic — does the ADR's Decision section faithfully restate the 21 lockdowns?

## Quality bar

production
