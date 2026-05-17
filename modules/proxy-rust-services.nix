# modules/proxy-rust-services.nix
#
# Builds proxy-daemon, proxy CLI, and proxy-voice from the cargo workspace at
# ~/Projects/tachikoma-starter/ using crane + sccache, and manages
# com.proxy.daemon / com.proxy.voice as LaunchAgents via home-manager's
# launchd.agents.*. MacBook-Pro-2 only (workspace path is hardcoded).
#
# crane is fetched inline via pkgs.fetchFromGitHub at the rev pinned in
# flake.lock (github:ipetkov/crane/v0.20.2 → 60202a2e…). The flake input
# entry in flake.nix serves as the canonical version record.
#
# First rebuild: cold cargo build of the full workspace takes 5-30 min.
# Subsequent rebuilds reuse Nix-store-cached cargoArtifacts + sccache hits,
# typically finishing in seconds.
{ config, pkgs, lib, ... }:

let
  # --- crane setup -------------------------------------------------------
  # Pinned to the same rev recorded in flake.lock: 60202a2e (v0.20.2).
  craneSource = pkgs.fetchFromGitHub {
    owner = "ipetkov";
    repo = "crane";
    rev = "60202a2e3597a3d91f5e791aab03f45470a738b5";
    hash = "sha256-fnyETBKSVRa5abjOiRG/IAzKZq5yX8U6oRrHstPl4VM=";
  };
  # crane's default.nix: { pkgs ? … }: pkgs.callPackage ./lib {}
  # — returns the craneLib attrset directly.
  craneLib = import craneSource { inherit pkgs; };

  # --- workspace source --------------------------------------------------
  # Absolute path; evaluation requires --impure (dev-environment already
  # passes --impure via setup.sh). cleanCargoSource excludes target/, .git/,
  # node_modules/, and all non-Rust files so the nix store copy stays lean.
  workspaceSrc = craneLib.cleanCargoSource /Users/pioneer/Projects/tachikoma-starter;

  # --- native build inputs -----------------------------------------------
  # proxy-voice needs cmake (whisper.cpp via whisper-rs) and CoreAudio (cpal).
  # proxy-daemon is pure Rust (rustls TLS — no libpq needed) but shares
  # cargoArtifacts with voice, so native deps apply to the common dep build.
  # bindgenHook: whisper-rs-sys uses bindgen to generate C bindings for
  # whisper.cpp; this hook sets LIBCLANG_PATH so bindgen finds libclang.
  nativeBuildInputs = with pkgs; [ cmake pkg-config rustPlatform.bindgenHook ];
  buildInputs = with pkgs.darwin.apple_sdk.frameworks; [
    CoreAudio
    AudioToolbox
    CoreFoundation
    Security
  ];

  # sccache wrapper — sandbox is false on this machine so sccache can reach
  # ~/Library/Caches/sccache/ during the nix build.
  sccacheBin = "${pkgs.sccache}/bin/sccache";

  # --- build all workspace deps once -------------------------------------
  # Nix caches this derivation by input hash; changing only app code
  # (daemon/src/*.rs) does NOT invalidate cargoArtifacts → rebuild is fast.
  cargoArtifacts = craneLib.buildDepsOnly {
    src = workspaceSrc;
    inherit nativeBuildInputs buildInputs;
    RUSTC_WRAPPER = sccacheBin;
  };

  # --- per-binary packages -----------------------------------------------
  proxy-daemon-pkg = craneLib.buildPackage {
    src = workspaceSrc;
    inherit cargoArtifacts nativeBuildInputs buildInputs;
    cargoExtraArgs = "--bin proxy-daemon";
    RUSTC_WRAPPER = sccacheBin;
  };

  proxy-voice-pkg = craneLib.buildPackage {
    src = workspaceSrc;
    inherit cargoArtifacts nativeBuildInputs buildInputs;
    cargoExtraArgs = "--bin proxy-voice";
    RUSTC_WRAPPER = sccacheBin;
  };

  # proxy CLI is proxy-daemon under a friendlier name (symlink, as in
  # the hand-install: ~/.local/bin/proxy → proxy-daemon).
  proxy-cli-pkg = pkgs.runCommand "proxy-cli" { } ''
    mkdir -p $out/bin
    ln -s ${proxy-daemon-pkg}/bin/proxy-daemon $out/bin/proxy
  '';

  homeDir = config.home.homeDirectory;
