{
  description = "Unified Nix configuration for all systems";

  inputs = {
    # MAIN NIXPKGS - upstream, used for 99% of packages
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";

    # CUSTOM NIXPKGS - isolated inputs for packages needing specific fixes
    # Temporary: Only for docling-parse until PR #184 merges upstream
    nixpkgs-docling.url = "github:timblaktu/nixpkgs/docling-parse-fix";
    # nixpkgs-docling.url = "git+file:///home/tim/src/nixpkgs?ref=docling-parse-fix&shallow=true";  # For local dev

    # For nixvim (needs postgres-lsp and other recent packages)
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # flake-parts for modular flake organization
    flake-parts.url = "github:hercules-ci/flake-parts";

    nixvim = {
      url = "github:nix-community/nixvim";
      # Use nixpkgs-unstable which has postgres-lsp and other packages
      # that NixVim's LSP server definitions require
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # HOME-MANAGER - upstream for non-WSL hosts
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # HOME-MANAGER CUSTOM - WSL-specific fork for windows-terminal feature (WIP)
    # home-manager-wsl.url = "github:timblaktu/home-manager/wsl-windows-terminal";  # Use after pushing branch
    home-manager-wsl.url = "git+file:///home/tim/src/home-manager?ref=wsl-windows-terminal";  # For local dev
    home-manager-wsl.inputs.nixpkgs.follows = "nixpkgs";

    # NIXOS-WSL - custom fork for plugin-shim-integration (WIP)
    nixos-wsl.url = "github:timblaktu/NixOS-WSL/plugin-shim-integration";
    # nixos-wsl.url = "github:timblaktu/NixOS-WSL/feature/bare-mount-support";
    # nixos-wsl.url = "git+file:///home/tim/src/NixOS-WSL";  # For local dev
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

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
        # Configure nixpkgs for this system (now uses upstream nixpkgs)
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            (import ./overlays { inherit inputs; })
          ];
        };
      };
    };
}
