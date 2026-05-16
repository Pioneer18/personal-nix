#!/usr/bin/env bash
#
# smoke-test-queue.sh — verify the filesystem work-queue contract still holds.
#
# Creates a throwaway work-request file under wiki/work-requests/, parses its
# frontmatter back out using the same patterns the skills rely on, checks each
# required field is present and well-formed, then cleans up (even on failure)
# via a trap. Exits 0 on a healthy queue, non-zero with a clear message on a
# broken one.
#
# Run from anywhere; the script resolves paths relative to its own location.

set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUEUE_DIR="$REPO_ROOT/wiki/work-requests"
TS="$(date +%s)"
SLUG="_smoke-test-$TS"
TESTFILE="$QUEUE_DIR/$SLUG.md"
TODAY="$(date +%Y-%m-%d)"

cleanup() {
  rm -f "$TESTFILE"
}
trap cleanup EXIT

fail() {
  echo "smoke-test-queue: FAIL — $*" >&2
  exit 1
}

# 1. Queue directory must exist.
if [ ! -d "$QUEUE_DIR" ]; then
  fail "queue directory missing: $QUEUE_DIR"
fi

# 2. Write a valid work-request file mirroring the template at
#    skills/work-queue/work-request.tmpl. Body must be > 50 chars to satisfy
#    the readiness check both skills perform.
cat > "$TESTFILE" <<EOF
---
status: open
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: $TODAY
---

# Smoke test $TS

Synthetic work-request written by scripts/smoke-test-queue.sh to verify the
filesystem queue contract. This file should never exist after the script
exits — the EXIT trap removes it.

## Goal

Verify the queue is parseable and round-trips a full frontmatter block.
EOF

if [ ! -f "$TESTFILE" ]; then
  fail "could not write test file: $TESTFILE"
fi

# 3. Parse frontmatter back out. Same approach the skills documentation
#    describes: read between the two `---` fences, then key-value match.
fm="$(awk '
  /^---$/ { fences++; if (fences == 2) exit; next }
  fences == 1 { print }
' "$TESTFILE")"

if [ -z "$fm" ]; then
  fail "frontmatter block is empty or missing fences"
fi

get_field() {
  # extracts "value" for key, stripping surrounding whitespace and one
  # optional pair of double quotes. Returns empty string when missing.
  printf '%s\n' "$fm" \
    | awk -v key="$1" -F: '
        $1 == key {
          sub("^[^:]*:[[:space:]]*", "")
          sub("[[:space:]]+$", "")
          gsub("^\"|\"$", "")
          print
          exit
        }
      '
}

status="$(get_field status)"
target_repo="$(get_field target_repo)"
github_issue="$(get_field github_issue)"
failure_count="$(get_field failure_count)"
last_updated="$(get_field last_updated)"

# 4. Required fields. github_issue may be empty string but must be defined.
[ -n "$status" ]        || fail "frontmatter missing 'status'"
[ -n "$target_repo" ]   || fail "frontmatter missing 'target_repo'"
[ -n "$failure_count" ] || fail "frontmatter missing 'failure_count'"
[ -n "$last_updated" ]  || fail "frontmatter missing 'last_updated'"

if ! printf '%s\n' "$fm" | grep -qE '^github_issue:'; then
  fail "frontmatter missing 'github_issue' key (empty string is allowed but the key must be present)"
fi

# 5. Value-shape checks.
case "$status" in
  open|grabbed|done|needs-triage|blocked) ;;
  *) fail "unexpected status value: $status" ;;
esac

if ! printf '%s' "$failure_count" | grep -qE '^[0-9]+$'; then
  fail "failure_count is not a non-negative integer: $failure_count"
fi

if ! printf '%s' "$last_updated" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
  fail "last_updated is not an ISO date (YYYY-MM-DD): $last_updated"
fi

# 6. Body length > 50 chars (same readiness check both skills enforce).
body="$(awk '
  /^---$/ { fences++; next }
  fences >= 2 { print }
' "$TESTFILE")"
body_len="${#body}"
if [ "$body_len" -le 50 ]; then
  fail "body length is $body_len chars; readiness requires > 50"
fi

# 7. Filename ↔ slug round-trip. The skills derive the slug from the filename
#    stem, so the test file must be globbable and recoverable.
found="$(find "$QUEUE_DIR" -maxdepth 1 -type f -name "$SLUG.md" -print -quit)"
if [ -z "$found" ]; then
  fail "test file not found via glob: $SLUG.md"
fi

echo "smoke-test-queue: PASS"
echo "  queue dir:     $QUEUE_DIR"
echo "  test slug:     $SLUG"
echo "  status:        $status"
echo "  target_repo:   $target_repo"
echo "  github_issue:  ${github_issue:-(empty)}"
echo "  failure_count: $failure_count"
echo "  last_updated:  $last_updated"
echo "  body length:   $body_len chars"
exit 0
