#!/bin/bash
# proxy-system.30s.sh — SwiftBar plugin showing PROXY system pressure.
# Refreshes every 30s. Header is one-line glance; dropdown has full detail.

# Source secrets / PATH so we can find proxy-daemon + proxy-sys
# shellcheck disable=SC1090
source "$HOME/.secrets" 2>/dev/null || true
export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

if ! command -v proxy-sys >/dev/null 2>&1; then
  echo "⚡? | size=12 color=gray"
  echo "---"
  echo "proxy-sys not on PATH"
  exit 0
fi

JSON="$(proxy-sys --json 2>/dev/null)"
if [ -z "$JSON" ]; then
  echo "⚡? | size=12 color=gray"
  echo "---"
  echo "proxy-daemon sensor unavailable"
  echo "Start daemon | bash='launchctl' param1='kickstart' param2='-k' param3=\"gui/$(id -u)/com.proxy.daemon\" terminal=false"
  exit 0
fi

# Parse JSON fields
read -r PRESSURE AVAIL_MB USED_MB SWAP_USED SWAP_FREE SWAP_TOTAL SWAP_RATE LOAD1 LOAD5 LOAD15 DOCKER WARNINGS <<EOF
$(printf '%s' "$JSON" | python3 -c "
import json,sys
d = json.load(sys.stdin)
print(d['pressure'], d['avail_mb'], d['used_mb'],
      d['swap_used_mb'], d['swap_free_mb'], d['swap_total_mb'],
      d['swap_rate_mbps'],
      d['load1'], d['load5'], d['load15'],
      d['docker_n'],
      ','.join(d['warnings']) if d['warnings'] else '-')
")
EOF

# Map pressure -> color + glyph
case "$PRESSURE" in
  normal)
    if [ "$WARNINGS" = "-" ]; then
      GLYPH="✓"
      COLOR="green"
    else
      GLYPH="⚠"
      COLOR="#B22222"
    fi
    ;;
  warn)
    GLYPH="⚠"
    COLOR="#B22222"
    ;;
  critical)
    GLYPH="✗"
    COLOR="red"
    ;;
  *)
    GLYPH="?"
    COLOR="gray"
    ;;
esac

SWAP_USED_GB=$(echo "scale=1; $SWAP_USED / 1024" | bc)
SWAP_FREE_GB=$(echo "scale=1; $SWAP_FREE / 1024" | bc)
SWAP_TOTAL_GB=$(echo "scale=1; $SWAP_TOTAL / 1024" | bc)

# ── Header line ────────────────────────────────────────────────────────────
HEADER="${GLYPH} ${AVAIL_MB}M / sw ${SWAP_USED_GB}G"
echo "${HEADER} | size=11 color=${COLOR} font=Menlo"

echo "---"

# ── Dropdown ───────────────────────────────────────────────────────────────
echo "PROXY System Pressure | size=13 color=#888888"
echo "---"
echo "Pressure: ${PRESSURE} | color=${COLOR} font=Menlo"

if [ "$WARNINGS" != "-" ]; then
  echo "Flags: ${WARNINGS} | color=#B22222 font=Menlo size=11"
fi

echo "---"
echo "Memory | size=11 color=#888888"
echo "  avail: ${AVAIL_MB} MB | font=Menlo size=12"
echo "  used:  ${USED_MB} MB / 24576 MB | font=Menlo size=12"
echo "---"
echo "Swap | size=11 color=#888888"
echo "  used:  ${SWAP_USED_GB} GB | font=Menlo size=12"
echo "  free:  ${SWAP_FREE_GB} GB | font=Menlo size=12"
echo "  total: ${SWAP_TOTAL_GB} GB | font=Menlo size=12"
echo "  rate:  ${SWAP_RATE} MB/s | font=Menlo size=12"
echo "---"
echo "Load (1/5/15) | size=11 color=#888888"
echo "  $(printf '%.2f / %.2f / %.2f' "$LOAD1" "$LOAD5" "$LOAD15") | font=Menlo size=12"
echo "---"
echo "Open Activity Monitor | bash='/usr/bin/open' param1='-a' param2='Activity Monitor' terminal=false"
echo "Run /memory-tidy | size=11 color=#666666"
echo "Refresh | refresh=true"
