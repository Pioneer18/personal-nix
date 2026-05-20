#!/usr/bin/env bash
# Regression test for the "ship.md never rendered" bug.
#
# tachikoma.sh checks $REPO/.tachikoma/ship.md after the COMPLETE sentinel
# fires and runs auto-ship if the file is present. Before this fix, the
# tachikoma_dispatch scaffold rendered prompt.md but not ship.md, so the
# runtime check always fell through to "ship.md not found".
#
# This test makes two assertions:
#   1. The dispatch source (mcps/tachikoma-mcp/index.ts) reads ship.md.tmpl
#      and writes .tachikoma/ship.md — the code path exists.
#   2. ship.md.tmpl renders cleanly with the exact placeholder set the MCP
#      passes — no unresolved {{X}} left over.
#
# No MCP SDK or node_modules required — runs offline.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"

PASS=0
FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

DISPATCH_SRC="$REPO_ROOT/mcps/tachikoma-mcp/index.ts"
SHIP_TMPL="$REPO_ROOT/skills/tachikoma/ship.md.tmpl"

# ─── Check 1: dispatch source code path ──────────────────────────────────────

if grep -q 'ship\.md\.tmpl' "$DISPATCH_SRC"; then
  ok "dispatch reads ship.md.tmpl"
else
  fail "dispatch does not read ship.md.tmpl — auto-ship will never fire"
fi

if grep -q '"ship.md"' "$DISPATCH_SRC"; then
  ok "dispatch writes .tachikoma/ship.md"
else
  fail "dispatch does not write ship.md — auto-ship will never fire"
fi

if grep -q '"ship_body.txt"' "$DISPATCH_SRC"; then
  ok "dispatch writes ship_body.txt (referenced by ship.md via --body-file)"
else
  fail "dispatch does not write ship_body.txt — gh pr create will fail"
fi

# ─── Check 2: ship.md.tmpl renders cleanly with the MCP placeholder set ──────

# Drive the same renderTemplate logic the MCP uses. Keep the placeholder set
# in sync with mcps/tachikoma-mcp/index.ts — if a new placeholder lands in
# ship.md.tmpl, either add it here or expect this test to fail (which is the
# desired behavior: it forces the scaffolder to substitute it).
RENDER_OUT="$(node --input-type=module -e "
import { readFileSync } from 'fs';
const tmpl = readFileSync('$SHIP_TMPL', 'utf8');
const vars = {
  WORKTREE_PATH: '/tmp/wt',
  TACHIKOMA_BRANCH: 'tachikoma/test-slug',
  BASE_BRANCH: 'main',
  PR_TARGET_BRANCH: 'main',
  SLUG: 'test-slug',
  REPO_OWNER_NAME: '',
  GITHUB_ISSUE_LINE: '',
  COMMIT_MESSAGE: 'msg [test-slug]',
  PR_TITLE: 'title',
  ISSUE_LABEL_BLOCK: '',
  ISSUE_CLOSE_BLOCK: '',
};
const out = Object.entries(vars).reduce((s, [k, v]) => s.replaceAll('{{' + k + '}}', v), tmpl);
const stray = out.match(/{{[A-Z_]+}}/g);
if (stray) {
  console.error('UNRESOLVED:' + [...new Set(stray)].join(','));
  process.exit(1);
}
if (!out.includes('test-slug')) {
  console.error('SLUG_NOT_SUBSTITUTED');
  process.exit(1);
}
console.log('OK');
" 2>&1)"

if [[ "$RENDER_OUT" == "OK" ]]; then
  ok "ship.md.tmpl renders with no unresolved {{}} placeholders"
else
  fail "ship.md.tmpl render: $RENDER_OUT"
fi

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
