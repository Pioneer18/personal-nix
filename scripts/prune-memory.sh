#!/usr/bin/env bash
# prune-memory.sh — weekly auto-curator for ~/.claude/projects/-Users-pioneer/memory/
#
# Fired by launchd.agents.memory-prune (see modules/memory-prune.nix). Invokes
# `claude -p` with the prompt template at scripts/prune-memory-prompt.md, parses
# the structured report, and then:
#   - Saves the report to .prune-reports/YYYY-MM-DD.md
#   - Moves ARCHIVE-AUTO entries (independently verified-expired) to
#     .archive/YYYY-MM-DD/ and strips them from MEMORY.md
#   - macOS-notifies if any ARCHIVE-RECOMMEND entries exist
#
# Usage:
#   prune-memory.sh                 # full run: report + auto-archive + notify
#   prune-memory.sh --dry-run       # produce the report, do not move files
#   prune-memory.sh --self-test     # run built-in unit tests (no API calls)
#   prune-memory.sh --memory-dir D  # override memory directory (mainly tests)
#   prune-memory.sh --prompt FILE   # override prompt-template path
#   prune-memory.sh --claude-bin X  # override claude binary
#
# Env vars (lowest precedence, overridden by flags):
#   PRUNE_MEMORY_DIR, PRUNE_MEMORY_PROMPT, PRUNE_MEMORY_CLAUDE_BIN
#
# Exit codes:
#   0  success (including "nothing to do")
#   1  fatal error (missing claude, missing memory dir, parse failure)
#   2  partial success — report produced but some auto-archive moves failed
#      the independent expiry check (claude said ARCHIVE-AUTO but no `expires:`
#      frontmatter actually present or actually past). Investigate the report.

set -euo pipefail

# ---------- defaults ----------
MEMORY_DIR_DEFAULT="$HOME/.claude/projects/-Users-pioneer/memory"
PROMPT_TEMPLATE_DEFAULT="$HOME/projects/personal-nix/scripts/prune-memory-prompt.md"
CLAUDE_BIN_DEFAULT="claude"

MEMORY_DIR="${PRUNE_MEMORY_DIR:-$MEMORY_DIR_DEFAULT}"
PROMPT_TEMPLATE="${PRUNE_MEMORY_PROMPT:-$PROMPT_TEMPLATE_DEFAULT}"
CLAUDE_BIN="${PRUNE_MEMORY_CLAUDE_BIN:-$CLAUDE_BIN_DEFAULT}"
DRY_RUN=false
SELF_TEST=false

# ---------- arg parsing ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)    DRY_RUN=true; shift ;;
    --self-test)  SELF_TEST=true; shift ;;
    --memory-dir) MEMORY_DIR="$2"; shift 2 ;;
    --prompt)     PROMPT_TEMPLATE="$2"; shift 2 ;;
    --claude-bin) CLAUDE_BIN="$2"; shift 2 ;;
    -h|--help)
      sed -n '/^# /,/^$/{ /^# /p; /^$/q }' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "prune-memory.sh: unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ---------- helpers ----------
log() { printf '[%s] prune-memory: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found in PATH: $1"
}

# Extract the JSON block delimited by <!-- machine-readable --> markers.
# Reads a report file path; prints just the JSON body to stdout.
extract_report_json() {
  local report="$1"
  awk '
    /<!-- machine-readable -->/ { in_block = 1; next }
    /<!-- \/machine-readable -->/ { in_block = 0; next }
    in_block { print }
  ' "$report" | awk '
    /^```json$/    { in_fence = 1; next }
    /^```$/        { if (in_fence) { in_fence = 0; exit } }
    in_fence       { print }
  '
}

