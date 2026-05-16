#!/usr/bin/env bash
# Validate + load a Tachikoma PRD JSON file.
#
# Usage:
#   prd-load.sh <prd-file>
#
# On valid PRD: prints the canonical JSON to stdout, exits 0.
# On invalid: errors on stderr, exits 1.
# On missing/unreadable file or bad JSON: errors on stderr, exits 2.
#
# Used by the tachikoma skill's --prd flow and (future) the M3 daemon's
# fast-dispatch REST endpoint stage that pre-validates client payloads.

set -e
set -o pipefail

PRD_FILE="${1:-}"
if [[ -z "$PRD_FILE" ]]; then
  echo "prd-load: missing argument — usage: prd-load.sh <prd-file>" >&2
  exit 2
fi
if [[ ! -r "$PRD_FILE" ]]; then
  echo "prd-load: file not readable: $PRD_FILE" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/prd-validate.py"

if [[ ! -x "$VALIDATOR" ]]; then
  echo "prd-load: validator not executable: $VALIDATOR" >&2
  exit 2
fi

"$VALIDATOR" "$PRD_FILE"
cat "$PRD_FILE"
