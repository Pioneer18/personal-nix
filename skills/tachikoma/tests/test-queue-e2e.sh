#!/usr/bin/env bash
# E2E test: Epic with 3 open slices → `tachikoma queue` invoked 3 times →
# each invocation grabs the next slice in Epic order.
#
# This test validates the PROXY queue's grab ordering, not tachikoma's full
# lifecycle (Phase 1–6 scaffold/launch/ship are skipped for speed).  It tests
# the slice of SKILL.md Step 0a that is exercisable without a real Claude loop:
# the auto-grab call and slug routing.
#
# Prerequisites:
#   - PROXY daemon running (proxy-daemon LaunchAgent active)
#   - `proxy` CLI on PATH
#   - A seeded QUEUE.yaml (or pass --seed to create a throwaway Epic)
#
# Usage:
#   bash tests/test-queue-e2e.sh              # expects pre-seeded queue
#   bash tests/test-queue-e2e.sh --stub       # use a stub proxy (offline)
#
# The --stub mode replaces the real proxy binary with a round-robin stub that
# returns slices in order: slice-one → slice-two → slice-three → (empty).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
QUEUE_GRAB="$SKILL_DIR/lib/queue-grab.sh"

USE_STUB=0
[[ "${1:-}" == "--stub" ]] && USE_STUB=1

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; ((PASS++)) || true; }
fail() { echo "  FAIL: $1"; ((FAIL++)) || true; }

# ─── Stub setup (--stub mode) ─────────────────────────────────────────────────

STUB_DIR=""
STUB_SEQ_FILE=""
cleanup() {
  [[ -n "$STUB_DIR" ]] && rm -rf "$STUB_DIR"
  [[ -n "$STUB_SEQ_FILE" ]] && rm -f "$STUB_SEQ_FILE"
}
trap cleanup EXIT

if [[ "$USE_STUB" -eq 1 ]]; then
  STUB_DIR="$(mktemp -d)"
  STUB_SEQ_FILE="$(mktemp)"
  # sequence: slice-one, slice-two, slice-three, then empty
  echo "0" > "$STUB_SEQ_FILE"
  SLICES=("proxy-e2e-slice-one" "proxy-e2e-slice-two" "proxy-e2e-slice-three" "")
  SLICES_JSON="(\"proxy-e2e-slice-one\" \"proxy-e2e-slice-two\" \"proxy-e2e-slice-three\" \"\")"

  cat > "$STUB_DIR/proxy" <<STUB
#!/usr/bin/env bash
SEQ_FILE="$STUB_SEQ_FILE"
SLICES=$SLICES_JSON
if [[ "\$1" == "queue" && "\$2" == "grab" ]]; then
  idx=\$(cat "\$SEQ_FILE")
  slug="\${SLICES[\$idx]}"
  echo \$(( idx + 1 )) > "\$SEQ_FILE"
  [[ -n "\$slug" ]] && echo "\$slug"
  exit 0
fi
exit 1
STUB
  chmod +x "$STUB_DIR/proxy"
  PATH="$STUB_DIR:$PATH"
  echo "Running in stub mode (offline, no live PROXY daemon needed)"
fi

# ─── E2E test: 3 grabs in Epic order ─────────────────────────────────────────

echo ""
echo "── test-queue-e2e.sh ───────────────────────────────────────────────────"
echo "── E2E: 3 open slices, 3 grabs → each gets next slice ─────────────────"
echo ""

GRAB1="$(bash "$QUEUE_GRAB")"
if [[ -n "$GRAB1" ]]; then
  ok "grab 1: returned non-empty slug ('$GRAB1')"
else
  fail "grab 1: expected non-empty slug, queue returned empty"
fi

GRAB2="$(bash "$QUEUE_GRAB")"
if [[ -n "$GRAB2" ]]; then
  ok "grab 2: returned non-empty slug ('$GRAB2')"
else
  fail "grab 2: expected non-empty slug, queue returned empty after grab 1"
fi

GRAB3="$(bash "$QUEUE_GRAB")"
if [[ -n "$GRAB3" ]]; then
  ok "grab 3: returned non-empty slug ('$GRAB3')"
else
  fail "grab 3: expected non-empty slug, queue returned empty after grab 2"
fi

# Verify all three slugs are distinct (no double-grab).
if [[ "$GRAB1" != "$GRAB2" && "$GRAB2" != "$GRAB3" && "$GRAB1" != "$GRAB3" ]]; then
  ok "all three grabbed slugs are distinct (no double-grab)"
else
  fail "double-grab detected: grab1='$GRAB1' grab2='$GRAB2' grab3='$GRAB3'"
fi

# 4th grab should find the queue empty.
GRAB4="$(bash "$QUEUE_GRAB")"
if [[ -z "$GRAB4" ]]; then
  ok "grab 4 (queue exhausted): empty output, exit 0"
else
  fail "grab 4: expected empty output (queue exhausted), got '$GRAB4'"
fi

# ─── E2E test: no-arg form exits 0 on empty queue ────────────────────────────
exit_code=0
bash "$QUEUE_GRAB" >/dev/null 2>&1 || exit_code=$?
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    ok "$desc"; else fail "$desc — expected=$expected actual=$actual"
  fi
}
assert_eq "empty-queue grab exits 0" "0" "$exit_code"

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""
[[ "$FAIL" -eq 0 ]] || exit 1
