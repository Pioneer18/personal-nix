---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-14
---

# PROXY — Notebook `todo` category removal + migration (slice 36)

Remove `notebook.todo` as a default category per ADR 007 D11. Migrate any extant `notebook.todo` rows to either a Follow-up on a "Migrated reminders" Op (if `due_at` was set) or to a `notebook.idea` row (if no `due_at`). Update notebook surfaces (web + TUI) + notification routing.

## Goal

`notebook.todo` deprecation is clean: zero data loss, notifiable reminders preserved via Follow-up's `remind_at`, idea-shaped entries demoted to `notebook.idea`. After ship, the Notebook substrate matches ADR 007's two-category model (`idea` + `custom`).

## Files in scope

- `daemon/migrations/NNNN_remove_notebook_todo.sql` — drops `todo` from `notebook.category` enum default; existing rows preserved until migrated by runtime job (don't auto-delete in migration)
- `daemon/src/notebook/migrate_todo.rs` — one-shot migration runner; idempotent:
  - For each `notebook.todo` row WITH `due_at` set: create Follow-up under a "Migrated reminders" Op in `relymd` Theater (create Op if doesn't exist), copy text → Follow-up text, `due_at` → `remind_at`, mark original notebook row `migrated_to=follow_up:<fu-id>`
  - For each `notebook.todo` row WITHOUT `due_at`: re-categorize as `notebook.idea` (preserve body, tags, created_at); mark `migrated_from=todo`
  - Log all migrations to `feed_items` for audit
- `daemon/src/cli/notebook.rs` — modify `notebook` subcommands to reject `todo` as a category arg; suggest using `proxy fu add` instead
- `apps/web/components/notebook/*` — remove `todo`-specific UI (due-date picker on capture form, todo filter button)
- `apps/web/components/notebook/IdeaPromotionMenu.tsx` — already extended in slice 35 to include "Promote to Op"; this slice ensures it remains the only promotion target plus existing "Promote to work-request"
- `apps/tui/src/components/NotebookPane.tsx` — if such a pane exists; remove todo display (defer to slice 34 if not yet built)
- Notification scheduler: ensure no jobs are still scheduled against `notebook.todo.due_at`; if any, they must have been migrated by `migrate_todo.rs` (verify via post-migration audit query)
- Documentation: update CLAUDE.md "Notebook" section (already done in ADR 007 PR), confirm consistent
- Skill files: `~/.claude/skills/wiki/` and any other skills that reference `notebook.todo` capture — audit + update to recommend `proxy fu add` (or `/op-grill` for Op-level reminders)

## Files out of scope

- The Op + Objective + Follow-up data model (slice 30)
- Triage / proactive engine (slices 31-32)
- Skills `/op` / `/op-grill` / `/op-next` (slice 33)
- TUI / web surfaces beyond notebook cleanup (slices 34-35)
- ADR 007 reference updates (already done at ADR creation time)

## Stop condition

- [ ] Migration `NNNN_remove_notebook_todo.sql` runs clean on a DB with existing `notebook.todo` rows; does NOT delete rows (defers to runtime migration)
- [ ] Runtime migration `migrate_todo.rs`:
  - [ ] Creates "Migrated reminders" Op in `relymd` Theater (P3 priority, `state=live`) if at least one `notebook.todo` with `due_at` exists; otherwise skips Op creation
  - [ ] For each `todo` WITH `due_at`: creates Follow-up with `remind_at = due_at`, `text = notebook.body`; original row marked `migrated_to=follow_up:<fu-id>`; original row's `due_at` is cleared so scheduler doesn't double-fire
  - [ ] For each `todo` WITHOUT `due_at`: re-categorizes to `idea`; marks `migrated_from=todo`
  - [ ] Idempotent: re-running the migration on an already-migrated row is a no-op
  - [ ] Emits one `feed_item` per migration with kind `notebook_todo_migrated`
- [ ] Notification scheduler audit: post-migration, no scheduled jobs reference a `notebook.todo` row; all migrated to Follow-up `remind_at` (extends `proxy-11b-pg-scheduler`)
- [ ] `proxy notebook add --category todo` CLI command errors with helpful message ("`todo` is removed; use `proxy fu add <op-slug>` for notifiable reminders, or `/op-grill` for Op-level capture")
- [ ] Web capture form for Notebook no longer shows `todo` option in category dropdown
- [ ] Existing `notebook.todo` rows (post-migration) are hidden from default notebook list view (they're "archived"); admin / `--all` flag still shows them for auditability
- [ ] All references in `~/.claude/skills/` to `notebook.todo` updated (audit via grep `notebook.todo` in skill files)
- [ ] CLAUDE.md "Notebook" section confirmed accurate (single-category-removal + two-category-default per ADR 007 D11)
- [ ] `seeds-folder.md` decision doc updated if it references `notebook.todo` semantics (the M6 importer pattern is unchanged — it only handles `idea`)
- [ ] `cargo test` covers: migration idempotence, with-`due_at` path, without-`due_at` path, Op creation conditional logic, notification scheduler audit query returns 0 todo references
- [ ] `cargo clippy --all-targets -- -D warnings`
- [ ] `pnpm test` + `pnpm typecheck` + `pnpm lint` clean for web changes

## Feedback loops

- `cargo test`
- `pnpm test`
- Manual: seed DB with sample `notebook.todo` rows (with + without `due_at`), run migration, verify Follow-ups created under "Migrated reminders" Op, idea conversions correct, no notification scheduler residue

## Quality bar

production

## v3 context

- See ADR 007 D10 + D11 for migration design
- Depends on slice 30 (Follow-up infrastructure), slice 33 (skill updates), slice 35 (web UI updates)
- This is the cleanup slice; ship LAST in the Op vertical
- If at ship time no `notebook.todo` rows exist (likely — handler hasn't been actively using it), migration is a near no-op; still ship to remove the capture surfaces + enum entries
- Audit `~/.claude/skills/wiki/` skill carefully — it's the most likely place where `notebook.todo` references linger
- Post-ship, ADR 007 D10 + D11 obligations are fully discharged
