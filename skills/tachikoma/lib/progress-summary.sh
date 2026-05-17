#!/usr/bin/env bash
# progress-summary.sh — compact .tachikoma/progress.txt into a dense
# progress.summary.md to combat context rot on long runs.
#
# Implements ADR 008 Principle 5 (progress journal with compaction). Called
# by tachikoma.sh at iter 10, 20, 30, ... (every COMPACTION_INTERVAL).
#
# Usage:
#   progress-summary.sh <WORKTREE_PATH>
#
# Env:
#   PLANNER_MODEL — the model name to pass to `claude -p --model`. Defaults
#       to "opus" (per tachikoma.conf planner_model).
#   TACHIKOMA_USE_COMPANY_API — pass through to claude -p auth routing.
#
# Behavior:
#   - Reads <WORKTREE>/.tachikoma/progress.txt
#   - Calls claude -p with a fixed compaction prompt
#   - Writes <WORKTREE>/.tachikoma/progress.summary.md (overwrites)
#   - Leaves progress.txt untouched (it remains the append-only authoritative log)
#
# Exit codes:
#   0 — wrote summary.
#   1 — invocation error.
#   2 — progress.txt missing or empty (nothing to summarize; not an error).

set -e
set -o pipefail

WORKTREE="${1:-}"
if [ -z "$WORKTREE" ] || [ ! -d "$WORKTREE" ]; then
  echo "progress-summary: usage: $0 <WORKTREE_PATH>" >&2
  exit 1
fi

PROGRESS="$WORKTREE/.tachikoma/progress.txt"
SUMMARY="$WORKTREE/.tachikoma/progress.summary.md"

if [ ! -s "$PROGRESS" ]; then
  exit 2
fi

MODEL="${PLANNER_MODEL:-opus}"

if [[ -n "${TACHIKOMA_USE_COMPANY_API:-}" ]]; then
  CLAUDE_ENV_ARGS=()
else
  CLAUDE_ENV_ARGS=(env -u ANTHROPIC_API_KEY)
fi

PROMPT="You are summarizing the progress journal of an autonomous coding loop. The full journal is below between <progress> tags.

Output a dense factual summary (max 60 lines, max ~1500 tokens) that captures:
- key decisions made and their reasoning
- architectural choices that constrain future iterations
- completed tasks (terse: id + one-line outcome)
- open blockers and known issues
- any deviation from the original plan

Do NOT include narrative filler, no headers like 'Summary:' or 'Here is...'. Start directly with content. Markdown headings (##) are fine for sections.

<progress>
$(cat "$PROGRESS")
</progress>"

set +e
# TACHIKOMA-PROVIDER-BRIDGE: DELETE WHEN /TACHIKOMA QUEUE ROUTES THROUGH PROXY DISPATCH
if [ "${PROVIDER:-}" = "codex" ]; then
  if [ -n "$MODEL" ]; then
    codex exec "$PROMPT" --model "$MODEL" --sandbox workspace-write \
      > "$SUMMARY.tmp" 2>/dev/null
  else
    codex exec "$PROMPT" --sandbox workspace-write \
      > "$SUMMARY.tmp" 2>/dev/null
  fi
else
  "${CLAUDE_ENV_ARGS[@]}" claude -p "$PROMPT" \
    --model "$MODEL" \
    --output-format text \
    --dangerously-skip-permissions \
    > "$SUMMARY.tmp" 2>/dev/null
fi
RC=$?
set -e

if [ $RC -ne 0 ] || [ ! -s "$SUMMARY.tmp" ]; then
  rm -f "$SUMMARY.tmp"
  echo "progress-summary: claude -p failed (rc=$RC); summary not updated" >&2
  exit 1
fi

mv "$SUMMARY.tmp" "$SUMMARY"
exit 0
