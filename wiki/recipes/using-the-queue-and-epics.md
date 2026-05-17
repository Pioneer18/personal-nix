---
title: "Using PROXY queue + Epics"
tags: [recipe, proxy, queue, epic, workflow]
last_updated: 2026-05-14
related:
  - ~/Projects/tachikoma-starter/docs/adr/006-epic-queue-architecture.md
  - ~/projects/personal-nix/wiki/QUEUE.yaml
---

# Using PROXY queue + Epics

How to organize work-requests into Epics, set priority order, and grab work via Tachikoma — using the Epic + Queue infrastructure shipped in proxy-27/28/29 (ADR 006).

## Mental model in 60 seconds

- **Slice** = a single work-request `.md` file at `~/projects/personal-nix/wiki/work-requests/<slug>.md`. Unchanged from before.
- **Epic** = a named container of related slices with a goal + ordered slice list. Each slice belongs to at most one Epic. Slices without an Epic are **standalone**.
- **Queue** = a single ordered list (top → bottom) of Epics + standalones. **Source of truth: `~/projects/personal-nix/wiki/QUEUE.yaml`.**
- **Grab** = walk queue top-down. Top Epic's first ready slice wins (respects `blocked_by` in slice frontmatter). Standalones grabbed when no Epics in queue. Parallel Tachikomas all pull from current top Epic.
- **Pause** = manual override on an Epic, hides it from grab.
- **Status** = derived from contained slices. Don't set manually except `paused: true`.

## Three ways to interact (today reality + tomorrow ergonomics)

| Method | State | Use when |
|---|---|---|
| **Edit `QUEUE.yaml` directly** | ✅ Works today | Always works; canonical source of truth; clean git diffs |
| `proxy queue {add-epic, add-slice, mv, pause, resume, grab, next}` CLI | ⚠️ Needs build + install | Once `proxy` binary is on PATH |
| Web UI at `/queue` (drag-reorder) | ⚠️ Needs daemon + web app rebuild | Once services restart with new code |
| `tachikoma queue` (no slug) auto-grab | ⚠️ Needs slice 29's wiring active | Once daemon is rebuilt |

To activate the ergonomic paths after a fresh proxy-27/28/29 ship:

```bash
cd ~/Projects/tachikoma-starter
cargo build --release                              # builds proxy-daemon + proxy CLI
cp target/release/proxy ~/.local/bin/proxy         # or whatever your install path is
launchctl kickstart -k "gui/$(id -u)/com.proxy.daemon"   # restart daemon
# Web app restart depends on how Next.js is launched (daemon-managed subprocess per ARCH.md)
```

Until rebuild + restart, **edit `QUEUE.yaml` directly** — daemon will pick it up on next start.

## Create a new Epic (direct YAML edit)

1. Open `~/projects/personal-nix/wiki/QUEUE.yaml` in your editor
2. Add a new entry to the `queue:` list at your desired position:

```yaml
queue:
  - epic: <kebab-case-slug>
    title: "Human-readable title"
    goal: "One-line outcome — what's true when this Epic is done?"
    slices:
      - <work-request-slug-1>
      - <work-request-slug-2>
      - <work-request-slug-3>
```

3. Save. Daemon `kqueue` watcher picks up the change + syncs to DB (when daemon is on new binary).

4. Verify the slice slugs reference real files at `~/projects/personal-nix/wiki/work-requests/<slug>.md`. Daemon warns on unknown slugs but doesn't crash.

## Add slices to an existing Epic

Append (or insert at a position) to the Epic's `slices:` list:

```yaml
  - epic: email-vertical
    title: "Email management vertical"
    goal: "Inbox triage + Reviewer + iterative compose for RelyMD Outlook"
    slices:
      - proxy-19-outlook-msgraph-auth
      - proxy-20-email-briefing-engine
      - <new-slice-here>           # ← insert
      - proxy-21-email-folder-taxonomy
      ...
```

## Reorder Epics in the queue

Drag/move the YAML entry. Position in the file IS the priority — top of file = highest priority.

```yaml
queue:
  - epic: urgent-bugfix         # ← moved to top, becomes active
  - epic: email-vertical        # ← was top, now second
  ...
```

## Reorder slices within an Epic

Reorder the `slices:` list. First in list = first to grab.

```yaml
  - epic: email-vertical
    slices:
      - proxy-19-outlook-msgraph-auth     # ← still first
      - proxy-21-email-folder-taxonomy    # ← bumped up
      - proxy-20-email-briefing-engine    # ← bumped down
```

