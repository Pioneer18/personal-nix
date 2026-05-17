---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: [proxy-v2-08-cli-dossier-verbs]
quality_bar: production
---

# PROXY v2 — CLI verbs: exfil / burn / drops / archive (MV3.10)

Terminal-state CLI verbs. `exfil` is the package-approval flow; `burn` is the force-fail; `drops` lists dead drops; `archive` views terminal-state history.

## Goal

Handler can review and approve packages (`exfil`), force-fail stuck infils (`burn`), peek at intermediate artifacts (`drops`), and browse history (`archive`).

## Verbs

### `proxy exfil <ref>`

For an infil in EXFIL_RDY: fetches the package payload, renders it in the terminal (PR title/body for type=pr, report content for type=report, diff for type=patch). Prompts handler for approval. On `y`, calls `POST /api/infils/{id}/exfil`, which performs the type-specific publish action.

Flags: `--auto` to skip preview prompt (for trusted callsigns); `--edit` to edit PR title/body before publishing (for type=pr).

### `proxy burn <ref>`

Force-fails a live infil. Daemon transitions infil to BURNED, kills container, logs reason. Used when an infil is stuck (e.g., infinite loop, no progress for hours) and recall feels too kind.

Flags: `--reason "..."` for audit log.

### `proxy drops [<ref>]`

No-arg: lists all current dead drops across all live infils.
With ref: lists drops for that specific infil.

Output: timestamp, file name, size, type-guess.

Subcommands:
- `proxy drops cat <ref> <filename>` — print the drop's contents
- `proxy drops save <ref> <filename> <destination>` — copy a drop to a local path

### `proxy archive`

Browse terminal-state infils (EXFIL_D, BURNED, RECALLED). Default lists most recent 20.

Flags: `--exfild`, `--burned`, `--recalled` to filter by terminal state; `--callsign <name>` to filter by callsign; `--limit N`.

## Files in scope

- `daemon/src/cli/exfil.rs`, `cli/burn.rs`, `cli/drops.rs`, `cli/archive.rs` (new)
- Daemon endpoints for drops listing if not already present from proxy-v2-07

## Files out of scope

- Web/TUI archive view (proxy-v2-16, 17)
- Voice-mode equivalents (proxy-v2-14)

## Stop condition

- [ ] `proxy exfil quill@PLRM-1222` shows package preview and prompts for approval
- [ ] `proxy exfil --auto` skips preview
- [ ] `proxy burn quill@PLRM-1222 --reason "stuck"` transitions to BURNED
- [ ] `proxy drops` lists current dead drops with metadata
- [ ] `proxy drops cat phantom@PLRM-1300 refactor.diff` prints content
- [ ] `proxy archive --burned --limit 5` lists 5 most-recent burned infils
- [ ] All verbs listed in `proxy --help`

## Feedback loops

- `cargo build`
- E2E for exfil: infil Quill → completes → EXFIL_RDY → `proxy exfil` → approve → PR opens
- E2E for burn: infil Phantom on a job, `proxy burn` mid-run, verify state

## Quality bar

production
