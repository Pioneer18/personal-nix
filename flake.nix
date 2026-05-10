{
  description = "Pioneer18 personal nix substrate (Claude Code + CLI + dotfiles)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, ... }: {
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
