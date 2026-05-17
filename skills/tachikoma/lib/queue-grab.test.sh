#!/usr/bin/env bash
# Tests for queue-grab.sh — uses a mock `proxy` binary in PATH via PROXY_BIN.
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRAB="$SCRIPT_DIR/queue-grab.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0

run_case() {
  local name="$1"; shift
  local expected_rc="$1"; shift
  local expected_stdout="$1"; shift
  # Remaining args: env-vars-to-export... -- command-to-run
  local actual_stdout
  local actual_rc

  set +e
  actual_stdout="$("$@" 2>/dev/null)"
  actual_rc=$?
  set -e

  if [ "$actual_rc" -eq "$expected_rc" ] && [ "$actual_stdout" = "$expected_stdout" ]; then
    PASS=$((PASS + 1))
    echo "  ok — $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL — $name"
    echo "       expected rc=$expected_rc stdout=$(printf %q "$expected_stdout")"
    echo "       got      rc=$actual_rc stdout=$(printf %q "$actual_stdout")"
  fi
}

# ── Case 1: slug returned (success path).
cat >"$TMPDIR/proxy-ok" <<'EOF'
#!/usr/bin/env bash
echo "proxy-29-queue-tui-and-tachikoma"
EOF
chmod +x "$TMPDIR/proxy-ok"

run_case "exit 0 prints slug on stdout" \
  0 "proxy-29-queue-tui-and-tachikoma" \
  env PROXY_BIN="$TMPDIR/proxy-ok" "$GRAB"

# ── Case 2: empty stdout means queue empty.
cat >"$TMPDIR/proxy-empty" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMPDIR/proxy-empty"

run_case "empty stdout → exit 1, empty stdout" \
  1 "" \
  env PROXY_BIN="$TMPDIR/proxy-empty" "$GRAB"

# ── Case 3: whitespace-only stdout treated as empty.
cat >"$TMPDIR/proxy-ws" <<'EOF'
#!/usr/bin/env bash
echo "   "
EOF
chmod +x "$TMPDIR/proxy-ws"

run_case "whitespace-only stdout → exit 1" \
  1 "" \
  env PROXY_BIN="$TMPDIR/proxy-ws" "$GRAB"

# ── Case 4: daemon failure (non-zero exit).
cat >"$TMPDIR/proxy-fail" <<'EOF'
#!/usr/bin/env bash
echo "daemon connection refused" >&2
exit 7
EOF
chmod +x "$TMPDIR/proxy-fail"

run_case "non-zero proxy rc → exit 3" \
  3 "" \
  env PROXY_BIN="$TMPDIR/proxy-fail" "$GRAB"

# ── Case 5: proxy binary missing.
run_case "missing proxy → exit 2" \
  2 "" \
  env PROXY_BIN="$TMPDIR/does-not-exist" "$GRAB"

# ── Case 5b: daemon-side admission deferral propagates as exit 3.
# When `proxy admission check tachikoma` exits 3, the shim must NOT
# call `proxy queue grab` and must propagate the deferral.
cat >"$TMPDIR/proxy-defer" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "admission" ]; then
  echo "reason=sustained_red effective_free_gb=1.20 swapouts_per_sec=712 samples=2" >&2
  exit 3
fi
# Should never be reached — fail loudly if so.
echo "queue grab called despite admission defer" >&2
exit 99
EOF
chmod +x "$TMPDIR/proxy-defer"

run_case "admission defer → exit 3, no grab" \
  3 "" \
  env PROXY_BIN="$TMPDIR/proxy-defer" "$GRAB"

# ── Case 5c: TACHIKOMA_SKIP_PRESSURE_CHECK bypasses admission.
# Even though `proxy admission check` exits 3, the bypass env var must
# cause the shim to skip admission entirely and reach the grab step.
cat >"$TMPDIR/proxy-bypass" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "admission" ]; then
  echo "reason=sustained_red samples=2" >&2
  exit 3
fi
echo "slug-via-bypass"
EOF
chmod +x "$TMPDIR/proxy-bypass"

