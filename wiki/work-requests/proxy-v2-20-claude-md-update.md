---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: [proxy-v2-19-architecture-v4]
quality_bar: production
---

# PROXY v2 — repo CLAUDE.md alignment with v2 vocab + rules (MV7.20)

Update `~/Projects/tachikoma-starter/CLAUDE.md` so it aligns with v2 vocabulary, references ARCHITECTURE.md v4, and updates the hard-rules + tech-stack truth.

## Goal

Repo CLAUDE.md is the entry point for any agent (claude session or otherwise) working on the codebase. After this slice, that doc reflects v2's vocabulary, lifecycle, hard rules, and points to ARCHITECTURE.md Part III as canonical.

## Update areas

### Vocabulary section
- Rename: work-request → dossier, run → infil, queue → on-deck, etc.
- Add the callsign table (Tracer / Quill / Phantom / Echo)
- Add the 5-level clearance system

### State machine section
- Replace v1 `open → grabbed → done` with v2 7-state diagram
- Note dossier-vs-infil state split

### Hard rules
- Keep existing v2-substrate rules (memory awareness, never kill loops, etc.)
- Add: never bypass pause_on triggers (handler must grant/deny STANDBY)
- Add: exfil-controlled actions never granted as clearance (only via `proxy exfil` approval)
- Add: clearance ceiling cannot be exceeded by infil flags (only downgraded)

### Tech stack
- Update with v2 tables (`dossiers`, `infils`, etc.) replacing v1
- Note 5ECH branding distinction (UI/voice label; daemon binary stays `proxy-daemon`)

### Branding section
- Rewrite the BMO faces section as v2 face system (hybrid kaomoji + big-art)
- Reference proxy-v2-11/12 face assets and proxy-v2-13 rendering

### Pointers
- Add link to ARCHITECTURE.md § 23-32 (Part III)
- Add link to ADR 005 (proxy-v2-21)

## Files in scope

- `~/Projects/tachikoma-starter/CLAUDE.md`

## Files out of scope

- ARCHITECTURE.md (proxy-v2-19)
- ADR 005 (proxy-v2-21)
- Personal-nix global CLAUDE.md (not in repo scope)

## Stop condition

- [ ] All v1 vocabulary in CLAUDE.md replaced with v2 equivalents
- [ ] Callsign table present
- [ ] Clearance system documented
- [ ] State machine diagram updated
- [ ] Hard rules section updated with v2 additions
- [ ] Tech-stack section reflects v2 schema
- [ ] Pointers to ARCHITECTURE.md Part III + ADR 005 added
- [ ] Markdown valid; no broken references

## Feedback loops

- Visual review of rendered CLAUDE.md
- Sanity check: any v1 term that appears (e.g., `work_request`) is intentional and noted as legacy

## Quality bar

production
