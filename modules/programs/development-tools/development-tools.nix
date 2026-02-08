# modules/programs/development-tools/development-tools.nix
# Development toolchains and build tools for home-manager [nd]
#
# Provides:
#   flake.modules.homeManager.development-tools - Language toolchains and build tools
#
# Features:
#   - Rust toolchain (rustc, cargo, rust-analyzer, clippy, rustfmt)
#   - Node.js ecosystem (nodejs, yarn, npm)
#   - Python with common packages
#   - C/C++ build tools (cmake, gcc, make, binutils)
#   - Kubernetes tools (kubectl, k9s)
#   - Build utilities (flex, bison, gperf)
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.development-tools ];
#   developmentTools = {
#     enable = true;
#     enableRust = true;
#     enableNode = true;
#     enablePython = true;
#   };
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager Module ===
    homeManager.development-tools = { config, lib, pkgs, ... }:
      let
        cfg = config.developmentTools;
      in
      {
        options.developmentTools = {
          enable = lib.mkEnableOption "development toolchains and build tools";

          # ─────────────────────────────────────────────────────────────────────
          # Language Toolchains
          # ─────────────────────────────────────────────────────────────────────

          enableRust = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Rust toolchain (rustc, cargo, rust-analyzer, clippy, rustfmt)";
          };

          enableNode = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Node.js ecosystem (nodejs, yarn)";
          };

          nodeVersion = lib.mkOption {
            type = lib.types.enum [ "lts" "current" ];
            default = "lts";
            description = "Node.js version to install (lts = 22.x, current = latest)";
          };

          enablePython = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Python with common development packages";
          };

          pythonPackages = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "ipython" "pip" "setuptools" "pyserial" "cryptography" "pyparsing" ];
            description = "Python packages to include";
            example = [ "ipython" "pip" "setuptools" "requests" "numpy" ];
          };

          # ─────────────────────────────────────────────────────────────────────
          # Build Tools
          # ─────────────────────────────────────────────────────────────────────

          enableCppTools = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable C/C++ build tools (cmake, gcc, make, binutils)";
          };

          enableBuildUtils = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable build utilities (flex, bison, gperf, doxygen, entr)";
          };

          # ─────────────────────────────────────────────────────────────────────
          # Kubernetes Tools
          # ─────────────────────────────────────────────────────────────────────

          enableKubernetes = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Kubernetes tools (kubectl, k9s)";
          };

          # ─────────────────────────────────────────────────────────────────────
          # Additional Packages
          # ─────────────────────────────────────────────────────────────────────

          additionalPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Additional development packages to install";
          };
        };

        config = lib.mkIf cfg.enable (lib.mkMerge [
          # ─────────────────────────────────────────────────────────────────────
          # Rust Toolchain
          # ─────────────────────────────────────────────────────────────────────
          (lib.mkIf cfg.enableRust {
            home.packages = with pkgs; [
              rustc
              cargo
              rust-analyzer
              rustfmt
              clippy
            ];
          })

          # ─────────────────────────────────────────────────────────────────────
          # Node.js Ecosystem
          # ─────────────────────────────────────────────────────────────────────
          (lib.mkIf cfg.enableNode {
            home.packages = with pkgs; [
              (if cfg.nodeVersion == "lts" then nodejs_22 else nodejs)
              yarn
            ];
          })

          # ─────────────────────────────────────────────────────────────────────
          # Python
          # ─────────────────────────────────────────────────────────────────────
          (lib.mkIf cfg.enablePython {
            home.packages = [
              (pkgs.python3.withPackages (ps:
                builtins.map (name: ps.${name}) cfg.pythonPackages
              ))
            ];
          })

          # ─────────────────────────────────────────────────────────────────────
          # C/C++ Build Tools
          # ─────────────────────────────────────────────────────────────────────
          (lib.mkIf cfg.enableCppTools {
            home.packages = with pkgs; [
              cmake
              gcc
              gnumake
              binutils
              pkg-config
              # Common build dependencies
              libffi
              openssl
              openssl.dev
              ncurses
              cacert
            ];
          })

          # ─────────────────────────────────────────────────────────────────────
          # Build Utilities
          # ─────────────────────────────────────────────────────────────────────
          (lib.mkIf cfg.enableBuildUtils {
            home.packages = with pkgs; [
              flex
              bison
              gperf
              doxygen
              entr # Run commands when files change
              nix-prefetch-github
              psmisc # killall, fuser, etc.
            ];
          })

          # ─────────────────────────────────────────────────────────────────────
          # Kubernetes Tools
          # ─────────────────────────────────────────────────────────────────────
          (lib.mkIf cfg.enableKubernetes {
            home.packages = with pkgs; [
              kubectl
              k9s
            ];
          })

          # ─────────────────────────────────────────────────────────────────────
          # Additional Packages
          # ─────────────────────────────────────────────────────────────────────
          {
            home.packages = cfg.additionalPackages;
          }
        ]);
      };
  };
}
