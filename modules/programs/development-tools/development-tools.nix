# modules/programs/development-tools/development-tools.nix
# Development toolchains and build tools for home-manager [nd]
#
# Provides:
#   flake.modules.homeManager.development-tools - Language toolchains and build tools
#
# Features:
#   - Rust toolchain (rustc, cargo, rust-analyzer, clippy, rustfmt)
#   - Node.js ecosystem (nodejs, yarn, npm)
#   - Python with common packages (includes pyenv, pymupdf4llm)
#   - Go environment setup (GOPATH, bin paths)
#   - C/C++ build tools (cmake, gcc, make, binutils)
#   - Kubernetes tools (kubectl, k9s)
#   - Build utilities (flex, bison, gperf)
#   - Enhanced CLI tools (bat, eza, delta, bottom, miller)
#   - Claude development utilities (claudevloop, restart_claude, etc.)
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
#     enableEnhancedCli = true;
#     enableClaudeUtils = true;
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
            default = [ "ipython" "pip" "setuptools" "pyserial" "cryptography" "pyparsing" "pymupdf4llm" ];
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
          # Enhanced CLI Tools
          # ─────────────────────────────────────────────────────────────────────

          enableEnhancedCli = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable enhanced CLI tools (bat, eza, delta, bottom, miller)";
          };

          # ─────────────────────────────────────────────────────────────────────
          # Claude Development Utilities
          # ─────────────────────────────────────────────────────────────────────

          enableClaudeUtils = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Claude Code development utilities (claudevloop, restart_claude, etc.)";
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
          # Enhanced CLI Tools
          # ─────────────────────────────────────────────────────────────────────
          (lib.mkIf cfg.enableEnhancedCli {
            home.packages = with pkgs; [
              bat # Better cat with syntax highlighting
              eza # Modern ls replacement (formerly exa)
              delta # Better git diff
              bottom # System monitoring (btm)
              miller # Command-line CSV/TSV/JSON processor
            ];
          })

          # ─────────────────────────────────────────────────────────────────────
          # Claude Development Utilities
          # ─────────────────────────────────────────────────────────────────────
          (lib.mkIf cfg.enableClaudeUtils {
            home.packages = with pkgs; [
              # PDF to Markdown converter CLI using pymupdf4llm with parallel processing
              (pkgs.writers.writePython3Bin "pdf2md"
                { libraries = [ pkgs.python3Packages.pymupdf4llm ]; }
                (builtins.readFile (../../.. + "/modules/programs/files [nd]/files/bin/pdf2md.py"))
              )

              # Claude development workflow scripts
              (pkgs.writeShellApplication {
                name = "claudevloop";
                text = builtins.readFile (../../.. + "/modules/programs/files [nd]/files/bin/claudevloop");
                runtimeInputs = with pkgs; [ neovim ];
              })

              (pkgs.writeShellApplication {
                name = "restart_claude";
                text = builtins.readFile (../../.. + "/modules/programs/files [nd]/files/bin/restart_claude");
                runtimeInputs = with pkgs; [ jq findutils coreutils ];
              })

              (pkgs.writeShellApplication {
                name = "mkclaude_desktop_config";
                text = builtins.readFile (../../.. + "/modules/programs/files [nd]/files/bin/mkclaude_desktop_config");
                runtimeInputs = with pkgs; [ jq coreutils ];
              })

              # Show Claude Code model mappings for current session
              (pkgs.writeShellApplication {
                name = "claude-models";
                text = ''
                  # Display current Claude Code model mappings

                  echo "Claude Code Model Mappings"
                  echo "=========================="
                  echo ""

                  # Check if we're in a Claude session by looking for the model env vars
                  if [[ -z "''${ANTHROPIC_DEFAULT_OPUS_MODEL:-}" ]] && \
                     [[ -z "''${ANTHROPIC_DEFAULT_SONNET_MODEL:-}" ]] && \
                     [[ -z "''${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}" ]]; then
                    echo "No model mappings found in environment."
                    echo "This command should be run from within a Claude Code session."
                    echo ""
                    echo "Launch Claude Code with one of these wrappers:"
                    echo "  - claudemax   (Anthropic Max account)"
                    echo "  - claudepro   (Anthropic Pro account)"
                    echo "  - claudework  (PAC Code-Companion)"
                    exit 1
                  fi

                  # Show API base URL if set
                  if [[ -n "''${ANTHROPIC_BASE_URL:-}" ]]; then
                    echo "API Base URL: ''${ANTHROPIC_BASE_URL}"
                    echo ""
                  fi

                  # Display model mappings
                  echo "Model Alias Mappings:"
                  echo "--------------------"

                  if [[ -n "''${ANTHROPIC_DEFAULT_OPUS_MODEL:-}" ]]; then
                    echo "  opus   -> ''${ANTHROPIC_DEFAULT_OPUS_MODEL}"
                  fi

                  if [[ -n "''${ANTHROPIC_DEFAULT_SONNET_MODEL:-}" ]]; then
                    echo "  sonnet -> ''${ANTHROPIC_DEFAULT_SONNET_MODEL}"
                  fi

                  if [[ -n "''${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}" ]]; then
                    echo "  haiku  -> ''${ANTHROPIC_DEFAULT_HAIKU_MODEL}"
                  fi

                  echo ""
                  echo "Usage:"
                  echo "  /model opus   - Switch to opus model"
                  echo "  /model sonnet - Switch to sonnet model"
                  echo "  /model haiku  - Switch to haiku model"
                  echo ""
                  echo "Or use full model names directly:"
                  echo "  --model <full-model-name>"
                '';
                runtimeInputs = with pkgs; [ coreutils ];
              })
            ];
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
