---
name: reorient
description: Deep top-down review of this Mac's state followed by surgical memory rewrite — prunes deprecated entries, updates shifted facts, adds missing context. Output is a memory layer that makes any cold-start agent (Claude, PROXY, tachikoma) immediately oriented to current reality, not yesterday's snapshot. Triggers — `/reorient`, `/reorient <section>`, "reorient memory", "deep machine review", "refresh my memory", "memory drift check".
---

# Reorient

The agent-side `whoami` for this machine. Reads PROXY sensor history + filesystem state + project state, compares to current memory, and rewrites the memory layer so the next cold-start session is grounded in *now*, not last week.

Intended cadence: weekly manual run + nightly unattended via `/cron` (once `cron-system` ships). Sibling to `memory-tidy` (which focuses on host RSS prunes); reorient focuses on the **memory layer's correctness**, not the machine's RSS.

## Review order (top-down — fixed sections)

| # | Section | Sources | What to inspect |
|---|---|---|---|
| 1 | **Machine** | `proxy sensor latest`; last 24h of `sensor_samples`; `uptime`; recent JetsamEvent files | Pressure trend, swap churn, recent crashes/reboots, OrbStack disk |
| 2 | **PROXY build state** | `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` § 22 (M1-M7); current milestone from queue + `agentic_shell_active_build.md` memory; sensor's running PIDs | Confirm milestone, in-flight slice, sensor active, daemon resident |
| 3 | **Filesystem** | `df -h /`; `~/Projects` + `~/projects` directory listing; OrbStack VM disk; `du -sh ~/Downloads ~/Desktop` if drift suspected | Hygiene drift, stale repos, large unexpected dirs |
| 4 | **Repos** | For each repo in `~/Projects/` and `~/projects/`: branch + ahead/behind master/develop, dirty state, last commit age | Identify dormant/stale repos, surface uncommitted work the user may have forgotten |
| 5 | **Anything else** | Queue state (`proxy queue list`, QUEUE.yaml); seeds/inbox counts in wiki; expiring creds (1Password, GitHub PAT, Anthropic keys via existing memory); login items count | Open work-requests, expiring credentials, drift in any subsystem |

Run sequentially. Each section produces findings before moving to the next.

## Memory update behavior (the surgical part)

After all sections collect findings, walk each existing memory in `~/.claude/projects/-Users-pioneer/memory/` and apply one of:

| Action | When | Behavior |
|---|---|---|
| **Prune** | The memory's referenced thing definitively no longer exists / is no longer true | Delete the `.md` file and its line in `MEMORY.md`. Log to today's reorient-run doc. |
| **Confirm-then-prune** | Memory *seems* deprecated but is ambiguous (e.g. names a file that doesn't exist but might have been renamed) | Queue to the "ambiguous-deletes" list in today's reorient-run doc; ask user during interactive run; **defer to next interactive run** during unattended cron run |
| **Update** | A memory's facts have shifted (dates, paths, statuses, names) — the entry's purpose is still valid, just stale | Rewrite the body in-place; bump any date fields; preserve the `name` slug; refresh `description` if needed; update the `MEMORY.md` one-liner if changed |
| **Add** | Section findings surfaced context that *should* be in memory but isn't (e.g. a new active build, a credential just installed, a behavior pattern observed multiple times) | Write a new memory file in the appropriate type (`user` / `feedback` / `project` / `reference`); add to `MEMORY.md` |
| **Skip** | Memory is still accurate | Do nothing |

Each verdict is logged to the run doc with one-line rationale.

## Run modes

| Form | Behavior |
|---|---|
| `/reorient` | Full pass: sections 1-5 then memory walk. Interactive — `AskUserQuestion` for any ambiguous-delete. |
| `/reorient <section>` | Run just one section + memory entries scoped to that section. `<section>` is `machine` / `proxy` / `filesystem` / `repos` / `other`. |
| `/reorient --unattended` | Cron-mode. Skip all ambiguous-deletes (queue them for next interactive run). No prompts. Idempotent. Used by `cron-system` once shipped. |

## Output — run doc

Every run writes a structured doc at:

```
~/projects/personal-nix/wiki/runbooks/reorient-runs/YYYY-MM-DD.md
```

Frontmatter + body shape:

```markdown
---
date: 2026-05-16
mode: interactive | unattended
duration_sec: 47
---

# Reorient — 2026-05-16

## Section findings

### Machine
<bullet list of observed state + any drift from prior run>

### PROXY
...

## Memory diff

### Pruned (N)
- `<slug>` — <reason>

### Updated (N)
- `<slug>` — <what changed>

### Added (N)
- `<slug>` — <why added>

### Ambiguous (deferred to next interactive run)
- `<slug>` — <ambiguity>
```

This doc is the diff/preview surface — user reads it the next day to catch unexpected changes. Append-only (one file per run).

## Hard rules

- **MEMORY.md and CLAUDE.md are touched conservatively.** The default scope is the contents of `~/.claude/projects/-Users-pioneer/memory/*.md` + `MEMORY.md` index. CLAUDE.md (global instructions) is only touched if the user explicitly approves in the run.
- **Ambiguous deletes never fire unattended.** If a memory seems deprecated but it's not certain, queue it; let the user decide on the next interactive run.
- **One run doc per day.** If a second run happens same day, append a new H1-level "Run 2" section to the same file rather than overwriting.
- **No commits.** Skill writes files; commit timing is the user's call.
- **Memory's body structure preserved.** When updating a `feedback` or `project` memory, preserve the `**Why:**` + `**How to apply:**` lines per the auto-memory convention. Don't reformat for no reason.

## Edge cases

- **proxy-daemon not running** — Section 1 falls back to `vm_stat` + `memory_pressure` (note the limitation in the run doc; the calibration drift means the snapshot is rougher).
- **PROXY sensor table empty** — note in run doc; rely on snapshot only.
- **Memory references a file/path that exists on a different machine** — don't prune; the user may have multi-Mac state. Flag as "machine-specific" if not obvious.
- **More than 5 prunes in one pass** — pause and surface the list as a single confirmation prompt (interactive mode) or limit to top 5 (unattended); aggressive memory reduction should be a user-explicit decision.
- **Run during system pressure (RED)** — refuse and surface why; the inventory passes would compete for cycles. Suggest user run `/memory-tidy` first.

## See also

- `~/.claude/skills/memory-tidy/SKILL.md` — sibling skill for RSS-side hygiene
- `~/.claude/skills/orient-to-machine/SKILL.md` — read-only orientation (no memory writes); use as the input source for some sections
- `~/projects/personal-nix/wiki/work-requests/cron-system.md` — the scheduler that will run `/reorient --unattended` once shipped
- `~/.claude/CLAUDE.md` § auto memory — the memory schema this skill respects
- `~/.claude/projects/-Users-pioneer/memory/MEMORY.md` — the index this skill maintains
