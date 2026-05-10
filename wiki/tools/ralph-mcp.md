---
title: "ralph-mcp"
summary: "Local MCP server exposing ralph_status and ralph_dispatch for managing Ralph autonomous coding loops"
category: "mcp"
tags: [ralph, mcp, automation, work-queue]
link: "~/projects/personal-nix/mcps/ralph-mcp/index.ts"
last_updated: "2026-05-10"
---

Native MCP server (Node.js + `@modelcontextprotocol/sdk`) that gives Claude first-class tools for the Ralph workflow. Registered user-scope so it's available in every project.

**Tools:**
- `ralph_status` — scans all repos under `~/projects/`, returns structured JSON for every ralph worktree found (status, PID liveness, iter progress, last progress note)
- `ralph_dispatch` — grabs the next `open` work-request from `wiki/work-requests/`, scaffolds a sibling worktree, renders templates from `~/.claude/skills/ralph/`, commits the scaffold, and launches `--afk N` detached

**Source:** `~/projects/personal-nix/mcps/ralph-mcp/index.ts`
**Registration:** `mcp.nix` runs `npm install` + `claude mcp add --scope user ralph` on each `home-manager switch`. Re-register manually with: `claude mcp remove --scope user ralph && claude mcp add --scope user ralph -- node --experimental-strip-types ~/projects/personal-nix/mcps/ralph-mcp/index.ts`
**Update:** edit `index.ts`, then open a new Claude Code session to pick up the change (MCP servers are spawned once per session).
