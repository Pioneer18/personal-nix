#!/usr/bin/env bash
# Symlink personal-nix/skills/* into ~/.claude/skills/.
# This is duplicated by home.activation.symlinkPersonalSkills in default.nix —
# this script is here so you can run it standalone (e.g. for testing) without
# a full nix rebuild.
set -euo pipefail

REPO="${PERSONAL_NIX_REPO:-$HOME/projects/personal-nix}"
CLAUDE_SKILLS="$HOME/.claude/skills"

mkdir -p "$CLAUDE_SKILLS"

if [ ! -d "$REPO/skills" ]; then
  echo "No skills directory at $REPO/skills"
  exit 0
fi

linked=0
skipped=0
for skill_dir in "$REPO/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  name=$(basename "$skill_dir")
  target="$CLAUDE_SKILLS/$name"
  if [ -L "$target" ] || [ ! -e "$target" ]; then
    ln -sfn "$skill_dir" "$target"
    echo "  ✓ $name → $skill_dir"
    linked=$((linked + 1))
  else
    echo "  ! skip $name (real directory exists at $target)"
    skipped=$((skipped + 1))
  fi
done

echo "→ Linked $linked, skipped $skipped"
