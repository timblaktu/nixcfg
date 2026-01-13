# flake-modules/termux-outputs.nix
# Generate Termux wrapper scripts for Claude Code accounts
#
# Produces portable shell scripts that can be copied to Termux without requiring
# Nix on the device. The scripts set up environment variables for each account
# (API proxy, authentication, model mappings) before launching Claude Code.
#
# Build: nix build .#termux-claude-scripts
# The result contains:
#   - bin/claudemax, bin/claudepro, bin/claudework - Account wrappers
#   - bin/install-termux-claude - Installer script for Termux
#
# Installation on Termux:
#   1. Copy the result to Termux (via adb, scp, or shared storage)
#   2. Run: ./install-termux-claude ~/bin
#   3. For bearer auth accounts, store token at: ~/.secrets/claude-<account>-token
#
# NOTE: We use the host system's pkgs (not aarch64-linux) because these are pure
# text scripts that don't need cross-compilation. The scripts are portable and
# will run on any system with bash.

{ inputs, self, withSystem, ... }: {
  flake = {
    # Build on host system - these are pure text scripts, no cross-compilation needed
    packages.x86_64-linux.termux-claude-scripts = withSystem "x86_64-linux" ({ pkgs, ... }:
      let
        lib = pkgs.lib;

        # Import shared Claude Code library
        # Note: We pass a minimal config since Termux scripts don't need home-manager features
        claudeLib = import ../home/modules/claude-code/lib.nix {
          inherit lib pkgs;
          config = { }; # Minimal config for Termux (no home-manager)
        };

        # Account definitions matching base.nix
        # These are duplicated here because we can't easily access home-manager
        # configuration from a standalone package build
        accounts = {
          max = {
            enable = true;
            displayName = "Claude Max Account";
            api = { };
            extraEnvVars = {
              DISABLE_TELEMETRY = "1";
              CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
              DISABLE_ERROR_REPORTING = "1";
            };
          };
          pro = {
            enable = true;
            displayName = "Claude Pro Account";
            api = { };
            extraEnvVars = {
              DISABLE_TELEMETRY = "1";
              CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
              DISABLE_ERROR_REPORTING = "1";
            };
          };
          work = {
            enable = true;
            displayName = "Work Code-Companion";
            api = {
              baseUrl = "https://codecompanionv2.d-dp.nextcloud.aero";
              authMethod = "bearer";
              disableApiKey = true;
              modelMappings = {
                sonnet = "devstral";
                opus = "devstral";
                haiku = "qwen-a3b";
              };
            };
            extraEnvVars = {
              DISABLE_TELEMETRY = "1";
              CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
              DISABLE_ERROR_REPORTING = "1";
            };
          };
        };

        # Filter to enabled accounts only
        enabledAccounts = lib.filterAttrs (n: a: a.enable) accounts;

        # Generate Termux wrapper for each enabled account
        # Use writeTextFile instead of writeShellScriptBin to preserve Termux shebang
        mkTermuxWrapper = name: account: pkgs.writeTextFile {
          name = "claude${name}";
          executable = true;
          destination = "/bin/claude${name}";
          text = claudeLib.mkTermuxWrapperScript {
            inherit (account) displayName;
            account = name;
            api = account.api or { };
            extraEnvVars = account.extraEnvVars or { };
          };
        };

        wrapperScripts = lib.mapAttrs mkTermuxWrapper enabledAccounts;

        # Install script for Termux - use writeTextFile to preserve Termux shebang
        installScript = pkgs.writeTextFile {
          name = "install-termux-claude";
          executable = true;
          destination = "/bin/install-termux-claude";
          text = ''
            #!/data/data/com.termux/files/usr/bin/bash
            set -euo pipefail

            INSTALL_DIR="''${1:-$HOME/bin}"
            mkdir -p "$INSTALL_DIR"

            echo "Installing Claude Code account wrappers to $INSTALL_DIR..."
            echo ""

            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: script: ''
            cp "${script}/bin/claude${name}" "$INSTALL_DIR/"
            chmod +x "$INSTALL_DIR/claude${name}"
            echo "  Installed: claude${name}"
            '') wrapperScripts)}

            echo ""
            echo "Installation complete!"
            echo ""
            echo "Usage:"
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: account: ''
            echo "  claude${name} - ${account.displayName}"
            '') enabledAccounts)}
            echo ""
            echo "For accounts using bearer auth (e.g., work), store token at:"
            echo "  mkdir -p ~/.secrets && chmod 700 ~/.secrets"
            echo "  echo 'your-token' > ~/.secrets/claude-<account>-token"
            echo "  chmod 600 ~/.secrets/claude-<account>-token"
            echo ""
            echo "Make sure $INSTALL_DIR is in your PATH:"
            echo "  export PATH=\"\$HOME/bin:\$PATH\""
          '';
        };

      in
      pkgs.symlinkJoin {
        name = "termux-claude-scripts";
        paths = (lib.attrValues wrapperScripts) ++ [ installScript ];
        meta = {
          description = "Claude Code wrapper scripts for Termux (portable shell scripts)";
          # These are pure text scripts - buildable on any platform, runnable on Termux
          platforms = lib.platforms.all;
        };
      }
    );

    # Alias for convenience - same package works for any host
    packages.aarch64-linux.termux-claude-scripts =
      self.packages.x86_64-linux.termux-claude-scripts;
  };
}
