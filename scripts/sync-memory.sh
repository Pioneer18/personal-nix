#!/usr/bin/env bash
# sync-memory.sh — relocate claude's auto-memory directory to iCloud Drive
# so memory follows the user across all their Macs.
#
# Idempotent — safe to re-run on every `dev`:
#   - If memory is already a symlink to iCloud: no-op.
#   - If memory is a real dir and iCloud target is empty: move contents in, then symlink.
#   - If memory is a real dir and iCloud target has contents: preserve iCloud, warn.
#   - If memory dir doesn't exist yet: just create the symlink (claude will populate on first save).
#
# See: ~/projects/personal-nix/wiki/decisions/agentic-shell-4-tier-state.md
# See: ~/projects/personal-nix/wiki/work-requests/shell-13-memory-icloud-sync.md

set -e

# Path Claude Code expects (per ~/.claude/projects/<project-slug>/memory/ convention)
MEM_DIR="$HOME/.claude/projects/-Users-pioneer/memory"

# iCloud Drive target — `com~apple~CloudDocs` is the canonical iCloud Drive path
ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/.claude-memory"

# Step 1: If memory dir is already a symlink to iCloud, we're done
if [ -L "$MEM_DIR" ]; then
  target=$(readlink "$MEM_DIR")
  if [ "$target" = "$ICLOUD_DIR" ]; then
    exit 0
  fi
fi

# Step 2: Ensure iCloud target exists
mkdir -p "$ICLOUD_DIR"

# Step 3: If memory dir is a real (non-symlink) directory with contents, migrate
if [ -d "$MEM_DIR" ] && [ ! -L "$MEM_DIR" ]; then
  if [ -n "$(ls -A "$MEM_DIR" 2>/dev/null)" ]; then
    if [ -z "$(ls -A "$ICLOUD_DIR" 2>/dev/null)" ]; then
      # iCloud target empty → migrate local contents in
      cp -p -R "$MEM_DIR"/. "$ICLOUD_DIR/" 2>/dev/null || true
      echo "personal-nix: migrated memory contents to iCloud Drive"
    else
      # iCloud target already populated (likely from another Mac)
      # Preserve iCloud as authoritative; back up local copy aside
      backup_dir="$HOME/.claude/projects/-Users-pioneer/memory.local-backup-$(date +%Y%m%d-%H%M%S)"
      mv "$MEM_DIR" "$backup_dir"
      echo "personal-nix: iCloud already had memory; local copy moved to $backup_dir for safety"
    fi
  fi

  # Remove the original directory if it still exists (and is not the backup we just made)
  if [ -d "$MEM_DIR" ] && [ ! -L "$MEM_DIR" ]; then
    rm -rf "$MEM_DIR"
  fi
fi

# Step 4: Ensure parent dir for symlink exists
mkdir -p "$(dirname "$MEM_DIR")"

# Step 5: Create the symlink (idempotent — `-n` doesn't follow if target is a symlink)
ln -sfn "$ICLOUD_DIR" "$MEM_DIR"

echo "personal-nix: ~/.claude/projects/-Users-pioneer/memory → $ICLOUD_DIR"
