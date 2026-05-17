{
  description = "Pioneer18 personal nix substrate (Claude Code + CLI + dotfiles)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # Rust build tool — used by modules/proxy-rust-services.nix to build the
    # proxy-daemon/proxy/proxy-voice cargo workspace via crane. The module
    # fetches crane inline via pkgs.fetchFromGitHub at the same rev pinned
    # here so the lock file remains the single source of truth for the pin.
    crane.url = "github:ipetkov/crane/v0.20.2";
  };

  outputs = { self, nixpkgs, home-manager, crane, ... }: {
    # Importable home-manager module — consumed by:
    #   - RelyMD team's gitignored local slot (imports = [ ~/projects/personal-nix ])
    #   - Standalone home-manager flakes on non-RelyMD Macs
    homeModules.default = import ./default.nix;

    # Shorthand for the module so consumers can do:
    #   imports = [ inputs.personal-nix.homeModule ];
    homeModule = import ./default.nix;

    # TODO: add a standaloneConfigurations.<host> entry for non-RelyMD Macs
    # when needed. Sketch:
    #   standaloneConfigurations.someHost = home-manager.lib.homeManagerConfiguration {
    #     pkgs = nixpkgs.legacyPackages.aarch64-darwin;
    #     modules = [ ./default.nix ];
    #   };
  };
}
