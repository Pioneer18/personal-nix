#!/bin/bash
# Anthropic API status indicator — SwiftBar plugin.
# Shows which account is active for each Claude consumer (PROXY vs PROXY Gmail).
# Shows today's token usage accumulated from tachikoma runs.
# Runs every 10 minutes (interval encoded in filename).

# shellcheck disable=SC1090
source "$HOME/.secrets" 2>/dev/null || true

CO="${ANTHROPIC_KEY_LABEL_COMPANY:-RelyMD}"
ME="${ANTHROPIC_KEY_LABEL_PERSONAL:-Max}"

# Check running tachikoma worktrees for company override.
PROXY_AUTH="$ME"
PROXY_OVERRIDE_SLUGS=()

for pid_file in "$HOME"/Projects/*-tachikoma-*/.tachikoma/run.pid \
                "$HOME"/projects/*-tachikoma-*/.tachikoma/run.pid; do
  [[ -f "$pid_file" ]] || continue
  pid=$(cat "$pid_file" 2>/dev/null) || continue
  kill -0 "$pid" 2>/dev/null || continue
  if ps eww "$pid" 2>/dev/null | grep -q "TACHIKOMA_USE_COMPANY_API=1"; then
    slug=$(basename "$(dirname "$(dirname "$pid_file")")")
    PROXY_OVERRIDE_SLUGS+=("$slug")
    PROXY_AUTH="$CO"
  fi
done

# Token usage from ~/.tachikoma/usage_stats.json
STATS_FILE="$HOME/.tachikoma/usage_stats.json"
TODAY_TOK=""
TODAY_CALLS=""
if [[ -f "$STATS_FILE" ]]; then
  TODAY=$(date +%Y-%m-%d)
  FILE_DATE=$(python3 -c "import json; d=json.load(open('$STATS_FILE')); print(d.get('today_date',''))" 2>/dev/null)
  if [[ "$FILE_DATE" == "$TODAY" ]]; then
    TODAY_IN=$(python3 -c "import json; d=json.load(open('$STATS_FILE')); print(d.get('today_input',0))" 2>/dev/null)
    TODAY_OUT=$(python3 -c "import json; d=json.load(open('$STATS_FILE')); print(d.get('today_output',0))" 2>/dev/null)
    TODAY_CALLS=$(python3 -c "import json; d=json.load(open('$STATS_FILE')); print(d.get('today_calls',0))" 2>/dev/null)
    TOTAL_TOK=$(( ${TODAY_IN:-0} + ${TODAY_OUT:-0} ))
    if (( TOTAL_TOK >= 1000000 )); then
      TODAY_TOK=$(python3 -c "print(f'{${TOTAL_TOK}/1000000:.1f}M')" 2>/dev/null)
    elif (( TOTAL_TOK >= 1000 )); then
      TODAY_TOK=$(python3 -c "print(f'{${TOTAL_TOK}/1000:.0f}K')" 2>/dev/null)
    else
      TODAY_TOK="$TOTAL_TOK"
    fi
  fi
fi

# Determine status color/symbol
if [[ "$PROXY_AUTH" == "$CO" ]]; then
  PROXY_COLOR="red"
  PROXY_SYMBOL="⚠"
else
  PROXY_COLOR="green"
  PROXY_SYMBOL="✓"
fi

# ── Menu bar line ──────────────────────────────────────────────────────────
if [[ -n "$TODAY_TOK" ]]; then
  echo "⚡${PROXY_SYMBOL} ${TODAY_TOK} | size=12"
else
  echo "⚡${PROXY_SYMBOL} | size=12"
fi
echo "---"

# ── Dropdown ───────────────────────────────────────────────────────────────
echo "Anthropic API Status | size=13 color=#888888"
echo "---"
echo "PROXY  →  $PROXY_AUTH | color=$PROXY_COLOR"
if [[ ${#PROXY_OVERRIDE_SLUGS[@]} -gt 0 ]]; then
  for slug in "${PROXY_OVERRIDE_SLUGS[@]}"; do
    echo "  ⚠ $slug using $CO key | color=orange size=11"
  done
fi
echo "PROXY Gmail  →  $CO | color=blue"
echo "---"

# Token usage section
echo "Token Usage (today) | size=12 color=#888888"
if [[ -n "$TODAY_TOK" ]]; then
  echo "  Total: ${TODAY_TOK} tokens  (${TODAY_CALLS} calls) | size=11"
  echo "  In: ${TODAY_IN}  Out: ${TODAY_OUT} | size=11 color=#666666"
else
  echo "  No data yet — runs after first tachikoma iteration | size=11 color=#666666"
fi
echo "---"

echo "Override for a run: | size=11 color=#666666"
echo "  TACHIKOMA_USE_COMPANY_API=1 .tachikoma/tachikoma.sh ... | size=10 color=#888888"
echo "---"
echo "Open Anthropic Console | href=https://console.anthropic.com"
echo "Refresh | refresh=true"
