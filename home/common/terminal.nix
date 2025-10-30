# Terminal configuration and tools module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;
in
{
  config = mkIf cfg.enableTerminal {
    # Terminal-specific packages and utilities
    home.packages = with pkgs; [
      # Terminal font setup and verification scripts
      (pkgs.writeShellApplication {
        name = "setup-terminal-fonts";
        text = builtins.readFile ../files/bin/setup-terminal-fonts;
        runtimeInputs = with pkgs; [ jq coreutils util-linux ];
      })

      (pkgs.writeShellApplication {
        name = "check-terminal-setup";
        text = builtins.readFile ../files/bin/check-terminal-setup;
        runtimeInputs = with pkgs; [ jq coreutils ];
      })

      (pkgs.writeShellApplication {
        name = "diagnose-emoji-rendering";
        text = builtins.readFile ../files/bin/diagnose-emoji-rendering;
        runtimeInputs = with pkgs; [ xxd coreutils util-linux ];
      })

      (pkgs.writeShellApplication {
        name = "is_terminal_background_light_or_dark";
        text = builtins.readFile ../files/bin/is_terminal_background_light_or_dark.sh;
        runtimeInputs = with pkgs; [ coreutils util-linux ];
      })
    ];
  };
}
