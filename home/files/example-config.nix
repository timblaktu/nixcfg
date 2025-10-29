# Example configuration for the unified files module
# This demonstrates how to use the hybrid autoWriter + enhanced libraries system
{ config, lib, pkgs, mkValidatedFile, mkScriptLibrary, mkClaudeWrapper, ... }:

let
  inherit (import ./lib/script-libraries.nix { inherit lib pkgs mkScriptLibrary; })
    terminalUtils colorUtils jsonUtils;

  inherit (import ./lib/domain-generators.nix { inherit lib pkgs mkValidatedFile mkScriptLibrary; })
    mkClaudeWrapper mkTmuxHelpers mkOneDriveHelpers;

in
{
  homeFiles = {
    enable = true;
    enableTesting = true;
    enableCompletions = true;

    # Script libraries (non-executable, for sourcing)
    libraries = {
      inherit terminalUtils colorUtils jsonUtils;
    };

    # Executable scripts using autoWriter detection
    scripts = {
      # Example script demonstrating the system
      example-unified = mkValidatedFile {
        name = "example-unified-script";
        source = ./content/scripts/example-unified-script.sh;
        executable = true;
        libraries = [ "terminalUtils" "colorUtils" ];
        tests = {
          helpText = pkgs.writeShellScript "test-help" ''
            echo "📖 Testing help text..."
            ${./content/scripts/example-unified-script.sh} --help >/dev/null
            echo "✅ Help text validation passed"
          '';
          colorSupport = pkgs.writeShellScript "test-colors" ''
            echo "🎨 Testing color support..."
            ${./content/scripts/example-unified-script.sh} --colors >/dev/null
            echo "✅ Color support validation passed"
          '';
        };
      };

      # Claude wrapper demonstration
      claude-demo = mkClaudeWrapper {
        account = "demo";
        displayName = "Demo Account";
        configDir = "$HOME/.config/claude-demo";
        extraEnvVars = {
          CLAUDE_DEMO_MODE = "true";
        };
      };

      # Tmux helpers
      inherit (mkTmuxHelpers) mkSessionPicker mkAutoAttach;

      # OneDrive helpers (for WSL environments)
      inherit (mkOneDriveHelpers) mkStatusChecker mkForceSync;
    };

    # Static files for direct copying
    staticFiles = {
      yazi-config = {
        source = ./yazi-init.lua;
        target = ".config/yazi/init.lua";
        executable = false;
      };
    };
  };
}
