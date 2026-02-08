# modules/programs/development-tools/development-tools.nix
# Development toolchains and build tools for home-manager [nd]
#
# Provides:
#   flake.modules.homeManager.development-tools - Language toolchains and build tools
#
# Features:
#   - Rust toolchain (rustc, cargo, rust-analyzer, clippy, rustfmt)
#   - Node.js ecosystem (nodejs, yarn, npm)
#   - Python with common packages (includes pyenv)
#   - Go environment setup (GOPATH, bin paths)
#   - C/C++ build tools (cmake, gcc, make, binutils)
#   - Kubernetes tools (kubectl, k9s)
#   - Build utilities (flex, bison, gperf)
#   - Development environment paths and variables
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.development-tools ];
#   developmentTools = {
#     enable = true;
#     enableRust = true;
#     enableNode = true;
#     enablePython = true;
#     enableGo = true;
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

          enablePyenv = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable pyenv for Python version management (adds PYENV_ROOT and paths)";
          };

          enableGo = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Go environment (GOPATH, go/bin paths)";
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
          # Go Environment
          # ─────────────────────────────────────────────────────────────────────
          (lib.mkIf cfg.enableGo {
            home.packages = with pkgs; [
              go
            ];

            home.sessionVariables = {
              GOPATH = "$HOME/go";
            };

            home.sessionPath = [
              "$HOME/go/bin"
              "/usr/local/go/bin"
            ];

            # Create Go directories
            home.activation.createGoDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              mkdir -p $HOME/go/{src,pkg,bin} 2>/dev/null || true
            '';
          })

          # ─────────────────────────────────────────────────────────────────────
          # Rust Environment (paths)
          # ─────────────────────────────────────────────────────────────────────
          (lib.mkIf cfg.enableRust {
            home.sessionPath = [
              "$HOME/.cargo/bin"
            ];
          })

          # ─────────────────────────────────────────────────────────────────────
          # Pyenv Environment
          # ─────────────────────────────────────────────────────────────────────
          (lib.mkIf cfg.enablePyenv {
            home.sessionVariables = {
              PYENV_ROOT = "$HOME/.pyenv";
            };

            home.sessionPath = [
              "$HOME/.pyenv/bin"
            ];

            # Pyenv shell initialization (bash/zsh)
            programs.bash.initExtra = lib.mkAfter ''
              if [[ -d $PYENV_ROOT/bin ]] && command -v pyenv >/dev/null 2>&1; then
                eval "$(pyenv init - bash)"
              fi
            '';

            programs.zsh.initContent = lib.mkAfter ''
              if [[ -d $PYENV_ROOT/bin ]] && command -v pyenv >/dev/null 2>&1; then
                eval "$(pyenv init - zsh)"
              fi
            '';
          })

          # ─────────────────────────────────────────────────────────────────────
          # Common Development Paths
          # ─────────────────────────────────────────────────────────────────────
          {
            home.sessionPath = [
              "$HOME/.local/bin"
            ];
          }

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
