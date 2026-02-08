# modules/system/types/1-minimal/minimal.nix
# Minimal system configuration layer [ND]
#
# Provides:
#   flake.modules.nixos.system-minimal - Absolute minimum NixOS configuration
#   flake.modules.darwin.system-minimal - Absolute minimum Darwin configuration
#
# This is the base layer that ALL systems inherit from. It contains:
#   - Nix flakes and experimental features
#   - Store optimization
#   - Garbage collection
#   - Trusted users (wheel group)
#   - State version handling
#
# Does NOT include:
#   - User creation (2-default)
#   - Home Manager integration (2-default)
#   - SSH, networking (3-cli)
#   - Desktop environments (4-desktop)
#
# Usage in host config:
#   imports = [ inputs.self.modules.nixos.system-minimal ];
#
# Or compose with higher layers:
#   imports = [ inputs.self.modules.nixos.system-cli ];  # inherits minimal -> default -> cli
{ config, lib, pkgs, ... }:
{
  flake.modules = {
    # === NixOS Minimal Module ===
    nixos.system-minimal = { config, lib, pkgs, ... }: {
      # Core Nix configuration - required for any modern NixOS system
      nix = {
        package = lib.mkDefault pkgs.nixVersions.stable;

        settings = {
          # Enable modern Nix features (flakes, nix command)
          experimental-features = [ "nix-command" "flakes" ];

          # Optimize store to save disk space
          auto-optimise-store = lib.mkDefault true;

          # Trust wheel group for binary cache operations
          trusted-users = [ "root" "@wheel" ];

          # Suppress warnings about dirty git trees
          warn-dirty = false;

          # Increase download buffer for large fetches
          download-buffer-size = lib.mkDefault 134217728; # 128 MB
        };

        # Automatic garbage collection with sensible defaults
        gc = {
          automatic = lib.mkDefault true;
          dates = lib.mkDefault "weekly";
          options = lib.mkDefault "--delete-older-than 30d";
        };
      };

      # Binary cache configuration for faster builds
      nix.settings = {
        substituters = lib.mkDefault [
          "https://cache.nixos.org/"
          "https://nix-community.cachix.org"
        ];
        trusted-public-keys = lib.mkDefault [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
        # Cache narinfo for 24 hours
        narinfo-cache-positive-ttl = lib.mkDefault 86400;
        connect-timeout = lib.mkDefault 10;
      };

      # Minimal system packages - just enough to bootstrap
      environment.systemPackages = with pkgs; [
        vim # Basic editor for emergency recovery
        git # Required for flake operations
      ];

      # System state version - should be overridden by host
      # Default to current stable; hosts should pin their version
      system.stateVersion = lib.mkDefault "24.11";
    };

    # === Darwin Minimal Module ===
    darwin.system-minimal = { config, lib, pkgs, ... }: {
      # Core Nix configuration - required for any modern Darwin system
      nix = {
        package = lib.mkDefault pkgs.nixVersions.stable;

        settings = {
          # Enable modern Nix features (flakes, nix command)
          experimental-features = [ "nix-command" "flakes" ];

          # Optimize store to save disk space
          auto-optimise-store = lib.mkDefault true;

          # Trust admin group for binary cache operations
          trusted-users = [ "root" "@admin" ];

          # Suppress warnings about dirty git trees
          warn-dirty = false;

          # Increase download buffer for large fetches
          download-buffer-size = lib.mkDefault 134217728; # 128 MB
        };

        # Automatic garbage collection with sensible defaults
        gc = {
          automatic = lib.mkDefault true;
          interval = lib.mkDefault { Weekday = 0; Hour = 3; Minute = 0; }; # Sunday 3 AM
          options = lib.mkDefault "--delete-older-than 30d";
        };
      };

      # Binary cache configuration for faster builds
      nix.settings = {
        substituters = lib.mkDefault [
          "https://cache.nixos.org/"
          "https://nix-community.cachix.org"
        ];
        trusted-public-keys = lib.mkDefault [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
        # Cache narinfo for 24 hours
        narinfo-cache-positive-ttl = lib.mkDefault 86400;
        connect-timeout = lib.mkDefault 10;
      };

      # Minimal system packages - just enough to bootstrap
      environment.systemPackages = with pkgs; [
        vim # Basic editor for emergency recovery
        git # Required for flake operations
      ];

      # Darwin uses nix-darwin's stateVersion
      # Note: Darwin stateVersion format differs from NixOS
      system.stateVersion = lib.mkDefault 4; # nix-darwin state version
    };
  };
}
