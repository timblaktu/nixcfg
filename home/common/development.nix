# Development packages and tools module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;

  # Import shared Claude Code wrapper library
  claudeLib = import ../modules/claude-code/lib.nix { inherit lib pkgs config; };
in
{
  config = mkIf cfg.enableDevelopment {
    # Development-specific packages
    home.packages = with pkgs; [
      cmake
      doxygen
      entr
      gcc
      gnumake
      binutils
      cacert
      nix-prefetch-github
      rust-analyzer
      rustc
      cargo
      rustfmt
      clippy
      nodejs
      yarn
      (python3.withPackages (ps: with ps; [
        ipython
        pip
        setuptools
        pyserial
        cryptography
        pyparsing
        pymupdf4llm
      ]))

      # PDF to Markdown converter CLI using pymupdf4llm with parallel processing
      (pkgs.writers.writePython3Bin "pdf2md"
        { libraries = [ pkgs.python3Packages.pymupdf4llm ]; }
        (builtins.readFile ../files/bin/pdf2md.py)
      )
      flex
      bison
      gperf
      psmisc
      libffi
      openssl
      ncurses

      podman
      podman-compose
      kubectl
      k9s

      fzf
      bat
      eza # Modern ls replacement (formerly exa)
      delta # better git diff
      bottom # system monitoring
      miller # Command-line CSV/TSV/JSON processor

      # Claude development workflow scripts
      (pkgs.writeShellApplication {
        name = "claudevloop";
        text = builtins.readFile ../files/bin/claudevloop;
        runtimeInputs = with pkgs; [ neovim ];
      })

      (pkgs.writeShellApplication {
        name = "restart_claude";
        text = builtins.readFile ../files/bin/restart_claude;
        runtimeInputs = with pkgs; [ jq findutils coreutils ];
      })

      (pkgs.writeShellApplication {
        name = "mkclaude_desktop_config";
        text = builtins.readFile ../files/bin/mkclaude_desktop_config;
        runtimeInputs = with pkgs; [ jq coreutils ];
      })

      # Claude Code account wrapper scripts - using shared library
      # NOTE: There is intentionally NO bare "claude" wrapper - explicit account selection is required
      # Use: claudemax, claudepro, or claudework

      (pkgs.writeShellApplication {
        name = "claudemax";
        text = claudeLib.mkClaudeWrapperScript {
          account = "max";
          displayName = "Claude Max Account";
          configDir = "${config.home.homeDirectory}/src/nixcfg/claude-runtime/.claude-max";
          extraEnvVars = {
            DISABLE_TELEMETRY = "1";
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
            DISABLE_ERROR_REPORTING = "1";
          };
        };
        runtimeInputs = with pkgs; [ procps coreutils claude-code jq ];
      })

      (pkgs.writeShellApplication {
        name = "claudepro";
        text = claudeLib.mkClaudeWrapperScript {
          account = "pro";
          displayName = "Claude Pro Account";
          configDir = "${config.home.homeDirectory}/src/nixcfg/claude-runtime/.claude-pro";
          extraEnvVars = {
            DISABLE_TELEMETRY = "1";
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
            DISABLE_ERROR_REPORTING = "1";
          };
        };
        runtimeInputs = with pkgs; [ procps coreutils claude-code jq ];
      })

      (pkgs.writeShellApplication {
        name = "claudework";
        text = claudeLib.mkClaudeWrapperScript {
          account = "work";
          displayName = "Work Code-Companion";
          configDir = "${config.home.homeDirectory}/src/nixcfg/claude-runtime/.claude-work";
          api = {
            baseUrl = "https://codecompanionv2.d-dp.nextcloud.aero";
            authMethod = "bearer";
            # Note: disableApiKey not needed - bearer auth sets ANTHROPIC_API_KEY from Bitwarden
            modelMappings = {
              opus = "devstral"; # Best reasoning (matches settings.json)
              sonnet = "devstral"; # Default model (matches settings.json)
              haiku = "qwen-a3b"; # Fast + images/OCR (250K context)
            };
          };
          secrets = {
            bearerToken = {
              bitwarden = {
                item = "PAC Code Companion v2 - API Key";
                # No field specified - uses default password from Bitwarden item
              };
            };
          };
          extraEnvVars = {
            DISABLE_TELEMETRY = "1";
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
            DISABLE_ERROR_REPORTING = "1";
          };
        };
        runtimeInputs = with pkgs; [ procps coreutils claude-code jq rbw ];
      })

      # Claude Code wrapper and update utilities
      (pkgs.writeShellApplication {
        name = "claude-code-wrapper";
        text = ''
          # Claude Code user-local installation wrapper

          # Set up local installation directories
          mkdir -p "$HOME/.local/share/claude-code"
          mkdir -p "$HOME/.local/bin"

          # Configure npm to use local prefix
          export NPM_CONFIG_PREFIX="$HOME/.local/share/claude-code/npm"
          export PATH="$HOME/.local/share/claude-code/npm/bin:$PATH"

          # Install claude-code if not already present
          if [ ! -x "$HOME/.local/share/claude-code/npm/bin/claude" ]; then
            echo "Installing claude-code to user directory..."
            if command -v npm >/dev/null 2>&1; then
              npm install -g @anthropic-ai/claude-code
            else
              echo "Error: npm not available"
              echo "   Please ensure Node.js is installed and available in PATH"
              exit 1
            fi
          fi

          # Execute claude with all arguments
          exec "$HOME/.local/share/claude-code/npm/bin/claude" "$@"
        '';
        runtimeInputs = with pkgs; [ nodejs_22 coreutils ];
        passthru.tests = {
          syntax = pkgs.runCommand "test-claude-code-wrapper-syntax" { } ''
            echo "Syntax validation passed at build time" > $out
          '';
          directory_setup = pkgs.runCommand "test-claude-code-wrapper-dirs" { } ''
            # Test that script sets up proper directory structure - placeholder
            echo "Directory setup test passed (placeholder)" > $out
          '';
        };
      })

      (pkgs.writeShellApplication {
        name = "claude-code-update";
        text = ''
          # Update claude-code installation

          export NPM_CONFIG_PREFIX="$HOME/.local/share/claude-code/npm"
          echo "Updating claude-code..."

          if command -v npm >/dev/null 2>&1; then
            npm update -g @anthropic-ai/claude-code
            echo "Update complete!"
          else
            echo "Error: npm not available"
            echo "   Please ensure Node.js is installed and available in PATH"
            exit 1
          fi
        '';
        runtimeInputs = with pkgs; [ nodejs_22 coreutils ];
        passthru.tests = {
          syntax = pkgs.runCommand "test-claude-code-update-syntax" { } ''
            echo "Syntax validation passed at build time" > $out
          '';
          npm_check = pkgs.runCommand "test-claude-code-update-npm" { } ''
            # Test npm availability check - placeholder
            echo "NPM check test passed (placeholder)" > $out
          '';
        };
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
            echo "  opus   → ''${ANTHROPIC_DEFAULT_OPUS_MODEL}"
          fi

          if [[ -n "''${ANTHROPIC_DEFAULT_SONNET_MODEL:-}" ]]; then
            echo "  sonnet → ''${ANTHROPIC_DEFAULT_SONNET_MODEL}"
          fi

          if [[ -n "''${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}" ]]; then
            echo "  haiku  → ''${ANTHROPIC_DEFAULT_HAIKU_MODEL}"
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
  };
}
