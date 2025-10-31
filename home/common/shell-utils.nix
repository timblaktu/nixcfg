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

      # Visual watch - like watch but shows history without clearing screen
      (pkgs.writeShellApplication {
        name = "vwatch";
        text = builtins.readFile ../files/bin/vwatch;
        runtimeInputs = with pkgs; [ coreutils ];
      })

      # Help format template for shell completion
      (pkgs.writeShellApplication {
        name = "help-format-template";
        text = builtins.readFile ../files/bin/help-format-template.sh;
        runtimeInputs = with pkgs; [ coreutils ];
      })

      # SoundCloud downloader with token persistence
      (pkgs.writeShellApplication {
        name = "soundcloud-dl";
        text = builtins.readFile ../files/bin/soundcloud-dl;
        runtimeInputs = with pkgs; [ yt-dlp coreutils ];
      })

      # Stress testing convenience wrapper
      (pkgs.writeShellApplication {
        name = "stress-wrapper";
        text = builtins.readFile ../files/bin/stress.sh;
        runtimeInputs = with pkgs; [ stress-ng coreutils ];
      })

      # WiFi analysis utilities (temporarily disabled due to possible dependency issues)
      # (pkgs.writeShellApplication {
      #   name = "wifi-test-comparison";
      #   text = builtins.readFile ../files/bin/wifi-test-comparison;
      #   runtimeInputs = with pkgs; [ coreutils openssh ];
      # })

      # (pkgs.writeShellApplication {
      #   name = "remote-wifi-analyzer";
      #   text = builtins.readFile ../files/bin/remote-wifi-analyzer;
      #   runtimeInputs = with pkgs; [ coreutils openssh ];
      # })
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
