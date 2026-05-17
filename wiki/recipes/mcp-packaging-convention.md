---
title: "MCP server packaging convention"
tags: [mcp, packaging, nix, claude-code, recipe]
last_updated: "2026-05-11"
---

# MCP server packaging convention

How custom MCP (Model Context Protocol) servers are packaged and registered in this `personal-nix` setup. Reference for building new MCPs (e.g. `shell-10-shortcuts-mcp` in the agentic-shell plan) and for any contributor following the existing pattern (`tachikoma-mcp`, `tachikoma-ui`).

## Two flavors

| Flavor | When | Mechanism |
|---|---|---|
| **npm-published** | The MCP exists on npm (e.g. `@modelcontextprotocol/server-filesystem`, `@peakmojo/applescript-mcp`) | One-liner: `register_mcp <name> -- npx -y <package>` |
| **Local TypeScript** | Custom MCP written from scratch, lives in `personal-nix/mcps/<name>/` | Build at activation; register as `node --experimental-strip-types <path>/index.ts` |

This recipe covers the **local** flavor. The npm flavor is trivial — just add a `register_mcp` line in `mcp.nix`.

## Directory layout

```
personal-nix/mcps/<name>/
├── package.json           # deps (typically @modelcontextprotocol/sdk + ts-node or just node 22+)
├── tsconfig.json          # optional; --experimental-strip-types lets you skip
├── index.ts               # MCP server entry point (or src/index.ts)
├── README.md              # what the MCP does + tool list
└── (node_modules/)        # populated by activation, gitignored
```

**No build step required** if Node 22+ + `--experimental-strip-types` is available (default on this machine via `nodejs_22` in the team config).

For more complex MCPs (e.g. needing real compilation): add `tsconfig.json` + `dist/` + a `build` script in `package.json`, then run `npm run build` in the activation.

## `index.ts` skeleton

```typescript
#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const server = new Server(
  { name: "<name>-mcp", version: "0.1.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "tool_name",
      description: "What it does",
      inputSchema: {
        type: "object",
        properties: { /* ... */ },
        required: [],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args } = req.params;
  switch (name) {
    case "tool_name": {
      // do the work
      return {
        content: [{ type: "text", text: "result" }],
      };
    }
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
```

## `package.json`

```json
{
  "name": "<name>-mcp",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0"
  },
  "engines": {
    "node": ">=22"
  }
}
```

## Wiring into `mcp.nix`

In `mcp.nix`'s `home.activation.registerMCPServers` shell block:

```nix
# <Name> MCP — <one-line purpose>
NAME_MCP_DIR="$HOME/projects/personal-nix/mcps/<name>"
if [ -d "$NAME_MCP_DIR" ]; then
  (cd "$NAME_MCP_DIR" && npm install --quiet 2>/dev/null) || true
  register_mcp <name> -- \
    node --experimental-strip-types "$NAME_MCP_DIR/index.ts"
else
  echo "personal-nix: <name>-mcp dir not found, skipping"
fi
```

Conventions:
- `npm install` failure is non-fatal — log + skip (activation should never block `dev`).
- Use `register_mcp` helper (defined in `mcp.nix`) — handles idempotent remove-then-add.
- Always log success/failure so the user can debug from terminal.

## Secrets / env vars

If the MCP needs an API key:

1. Add the key to Keychain: `security add-generic-password -A -U -s <KEY_NAME> -a "$USER" -w '<value>'`
2. Update `scripts/secrets-from-keychain.sh` to add a `read_keychain` line for `<KEY_NAME>`
3. In `mcp.nix`, pass via `-e`:

```nix
if [ -n "''${MY_API_KEY:-}" ]; then
  register_mcp <name> \
    -e "MY_API_KEY=$MY_API_KEY" \
    -- node --experimental-strip-types "$NAME_MCP_DIR/index.ts"
fi
```

The `-e` flag embeds the env var into `~/.claude.json` so Claude Code passes it when spawning the server. **Required** — without it, Claude Code's MCP spawn context may not see your interactive shell's exports.

## Activation timing

The MCP registration runs at `home.activation.registerMCPServers` time. Ordering matters:

```nix
home.activation.registerMCPServers =
  lib.hm.dag.entryAfter [ "writeBoundary" "secretsFromKeychain" ] ''
    ...
  '';
```

Why after `secretsFromKeychain`: secrets must be written to `~/.secrets` before we can source them for `-e` flag values.

## Verification

After `dev`:

```bash
claude mcp list                    # should show your new MCP
claude mcp logs <name>             # see startup output
```

In a **fresh** claude session (existing sessions cache MCP state — restart needed):

```bash
claude
# In the session, the new MCP's tools should appear in the tool list
```

## Common gotchas

- **MCP changes require a fresh Claude Code session.** `claude mcp add` updates `~/.claude.json` but running sessions don't reload. Quit + relaunch claude.
- **PATH inside activation scripts is sanitized.** Use full paths (`/usr/bin/security` etc.) for system binaries. `node` is added explicitly via `export PATH="$HOME/.local/bin:${pkgs.nodejs_22}/bin:$PATH"` at top of the activation.
- **`--experimental-strip-types` is Node 22+.** Older Node won't work; ensure `nodejs_22` is in the team config (it is on this machine).
- **Idempotency**: `register_mcp` does `claude mcp remove` first, so re-running `dev` is safe.

## Examples in this repo

| MCP | Path | Pattern |
|---|---|---|
| `tachikoma-mcp` | `mcps/tachikoma-mcp/index.ts` | Local TS, no `src/` subdir |
| `tachikoma-ui` | `mcps/tachikoma-ui/server/index.ts` | Local TS, has separate frontend + server dirs, dual purpose (Web UI + MCP server) |
| (new) `shortcuts-mcp` | `mcps/shortcuts-mcp/index.ts` (planned shell-10) | Local TS, wraps `shortcuts run` CLI |

## See also

- `mcp.nix` — the actual registration logic
- `default.nix` — the `home.activation.buildTachikomaUI` activation pattern for MCPs with a build step
- [Anthropic MCP docs](https://modelcontextprotocol.io)
- Work-request: `wiki/work-requests/shell-10-shortcuts-mcp.md`
