# modules/programs/terminal/terminal.nix
# Terminal configuration and font setup tools [nd]
#
# Provides:
#   flake.modules.homeManager.terminal - Terminal font and rendering utilities
#
# Features:
#   - setup-terminal-fonts: Configure terminal fonts
#   - check-terminal-setup: Verify terminal configuration
#   - diagnose-emoji-rendering: Debug emoji display issues
#   - is_terminal_background_light_or_dark: Detect terminal theme
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.terminal ];
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager Module ===
    homeManager.terminal = { config, lib, pkgs, ... }:
      {
        # Terminal utilities are always enabled when this module is imported
        home.packages = with pkgs; [
          # Terminal font setup and verification scripts
          (pkgs.writeShellApplication {
            name = "setup-terminal-fonts";
            text = builtins.readFile ../../../home/files/bin/setup-terminal-fonts;
            runtimeInputs = with pkgs; [ jq coreutils util-linux ];
          })

          (pkgs.writeShellApplication {
            name = "check-terminal-setup";
            text = builtins.readFile ../../../home/files/bin/check-terminal-setup;
            runtimeInputs = with pkgs; [ jq coreutils ];
          })

          (pkgs.writeShellApplication {
            name = "diagnose-emoji-rendering";
            text = builtins.readFile ../../../home/files/bin/diagnose-emoji-rendering;
            runtimeInputs = with pkgs; [ xxd coreutils util-linux ];
          })

          (pkgs.writeShellApplication {
            name = "is_terminal_background_light_or_dark";
            text = builtins.readFile ../../../home/files/bin/is_terminal_background_light_or_dark.sh;
            runtimeInputs = with pkgs; [ coreutils util-linux ];
          })
        ];
      };
  };
}
