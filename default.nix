# Pioneer18 personal home-manager module.
# Entry point — imports packages, MCP server config, and registers activation
# scripts for skill symlinks and Keychain-backed secrets.
{ config, pkgs, lib, ... }:

let
  # Live working-tree path. Symlinks point here (not at the nix-store copy)
  # so editing skills/ doesn't require a rebuild.
  repoPath = "$HOME/projects/personal-nix";
in {
  imports = [
    ./packages.nix
    ./mcp.nix
  ];

  # Symlink personal skills/ entries into ~/.claude/skills/.
  # Idempotent. Will not clobber a real directory at the same name (e.g.
  # team-installed skills like managing-this-computer).
  home.activation.symlinkPersonalSkills =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      REPO="${repoPath}"
      CLAUDE_SKILLS="$HOME/.claude/skills"
      mkdir -p "$CLAUDE_SKILLS"
      if [ -d "$REPO/skills" ]; then
        for skill_dir in "$REPO/skills"/*/; do
          [ -d "$skill_dir" ] || continue
          name=$(basename "$skill_dir")
          target="$CLAUDE_SKILLS/$name"
          if [ -L "$target" ] || [ ! -e "$target" ]; then
            ln -sfn "$skill_dir" "$target"
          else
            echo "personal-nix: skip skill '$name' (real directory exists)"
          fi
        done
      fi
    '';

  # Regenerate ~/.secrets from macOS Keychain on every rebuild.
  # Failure is non-fatal — if Keychain entries are missing on first run, the
  # warning tells the user how to populate them.
  home.activation.secretsFromKeychain =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      REPO="${repoPath}"
      if [ -x "$REPO/scripts/secrets-from-keychain.sh" ]; then
        "$REPO/scripts/secrets-from-keychain.sh" \
          || echo "personal-nix: secrets-from-keychain.sh reported missing items (see warnings above)"
      fi
    '';
}
