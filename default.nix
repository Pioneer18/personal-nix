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
    ./modules/proxy-rust-services.nix
    ./modules/proxy-boot.nix
  ];

  programs.zsh.shellAliases = {
    proxy-shell = "$HOME/.local/bin/proxy-shell";
  };

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

  # Sync claude's auto-memory directory to iCloud Drive so memory follows
  # the user across all their Macs. Idempotent — safe to re-run.
  # v3 agentic-shell slice shell-13 — see:
  #   ~/projects/personal-nix/wiki/decisions/agentic-shell-4-tier-state.md
  home.activation.syncMemoryToiCloud =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      REPO="${repoPath}"
      if [ -x "$REPO/scripts/sync-memory.sh" ]; then
        "$REPO/scripts/sync-memory.sh" \
          || echo "personal-nix: sync-memory.sh reported a warning (non-fatal)"
      fi
    '';

  home.activation.writeProxyShellScript =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.local/bin"
      cat > "$HOME/.local/bin/proxy-tmux" << 'WRAPPER'
#!/bin/sh
exec /etc/profiles/per-user/pioneer/bin/tmux attach -t proxy
WRAPPER
      chmod +x "$HOME/.local/bin/proxy-tmux"
      cat > "$HOME/.local/bin/proxy-shell" << 'WRAPPER'
#!/bin/bash
/usr/bin/open -na Ghostty --args --config-file="$HOME/.config/ghostty/proxy.config"
WRAPPER
      chmod +x "$HOME/.local/bin/proxy-shell"
    '';

  home.activation.buildTachikomaUI =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      TACHIKOMA_UI="$HOME/projects/personal-nix/mcps/tachikoma-ui"
      if [ -d "$TACHIKOMA_UI" ]; then
        echo "personal-nix: building tachikoma-ui..."
        cd "$TACHIKOMA_UI"
        npm install --quiet 2>/dev/null || echo "personal-nix: npm install failed (non-fatal)"
        npm run build 2>/dev/null || echo "personal-nix: npm run build failed (non-fatal)"
      fi
    '';

  home.activation.writeTachikomaUILauncher =
    lib.hm.dag.entryAfter [ "writeBoundary" "buildTachikomaUI" ] ''
      mkdir -p "$HOME/.local/bin"

      cat > "$HOME/.local/bin/tachikoma-ui-start" << 'WRAPPER'
#!/bin/bash
set -a
[ -f "$HOME/.secrets" ] && . "$HOME/.secrets"
set +a
exec ${pkgs.nodejs_22}/bin/node --experimental-strip-types \
  "$HOME/projects/personal-nix/mcps/tachikoma-ui/server/index.ts"
WRAPPER
      chmod +x "$HOME/.local/bin/tachikoma-ui-start"

      cat > "$HOME/.local/bin/tachikoma-ui-stop" << 'STOP'
#!/bin/bash
launchctl bootout "gui/$(id -u)/org.nix-community.home.tachikoma-ui" 2>/dev/null && echo "tachikoma-ui stopped" || echo "tachikoma-ui was not running"
STOP
      chmod +x "$HOME/.local/bin/tachikoma-ui-stop"

      cat > "$HOME/.local/bin/tachikoma-ui-restart" << 'RESTART'
#!/bin/bash
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.tachikoma-ui" 2>/dev/null && echo "tachikoma-ui restarted" || echo "tachikoma-ui not found in launchd — run: dev"
RESTART
      chmod +x "$HOME/.local/bin/tachikoma-ui-restart"
    '';

  # Configure SwiftBar to use our versioned plugin directory, and ensure all
  # plugin scripts are executable. Idempotent — safe to re-run on every rebuild.
  home.activation.setupSwiftBar =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      SWIFTBAR_PLUGINS="${repoPath}/swiftbar"
      if [ -d "$SWIFTBAR_PLUGINS" ]; then
        chmod +x "$SWIFTBAR_PLUGINS"/*.sh 2>/dev/null || true
        /usr/bin/defaults write com.ameba.SwiftBar PluginDirectory "$SWIFTBAR_PLUGINS" 2>/dev/null || true
      fi
    '';

  launchd.agents.tachikoma-ui = {
    enable = true;
    config = {
      ProgramArguments = [ "${config.home.homeDirectory}/.local/bin/tachikoma-ui-start" ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/tachikoma-ui.log";
      StandardErrorPath = "/tmp/tachikoma-ui.log";
    };
  };
}
