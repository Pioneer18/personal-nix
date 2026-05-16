#!/usr/bin/env bash
# verifier-gate.sh — independent verifier called by tachikoma.sh after the
# sentinel substring is detected, before ship phase fires.
#
# Implements ADR 008 Principle 1 (oracle separation) + Principle 8 (anti-
# shortcut by structure). The model's sentinel emission is *necessary* but
# not *sufficient* — this gate is sufficient. If it rejects, the loop
# continues iterating instead of shipping.
#
# Usage (invoked from tachikoma.sh):
#   verifier-gate.sh <WORKTREE_PATH> <BASE_BRANCH>
#
# Env:
#   TYPECHECK_CMD, TEST_CMD, LINT_CMD — feedback-loop commands rendered into
#       the worktree at scaffold time. Empty string means "skip that check"
#       (which is itself a smell — the gate logs a warning).
#   VERIFIER_GATE_SKIP_FEEDBACK=1 — for unit testing; skips step 3.
#
# Exit codes:
#   0 — gate passed; tachikoma.sh proceeds to ship phase.
#   1 — gate failed; tachikoma.sh appends a REJECTED block to progress.txt
#       and continues iterating (does NOT ship).
#   2 — invocation error (bad args, missing files). Treat as failure;
#       refuse to ship.
#
# Output:
#   On reject, prints a one-line summary to stderr starting with "GATE-REJECT:"
#   plus a multi-line block to stdout suitable for appending to progress.txt.
#   On pass, prints a one-line summary to stderr starting with "GATE-PASS:".

set -e
set -o pipefail

WORKTREE="${1:-}"
BASE_BRANCH="${2:-}"

if [ -z "$WORKTREE" ] || [ -z "$BASE_BRANCH" ]; then
  echo "verifier-gate: usage: $0 <WORKTREE_PATH> <BASE_BRANCH>" >&2
  exit 2
fi

if [ ! -d "$WORKTREE/.git" ] && [ ! -f "$WORKTREE/.git" ]; then
  echo "verifier-gate: $WORKTREE is not a git worktree" >&2
  exit 2
fi

cd "$WORKTREE"

FAILED_CHECKS=()
emit_reject() {
  local check="$1"
  local detail="$2"
  FAILED_CHECKS+=("$check: $detail")
}

# --- Check 1: working tree clean ---
if [ -n "$(git status --porcelain)" ]; then
  emit_reject "tree-dirty" "uncommitted changes present after sentinel — model emitted COMPLETE without committing all work"
fi

# --- Check 2: last commit is non-empty (model did work, not just emit sentinel) ---
LAST_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo "")"
if [ -z "$LAST_COMMIT" ]; then
  emit_reject "no-head" "could not read HEAD"
else
  # Files changed in last commit; 0 means an empty commit (--allow-empty).
  # On root-commit (no HEAD~1), use --root form. Wrap in subshell to keep
  # set -e + pipefail from killing us on the lookup failure.
  set +e
  if git rev-parse HEAD~1 >/dev/null 2>&1; then
    CHANGED_IN_LAST="$(git diff --name-only HEAD~1 HEAD 2>/dev/null | wc -l | tr -d ' ')"
  else
    # Root commit: count files in the commit's tree.
    CHANGED_IN_LAST="$(git show --name-only --pretty=format: HEAD 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
  fi
  set -e
  if [ "${CHANGED_IN_LAST:-0}" = "0" ]; then
    emit_reject "empty-last-commit" "HEAD has no file changes — sentinel emitted without committing work"
  fi
fi

# --- Check 3: re-run feedback loops from supervisor ---
if [ -z "${VERIFIER_GATE_SKIP_FEEDBACK:-}" ]; then
  for pair in "TYPECHECK_CMD:typecheck" "TEST_CMD:test" "LINT_CMD:lint"; do
    var_name="${pair%%:*}"
    label="${pair##*:}"
    cmd="${!var_name:-}"
    if [ -z "$cmd" ]; then
      echo "verifier-gate: WARN — $var_name not set; skipping $label re-run" >&2
      continue
    fi
    if ! bash -c "$cmd" >/tmp/verifier-gate-$label.out 2>&1; then
      LAST_LINE="$(tail -n 5 /tmp/verifier-gate-$label.out | tr '\n' ' ' | cut -c1-200)"
      emit_reject "$label-failed" "$cmd → exit non-zero; tail: $LAST_LINE"
    fi
  done
fi

# --- Check 4: cumulative diff cheat-scan (BASE_BRANCH..HEAD) ---
# Patterns the model might use to fake-pass tests without doing the work.
CHEAT_PATTERNS=(
  '\.skip\('
  '\.only\('
  'xit\('
  'xdescribe\('
  'fit\.skip'
  'it\.todo\('
  'pytest\.mark\.skip'
  'pytest\.skip\('
  '@unittest\.skip'
  '# *TODO'
  '# *FIXME'
  'expect\.assertions\(0\)'
  '\.toBe\(true\); *// *TODO'
  '--no-verify'
  'eslint-disable'
  'ts-ignore'
  'ts-nocheck'
)
# Build a single -E pattern, anchored to added lines only ("^+" but not "^+++ ").
COMBINED_RE="$(IFS='|'; echo "${CHEAT_PATTERNS[*]}")"
# Wrap in set +e — `git diff` returns non-zero if BASE_BRANCH doesn't exist
# (e.g. a renamed default branch); we treat that as "no diff to scan".
set +e
DIFF_OUT="$(git diff "$BASE_BRANCH..HEAD" 2>/dev/null)"
set -e
if [ -n "$DIFF_OUT" ]; then
  set +e
  CHEAT_HITS="$(printf '%s\n' "$DIFF_OUT" \
    | grep -E '^\+' \
    | grep -vE '^\+\+\+ ' \
    | grep -nE "$COMBINED_RE" \
    | head -5)"
  set -e
  if [ -n "$CHEAT_HITS" ]; then
    FIRST="$(printf '%s' "$CHEAT_HITS" | head -1 | cut -c1-160)"
    emit_reject "cheat-pattern" "diff introduces a test-skip / lint-disable pattern; first hit: $FIRST"
  fi
fi

# --- Check 5: no test files deleted in cumulative diff ---
set +e
DELETED_TESTS="$(git diff --name-only --diff-filter=D "$BASE_BRANCH..HEAD" 2>/dev/null \
  | grep -E '(\.test\.|_test\.|/tests?/|/__tests__/)' \
  | head -3)"
set -e
if [ -n "$DELETED_TESTS" ]; then
  FIRST="$(printf '%s' "$DELETED_TESTS" | head -1)"
  emit_reject "test-deleted" "diff deletes test file(s); first: $FIRST"
fi

# --- Verdict ---
if [ "${#FAILED_CHECKS[@]}" -eq 0 ]; then
  echo "GATE-PASS: all checks passed" >&2
  exit 0
fi

# Emit human-readable rejection block on stdout (tachikoma.sh appends to progress.txt).
echo ""
echo "## verifier-gate REJECTED"
for c in "${FAILED_CHECKS[@]}"; do
  echo "- $c"
done
echo ""
echo "GATE-REJECT: ${#FAILED_CHECKS[@]} check(s) failed" >&2
exit 1
