---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: [proxy-v2-07-exfil-flow]
quality_bar: production
---

# PROXY v2 — CLI verbs: brief / dossiers / infil / recall (MV3.08)

First batch of v2 CLI verbs. These cover the dossier-creation and infil-dispatch flow plus the handler-abort path.

## Goal

Handler can: write a dossier brief in the terminal (`proxy brief`), list briefed dossiers (`proxy dossiers`), dispatch a callsign on a dossier (`proxy infil`), abort a live infil (`proxy recall`).

## Verbs

### `proxy brief <slug>`

Opens an editor (respecting $EDITOR) with a dossier template. On save, parses the markdown frontmatter + body, creates a `dossiers` row, deletes the transient file.

Template includes: title, target_repo, files_in_scope, files_out_of_scope, recommended_callsign, recommended_clearance, recommended_comms, acceptance_criteria, feedback_loops, linked_issues, body.

Flags: `--edit` to re-open an existing dossier for edit (DB updates on save).

### `proxy dossiers`

Lists briefed dossiers (no active completed infil). Columns: slug, title, target_repo, recommended_callsign, briefed_at.

Flags: `--all` to include completed dossiers; `--repo <path>` to filter.

### `proxy infil <callsign> --dossier <slug>`

Dispatches the named callsign on the given dossier. Creates an `infils` row in LIVE state, spawns the loop container via the runner.

Flags: `--clearance <lvl>` (default = preset's default_clearance_ceiling); `--comms <loud|quiet>` (default = preset's default_comms); `--allow-slack-post`, `--allow-jira-write`, etc. for external-write overrides.

### `proxy recall <ref>`

Handler aborts a live infil. Transitions infil to RECALLED, kills container, marks standby_request resolved if open.

`<ref>` = callsign alone (if unambiguous) or `callsign@dossier-slug`.

## Files in scope

- `daemon/src/bin/proxy.rs` or wherever the CLI binary lives — add verbs
- `daemon/src/cli/brief.rs`, `cli/dossiers.rs`, `cli/infil.rs`, `cli/recall.rs` (new files)
- `daemon/src/cli/ref_resolver.rs` (new — parses `callsign` or `callsign@dossier` into infil_id)
- Existing CLI argument parser (clap or similar)

## Files out of scope

- Other CLI verbs (proxy-v2-09, proxy-v2-10)
- Voice command-mode grammar (proxy-v2-14)
- Web/TUI surfaces

## Stop condition

- [ ] `proxy brief test-slug` opens editor with template
- [ ] On save, dossiers row exists matching content
- [ ] `proxy dossiers` lists open dossiers correctly
- [ ] `proxy infil quill --dossier test-slug` creates LIVE infil, spawns container
- [ ] `proxy infil quill --dossier test-slug --clearance commit` overrides clearance
- [ ] `proxy recall quill@test-slug` transitions infil to RECALLED, kills container
- [ ] Ref resolver disambiguates: callsign alone works when one match; errors with helpful message when ambiguous
- [ ] `proxy --help` lists all 4 verbs

## Feedback loops

- `cargo build`
- Manual e2e: each verb invoked in order against dev daemon

## Quality bar

production
