---
title: "tachikoma-mcp"
summary: "Local MCP server exposing tachikoma_status and tachikoma_dispatch for managing Tachikoma autonomous coding loops"
category: "mcp"
tags: [tachikoma, mcp, automation, work-queue]
link: "~/projects/personal-nix/mcps/tachikoma-mcp/index.ts"
last_updated: "2026-05-10"
---

Native MCP server (Node.js + `@modelcontextprotocol/sdk`) that gives Claude first-class tools for the Tachikoma workflow. Registered user-scope so it's available in every project.

**Tools:**
- `tachikoma_status` — scans all repos under `~/projects/`, returns structured JSON for every tachikoma worktree found (status, PID liveness, iter progress, last progress note)
- `tachikoma_dispatch` — grabs the next `open` work-request from `wiki/work-requests/`, scaffolds a sibling worktree, renders templates from `~/.claude/skills/tachikoma/`, commits the scaffold, and launches `--afk N` detached

**Source:** `~/projects/personal-nix/mcps/tachikoma-mcp/index.ts`
**Registration:** `mcp.nix` runs `npm install` + `claude mcp add --scope user tachikoma` on each `home-manager switch`. Re-register manually with: `claude mcp remove --scope user tachikoma && claude mcp add --scope user tachikoma -- node --experimental-strip-types ~/projects/personal-nix/mcps/tachikoma-mcp/index.ts`
**Update:** edit `index.ts`, then open a new Claude Code session to pick up the change (MCP servers are spawned once per session).
