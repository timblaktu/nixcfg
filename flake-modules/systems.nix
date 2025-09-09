# flake-modules/systems.nix
# System-specific configuration and utilities
{ inputs, ... }: {
  # Systems are defined in the main flake.nix
  # This module provides system-specific logic and utilities
  
  flake = {
    # Expose utility functions for cross-system usage
    lib = {
      # Helper to get nixpkgs for a specific system with our overlays
      nixpkgsFor = system: import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          (import ../overlays)
        ];
      };
      
      # Helper to extract hostname from configuration name pattern "user@hostname"
      extractHostname = configName: 
        builtins.elemAt (inputs.nixpkgs.lib.splitString "@" configName) 1;
    };
  };
}
