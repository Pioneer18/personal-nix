---
title: Ghostty macOS CLI Launch
tags: [ghostty, proxy-shell, boot]
---

# Ghostty macOS CLI Launch

## Symptom

Running `ghostty --fullscreen -e <cmd>` or invoking the binary directly at
`/Applications/Ghostty.app/Contents/MacOS/ghostty` fails with:

```
Ghostty failed to launch the requested command:
/usr/bin/login -flp pioneer <cmd>
```

Ghostty on macOS wraps any `-e`/direct command via `/usr/bin/login -flp <user> <cmd>`,
treating the entire string as a single filename. Multi-word commands always fail this way.

## Fix

Use `--config-file=` with a Ghostty config that sets `command = /path/to/script`.
This is the only reliable pattern on macOS — Ghostty wraps ANY command (whether via
`-e` or `--command=` CLI override) in `/usr/bin/login -flp <user> <cmd>`. Multi-word
commands always fail because login treats the string as a single filename.

By pointing at a config file, you put the `command =` value in a file (no quoting
issues) and keep the wrapper script path a single clean token.

```bash
# Correct: use a config file
/usr/bin/open -na Ghostty --args --config-file="$HOME/.config/ghostty/proxy.config"
```

The config file sets:
```
command = /path/to/launcher-script.sh
```

The launcher script must be a single executable path (no spaces). It can then exec
multi-word commands internally since it runs as a proper shell script.

## proxy-shell implementation

`~/.local/bin/proxy-shell` opens fullscreen Ghostty attached to the proxy tmux session:

```bash
#!/bin/bash
/usr/bin/open -na Ghostty --args --config-file="$HOME/.config/ghostty/proxy.config"
```

`~/.config/ghostty/proxy.config` (managed by `modules/proxy-boot.nix`):
```
command = /Users/pioneer/projects/personal-nix/scripts/proxy-tmux-launcher.sh
fullscreen = true
macos-non-native-fullscreen = visible-menu
confirm-close-surface = false
```

`proxy-tmux-launcher.sh` sets PATH, creates the proxy tmux session if missing, then
does `exec tmux attach -t proxy`.

Source: `~/projects/personal-nix/default.nix` → `home.activation.writeProxyShellScript`
Boot LaunchAgent (`modules/proxy-boot.nix`) uses the same pattern — that's how it was
discovered to be the right approach.

## Why `--command=` CLI override also fails

Even via `open -na Ghostty --args --command=/path/to/script`, Ghostty STILL wraps
the value in `/usr/bin/login -flp pioneer <command>`. If that script then execs a
multi-word command, Ghostty's error reporter shows the exec'd command (with spaces)
as the "failed command", making it look like `--command=` never used the wrapper at all.
The config-file approach avoids this entirely.
