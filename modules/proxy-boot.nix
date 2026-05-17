# modules/proxy-boot.nix
#
# LaunchAgent that opens Ghostty (with the proxy config) at user login.
# Ghostty's config handles tmux + fullscreen — zero Accessibility prompts needed.
#
# This is M1 of the agentic shell — see:
#   - ~/projects/personal-nix/wiki/work-requests/shell-01-boot-launchagent.md
#   - ~/Projects/tachikoma-starter/docs/ARCHITECTURE.md § 21
#
# To disable: remove `./modules/proxy-boot.nix` from default.nix imports.
{ config, pkgs, lib, ... }:
{
  launchd.agents.proxy-boot = {
    enable = true;
    config = {
      Label = "com.proxy.boot";
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "${config.home.homeDirectory}/projects/personal-nix/scripts/proxy-boot.sh"
      ];
      RunAtLoad = true;
      KeepAlive = false;
      StandardOutPath = "/tmp/proxy-boot.log";
      StandardErrorPath = "/tmp/proxy-boot.log";
    };
  };

  # Ghostty config for the PROXY session. Invoked when proxy-boot.sh runs
  # `open -na Ghostty --args --config-file=...`. Separate from any default
  # Ghostty config so regular Ghostty windows don't auto-launch tmux or
  # go fullscreen.
  home.file.".config/ghostty/proxy.config".text = ''
    # PROXY session config (loaded only when launched via --config-file)
    # Launches proxy-tmux-launcher.sh which exec's tmux as a login shell.
    command = ${config.home.homeDirectory}/projects/personal-nix/scripts/proxy-tmux-launcher.sh

    # Fullscreen on launch. `fullscreen = true` alone is flaky when Ghostty
    # is already running (only fires on cold start); non-native fullscreen
    # applies reliably on every new window. visible-menu keeps the menu bar
    # accessible.
    fullscreen = true
    macos-non-native-fullscreen = visible-menu

    # Quality-of-life
    confirm-close-surface = false
    macos-titlebar-style = hidden
  '';

  # Global tmux config. Sets up the status bar with placeholder PROXY segments
  # that read from /tmp/proxy-*. Voice daemon (shell-04) and PROXY daemon (M3)
  # will populate those files; until then, the status bar shows defaults.
  home.file.".tmux.conf".text = ''
    # Faster status refresh so PROXY state updates feel live
    set -g status-interval 2

    # Sensible defaults
    set -g mouse on
    set -g mode-keys vi
    set -s escape-time 0
    set -g history-limit 50000
    set -g base-index 0
    setw -g pane-base-index 0

    # Status bar layout
    set -g status-position bottom
    set -g status-style "bg=default fg=default"
    set -g status-left-length 30
    set -g status-right-length 100

    set -g status-left "[#S] "

    # PROXY segments: read /tmp files written by daemons. Fallbacks show defaults
    # until shell-04 (voice) and M3 (queue + sensor) land.
    set -g status-right "#(cat /tmp/proxy-voice-mode 2>/dev/null || echo 'mode: pending') | #(cat /tmp/proxy-queue 2>/dev/null || echo 'queue: -') | #(cat /tmp/proxy-pressure 2>/dev/null || echo 'pressure: -') | %H:%M"
  '';
}