run_case "TACHIKOMA_SKIP_PRESSURE_CHECK bypasses admission" \
  0 "slug-via-bypass" \
  env TACHIKOMA_SKIP_PRESSURE_CHECK=1 PROXY_BIN="$TMPDIR/proxy-bypass" "$GRAB"

# ── Case 6: slug with surrounding whitespace is trimmed.
cat >"$TMPDIR/proxy-trim" <<'EOF'
#!/usr/bin/env bash
echo "   my-slug   "
EOF
chmod +x "$TMPDIR/proxy-trim"

run_case "trims whitespace around slug" \
  0 "my-slug" \
  env PROXY_BIN="$TMPDIR/proxy-trim" "$GRAB"

# ── Case 7: E2E — Epic A with 3 open slices, three sequential grabs.
# Simulates the daemon's state machine: each grab transitions one slice
# from open → grabbed and the next call returns the following slice. This
# mirrors the proxy-29 stop condition: "queue has Epic A with 3 open
# slices → run `tachikoma queue` three times → each invocation grabs the
# next slice in Epic A's order." The mock now must also distinguish
# `admission check tachikoma` (silent admit) from `queue grab` (mutate +
# emit slug) — `auto-tachi-pressure-management` added the admission gate
# in front of the grab.
STATE_FILE="$TMPDIR/epic-a-state"
cat >"$STATE_FILE" <<'EOF'
epic-a-1 open
epic-a-2 open
epic-a-3 open
EOF

cat >"$TMPDIR/proxy-epic-a" <<EOF
#!/usr/bin/env bash
# Mock: handles two subcommands —
#   admission check tachikoma   → silent admit (exit 0).
#   queue grab                  → returns the slug of the first open
#     slice and flips it to grabbed.
if [ "\$1" = "admission" ]; then
  exit 0
fi
STATE="$STATE_FILE"
SLUG=""
TMP_NEW="\$STATE.tmp"
: > "\$TMP_NEW"
while IFS= read -r line; do
  if [ -z "\$SLUG" ]; then
    candidate="\${line%% *}"
    status="\${line#* }"
    if [ "\$status" = "open" ]; then
      SLUG="\$candidate"
      echo "\$candidate grabbed" >> "\$TMP_NEW"
      continue
    fi
  fi
  echo "\$line" >> "\$TMP_NEW"
done < "\$STATE"
mv "\$TMP_NEW" "\$STATE"
if [ -n "\$SLUG" ]; then
  echo "\$SLUG"
fi
EOF
chmod +x "$TMPDIR/proxy-epic-a"

E2E_PASS=0
E2E_FAIL=0
for expected in epic-a-1 epic-a-2 epic-a-3; do
  set +e
  actual="$(env PROXY_BIN="$TMPDIR/proxy-epic-a" "$GRAB" 2>/dev/null)"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ] && [ "$actual" = "$expected" ]; then
    E2E_PASS=$((E2E_PASS + 1))
  else
    E2E_FAIL=$((E2E_FAIL + 1))
    echo "  FAIL e2e — expected '$expected', got rc=$rc stdout='$actual'"
  fi
done

# Fourth call: queue exhausted, expect exit 1.
set +e
exhaust="$(env PROXY_BIN="$TMPDIR/proxy-epic-a" "$GRAB" 2>/dev/null)"
exhaust_rc=$?
set -e
if [ "$exhaust_rc" -eq 1 ] && [ -z "$exhaust" ]; then
  E2E_PASS=$((E2E_PASS + 1))
else
  E2E_FAIL=$((E2E_FAIL + 1))
  echo "  FAIL e2e — expected drained queue rc=1, got rc=$exhaust_rc stdout='$exhaust'"
fi

if [ "$E2E_FAIL" -eq 0 ]; then
  echo "  ok — e2e: 3 sequential grabs + drained queue ($E2E_PASS/4)"
  PASS=$((PASS + E2E_PASS))
else
  echo "  FAIL e2e: $E2E_FAIL of 4 failed"
  FAIL=$((FAIL + E2E_FAIL))
fi

echo ""
echo "queue-grab.sh tests: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
