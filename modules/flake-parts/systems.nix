# modules/flake-parts/systems.nix
# Supported architectures for the dendritic pattern
#
# This module:
# - Defines all supported system architectures as read-only options
# - Sets the flake-parts `systems` for perSystem evaluation
# - Provides categorized views (Linux, Darwin, etc.) for convenience
#
# Usage in other flake-parts modules:
#   { config, ... }:
#   {
#     # Access all supported systems
#     systems = config.dendriticMeta.systems.all;
#
#     # Access Linux-only systems
#     linuxSystems = config.dendriticMeta.systems.linux;
#
#     # Check if building for darwin
#     perSystem = { system, ... }:
#       lib.optionalAttrs (builtins.elem system config.dendriticMeta.systems.darwin) {
#         # Darwin-specific outputs
#       };
#   }
#
# NOTE: These options live under `dendriticMeta` (not `flake.meta`) to avoid
# creating an unknown flake output. Only `flake.*` options become flake outputs.
{ lib, ... }:
{
  options.dendriticMeta.systems = {
    all = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      readOnly = true;
      description = ''
        All supported system architectures for this flake.

        This includes all platforms where we build packages, dev shells,
        and run checks. Individual configurations may target a subset.

        Read-only: System support is defined at flake architecture level.
      '';
    };

    linux = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      readOnly = true;
      description = ''
        Linux system architectures (NixOS and standalone Home Manager).

        - x86_64-linux: WSL primary development, standard PCs
        - aarch64-linux: ARM SBCs (potato), Termux on Android

        Read-only: Derived from supported platforms.
      '';
    };

    darwin = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      readOnly = true;
      description = ''
        Darwin system architectures (macOS).

        - x86_64-darwin: Intel Macs (mbp)
        - aarch64-darwin: Apple Silicon Macs (macbook-air)

        Read-only: Derived from supported platforms.
      '';
    };

    # Host-to-system mapping for configuration builders
    hosts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        # NixOS hosts
        "thinky-nixos" = "x86_64-linux";
        "pa161878-nixos" = "x86_64-linux";
        "nixos-wsl-minimal" = "x86_64-linux";
        "nixos-wsl-tiger-team" = "x86_64-linux";
        "potato" = "aarch64-linux";
        "mbp" = "x86_64-darwin";
        "macbook-air" = "aarch64-darwin";

        # Home Manager standalone hosts
        "thinky-ubuntu" = "x86_64-linux";
      };
      readOnly = true;
      description = ''
        Mapping of hostnames to their system architecture.

        Used by configuration builders to determine the correct
        system for each host without redundant specification.

        Read-only: Host architectures are fixed hardware facts.
      '';
    };
  };

  # Set flake-parts systems from our definition
  # This enables perSystem evaluation for all supported architectures
  config.systems = [
    "x86_64-linux"
    "aarch64-linux"
    # Darwin not included in perSystem by default (most packages are Linux-only)
    # Individual modules can extend this if needed
  ];
}
