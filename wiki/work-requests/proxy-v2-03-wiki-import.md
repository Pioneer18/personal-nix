---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: [proxy-v2-01-schema-migration, proxy-v2-02-data-migration]
quality_bar: production
---

# PROXY v2 — wiki work-requests importer (MV1.03)

One-shot importer that reads `~/projects/personal-nix/wiki/work-requests/*.md` files (the file-based v1 work-request queue), creates a `dossiers` row per open work-request, and archives the rest. Wiki work-requests folder is finally retired as a queue substrate.

## Goal

After running, all open file-based work-requests exist as dossiers in the v2 DB. Closed/done work-request files moved to `_archive/v1-work-requests/`. The `wiki/work-requests/` folder retains only the v2 epic + child slice files (which are part of v2 itself).

## Behavior

For each `wiki/work-requests/*.md`:
1. Parse YAML frontmatter
2. If `status: open` or `status: blocked` and NOT a `proxy-v2-*` file → create `dossiers` row with title (from H1 heading), body (md content), target_repo, files_in_scope (if present), recommended_callsign (heuristic from filename or unset), briefed_by="wiki-import", briefed_at=file mtime
3. If `status: done` or `status: superseded` → move file to `_archive/v1-work-requests/`
4. If file is a `proxy-v2-*-epic` or child slice → leave in place (they're v2 work in flight)
5. Log every action

## Files in scope

- `daemon/src/bin/wiki_import.rs` (new — one-shot CLI binary)
- `daemon/Cargo.toml` (add binary entry)

## Files out of scope

- Skill rename (`/create-work-request` → `/brief`) — handled in proxy-v2-18
- Wiki seeds folder — untouched (still pre-grilling ideas)
- Other wiki dirs (decisions, recipes, runbooks) — untouched

## Stop condition

- [ ] Binary builds: `cargo build --bin wiki_import`
- [ ] Running `wiki_import --dry-run` lists what would happen, no DB writes
- [ ] Running `wiki_import` (no flag) executes the imports
- [ ] All open work-requests in wiki now have matching `dossiers` rows
- [ ] Done/superseded work-requests in `_archive/v1-work-requests/`
- [ ] proxy-v2-* files (epic + children) untouched
- [ ] Wiki seeds folder untouched
- [ ] Log file emitted: `~/projects/personal-nix/wiki/notes/v2-wiki-import-<date>.md` with action list

## Feedback loops

- `cargo build --bin wiki_import`
- `cargo run --bin wiki_import -- --dry-run`
- Manual review of dry-run output
- `cargo run --bin wiki_import`
- `psql -c "select title from dossiers where briefed_by = 'wiki-import';"`

## Quality bar

production
