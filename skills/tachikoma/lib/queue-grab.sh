#!/usr/bin/env bash
# queue-grab.sh — thin wrapper around `proxy queue grab`.
#
# Memory-pressure decisions now live in `proxy-daemon`. Before grabbing
# a slug we ask `proxy admission check tachikoma` for a verdict:
#   - exit 0 → admit, proceed to grab.
#   - exit 3 → defer; daemon-side rubric refused; forward the reason.
# Set TACHIKOMA_SKIP_PRESSURE_CHECK=1 to bypass the admission gate.
#
# Shell-side exit codes (unchanged):
#   0 — slug printed to stdout (single line, no trailing newline).
#   1 — queue empty (nothing ready). Stdout empty.
#   2 — `proxy` CLI not found.
#   3 — daemon refused admission OR `proxy queue grab` itself failed.
set -e
set -o pipefail

PROXY_BIN="${PROXY_BIN:-proxy}"

if ! command -v "$PROXY_BIN" >/dev/null 2>&1; then
  echo "queue-grab: 'proxy' CLI not found on PATH (set PROXY_BIN to override)" >&2
  exit 2
fi

if [[ -z "${TACHIKOMA_SKIP_PRESSURE_CHECK:-}" ]]; then
  set +e
  ADMIT_ERR="$("$PROXY_BIN" admission check tachikoma 2>&1 1>/dev/null)"
  ADMIT_RC=$?
  set -e
  if [[ $ADMIT_RC -eq 3 ]]; then
    echo "queue-grab: admission deferred: ${ADMIT_ERR}" >&2
    exit 3
  fi
fi

set +e
OUT="$("$PROXY_BIN" queue grab 2>&1)"
RC=$?
set -e

if [ $RC -ne 0 ]; then
  echo "queue-grab: proxy queue grab failed (rc=$RC): $OUT" >&2
  exit 3
fi

SLUG="$(printf '%s' "$OUT" | tr -d '[:space:]')"
if [ -z "$SLUG" ]; then
  exit 1
fi

printf '%s' "$SLUG"
