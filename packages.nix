# Personal CLI packages.
# Only add things NOT already in modules/home/team.nix to avoid duplication.
# Team already provides: ripgrep, fd, fzf, jq, gh, git, vim, htop, tree, etc.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Mac-native automation
    switchaudio-osx     # change audio input/output devices from CLI
    mas                 # Mac App Store CLI (install, update, list)
    # NOTE: displayplacer is brew-only (not in nixpkgs). If you want it,
    # add `displayplacer` to homebrew.brews in hosts/jonathan-sells-darwin.nix.

    # Convenience
    just                # task runner (per-project Justfile)
    lazygit             # git TUI
    yq-go               # like jq, for YAML

    # Add more here as you discover needs. Keep this list small and
    # additive — every entry slows rebuilds slightly.
  ];
}
