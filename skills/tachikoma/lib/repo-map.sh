#!/usr/bin/env bash
# repo-map.sh — generate a token-budgeted repo map for injection into the
# iteration prompt.
#
# Implements ADR 008 Principle 2 (ACI discipline): inject structure into the
# prompt so the model doesn't burn turns on Grep/Glob discovery.
#
# Three tiers, fall through to the next on missing tool:
#   1. ctags (symbol-level — best)
#   2. tree-sitter CLI (symbol-level — equivalent)
#   3. git ls-files + tree-style directory layout (path-level — adequate)
#
# Usage:
#   repo-map.sh <REPO_PATH> <OUTPUT_FILE> [TOKEN_BUDGET]
#
# TOKEN_BUDGET is approximate (1 token ≈ 4 chars). Default 2000 tokens (8000 chars).
#
# Exit codes:
#   0 — wrote OUTPUT_FILE.
#   1 — invocation error.
#   2 — repo unreadable.

set -e
set -o pipefail

REPO="${1:-}"
OUT="${2:-}"
BUDGET_TOKENS="${3:-2000}"
BUDGET_CHARS=$((BUDGET_TOKENS * 4))

if [ -z "$REPO" ] || [ -z "$OUT" ]; then
  echo "repo-map: usage: $0 <REPO_PATH> <OUTPUT_FILE> [TOKEN_BUDGET]" >&2
  exit 1
fi

if [ ! -d "$REPO" ]; then
  echo "repo-map: $REPO is not a directory" >&2
  exit 2
fi

mkdir -p "$(dirname "$OUT")"

write_header() {
  cat > "$OUT" <<EOF
# Repo map — $(basename "$REPO")

Generated $(date -u +"%Y-%m-%dT%H:%M:%SZ") · token budget ~$BUDGET_TOKENS · method: $1

EOF
}

# --- Tier 1: ctags ---
if command -v ctags >/dev/null 2>&1; then
  write_header "ctags"
  {
    echo "## Symbols"
    echo ""
    echo '```'
    # -R recursive, --exclude common noise, kind filter to public-ish symbols.
    ctags -R -f - \
      --exclude=node_modules \
      --exclude=target \
      --exclude=dist \
      --exclude=build \
      --exclude=.git \
      --exclude=.tachikoma \
      --exclude=__pycache__ \
      --exclude=.next \
      "$REPO" 2>/dev/null \
      | awk -F'\t' '{print $2 ":" $1}' \
      | sort -u \
      | head -300
    echo '```'
  } >> "$OUT" 2>/dev/null || true
  # If ctags produced anything beyond the header, accept this tier.
  if [ "$(wc -c < "$OUT" | tr -d ' ')" -gt 200 ]; then
    truncate -s "$BUDGET_CHARS" "$OUT" 2>/dev/null || \
      head -c "$BUDGET_CHARS" "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
    exit 0
  fi
fi

# --- Tier 2: tree-sitter CLI ---
# tree-sitter parse output is verbose; we extract function/class names per
# language using a tiny grep instead of full AST parsing — good enough for
# orientation. Only fires if tree-sitter is installed AND ctags wasn't.
if command -v tree-sitter >/dev/null 2>&1; then
  write_header "tree-sitter (grep-fallback)"
  {
    echo "## Top-level definitions"
    echo ""
    echo '```'
    find "$REPO" \
      -type f \
      \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
         -o -name '*.py' -o -name '*.rs' -o -name '*.go' \) \
      -not -path '*/node_modules/*' \
      -not -path '*/target/*' \
      -not -path '*/.git/*' \
      -not -path '*/.tachikoma/*' \
      -not -path '*/dist/*' \
      -not -path '*/build/*' \
      2>/dev/null \
      | head -100 \
      | while read -r f; do
          grep -nE '^(export +(default +)?)?(async +)?(function|class|interface|type|enum|const|fn|pub +fn|pub +struct|def )' "$f" 2>/dev/null \
            | head -10 \
            | sed "s|$REPO/||; s|^|${f#$REPO/}:|"
        done \
      | head -300
    echo '```'
  } >> "$OUT" 2>/dev/null || true
  if [ "$(wc -c < "$OUT" | tr -d ' ')" -gt 200 ]; then
    head -c "$BUDGET_CHARS" "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
    exit 0
  fi
fi

# --- Tier 3: git ls-files + tree ---
write_header "git-ls-files (path-level)"
{
  echo "## Directory layout (depth 3)"
  echo ""
  echo '```'
  if command -v tree >/dev/null 2>&1; then
    tree -L 3 \
      -I 'node_modules|target|dist|build|.git|.tachikoma|__pycache__|.next|.nuxt|.cache' \
      "$REPO" 2>/dev/null \
      | head -100
  else
    find "$REPO" \
      -maxdepth 3 \
      -type d \
      -not -path '*/node_modules*' \
      -not -path '*/target*' \
      -not -path '*/dist*' \
      -not -path '*/build*' \
      -not -path '*/.git*' \
      -not -path '*/.tachikoma*' \
      -not -path '*/__pycache__*' \
      -not -path '*/.next*' \
      2>/dev/null \
      | sed "s|$REPO|.|" \
      | sort \
      | head -80
  fi
  echo '```'
  echo ""
  echo "## Files (top 200 from git ls-files)"
  echo ""
  echo '```'
  if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$REPO" ls-files 2>/dev/null \
      | grep -vE '^(node_modules|target|dist|build|\.tachikoma)' \
      | head -200
  else
    find "$REPO" \
      -type f \
      -not -path '*/node_modules/*' \
      -not -path '*/target/*' \
      -not -path '*/.git/*' \
      -not -path '*/.tachikoma/*' \
      2>/dev/null \
      | sed "s|$REPO/||" \
      | head -200
  fi
  echo '```'
} >> "$OUT"

# Enforce budget
head -c "$BUDGET_CHARS" "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
exit 0
