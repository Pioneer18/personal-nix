#!/usr/bin/env bash
# Tachikoma — autonomous coding loop
# Slug: tachikoma-ui-nix-service | Mode: once | Quality: prototype

set -euo pipefail

WORKTREE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$WORKTREE/.tachikoma"
PID_FILE="$STATE_DIR/run.pid"
OUTCOME_FILE="$STATE_DIR/outcome"
LOG_FILE="$STATE_DIR/run.log"

echo $$ > "$PID_FILE"

cleanup() { rm -f "$PID_FILE"; }
trap cleanup EXIT

log() { echo "[tachikoma] $*" | tee -a "$LOG_FILE"; }

log "────────────────────────────────────────"
log "  Tachikoma — tachikoma-ui-nix-service"
log "  mode: once | quality: prototype"
log "────────────────────────────────────────"

ALLOWED_TOOLS="Edit Write Read Glob Grep Bash(git *) Bash(gh *) Bash(nix *) Bash(npm *) Bash(npx *) Bash(node *) Bash(find *) Bash(cat *) Bash(echo *) Bash(ls *) Bash(mkdir *) Bash(cp *) Bash(mv *) Bash(rm *) Bash(touch *) Bash(chmod *) Bash(cd *)"

cd "$WORKTREE"

log "Iteration 1/1 …"

OUTPUT=$(claude -p "$(cat "$STATE_DIR/prompt.md")" \
  --allowedTools $ALLOWED_TOOLS \
  --output-format text \
  2>>"$LOG_FILE" || true)

echo "$OUTPUT" >> "$LOG_FILE"

if echo "$OUTPUT" | grep -q '<promise>COMPLETE</promise>'; then
  log "Sentinel detected — running ship phase"
  echo "complete" > "$OUTCOME_FILE"

  SHIP_OUTPUT=$(claude -p "$(cat "$STATE_DIR/ship.md")" \
    --allowedTools $ALLOWED_TOOLS \
    --output-format text \
    2>>"$LOG_FILE" || true)
  echo "$SHIP_OUTPUT" >> "$LOG_FILE"
  log "Ship phase complete"
else
  log "No sentinel — cap reached, outcome: cap"
  echo "cap" > "$OUTCOME_FILE"
fi

log "Done."
