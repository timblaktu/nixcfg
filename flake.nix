{
  description = "Unified Nix configuration for all systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    
    # flake-parts for modular flake organization
    flake-parts.url = "github:hercules-ci/flake-parts";
    
    nixvim = {
      url = "github:nix-community/nixvim/fef045cb912e51185d0d5d67e035eca7fea7eda4";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "git+file:///home/tim/src/home-manager?ref=feature-test-with-fcitx5-fix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    nixos-wsl.url = "github:timblaktu/NixOS-WSL/feature/bare-mount-support";
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    sops-nix.url = "github:Mic92/sops-nix";
    flake-utils.url = "github:numtide/flake-utils";

    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    nixpkgs-esp-dev = {
      url = "github:timblaktu/nixpkgs-esp-dev/c5";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    
    nix-writers.url = "github:timblaktu/nix-writers";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # Import our modular flake structure
      imports = [
        ./flake-modules/systems.nix
        ./flake-modules/overlays.nix
        ./flake-modules/packages.nix
        ./flake-modules/dev-shells.nix
        ./flake-modules/nixos-configurations.nix
        ./flake-modules/darwin-configurations.nix
        ./flake-modules/home-configurations.nix
        ./flake-modules/tests.nix  # All checks and tests consolidated here
      ];

      # Support these systems across all modules
      systems = [ 
        "x86_64-linux" 
      ];
      
      # Per-system configuration
      perSystem = { config, self', inputs', pkgs, system, ... }: {
        # Configure nixpkgs for this system
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            (import ./overlays)
          ];
        };
      };
    };
}
