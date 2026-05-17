#!/usr/bin/env bash
# proxy-boot.sh — fired by LaunchAgent at user login.
#
# Opens Ghostty with the dedicated proxy config (which handles tmux + fullscreen).
# No osascript, no System Events, no keyboard injection — so no Accessibility
# prompt is needed.
#
# The heavy lifting (launching tmux, fullscreening) is done by Ghostty itself,
# driven by ~/.config/ghostty/proxy.config (managed by modules/proxy-boot.nix).

# Brief settle period after login
sleep 2

# Launch Ghostty with the proxy config file. -n forces a new instance so we
# get a fresh window with these settings even if Ghostty was already open.
/usr/bin/open -na Ghostty --args --config-file="$HOME/.config/ghostty/proxy.config"

echo "[$(date '+%Y-%m-%dT%H:%M:%S')] proxy-boot.sh completed"
