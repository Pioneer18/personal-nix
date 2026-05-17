# Personal CLI packages.
# Only add things NOT already in modules/home/team.nix to avoid duplication.
# Team already provides: ripgrep, fd, fzf, jq, gh, git, vim, htop, tree, etc.
{ pkgs, ... }:

let
  codexVersion = "0.130.0";
  codexPlatform = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-vFCkt/mgyMqZF5GJ5GWbYBEHgwdw4hVH3Awka85zNXc=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      hash = "sha256-/t2xFr2W19g/i7GbNPur5oQ8xkRhuvLknAF+EgatXmc=";
    };
  }.${pkgs.stdenv.hostPlatform.system} or (throw "codex ${codexVersion} is not pinned for ${pkgs.stdenv.hostPlatform.system}");

  codexPinned = pkgs.stdenvNoCC.mkDerivation {
    pname = "codex";
    version = codexVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-${codexPlatform.target}.tar.gz";
      hash = codexPlatform.hash;
    };
    sourceRoot = ".";
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      install -m755 "codex-${codexPlatform.target}" "$out/bin/codex"
      runHook postInstall
    '';
  };
in
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
    codexPinned         # OpenAI Codex CLI
    tmux                # terminal multiplexer — used by PROXY boot integration (shell-01/02)

    # MCP servers (binaries referenced by mcp.nix)
    github-mcp-server   # GitHub's official MCP server (richer than @modelcontextprotocol/server-github)

    # Rust development — for tachikoma-starter daemon/ + voice/ crates
    rustup                # manages rustc + cargo on PATH; run `rustup default stable` once after dev
    cmake                 # C++ build dep for whisper-rs-sys (whisper.cpp)

    # Add more here as you discover needs. Keep this list small and
    # additive — every entry slows rebuilds slightly.
  ];
}