# Defense-in-depth: independently verify that <file> has YAML frontmatter with
# an `expires: YYYY-MM-DD` field that is today or earlier. Claude may have
# misjudged; we refuse to auto-archive anything we cannot verify ourselves.
file_is_expired() {
  local file="$1"
  [ -f "$file" ] || return 1

  local frontmatter expires_line expires_date today
  frontmatter="$(awk '
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm { print }
  ' "$file")"

  [ -n "$frontmatter" ] || return 1

  expires_line="$(printf '%s\n' "$frontmatter" | grep -E '^[[:space:]]*expires:[[:space:]]*' | head -1 || true)"
  [ -n "$expires_line" ] || return 1

  expires_date="$(printf '%s\n' "$expires_line" \
    | sed -E 's/^[[:space:]]*expires:[[:space:]]*//; s/[[:space:]]*$//; s/^["'\'']//; s/["'\'']$//')"
  # Require strict YYYY-MM-DD shape so the lexicographic compare below is safe.
  printf '%s' "$expires_date" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || return 1

  today="$(date +%Y-%m-%d)"
  # Lexicographic compare is sound for fixed-width YYYY-MM-DD.
  [ "$expires_date" \< "$today" ] || [ "$expires_date" = "$today" ]
}

# Remove from MEMORY.md any line whose markdown link points at the given file
# basename — e.g. `- [Title](user_role.md) — hook`. Idempotent.
remove_from_index() {
  local file="$1"
  [ -f "$INDEX_FILE" ] || return 0
  local pattern tmp
  # Escape regex metachars in the filename
  pattern="$(printf '%s' "$file" | sed 's/[][\\.^$*+?(){}|/]/\\&/g')"
  tmp="$(mktemp)"
  # Match the file inside a markdown link target: (filename)
  grep -v -E "\\($pattern\\)" "$INDEX_FILE" > "$tmp" || true
  mv "$tmp" "$INDEX_FILE"
}

notify_user() {
  local count="$1"
  local report="$2"
  if command -v osascript >/dev/null 2>&1; then
    local msg
    msg="$count memory entries suggested for archive — see $report"
    osascript \
      -e "display notification \"$msg\" with title \"Claude Memory Curator\"" \
      >/dev/null 2>&1 \
      || log "osascript notification failed (non-fatal)"
  else
    log "osascript not available; skipping notification"
  fi
}

