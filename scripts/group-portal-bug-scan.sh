#!/bin/zsh
# Daily Group Portal prod-log bug scan (launchd: modules/group-portal-bug-scan.nix).
# Runs headless Claude Code in a throwaway worktree of origin/develop. The run
# may open fix PRs; it never merges, deploys, or touches the prod DB (deny
# rules in group-portal-bug-scan.settings.json enforce that).
# Procedure: wiki/recipes/group-portal-bug-scan.md
set -u

export PATH="$HOME/.local/bin:/etc/profiles/per-user/$USER/bin:$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

HERE="$HOME/projects/personal-nix/scripts"
REPO="$HOME/Projects/platform"
STATE_DIR="$HOME/.local/state/group-portal-bug-scan"
LOG_DIR="$HOME/Library/Logs/group-portal-bug-scan"
DATE=$(date +%Y-%m-%d)
LOG="$LOG_DIR/$DATE.log"
WT="$STATE_DIR/worktree-$DATE"
LOCK="$STATE_DIR/lock"
REPORT="$REPO/docs/workbench/ftp-group-portal/bug-scan-$DATE.md"

# CLAUDE_CODE_OAUTH_TOKEN and GITHUB_TOKEN; launchd does not run ~/.zshrc.
[[ -f "$HOME/.secrets" ]] && source "$HOME/.secrets"

mkdir -p "$STATE_DIR" "$LOG_DIR"
exec >>"$LOG" 2>&1
echo "=== $(date -u +%FT%TZ) start"

notify() {
  /usr/bin/osascript -e "display notification \"${2//\"/\'}\" with title \"Group Portal scan\" subtitle \"$1\"" || true
}

if ! mkdir "$LOCK" 2>/dev/null; then
  echo "another run holds $LOCK; exit"; exit 0
fi
cleanup() {
  git -C "$REPO" worktree remove --force "$WT" 2>/dev/null
  rmdir "$LOCK" 2>/dev/null
}
trap cleanup EXIT

if [[ -e "$REPORT" && "${FORCE:-0}" != 1 ]]; then
  echo "report for $DATE exists; exit (FORCE=1 to rerun)"; exit 0
fi

if ! gcloud auth print-access-token >/dev/null 2>&1; then
  echo "gcloud auth expired"; notify "skipped" "gcloud login expired: run gcloud auth login"; exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "gh auth failed"; notify "skipped" "gh auth failed: run gh auth login"; exit 1
fi

SINCE=$(cat "$STATE_DIR/last-success" 2>/dev/null || python3 -c 'import datetime as d;print((d.datetime.now(d.timezone.utc)-d.timedelta(hours=26)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
DEPLOYED=$(gh run list -R relymd/platform --workflow group-portal-prod.yml --status success -L 1 --json headSha --jq '.[0].headSha')
PREV_DEPLOYED=$(cat "$STATE_DIR/last-deployed-sha" 2>/dev/null || echo "$DEPLOYED")
STARTED=$(date -u +%FT%TZ)

git -C "$REPO" fetch -q origin develop || { notify "failed" "git fetch failed"; exit 1; }
git -C "$REPO" worktree add -q --detach "$WT" origin/develop || { notify "failed" "worktree add failed"; exit 1; }

PROMPT=$(sed -e "s|{{DATE}}|$DATE|g" -e "s|{{SINCE}}|$SINCE|g" -e "s|{{REPORT}}|$REPORT|g" \
  -e "s|{{DEPLOYED}}|$DEPLOYED|g" -e "s|{{PREV_DEPLOYED}}|$PREV_DEPLOYED|g" -e "s|{{REPO}}|$REPO|g" \
  "$HERE/group-portal-bug-scan.prompt.md")

cd "$WT"
OUT="$STATE_DIR/out-$DATE.txt"
timeout 4h claude -p "$PROMPT" \
  --model claude-opus-5-5 --effort high \
  --permission-mode bypassPermissions \
  --settings "$HERE/group-portal-bug-scan.settings.json" \
  --add-dir "$REPO/docs/workbench/ftp-group-portal" \
  --max-budget-usd "${MAX_BUDGET_USD:-40}" \
  -n "group-portal-bug-scan-$DATE" \
  --output-format text | tee "$OUT"
RC=${pipestatus[1]}
echo "=== $(date -u +%FT%TZ) claude exit $RC"

VERDICT=$(grep -E '^VERDICT:' "$OUT" | tail -1 | cut -c10-)
if [[ $RC -eq 0 && -e "$REPORT" ]]; then
  echo "$STARTED" >"$STATE_DIR/last-success"
  echo "$DEPLOYED" >"$STATE_DIR/last-deployed-sha"
  notify "done" "${VERDICT:-see $REPORT}"
else
  notify "failed (exit $RC)" "${VERDICT:-see $LOG}"
  exit 1
fi
