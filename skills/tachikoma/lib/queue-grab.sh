#!/usr/bin/env bash
# Thin wrapper around `proxy queue grab` with error handling.
#
# Stdout: grabbed slug (one line, no trailing newline) or nothing if the
#         queue is empty / all candidates are blocked or paused.
# Exit 0: success (slug grabbed OR queue empty).
# Non-zero: proxy CLI missing, daemon connection failed, or unexpected error.
#
# The caller (SKILL.md Step 0a) interprets:
#   empty stdout + exit 0   → queue empty; print user-facing message and exit
#   non-empty stdout + exit 0 → slug grabbed; proceed with tachikoma queue <slug>
#   non-zero exit            → proxy error; surface error and abort

set -euo pipefail

if ! command -v proxy >/dev/null 2>&1; then
  echo "✗ proxy CLI not found on PATH." >&2
  echo "  → Ensure ~/.local/bin is on PATH (PROXY install location)." >&2
  exit 1
fi

# `proxy queue grab` prints the slug to stdout and exits 0 on success.
# It prints nothing (still exit 0) when the queue is empty, the QUEUE.yaml
# is missing, or every candidate is blocked/paused/grabbed.
# Non-zero exit indicates a real error (daemon down, DB unreachable, etc.).
proxy queue grab