Watch out: if you have `blocked_by:` in slice frontmatter, list order can be misleading (slices skip until blockers done). Use list order for *preference*; use `blocked_by` for *constraint*.

## Pause/resume an Epic

```yaml
  - epic: telemetry-v2
    title: "Telemetry hardening"
    goal: "..."
    paused: true                # ← hides Epic from grab, keeps in list
    slices: [...]
```

Remove the `paused:` line to resume.

## Add a standalone work-request

A slice not in any Epic — gets grabbed when no Epics are in the queue (or no Epics active).

```yaml
queue:
  - epic: email-vertical
    ...
  - standalone: shell-cleanshot-tool-catalog
  - standalone: proxy-tui-face-redesign
    paused: true                # standalones can also be paused
```

## Grab the next ready slice

**Once `proxy` CLI is installed**:
```bash
proxy queue grab          # claims + returns next ready slice slug
proxy queue next          # peek without claiming
```

**With Tachikoma auto-grab (no slug needed)**:
```bash
tachikoma queue           # auto-grabs via proxy queue grab + drives the loop
```

**Today (manual, until CLI deploys)**:
- Read QUEUE.yaml, eyeball top of active Epic, run `tachikoma queue <slug>` interactively
- Or dispatch via REST: `curl -X POST http://127.0.0.1:4321/api/dispatch -H 'Content-Type: application/json' -d '{"work_request_slug":"<slug>","target_repo":"/Users/pioneer/Projects/tachikoma-starter"}'` then `cd <worktree> && ./.tachikoma/tachikoma.sh --afk 5` (workaround for [dispatch bugs](~/projects/personal-nix/wiki/seeds/fix-tachikoma-dispatch-bugs.md))

## Common workflows

### Convert a grilling session output → Epic

After a grilling session ends with a slice breakdown (typically in an ADR's "Follow-on work" table):

1. Write each slice as a work-request `.md` at `~/projects/personal-nix/wiki/work-requests/<slug>.md`
2. Add an Epic entry to `QUEUE.yaml` listing those slugs in dependency order
3. Position the Epic where you want it in the queue (top = work next)

(A future `/grill-to-epic` skill — see [seed](~/projects/personal-nix/wiki/seeds/grill-to-epic-skill.md) — automates steps 1-3.)

### Ship an entire Epic via parallel Tachikomas

```bash
# Once daemon + CLI are rebuilt:
tachikoma queue &     # T1 grabs slice A
tachikoma queue &     # T2 grabs slice B (if not blocked by A)
tachikoma queue &     # T3 grabs slice C (if ready)
```

All three pull from the current top Epic, respecting `blocked_by`. As each merges, the next ready slice becomes grabable.

### Park an Epic temporarily

```yaml
  - epic: telemetry-v2
    paused: true
    slices: [...]
```

Useful when an Epic is blocked on external work (e.g. compliance, vendor, deciders) — keeps it in the queue without it eating capacity.

### Promote a standalone to its own Epic

Convert:
```yaml
  - standalone: proxy-tui-face-redesign
```
into:
```yaml
  - epic: ui-polish
    title: "UI polish"
    goal: "Tighten TUI + web visual consistency"
    slices:
      - proxy-tui-face-redesign
      - <future-related-slice>
```

## Quirks + gotchas

- **Done slices are NOT in QUEUE.yaml.** They're history. Once a slice transitions to `done` in DB, daemon optionally cleans the entry from QUEUE.yaml; or you delete the row manually.
- **Slices not in QUEUE.yaml are "unqueued"** — they exist as `.md` files but aren't on the priority list. Useful for drafts.
- **Tags / categories**: not in the schema. Use Epic membership for grouping; cross-cuts via `blocked_by` or convention.
- **No sub-Epics yet.** If an Epic grows past ~15 slices, split it into multiple Epics or introduce sub-Epics via ADR amendment.
- **Multi-machine queue editing**: QUEUE.yaml conflicts if edited from two machines simultaneously. Single-user workflow assumed for now.

## Related

- ADR 006 — design rationale + decision matrix
- [`relymd-work-data-pragmatic-compliance`](~/projects/personal-nix/wiki/decisions/relymd-work-data-pragmatic-compliance.md) — example Epic-scope context (email vertical compliance posture)
- [`fix-tachikoma-dispatch-bugs`](~/projects/personal-nix/wiki/seeds/fix-tachikoma-dispatch-bugs.md) — current dispatch friction; rebuild + slice 27 should resolve
- [`grill-to-epic-skill`](~/projects/personal-nix/wiki/seeds/grill-to-epic-skill.md) — future automation for grilling → Epic workflow
