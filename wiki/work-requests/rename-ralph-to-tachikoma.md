---
status: grabbed
target_repo: ~/projects/personal-nix
last_updated: 2026-05-10
---

# Rename Ralph to Tachikoma

Rebrand the ralph autonomous-coding-loop skill, its MCP server, wiki entries, and nix config throughout personal-nix to use the name "Tachikoma" (the AI spider-tank from Ghost in the Shell).

## Goal

Tachikoma is done when every occurrence of "ralph"/"Ralph" in `skills/`, `mcps/`, `wiki/tools/`, `wiki/INDEX.md`, and `mcp.nix` has been replaced with "tachikoma"/"Tachikoma", the `skills/ralph/` and `mcps/ralph-mcp/` directories have been renamed to `skills/tachikoma/` and `mcps/tachikoma-mcp/`, and `grep -ri 'ralph' skills/ mcps/ wiki/tools/ wiki/INDEX.md mcp.nix` returns no matches.

## Files in scope

```
skills/ralph/**
mcps/ralph-mcp/index.ts
mcps/ralph-mcp/package.json
wiki/tools/ralph.md
wiki/tools/ralph-mcp.md
wiki/INDEX.md
mcp.nix
skills/work-queue/SKILL.md
skills/wiki/SKILL.md
skills/wiki/README.md
```

## Files out of scope

```
wiki/work-requests/**           # historical records — leave filenames/content as-is
mcps/ralph-mcp/node_modules/
mcps/ralph-mcp/package-lock.json   # auto-regenerated via npm install after rename
~/.claude/skills/ralph             # symlink lives outside the repo — update manually after merge
```

## Stop condition

- [ ] `grep -ri 'ralph' skills/ mcps/ wiki/tools/ wiki/INDEX.md mcp.nix` returns no matches
- [ ] `skills/tachikoma/` exists with all files from `skills/ralph/`
- [ ] `mcps/tachikoma-mcp/` exists with all files from `mcps/ralph-mcp/` (minus node_modules)
- [ ] `wiki/tools/tachikoma.md` and `wiki/tools/tachikoma-mcp.md` exist
- [ ] `mcp.nix` references `tachikoma-mcp`, not `ralph-mcp`
- [ ] `mcps/tachikoma-mcp/package.json` has `name: "tachikoma-mcp"`

## Feedback loops

```bash
# Primary: verify no remaining ralph references
grep -ri 'ralph' skills/ mcps/ wiki/tools/ wiki/INDEX.md mcp.nix

# Secondary: verify MCP package installs cleanly after rename
cd mcps/tachikoma-mcp && npm install
```

## Quality bar

production
