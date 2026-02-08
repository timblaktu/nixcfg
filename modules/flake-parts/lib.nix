# modules/flake-parts/lib.nix
# Helper functions for creating configurations from flake.modules.*
#
# These functions provide a standardized way to create NixOS, Darwin, and
# Home Manager configurations from the dendritic flake.modules.* namespace.
#
# Simple usage (no extra options):
#   flake.nixosConfigurations = inputs.self.lib.mkNixos "x86_64-linux" "thinky-nixos";
#   flake.homeConfigurations = inputs.self.lib.mkHomeManager "x86_64-linux" "tim@thinky-nixos";
#
# Advanced usage (with extra options):
#   flake.nixosConfigurations = inputs.self.lib.mkNixosWithArgs "x86_64-linux" "thinky-nixos" {
#     extraModules = [ ./hardware-quirks.nix ];
#     extraSpecialArgs = { wslHostname = "thinky-nixos"; };
#   };
#
# Each helper:
# - Looks up the module from config.flake.modules.{nixos,darwin,homeManager}.<name>
# - Applies common defaults (nixpkgs config, specialArgs)
# - Returns an attrset suitable for merging into flake.*Configurations
{ lib, config, inputs, withSystem, ... }:
let
  # === Utilities (migrated from flake-modules/systems.nix) ===

  # Helper to get nixpkgs for a specific system with our overlays
  nixpkgsFor = system: import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [
      (import ../../overlays { inherit inputs; })
    ];
  };

  # Helper to extract hostname from configuration name pattern "user@hostname"
  extractHostname = configName:
    builtins.elemAt (lib.splitString "@" configName) 1;

  # === Configuration Builders ===

  # Internal implementation with all options
  mkNixosImpl = system: name: { extraModules ? [ ]
                              , extraSpecialArgs ? { }
                              ,
                              }: {
    ${name} = withSystem system ({ pkgs, ... }:
      inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          { nixpkgs.config.allowUnfree = true; }
          config.flake.modules.nixos.${name}
        ] ++ extraModules;
        specialArgs = {
          inherit inputs;
          inherit (inputs) nixpkgs-stable;
        } // extraSpecialArgs;
      }
    );
  };

  mkDarwinImpl = system: name: { extraModules ? [ ]
                               , extraSpecialArgs ? { }
                               ,
                               }: {
    ${name} = withSystem system ({ pkgs, ... }:
      inputs.darwin.lib.darwinSystem {
        inherit system;
        modules = [
          { nixpkgs.config.allowUnfree = true; }
          config.flake.modules.darwin.${name}
          inputs.sops-nix.darwinModules.sops
        ] ++ extraModules;
        specialArgs = {
          inherit inputs;
          inherit (inputs) nixpkgs-stable;
        } // extraSpecialArgs;
      }
    );
  };

  mkHomeManagerImpl = system: name: { extraModules ? [ ]
                                    , extraSpecialArgs ? { }
                                    , useWslVariant ? false
                                    ,
                                    }:
    let
      hmInput = if useWslVariant then inputs.home-manager-wsl else inputs.home-manager;
    in
    {
      ${name} = withSystem system ({ pkgs, ... }:
        hmInput.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            config.flake.modules.homeManager.${name}
          ] ++ extraModules;
          extraSpecialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
          } // extraSpecialArgs;
        }
      );
    };
in
{
  flake.lib = {
    # === Utilities ===

    # Helper to get nixpkgs for a specific system with our overlays
    inherit nixpkgsFor;

    # Helper to extract hostname from configuration name pattern "user@hostname"
    inherit extractHostname;

    # === Configuration Builders ===

    # mkNixos: Create a NixOS configuration from flake.modules.nixos.<name>
    # Simple 2-argument form uses defaults for all options.
    #
    # Arguments:
    #   system: Architecture (e.g., "x86_64-linux", "aarch64-linux")
    #   name: Configuration name matching flake.modules.nixos.<name>
    #
    # Returns: { <name> = <nixosConfiguration>; }
    mkNixos = system: name: mkNixosImpl system name { };

    # mkNixosWithArgs: Create a NixOS configuration with extra options
    #
    # Arguments:
    #   system: Architecture (e.g., "x86_64-linux", "aarch64-linux")
    #   name: Configuration name matching flake.modules.nixos.<name>
    #   args: {
    #     extraModules?: List of additional modules to include
    #     extraSpecialArgs?: Additional specialArgs to pass to modules
    #   }
    #
    # Returns: { <name> = <nixosConfiguration>; }
    mkNixosWithArgs = mkNixosImpl;

    # mkDarwin: Create a Darwin configuration from flake.modules.darwin.<name>
    # Simple 2-argument form uses defaults for all options.
    #
    # Arguments:
    #   system: Architecture (e.g., "aarch64-darwin", "x86_64-darwin")
    #   name: Configuration name matching flake.modules.darwin.<name>
    #
    # Returns: { <name> = <darwinConfiguration>; }
    mkDarwin = system: name: mkDarwinImpl system name { };

    # mkDarwinWithArgs: Create a Darwin configuration with extra options
    #
    # Arguments:
    #   system: Architecture (e.g., "aarch64-darwin", "x86_64-darwin")
    #   name: Configuration name matching flake.modules.darwin.<name>
    #   args: {
    #     extraModules?: List of additional modules to include
    #     extraSpecialArgs?: Additional specialArgs to pass to modules
    #   }
    #
    # Returns: { <name> = <darwinConfiguration>; }
    mkDarwinWithArgs = mkDarwinImpl;

    # mkHomeManager: Create a Home Manager configuration from flake.modules.homeManager.<name>
    # Simple 2-argument form uses defaults for all options.
    #
    # Arguments:
    #   system: Architecture (e.g., "x86_64-linux", "aarch64-linux")
    #   name: Configuration name matching flake.modules.homeManager.<name> (typically "user@host")
    #
    # Returns: { <name> = <homeManagerConfiguration>; }
    mkHomeManager = system: name: mkHomeManagerImpl system name { };

    # mkHomeManagerWithArgs: Create a Home Manager configuration with extra options
    #
    # Arguments:
    #   system: Architecture (e.g., "x86_64-linux", "aarch64-linux")
    #   name: Configuration name matching flake.modules.homeManager.<name>
    #   args: {
    #     extraModules?: List of additional modules to include
    #     extraSpecialArgs?: Additional specialArgs to pass to modules
    #     useWslVariant?: Use home-manager-wsl input (for WSL-specific features like windows-terminal)
    #   }
    #
    # Returns: { <name> = <homeManagerConfiguration>; }
    mkHomeManagerWithArgs = mkHomeManagerImpl;
  };
}
