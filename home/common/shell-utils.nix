# Shell utilities and libraries module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;
in
{
  config = mkIf cfg.enableShellUtils {
    # Shell utilities and library packages
    home.packages = with pkgs; [
      # Utility scripts - executable shell applications
      (pkgs.writeShellApplication {
        name = "mytree";
        text = builtins.readFile ../files/bin/mytree.sh;
        runtimeInputs = with pkgs; [ coreutils tree ];
      })

      (pkgs.writeShellApplication {
        name = "colorfuncs";
        text = builtins.readFile ../files/bin/colorfuncs.sh;
        runtimeInputs = with pkgs; [ coreutils ];
      })

      # Shell libraries - non-executable text files for sourcing
      (pkgs.writeText "claude-utils.bash" (builtins.readFile ../files/lib/claude-utils.bash))
      (pkgs.writeText "color-utils.bash" (builtins.readFile ../files/lib/color-utils.bash))
      (pkgs.writeText "datetime-utils.bash" (builtins.readFile ../files/lib/datetime-utils.bash))
      (pkgs.writeText "fs-utils.bash" (builtins.readFile ../files/lib/fs-utils.bash))
      (pkgs.writeText "general-utils.bash" (builtins.readFile ../files/lib/general-utils.bash))
      (pkgs.writeText "git-utils.bash" (builtins.readFile ../files/lib/git-utils.bash))
      (pkgs.writeText "path-utils.bash" (builtins.readFile ../files/lib/path-utils.bash))
      (pkgs.writeText "profiling-utils.bash" (builtins.readFile ../files/lib/profiling-utils.bash))
      (pkgs.writeText "terminal-utils.bash" (builtins.readFile ../files/lib/terminal-utils.bash))
    ];
  };
}
