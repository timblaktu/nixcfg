# flake-modules/systems.nix
# System-specific configuration and utilities
#
# NOTE: Utility functions (nixpkgsFor, extractHostname) have been moved to
# modules/flake-parts/lib.nix as part of Plan 019 (dendritic pattern migration).
# Access them via: inputs.self.lib.nixpkgsFor, inputs.self.lib.extractHostname
{ inputs, ... }: {
  # Systems are defined in the main flake.nix
  # This module provides system-specific logic and utilities

  # Utility functions are now in modules/flake-parts/lib.nix
}
