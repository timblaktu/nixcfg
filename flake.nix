{
  description = "Unified Nix configuration for all systems";

  inputs = {
    nixpkgs.url = "github:timblaktu/nixpkgs/writers-auto-detection";
    # nixpkgs.url = "git+file:///home/tim/src/nixpkgs?ref=writers-auto-detection";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    # nixpkgs-unstable for nixvim (has postgres-lsp and other recent packages)
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # flake-parts for modular flake organization
    flake-parts.url = "github:hercules-ci/flake-parts";

    nixvim = {
      url = "github:nix-community/nixvim";
      # Use nixpkgs-unstable which has postgres-lsp and other packages
      # that NixVim's LSP server definitions require
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    home-manager = {
      url = "github:timblaktu/home-manager/feature-test-with-fcitx5-fix";
      # url = "git+file:///home/tim/src/home-manager?ref=feature-test-with-fcitx5-fix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:timblaktu/NixOS-WSL/plugin-shim-integration";
      # url = "github:timblaktu/NixOS-WSL/feature/bare-mount-support";
      # url = "git+file:///home/tim/src/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
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
        ./flake-modules/tests.nix # All checks and tests consolidated here
        ./flake-modules/github-actions.nix # Configurable GitHub Actions validation
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