in
{
  # Install all three binaries into ~/.nix-profile/bin/
  home.packages = [ proxy-daemon-pkg proxy-voice-pkg proxy-cli-pkg ];

  # ------------------------------------------------------------------
  # com.proxy.daemon — persistent scheduler + admission brain
  # ------------------------------------------------------------------
  launchd.agents.proxy-daemon = {
    enable = true;
    config = {
      Label = "com.proxy.daemon";
      ProgramArguments = [ "${proxy-daemon-pkg}/bin/proxy-daemon" "run" ];
      RunAtLoad = true;
      KeepAlive = { SuccessfulExit = false; };
      ProcessType = "Background";
      StandardOutPath = "${homeDir}/Library/Logs/proxy-daemon.out.log";
      StandardErrorPath = "${homeDir}/Library/Logs/proxy-daemon.err.log";
      EnvironmentVariables = {
        RUST_LOG = "info,proxy_daemon=debug";
        # Include nix profile on PATH so the daemon can resolve helper binaries.
        PATH = "${homeDir}/.nix-profile/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      ThrottleInterval = 10;
    };
  };

  # ------------------------------------------------------------------
  # com.proxy.voice — wake-word + STT + audio capture daemon
  # ------------------------------------------------------------------
  launchd.agents.proxy-voice = {
    enable = true;
    config = {
      Label = "com.proxy.voice";
      ProgramArguments = [ "${proxy-voice-pkg}/bin/proxy-voice" ];
      RunAtLoad = true;
      KeepAlive = { SuccessfulExit = false; };
      ProcessType = "Interactive";
      StandardOutPath = "${homeDir}/Library/Logs/proxy-voice.log";
      StandardErrorPath = "${homeDir}/Library/Logs/proxy-voice.log";
      EnvironmentVariables = {
        RUST_LOG = "info";
        PROXY_DATABASE_URL = "postgres://proxy:proxy@localhost:5432/proxy";
      };
      ThrottleInterval = 10;
    };
  };

  # ------------------------------------------------------------------
  # Cleanup: remove hand-installed binaries and old plists so nix owns
  # them exclusively after the first rebuild.
  #
  # Runs BEFORE writeBoundary so home-manager writes the new plists into
  # a clean slate (no .backup files created by the collision handler).
  # ------------------------------------------------------------------
  home.activation.cleanupHandInstalledProxyServices =
    lib.hm.dag.entryBefore [ "writeBoundary" ] ''
      # Bootout and remove any old hand-placed LaunchAgent plists so the
      # nix-written plists (com.proxy.daemon / com.proxy.voice) take over
      # cleanly on first activation.
      for label in "com.proxy.daemon" "com.proxy.voice"; do
        old_plist="$HOME/Library/LaunchAgents/$label.plist"
        if [ -f "$old_plist" ]; then
          echo "personal-nix: booting out $label (plist will be rewritten by nix)"
          launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
          rm -f "$old_plist"
        fi
      done

      # Remove hand-installed binaries from ~/.local/bin/ — these are now
      # provided by ~/.nix-profile/bin/ after home.packages installs them.
      for f in \
        "$HOME/.local/bin/proxy" \
        "$HOME/.local/bin/proxy-daemon" \
        "$HOME/.local/bin/proxy-voice"; do
        if [ -e "$f" ] || [ -L "$f" ]; then
          echo "personal-nix: removing hand-installed $f (now managed by nix)"
          rm -f "$f"
        fi
      done
    '';
}
