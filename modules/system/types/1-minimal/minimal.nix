# modules/system/types/1-minimal/minimal.nix
# Minimal system configuration layer [NDnd]
#
# Provides:
#   flake.modules.nixos.system-minimal - Absolute minimum NixOS configuration
#   flake.modules.darwin.system-minimal - Absolute minimum Darwin configuration
#   flake.modules.homeManager.home-minimal - Absolute minimum Home Manager configuration
#
# This is the base layer that ALL systems inherit from. It contains:
#   - Nix flakes and experimental features
#   - Store optimization
#   - Garbage collection
#   - Trusted users (wheel group)
#   - State version handling
#   - Performance settings (max-jobs, cores)
#   - Binary cache configuration
#
# Does NOT include:
#   - User creation (2-default)
#   - Home Manager integration (2-default)
#   - SSH, networking (3-cli)
#   - Desktop environments (4-desktop)
#
# Usage in host config:
#   imports = [ inputs.self.modules.nixos.system-minimal ];
#   systemMinimal.nixMaxJobs = 8;
#
# Or compose with higher layers:
#   imports = [ inputs.self.modules.nixos.system-cli ];  # inherits minimal -> default -> cli
{ config, lib, pkgs, inputs, ... }:
{
  flake.modules = {
    # === NixOS Minimal Module ===
    nixos.system-minimal = { config, lib, pkgs, ... }:
      let
        cfg = config.systemMinimal;
      in
      {
        options.systemMinimal = {
          # Nix performance settings
          nixMaxJobs = lib.mkOption {
            type = lib.types.int;
            default = 8;
            description = "Maximum number of parallel build jobs (nix.settings.max-jobs)";
          };

          nixCores = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = "Number of cores per build job (0 = all available)";
          };

          # Binary cache settings
          enableBinaryCache = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable community binary caches for faster builds";
          };

          cacheTimeout = lib.mkOption {
            type = lib.types.int;
            default = 10;
            description = "Connection timeout for cache in seconds";
          };

          # Garbage collection settings
          gcDates = lib.mkOption {
            type = lib.types.str;
            default = "weekly";
            description = "When to run automatic garbage collection";
          };

          gcOptions = lib.mkOption {
            type = lib.types.str;
            default = "--delete-older-than 30d";
            description = "Options for garbage collection";
          };
        };

        config = {
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

              # Performance settings
              max-jobs = lib.mkDefault cfg.nixMaxJobs;
              cores = lib.mkDefault cfg.nixCores;
            } // (lib.optionalAttrs cfg.enableBinaryCache {
              # Binary cache configuration
              substituters = [
                "https://cache.nixos.org/"
                "https://nix-community.cachix.org"
              ];
              trusted-public-keys = [
                "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
                "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
              ];
              # Cache narinfo for 24 hours
              narinfo-cache-positive-ttl = 86400;
              connect-timeout = cfg.cacheTimeout;
            });

            # Automatic garbage collection
            gc = {
              automatic = lib.mkDefault true;
              dates = lib.mkDefault cfg.gcDates;
              options = lib.mkDefault cfg.gcOptions;
            };
          };

          # Minimal system packages - just enough to bootstrap
          # nano is included by NixOS defaults; neovim is added at the cli layer
          environment.systemPackages = with pkgs; [
            git # Required for flake operations
          ];

          # Disable documentation outputs to reduce closure size.
          # Saves ~77 MiB: nixos-manual-html (27), nix-manual + /share/doc (36), texinfo (14).
          # Man pages (documentation.man.enable) are kept — those are actually useful.
          # Hosts can override with lib.mkForce true if needed.
          documentation.nixos.enable = lib.mkDefault false;
          documentation.doc.enable = lib.mkDefault false;
          documentation.info.enable = lib.mkDefault false;

          # Pin nix registry to GitHub ref instead of storing nixpkgs source in closure.
          # Saves ~186 MiB. Ad-hoc commands (nix run nixpkgs#foo) require a one-time
          # ~30 MB fetch instead of resolving instantly; flake-based workflows are unaffected.
          nix.registry.nixpkgs.to = {
            type = "github";
            owner = "NixOS";
            repo = "nixpkgs";
            rev = inputs.nixpkgs.rev;
          };

          # System state version - should be overridden by host
          # Default to current stable; hosts should pin their version
          system.stateVersion = lib.mkDefault "24.11";
        };
      };

    # === Darwin Minimal Module ===
    darwin.system-minimal = { config, lib, pkgs, ... }:
      let
        cfg = config.systemMinimal;
      in
      {
        options.systemMinimal = {
          # Nix performance settings
          nixMaxJobs = lib.mkOption {
            type = lib.types.int;
            default = 8;
            description = "Maximum number of parallel build jobs (nix.settings.max-jobs)";
          };

          nixCores = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = "Number of cores per build job (0 = all available)";
          };

          # Binary cache settings
          enableBinaryCache = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable community binary caches for faster builds";
          };

          cacheTimeout = lib.mkOption {
            type = lib.types.int;
            default = 10;
            description = "Connection timeout for cache in seconds";
          };

          # Garbage collection settings (Darwin uses interval, not dates)
          gcInterval = lib.mkOption {
            type = lib.types.attrs;
            default = { Weekday = 0; Hour = 3; Minute = 0; }; # Sunday 3 AM
            description = "When to run automatic garbage collection (launchd interval)";
          };

          gcOptions = lib.mkOption {
            type = lib.types.str;
            default = "--delete-older-than 30d";
            description = "Options for garbage collection";
          };
        };

        config = {
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

              # Performance settings
              max-jobs = lib.mkDefault cfg.nixMaxJobs;
              cores = lib.mkDefault cfg.nixCores;
            } // (lib.optionalAttrs cfg.enableBinaryCache {
              # Binary cache configuration
              substituters = [
                "https://cache.nixos.org/"
                "https://nix-community.cachix.org"
              ];
              trusted-public-keys = [
                "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
                "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
              ];
              # Cache narinfo for 24 hours
              narinfo-cache-positive-ttl = 86400;
              connect-timeout = cfg.cacheTimeout;
            });

            # Automatic garbage collection
            gc = {
              automatic = lib.mkDefault true;
              interval = lib.mkDefault cfg.gcInterval;
              options = lib.mkDefault cfg.gcOptions;
            };
          };

          # Minimal system packages - just enough to bootstrap
          environment.systemPackages = with pkgs; [
            git # Required for flake operations
          ];

          # Darwin uses nix-darwin's stateVersion
          # Note: Darwin stateVersion format differs from NixOS
          system.stateVersion = lib.mkDefault 4; # nix-darwin state version
        };
      };

    # === Home Manager Minimal Module ===
    homeManager.home-minimal = { config, lib, pkgs, ... }:
      let
        cfg = config.homeMinimal;
      in
      {
        options.homeMinimal = {
          # User identity (required)
          username = lib.mkOption {
            type = lib.types.str;
            description = "Username for Home Manager (required)";
            example = "tim";
          };

          homeDirectory = lib.mkOption {
            type = lib.types.str;
            description = "Home directory path (required)";
            example = "/home/tim";
          };

          # State version
          stateVersion = lib.mkOption {
            type = lib.types.str;
            default = "24.11";
            description = "Home Manager state version";
          };

          # Nix settings
          nixMaxJobs = lib.mkOption {
            type = lib.types.int;
            default = 2;
            description = "Maximum parallel nix jobs";
          };
        };

        config = {
          # Assertions
          assertions = [
            {
              assertion = cfg.username != "";
              message = "homeMinimal.username must be set";
            }
            {
              assertion = cfg.homeDirectory != "";
              message = "homeMinimal.homeDirectory must be set";
            }
          ];

          # Core Home Manager identity
          home = {
            inherit (cfg) username;
            inherit (cfg) homeDirectory;
            inherit (cfg) stateVersion;

            # Add ~/bin to PATH
            sessionPath = [ "$HOME/bin" ];
          };

          # Let Home Manager manage itself
          programs.home-manager.enable = true;

          # Disable version mismatch warnings (using HM master with nixos-unstable)
          home.enableNixpkgsReleaseCheck = false;

          # Enable standalone mode support (Linux only)
          targets.genericLinux.enable = lib.mkDefault pkgs.stdenv.isLinux;

          # Nix configuration
          nix = {
            package = lib.mkDefault pkgs.nix;
            settings = {
              max-jobs = lib.mkDefault cfg.nixMaxJobs;
              warn-dirty = false;
              experimental-features = [ "nix-command" "flakes" ];
            };
          };
        };
      };
  };
}
