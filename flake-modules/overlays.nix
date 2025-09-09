# flake-modules/overlays.nix
# Package overlays and customizations
{ inputs, ... }: {
  perSystem = { pkgs, ... }: {
    # System-specific overlay applications are handled in main flake.nix
    # This module provides overlay-related packages and utilities
  };

  flake = {
    # Export overlays for other flakes to use
    overlays = {
      default = import ../overlays;
    };
  };
}
