# Shell utilities and libraries module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;
in
{
  config = mkIf cfg.enableShellUtils {
    # Shell utilities - executable shell applications
    home.packages = with pkgs; [
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
    ];

    # Shell libraries - place as files for sourcing
    home.file = {
      ".local/lib/claude-utils.bash".source = pkgs.writeText "claude-utils.bash" (builtins.readFile ../files/lib/claude-utils.bash);
      ".local/lib/color-utils.bash".source = pkgs.writeText "color-utils.bash" (builtins.readFile ../files/lib/color-utils.bash);
      ".local/lib/datetime-utils.bash".source = pkgs.writeText "datetime-utils.bash" (builtins.readFile ../files/lib/datetime-utils.bash);
      ".local/lib/fs-utils.bash".source = pkgs.writeText "fs-utils.bash" (builtins.readFile ../files/lib/fs-utils.bash);
      ".local/lib/general-utils.bash".source = pkgs.writeText "general-utils.bash" (builtins.readFile ../files/lib/general-utils.bash);
      ".local/lib/git-utils.bash".source = pkgs.writeText "git-utils.bash" (builtins.readFile ../files/lib/git-utils.bash);
      ".local/lib/path-utils.bash".source = pkgs.writeText "path-utils.bash" (builtins.readFile ../files/lib/path-utils.bash);
      ".local/lib/profiling-utils.bash".source = pkgs.writeText "profiling-utils.bash" (builtins.readFile ../files/lib/profiling-utils.bash);
      ".local/lib/terminal-utils.bash".source = pkgs.writeText "terminal-utils.bash" (builtins.readFile ../files/lib/terminal-utils.bash);
    };
  };
}
