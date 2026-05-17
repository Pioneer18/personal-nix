#!/bin/zsh
# proxy-tui-placeholder.sh — temporary content for the right pane of the
# proxy tmux session. Real Ink TUI lands in M4 (proxy-16-extended).

# Match PATH setup from the launcher
export PATH="/etc/profiles/per-user/$(whoami)/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

clear
cat <<'EOF'

  ╔══════════════════════════════════════════════╗
  ║                                              ║
  ║              PROXY  TUI                      ║
  ║              (placeholder)                   ║
  ║                                              ║
  ║   M4 will replace this pane with the real    ║
  ║   Ink TUI showing:                           ║
  ║                                              ║
  ║      • Queue + work-request status           ║
  ║      • Live sensor metrics                   ║
  ║      • Recommendation inbox                  ║
  ║      • Mode indicator                        ║
  ║                                              ║
  ║   For now this pane drops to a zsh prompt    ║
  ║   so you can run commands while M4 cooks.    ║
  ║                                              ║
  ╚══════════════════════════════════════════════╝

EOF

# Replace this script with a regular login shell so the pane stays useful
exec /bin/zsh -l