# Build the prompt that will be piped to claude: template + MEMORY.md + each memory file.
build_prompt() {
  cat "$PROMPT_TEMPLATE"
  printf '\n\n---\n\n## CURRENT INDEX (`MEMORY.md`)\n\n'
  if [ -f "$INDEX_FILE" ]; then
    printf '```markdown\n'
    cat "$INDEX_FILE"
    printf '\n```\n'
  else
    printf '_(no MEMORY.md found)_\n'
  fi
  printf '\n## MEMORY FILES\n\n'
  local f base
  shopt -s nullglob
  for f in "$MEMORY_DIR"/*.md; do
    base="$(basename "$f")"
    [ "$base" = "MEMORY.md" ] && continue
    printf '### %s\n\n```markdown\n' "$base"
    cat "$f"
    printf '\n```\n\n'
  done
  shopt -u nullglob
}

# ---------- self-test ----------
# Built-in unit tests for the pure helpers. No API calls, no real filesystem
# outside a private tmpdir. Run via `prune-memory.sh --self-test`.
run_self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
      pass=$((pass+1))
      printf '  ✓ %s\n' "$name"
    else
      fail=$((fail+1))
      printf '  ✗ %s\n    expected: %q\n    actual:   %q\n' "$name" "$expected" "$actual"
    fi
  }
  assert_rc() {
    local name="$1" expected_rc="$2"; shift 2
    if "$@"; then
      local rc=0
    else
      local rc=$?
    fi
    if [ "$rc" = "$expected_rc" ]; then
      pass=$((pass+1))
      printf '  ✓ %s\n' "$name"
    else
      fail=$((fail+1))
      printf '  ✗ %s (expected rc=%s got rc=%s)\n' "$name" "$expected_rc" "$rc"
    fi
  }

  log "self-test: extract_report_json"
  cat > "$tmp/report1.md" <<'EOF'
# Memory Report

Some preamble.

<!-- machine-readable -->
```json
{
  "date": "2026-05-14",
  "categorized": [
    { "file": "a.md", "category": "KEEP", "rationale": "x" }
  ]
}
```
<!-- /machine-readable -->
EOF
  local extracted
  extracted="$(extract_report_json "$tmp/report1.md")"
  if printf '%s\n' "$extracted" | jq -e '.categorized[0].file == "a.md"' >/dev/null; then
    pass=$((pass+1)); echo "  ✓ JSON extraction parses"
  else
    fail=$((fail+1)); echo "  ✗ JSON extraction parses (got: $extracted)"
  fi

  # No machine-readable block → empty output
  cat > "$tmp/report2.md" <<'EOF'
Just a plain report with no JSON.
EOF
  extracted="$(extract_report_json "$tmp/report2.md")"
  assert_eq "no-JSON returns empty string" "" "$extracted"

  log "self-test: file_is_expired"
  # Expired file
  cat > "$tmp/expired.md" <<'EOF'
---
name: expired
description: x
expires: 2020-01-01
metadata:
  type: project
---
body
EOF
  assert_rc "expired file detected" 0 file_is_expired "$tmp/expired.md"

  # Future expiry
  cat > "$tmp/future.md" <<'EOF'
---
name: future
expires: 2099-12-31
---
body
EOF
  assert_rc "future expiry rejected" 1 file_is_expired "$tmp/future.md"

  # No expires field
  cat > "$tmp/no-expires.md" <<'EOF'
---
name: nope
description: x
---
body
EOF
  assert_rc "missing expires rejected" 1 file_is_expired "$tmp/no-expires.md"

  # Malformed date
  cat > "$tmp/bad-date.md" <<'EOF'
---
name: bad
expires: last-tuesday
---
body
EOF
  assert_rc "malformed date rejected" 1 file_is_expired "$tmp/bad-date.md"

  # No frontmatter at all
  cat > "$tmp/no-fm.md" <<'EOF'
just body, no frontmatter
EOF
  assert_rc "no frontmatter rejected" 1 file_is_expired "$tmp/no-fm.md"

  log "self-test: remove_from_index"
  INDEX_FILE="$tmp/MEMORY.md"
  cat > "$INDEX_FILE" <<'EOF'
- [Role](user_role.md) — who the user is
- [Old project](old_project.md) — stale workstream
- [Keep](user_role.md.keep) — sneaky lookalike
EOF
  remove_from_index "old_project.md"
  local after
  after="$(cat "$INDEX_FILE")"
  if printf '%s' "$after" | grep -q 'old_project.md'; then
    fail=$((fail+1)); echo "  ✗ removed line still present"
  else
    pass=$((pass+1)); echo "  ✓ matching line removed"
  fi
  if printf '%s' "$after" | grep -q 'user_role.md'; then
    pass=$((pass+1)); echo "  ✓ unrelated lines preserved"
  else
    fail=$((fail+1)); echo "  ✗ unrelated lines incorrectly removed"
  fi

  # Idempotency: a second call is a no-op
  cp "$INDEX_FILE" "$tmp/INDEX.before"
  remove_from_index "old_project.md"
  if cmp -s "$INDEX_FILE" "$tmp/INDEX.before"; then
    pass=$((pass+1)); echo "  ✓ remove_from_index idempotent"
  else
    fail=$((fail+1)); echo "  ✗ remove_from_index changed file on repeat"
  fi

  echo
  log "self-test results: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

INDEX_FILE="$MEMORY_DIR/MEMORY.md"

if [ "$SELF_TEST" = "true" ]; then
  run_self_test
  exit $?
fi

# ---------- main ----------
require_cmd "$CLAUDE_BIN"
require_cmd jq
require_cmd awk
require_cmd sed
require_cmd grep

[ -d "$MEMORY_DIR" ] || die "memory directory not found: $MEMORY_DIR"
[ -f "$PROMPT_TEMPLATE" ] || die "prompt template not found: $PROMPT_TEMPLATE"

DATE="$(date +%Y-%m-%d)"
REPORTS_DIR="$MEMORY_DIR/.prune-reports"
ARCHIVE_DIR="$MEMORY_DIR/.archive/$DATE"
REPORT_FILE="$REPORTS_DIR/$DATE.md"

mkdir -p "$REPORTS_DIR"

log "memory dir: $MEMORY_DIR"
log "report: $REPORT_FILE${DRY_RUN:+ (dry-run)}"

PROMPT="$(build_prompt)"

log "invoking $CLAUDE_BIN -p (text output)..."
# Pipe via stdin to avoid arg length limits; force text output to keep the
# response plain markdown (claude's default json mode would wrap the body).
if ! REPORT_OUTPUT="$(printf '%s' "$PROMPT" | "$CLAUDE_BIN" -p --output-format text 2>&1)"; then
  printf '%s\n' "$REPORT_OUTPUT" > "$REPORT_FILE"
  die "claude invocation failed; raw output preserved in $REPORT_FILE"
fi

printf '%s\n' "$REPORT_OUTPUT" > "$REPORT_FILE"
log "wrote report ($(wc -c < "$REPORT_FILE" | tr -d ' ') bytes)"

JSON="$(extract_report_json "$REPORT_FILE" || true)"
if [ -z "$JSON" ]; then
  die "no <!-- machine-readable --> JSON block in report — claude did not emit structured data. See $REPORT_FILE"
fi
if ! printf '%s' "$JSON" | jq -e '.categorized | type == "array"' >/dev/null 2>&1; then
  die "report JSON lacks .categorized array. See $REPORT_FILE"
fi

KEEP_COUNT="$(printf '%s' "$JSON" | jq -r '[.categorized[] | select(.category == "KEEP")] | length')"
CONSOL_COUNT="$(printf '%s' "$JSON" | jq -r '[.categorized[] | select(.category == "CONSOLIDATE")] | length')"
ARC_REC_COUNT="$(printf '%s' "$JSON" | jq -r '[.categorized[] | select(.category == "ARCHIVE-RECOMMEND")] | length')"
ARC_AUTO_COUNT="$(printf '%s' "$JSON" | jq -r '[.categorized[] | select(.category == "ARCHIVE-AUTO")] | length')"

log "summary: $KEEP_COUNT keep · $CONSOL_COUNT consolidate · $ARC_REC_COUNT recommend · $ARC_AUTO_COUNT auto"

ARCHIVED=0
FAILED=0
if [ "$ARC_AUTO_COUNT" -gt 0 ]; then
  if [ "$DRY_RUN" = "true" ]; then
    log "dry-run: would auto-archive $ARC_AUTO_COUNT entries (skipped)"
  else
    mkdir -p "$ARCHIVE_DIR"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      # Guard: ARCHIVE-AUTO must operate on a plain basename (no path traversal).
      case "$f" in
        */*|..|.|"")
          log "skip archive (invalid filename): $f"
          FAILED=$((FAILED+1))
          continue
          ;;
      esac
      src="$MEMORY_DIR/$f"
      if [ ! -f "$src" ]; then
        # Already gone (idempotency: prior run archived it). Not a failure.
        log "skip archive (file gone, idempotent): $f"
        continue
      fi
      if ! file_is_expired "$src"; then
        log "skip archive (no verified expires: frontmatter): $f"
        FAILED=$((FAILED+1))
        continue
      fi
      dest="$ARCHIVE_DIR/$f"
      mv "$src" "$dest"
      remove_from_index "$f"
      log "archived: $f → .archive/$DATE/$f"
      ARCHIVED=$((ARCHIVED+1))
    done < <(printf '%s' "$JSON" | jq -r '.categorized[] | select(.category == "ARCHIVE-AUTO") | .file')

    # Clean up the date archive dir if nothing actually landed in it.
    if [ "$ARCHIVED" -eq 0 ] && [ -d "$ARCHIVE_DIR" ]; then
      rmdir "$ARCHIVE_DIR" 2>/dev/null || true
    fi
  fi
fi

if [ "$ARC_REC_COUNT" -gt 0 ]; then
  if [ "$DRY_RUN" = "true" ]; then
    log "dry-run: would notify about $ARC_REC_COUNT recommendations"
  else
    notify_user "$ARC_REC_COUNT" "$REPORT_FILE"
  fi
fi

log "done — archived $ARCHIVED, refused $FAILED, report $REPORT_FILE"
if [ "$FAILED" -gt 0 ]; then
  exit 2
fi
exit 0
