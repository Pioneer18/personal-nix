---
title: "Karabiner-Elements config via home-manager"
tags: [karabiner, home-manager, nix, keybindings, recipe]
last_updated: "2026-05-11"
---

# Karabiner-Elements config via home-manager

How Karabiner-Elements is declaratively managed on this Mac. Reference for `shell-06` (Wispr mode chord) and `shell-08` (voice mode cycle), and any future custom chord work.

## Status of nix integration

Karabiner-Elements (the macOS keyboard customization app) is **installed** via the team config (`~/Projects/dev-environment/hosts/jonathan-sells-darwin.nix` → `homebrew.casks = [ "karabiner-elements" ]`).

There is **no `programs.karabiner-elements`** home-manager module. Direct file management via `home.file.".config/karabiner/karabiner.json"` is the convention. Joshua Willey on the RelyMD team already uses this pattern (`~/Projects/dev-environment/users/joshua-willey.nix`).

## Convention for personal-nix

Karabiner config goes in a personal-nix module to keep it isolated from the rest of `default.nix`. Suggested layout:

```
personal-nix/modules/karabiner.nix     # the home.file declaration
personal-nix/modules/karabiner-rules/  # individual rule files
  ├── proxy-voice-chord.nix
  ├── proxy-voice-cycle.nix
  └── (more as added)
```

Each rule file is a Nix attribute (a "complex_modification") that gets merged into `profiles[0].complex_modifications.rules`.

## Single-rule example: ⌘⇧V cycles voice modes

`personal-nix/modules/karabiner-rules/proxy-voice-cycle.nix`:

```nix
{
  description = "PROXY voice mode — ⌘⇧V cycle forward, ⌘⇧⌥V backward";
  enabled = true;
  manipulators = [
    {
      type = "basic";
      from = {
        key_code = "v";
        modifiers = {
          mandatory = [ "left_command" "left_shift" ];
          optional = [ "caps_lock" ];
        };
      };
      to = [
        {
          shell_command = "/usr/local/bin/proxy voice mode cycle";
        }
      ];
    }
    {
      type = "basic";
      from = {
        key_code = "v";
        modifiers = {
          mandatory = [ "left_command" "left_shift" "left_option" ];
          optional = [ "caps_lock" ];
        };
      };
      to = [
        {
          shell_command = "/usr/local/bin/proxy voice mode cycle --backward";
        }
      ];
    }
  ];
}
```

## Aggregator: `personal-nix/modules/karabiner.nix`

```nix
{ config, pkgs, lib, ... }:
let
  proxyVoiceCycle = import ./karabiner-rules/proxy-voice-cycle.nix;
  proxyVoiceChord = import ./karabiner-rules/proxy-voice-chord.nix;
  # Add more rule imports here as you build them

  rules = [
    proxyVoiceCycle
    proxyVoiceChord
    # …
  ];
in {
  home.file.".config/karabiner/karabiner.json" = {
    text = builtins.toJSON {
      title = "Personal";
      profiles = [
        {
          name = "Default";
          selected = true;
          complex_modifications = {
            inherit rules;
          };
          # Keep simple_modifications minimal; chord rules go in complex_modifications
          simple_modifications = [];
        }
      ];
    };
  };
}
```

Enable by adding `./modules/karabiner.nix` to `imports = [ ... ]` in `default.nix`.

## Reload after `dev`

Karabiner watches `~/.config/karabiner/karabiner.json` and reloads automatically on file change. After `dev`:

```bash
# Verify the file content
cat ~/.config/karabiner/karabiner.json | jq '.profiles[0].complex_modifications.rules[] | .description'

# (No manual reload needed; Karabiner picks it up within ~1s)
```

If Karabiner shows a stale config, force a reload via menu bar icon → "Restart Karabiner-Elements".

## Gotchas

- **Karabiner-Elements requires Accessibility + Input Monitoring permissions.** These are GUI-only grants (System Settings → Privacy & Security). First-run wizard (proxy-15b) will walk you through these.
- **`mandatory` vs `optional` modifiers**: `mandatory` modifiers MUST be pressed; `optional` modifiers MAY be pressed (e.g. caps_lock as a typist toggle). Putting only `mandatory` is usually correct for chord rules.
- **Shell commands run in a sanitized PATH.** Use full paths (`/usr/local/bin/proxy` or `${pkgs.proxy}/bin/proxy` if nix-installed). `proxy` not on PATH = silent no-op.
- **JSON validation**: a malformed `karabiner.json` causes Karabiner to refuse the whole config. Validate with `jq . ~/.config/karabiner/karabiner.json` before relying on a `dev` apply.
- **Conflicts with macOS system shortcuts**: e.g. ⌘⇧V is often used for "paste and match formatting". Pick chords that don't collide; check System Settings → Keyboard → Shortcuts.

## See also

- Joshua's example (read-only reference): `~/Projects/dev-environment/users/joshua-willey.nix`
- Karabiner-Elements docs: https://karabiner-elements.pqrs.org/docs/
- Work-requests using this pattern: `shell-06-wispr-mode.md`, `shell-08-off-mode-and-switching.md`
