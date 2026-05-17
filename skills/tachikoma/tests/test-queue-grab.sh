#!/usr/bin/env bash
# Tests for lib/queue-grab.sh — no-arg form auto-grab behaviour.
#
# Prerequisites: PROXY daemon running with a seeded QUEUE.yaml.
# Run from the skill root:  bash tests/test-queue-grab.sh
#
# Each test uses a stub proxy binary injected via PATH override so tests can
# run offline (without a live PROXY daemon).  Replace the stub with the real
# proxy binary (unset PROXY_STUB) for integration testing against a live queue.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
QUEUE_GRAB="$SKILL_DIR/lib/queue-grab.sh"

PASS=0
FAIL=0

ok() {
  echo "  PASS: $1"
  ((PASS++)) || true
}

fail() {
  echo "  FAIL: $1"
  ((FAIL++)) || true
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    ok "$desc"
  else
    fail "$desc — expected='$expected' actual='$actual'"
  fi
}

# ─── Stub helpers ──────────────────────────────────────────────────────────────

make_proxy_stub() {
  local mode="$1"  # "slug", "empty", or "error"
  local slug="${2:-}"
  local stub_dir
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/proxy" <<STUB
#!/usr/bin/env bash
# Stub proxy binary — mode: $mode
if [[ "\$1" == "queue" && "\$2" == "grab" ]]; then
  case "$mode" in
    slug)  echo "$slug"; exit 0 ;;
    empty) exit 0 ;;
    error) echo "error: connection refused" >&2; exit 1 ;;
  esac
fi
exit 1
STUB
  chmod +x "$stub_dir/proxy"
  echo "$stub_dir"
}

cleanup_stubs=()
cleanup() {
  for d in "${cleanup_stubs[@]:-}"; do
    rm -rf "$d"
  done
}
trap cleanup EXIT

# ─── Test: queue empty → empty output, exit 0 ─────────────────────────────────

echo ""
echo "── test-queue-grab.sh ──────────────────────────────────────────────────"
echo "── no-arg form (lib/queue-grab.sh) ────────────────────────────────────"
echo ""

STUB_DIR="$(make_proxy_stub "empty")"
cleanup_stubs+=("$STUB_DIR")

OUTPUT="$(PATH="$STUB_DIR:$PATH" bash "$QUEUE_GRAB")"
assert_eq "empty queue → empty stdout" "" "$OUTPUT"

exit_code=0
PATH="$STUB_DIR:$PATH" bash "$QUEUE_GRAB" >/dev/null 2>&1 || exit_code=$?
assert_eq "empty queue → exit 0" "0" "$exit_code"

# ─── Test: slug returned → slug on stdout, exit 0 ────────────────────────────

STUB_DIR2="$(make_proxy_stub "slug" "proxy-29b-tachikoma-queue-no-arg-wiring")"
cleanup_stubs+=("$STUB_DIR2")

OUTPUT2="$(PATH="$STUB_DIR2:$PATH" bash "$QUEUE_GRAB")"
assert_eq "slug returned → stdout has slug" "proxy-29b-tachikoma-queue-no-arg-wiring" "$OUTPUT2"

exit_code2=0
PATH="$STUB_DIR2:$PATH" bash "$QUEUE_GRAB" >/dev/null 2>&1 || exit_code2=$?
assert_eq "slug returned → exit 0" "0" "$exit_code2"

# ─── Test: proxy error → non-zero exit ───────────────────────────────────────

STUB_DIR3="$(make_proxy_stub "error")"
cleanup_stubs+=("$STUB_DIR3")

exit_code3=0
PATH="$STUB_DIR3:$PATH" bash "$QUEUE_GRAB" >/dev/null 2>&1 || exit_code3=$?
if [[ "$exit_code3" -ne 0 ]]; then
  ok "proxy error → non-zero exit ($exit_code3)"
else
  fail "proxy error → expected non-zero exit, got 0"
fi

# ─── Test: proxy not on PATH → exit 1 with message ───────────────────────────
# Keep /usr/bin and /bin on PATH so bash stays findable; only exclude proxy.

NO_PROXY_PATH="/usr/bin:/bin"

exit_code4=0
ERR_MSG=""
ERR_MSG="$(PATH="$NO_PROXY_PATH" bash "$QUEUE_GRAB" 2>&1)" || exit_code4=$?
if [[ "$exit_code4" -ne 0 ]]; then
  ok "proxy not on PATH → non-zero exit"
else
  fail "proxy not on PATH → expected non-zero exit, got 0"
fi
if [[ "$ERR_MSG" == *"proxy CLI not found"* ]]; then
  ok "proxy not on PATH → user-friendly error message"
else
  fail "proxy not on PATH → missing user-friendly message, got: $ERR_MSG"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

[[ "$FAIL" -eq 0 ]] || exit 1
