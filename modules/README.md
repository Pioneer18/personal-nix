# personal-nix modules/

Pulled-out home-manager modules for things bigger than a few lines that don't belong inline in `default.nix`. Each file declares one feature; you opt-in by adding `./modules/<name>.nix` to the `imports = [ ... ]` list in `default.nix`.

## Modules

| Module | Status | Description |
|---|---|---|
| `proxy-boot.nix` | **DRAFT** (not yet imported) | LaunchAgent that opens fullscreen Ghostty with the "proxy" tmux session at user login. M1 / shell-01 of the agentic shell v1.0 plan. |
| `memory-prune.nix` | **READY** (opt-in) | Weekly LaunchAgent that runs `scripts/prune-memory.sh` — claude-driven auto-curator for `~/.claude/projects/-Users-pioneer/memory/`. Sunday 03:00 local. |

## Enabling a module

```nix
# In default.nix:
imports = [
  ./packages.nix
  ./mcp.nix
  ./modules/proxy-boot.nix     # optional
  ./modules/memory-prune.nix   # optional
];
```

Then `dev` to rebuild.

## Disabling

Remove the import line; rebuild. The LaunchAgent will be unloaded on next rebuild.

## Adding a new module

1. Create `modules/<name>.nix` with `{ config, pkgs, lib, ... }: { ... }` shape
2. Document it in this README
3. Import it in `default.nix` when ready

---

## `memory-prune.nix` — claude-driven memory auto-curator

A weekly LaunchAgent that asks claude to review every file in `~/.claude/projects/-Users-pioneer/memory/`, writes a categorized report, auto-archives entries with explicitly-expired frontmatter, and surfaces other archive candidates via a macOS notification.

### What it does

On its schedule (Sunday 03:00 by default), the agent fires `scripts/prune-memory.sh`, which:

1. Builds a prompt by concatenating `scripts/prune-memory-prompt.md` with the current `MEMORY.md` index and every memory file's contents.
2. Pipes the prompt to `claude -p --output-format text`.
3. Saves the response to `~/.claude/projects/-Users-pioneer/memory/.prune-reports/YYYY-MM-DD.md`.
4. Parses the `<!-- machine-readable --> ... <!-- /machine-readable -->` JSON block inside the report. Each entry is categorized:
   - `KEEP` — still load-bearing
   - `CONSOLIDATE` — merge into another memory (rationale names the target)
   - `ARCHIVE-RECOMMEND` — surface to user for manual review
   - `ARCHIVE-AUTO` — has explicit `expires: YYYY-MM-DD` frontmatter, past
5. For every `ARCHIVE-AUTO`, the script independently re-verifies the file's `expires:` frontmatter (defense-in-depth on top of claude's judgment) before moving it to `~/.claude/projects/-Users-pioneer/memory/.archive/YYYY-MM-DD/` and stripping its index entry from `MEMORY.md`.
6. If any `ARCHIVE-RECOMMEND` entries exist, fires a macOS notification ("N memory entries suggested for archive — see /…/<date>.md") so the user can review at their next idle moment.

### Enabling

Add to `default.nix` imports:

```nix
imports = [
  ./packages.nix
  ./mcp.nix
  ./modules/memory-prune.nix
];
```

Then run `dev`. Verify the agent loaded:

```sh
launchctl list | grep memory-prune
```

### Changing the schedule

Edit the `StartCalendarInterval` block in `modules/memory-prune.nix`. Apple's launchd accepts `Minute`, `Hour`, `Day`, `Weekday` (0 = Sunday), and `Month`. To run daily at 04:00:

```nix
StartCalendarInterval = [{
  Hour = 4;
  Minute = 0;
}];
```

### Manual invocations

```sh
# Fire it now (useful for testing after a config change):
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.memory-prune"

# Or run the script directly without launchd:
~/projects/personal-nix/scripts/prune-memory.sh

# Dry-run — produces the report but does NOT move any files:
~/projects/personal-nix/scripts/prune-memory.sh --dry-run

# Self-test — runs built-in unit tests for the helpers, no API call:
~/projects/personal-nix/scripts/prune-memory.sh --self-test
```

### Adding an expiry to a memory

To opt a memory into automatic archival on a given date, add `expires: YYYY-MM-DD` to its YAML frontmatter:

```yaml
---
name: q1-2026-incident-followup
description: post-incident TODOs from the Jan auth outage
metadata:
  type: project
expires: 2026-06-01
---
```

After the expiry passes, the next prune run will move the file into `.archive/<date>/` and remove the line from `MEMORY.md`.

### Recovering an archived entry

Auto-archive is reversible. To restore a single file:

```sh
mv ~/.claude/projects/-Users-pioneer/memory/.archive/<date>/<file> \
   ~/.claude/projects/-Users-pioneer/memory/<file>
```

Then re-add its one-line entry to `MEMORY.md`. The archived file is byte-for-byte identical to the original.

### Idempotency

Re-running on the same memory state produces no new archives — the script only touches files that are still present in the live directory. The archive directory for a given day is removed if no files actually landed in it.

### Logs

- LaunchAgent stdout/stderr: `/tmp/memory-prune.log`
- Per-run report: `~/.claude/projects/-Users-pioneer/memory/.prune-reports/YYYY-MM-DD.md`

### Requirements

- `claude` CLI on PATH (the LaunchAgent's `EnvironmentVariables.PATH` includes `~/.local/bin` and the nix profile paths)
- `jq` (provided by the team nix profile)
- Working `claude -p` auth (anthropic API key or claude.ai login)
