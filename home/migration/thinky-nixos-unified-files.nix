# Migration configuration for thinky-nixos using unified files module
# This replaces the current files module with the new hybrid autoWriter + enhanced libraries
{ config, lib, pkgs, mkUnifiedFile, mkUnifiedLibrary, mkClaudeWrapper, ... }:

{
  homeFiles = {
    enable = true;
    enableTesting = true;
    enableCompletions = true;

    # Start with essential scripts that exist
    scripts = {
      # Essential utility scripts - using autoWriter directly
      mytree = mkUnifiedFile {
        name = "mytree";
        source = ../files/bin/mytree.sh;
        executable = true;
      };

      stress = mkUnifiedFile {
        name = "stress";
        source = ../files/bin/stress.sh;
        executable = true;
      };

      syncfork = mkUnifiedFile {
        name = "syncfork";
        source = ../files/bin/syncfork.sh;
        executable = true;
      };

      # Background detection utility
      is-terminal-background-light-or-dark = mkUnifiedFile {
        name = "is-terminal-background-light-or-dark";
        source = ../files/bin/is_terminal_background_light_or_dark.sh;
        executable = true;
      };

      # Claude wrapper for thinky-nixos (with max account)
      claude-max = mkClaudeWrapper {
        account = "max";
        displayName = "Claude Code (Anthropic MAX)";
        configDir = "$HOME/.config/claude-code";
        extraEnvVars = {
          CLAUDE_ACCOUNT_TYPE = "max";
          CLAUDE_CONFIG_DIR = "$HOME/.config/claude-code";
        };
      };
    };

    # Start with basic libraries
    libraries = {
      # Create simple terminal utils library
      terminalUtils = mkUnifiedLibrary {
        name = "terminalUtils";
        content = ''
          # Terminal utility functions
          
          # Check if we have a TTY
          is_tty() {
            [ -t 1 ]
          }
          
          # Basic output functions
          info() {
            echo "INFO: $*" >&2
          }
          
          warn() {
            echo "WARN: $*" >&2
          }
          
          error() {
            echo "ERROR: $*" >&2
          }
        '';
      };
    };

    # Static files for direct copying
    staticFiles = {
      # Note: yazi config removed due to conflict with legacy files module
    };
  };
}
