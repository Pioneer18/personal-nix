# shortcuts-mcp

MCP server wrapping macOS Shortcuts.app. Exposes every installed Shortcut as a callable tool that claude can invoke directly.

## Tools

| Tool | Purpose |
|---|---|
| `list` | Enumerate every Shortcut installed on this Mac. Returns `{ count, shortcuts: [name, …] }`. |
| `run` | Execute a Shortcut by exact name. Optional `input` parameter is piped via stdin for Shortcuts that accept input. |

## How it gets registered

Built + registered automatically via `personal-nix/mcp.nix` on every `dev`. After `dev`, MCP changes need a fresh `claude` session to pick up (existing sessions cache the MCP catalog).

## Building Shortcuts to expose

You build Shortcuts in the macOS Shortcuts.app (GUI, no code). Anything callable via `shortcuts run "<name>"` is automatically callable by claude through this MCP — no per-Shortcut wrapper code needed.

Examples of useful Shortcuts to build:
- HomeKit actions ("Toggle desk light", "Set scene: focus")
- Photos queries ("Recent screenshots", "Photos from yesterday")
- Reading list management ("Save current Safari tab")
- Custom workflows that compose share-sheet targets
- Anything you regularly do in the Shortcuts GUI

## Verifying

```bash
# After `dev`, in a fresh claude session:
claude mcp list                   # should show 'shortcuts' connected
# Or via the CLI directly:
shortcuts list | head             # baseline — what claude sees via `list`
shortcuts run "<your shortcut>"   # baseline — what claude does via `run`
```

## Future

- Pull richer metadata (Shortcut descriptions, input/output types) when macOS exposes them via the CLI
- Per-Shortcut tool registration (one MCP tool per Shortcut name) instead of generic `list` + `run` — would give claude more discoverable surface area but requires regenerating tool list on Shortcut add/remove
