---
title: "Declarative Chrome workspaces via Nix"
tags: [chrome, nix, workspace, memory, launcher]
last_updated: "2026-05-11"
---

# Declarative Chrome workspaces via Nix

A small Nix module + shell function pattern for **fearless Chrome closing**. Lets you quit Chrome any time without dread because your workspaces are declared and one command reopens any of them. Pairs with Chrome's built-in Memory Saver mode to keep idle tabs cheap.

**Why this exists**: Chrome on a busy dev Mac is the single biggest non-essential RAM consumer (commonly 3+ GB across renderers). The hygiene guide [`mac-hygiene-guide.md`](../runbooks/mac-hygiene-guide.md) § 3.3 calls it out by name. The PROXY v2 redesign session (2026-05-11) surfaced the pattern: "store Chrome state in Nix" is the wrong framing because Chrome already persists tabs; the right framing is **declarative workspace bundles** that you launch with one command, combined with Chrome Memory Saver discarding inactive tabs.

## The pattern

```nix
# ~/projects/personal-nix/chrome-workspaces.nix
{ config, pkgs, lib, ... }:

let
  chromeBin = "/Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome";

  # Declare your workspaces here. Each is a name → list of URLs.
  workspaces = {
    work = [
      "https://github.com/MioMarker/major"
      "https://github.com/MioMarker/healthbite"
      "https://supabase.com/dashboard/project/nuihvxluxdpdjgkvtdih"
      "https://app.linear.app/relymd"
    ];
    notes = [
      "https://www.notion.so/"
    ];
    triage = [
      "https://github.com/MioMarker/major/issues"
      "https://github.com/MioMarker/tachikoma-starter/issues"
    ];
    healix = [
      "https://github.com/MioMarker/healix"
    ];
    # Add more as you discover patterns
  };

  # Generate a shell function that takes a workspace name and opens those URLs
  workspaceScript = pkgs.writeShellScriptBin "workspace" ''
    set -euo pipefail
    name="''${1:-}"
    if [[ -z "$name" ]]; then
      echo "Usage: workspace <name>"
      echo "Available:"
      ${lib.concatMapStringsSep "\n" (n: "  echo '  - ${n}'") (lib.attrNames workspaces)}
      exit 1
    fi
    case "$name" in
      ${lib.concatMapStringsSep "\n      " (n:
        ''${n}) ${chromeBin} --new-window ${lib.concatStringsSep " " (map (u: "\"${u}\"") workspaces.${n})} ;;''
      ) (lib.attrNames workspaces)}
      *)
        echo "Unknown workspace: $name"
        exit 1
        ;;
    esac
  '';
in
{
  home.packages = [ workspaceScript ];
}
```

Add this module to your `personal-nix/default.nix` imports, run `dev`, and now you have:

```bash
workspace          # lists available workspaces
workspace work     # opens a new Chrome window with the 4 work URLs
workspace notes    # opens Notion
workspace triage   # opens issue trackers
```

## Pairs with Chrome Memory Saver

The Nix module gives you fast reopen. **Chrome Memory Saver** keeps the reopened tabs cheap when idle:

1. `chrome://settings/performance` → Memory Saver **On**
2. Mode: **Maximum memory savings**
3. Optional: add specific URLs to "Always keep these sites active" for the 2-3 tabs you really need warm

Tabs not touched for ~2 hours discard their renderer; reload on click (typically 1-2s). Per the prep recipe [`mac-pre-proxy-prep.md`](mac-pre-proxy-prep.md) Step 5, this cuts Chrome's footprint by 60-80% for tab-hoarders.

## Why this beats Chrome's native "restore previous session"

Chrome's native restore opens **every** tab from your last session — including the 47 tabs you accumulated last Tuesday that you forgot about. Workspaces are **curated by intent**: this is the work workspace, this is the notes workspace. Closing Chrome is now a deliberate context-switch, not a fear of loss.

It also separates concerns across Chrome profiles cleanly if you use them — adapt the `chromeBin` path or add a `--profile-directory` flag per workspace.

## Extending

- **Per-machine workspaces**: declare the workspace map in the machine's host file (e.g. `hosts/jonathan-sells-darwin.nix`) and import the shared script from `personal-nix/`. Different machines, different workspaces.
- **Workspaces in Brave / Arc / Firefox**: same pattern, swap `chromeBin` for the right executable path. Arc has its own "Spaces" feature that may be redundant; Brave/Firefox use Chrome's `--new-window URL ...` semantics.
- **Per-workspace Chrome profile**: append `--profile-directory="Profile 1"` etc. to isolate cookies/extensions per workspace.
- **From the PROXY UI**: future enhancement — when PROXY's system manager recommends "close Chrome", offer a one-click "reopen the workspace I had" after the close. Requires capturing the last-active workspace name in a state file.

## Files

When implemented:
- `~/projects/personal-nix/chrome-workspaces.nix` — the module
- `~/projects/personal-nix/default.nix` — add `./chrome-workspaces.nix` to imports
- Run `dev` to apply

## See also

- [`mac-pre-proxy-prep.md`](mac-pre-proxy-prep.md) — Step 5 (Chrome Memory Saver)
- [`../runbooks/mac-hygiene-guide.md`](../runbooks/mac-hygiene-guide.md) § 3.3 — top memory offenders
- [`~/Projects/tachikoma-starter/docs/ARCHITECTURE.md`](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) § 8 — PROXY's system manager and Chrome-close recommendation flow
