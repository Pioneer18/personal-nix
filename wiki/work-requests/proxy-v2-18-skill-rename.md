---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/projects/personal-nix
last_updated: 2026-05-14
depends_on: [proxy-v2-08-cli-dossier-verbs]
quality_bar: production
---

# PROXY v2 — skill rename + brief output format (MV7.18)

Rename `/create-work-request` skill → `/brief` (or `/create-dossier`). Update its output format from v1 work-request markdown to v2 dossier-brief markdown compatible with `proxy brief`. Update `/grill-me` skill's wiki-seed path detection and downstream skill name reference.

## Goal

User runs `/brief <slug>` → grills the user (or accepts pre-grilled spec) → writes a v2 dossier-brief markdown file → invokes `proxy brief <slug>` to import into DB → deletes the brief file. `/grill-me` produces specs compatible with this new flow.

## Skill changes

### `/create-work-request` → `/brief`
- Rename skill directory: `~/.claude/skills/create-work-request/` → `~/.claude/skills/brief/` (or `/create-dossier/`)
- Update SKILL.md frontmatter (name, description, trigger phrases)
- Update output template to v2 dossier-brief shape (matches `proxy brief` template):
  - `target_repo`, `files_in_scope`, `files_out_of_scope`, `recommended_callsign`, `recommended_clearance`, `recommended_comms`, `acceptance_criteria`, `feedback_loops`, `linked_issues`
- On completion, invoke `proxy brief <slug>` with the prepared file → daemon parses + creates dossier row → file is deleted
- Trigger phrases: `/brief <slug>`, "brief proxy on X", "create a dossier for Y"

### `/grill-me`
- Update SKILL.md wiki-seed path detection wording — still pattern `~/projects/personal-nix/wiki/seeds/<slug>.md`
- Update reference to downstream skill: `/create-work-request` → `/brief`
- Output spec format compatible with `proxy brief` (frontmatter + body)

## Files in scope

- `~/.claude/skills/create-work-request/` (rename + content update)
- `~/.claude/skills/grill-me/SKILL.md` (reference update)
- Personal-nix wiki skill registry (if any)

## Files out of scope

- `proxy brief` CLI verb (proxy-v2-08)
- Other skills (`/orient-to-machine`, etc.) — they don't reference work-requests

## Stop condition

- [ ] `/brief <slug>` works end-to-end: grill → write file → invoke `proxy brief` → file deleted, dossier row created
- [ ] `/grill-me` references the new skill name
- [ ] Old `/create-work-request` removed or archived
- [ ] Skill output format matches v2 dossier-brief template
- [ ] All four `recommended_*` fields supported (advisory; nullable)

## Feedback loops

- Invoke `/brief test-slug` → verify file written, `proxy brief` invoked, dossier in DB
- Invoke `/grill-me` against a seed → verify spec output is `proxy brief`-compatible

## Quality bar

production
