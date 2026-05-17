# personal-nix modules/

Pulled-out home-manager modules for things bigger than a few lines that don't belong inline in `default.nix`. Each file declares one feature; you opt-in by adding `./modules/<name>.nix` to the `imports = [ ... ]` list in `default.nix`.

## Modules

| Module | Status | Description |
|---|---|---|
| `proxy-boot.nix` | **DRAFT** (not yet imported) | LaunchAgent that opens fullscreen Ghostty with the "proxy" tmux session at user login. M1 / shell-01 of the agentic shell v1.0 plan. |

## Enabling a module

```nix
# In default.nix:
imports = [
  ./packages.nix
  ./mcp.nix
  ./modules/proxy-boot.nix   # <-- add this line
];
```

Then `dev` to rebuild.

## Disabling

Remove the import line; rebuild. The LaunchAgent will be unloaded on next rebuild.

## Adding a new module

1. Create `modules/<name>.nix` with `{ config, pkgs, lib, ... }: { ... }` shape
2. Document it in this README
3. Import it in `default.nix` when ready
