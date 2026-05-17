#!/bin/zsh
# proxy-tmux-launcher.sh — invoked by Ghostty (via `command =` in proxy.config)
# when the proxy window opens.
#
# Idempotent session setup:
#   - If no proxy session: create it with two panes (claude + placeholder TUI).
#   - If session exists with only 1 pane: add the missing TUI pane.
#   - If session exists with 2 panes: just attach as-is.

# Ensure nix-darwin per-user profile and system paths are on PATH so tmux + claude are findable
export PATH="/etc/profiles/per-user/$(whoami)/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

TUI_CMD="cd $HOME/Projects/tachikoma-starter/apps/tui && npm start"

# Create session if missing
if ! tmux has-session -t proxy 2>/dev/null; then
  # Detached new session; pane 0 will host claude
  tmux new-session -d -s proxy -n main
  # Run claude in the left pane via send-keys (so when claude exits,
  # the user lands at a zsh prompt rather than the pane closing).
  tmux send-keys -t 'proxy:main.0' "claude" Enter
fi

# Ensure the right pane (placeholder TUI) exists; idempotent
panes=$(tmux list-panes -t 'proxy:main' 2>/dev/null | wc -l | tr -d ' ')
if [ "$panes" = "1" ]; then
  tmux split-window -h -t 'proxy:main' "$TUI_CMD"
fi

# Always focus the chat (left) pane
tmux select-pane -t 'proxy:main.0'

# Attach
exec tmux attach -t proxy
